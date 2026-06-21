#!/bin/bash
set -euo pipefail

# update-rules.sh — Автономное обновление geoip/geosite правил
# ============================================================================
# Особенности:
#   - Retry с экспоненциальной задержкой при сетевых ошибках
#   - SHA256 верификация скачанных файлов
#   - Блокировка конкурентного запуска
#   - Поддержка systemd timer для автоматического запуска
#   - Логирование в ~/.local/share/v2rayN/logs/update-rules.log
#   - Кэширование: если скачать не удалось — использует предыдущую версию
#
# Использование:
#   ./scripts/update-rules.sh                         # Однократное обновление
#   ./scripts/update-rules.sh --restart-v2rayn         # Обновить + рестарт v2rayN
#   ./scripts/update-rules.sh --install-timer          # Установить systemd timer
#   ./scripts/update-rules.sh --remove-timer           # Удалить systemd timer
#   ./scripts/update-rules.sh --status                 # Проверить статус
# ============================================================================

SCRIPT_NAME="update-rules"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"

# Подключаем общую библиотеку
if [ -f "$LIB_DIR/common.sh" ]; then
  # shellcheck disable=SC1091 # source file resolved at runtime
  source "$LIB_DIR/common.sh"
else
  # Fallback: минимальные функции, если lib/common.sh не найден
  info()  { echo -e "\033[0;32m[✓]\033[0m $1"; }
  warn()  { echo -e "\033[1;33m[!]\033[0m $1"; }
  error() { echo -e "\033[0;31m[✗]\033[0m $1"; exit 1; }
  download_with_retry() {
    local url="$1" dest="$2" max_retries="${3:-3}" delay="${4:-2}" i=0
    while [ "$i" -lt "$max_retries" ]; do
      i=$((i+1))
      if command -v curl &>/dev/null; then curl -sSL --connect-timeout 20 -o "$dest.tmp" "$url" && mv "$dest.tmp" "$dest" && return 0
      elif command -v wget &>/dev/null; then wget -q --timeout=20 -O "$dest.tmp" "$url" && mv "$dest.tmp" "$dest" && return 0
      fi
      [ "$i" -lt "$max_retries" ] && sleep "$delay" && delay=$((delay*2))
    done
    return 1
  }
  verify_sha256() { local f="$1" u="$2"; local e s; s=$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1); e=$(curl -sSL "$u" 2>/dev/null | cut -d' ' -f1); [ -n "$e" ] && [ "$e" = "$s" ]; }
  validate_dat() { [ -f "$1" ] && [ -s "$1" ]; }
  acquire_lock() { return 0; }
  release_lock() { return 0; }
  # shellcheck disable=SC2012
  file_size() { ls -lh "$1" 2>/dev/null | awk '{print $5}'; }
fi

# ---- Константы ----
# Основной источник и зеркала для geoip/geosite
RELEASE_URLS=(
  "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
  "https://gitlab.com/runetfreedom/russia-v2ray-rules-dat/-/raw/release"
  "https://codeberg.org/runetfreedom/russia-v2ray-rules-dat/raw/branch/release"
)

BIN_DIR="${V2RAYN_BIN_DIR:-$HOME/.local/share/v2rayN/bin}"
CACHE_DIR="$HOME/.cache/v2rayN/rules"
SYSTEMD_DIR="$HOME/.config/systemd/user"
TIMER_NAME="v2rayn-rules-update"
SERVICE_FILE="$LIB_DIR/../lib/systemd/${TIMER_NAME}.service"
TIMER_FILE="$LIB_DIR/../lib/systemd/${TIMER_NAME}.timer"

# ---- Парсинг аргументов ----
show_help() {
  cat <<'HELP'
Использование:
  ./scripts/update-rules.sh                        # Однократное обновление
  ./scripts/update-rules.sh --restart-v2rayn       # Обновить + рестарт v2rayN
  ./scripts/update-rules.sh --install-timer        # Установить systemd timer
  ./scripts/update-rules.sh --remove-timer         # Удалить systemd timer
  ./scripts/update-rules.sh --status               # Проверить статус
  ./scripts/update-rules.sh --help                 # Показать эту справку

Флаги:
  --install-timer   Установить systemd timer для еженедельного обновления
  --remove-timer    Удалить systemd timer
  --status          Показать статус timer и файлов правил
  --restart-v2rayn  Перезапустить v2rayN после обновления
  --help            Показать эту справку
HELP
  exit 0
}

ACTION="update"
RESTART_V2RAYN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)               show_help                      ;;
    --install-timer)      ACTION="install-timer"         ;;
    --remove-timer)       ACTION="remove-timer"          ;;
    --status)             ACTION="status"                ;;
    --restart-v2rayn|--restart) RESTART_V2RAYN=true      ;;
    *) echo "Неизвестный флаг: $1. Используйте --help для справки." >&2; exit 1 ;;
  esac
  shift
done

# ---- Установка/удаление systemd timer ----
install_timer() {
  log_header "Установка systemd timer"

  if [ ! -f "$SERVICE_FILE" ] || [ ! -f "$TIMER_FILE" ]; then
    log_error "Файлы systemd не найдены в $LIB_DIR/../lib/systemd/"
  fi

  mkdir -p "$SYSTEMD_DIR"
  cp -f "$SERVICE_FILE" "$SYSTEMD_DIR/${TIMER_NAME}.service"
  cp -f "$TIMER_FILE" "$SYSTEMD_DIR/${TIMER_NAME}.timer"

  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable "${TIMER_NAME}.timer" 2>/dev/null || true
  systemctl --user start "${TIMER_NAME}.timer" 2>/dev/null || true

  log_info "Systemd timer установлен: ${TIMER_NAME}.timer"
  log_info "  Расписание: еженедельно (OnCalendar=weekly) + 6h случайная задержка"
  log_info "  Просмотр: systemctl --user list-timers ${TIMER_NAME}.timer"
}

remove_timer() {
  log_header "Удаление systemd timer"

  systemctl --user stop "${TIMER_NAME}.timer" 2>/dev/null || true
  systemctl --user disable "${TIMER_NAME}.timer" 2>/dev/null || true
  rm -f "$SYSTEMD_DIR/${TIMER_NAME}.service" "$SYSTEMD_DIR/${TIMER_NAME}.timer"
  systemctl --user daemon-reload 2>/dev/null || true

  log_info "Systemd timer удалён: ${TIMER_NAME}"
}

show_status() {
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  v2rayN — статус авто-обновления правил         ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # Timer status
  if systemctl --user --no-pager list-timers "${TIMER_NAME}.timer" &>/dev/null 2>&1; then
    echo "  Systemd timer: УСТАНОВЛЕН"
    systemctl --user --no-pager list-timers "${TIMER_NAME}.timer" 2>/dev/null
  else
    echo "  Systemd timer: НЕ УСТАНОВЛЕН"
    echo "  Установка: $0 --install-timer"
  fi
  echo ""

  # Rules status
  for f in geoip.dat geosite.dat; do
    if [ -f "$BIN_DIR/$f" ]; then
      echo "  $f: $(file_size "$BIN_DIR/$f") (последнее обновление: $(stat -c '%y' "$BIN_DIR/$f" 2>/dev/null | cut -d. -f1 || echo 'неизвестно'))"
    else
      echo "  $f: НЕ УСТАНОВЛЕН"
    fi
  done
  echo ""

  # Last update log
  if [ -f "$LOG_FILE" ]; then
    echo "  Последнее обновление в логе:"
    tail -3 "$LOG_FILE" 2>/dev/null
  fi
  echo ""

  echo "  systemctl --user list-timers           # список таймеров"
  echo "  journalctl --user -u ${TIMER_NAME}.service  # логи обновления"
  echo "  $0 --install-timer                 # установить таймер"
  echo "  $0 --remove-timer                  # удалить таймер"
}

# ---- Обработка специальных действий ----
case "$ACTION" in
  install-timer) install_timer; exit 0 ;;
  remove-timer)  remove_timer;  exit 0 ;;
  status)        show_status;   exit 0 ;;
esac

# ---- Основное обновление ----
# Инициализация логирования (если lib/common.sh загружен)
if declare -f log_init &>/dev/null; then
  log_init
else
  LOG_DIR="$HOME/.local/share/v2rayN/logs"
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/${SCRIPT_NAME}.log"
fi

log_header "v2rayN Russia Rules Updater"
mkdir -p "$BIN_DIR" "$CACHE_DIR"

# Блокировка конкурентного запуска
if ! acquire_lock; then
  log_warn "Предыдущий запуск ещё выполняется. Выход."
  exit 1
fi

# Retry-загрузка + SHA256 проверка
update_file() {
  local name="$1"
  local dest="$BIN_DIR/$name"
  local cache="$CACHE_DIR/$name"

  log_info "Загрузка $name ..."

  local tmp_file
  tmp_file=$(mktemp "/tmp/${name}.XXXXXX")
  chmod 600 "$tmp_file"

  local downloaded=false

  # Пробуем каждый зеркальный URL по порядку
  for base_url in "${RELEASE_URLS[@]}"; do
    local url="$base_url/$name"
    local sha_url="${url}.sha256"

    log_info "  Попытка: $base_url"

    if download_with_retry "$url" "$tmp_file" 2 2; then
      log_info "  Скачан: $(file_size "$tmp_file")"

      # Проверка SHA256
      local sha_ok=2  # 2 = нет checksum файла
      if declare -f verify_sha256 &>/dev/null; then
        verify_sha256 "$tmp_file" "$sha_url" && sha_ok=0 || sha_ok=$?
      fi

      if [ "$sha_ok" -eq 0 ]; then
        # SHA256 совпал — устанавливаем
        cp -f "$tmp_file" "$cache"
        mv -f "$tmp_file" "$dest"
        log_info "  $name: установлен (SHA256 OK, зеркало: $base_url)"
        downloaded=true
        break
      elif [ "$sha_ok" -eq 2 ]; then
        # Нет checksum файла — устанавливаем с предупреждением
        cp -f "$tmp_file" "$cache"
        mv -f "$tmp_file" "$dest"
        log_info "  $name: установлен (без SHA256 проверки, зеркало: $base_url)"
        downloaded=true
        break
      else
        # SHA256 не совпал — пробуем следующее зеркало
        log_warn "  $name: SHA256 не совпал на $base_url. Пробую следующее зеркало."
        rm -f "$tmp_file"
        tmp_file=$(mktemp "/tmp/${name}.XXXXXX")
        chmod 600 "$tmp_file"
      fi
    else
      log_warn "  $name: зеркало $base_url недоступно. Пробую следующее..."
      rm -f "$tmp_file"
      tmp_file=$(mktemp "/tmp/${name}.XXXXXX")
      chmod 600 "$tmp_file"
    fi
  done

  if [ "$downloaded" = true ]; then
    return 0
  fi

  # Fallback: кэш
  if [ -f "$cache" ] && validate_dat "$cache"; then
    cp -f "$cache" "$dest"
    log_info "  $name: восстановлен из кэша ($(file_size "$cache"))"
    return 0
  fi

  log_warn "  $name: кэш пуст. Файл не обновлён."
  return 1
}

# Обновляем файлы
update_file "geoip.dat"
update_file "geosite.dat"

# Финальная проверка
log_header "Проверка"
ALL_OK=true
for f in geoip.dat geosite.dat; do
  if [ -f "$BIN_DIR/$f" ] && validate_dat "$BIN_DIR/$f"; then
    log_info "  $f: OK ($(file_size "$BIN_DIR/$f"))"
  else
    log_warn "  $f: ОТСУТСТВУЕТ или повреждён"
    ALL_OK=false
  fi
done

if [ "$ALL_OK" = true ]; then
  log_info "Обновление завершено успешно."

  # Desktop notification
  if command -v notify-send &>/dev/null; then
    notify-send -i v2rayN "v2rayN: правила обновлены" \
      "GeoIP/Geosite обновлены успешно" 2>/dev/null || true
  fi

  # Авто-рестарт v2rayN (если запрошено)
  if [ "$RESTART_V2RAYN" = true ]; then
    log_info "Перезапуск v2rayN..."
    if systemctl --user is-active v2rayn.service &>/dev/null 2>&1; then
      if systemctl --user restart v2rayn.service 2>/dev/null; then
        log_info "  v2rayn.service перезапущен"
      else
        log_warn "  Не удалось перезапустить v2rayn.service"
      fi
    elif command -v pgrep &>/dev/null && pgrep -x v2rayn &>/dev/null; then
      pkill -x v2rayn 2>/dev/null || true
      log_info "  v2rayn остановлен. Запустите заново: v2rayn"
    else
      log_info "  v2rayn не запущен. Ничего не делаю."
    fi
  fi
else
  log_warn "Обновление завершено с ошибками."
  if [ "$RESTART_V2RAYN" = false ]; then
    log_info "Для применения изменений перезапустите v2rayN."
  fi
fi

if [ "$RESTART_V2RAYN" = false ]; then
  echo ""
  log_info "Совет: установите systemd timer для авто-обновления:"
  log_info "  $0 --install-timer"
  log_info ""
  log_info "Авто-рестарт v2rayN после обновления:"
  log_info "  $0 --restart-v2rayn"
fi
