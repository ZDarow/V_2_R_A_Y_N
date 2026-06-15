#!/bin/bash
# shellcheck disable=SC2317
set -euo pipefail

# v2rayN Russia Setup — полностью автоматизированный установщик
# Использование:
#   bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)
#   или
#   ./install.sh [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]

REPO_URL="${REPO_URL:-https://github.com/ZDarow/V_2_R_A_Y_N.git}"
RULES_RELEASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"

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
  source "$LIB_SHARED"
elif [ -f "./lib/common.sh" ]; then
  LIB_SHARED="./lib/common.sh"
  source "$LIB_SHARED"
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

# ---- Парсинг аргументов ----
FORCE_REINSTALL=false
SKIP_V2RAYN=false
show_help() {
  echo "v2rayN Russia Setup — полностью автоматизированный установщик"
  echo ""
  echo "Использование:"
  echo "  bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)"
  echo "  $0 [--help] [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]"
  echo ""
  echo "Флаги:"
  echo "  --help              Показать эту справку"
  echo "  --force-reinstall   Переустановить v2rayN, даже если уже установлен"
  echo "  --skip-v2rayn       Не устанавливать v2rayN (только конфиги и подписки)"
  echo "  --repo-url <url>    URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N)"
  exit 0
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) show_help ;;
    --force-reinstall) FORCE_REINSTALL=true; shift ;;
    --skip-v2rayn) SKIP_V2RAYN=true; shift ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    *) warn "Неизвестный флаг: $1 (используйте --help для списка)"; shift ;;
  esac
done

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
# Используем ${BASH_SOURCE[0]:-$0} для защиты от pipe и set -u
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]:-$0}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[0]:-$0}")"
if [ -n "$SCRIPT_PATH" ] && [ -f "$(dirname "$SCRIPT_PATH")/config/routing-russia.json" ] 2>/dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  LOCAL_MODE=true
  info "Локальный режим: конфиги найдены в $SCRIPT_DIR"
else
  LOCAL_MODE=false
  warn "Запуск через pipe или конфиги не найдены. Репозиторий будет клонирован."
  CLONE_DIR=$(mktemp -d)
  info "Клонирование $REPO_URL ..."
  git clone --depth=1 "$REPO_URL" "$CLONE_DIR" 2>/dev/null || error "Не удалось клонировать репозиторий. Проверьте подключение к интернету."
  SCRIPT_DIR="$CLONE_DIR"
fi

# ---- 1. Установка зависимостей ----
header "Установка системных зависимостей"
install_deps() {
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
  if command -v apt-get &>/dev/null; then
    info "Установка dotnet-runtime-10.0 (требуется для v2rayN 7.22+)..."
    # Пробуем установить напрямую; если не находит — добавляем Microsoft репозиторий
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
    V2RAYN_DEB="/tmp/v2rayN-$$.deb"
    info "Загрузка v2rayN: $LATEST"
    # Для Android используйте v2rayNG: https://github.com/2dust/v2rayNG/releases
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
    # Проверка v2rayN: сначала PATH, потом /opt/v2rayN/
    if command -v v2rayn &>/dev/null; then
      info "v2rayN установлен: $(v2rayn --version 2>/dev/null || echo 'версия неизвестна')"
    elif [ -x /opt/v2rayN/v2rayn ]; then
      info "v2rayN установлен в /opt/v2rayN/"
      # Добавляем в PATH для текущего пользователя
      mkdir -p "$HOME/.local/bin"
      ln -sf /opt/v2rayN/v2rayn "$HOME/.local/bin/v2rayn"
    else
      warn "v2rayN: бинарник не найден. Проверьте /opt/v2rayN/ или установите вручную."
    fi
  fi
fi

# ---- 4. Директории ----
V2RAYN_CONFIG_DIR="$HOME/.config/v2rayN"
V2RAYN_BIN_DIR="$HOME/.local/share/v2rayN/bin"
V2RAYN_BINCONFIG_DIR="$HOME/.local/share/v2rayN/binConfigs"
V2RAYN_GUICONFIG_DIR="$HOME/.local/share/v2rayN/guiConfigs"
mkdir -p "$V2RAYN_CONFIG_DIR" "$V2RAYN_BIN_DIR" "$V2RAYN_BINCONFIG_DIR" "$V2RAYN_GUICONFIG_DIR"

# ---- 5. Правила роутинга (geoip/geosite) ----
header "Установка правил geoip/geosite"

info "Загрузка правил из runetfreedom (ветка release) ..."

CACHE_DIR="$HOME/.cache/v2rayN/rules"
mkdir -p "$CACHE_DIR"

install_rule_file() {
  local name="$1"
  local url="$RULES_RELEASE_URL/$name"
  local sha_url="${url}.sha256"
  local dest="$V2RAYN_BIN_DIR/$name"
  local cache="$CACHE_DIR/$name"
  local tmp_file="/tmp/${name}.$$"

  if download_with_retry "$url" "$tmp_file" 3 2; then
    # SHA256 проверка
    local sha_ok=2
    if declare -f verify_sha256 &>/dev/null; then
      verify_sha256 "$tmp_file" "$sha_url" && sha_ok=0 || sha_ok=$?
    fi

    if [ "$sha_ok" -eq 0 ] || [ "$sha_ok" -eq 2 ]; then
      # SHA256 OK или нет checksum файла — устанавливаем
      cp -f "$tmp_file" "$cache"
      mv -f "$tmp_file" "$dest"
      info "$name: установлен ($(ls -lh "$dest" | awk '{print $5}'))"
      return 0
    else
      warn "$name: SHA256 не совпал. Пробую кэш."
      rm -f "$tmp_file"
    fi
  else
    warn "$name: не удалось скачать. Пробую кэш."
    rm -f "$tmp_file"
  fi

  # Fallback: кэш
  if [ -f "$cache" ] && validate_dat "$cache"; then
    cp -f "$cache" "$dest"
    info "$name: восстановлен из кэша"
    return 0
  fi

  warn "$name: не установлен (ни загрузка, ни кэш)"
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
    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest"
    info "$label: установлен"
  else
    warn "$label: файл $src не найден, пропущен"
  fi
}

copy_config "$SCRIPT_DIR/config/routing-russia.json" "$V2RAYN_CONFIG_DIR/routing-russia.json" "routing-russia.json"
copy_config "$SCRIPT_DIR/config/config-template-xray.json" "$V2RAYN_BINCONFIG_DIR/config-template-xray.json" "config-template-xray.json"
copy_config "$SCRIPT_DIR/config/only_blocked.json" "$V2RAYN_CONFIG_DIR/only_blocked.json" "only_blocked.json (мобильный режим)"
copy_config "$SCRIPT_DIR/config/v2rayng-routing-russia.json" "$V2RAYN_CONFIG_DIR/v2rayng-routing-russia.json" "v2rayng-routing-russia.json (v2rayNG формат)"
copy_config "$SCRIPT_DIR/config/v2rayng-only-blocked.json" "$V2RAYN_CONFIG_DIR/v2rayng-only-blocked.json" "v2rayng-only-blocked.json (v2rayNG формат)"
# Предупреждение о allowInsecure
info "⚠️  ВНИМАНИЕ: Xray отключит параметр allowInsecure с 1 августа 2026."
info "   Используйте verifyPeerCertByName в настройках подписки v2rayN."

# ---- 7. Скрипты управления + авто-обновление ----
header "Установка скриптов управления"
V2RAYN_SCRIPTS_DIR="$HOME/.local/share/v2rayN/scripts"
mkdir -p "$V2RAYN_SCRIPTS_DIR"

# Утилитарные скрипты
for script in proxy-toggle.sh proxy_set_linux_sh.sh update-rules.sh; do
  local_src="$SCRIPT_DIR/scripts/$script"
  if [ -f "$local_src" ]; then
    cp -f "$local_src" "$V2RAYN_SCRIPTS_DIR/$script"
    chmod +x "$V2RAYN_SCRIPTS_DIR/$script"
    info "$script: установлен"
  fi
done

# Алиас для update-rules.sh (удобный вызов)
mkdir -p "$HOME/.local/bin"
ln -sf "$V2RAYN_SCRIPTS_DIR/update-rules.sh" "$HOME/.local/bin/v2rayn-update-rules"
info "update-rules.sh: алиас ~/.local/bin/v2rayn-update-rules"

# Установка systemd timer для авто-обновления правил
header "Авто-обновление geoip/geosite (systemd timer)"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

if [ -f "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.service" ] && \
   [ -f "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.timer" ]; then
  # Путь к update-rules.sh в systemd unit должен быть абсолютным
  sed "s|ExecStart=.*|ExecStart=$V2RAYN_SCRIPTS_DIR/update-rules.sh|" \
    "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.service" > "$SYSTEMD_USER_DIR/v2rayn-rules-update.service"
  cp -f "$SCRIPT_DIR/lib/systemd/v2rayn-rules-update.timer" "$SYSTEMD_USER_DIR/v2rayn-rules-update.timer"

  if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable v2rayn-rules-update.timer 2>/dev/null || true
    systemctl --user start v2rayn-rules-update.timer 2>/dev/null || true
    info "Systemd timer: v2rayn-rules-update.timer (еженедельно)"
    info "  Просмотр: systemctl --user list-timers v2rayn-rules-update.timer"
  else
    warn "systemd --user недоступен. Timer не установлен."
    warn "  Ручной запуск: $V2RAYN_SCRIPTS_DIR/update-rules.sh"
  fi
else
  warn "Файлы systemd не найдены. Timer не установлен."
fi

# ---- 8. Импорт подписок в БД v2rayN ----
header "Импорт подписок в v2rayN"
DB_PATH="$V2RAYN_GUICONFIG_DIR/guiNDB.db"
if command -v sqlite3 &>/dev/null; then
  # Создаём таблицу, если БД ещё не инициализирована v2rayN
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

  # Импорт подписок (IGNORE — не перезаписывает существующие)
  sqlite3 "$DB_PATH" <<'SQL' 2>/dev/null || warn "Не удалось импортировать подписки в БД"
INSERT OR IGNORE INTO SubItem (Id, Remarks, Url, MoreUrl, Enabled, Sort, AutoUpdateInterval, ConvertTarget)
VALUES
  ('BLACK-RUS-001', 'Чёрные списки РФ (весь трафик через VPN)',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt',
   1, 1, 1440, 'v2ray'),
  ('WHITE-RUS-001', 'Белые списки РФ (только РФ через VPN)',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile-2.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-checked.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-SNI-RU-all.txt',
   1, 2, 1440, 'v2ray'),
  ('WL-ZIENG2-001', 'WL Белый список (zieng2)',
   'https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt',
   'https://codeberg.org/zieng2/wl/raw/branch/main/vless_universal.txt',
   1, 3, 60, 'v2ray'),
  ('WHITELIST-IPS-001', 'Whitelist IP (hxehex) — CIDR для мобильных',
   'https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt',
   'https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt
https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt',
   1, 4, 60, 'v2ray');
SQL
  info "Подписки импортированы в БД v2rayN"
else
  warn "sqlite3 не найден. Подписки не импортированы (можно импортировать вручную в GUI)."
fi

# ---- 9. Настройка системного прокси ----
header "Настройка системного прокси"
if command -v gsettings &>/dev/null && gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.system.proxy'; then
  gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.http port 10809 2>/dev/null || true
  gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.https port 10809 2>/dev/null || true
  gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.socks port 10808 2>/dev/null || true
  IGNORE="['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']"
  gsettings set org.gnome.system.proxy ignore-hosts "$IGNORE" 2>/dev/null || true
  info "Системный прокси настроен (GNOME/Cinnamon/XFCE/MATE)"
elif command -v kwriteconfig6 &>/dev/null || command -v kwriteconfig5 &>/dev/null; then
  KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null)
  "$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 1 2>/dev/null || true
  "$KWC" --file kioslaverc --group "Proxy Settings" --key httpProxy "http://127.0.0.1:10809" 2>/dev/null || true
  "$KWC" --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://127.0.0.1:10809" 2>/dev/null || true
  "$KWC" --file kioslaverc --group "Proxy Settings" --key socksProxy "socks://127.0.0.1:10808" 2>/dev/null || true
  "$KWC" --file kioslaverc --group "Proxy Settings" --key NoProxyFor "localhost,127.0.0.0/8,::1,*.local,.ru,.su,.xn--p1ai" 2>/dev/null || true
  dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
  info "Системный прокси настроен (KDE Plasma)"
else
  warn "Не удалось настроить системный прокси (только GNOME/KDE). Настройте вручную: HTTP 127.0.0.1:10809, SOCKS 127.0.0.1:10808"
fi

# ---- 10. Завершение ----
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  v2rayN успешно установлен и настроен для работы в РФ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${YELLOW}Запуск:${NC}         v2rayn"
echo -e "  ${YELLOW}SOCKS5:${NC}         127.0.0.1:10808"
echo -e "  ${YELLOW}HTTP(S):${NC}        127.0.0.1:10809"
echo ""
echo -e "  ${YELLOW}Включить/выключить прокси:${NC}"
echo -e "    ~/.config/v2rayN/proxy-toggle.sh {on|off|status}"
echo ""
echo -e "  ${YELLOW}Обновить подписки:${NC}  v2rayn → Подписки → Обновить все"
echo -e "  ${YELLOW}Обновить правила:${NC}    bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)"
echo ""
