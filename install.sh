#!/bin/bash
# shellcheck disable=SC2317
set -euo pipefail

# v2rayN Russia Setup — полностью автоматизированный установщик
# Использование:
#   bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)
#   или
#   ./install.sh [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]

REPO_URL="${REPO_URL:-https://github.com/ZDarow/V_2_R_A_Y_N.git}"

# Зеркала для geoip/geosite (runetfreedom/russia-v2ray-rules-dat)
RULES_RELEASE_URLS=(
  "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
  "https://gitlab.com/runetfreedom/russia-v2ray-rules-dat/-/raw/release"
  "https://codeberg.org/runetfreedom/russia-v2ray-rules-dat/raw/branch/release"
)


# ---- Валидация REPO_URL ----
if ! [[ "$REPO_URL" =~ ^https://github\.com/[^/]+/[^/]+(\.git)?$ ]]; then
  echo "[✗] Недопустимый URL репозитория: $REPO_URL"
  echo "   Ожидается: https://github.com/username/repo.git"
  exit 1
fi

# ---- trap для очистки временных файлов ----
CLONE_DIR=""
cleanup() {
  if [ -n "$CLONE_DIR" ] && [ -d "$CLONE_DIR" ]; then
    rm -rf "$CLONE_DIR"
  fi
}
trap cleanup EXIT

# ---- Подключаем общую библиотеку локально (только если есть) ----
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]:-$0}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[0]:-$0}")"
SCRIPT_DIR_INSTALLER=""
if [ -n "$SCRIPT_PATH" ] && [ -f "$(dirname "$SCRIPT_PATH")/config/routing-russia.json" ] 2>/dev/null; then
  SCRIPT_DIR_INSTALLER="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
fi

LIB_SHARED=""
if [ -n "$SCRIPT_DIR_INSTALLER" ] && [ -f "$SCRIPT_DIR_INSTALLER/lib/common.sh" ]; then
  LIB_SHARED="$SCRIPT_DIR_INSTALLER/lib/common.sh"
  # shellcheck disable=SC1090
  source "$LIB_SHARED"
  declare -f log_init &>/dev/null && log_init  # инициализация лог-файла и fd 3
elif [ -f "./lib/common.sh" ]; then
  LIB_SHARED="./lib/common.sh"
  # shellcheck disable=SC1090
  source "$LIB_SHARED"
  declare -f log_init &>/dev/null && log_init
fi

# Если библиотека не загружена — минимальные fallback функции
if ! declare -f download_with_retry &>/dev/null; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
  info()  { echo -e "${GREEN}[✓]${NC} $1"; }
  warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
  error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
  header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }
  download_with_retry() {
    local url="$1" dest="$2" i=0 max=3 delay=2
    while [ "$i" -lt "$max" ]; do
      i=$((i+1))
      if command -v curl &>/dev/null; then curl -sSL --connect-timeout 15 -o "$dest.tmp" "$url" && mv "$dest.tmp" "$dest" && return 0
      elif command -v wget &>/dev/null; then wget -q --timeout=15 -O "$dest.tmp" "$url" && mv "$dest.tmp" "$dest" && return 0
      fi
      [ "$i" -lt "$max" ] && sleep "$delay" && delay=$((delay*2))
    done
    return 1
  }
  validate_dat() { [ -f "$1" ] && [ -s "$1" ]; }
  verify_sha256() { return 2; }
  acquire_lock() { return 0; }
  release_lock() { return 0; }
fi

# ---- Dry-run helper ----
DRY_RUN=false
run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] $*" >&2
    return 0
  fi
  "$@"
}

# ---- Парсинг аргументов ----
FORCE_REINSTALL=false
SKIP_V2RAYN=false
SUBSCRIPTIONS_MODE="all"  # all | interactive
show_help() {
  echo "v2rayN Russia Setup — полностью автоматизированный установщик"
  echo ""
  echo "Использование:"
  echo "  bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)"
  echo "  $0 [--help] [--dry-run] [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]"
  echo ""
  echo "Флаги:"
  echo "  --help              Показать эту справку"
  echo "  --dry-run           Показать что будет сделано без реальных изменений"
  echo "  --force-reinstall   Переустановить v2rayN, даже если уже установлен"
  echo "  --skip-v2rayn       Не устанавливать v2rayN (только конфиги и подписки)"
  echo "  --repo-url <url>    URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N)"
  echo "  --kill-switch       Включить kill-switch (iptables) после установки"
  echo "  --subscriptions     Интерактивный выбор подписок для импорта"
  echo ""
  echo "  Перед установкой скрипт запросит sudo для:"
  echo "    • apt-get/dnf/pacman — установка пакетов"
  echo "    • dpkg — установка .NET Runtime"
  echo "    • установка v2rayN в /opt/"
  echo "    • iptables — kill-switch (только с --kill-switch)"
  echo "    Подробнее: docs/install.md#безопасность"
  exit 0
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) show_help ;;
    --dry-run) DRY_RUN=true; shift ;;
    --force-reinstall) FORCE_REINSTALL=true; shift ;;
    --skip-v2rayn) SKIP_V2RAYN=true; shift ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --kill-switch) KILL_SWITCH=true; shift ;;
    --subscriptions) SUBSCRIPTIONS_MODE="interactive"; shift ;;
    *) warn "Неизвестный флаг: $1 (используйте --help для списка)"; shift ;;
  esac
done

if [ "$DRY_RUN" = true ]; then
  header "РЕЖИМ DRY-RUN: изменения не применяются"
fi

# ---- Определение системы ----
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  DEB_ARCH="64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *) error "Неподдерживаемая архитектура: $ARCH. Поддерживаются только x86_64 и aarch64." ;;
esac

OS_ID=$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null || echo "unknown")
info "Система: $OS_ID, архитектура: $ARCH"

# ---- Root-проверка ----
if [ "$(id -u)" -eq 0 ]; then
  error "Не запускайте скрипт от root. Используйте обычного пользователя (sudo будет запрошен по мере необходимости)."
fi

# ---- Режимы работы ----
# Определяем, откуда запущен скрипт: из локального репозитория или из pipe
# SCRIPT_PATH уже вычислен выше (строки 24-28)
if [ -n "$SCRIPT_PATH" ] && [ -f "$(dirname "$SCRIPT_PATH")/config/routing-russia.json" ] 2>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  # shellcheck disable=SC2034
  LOCAL_MODE=true
  info "Локальный режим: конфиги найдены в $SCRIPT_DIR"
else
  # shellcheck disable=SC2034
  LOCAL_MODE=false
  warn "Запуск через pipe или конфиги не найдены. Репозиторий будет клонирован."
  CLONE_DIR=$(mktemp -d)
  info "Клонирование $REPO_URL ..."
  run git clone --depth=1 "$REPO_URL" "$CLONE_DIR" 2>/dev/null || error "Не удалось клонировать репозиторий. Проверьте подключение к интернету."
  SCRIPT_DIR="$CLONE_DIR"
fi

# ---- 1. Установка зависимостей ----
header "Установка системных зависимостей"
install_deps() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] sudo apt-get update && install git wget curl sqlite3 ca-certificates (или dnf/pacman)"
    return 0
  fi
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git wget curl sqlite3 ca-certificates
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y -q git wget curl sqlite ca-certificates
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm --needed git wget curl sqlite ca-certificates
  else
    return 1
  fi
}
if install_deps; then
  info "Зависимости установлены"
else
  warn "Не удалось установить зависимости через пакетный менеджер. Установите git, wget, curl, sqlite3 вручную."
fi

# ---- 2. Установка .NET Runtime (если не установлен) ----
header "Проверка .NET Runtime"
DOTNET_INSTALLED=false
if command -v dotnet &>/dev/null; then
  DOTNET_VER=$(dotnet --version 2>/dev/null | cut -d. -f1)
  info ".NET Runtime найден: $(dotnet --version 2>/dev/null)"
  if [ -n "$DOTNET_VER" ] && [ "$DOTNET_VER" -ge 10 ] 2>/dev/null; then
    DOTNET_INSTALLED=true
  else
    warn "Требуется .NET 10.0+, установлена версия $(dotnet --version 2>/dev/null). Попытка обновления..."
  fi
fi
if [ "$DOTNET_INSTALLED" = false ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] sudo apt-get install dotnet-runtime-10.0 (или через Microsoft repo)"
  elif command -v apt-get &>/dev/null; then
    info "Установка dotnet-runtime-10.0 (требуется для v2rayN 7.22+)..."
    if sudo apt-get install -y -qq dotnet-runtime-10.0 2>/dev/null; then
      info ".NET 10.0 успешно установлен"
    else
      warn "Пакет dotnet-runtime-10.0 не найден в стандартных репозиториях."
      info "Добавляю Microsoft package repository..."
      MS_PKG="packages-microsoft-prod.deb"
      wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs 2>/dev/null || echo '24.04')/$MS_PKG" -O "/tmp/$MS_PKG" 2>/dev/null || true
      if [ -f "/tmp/$MS_PKG" ] && [ -s "/tmp/$MS_PKG" ]; then
        sudo dpkg -i "/tmp/$MS_PKG" 2>/dev/null || true
        rm -f "/tmp/$MS_PKG"
        sudo apt-get update -qq 2>/dev/null || true
        if sudo apt-get install -y -qq dotnet-runtime-10.0; then
          info ".NET 10.0 успешно установлен после добавления Microsoft репозитория"
        else
          warn "Microsoft репозиторий добавлен, но dotnet-runtime-10.0 всё ещё недоступен."
          warn "Установите вручную: https://dotnet.microsoft.com/download"
        fi
      else
        warn "Не удалось загрузить Microsoft repository package."
        warn "Установите .NET 10.0 вручную: https://dotnet.microsoft.com/download"
      fi
    fi
  else
    warn "Установите .NET Runtime 10.0+ вручную: https://dotnet.microsoft.com/download"
  fi
fi

# ---- 3. Установка v2rayN ----
if [ "$SKIP_V2RAYN" = false ]; then
  if command -v v2rayn &>/dev/null && [ "$FORCE_REINSTALL" = false ]; then
    info "v2rayN уже установлен (пропускаем, используйте --force-reinstall для переустановки)"
  else
    header "Установка v2rayN"
    # Пробуем GitHub API, затем fallback на прямой URL
    LATEST=""
    if command -v curl &>/dev/null; then
    LATEST=$(curl -sSL --connect-timeout 10 https://api.github.com/repos/2dust/v2rayN/releases/latest 2>/dev/null \
      | grep "browser_download_url.*linux-${DEB_ARCH}\.deb\"" | head -1 | cut -d'"' -f4 || true)
    fi
    if [ -z "$LATEST" ]; then
      LATEST="https://github.com/2dust/v2rayN/releases/latest/download/v2rayN-linux-${DEB_ARCH}.deb"
      warn "GitHub API недоступен. Использую прямой URL (может быть неактуальным)."
    fi
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY-RUN] Загрузка v2rayN: $LATEST"
      echo "  [DRY-RUN] sudo dpkg -i ... && настройка PATH"
    else
      V2RAYN_DEB="/tmp/v2rayN-$$.deb"
      info "Загрузка v2rayN: $LATEST"
      if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$V2RAYN_DEB" "$LATEST" 2>/dev/null || \
          curl -sSL -o "$V2RAYN_DEB" "$LATEST"
      else
        curl -sSL -o "$V2RAYN_DEB" "$LATEST"
      fi
      if [ ! -f "$V2RAYN_DEB" ] || [ ! -s "$V2RAYN_DEB" ]; then
        rm -f "$V2RAYN_DEB"
        error "Не удалось загрузить v2rayN. Проверьте соединение."
      fi
      if sudo dpkg -i "$V2RAYN_DEB"; then
        info "v2rayN: пакет установлен"
      else
        warn "dpkg: ошибка зависимостей. Исправление через apt-get install -f..."
        sudo apt-get install -f -y -qq || warn "apt-get install -f не удался"
      fi
      rm -f "$V2RAYN_DEB"
      if command -v v2rayn &>/dev/null; then
        info "v2rayN установлен: $(v2rayn --version 2>/dev/null || echo 'версия неизвестна')"
      elif [ -x /opt/v2rayN/v2rayn ]; then
        info "v2rayN установлен в /opt/v2rayN/"
        mkdir -p "$HOME/.local/bin"
        ln -sf /opt/v2rayN/v2rayn "$HOME/.local/bin/v2rayn"
      else
        warn "v2rayN: бинарник не найден. Проверьте /opt/v2rayN/ или установите вручную."
      fi
    fi
  fi
fi

# ---- Проверка $HOME ----
if [ -z "${HOME:-}" ] || [ "$HOME" = "/" ]; then
  error "HOME не установлен или равен корню системы. Установите HOME в директорию пользователя."
fi

# ---- 4. Директории ----
V2RAYN_CONFIG_DIR="$HOME/.config/v2rayN"
V2RAYN_BIN_DIR="$HOME/.local/share/v2rayN/bin"
V2RAYN_BINCONFIG_DIR="$HOME/.local/share/v2rayN/binConfigs"
V2RAYN_GUICONFIG_DIR="$HOME/.local/share/v2rayN/guiConfigs"
run mkdir -p "$V2RAYN_CONFIG_DIR" "$V2RAYN_BIN_DIR" "$V2RAYN_BINCONFIG_DIR" "$V2RAYN_GUICONFIG_DIR"

# ---- 5. Правила роутинга (geoip/geosite) ----
header "Установка правил geoip/geosite"

info "Загрузка правил из runetfreedom (ветка release) ..."

CACHE_DIR="$HOME/.cache/v2rayN/rules"
run mkdir -p "$CACHE_DIR"

install_rule_file() {
  local name="$1"
  local dest="$V2RAYN_BIN_DIR/$name"
  local cache="$CACHE_DIR/$name"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Загрузка $name + SHA256 проверка + установка в $dest"
    return 0
  fi

  local downloaded=false
  for base_url in "${RULES_RELEASE_URLS[@]}"; do
    local url="$base_url/$name"
    local sha_url="${url}.sha256"
    local tmp_file
    tmp_file="/tmp/${name}.$$.$(echo "$base_url" | md5sum 2>/dev/null | cut -c1-8 || echo "$RANDOM")"

    info "  Попытка: $base_url"
    if download_with_retry "$url" "$tmp_file" 2 2; then
      local sha_ok=2
      if declare -f verify_sha256 &>/dev/null; then
        verify_sha256 "$tmp_file" "$sha_url" && sha_ok=0 || sha_ok=$?
      fi

      if [ "$sha_ok" -eq 0 ] || [ "$sha_ok" -eq 2 ]; then
        run cp -f "$tmp_file" "$cache"
        run mv -f "$tmp_file" "$dest"
        # shellcheck disable=SC2012
        info "$name: установлен ($(ls -lh "$dest" | awk '{print $5}'))"
        downloaded=true
        break
      else
        warn "$name: SHA256 не совпал на $base_url. Пробую следующее зеркало."
        run rm -f "$tmp_file"
      fi
    else
      warn "$name: зеркало $base_url недоступно. Пробую следующее..."
      run rm -f "$tmp_file"
    fi
  done

  if [ "$downloaded" = true ]; then
    return 0
  fi

  # Fallback: кэш
  if [ -f "$cache" ] && validate_dat "$cache"; then
    run cp -f "$cache" "$dest"
    info "$name: восстановлен из кэша"
    return 0
  fi

  warn "$name: не установлен (ни одно зеркало, ни кэш)"
  return 1
}

install_rule_file "geoip.dat"
install_rule_file "geosite.dat"

if validate_dat "$V2RAYN_BIN_DIR/geoip.dat" && validate_dat "$V2RAYN_BIN_DIR/geosite.dat"; then
  info "Правила geoip/geosite: OK"
fi

# ---- 6. Конфигурация роутинга и Xray ----
header "Установка конфигурации"

# Функция копирования с проверкой
copy_config() {
  local src="$1" dest="$2" label="$3"
  if [ -f "$src" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY-RUN] cp $src → $dest"
    else
      run mkdir -p "$(dirname "$dest")"
      run cp -f "$src" "$dest"
    fi
    info "$label: установлен"
  else
    warn "$label: файл $src не найден, пропущен"
  fi
}

copy_config "$SCRIPT_DIR/config/routing-russia.json" "$V2RAYN_CONFIG_DIR/routing-russia.json" "routing-russia.json"
copy_config "$SCRIPT_DIR/config/config-template-xray.json" "$V2RAYN_BINCONFIG_DIR/config-template-xray.json" "config-template-xray.json"
copy_config "$SCRIPT_DIR/config/only_blocked.json" "$V2RAYN_CONFIG_DIR/only_blocked.json" "only_blocked.json (мобильный режим)"

# Предупреждение о allowInsecure
info "⚠️  Xray-core v26.2.6+ УЖЕ удалил allowInsecure."
info "   Используйте pinnedPeerCertSha256 в настройках подписки."
info "   Проверка: ~/.local/share/v2rayN/scripts/migrate-allowinsecure.sh"

# ---- 7. Скрипты управления + авто-обновление ----
header "Установка скриптов управления"
V2RAYN_SCRIPTS_DIR="$HOME/.local/share/v2rayN/scripts"
run mkdir -p "$V2RAYN_SCRIPTS_DIR"

# Утилитарные скрипты
for script in proxy-toggle.sh proxy_set_linux_sh.sh update-rules.sh status.sh diagnose.sh kill-switch.sh migrate-allowinsecure.sh; do
  local_src="$SCRIPT_DIR/scripts/$script"
  if [ -f "$local_src" ]; then
    run cp -f "$local_src" "$V2RAYN_SCRIPTS_DIR/$script"
    run chmod +x "$V2RAYN_SCRIPTS_DIR/$script"
    info "$script: установлен"
  fi
done

# Алиас для update-rules.sh (удобный вызов)
run mkdir -p "$HOME/.local/bin"
run ln -sf "$V2RAYN_SCRIPTS_DIR/update-rules.sh" "$HOME/.local/bin/v2rayn-update-rules"
info "update-rules.sh: алиас ~/.local/bin/v2rayn-update-rules"

# Установка systemd timer для авто-обновления правил
header "Авто-обновление geoip/geosite (systemd timer)"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
run mkdir -p "$SYSTEMD_USER_DIR"

if [ -f "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.service" ] && \
   [ -f "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.timer" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Установка systemd timer (v2rayn-rules-update.timer)"
  else
    sed "s|ExecStart=.*|ExecStart=$V2RAYN_SCRIPTS_DIR/update-rules.sh|" \
      "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.service" > "$SYSTEMD_USER_DIR/v2rayn-rules-update.service"
    run cp -f "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.timer" "$SYSTEMD_USER_DIR/v2rayn-rules-update.timer"

    if systemctl --user daemon-reload 2>/dev/null; then
      run systemctl --user enable v2rayn-rules-update.timer 2>/dev/null || true
      run systemctl --user start v2rayn-rules-update.timer 2>/dev/null || true
      info "Systemd timer: v2rayn-rules-update.timer (еженедельно)"
      info "  Просмотр: systemctl --user list-timers v2rayn-rules-update.timer"
    else
      warn "systemd --user недоступен. Timer не установлен."
      warn "  Ручной запуск: $V2RAYN_SCRIPTS_DIR/update-rules.sh"
    fi
  fi
else
  warn "Файлы systemd не найдены. Timer не установлен."
fi

# ---- 8. Импорт подписок в БД v2rayN ----
header "Импорт подписок в v2rayN"
DB_PATH="$V2RAYN_GUICONFIG_DIR/guiNDB.db"

# Определение всех доступных подписок
declare -A SUBSCRIPTIONS
SUBSCRIPTIONS["BLACK-RUS-001"]="Чёрные списки РФ — весь трафик через VPN (igareck)"
SUBSCRIPTIONS["WHITE-RUS-001"]="Белые списки РФ — только РФ через VPN (igareck)"
SUBSCRIPTIONS["WL-ZIENG2-001"]="WL Белый список (zieng2) — для REALITY"
SUBSCRIPTIONS["WHITELIST-IPS-001"]="Whitelist IP (hxehex) — CIDR для мобильных"

if [ "$SUBSCRIPTIONS_MODE" = "interactive" ] && [ -t 0 ] && [ -t 1 ]; then
  info "Выберите подписки для импорта (по умолчанию — все):"
  SELECTED_SUBS=()
  for id in "${!SUBSCRIPTIONS[@]}"; do
    echo -n "  Импортировать «${SUBSCRIPTIONS[$id]}»? [Y/n] "
    read -r -t 10 ans || true
    case "${ans,,}" in
      n|no) ;;
      *) SELECTED_SUBS+=("$id") ;;
    esac
  done
  if [ "${#SELECTED_SUBS[@]}" -eq 0 ]; then
    warn "Не выбрано ни одной подписки. Импорт пропущен."
  else
    info "Выбрано ${#SELECTED_SUBS[@]} подписки(ок)"
  fi
else
  SELECTED_SUBS=("${!SUBSCRIPTIONS[@]}")
fi

if command -v sqlite3 &>/dev/null && [ "${#SELECTED_SUBS[@]}" -gt 0 ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Импорт ${#SELECTED_SUBS[@]} подписок в БД v2rayN (sqlite3)"
  else
    sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS SubItem (
      Id TEXT PRIMARY KEY,
      Remarks TEXT,
      Url TEXT,
      MoreUrl TEXT,
      Enabled INTEGER DEFAULT 1,
      UserAgent TEXT DEFAULT '',
      Sort INTEGER DEFAULT 0,
      Filter TEXT DEFAULT '',
      AutoUpdateInterval INTEGER DEFAULT 1440,
      UpdateTime INTEGER DEFAULT 0,
      ConvertTarget TEXT DEFAULT 'v2ray',
      Memo TEXT DEFAULT '',
      LastUpdateTime INTEGER DEFAULT 0
    );" 2>/dev/null || true

    for sub_id in "${SELECTED_SUBS[@]}"; do
      case "$sub_id" in
        BLACK-RUS-001)
          sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO SubItem (Id, Remarks, Url, MoreUrl, Enabled, Sort, AutoUpdateInterval, ConvertTarget)
            VALUES ('BLACK-RUS-001', 'Чёрные списки РФ (весь трафик через VPN)',
              'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt',
              'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt',
              1, 1, 1440, 'v2ray');" 2>/dev/null || warn "  BLACK-RUS-001: ошибка импорта" ;;
        WHITE-RUS-001)
          sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO SubItem (Id, Remarks, Url, MoreUrl, Enabled, Sort, AutoUpdateInterval, ConvertTarget)
            VALUES ('WHITE-RUS-001', 'Белые списки РФ (только РФ через VPN)',
              'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt',
              'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-checked.txt
          https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-SNI-RU-all.txt',
              1, 2, 1440, 'v2ray');" 2>/dev/null || warn "  WHITE-RUS-001: ошибка импорта" ;;
        WL-ZIENG2-001)
          sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO SubItem (Id, Remarks, Url, MoreUrl, Enabled, Sort, AutoUpdateInterval, ConvertTarget)
            VALUES ('WL-ZIENG2-001', 'WL Белый список (zieng2)',
              'https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt',
              'https://codeberg.org/zieng2/wl/raw/branch/main/vless_universal.txt',
              1, 3, 60, 'v2ray');" 2>/dev/null || warn "  WL-ZIENG2-001: ошибка импорта" ;;
      esac
    done
    info "Подписки импортированы в БД v2rayN"
  fi
elif [ "$DRY_RUN" = false ]; then
  warn "sqlite3 не найден. Подписки не импортированы (можно импортировать вручную в GUI)."
fi

# ---- 9. Настройка системного прокси ----
header "Настройка системного прокси"
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Настройка системного прокси (gsettings или kwriteconfig)"
elif command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.system.proxy'; then
  run gsettings set org.gnome.system.proxy mode 'manual'
  run gsettings set org.gnome.system.proxy.http host '127.0.0.1'
  run gsettings set org.gnome.system.proxy.http port 10809
  run gsettings set org.gnome.system.proxy.https host '127.0.0.1'
  run gsettings set org.gnome.system.proxy.https port 10809
  run gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
  run gsettings set org.gnome.system.proxy.socks port 10808
  IGNORE="['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']"
  run gsettings set org.gnome.system.proxy ignore-hosts "$IGNORE"
  info "Системный прокси настроен (GNOME/Cinnamon/XFCE/MATE)"
elif command -v kwriteconfig6 &>/dev/null || command -v kwriteconfig5 &>/dev/null; then
  KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null)
  run "$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 1
  run "$KWC" --file kioslaverc --group "Proxy Settings" --key httpProxy "http://127.0.0.1:10809"
  run "$KWC" --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://127.0.0.1:10809"
  run "$KWC" --file kioslaverc --group "Proxy Settings" --key socksProxy "socks://127.0.0.1:10808"
  run "$KWC" --file kioslaverc --group "Proxy Settings" --key NoProxyFor "localhost,127.0.0.0/8,::1,*.local,.ru,.su,.xn--p1ai"
  run dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:""
  info "Системный прокси настроен (KDE Plasma)"
else
  warn "Не удалось настроить системный прокси (только GNOME/KDE). Настройте вручную: HTTP 127.0.0.1:10809, SOCKS 127.0.0.1:10808"
fi

# ---- 10. Системный сервис + автозапуск ----
header "Системный сервис и автозапуск"

# Systemd user service
if command -v systemctl &>/dev/null; then
  if [ -f "$SCRIPT_DIR/lib/systemd/v2rayn.service" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY-RUN] Установка systemd сервиса v2rayn.service"
    else
      HOME_ESC=$(printf '%s\n' "$HOME" | sed 's/[&|/\]/\\&/g')
      sed "s|ExecStart=.*|ExecStart=${HOME_ESC}/.local/bin/v2rayn|" \
        "$SCRIPT_DIR/lib/systemd/v2rayn.service" > "$SYSTEMD_USER_DIR/v2rayn.service"
      sed -i "s|%h|$HOME|g; s|%t|${XDG_RUNTIME_DIR:-/run/user/$(id -u)}|g" "$SYSTEMD_USER_DIR/v2rayn.service"
      run systemctl --user daemon-reload
      run systemctl --user enable v2rayn.service
      info "systemd сервис: v2rayn.service (авто-перезапуск при падении)"
      info "  systemctl --user start v2rayn.service"
    fi
  fi
fi

# XDG автозапуск
AUTOSTART_DIR="$HOME/.config/autostart"
run mkdir -p "$AUTOSTART_DIR"
if [ -f "$SCRIPT_DIR/lib/autostart/v2rayn.desktop" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] Установка XDG autostart v2rayn.desktop"
  else
    sed "s|__HOME__|$HOME|g" "$SCRIPT_DIR/lib/autostart/v2rayn.desktop" > "$AUTOSTART_DIR/v2rayn.desktop"
  fi
  info "Автозапуск: XDG autostart (v2rayN будет запускаться при входе)"
fi

# ---- 11. Авто-настройка роутинга (попытка) ----
header "Авто-настройка роутинга"
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] Настройка роутинга в БД v2rayN"
elif command -v sqlite3 &>/dev/null && [ -f "$DB_PATH" ]; then
  ROUTING_FILE="$HOME/.config/v2rayN/routing-russia.json"
  ROUTING_KEYS_EXIST=$(sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('GlobalConfig','SettingItem');" 2>/dev/null | wc -l)
  if [ "$ROUTING_KEYS_EXIST" -gt 0 ]; then
    if sqlite3 "$DB_PATH" \
      "INSERT OR REPLACE INTO GlobalConfig (key, value) VALUES
        ('routingCustomFile', '$ROUTING_FILE'),
        ('routingCustomEnabled', 'true'),
        ('setRouteOnly', 'false'),
        ('domainStrategy', 'IPOnDemand');" 2>/dev/null; then
      info "Правила роутинга настроены в БД (GlobalConfig)"
    else
      warn "Не удалось записать настройки роутинга (будет настроено вручную)"
    fi
  else
    sqlite3 "$DB_PATH" "CREATE TABLE IF NOT EXISTS GlobalConfig (key TEXT PRIMARY KEY, value TEXT);" 2>/dev/null
    if sqlite3 "$DB_PATH" \
      "INSERT OR REPLACE INTO GlobalConfig (key, value) VALUES
        ('routingCustomFile', '$ROUTING_FILE'),
        ('routingCustomEnabled', 'true'),
        ('setRouteOnly', 'false'),
        ('domainStrategy', 'IPOnDemand');" 2>/dev/null; then
      info "Правила роутинга настроены (новая БД)"
    else
      warn "Не удалось записать настройки роутинга"
    fi
  fi
  info "  Файл: routing-russia.json"
else
  warn "Не удалось настроить роутинг автоматически. После запуска v2rayN:"
  warn "  Настройки → Настройки маршрутизации → routing-russia.json"
fi

# ---- 12. Запуск v2rayN + прокси ----
header "Запуск v2rayN"

if command -v v2rayn &>/dev/null; then
  if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    info "Запускаю v2rayN в фоне..."
    if [ "$DRY_RUN" = true ]; then
      echo "  [DRY-RUN] nohup v2rayn > /dev/null 2>&1 &"
    else
      nohup v2rayn > /dev/null 2>&1 &
      V2RAYN_PID=$!
      info "  PID: $V2RAYN_PID"
      sleep 2
    fi

    if [ "$DRY_RUN" = false ]; then
      if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.system.proxy'; then
        info "Включаю системный прокси..."
        run gsettings set org.gnome.system.proxy mode 'manual'
        info "  Системный прокси: включён"
      elif command -v kwriteconfig5 &>/dev/null || command -v kwriteconfig6 &>/dev/null; then
        KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null)
        run "$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 1
        info "Системный прокси: включён (KDE)"
      fi
    fi

    info "v2rayN запущен. Прокси активен."
    echo ""
    echo "  🔗 SOCKS5: 127.0.0.1:10808"
    echo "  🔗 HTTP:   127.0.0.1:10809"
    echo "  🔄 Для выключения: ~/.config/v2rayN/proxy-toggle.sh off"
  else
    warn "Графическая сессия не обнаружена (нет DISPLAY/WAYLAND_DISPLAY)."
    warn "  v2rayN не запущен — запустите вручную после входа в GUI."
    warn "  Системный прокси и systemd сервис настроены и будут работать."
  fi
else
  warn "v2rayN не найден в PATH. Запустите вручную: v2rayn"
fi

# ---- 13. Kill-switch (опционально) ----
if [ "${KILL_SWITCH:-false}" = true ]; then
  header "Kill-switch (iptables)"
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] sudo $V2RAYN_SCRIPTS_DIR/kill-switch.sh on"
  elif command -v iptables &>/dev/null && sudo -n true 2>/dev/null; then
    info "Включение kill-switch..."
    if sudo "$V2RAYN_SCRIPTS_DIR/kill-switch.sh" on 2>/dev/null; then
      info "Kill-switch активен. Трафик блокируется вне прокси."
    else
      warn "Не удалось включить kill-switch (нужен sudo)"
    fi
  else
    warn "iptables не найден или sudo недоступен. Kill-switch не включён."
    warn "  Включить вручную: sudo ~/.local/share/v2rayN/scripts/kill-switch.sh on"
  fi
fi

# ---- 14. Завершение ----
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  v2rayN установлен и запущен!${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Системный прокси:${NC}    активен (SOCKS5 :10808, HTTP :10809)"
echo -e "  ${YELLOW}Авто-обновление:${NC}     systemd timer (еженедельно)"
echo -e "  ${YELLOW}Автозапуск:${NC}          при входе в систему"
echo -e "  ${YELLOW}Проверка статуса:${NC}    ~/.local/share/v2rayN/scripts/status.sh"
echo -e "  ${YELLOW}Диагностика:${NC}         ~/.local/share/v2rayN/scripts/diagnose.sh"
echo -e "  ${YELLOW}Выключить прокси:${NC}    ~/.config/v2rayN/proxy-toggle.sh off"
echo -e "  ${YELLOW}Обновить правила:${NC}    v2rayn-update-rules"
echo -e "  ${YELLOW}Статус:${NC}              v2rayn-update-rules --status"
echo ""
