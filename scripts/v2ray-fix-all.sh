#!/bin/bash
# v2ray-fix-all.sh — Полная диагностика и автоисправление v2rayN/Xray

set -uo pipefail

# Цвета
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

# Пути
XRAY_BIN="$HOME/.local/share/v2rayN/bin/xray/xray"
CONFIG="$HOME/.config/v2rayN/config.json"
XRAY_DIR="$HOME/.local/share/v2rayN/bin/xray"
BIN_DIR="$HOME/.local/share/v2rayN/bin"

echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Полная диагностика и исправление v2rayN/Xray   ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
echo -e "Дата: $(date '+%Y-%m-%d %H:%M:%S')"

# ─── 1. Проверка бинарников ───────────────────────────────────────
step "1. Проверка бинарников"
if [[ -x "$XRAY_BIN" ]]; then
    ok "Xray найден: $XRAY_BIN"
    ver=$("$XRAY_BIN" version 2>/dev/null | head -1)
    ok "Версия: $ver"
else
    fail "Xray не найден: $XRAY_BIN"
    echo -e "  ${Y}Установите v2rayN через install.sh${N}"
    exit 1
fi

# ─── 2. Симлинки geosite.dat/geoip.dat ────────────────────────────
step "2. Проверка симлинков geosite.dat/geoip.dat"
if [[ -f "$XRAY_DIR/geosite.dat" ]] || [[ -L "$XRAY_DIR/geosite.dat" ]]; then
    ok "geosite.dat уже есть"
else
    warn "Создаю симлинки..."
    ln -sf ../geosite.dat ../geoip.dat "$XRAY_DIR/"
    ok "Симлинки созданы"
fi

# ─── 3. Проверка конфига ──────────────────────────────────────────
step "3. Проверка конфига"
if [[ ! -f "$CONFIG" ]]; then
    fail "Конфиг не найден: $CONFIG"
    exit 1
fi

if ! jq empty "$CONFIG" 2>/dev/null; then
    fail "JSON невалиден!"
    exit 1
fi
ok "JSON валиден"

# Проверяем outbound proxy
if ! jq -e '.outbounds[] | select(.tag=="proxy")' "$CONFIG" >/dev/null 2>&1; then
    fail "Outbound 'proxy' не найден"
    exit 1
fi

# Проверяем, что proxy не freedom
proxy_proto=$(jq -r '.outbounds[] | select(.tag=="proxy") | .protocol' "$CONFIG")
if [[ "$proxy_proto" == "freedom" ]]; then
    warn "Outbound 'proxy' использует freedom (прямое подключение)"
    echo -e "  ${Y}Нужно добавить сервер через GUI или вручную${N}"
    echo -e "  ${Y}Запусти: ~/.local/bin/v2rayn &${N}"
fi

# ─── 4. Создание xray.service ─────────────────────────────────────
step "4. Проверка systemd юнитов"
if [[ ! -f "$HOME/.config/systemd/user/xray.service" ]]; then
    warn "Создаю xray.service..."
    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/xray.service" << 'SERVICE'
[Unit]
Description=Xray Core
After=network.target

[Service]
Type=simple
ExecStart=%h/.local/share/v2rayN/bin/xray/xray run -config %h/.config/v2rayN/config.json
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=default.target
SERVICE
    ok "xray.service создан"
fi

# Отключаем v2rayn.service если есть
if systemctl --user is-enabled v2rayn.service 2>/dev/null | grep -q enabled; then
    warn "Отключаю v2rayn.service (GUI не работает в systemd)..."
    systemctl --user disable --now v2rayn.service 2>/dev/null || true
fi

# ─── 5. Исправление правил роутинга ───────────────────────────────
step "5. Исправление правил роутинга"
warn "Устанавливаю стандартные правила роутинга..."
cp "$CONFIG" "${CONFIG}.bak-routing"

jq '.routing.rules = [
  {"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"},
  {"type":"field","domain":["geosite:google","geosite:twitter","geosite:facebook","geosite:telegram","geosite:youtube","geosite:github","geosite:openai","geosite:instagram","geosite:whatsapp"],"outboundTag":"proxy"},
  {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
  {"type":"field","domain":["geosite:private","geosite:cn"],"outboundTag":"direct"},
  {"type":"field","ip":["geoip:ru"],"outboundTag":"direct"},
  {"type":"field","domain":["geosite:ru"],"outboundTag":"direct"},
  {"type":"field","port":"0-65535","outboundTag":"proxy"}
]' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

ok "Правила роутинга обновлены"

# ─── 6. Запуск xray.service ───────────────────────────────────────
step "6. Запуск xray.service"
systemctl --user daemon-reload
systemctl --user enable --now xray.service
sleep 3

if systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null; then
    ok "Xray запущен"
else
    fail "Xray не запустился"
    echo -e "  ${Y}Логи:${N}"
    journalctl --user -u xray.service --no-pager -n 10 | sed 's/^/    /'
fi

# ─── 7. Системный прокси ──────────────────────────────────────────
step "7. Настройка системного прокси"
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
gsettings set org.gnome.system.proxy.socks port 10808
gsettings set org.gnome.system.proxy.http host '127.0.0.1'
gsettings set org.gnome.system.proxy.http port 10809
gsettings set org.gnome.system.proxy.https host '127.0.0.1'
gsettings set org.gnome.system.proxy.https port 10809
ok "Системный прокси настроен"

# ─── 8. Финальная проверка ────────────────────────────────────────
step "8. Финальная проверка"

# Порты
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

# IP
direct_ip=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
proxy_ip=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null)

echo -e "  Прямой IP: ${C}$direct_ip${N}"
echo -e "  IP через прокси: ${C}$proxy_ip${N}"

if [[ -n "$direct_ip" && -n "$proxy_ip" && "$direct_ip" != "$proxy_ip" ]]; then
    ok "IP разные — прокси работает!"
else
    fail "IP одинаковые — прокси не работает"
fi

# Сайты
if curl -s -m 5 https://gosuslugi.ru -o /dev/null 2>/dev/null; then
    ok "Госуслуги работают (напрямую)"
else
    warn "Госуслуги недоступны"
fi

if curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://google.com -o /dev/null 2>/dev/null; then
    ok "Google через прокси работает"
else
    fail "Google через прокси не работает"
fi

# ─── Итог ──────────────────────────────────────────────────────────
echo -e "\n${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  ИТОГ                                           ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"

if systemctl --user is-active --quiet xray.service 2>/dev/null && [[ "$direct_ip" != "$proxy_ip" ]]; then
    echo -e "${G}✅ ВСЁ РАБОТАЕТ!${N}"
    echo -e "${G}   Прямой IP: $direct_ip${N}"
    echo -e "${G}   IP через прокси: $proxy_ip${N}"
else
    echo -e "${R}❌ Есть проблемы${N}"
    echo -e "${Y}   Проверьте логи: journalctl --user -u xray.service -n 20${N}"
fi

echo -e "\n${B}Полезные команды:${N}"
echo -e "  ${C}./netcheck.sh${N}              # Полная диагностика"
echo -e "  ${C}systemctl --user status xray${N}  # Статус сервиса"
echo -e "  ${C}systemctl --user restart xray${N} # Перезапуск"
echo -e "  ${C}gsettings set org.gnome.system.proxy mode none${N}  # Выключить прокси"
