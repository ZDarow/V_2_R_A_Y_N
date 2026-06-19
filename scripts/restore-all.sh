#!/bin/bash
# restore-all.sh — Восстановление работоспособности v2rayN/Xray

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

CONFIG="$HOME/.config/v2rayN/config.json"

echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Восстановление работоспособности v2rayN/Xray   ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"

# ─── 1. Отключение системного прокси ──────────────────────────────
step "1. Отключение системного прокси"
gsettings set org.gnome.system.proxy mode 'none'
ok "Системный прокси отключён"

# ─── 2. Восстановление конфига ────────────────────────────────────
step "2. Восстановление конфига из бэкапа"

# Ищем последний рабочий бэкап
if [[ -f "${CONFIG}.bak-routing" ]]; then
    cp "${CONFIG}.bak-routing" "$CONFIG"
    ok "Восстановлен из config.json.bak-routing"
elif [[ -f "${CONFIG}.bak" ]]; then
    cp "${CONFIG}.bak" "$CONFIG"
    ok "Восстановлен из config.json.bak"
elif [[ -f "${CONFIG}.bak-opt" ]]; then
    cp "${CONFIG}.bak-opt" "$CONFIG"
    ok "Восстановлен из config.json.bak-opt"
elif [[ -f "${CONFIG}.bak-sni" ]]; then
    cp "${CONFIG}.bak-sni" "$CONFIG"
    ok "Восстановлен из config.json.bak-sni"
else
    fail "Бэкапы не найдены!"
    echo -e "  ${Y}Создаю минимальный рабочий конфиг...${N}"
    cat > "$CONFIG" << 'JSONEOF'
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {"port": 10808, "protocol": "socks", "settings": {"auth": "noauth", "udp": true}},
    {"port": 10809, "protocol": "http", "settings": {}}
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [{
          "address": "109.120.150.94",
          "port": 8443,
          "users": [{"id": "a825e98c-c6e9-4770-bdaa-bc1f4b1199f8", "alterId": 0, "security": "auto"}]
        }]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/websocket"}
      }
    },
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block"},
      {"type": "field", "ip": ["geoip:private"], "outboundTag": "direct"},
      {"type": "field", "port": "0-65535", "outboundTag": "proxy"}
    ]
  }
}
JSONEOF
    ok "Минимальный конфиг создан"
fi

# Проверка валидности
if jq empty "$CONFIG" 2>/dev/null; then
    ok "JSON валиден"
else
    fail "JSON невалиден! Требуется ручное вмешательство"
    exit 1
fi

# ─── 3. Восстановление MTU ────────────────────────────────────────
step "3. Восстановление MTU"
interface=$(ip route show default | awk '{print $5}' | head -1)
current_mtu=$(ip link show "$interface" | grep mtu | awk '{print $5}')

if [[ "$current_mtu" != "1400" ]]; then
    sudo ip link set dev "$interface" mtu 1400
    ok "MTU изменён с $current_mtu на 1400"
else
    ok "MTU уже 1400"
fi

# ─── 4. Перезапуск xray ───────────────────────────────────────────
step "4. Перезапуск xray.service"
systemctl --user daemon-reload
systemctl --user restart xray.service
sleep 3

if systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null; then
    ok "Xray запущен"
else
    fail "Xray не запустился"
    echo -e "  ${Y}Логи:${N}"
    journalctl --user -u xray.service --no-pager -n 10 | sed 's/^/    /'
    exit 1
fi

# ─── 5. Проверка портов ───────────────────────────────────────────
step "5. Проверка портов"
if ss -tln 2>/dev/null | grep -q ":10808 "; then
    ok "Порт 10808 слушается"
else
    fail "Порт 10808 не слушается"
fi

if ss -tln 2>/dev/null | grep -q ":10809 "; then
    ok "Порт 10809 слушается"
else
    fail "Порт 10809 не слушается"
fi

# ─── 6. Проверка прокси ───────────────────────────────────────────
step "6. Проверка прокси"
proxy_ip=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null)
if [[ -n "$proxy_ip" ]]; then
    ok "IP через прокси: $proxy_ip"
else
    fail "Прокси не отвечает"
fi

# ─── 7. Включение системного прокси ───────────────────────────────
step "7. Включение системного прокси"
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
gsettings set org.gnome.system.proxy.socks port 10808
gsettings set org.gnome.system.proxy.http host '127.0.0.1'
gsettings set org.gnome.system.proxy.http port 10809
gsettings set org.gnome.system.proxy.https host '127.0.0.1'
gsettings set org.gnome.system.proxy.https port 10809
gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '192.168.0.0/16', '10.0.0.0/8', '172.16.0.0/12', '*.local']"
ok "Системный прокси включён с исключениями"

# ─── 8. Финальная проверка ────────────────────────────────────────
step "8. Финальная проверка"

echo -e "  ${C}Тесты:${N}"
if curl -s -m 5 https://gosuslugi.ru -o /dev/null 2>/dev/null; then
    ok "Госуслуги работают"
else
    warn "Госуслуги недоступны"
fi

if curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://twitter.com -o /dev/null 2>/dev/null; then
    ok "Twitter через прокси работает"
else
    fail "Twitter через прокси не работает"
fi

# ─── Итог ──────────────────────────────────────────────────────────
echo -e "\n${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  ИТОГ                                           ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"

if systemctl --user is-active --quiet xray.service 2>/dev/null && [[ -n "$proxy_ip" ]]; then
    echo -e "${G}✅ ВСЁ ВОССТАНОВЛЕНО!${N}"
    echo -e "${G}   IP через прокси: $proxy_ip${N}"
    echo -e "${G}   MTU: 1400${N}"
    echo -e "${G}   Системный прокси: ВКЛ${N}"
else
    echo -e "${R}❌ Есть проблемы${N}"
    echo -e "${Y}   Проверьте логи: journalctl --user -u xray.service -n 20${N}"
fi

echo -e "\n${B}Полезные команды:${N}"
echo -e "  ${C}./netcheck.sh${N}              # Диагностика"
echo -e "  ${C}./mobile-netcheck.sh${N}       # Диагностика мобильного"
echo -e "  ${C}systemctl --user restart xray${N}  # Перезапуск"
echo -e "  ${C}gsettings set org.gnome.system.proxy mode none${N}  # Отключить прокси"
