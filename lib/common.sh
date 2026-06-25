#!/bin/bash
# v2rayN Russia Setup — общая библиотека
# ============================================================================
# Предоставляет функции для:
#   - Скачивания с retry и экспоненциальной задержкой
#   - Структурированного логирования (INFO/WARN/ERROR) в файл + stderr
#   - Блокировок (lock-файлы) для предотвращения конкурентного запуска
#   - SHA256 верификации скачанных файлов
#   - Определения системы
#
# Использование:
#   source "$(dirname "$0")/../lib/common.sh"
# ============================================================================

# ---- Конфигурация по умолчанию ----
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "$0" .sh)}"
LOG_DIR="${LOG_DIR:-$HOME/.local/share/v2rayN/logs}"
LOCK_DIR="${LOCK_DIR:-$HOME/.local/share/v2rayN/locks}"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/v2rayN}"

# Цвета (stderr)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# ============================================================================
# 1. ЛОГГИРОВАНИЕ
# ============================================================================
# Инициализация лога
log_init() {
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/${SCRIPT_NAME}.log"

  # Ротация: если лог > 5 МБ, сдвигаем
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)" -gt 5242880 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
  fi

  exec 3>&2  # сохраняем stderr
  exec 2>>"$LOG_FILE"  # перенаправляем stderr в лог
}

log_info()  { echo -e "${GREEN}[✓]${NC} $1" >&3; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $1" >> "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1" >&3; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $1" >> "$LOG_FILE"; }
log_error() { echo -e "${RED}[✗]${NC} $1" >&3; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"; exit 1; }
log_header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}" >&3; echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HEADER] $1" >> "$LOG_FILE"; }

# Функции для обратной совместимости (скрипты, не использующие log_init)
info()  { log_info "$1"; }
warn()  { log_warn "$1"; }
error() { log_error "$1"; }
header(){ log_header "$1"; }

# ============================================================================
# 2. СКАЧИВАНИЕ С RETRY
# ============================================================================
# Скачивает файл с retry и экспоненциальной задержкой
# Возвращает 0 при успехе, 1 при неудаче после всех попыток
# Аргументы: <url> <destination> [max_retries=3] [initial_delay=2]
download_with_retry() {
  local url="$1" dest="$2"
  local max_retries="${3:-3}"
  local delay="${4:-2}"
  local attempt=0
  local tmp_dest
  tmp_dest=$(mktemp "${dest}.XXXXXX")

  while [ "$attempt" -lt "$max_retries" ]; do
    attempt=$((attempt + 1))

    if command -v curl &>/dev/null; then
      if curl -sSL --connect-timeout 20 -o "$tmp_dest" "$url" 2>>"$LOG_FILE"; then
        mv "$tmp_dest" "$dest"
        return 0
      fi
    elif command -v wget &>/dev/null; then
      if wget -q --timeout=20 -O "$tmp_dest" "$url" 2>>"$LOG_FILE"; then
        mv "$tmp_dest" "$dest"
        return 0
      fi
    else
      echo "Ни curl, ни wget не найдены" >&3
      return 1
    fi

    rm -f "$tmp_dest"

    if [ "$attempt" -lt "$max_retries" ]; then
      echo "  Попытка $attempt/$max_retries не удалась. Повтор через ${delay}с..." >&3
      sleep "$delay"
      delay=$((delay * 2))  # экспоненциальная задержка
    fi
  done

  echo "  Ошибка: не удалось скачать $url после $max_retries попыток" >&3
  return 1
}

# ============================================================================
# 3. SHA256 ВЕРИФИКАЦИЯ
# ============================================================================
# Проверяет SHA256 файла. Если checksum-файл не найден — предупреждает, но проходит.
# Аргументы: <data_file> <sha256_url>
# Возвращает: 0 — OK, 1 — не совпадает, 2 — нет checksum для проверки
verify_sha256() {
  local data_file="$1" sha_url="$2"
  local sha_file
  sha_file=$(mktemp "/tmp/$(basename "$data_file").sha256.XXXXXX")

  if ! download_with_retry "$sha_url" "$sha_file" 2 2; then
    rm -f "$sha_file"
    echo "  ⚠️  Нет SHA256 checksum для проверки (пропускаем)" >&3
    return 2
  fi

  local expected
  expected=$(cut -d' ' -f1 < "$sha_file" 2>/dev/null || echo "")
  rm -f "$sha_file"

  if [ -z "$expected" ]; then
    echo "  ⚠️  Пустой SHA256 checksum (пропускаем)" >&3
    return 2
  fi

  local actual
  actual=$(sha256sum "$data_file" 2>/dev/null | cut -d' ' -f1 || echo "")

  if [ "$expected" = "$actual" ]; then
    echo "  ✓ SHA256: OK" >&3
    return 0
  else
    echo "  ✗ SHA256: не совпадает (ожидается: $expected, получено: $actual)" >&3
    return 1
  fi
}

# ============================================================================
# 4. БЛОКИРОВКИ
# ============================================================================
# Предотвращает конкурентный запуск одного скрипта
# Аргументы: [lock_name] (по умолчанию: $SCRIPT_NAME)
# Возвращает: 0 — блокировка получена, 1 — скрипт уже запущен
acquire_lock() {
  local lock_name="${1:-$SCRIPT_NAME}"
  mkdir -p "$LOCK_DIR"
  local lock_file="$LOCK_DIR/${lock_name}.lock"

  if ! mkdir "$lock_file" 2>/dev/null; then
    local pid
    pid=$(cat "$lock_file/pid" 2>/dev/null || echo "unknown")
    echo "  ⚠️  Скрипт уже запущен (PID: $pid). Блокировка: $lock_file" >&3
    return 1
  fi

  echo "$$" > "$lock_file/pid"
  # Автоматический unlock при выходе
  # shellcheck disable=SC2064
  trap "release_lock '$lock_name'" EXIT
  return 0
}

release_lock() {
  local lock_name="${1:-$SCRIPT_NAME}"
  local lock_file="$LOCK_DIR/${lock_name}.lock"
  rm -rf "$lock_file" 2>/dev/null || true
  # Убираем trap, чтобы не вызвать повторно
  trap - EXIT
}

# ============================================================================
# 5. ПРОВЕРКА СИСТЕМЫ
# ============================================================================
# Определяет архитектуру
detect_arch() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)  echo "64" ;;
    aarch64) echo "arm64" ;;
    *)       echo "unsupported" ;;
  esac
}

# Определяет ID дистрибутива
detect_os_id() {
  grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null || echo "unknown"
}

# ============================================================================
# 6. ВСПОМОГАТЕЛЬНЫЕ
# ============================================================================
# Показывает размер файла в human-readable формате
file_size() {
  # shellcheck disable=SC2012
  ls -lh "$1" 2>/dev/null | awk '{print $5}' || echo "?"
}

# Валидация .dat файла (не пустой, не слишком маленький)
validate_dat() {
  local f="$1"
  [ -f "$f" ] && [ -s "$f" ] && [ "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null)" -gt 10240 ]
}

# Проверка root
check_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "Не запускайте скрипт от root. Используйте обычного пользователя." >&3
    exit 1
  fi
}
