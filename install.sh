#!/bin/bash
# shellcheck disable=SC2317
set -euo pipefail

# v2rayN Russia Setup — полностью автоматизированный установщик
# Использование:
#   curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh | bash
#   или
#   ./install.sh [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]

REPO_URL="${REPO_URL:-https://github.com/ZDarow/V_2_R_A_Y_N.git}"

# ---- Цвета и утилиты ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- Парсинг аргументов ----
FORCE_REINSTALL=false
SKIP_V2RAYN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-reinstall) FORCE_REINSTALL=true; shift ;;
    --skip-v2rayn) SKIP_V2RAYN=true; shift ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    *) shift ;;
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
if [ "$EUID" -eq 0 ]; then
  error "Не запускайте скрипт от root. Используйте обычного пользователя (sudo будет запрошен по мере необходимости)."
fi

# ---- Режимы работы ----
# Определяем, откуда запущен скрипт: из локального репозитория или из pipe
if [ -f "${BASH_SOURCE[0]}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/config/routing-russia.json" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
if command -v apt-get &>/dev/null; then
  sudo apt-get update -qq 2>/dev/null || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git wget curl sqlite3 ca-certificates 2>/dev/null || warn "Некоторые зависимости не установлены"
elif command -v dnf &>/dev/null; then
  sudo dnf install -y -q git wget curl sqlite ca-certificates 2>/dev/null || warn "Некоторые зависимости не установлены"
elif command -v pacman &>/dev/null; then
  sudo pacman -S --noconfirm --needed git wget curl sqlite ca-certificates 2>/dev/null || warn "Некоторые зависимости не установлены"
else
  warn "Не удалось определить пакетный менеджер. Установите git, wget, curl, sqlite3 вручную."
fi

# ---- 2. Установка .NET Runtime (если не установлен) ----
header "Проверка .NET Runtime"
if command -v dotnet &>/dev/null; then
  info ".NET Runtime найден: $(dotnet --version 2>/dev/null)"
else
  warn ".NET Runtime не найден. v2rayN требует .NET 8.0+."
  if command -v apt-get &>/dev/null; then
    info "Установка dotnet-runtime-8.0..."
    sudo apt-get install -y -qq dotnet-runtime-8.0 2>/dev/null || warn "Не удалось установить .NET через apt. Установите вручную: https://dotnet.microsoft.com/download"
  else
    warn "Установите .NET Runtime 8.0+ вручную: https://dotnet.microsoft.com/download"
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
        | grep "browser_download_url.*linux-${DEB_ARCH}\.deb" | head -1 | cut -d'"' -f4 || true)
    fi
    if [ -z "$LATEST" ]; then
      LATEST="https://github.com/2dust/v2rayN/releases/latest/download/v2rayN-linux-${DEB_ARCH}.deb"
      warn "GitHub API недоступен. Использую прямой URL (может быть неактуальным)."
    fi
    info "Загрузка v2rayN: $LATEST"
    wget -q --show-progress -O /tmp/v2rayN.deb "$LATEST" 2>/dev/null || curl -sSL -o /tmp/v2rayN.deb "$LATEST"
    if [ ! -f /tmp/v2rayN.deb ] || [ ! -s /tmp/v2rayN.deb ]; then
      error "Не удалось загрузить v2rayN. Проверьте соединение."
    fi
    sudo dpkg -i /tmp/v2rayN.deb 2>/dev/null || true
    sudo apt-get install -f -y -qq 2>/dev/null || true
    rm -f /tmp/v2rayN.deb
    if command -v v2rayn &>/dev/null; then
      info "v2rayN установлен: $(v2rayn --version 2>/dev/null || true)"
    else
      warn "v2rayN установлен, но команда 'v2rayn' не найдена в PATH. Проверьте /opt/v2rayN/"
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
RULES_SRC="$SCRIPT_DIR/rules"
if [ ! -f "$RULES_SRC/geoip.dat" ] || [ ! -f "$RULES_SRC/geosite.dat" ]; then
  info "Правила не найдены в репозитории. Клонирование runetfreedom/russia-v2ray-rules-dat..."
  TMP_RULES=$(mktemp -d)
  if git clone --depth=1 https://github.com/runetfreedom/russia-v2ray-rules-dat.git "$TMP_RULES/rules" 2>/dev/null; then
    cp -f "$TMP_RULES/rules/geoip.dat" "$V2RAYN_BIN_DIR/geoip.dat" 2>/dev/null || warn "geoip.dat не найден"
    cp -f "$TMP_RULES/rules/geosite.dat" "$V2RAYN_BIN_DIR/geosite.dat" 2>/dev/null || warn "geosite.dat не найден"
    rm -rf "$TMP_RULES"
    info "Правила geoip/geosite установлены"
  else
    rm -rf "$TMP_RULES"
    warn "Не удалось клонировать правила. Проверьте подключение."
  fi
else
  cp -f "$RULES_SRC/geoip.dat" "$V2RAYN_BIN_DIR/geoip.dat"
  cp -f "$RULES_SRC/geosite.dat" "$V2RAYN_BIN_DIR/geosite.dat"
  info "Правила geoip/geosite установлены из репозитория"
fi

# ---- 6. Конфигурация роутинга и Xray ----
header "Установка конфигурации"
if [ -f "$SCRIPT_DIR/config/routing-russia.json" ]; then
  cp -f "$SCRIPT_DIR/config/routing-russia.json" "$V2RAYN_CONFIG_DIR/routing-russia.json"
  info "routing-russia.json установлен"
fi
if [ -f "$SCRIPT_DIR/config/config-template-xray.json" ]; then
  cp -f "$SCRIPT_DIR/config/config-template-xray.json" "$V2RAYN_BINCONFIG_DIR/config-template-xray.json"
  info "config-template-xray.json установлен"
fi

# ---- 7. Скрипты управления ----
header "Установка скриптов управления"
if [ -f "$SCRIPT_DIR/scripts/proxy-toggle.sh" ]; then
  cp -f "$SCRIPT_DIR/scripts/proxy-toggle.sh" "$V2RAYN_CONFIG_DIR/proxy-toggle.sh"
  chmod +x "$V2RAYN_CONFIG_DIR/proxy-toggle.sh"
fi
if [ -f "$SCRIPT_DIR/scripts/proxy_set_linux_sh.sh" ]; then
  cp -f "$SCRIPT_DIR/scripts/proxy_set_linux_sh.sh" "$V2RAYN_BINCONFIG_DIR/proxy_set_linux_sh.sh"
  chmod +x "$V2RAYN_BINCONFIG_DIR/proxy_set_linux_sh.sh"
fi
info "Скрипты управления установлены"

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
   1, 3, 60, 'v2ray');
SQL
  info "Подписки импортированы в БД v2rayN"
else
  warn "sqlite3 не найден. Подписки не импортированы (можно импортировать вручную в GUI)."
fi

# ---- 9. Настройка системного прокси ----
header "Настройка системного прокси"
if command -v gsettings &>/dev/null; then
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
  "$KWC" --file kioslaverc --group "Proxy Settings" --key socksProxy "http://127.0.0.1:10808" 2>/dev/null || true
  "$KWC" --file kioslaverc --group "Proxy Settings" --key NoProxyFor "localhost,127.0.0.0/8,::1,*.local,.ru,.su,.xn--p1ai" 2>/dev/null || true
  dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
  info "Системный прокси настроен (KDE Plasma)"
else
  warn "Не удалось настроить системный прокси (только GNOME/KDE). Настройте вручную: HTTP 127.0.0.1:10809, SOCKS 127.0.0.1:10808"
fi

# ---- 10. Очистка временных файлов ----
if [ "$LOCAL_MODE" = false ] && [ -n "${CLONE_DIR:-}" ]; then
  rm -rf "$CLONE_DIR"
fi

# ---- 11. Завершение ----
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
echo -e "  ${YELLOW}Обновить правила:${NC}    ${SCRIPT_DIR}/scripts/update-rules.sh  (или из репозитория)"
echo ""
