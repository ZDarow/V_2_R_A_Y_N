#!/bin/bash
# proxy-manager-gui.sh — Tray-иконка для управления v2rayN/Xray прокси
# ============================================================================
# Зависимости: yad, jq, curl, gsettings (GNOME прокси)
# Установка:   sudo apt install yad
# ============================================================================
# Возможности:
#   - Tray-иконка в системном лотке
#   - Правый клик — меню со всеми действиями
#   - Левый клик — показать статус
#   - Уведомления через notify-send
# ============================================================================

set -uo pipefail

# ─── Конфигурация ─────────────────────────────────────────────────────────
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-$HOME/.config/v2rayN/config.json}"
XRAY_EXEC="${XRAY_EXEC:-$HOME/.local/share/v2rayN/bin/xray}"
[[ -x "$XRAY_EXEC" ]] || XRAY_EXEC="xray"
STATUS_FILE="/tmp/v2rayn-gui-status.$$"

# Иконка
ICON_THEME="network-vpn"
TRAY_ICON="network-vpn"
TITLE="Менеджер прокси v2rayN"

trap 'rm -f "$STATUS_FILE"' EXIT

# ─── Функции статуса ───────────────────────────────────────────────────────

xray_running() {
    systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null
}

get_xray_status() {
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        echo "active"
    elif pgrep -x xray >/dev/null; then
        echo "standalone"
    else
        echo "stopped"
    fi
}

get_proxy_gnome() {
    local mode
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
    [[ "$mode" == "manual" ]] && echo "on" || echo "off"
}

is_proxy_on() { [[ "$(get_proxy_gnome)" == "on" ]]; }

get_ip_str() {
    local direct proxy
    direct=$(curl -s -m 4 https://ipinfo.io/ip 2>/dev/null || echo "⏳")
    proxy=$(curl -s -m 4 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null || echo "⏳")
    echo "Прямой: $direct  →  Прокси: $proxy"
}

# ─── Уведомления ────────────────────────────────────────────────────────────

notify() { notify-send "$TITLE" "$1" -t 3000 -i "$ICON_THEME" 2>/dev/null || true; }

# ─── Действия ───────────────────────────────────────────────────────────────

action_status_popup() {
    local xray_s xray_pid proxy_s ip_str
    case "$(get_xray_status)" in
        active)     xray_s="● Работает (systemd)" ;;
        standalone) xray_s="● Работает (PID $(pgrep -x xray | head -1))" ;;
        *)          xray_s="○ Остановлен" ;;
    esac
    is_proxy_on && proxy_s="● ВКЛЮЧЁН" || proxy_s="○ ВЫКЛЮЧЕН"
    ip_str=$(get_ip_str)

    yad --info --title="$TITLE" \
        --text="<b>🛡️ Xray:</b> $xray_s
<b>🔌 Прокси GNOME:</b> $proxy_s

SOCKS5 :10808  HTTP :10809

<b>🌍 $ip_str</b>" \
        --width=400 --height=250 \
        --button="OK:0" \
        --window-icon="$ICON_THEME" \
        --timeout=10 2>/dev/null
}

action_toggle_proxy() {
    if is_proxy_on; then
        gsettings set org.gnome.system.proxy mode 'none'
        notify "🔌 Прокси выключен"
    else
        gsettings set org.gnome.system.proxy mode 'manual'
        gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
        gsettings set org.gnome.system.proxy.socks port 10808
        gsettings set org.gnome.system.proxy.http host '127.0.0.1'
        gsettings set org.gnome.system.proxy.http port 10809
        gsettings set org.gnome.system.proxy.https host '127.0.0.1'
        gsettings set org.gnome.system.proxy.https port 10809
        notify "🔌 Прокси включён (SOCKS :10808, HTTP :10809)"
    fi
}

action_toggle_xray() {
    if xray_running; then
        systemctl --user stop xray.service 2>/dev/null || pkill -x xray 2>/dev/null || true
        sleep 1
        if ! xray_running; then
            notify "⏹ Xray остановлен"
        else
            notify "⚠️ Не удалось остановить Xray"
        fi
    else
        systemctl --user start xray.service 2>/dev/null && sleep 2
        if xray_running; then
            notify "▶ Xray запущен"
        else
            notify "❌ Xray не запустился"
        fi
    fi
}

action_restart_xray() {
    local old_pid
    old_pid=$(pgrep -x xray 2>/dev/null | head -1)
    systemctl --user restart xray.service 2>/dev/null || pkill -x xray 2>/dev/null || true
    sleep 2
    if xray_running; then
        notify "🔄 Xray перезапущен (PID ${old_pid} → $(pgrep -x xray | head -1))"
    else
        notify "❌ Xray не запустился после перезапуска"
    fi
}

action_run_script() {
    local script="$1" title="$2" interactive="${3:-}"
    if [[ ! -f "$script" ]]; then
        yad --error --text="Скрипт не найден:\n$script" --width=350 2>/dev/null
        return
    fi
    if [[ "$interactive" == "terminal" ]]; then
        gnome-terminal --title="$title" -- bash -c "bash '$script'; echo; echo 'Нажмите Enter...'; read" 2>/dev/null &
    else
        bash "$script" 2>&1 | yad --text-info --width=750 --height=500 \
            --title="$title" --fontname="Monospace 10" \
            --button="Закрыть:0" \
            --window-icon="$ICON_THEME" 2>/dev/null
    fi
}

action_detect_block() {
    local script="$SCRIPTS_DIR/detect-block-type.sh"
    [[ ! -f "$script" ]] && { yad --error --text="detect-block-type.sh не найден" 2>/dev/null; return; }

    local mode
    mode=$(yad --list --title="Тип блокировки" --text="Режим диагностики:" \
        --column="Режим" --column="Описание" \
        "full" "Полная — все 8 тестов" \
        "quick" "Быстрая — SNI, IP, CGNAT" \
        --width=450 --height=150 \
        --button="Запустить:0" --button="Отмена:1" 2>/dev/null)
    [[ $? -ne 0 || -z "$mode" ]] && return

    bash "$script" "--$mode" 2>&1 | yad --text-info --width=800 --height=600 \
        --title="Тип блокировки" --fontname="Monospace 9" \
        --button="Закрыть:0" 2>/dev/null
}

action_rotate_sni() {
    local script="$SCRIPTS_DIR/rotate-sni.sh"
    [[ ! -f "$script" ]] && { yad --error --text="rotate-sni.sh не найден" 2>/dev/null; return; }

    # Выбор домена из whitelist
    local snis
    snis=$(bash "$script" --list 2>/dev/null)
    local domain
    domain=$(echo "$snis" | grep -v '^#' | grep -v '^\[' | head -20 | \
        yad --list --title="Ротация SNI" --text="Выберите SNI домен или случайный:" \
            --column="Домен" \
            --button="Случайный:0" --button="Выбрать:1" --button="Отмена:2" \
            --width=350 --height=300 2>/dev/null)
    local btn=$?
    # 0 = случайный, 1 = выбрал домен, 2 = отмена

    if [[ $btn -eq 0 ]]; then
        domain=""
    elif [[ $btn -ne 1 || -z "$domain" ]]; then
        return
    fi

    if [[ -n "$domain" ]]; then
        bash "$script" --set "$domain" 2>&1 | yad --text-info --width=500 --height=200 \
            --title="SNI: $domain" --fontname="Monospace 10" \
            --button="OK:0" 2>/dev/null
    else
        bash "$script" 2>&1 | yad --text-info --width=500 --height=200 \
            --title="Случайный SNI" --fontname="Monospace 10" \
            --button="OK:0" 2>/dev/null
    fi
    notify "🔄 SNI сменён"
}

action_view_logs() {
    local log_data
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        log_data=$(journalctl --user -u xray.service --no-pager -n 200 2>&1)
    elif [[ -f "$HOME/.local/share/v2rayN/logs/v2rayN.log" ]]; then
        log_data=$(tail -200 "$HOME/.local/share/v2rayN/logs/v2rayN.log" 2>/dev/null)
    else
        log_data="Логи не найдены"
    fi
    echo "$log_data" | yad --text-info --width=900 --height=600 \
        --title="Логи Xray" --fontname="Monospace 9" \
        --button="Закрыть:0" 2>/dev/null
}

action_view_config() {
    if [[ -f "$CONFIG" ]]; then
        jq '.' "$CONFIG" 2>/dev/null | yad --text-info --width=800 --height=600 \
            --title="config.json" --fontname="Monospace 9" \
            --button="Закрыть:0" 2>/dev/null
    else
        yad --error --text="Конфиг не найден" --width=350 2>/dev/null
    fi
}

action_about() {
    local xray_ver
    xray_ver=$("$XRAY_EXEC" version 2>/dev/null | head -1 || echo "N/A")
    yad --info --title="О программе" \
        --text="<b>🌐 Менеджер прокси v2rayN/Xray</b>

<b>Версия:</b> 1.0
<b>Платформа:</b> Linux (YAD tray)

<b>Компоненты:</b>
• $xray_ver
• GNOME system proxy
• 17 CLI-скриптов диагностики

<b>Меню tray:</b>
• Статус — сводка по Xray, прокси, IP
• Пуск/Стоп/Рестарт Xray
• Вкл/Выкл системный прокси
• Диагностика сети и мобильного
• Тип блокировки (detect-block-type)
• Ротация SNI
• Двухсерверная схема
• Kill Switch
• Захват трафика
• Логи и конфиг

<b>Лицензия:</b> MIT" \
        --width=450 --height=400 \
        --window-icon="$ICON_THEME" 2>/dev/null
}

# ─── Tray-меню ─────────────────────────────────────────────────────────────

build_menu() {
    cat << MENU
📊 Статус!status
▶ Запустить/Остановить Xray!toggle-xray
🔄 Перезапустить Xray!restart-xray
🔌 Вкл/Выкл прокси!toggle-proxy
━!sep
🔍 Диагностика сети!netcheck
📱 Диагностика мобильного!mobile
🚦 Тип блокировки!detect-block
📡 Захват трафика!tcapture
━!sep
🔄 Сменить SNI!rotate-sni
🔧 Двухсерверная схема!two-server
🛡️ Kill Switch!killswitch
⚡ Оптимизация мобильного!optimize
━!sep
📜 Логи Xray!logs
⚙️ Конфиг!config
🔄 Обновить правила!update-rules
🔧 Исправить всё!fixall
♻️ Восстановить!restore
━!sep
ℹ️ О программе!about
🚪 Выход!quit
MENU
}

# ─── Обработчик команд ─────────────────────────────────────────────────────

handle_command() {
    case "$1" in
        status)        action_status_popup ;;
        toggle-xray)   action_toggle_xray ;;
        restart-xray)  action_restart_xray ;;
        toggle-proxy)  action_toggle_proxy ;;
        netcheck)      action_run_script "$SCRIPTS_DIR/netcheck.sh" "Диагностика сети" ;;
        mobile)        action_run_script "$SCRIPTS_DIR/mobile-netcheck.sh" "Диагностика мобильного" ;;
        detect-block)  action_detect_block ;;
        tcapture)      action_run_script "$SCRIPTS_DIR/traffic-capture.sh" "Захват трафика" ;;
        rotate-sni)    action_rotate_sni ;;
        two-server)    action_run_script "$SCRIPTS_DIR/setup-two-server.sh" "Двухсерверная схема" terminal ;;
        killswitch)    action_run_script "$SCRIPTS_DIR/kill-switch.sh" "Kill Switch" ;;
        optimize)      action_run_script "$SCRIPTS_DIR/optimize-mobile.sh" "Оптимизация мобильного" ;;
        logs)          action_view_logs ;;
        config)        action_view_config ;;
        update-rules)  action_run_script "$SCRIPTS_DIR/update-rules.sh" "Обновление правил" ;;
        fixall)        action_run_script "$SCRIPTS_DIR/v2ray-fix-all.sh" "Диагностика v2rayN" terminal ;;
        restore)       action_run_script "$SCRIPTS_DIR/restore-all.sh" "Восстановление" ;;
        about)         action_about ;;
        quit)          exit 0 ;;
    esac
}

# ─── Запуск tray ───────────────────────────────────────────────────────────

main() {
    # Проверки
    if ! command -v yad &>/dev/null; then
        echo "Ошибка: yad не установлен. Установите: sudo apt install yad"
        exit 1
    fi
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        echo "Ошибка: нет графического окружения (DISPLAY не установлен)"
        echo "Запустите из терминала с DISPLAY или используйте TUI"
        exit 1
    fi

    # PID-файл для предотвращения дублирования
    local pid_file="/tmp/v2rayn-gui-tray.pid"
    if [[ -f "$pid_file" ]]; then
        local old_pid
        old_pid=$(cat "$pid_file" 2>/dev/null)
        if kill -0 "$old_pid" 2>/dev/null; then
            notify "⚠️ Tray-иконка уже запущена (PID $old_pid)"
            exit 0
        fi
    fi
    echo "$$" > "$pid_file"
    trap 'rm -f "$pid_file" "$STATUS_FILE"' EXIT

    # Запуск tray (YAD notification)
    yad --notification \
        --command="bash '$0' --handle" \
        --menu="$(build_menu)" \
        --image="$TRAY_ICON" \
        --text="$TITLE" 2>/dev/null &

    local yad_pid=$!
    notify "✅ Tray-иконка запущена (PID $yad_pid)"

    # Ожидаем завершения yad
    wait "$yad_pid" 2>/dev/null
}

# ─── Обработчик кликов (при --handle) ──────────────────────────────────────
# YAD notification вызывает --command при клике:
#   - левый клик → без аргументов (показываем статус)
#   - пункт меню → с action в качестве аргумента

if [[ "${1:-}" == "--handle" ]]; then
    handle_command "${2:-status}"
    exit 0
fi

# ─── Запуск ────────────────────────────────────────────────────────────────

main "$@"
