#!/bin/bash
set -e
# v2rayN Russia Setup — установочный скрипт

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V2RAYN_CONFIG_DIR="$HOME/.config/v2rayN"
V2RAYN_BIN_DIR="$HOME/.local/share/v2rayN/bin"
V2RAYN_BINCONFIG_DIR="$HOME/.local/share/v2rayN/binConfigs"

info "Проверка установки v2rayN..."
if ! command -v v2rayn &>/dev/null && ! [ -f /opt/v2rayN/v2rayN ]; then
    error "v2rayN не установлен! Скачайте .deb с https://github.com/2dust/v2rayN/releases"
fi
info "v2rayN найден"

info "Установка правил роутинга из runetfreedom/russia-v2ray-rules-dat..."
RULES_DIR="/tmp/russia-v2ray-rules-dat"
if [ ! -d "$RULES_DIR" ]; then
    git clone --depth=1 https://github.com/runetfreedom/russia-v2ray-rules-dat.git "$RULES_DIR"
fi

mkdir -p "$V2RAYN_BIN_DIR"
cp -f "$RULES_DIR/geoip.dat" "$V2RAYN_BIN_DIR/geoip.dat"
cp -f "$RULES_DIR/geosite.dat" "$V2RAYN_BIN_DIR/geosite.dat"
info "Правила geoip/geosite установлены"

info "Установка конфигурации роутинга..."
mkdir -p "$V2RAYN_CONFIG_DIR"
cp -f "$SCRIPT_DIR/config/routing-russia.json" "$V2RAYN_CONFIG_DIR/routing-russia.json"

info "Установка шаблона Xray-core..."
mkdir -p "$V2RAYN_BINCONFIG_DIR"
cp -f "$SCRIPT_DIR/config/config-template-xray.json" "$V2RAYN_BINCONFIG_DIR/config-template-xray.json"

info "Установка скриптов управления прокси..."
cp -f "$SCRIPT_DIR/scripts/proxy-toggle.sh" "$V2RAYN_CONFIG_DIR/proxy-toggle.sh"
cp -f "$SCRIPT_DIR/scripts/proxy_set_linux_sh.sh" "$V2RAYN_BINCONFIG_DIR/proxy_set_linux_sh.sh"
chmod +x "$V2RAYN_CONFIG_DIR/proxy-toggle.sh"
chmod +x "$V2RAYN_BINCONFIG_DIR/proxy_set_linux_sh.sh"

info "Импорт подписок в v2rayN..."
DB_PATH="$HOME/.local/share/v2rayN/guiConfigs/guiNDB.db"
if [ -f "$DB_PATH" ]; then
    cp "$DB_PATH" "${DB_PATH}.bak.pre-import.$(date +%Y%m%d)"
    sqlite3 "$DB_PATH" <<'SQL'
INSERT OR IGNORE INTO SubItem (Id, Remarks, Url, MoreUrl, Enabled, Sort, AutoUpdateInterval, ConvertTarget)
VALUES
  ('BLACK-RUS-001', 'Чёрные списки РФ (весь трафик через VPN)',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt\r\nhttps://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt',
   1, 1, 1440, 'v2ray'),
  ('WHITE-RUS-001', 'Белые списки РФ (только РФ через VPN)',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt',
   'https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile-2.txt\r\nhttps://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt\r\nhttps://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-checked.txt\r\nhttps://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-SNI-RU-all.txt',
   1, 2, 1440, 'v2ray'),
  ('WL-ZIENG2-001', 'WL Белый список (zieng2)',
   'https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt',
   'https://codeberg.org/zieng2/wl/raw/branch/main/vless_universal.txt',
   1, 3, 60, 'v2ray');
SQL
    info "Подписки импортированы в базу v2rayN"
else
    warn "База данных v2rayN не найдена. Подписки не импортированы."
fi

info "Настройка системного прокси..."
if command -v gsettings &>/dev/null; then
    bash "$V2RAYN_CONFIG_DIR/proxy-toggle.sh" on 2>/dev/null || warn "Не удалось настроить системный прокси"
fi

info "Установка завершена!"
echo ""
echo "═══════════════════════════════════════════"
echo "  v2rayN успешно настроен для работы в РФ"
echo "═══════════════════════════════════════════"
echo ""
echo "Запуск:          v2rayn"
echo "Прокси SOCKS:    127.0.0.1:10808"
echo "Прокси HTTP:     127.0.0.1:10809"
echo ""
echo "Управление прокси:"
echo "  on/off/status   ~/.config/v2rayN/proxy-toggle.sh"
echo ""
echo "Обновление подписок: v2rayn → Подписки → Обновить все"
echo "Обновление правил:   ./scripts/update-rules.sh"
