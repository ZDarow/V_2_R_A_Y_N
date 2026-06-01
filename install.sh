#!/bin/bash
set -euo pipefail

# v2rayN Russia Setup — полностью автоматизированный установщик
# Использование:
#   curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh | bash
#   или
#   ./install.sh [--force-reinstall] [--skip-v2rayn]

# ---- Цвета и утилиты ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- Парсинг аргументов ----
FORCE_REINSTALL=false
SKIP_V2RAYN=false
for arg in "$@"; do
  case "$arg" in
    --force-reinstall) FORCE_REINSTALL=true ;;
    --skip-v2rayn) SKIP_V2RAYN=true ;;
  esac
done

# ---- Определение системы ----
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  DEB_ARCH="64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *) error "Неподдерживаемая архитектура: $ARCH" ;;
esac

# ---- Root-проверка ----
if [ "$EUID" -eq 0 ]; then
  error "Не запускайте скрипт от root. Используйте обычного пользователя (sudo будет запрошен по мере необходимости)."
fi

# ---- 1. Установка зависимостей ----
header "Установка системных зависимостей"
sudo apt-get update -qq
sudo apt-get install -y -qq git wget curl sqlite3 gsettings-desktop-schemas libglib2.0-bin 2>/dev/null || true

# ---- 2. Установка v2rayN ----
if [ "$SKIP_V2RAYN" = false ]; then
  if command -v v2rayn &>/dev/null && [ "$FORCE_REINSTALL" = false ]; then
    info "v2rayN уже установлен (пропускаем, используйте --force-reinstall для переустановки)"
  else
    header "Установка v2rayN"
    LATEST=$(curl -sSL https://api.github.com/repos/2dust/v2rayN/releases/latest 2>/dev/null | grep "browser_download_url.*linux-${DEB_ARCH}.deb" | head -1 | cut -d'"' -f4)
    if [ -z "$LATEST" ]; then
      # Fallback: прямой URL последнего релиза
      LATEST="https://github.com/2dust/v2rayN/releases/latest/download/v2rayN-linux-${DEB_ARCH}.deb"
    fi
    info "Загрузка: $LATEST"
    wget -q --show-progress -O /tmp/v2rayN.deb "$LATEST"
    sudo dpkg -i /tmp/v2rayN.deb 2>/dev/null || sudo apt-get install -f -y -qq
    rm -f /tmp/v2rayN.deb
    info "v2rayN установлен"
  fi
fi

# ---- 3. Директории ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2RAYN_CONFIG_DIR="$HOME/.config/v2rayN"
V2RAYN_BIN_DIR="$HOME/.local/share/v2rayN/bin"
V2RAYN_BINCONFIG_DIR="$HOME/.local/share/v2rayN/binConfigs"
V2RAYN_GUICONFIG_DIR="$HOME/.local/share/v2rayN/guiConfigs"
mkdir -p "$V2RAYN_CONFIG_DIR" "$V2RAYN_BIN_DIR" "$V2RAYN_BINCONFIG_DIR" "$V2RAYN_GUICONFIG_DIR"

# ---- 4. Правила роутинга (geoip/geosite) ----
header "Установка правил geoip/geosite"
if [ ! -d /tmp/russia-v2ray-rules-dat ]; then
  git clone --depth=1 https://github.com/runetfreedom/russia-v2ray-rules-dat.git /tmp/russia-v2ray-rules-dat 2>/dev/null
fi
cp -f /tmp/russia-v2ray-rules-dat/geoip.dat "$V2RAYN_BIN_DIR/geoip.dat" 2>/dev/null || warn "geoip.dat не найден"
cp -f /tmp/russia-v2ray-rules-dat/geosite.dat "$V2RAYN_BIN_DIR/geosite.dat" 2>/dev/null || warn "geosite.dat не найден"
info "Правила установлены"

# ---- 5. Конфигурация роутинга и Xray ----
header "Установка конфигурации"
if [ -f "$SCRIPT_DIR/config/routing-russia.json" ]; then
  cp -f "$SCRIPT_DIR/config/routing-russia.json" "$V2RAYN_CONFIG_DIR/routing-russia.json"
  info "routing-russia.json установлен"
fi
if [ -f "$SCRIPT_DIR/config/config-template-xray.json" ]; then
  cp -f "$SCRIPT_DIR/config/config-template-xray.json" "$V2RAYN_BINCONFIG_DIR/config-template-xray.json"
  info "config-template-xray.json установлен"
fi

# ---- 6. Скрипты управления ----
header "Установка скриптов управления"
if [ -f "$SCRIPT_DIR/scripts/proxy-toggle.sh" ]; then
  cp -f "$SCRIPT_DIR/scripts/proxy-toggle.sh" "$V2RAYN_CONFIG_DIR/proxy-toggle.sh"
  chmod +x "$V2RAYN_CONFIG_DIR/proxy-toggle.sh"
fi
if [ -f "$SCRIPT_DIR/scripts/proxy_set_linux_sh.sh" ]; then
  cp -f "$SCRIPT_DIR/scripts/proxy_set_linux_sh.sh" "$V2RAYN_BINCONFIG_DIR/proxy_set_linux_sh.sh"
  chmod +x "$V2RAYN_BINCONFIG_DIR/proxy_set_linux_sh.sh"
fi
info "Скрипты установлены"

# ---- 7. Импорт подписок в БД v2rayN ----
header "Импорт подписок в v2rayN"
DB_PATH="$V2RAYN_GUICONFIG_DIR/guiNDB.db"

# Убедимся что sqlite3 доступен
if command -v sqlite3 &>/dev/null; then
  # Создаём БД и таблицу если нет
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

  # Импорт подписок
  sqlite3 "$DB_PATH" <<'SQL'
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
  warn "sqlite3 не найден. Подписки не импортированы (можно импортировать вручную в GUI)"
fi

# ---- 8. Настройка системного прокси ----
header "Настройка системного прокси"
if command -v gsettings &>/dev/null; then
  gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.http port 10809 2>/dev/null || true
  gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
  gsettings set org.gnome.system.proxy.socks port 10808 2>/dev/null || true
  IGNORE="['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']"
  gsettings set org.gnome.system.proxy ignore-hosts "$IGNORE" 2>/dev/null || true
  info "Системный прокси настроен (GNOME/Cinnamon/XFCE)"
fi

# ---- 9. Завершение ----
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
echo -e "  ${YELLOW}Обновить правила:${NC}    ./scripts/update-rules.sh"
echo ""
