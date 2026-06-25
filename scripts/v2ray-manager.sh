#!/bin/bash
# v2ray-manager.sh — Единый менеджер v2rayN/Xray
# Использование: ./v2ray-manager.sh [КОМАНДА]
# Без аргументов запускает GUI

set -uo pipefail

# ─── Цвета ───────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; ((++ISSUES)); }
warn() { echo -e "  ${Y}!${N} $*"; ((++WARNINGS)); }
sec()  { echo -e "\n${B}━━━ $* ━━━${N}"; }

ISSUES=0; WARNINGS=0

# ─── Пути ────────────────────────────────────────────────────────────
XRAY_BIN="$HOME/.local/share/v2rayN/bin/xray/xray"
CONFIG="$HOME/.config/v2rayN/config.json"
SERVICE="xray.service"

# ─── Функции диагностики ────────────────────────────────────────────
check_status() {
    echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
    echo -e "${C}║  Диагностика v2rayN/Xray                        ║${N}"
    echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
    echo -e "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 1. Systemd
    sec "1. Systemd юниты"
    local state
    state=$(systemctl --user is-active "$SERVICE" 2>/dev/null)
    if [[ "$state" == "active" ]] || { [[ "$state" == "activating" ]] && pgrep -x xray >/dev/null; }; then
        ok "$SERVICE — активен"
    else
        fail "$SERVICE — $state"
    fi
    
    # 2. Процессы
    sec "2. Запущенные процессы"
    if pgrep -x xray &>/dev/null; then
        ok "xray (PID: $(pgrep -x xray | head -1))"
    else
        fail "xray не запущен"
    fi
    
    # 3. Порты
    sec "3. Порты прокси"
    for port in 10808 10809; do
        if ss -tln 2>/dev/null | grep -q ":${port} "; then
            ok "Порт $port слушается"
        else
            fail "Порт $port не слушается"
        fi
    done
    
    # 4. Конфиг
    sec "4. Конфиг v2rayN"
    if [[ -f "$CONFIG" ]]; then
        if jq empty "$CONFIG" 2>/dev/null; then
            ok "JSON валиден"
            local inbounds outbounds
            inbounds=$(jq '.inbounds | length' "$CONFIG" 2>/dev/null)
            outbounds=$(jq '.outbounds | length' "$CONFIG" 2>/dev/null)
            ok "Inbounds: $inbounds | Outbounds: $outbounds"
            local active
            active=$(jq -r '.outbounds[] | select(.tag=="proxy") | .settings.vnext[0].address // empty' "$CONFIG" 2>/dev/null)
            [[ -n "$active" ]] && ok "Активный сервер: $active" || warn "Не найден outbound 'proxy'"
        else
            fail "JSON невалиден!"
        fi
    else
        fail "Конфиг не найден: $CONFIG"
    fi
    
    # 5. Xray бинарник
    sec "5. Xray-core"
    if [[ -x "$XRAY_BIN" ]]; then
        ok "Бинарник: $XRAY_BIN"
        local ver
        ver=$("$XRAY_BIN" version 2>/dev/null | head -1)
        [[ -n "$ver" ]] && ok "Версия: $ver"
    else
        fail "Xray не найден: $XRAY_BIN"
    fi
    
    # 6. Прокси-связность
    sec "6. Работа через прокси"
    if ss -tln 2>/dev/null | grep -q ":10808 "; then
        local code
        code=$(curl -sS -o /dev/null -w "%{http_code}" --socks5-hostname 127.0.0.1:10808 -m 5 https://www.google.com 2>/dev/null)
        if [[ "$code" =~ ^(200|301|302)$ ]]; then
            ok "Google через прокси (HTTP $code)"
        else
            fail "Google через прокси (HTTP $code)"
        fi
    else
        fail "Пропуск — порт 10808 не слушается"
    fi
    
    # 7. IP
    sec "7. Публичные IP"
    local direct_ip
    direct_ip=$(curl -sS -m 5 https://ipinfo.io/ip 2>/dev/null)
    [[ -n "$direct_ip" ]] && ok "Напрямую: $direct_ip" || warn "Не удалось получить прямой IP"
    
    if ss -tln 2>/dev/null | grep -q ":10808 "; then
            local proxy_ip
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
    
    # 8. Системный прокси
    sec "8. Системный прокси"
    local mode
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
    if [[ "$mode" == "none" ]]; then
        warn "GNOME системный прокси: выключен"
    else
        local host port
        host=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null | tr -d "'")
        port=$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null)
        ok "GNOME прокси: $mode → $host:$port"
    fi
    
    # Итог
    echo -e "\n${C}╔═══════════════════════════════════════════════════╗${N}"
    if [[ $ISSUES -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "${G}✅ Всё работает идеально!${N}"
    elif [[ $ISSUES -eq 0 ]]; then
        echo -e "${Y}⚠ Работает, но есть $WARNINGS предупреждений${N}"
    else
        echo -e "${R}❌ Найдено $ISSUES критических проблем и $WARNINGS предупреждений${N}"
    fi
    echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
}

# ─── Функции управления ─────────────────────────────────────────────
proxy_on() {
    gsettings set org.gnome.system.proxy mode 'manual'
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
    gsettings set org.gnome.system.proxy.socks port 10808
    gsettings set org.gnome.system.proxy.http host '127.0.0.1'
    gsettings set org.gnome.system.proxy.http port 10809
    gsettings set org.gnome.system.proxy.https host '127.0.0.1'
    gsettings set org.gnome.system.proxy.https port 10809
    echo -e "${G}✅ Прокси ВКЛЮЧЁН${N}"
}

proxy_off() {
    gsettings set org.gnome.system.proxy mode 'none'
    echo -e "${Y}✅ Прокси ВЫКЛЮЧЕН${N}"
}

xray_start() {
    systemctl --user start "$SERVICE"
    sleep 2
    if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null || pgrep -x xray >/dev/null; then
        echo -e "${G}✅ Xray запущен${N}"
    else
        echo -e "${R}❌ Xray не запустился${N}"
    fi
}

xray_stop() {
    systemctl --user stop "$SERVICE"
    echo -e "${Y}✅ Xray остановлен${N}"
}

xray_restart() {
    systemctl --user restart "$SERVICE"
    sleep 2
    if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null || pgrep -x xray >/dev/null; then
        echo -e "${G}✅ Xray перезапущен${N}"
    else
        echo -e "${R}❌ Xray не запустился после перезапуска${N}"
    fi
}

# ─── Функции исправления ────────────────────────────────────────────
fix_geoip() {
    echo -e "${B}Исправление симлинков geosite.dat/geoip.dat...${N}"
    ln -sf ../geosite.dat ../geoip.dat "$HOME/.local/share/v2rayN/bin/xray/"
    echo -e "${G}✅ Симлинки созданы${N}"
    xray_restart
}

fix_config() {
    echo -e "${B}Исправление конфига...${N}"
    if ! jq empty "$CONFIG" 2>/dev/null; then
        echo -e "${R}❌ Конфиг невалиден, требуется ручное исправление${N}"
        return 1
    fi
    
    # Проверяем, есть ли outbound с тегом proxy
    if ! jq -e '.outbounds[] | select(.tag=="proxy")' "$CONFIG" >/dev/null 2>&1; then
        echo -e "${Y}⚠ Не найден outbound 'proxy', создаю минимальный...${N}"
        cp "$CONFIG" "${CONFIG}.bak"
        jq '.outbounds += [{"tag":"proxy","protocol":"vmess","settings":{"vnext":[{"address":"YOUR_SERVER","port":443,"users":[{"id":"YOUR_UUID","alterId":0}]}]},"streamSettings":{"network":"ws","security":"tls","wsSettings":{"path":"/"}}}]' "${CONFIG}.bak" > "$CONFIG"
        echo -e "${Y}⚠ Замените YOUR_SERVER и YOUR_UUID в $CONFIG${N}"
    else
        echo -e "${G}✅ Конфиг корректен${N}"
    fi
}

# ─── Функции информации ─────────────────────────────────────────────
show_logs() {
    journalctl --user -u "$SERVICE" --no-pager -n "${1:-50}"
}

show_config() {
    if [[ -f "$CONFIG" ]]; then
        jq '.' "$CONFIG" 2>/dev/null || cat "$CONFIG"
    else
        echo -e "${R}❌ Конфиг не найден${N}"
    fi
}

# ─── GUI режим ──────────────────────────────────────────────────────
gui_mode() {
    if ! command -v zenity &>/dev/null; then
        echo -e "${R}❌ zenity не установлен. Установите: sudo apt install zenity${N}"
        exit 1
    fi
    
    while true; do
        local status proxy
        status=$(systemctl --user is-active "$SERVICE" 2>/dev/null)
        proxy=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
        
        local svc_text prx_text
        if [[ "$status" == "active" ]] || { [[ "$status" == "activating" ]] && pgrep -x xray >/dev/null; }; then
            svc_text="✅ Xray: работает"
        else
            svc_text="❌ Xray: остановлен"
        fi
        
        [[ "$proxy" == "manual" ]] && prx_text="✅ Прокси: ВКЛ" || prx_text="❌ Прокси: ВЫКЛ"
        
        local ip_text
        ip_text=$(curl -s -m 3 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null || echo 'нет')
        
        local choice
        choice=$(zenity --width=450 --height=300 --list --title="Менеджер прокси v2rayN" \
            --text="$svc_text\n$prx_text\nIP через прокси: $ip_text" \
            --column="Действие" \
            "🔍 Диагностика" \
            "▶️ Включить прокси" \
            "⏸ Выключить прокси" \
            "🔄 Перезапустить Xray" \
            "🛑 Остановить Xray" \
            "🔧 Исправить geosite.dat" \
            "📋 Показать конфиг" \
            "📜 Логи (последние 50)" \
            "🚪 Выход")
        
        case "$choice" in
            "🔍 Диагностика")
                check_status 2>&1 | zenity --text-info --width=700 --height=500 --title="Диагностика"
                ;;
            "▶️ Включить прокси")
                proxy_on
                zenity --info --text="Прокси ВКЛЮЧЁН" --timeout=2
                ;;
            "⏸ Выключить прокси")
                proxy_off
                zenity --info --text="Прокси ВЫКЛЮЧЕН" --timeout=2
                ;;
            "🔄 Перезапустить Xray")
                xray_restart
                zenity --info --text="Xray перезапущен" --timeout=2
                ;;
            "🛑 Остановить Xray")
                xray_stop
                zenity --info --text="Xray остановлен" --timeout=2
                ;;
            "🔧 Исправить geosite.dat")
                fix_geoip
                zenity --info --text="Симлинки созданы, Xray перезапущен" --timeout=3
                ;;
            "📋 Показать конфиг")
                show_config 2>&1 | zenity --text-info --width=700 --height=500 --title="Конфиг v2rayN"
                ;;
            "📜 Логи (последние 50)")
                show_logs 50 2>&1 | zenity --text-info --width=700 --height=500 --title="Логи Xray"
                ;;
            "🚪 Выход"|"")
                exit 0
                ;;
        esac
    done
}

# ─── Справка ─────────────────────────────────────────────────────────
show_help() {
    cat << 'HELP'
v2ray-manager.sh — Единый менеджер v2rayN/Xray

Использование:
  ./v2ray-manager.sh [КОМАНДА]

Команды:
  status          Полная диагностика
  proxy-on        Включить системный прокси
  proxy-off       Выключить системный прокси
  start           Запустить Xray
  stop            Остановить Xray
  restart         Перезапустить Xray
  fix-geoip       Исправить симлинки geosite.dat/geoip.dat
  fix-config      Проверить и исправить конфиг
  logs [N]        Показать последние N строк логов (по умолчанию 50)
  config          Показать текущий конфиг
  gui             Запустить GUI интерфейс (по умолчанию)
  help            Эта справка

Примеры:
  ./v2ray-manager.sh              # Запуск GUI
  ./v2ray-manager.sh status       # Диагностика в терминале
  ./v2ray-manager.sh proxy-on     # Включить прокси
  ./v2ray-manager.sh restart      # Перезапустить Xray
  ./v2ray-manager.sh logs 100     # Последние 100 строк логов
HELP
}

# ─── Основной блок ──────────────────────────────────────────────────
case "${1:-gui}" in
    status)         check_status ;;
    proxy-on)       proxy_on ;;
    proxy-off)      proxy_off ;;
    start)          xray_start ;;
    stop)           xray_stop ;;
    restart)        xray_restart ;;
    fix-geoip)      fix_geoip ;;
    fix-config)     fix_config ;;
    logs)           show_logs "${2:-50}" ;;
    config)         show_config ;;
    gui)            gui_mode ;;
    help|-h|--help) show_help ;;
    *)              echo -e "${R}❌ Неизвестная команда: $1${N}"; show_help; exit 1 ;;
esac
