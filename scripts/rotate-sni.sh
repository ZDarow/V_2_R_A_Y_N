#!/bin/bash
# rotate-sni.sh — смена SNI для обхода SNI-блокировок
# Выбирает случайный домен из whitelist-списка и применяет его
# к outbound-proxy в конфиге Xray, после чего перезапускает сервис.
# ============================================================================

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
info() { echo -e "  ${C}ℹ${N} $*"; }

CONFIG="${CONFIG:-$HOME/.config/v2rayN/config.json}"
BACKUP="${CONFIG}.before-rotate"
SNI_FILE="${SNI_FILE:-$HOME/.config/v2rayN/sni-whitelist.txt}"

# Встроенный whitelist (на случай отсутствия файла)
DEFAULT_SNIS=(
    "yandex.ru" "vk.com" "mail.ru" "gosuslugi.ru"
    "ok.ru" "rkn.gov.ru" "xn--80af2al1c.xn--p1ai"
    "sberbank.ru" "mos.ru" "nalog.ru" "cbr.ru"
)

# ─── Парсинг аргументов ────────────────────────────────────────────
show_help() {
    echo "Использование: $0 [--help | --list | --set <domain> | --file <path>]"
    echo ""
    echo "  --help           Показать справку"
    echo "  --list           Показать доступные SNI домены"
    echo "  --set <domain>   Установить конкретный SNI"
    echo "  --file <path>    Указать свой файл со списком SNI"
    echo ""
    echo "Без аргументов: выбирает случайный SNI из файла/встроенного списка"
    exit 0
}

select_random_sni() {
    local snis=("${DEFAULT_SNIS[@]}")
    if [[ -f "$SNI_FILE" ]]; then
        mapfile -t snis < "$SNI_FILE"
    fi
    echo "${snis[$RANDOM % ${#snis[@]}]}"
}

list_snis() {
    if [[ -f "$SNI_FILE" ]]; then
        info "SNI из файла $SNI_FILE:"
        cat "$SNI_FILE"
    else
        info "Встроенный SNI whitelist:"
        printf '%s\n' "${DEFAULT_SNIS[@]}"
    fi
    exit 0
}

SNI=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)    show_help ;;
        --list)    list_snis ;;
        --set)     SNI="$2"; shift ;;
        --file)    SNI_FILE="$2"; shift ;;
        *)         echo "Неизвестный аргумент: $1"; show_help ;;
    esac
    shift
done

# ─── Основная логика ───────────────────────────────────────────────

if [[ -z "$SNI" ]]; then
    SNI=$(select_random_sni)
fi

echo -e "${C}━━━ Ротация SNI ━━━${N}"
info "Новый SNI: ${B}$SNI${N}"

# Бэкап
cp "$CONFIG" "$BACKUP" 2>/dev/null || true

# Применение SNI ко всем outbound с тегом "proxy"
if ! jq --arg sni "$SNI" '
    .outbounds |= map(
        if .tag == "proxy" then
            if .streamSettings.realitySettings then
                .streamSettings.realitySettings.serverName = $sni
            elif .streamSettings.tlsSettings then
                .streamSettings.tlsSettings.serverName = $sni
            elif .streamSettings.wsSettings then
                .streamSettings.wsSettings.headers.Host = $sni
            else . end
        else . end
    )
' "$CONFIG" > /tmp/config.tmp 2>/dev/null; then
    fail "Ошибка применения SNI"
    exit 1
fi

mv /tmp/config.tmp "$CONFIG"
ok "SNI применён: $SNI"

# Перезапуск Xray
if systemctl --user is-active --quiet xray.service 2>/dev/null; then
    systemctl --user restart xray.service 2>/dev/null
    sleep 2
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        ok "Xray перезапущен"
    else
        fail "Xray не запустился, восстанавливаю бэкап..."
        cp "$BACKUP" "$CONFIG"
        systemctl --user restart xray.service
        exit 1
    fi
elif pgrep -x xray >/dev/null; then
    pkill -x xray 2>/dev/null
    sleep 1
    ok "Xray (standalone) перезапущен"
else
    warn "Xray не запущен, конфиг обновлён"
fi

echo ""
echo -e "${G}✅ SNI сменён на: $SNI${N}"
echo -e "${Y}Бэкап: $BACKUP${N}"
