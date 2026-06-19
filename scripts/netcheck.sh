#!/usr/bin/env bash
# netcheck.sh — Полная диагностика сетевого окружения для v2rayN/Xray

set -uo pipefail

# ─── Цвета ───────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; ((++ISSUES)); }
warn() { echo -e "  ${Y}!${N} $*"; ((++WARNINGS)); }
sec()  { echo -e "\n${B}━━━ $* ━━━${N}"; }

ISSUES=0; WARNINGS=0
LOG_FILE="${1:-/dev/null}"
[[ "${1:-}" == "--save" ]] && LOG_FILE="netcheck-$(date +%Y%m%d-%H%M%S).log" && exec > >(tee "$LOG_FILE") 2>&1

# ─── Заголовок ───────────────────────────────────────────────────────
echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Диагностика сети / v2rayN / Xray              ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
echo -e "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Хост: $(hostname) | OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo -e "Ядро: $(uname -r)"

# ─── 1. Systemd юниты ───────────────────────────────────────────────
sec "1. Systemd юниты"
for unit in v2rayn.service xray.service v2rayn-rules-update.timer; do
    if systemctl --user is-enabled "$unit" 2>/dev/null | grep -q enabled; then
        state=$(systemctl --user is-active "$unit" 2>/dev/null)
        if [[ "$state" == "active" ]]; then
            ok "$unit — активен"
        else
            fail "$unit — $state"
        fi
    fi
done

# ─── 2. Процессы ───────────────────────────────────────────────────
sec "2. Запущенные процессы"
for proc in v2rayn xray sing-box mihomo; do
    if pgrep -x "$proc" &>/dev/null; then
        ok "$proc (PID: $(pgrep -x "$proc" | head -1))"
    fi
done
[[ $ISSUES -eq 0 ]] && ! pgrep -x v2rayn &>/dev/null && ! pgrep -x xray &>/dev/null && \
    fail "Не запущен ни v2rayn, ни xray"

# ─── 3. Порты прокси ──────────────────────────────────────────────
sec "3. Порты прокси (10808 SOCKS / 10809 HTTP)"
for port in 10808 10809; do
    if ss -tln 2>/dev/null | grep -q ":${port} "; then
        ok "Порт $port слушается"
    else
        fail "Порт $port не слушается"
    fi
done

# ─── 4. Конфигурация ──────────────────────────────────────────────
sec "4. Конфиг v2rayN"
CONFIG="$HOME/.config/v2rayN/config.json"
if [[ -f "$CONFIG" ]]; then
    if command -v jq &>/dev/null; then
        if jq empty "$CONFIG" 2>/dev/null; then
            ok "JSON валиден"
            inbounds=$(jq '.inbounds | length' "$CONFIG" 2>/dev/null)
            outbounds=$(jq '.outbounds | length' "$CONFIG" 2>/dev/null)
            ok "Inbounds: $inbounds | Outbounds: $outbounds"
            # Проверяем активный сервер
            active=$(jq -r '.outbounds[] | select(.tag=="proxy") | .settings.vnext[0].address // empty' "$CONFIG" 2>/dev/null)
            [[ -n "$active" ]] && ok "Активный сервер: $active" || warn "Не найден outbound с тегом 'proxy'"
        else
            fail "JSON невалиден!"
        fi
    else
        warn "jq не установлен — пропуск проверки"
    fi
else
    fail "Конфиг не найден: $CONFIG"
fi

# ─── 5. Xray-core бинарник ────────────────────────────────────────
sec "5. Xray-core"
XRAY="$HOME/.local/share/v2rayN/bin/xray/xray"
if [[ -x "$XRAY" ]]; then
    ok "Бинарник: $XRAY"
    ver=$("$XRAY" version 2>/dev/null | head -1)
    [[ -n "$ver" ]] && ok "Версия: $ver"
else
    fail "Xray не найден: $XRAY"
fi

# ─── 6. Сеть напрямую ─────────────────────────────────────────────
sec "6. Интернет напрямую"
if ping -c1 -W2 8.8.8.8 &>/dev/null; then
    ok "Ping 8.8.8.8"
else
    fail "Ping 8.8.8.8 не работает"
fi

if curl -sS -o /dev/null -w "%{http_code}" -m 5 https://www.google.com 2>/dev/null | grep -q 200; then
    ok "HTTPS google.com"
else
    warn "HTTPS google.com недоступен (может быть заблокирован)"
fi

if curl -sS -o /dev/null -w "%{http_code}" -m 5 https://gosuslugi.ru 2>/dev/null | grep -qE "200|301|302"; then
    ok "HTTPS gosuslugi.ru (RU)"
else
    warn "HTTPS gosuslugi.ru недоступен"
fi

# ─── 7. Прокси-связность ──────────────────────────────────────────
sec "7. Работа через прокси (SOCKS5 127.0.0.1:10808)"
if ss -tln 2>/dev/null | grep -q ":10808 "; then
    code=$(curl -sS -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:10808 -m 5 https://www.google.com 2>/dev/null)
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
        ok "Google через прокси (HTTP $code)"
    else
        fail "Google через прокси (HTTP $code)"
    fi
    
    code=$(curl -sS -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:10808 -m 5 https://twitter.com 2>/dev/null)
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
        ok "Twitter через прокси (HTTP $code)"
    else
        warn "Twitter через прокси (HTTP $code) — может быть заблокирован на сервере"
    fi
else
    fail "Пропуск — порт 10808 не слушается"
fi

# ─── 8. Публичный IP ──────────────────────────────────────────────
sec "8. Публичные IP"
direct_ip=$(curl -sS -m 5 https://ipinfo.io/ip 2>/dev/null)
[[ -n "$direct_ip" ]] && ok "Напрямую: $direct_ip" || warn "Не удалось получить прямой IP"

if ss -tln 2>/dev/null | grep -q ":10808 "; then
    proxy_ip=$(curl -sS -m 5 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null)
    if [[ -n "$proxy_ip" ]]; then
        if [[ "$proxy_ip" == "$direct_ip" ]]; then
            warn "IP через прокси совпадает с прямым — прокси не работает!"
        else
            ok "Через прокси: $proxy_ip"
        fi
    else
        fail "Не удалось получить IP через прокси"
    fi
fi

# ─── 9. DNS ───────────────────────────────────────────────────────
sec "9. DNS-резолвинг"
dns=$(grep -m1 nameserver /etc/resolv.conf | awk '{print $2}')
[[ -n "$dns" ]] && ok "Системный DNS: $dns"

if command -v dig &>/dev/null; then
    resolved=$(dig +short google.com 2>/dev/null | head -1)
    [[ -n "$resolved" ]] && ok "dig google.com → $resolved" || warn "dig google.com не резолвится"
elif command -v nslookup &>/dev/null; then
    resolved=$(nslookup google.com 2>/dev/null | awk '/^Address:/ {print $2; exit}')
    [[ -n "$resolved" ]] && ok "nslookup google.com → $resolved"
fi

# ─── 10. Таблица маршрутов ────────────────────────────────────────
sec "10. Маршруты"
default_gw=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
[[ -n "$default_gw" ]] && ok "Шлюз по умолчанию: $default_gw" || fail "Нет default gateway"
ip route show | head -5 | sed 's/^/  /'

# ─── 11. Системный прокси (GNOME/KDE) ────────────────────────────
sec "11. Системный прокси"
if command -v gsettings &>/dev/null; then
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
    if [[ "$mode" == "none" ]]; then
        warn "GNOME системный прокси: выключен"
    else
        host=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null | tr -d "'")
        port=$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null)
        ok "GNOME прокси: $mode → $host:$port"
    fi
fi

# ─── 12. GUI окружение ───────────────────────────────────────────
sec "12. GUI (для v2rayN)"
[[ -n "${DISPLAY:-}" ]] && ok "DISPLAY=$DISPLAY" || warn "DISPLAY не установлен (systemd не запустит GUI)"
[[ -n "${WAYLAND_DISPLAY:-}" ]] && ok "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
[[ -n "${XDG_RUNTIME_DIR:-}" ]] && ok "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

# ─── 13. Последние ошибки в логах ─────────────────────────────────
sec "13. Последние ошибки (journalctl)"
for unit in v2rayn xray; do
    if systemctl --user is-enabled "${unit}.service" 2>/dev/null | grep -q enabled; then
        errors=$(journalctl --user -u "${unit}.service" --no-pager -p err -n 3 2>/dev/null | grep -v "^--")
        if [[ -n "$errors" ]]; then
            warn "Ошибки в ${unit}.service:"
            echo "$errors" | tail -3 | sed 's/^/    /'
        else
            ok "${unit}.service — ошибок нет"
        fi
    fi
done

# ─── 14. Итоговое резюме ──────────────────────────────────────────
echo -e "\n${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  ИТОГО                                          ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"

if [[ $ISSUES -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${G}✅ Всё работает идеально!${N}"
elif [[ $ISSUES -eq 0 ]]; then
    echo -e "${Y}⚠ Работает, но есть $WARNINGS предупреждений${N}"
else
    echo -e "${R}❌ Найдено $ISSUES критических проблем и $WARNINGS предупреждений${N}"
fi

[[ "$LOG_FILE" != "/dev/null" ]] && echo -e "\nЛог сохранён: ${B}$LOG_FILE${N}"