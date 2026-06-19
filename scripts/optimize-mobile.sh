#!/bin/bash
# optimize-mobile.sh — Безопасная оптимизация для мобильного интернета

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

CONFIG="$HOME/.config/v2rayN/config.json"

echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Оптимизация для мобильного интернета            ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"

# ─── 1. Создание бэкапа ───────────────────────────────────────────
step "1. Создание бэкапа"
cp "$CONFIG" "${CONFIG}.before-optimize"
ok "Бэкап создан: config.json.before-optimize"

# ─── 2. Оптимизация MTU ───────────────────────────────────────────
step "2. Оптимизация MTU"
interface=$(ip route show default | awk '{print $5}' | head -1)
current_mtu=$(ip link show "$interface" | grep mtu | awk '{print $5}')

# Для мобильного интернета оптимально 1360-1380
target_mtu=1360

if [[ "$current_mtu" != "$target_mtu" ]]; then
    sudo ip link set dev "$interface" mtu "$target_mtu"
    ok "MTU изменён с $current_mtu на $target_mtu"
else
    ok "MTU уже $target_mtu"
fi

# ─── 3. Добавление фрагментации TLS ───────────────────────────────
step "3. Добавление фрагментации TLS (обход DPI)"

# Создаём временный файл с новыми настройками
cat > /tmp/sockopt.json << 'JSONEOF'
{
  "tcpFastOpen": true,
  "tcpKeepAliveIdle": 45,
  "tcpKeepAliveInterval": 15,
  "tcpUserTimeout": 10000,
  "tcpcongestion": "bbr"
}
JSONEOF

# Применяем sockopt к outbound proxy
if jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.sockopt' "$CONFIG" >/dev/null 2>&1; then
    warn "sockopt уже есть, пропускаем"
else
    jq --slurpfile sockopt /tmp/sockopt.json '.outbounds |= map(if .tag == "proxy" then .streamSettings.sockopt = $sockopt[0] else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "Добавлены TCP оптимизации (FastOpen, KeepAlive, BBR)"
fi

# ─── 4. Добавление маскировки Host ────────────────────────────────
step "4. Добавление маскировки Host (обход SNI-блокировок)"

if jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.wsSettings.headers.Host' "$CONFIG" >/dev/null 2>&1; then
    warn "Host header уже есть, пропускаем"
else
    jq '.outbounds |= map(if .tag == "proxy" then .streamSettings.wsSettings.headers = {"Host": "www.google.com"} else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "Добавлен Host header: www.google.com"
fi

# ─── 5. Проверка валидности ───────────────────────────────────────
step "5. Проверка валидности конфига"
if jq empty "$CONFIG" 2>/dev/null; then
    ok "JSON валиден"
else
    fail "JSON сломан! Восстанавливаю бэкап..."
    cp "${CONFIG}.before-optimize" "$CONFIG"
    exit 1
fi

# ─── 6. Перезапуск xray ───────────────────────────────────────────
step "6. Перезапуск xray.service"
systemctl --user restart xray.service
sleep 3

if systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null; then
    ok "Xray перезапущен"
else
    fail "Xray не запустился! Восстанавливаю бэкап..."
    cp "${CONFIG}.before-optimize" "$CONFIG"
    systemctl --user restart xray.service
    exit 1
fi

# ─── 7. Тест скорости ─────────────────────────────────────────────
step "7. Тест скорости"
speed=$(curl -s -o /dev/null -w "%{speed_download}" -m 10 http://speedtest.tele2.net/1MB.zip 2>/dev/null)
if [[ -n "$speed" && "$speed" != "0" ]]; then
    speed_mb=$(echo "scale=2; $speed / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
    ok "Скорость: ${speed_mb} MB/s"
else
    warn "Не удалось измерить скорость"
fi

# ─── 8. Финальная проверка ────────────────────────────────────────
step "8. Финальная проверка"
proxy_ip=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null)
if [[ -n "$proxy_ip" ]]; then
    ok "IP через прокси: $proxy_ip"
else
    fail "Прокси не отвечает"
fi

# ─── Итог ──────────────────────────────────────────────────────────
echo -e "\n${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  ИТОГ                                           ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"

if systemctl --user is-active --quiet xray.service 2>/dev/null && [[ -n "$proxy_ip" ]]; then
    echo -e "${G}✅ ОПТИМИЗАЦИЯ ПРИМЕНЕНА!${N}"
    echo -e "${G}   MTU: $target_mtu${N}"
    echo -e "${G}   TCP оптимизации: FastOpen, KeepAlive, BBR${N}"
    echo -e "${G}   Маскировка Host: www.google.com${N}"
    echo -e "${G}   IP через прокси: $proxy_ip${N}"
else
    echo -e "${R}❌ Оптимизация не удалась${N}"
    echo -e "${Y}   Восстановлен бэкап: config.json.before-optimize${N}"
fi

echo -e "\n${B}Если что-то сломалось, восстанови бэкап:${N}"
echo -e "  ${C}cp ~/.config/v2rayN/config.json.before-optimize ~/.config/v2rayN/config.json${N}"
echo -e "  ${C}systemctl --user restart xray.service${N}"
