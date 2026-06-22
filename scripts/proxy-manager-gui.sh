#!/bin/bash
# proxy-manager-gui.sh — YAD-десктоп GUI для управления v2rayN/Xray
# ============================================================================
# Зависимости: yad, jq, curl, gsettings (для GNOME прокси)
# Установка:   sudo apt install yad
# ============================================================================

set -uo pipefail

# ─── Конфигурация ─────────────────────────────────────────────────────────
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
CONFIG="${CONFIG:-$HOME/.config/v2rayN/config.json}"
XRAY_EXEC="${XRAY_EXEC:-xray}"

# Иконки (Gtk stock или эмодзи)
ICON_XRAY="🛡️"
ICON_OK="✅"
ICON_FAIL="❌"
ICON_WARN="⚠️"
ICON_INFO="ℹ️"
TITLE="🌐 Менеджер прокси v2rayN"

# ─── Функции получения статуса ─────────────────────────────────────────────

xray_running() {
    systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null
}

get_xray_status() {
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        echo "$ICON_OK systemd: активен"
    elif pgrep -x xray >/dev/null; then
        local pid; pid=$(pgrep -x xray | head -1)
        echo "$ICON_OK standalone (PID $pid)"
    else
        echo "$ICON_FAIL Остановлен"
    fi
}

get_proxy_gnome_status() {
    local mode
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
    if [[ "$mode" == "manual" ]]; then
        echo "$ICON_OK ВКЛ (SOCKS :10808, HTTP :10809)"
    else
        echo "$ICON_FAIL ВЫКЛ"
    fi
}

get_ip_info() {
    local direct="" proxy=""
    direct=$(curl -s -m 4 https://ipinfo.io/ip 2>/dev/null || echo "⏳")
    proxy=$(curl -s -m 4 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null || echo "⏳")
    echo "Прямой: $direct  →  Прокси: $proxy"
}

get_xray_version() {
    "$XRAY_EXEC" version 2>/dev/null | head -1 || echo "N/A"
}

get_xray_ports() {
    local socks="" http=""
    socks=$(ss -tln 2>/dev/null | grep -c ':10808 ' || echo 0)
    http=$(ss -tln 2>/dev/null | grep -c ':10809 ' || echo 0)
    [[ "$socks" -gt 0 ]] && echo "SOCKS5 :10808 $ICON_OK" || echo "SOCKS5 :10808 $ICON_FAIL"
    [[ "$http" -gt 0 ]] && echo "HTTP   :10809 $ICON_OK" || echo "HTTP   :10809 $ICON_FAIL"
}

# ─── Функции действий ──────────────────────────────────────────────────────

notify() { notify-send "$TITLE" "$1" -t 3000 2>/dev/null || true; }

action_start_xray() {
    systemctl --user start xray.service 2>/dev/null && sleep 2
    if xray_running; then notify "$ICON_OK Xray запущен"; else notify "$ICON_FAIL Xray не запустился"; fi
}

action_stop_xray() {
    systemctl --user stop xray.service 2>/dev/null || pkill -x xray 2>/dev/null || true
    sleep 1
    if ! xray_running; then notify "$ICON_OK Xray остановлен"; else notify "$ICON_WARN Не удалось остановить"; fi
}

action_restart_xray() {
    systemctl --user restart xray.service 2>/dev/null && sleep 2
    if xray_running; then notify "$ICON_OK Xray перезапущен"; else notify "$ICON_FAIL Ошибка перезапуска"; fi
}

action_proxy_on() {
    gsettings set org.gnome.system.proxy mode 'manual'
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
    gsettings set org.gnome.system.proxy.socks port 10808
    gsettings set org.gnome.system.proxy.http host '127.0.0.1'
    gsettings set org.gnome.system.proxy.http port 10809
    gsettings set org.gnome.system.proxy.https host '127.0.0.1'
    gsettings set org.gnome.system.proxy.https port 10809
    notify "$ICON_OK Системный прокси ВКЛЮЧЁН"
}

action_proxy_off() {
    gsettings set org.gnome.system.proxy mode 'none'
    notify "$ICON_OK Системный прокси ВЫКЛЮЧЕН"
}

action_run_diagnose() {
    local script="$SCRIPTS_DIR/netcheck.sh"
    if [[ -f "$script" ]]; then
        bash "$script" 2>&1 | yad --text-info --width=800 --height=600 \
            --title="$TITLE — Диагностика сети" --fontname="Monospace 10" \
            --button="Закрыть:0" --window-icon="applications-utilities"
    else
        yad --error --text="Скрипт netcheck.sh не найден"
    fi
}

action_run_mobile() {
    local script="$SCRIPTS_DIR/mobile-netcheck.sh"
    if [[ -f "$script" ]]; then
        bash "$script" 2>&1 | yad --text-info --width=800 --height=600 \
            --title="$TITLE — Диагностика мобильного" --fontname="Monospace 10" \
            --button="Закрыть:0"
    else
        yad --error --text="Скрипт mobile-netcheck.sh не найден"
    fi
}

action_detect_block() {
    local script="$SCRIPTS_DIR/detect-block-type.sh"
    if [[ -f "$script" ]]; then
        # Выбор режима
        local mode
        mode=$(yad --list --title="Тип блокировки" --text="Выберите режим:" \
            --column="Режим" --column="Описание" \
            "full" "Полная диагностика (все 8 тестов)" \
            "quick" "Быстрая (только SNI, IP, CGNAT)" \
            --width=500 --height=200 --button="Запустить:0" --button="Отмена:1")
        [[ $? -ne 0 || -z "$mode" ]] && return
        bash "$script" "--$mode" 2>&1 | yad --text-info --width=800 --height=600 \
            --title="$TITLE — Тип блокировки" --fontname="Monospace 10" \
            --button="Закрыть:0"
    else
        yad --error --text="Скрипт detect-block-type.sh не найден"
    fi
}

action_rotate_sni() {
    local script="$SCRIPTS_DIR/rotate-sni.sh"
    if [[ -f "$script" ]]; then
        # Показать список SNI
        local sni_list
        sni_list=$(bash "$script" --list 2>&1 | yad --text-info --width=400 --height=300 \
            --title="Доступные SNI" --fontname="Monospace 10" \
            --button="Выбрать случайный:0" --button="Отмена:1" --no-buttons)
        [[ $? -ne 0 ]] && return
        # Запуск ротации
        bash "$script" 2>&1 | yad --text-info --width=600 --height=200 \
            --title="$TITLE — Ротация SNI" --fontname="Monospace 10" \
            --button="Закрыть:0"
        notify "$ICON_OK SNI сменён"
    else
        yad --error --text="Скрипт rotate-sni.sh не найден"
    fi
}

action_two_server() {
    local script="$SCRIPTS_DIR/setup-two-server.sh"
    if [[ -f "$script" ]]; then
        local action
        action=$(yad --list --title="Двухсерверная схема" \
            --text="Выберите действие:" \
            --column="Действие" --column="Описание" \
            "check" "Проверить, нужна ли two-server схема" \
            "gen-config" "Сгенерировать конфиги для серверов" \
            --width=500 --height=200 --button="Выполнить:0" --button="Отмена:1")
        [[ $? -ne 0 || -z "$action" ]] && return
        if [[ "$action" == "gen-config" ]]; then
            x-terminal-emulator -T "Настройка two-server" -e "bash '$script' --gen-config; echo; echo 'Нажмите Enter...'; read"
        else
            bash "$script" "--$action" 2>&1 | yad --text-info --width=700 --height=500 \
                --title="$TITLE — Two-server" --fontname="Monospace 10" \
                --button="Закрыть:0"
        fi
    else
        yad --error --text="Скрипт setup-two-server.sh не найден"
    fi
}

action_traffic_capture() {
    local script="$SCRIPTS_DIR/traffic-capture.sh"
    if [[ -f "$script" ]]; then
        local test_type
        test_type=$(yad --list --title="Захват трафика" --text="Выберите тип теста:" \
            --column="Тест" --column="Описание" \
            "dns" "DNS-запросы" \
            "https" "HTTPS (порт 443)" \
            "sni" "SNI-блокировка" \
            "full" "Полный захват (30 сек)" \
            --width=400 --height=250 --button="Запустить:0" --button="Отмена:1")
        [[ $? -ne 0 || -z "$test_type" ]] && return
        bash "$script" "--$test_type" 2>&1 | yad --text-info --width=800 --height=400 \
            --title="$TITLE — Захват трафика" --fontname="Monospace 9" \
            --button="Закрыть:0"
        notify "$ICON_OK Захват завершён"
    else
        yad --error --text="Скрипт traffic-capture.sh не найден"
    fi
}

action_optimize() {
    local script="$SCRIPTS_DIR/optimize-mobile.sh"
    if [[ -f "$script" ]]; then
        yad --question --title="Оптимизация" \
            --text="Применить оптимизацию для мобильного интернета?\n\nMTU, TLS-фрагментация, маскировка Host" \
            --width=400
        if [[ $? -eq 0 ]]; then
            bash "$script" 2>&1 | yad --text-info --width=700 --height=500 \
                --title="$TITLE — Оптимизация" --fontname="Monospace 10" \
                --button="Закрыть:0"
            notify "$ICON_OK Оптимизация применена"
        fi
    else
        yad --error --text="Скрипт optimize-mobile.sh не найден"
    fi
}

action_restore() {
    local script="$SCRIPTS_DIR/restore-all.sh"
    if [[ -f "$script" ]]; then
        yad --question --title="Восстановление" \
            --text="Восстановить все настройки по умолчанию?\n\nЭто перезапустит Xray и сбросит прокси" \
            --width=400
        if [[ $? -eq 0 ]]; then
            bash "$script" 2>&1 | yad --text-info --width=700 --height=500 \
                --title="$TITLE — Восстановление" --fontname="Monospace 10" \
                --button="Закрыть:0"
            notify "$ICON_OK Восстановление завершено"
        fi
    else
        yad --error --text="Скрипт restore-all.sh не найден"
    fi
}

action_kill_switch() {
    local script="$SCRIPTS_DIR/kill-switch.sh"
    if [[ -f "$script" ]]; then
        local action
        action=$(yad --list --title="Kill Switch" \
            --text="Управление Kill Switch (блокировка трафика при падении VPN):" \
            --column="Действие" --column="Описание" \
            "enable" "Включить Kill Switch" \
            "disable" "Выключить Kill Switch" \
            "status" "Проверить статус" \
            --width=500 --height=200 --button="Выполнить:0" --button="Отмена:1")
        [[ $? -ne 0 || -z "$action" ]] && return
        bash "$script" "--$action" 2>&1 | yad --text-info --width=600 --height=300 \
            --title="$TITLE — Kill Switch" --fontname="Monospace 10" \
            --button="Закрыть:0"
    else
        yad --error --text="Скрипт kill-switch.sh не найден"
    fi
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
        --title="$TITLE — Логи Xray" --fontname="Monospace 9" \
        --button="Закрыть:0"
}

action_view_config() {
    if [[ -f "$CONFIG" ]]; then
        jq '.' "$CONFIG" 2>/dev/null | yad --text-info --width=800 --height=600 \
            --title="$TITLE — Конфиг v2rayN" --fontname="Monospace 9" \
            --button="Закрыть:0"
    else
        yad --error --text="Конфиг не найден:\n$CONFIG" --width=400
    fi
}

action_edit_config() {
    if [[ -f "$CONFIG" ]]; then
        local editor
        editor=${EDITOR:-nano}
        x-terminal-emulator -T "Редактирование config.json" -e "$editor '$CONFIG'; echo; echo 'Нажмите Enter...'; read" &
    else
        yad --error --text="Конфиг не найден:\n$CONFIG" --width=400
    fi
}

action_update_rules() {
    local script="$SCRIPTS_DIR/update-rules.sh"
    if [[ -f "$script" ]]; then
        yad --question --title="Обновление правил" \
            --text="Скачать свежие geoip.dat и geosite.dat?" \
            --width=400
        if [[ $? -eq 0 ]]; then
            bash "$script" 2>&1 | yad --text-info --width=600 --height=300 \
                --title="$TITLE — Обновление правил" --fontname="Monospace 10" \
                --button="Закрыть:0"
            notify "$ICON_OK Правила обновлены"
        fi
    else
        yad --error --text="Скрипт update-rules.sh не найден"
    fi
}

action_fix_all() {
    local script="$SCRIPTS_DIR/v2ray-fix-all.sh"
    if [[ -f "$script" ]]; then
        yad --question --title="Исправление проблем" \
            --text="Запустить полную диагностику и исправление проблем v2rayN?\n\nПроверка: Xray, порты, конфиги, DNS, маршрутизация" \
            --width=450
        if [[ $? -eq 0 ]]; then
            x-terminal-emulator -T "Диагностика v2rayN" -e "bash '$script'; echo; echo 'Нажмите Enter...'; read" &
        fi
    else
        yad --error --text="Скрипт v2ray-fix-all.sh не найден"
    fi
}

action_proxy_toggle() {
    local script="$SCRIPTS_DIR/proxy-toggle.sh"
    if [[ -f "$script" ]]; then
        bash "$script" 2>&1 | yad --text-info --width=400 --height=150 \
            --title="$TITLE — Toggle прокси" --fontname="Monospace 10" \
            --button="Закрыть:0" --timeout=5
    else
        yad --error --text="Скрипт proxy-toggle.sh не найден"
    fi
}

action_about() {
    local xray_ver; xray_ver=$(get_xray_version)
    yad --info --title="$TITLE — О программе" \
        --text="<b>🌐 Менеджер прокси v2rayN/Xray</b>\n\n\
Версия: 1.0\n\
Платформа: Linux (YAD GUI)\n\n\
<b>Компоненты:</b>\n\
• $xray_ver\n\
• systemd user service\n\
• GNOME system proxy\n\n\
<b>Скрипты диагностики:</b>\n\
• detect-block-type.sh — тип блокировки оператора\n\
• mobile-netcheck.sh — диагностика мобильного\n\
• netcheck.sh — диагностика сети\n\
• rotate-sni.sh — ротация SNI\n\
• setup-two-server.sh — двухсерверная схема\n\n\
<b>Лицензия:</b> MIT" \
        --width=500 --height=400
}

# ─── Обновление статус-бара ────────────────────────────────────────────────

# PID файл для IPC с yad
STATUS_FIFO="/tmp/v2rayn-gui-status.$$"
trap 'rm -f "$STATUS_FIFO"' EXIT

update_status() {
    local xray_s xray_port ip_info proxy_s
    xray_s=$(get_xray_status)
    xray_port=$(get_xray_ports | tr '\n' ' | ')
    ip_info=$(get_ip_info)
    proxy_s=$(get_proxy_gnome_status)
    echo "🛡️ $xray_s | $proxy_s | $ip_info" > "$STATUS_FIFO"
}

# ─── Сборка статуса для отображения ────────────────────────────────────────

build_status_html() {
    local xray_s xray_ports ip_info proxy_s
    xray_s=$(get_xray_status)
    xray_ports=$(get_xray_ports | sed 's/^/    /')
    proxy_s=$(get_proxy_gnome_status)
    ip_info=$(get_ip_info)

    cat << HTML
<b>🛡️ Xray-core:</b>  $xray_s
    $xray_ports

<b>🔌 Системный прокси (GNOME):</b>  $proxy_s

<b>🌍 Внешний IP:</b>
    $ip_info
HTML
}

# ─── Главное окно ──────────────────────────────────────────────────────────

main_dialog() {
    local status_html
    status_html=$(build_status_html)

    # yad --form с информационными полями и кнопками действий
    yad --form --title="$TITLE" \
        --window-icon="network-server" \
        --width=600 --height=550 \
        --center \
        --separator="\n" \
        --buttons-layout=spread \
        --image="network-server" \
        --field=":LBL" \
        --field="$status_html:LBL" \
        --field="━━━ Управление Xray ━━━:LBL" \
        --field="▸ Запустить Xray:BTN" \
        --field="▸ Остановить Xray:BTN" \
        --field="▸ Перезапустить Xray:BTN" \
        --field="━━━ Системный прокси ━━━:LBL" \
        --field="▸ Включить прокси:BTN" \
        --field="▸ Выключить прокси:BTN" \
        --field="━━━ Диагностика ━━━:LBL" \
        --field="▸ Диагностика сети (netcheck):BTN" \
        --field="▸ Диагностика мобильного:BTN" \
        --field="▸ Тип блокировки (detect-block-type):BTN" \
        --field="▸ Захват трафика:BTN" \
        --field="━━━ Инструменты ━━━:LBL" \
        --field="▸ Ротация SNI:BTN" \
        --field="▸ Двухсерверная схема:BTN" \
        --field="▸ Оптимизация мобильного:BTN" \
        --field="▸ Kill Switch:BTN" \
        --field="━━━ Обслуживание ━━━:LBL" \
        --field="▸ Обновить geoip/geosite:BTN" \
        --field="▸ Исправить всё (fix-all):BTN" \
        --field="▸ Восстановить настройки:BTN" \
        --field="━━━ Просмотр ━━━:LBL" \
        --field="▸ Логи Xray:BTN" \
        --field="▸ Просмотр конфига:BTN" \
        --field="▸ Редактировать конфиг:BTN" \
        --field="▸ О программе:BTN" \
        --field=":LBL" \
        --button="🔄 Обновить статус:2" \
        --button="Выход:0" \
        --no-selection
}

# ─── Main loop ─────────────────────────────────────────────────────────────

main_loop() {
    while true; do
        local result exit_code
        result=$(main_dialog)
        exit_code=$?

        # exit_code:
        #   0 — Выход
        #   2 — Обновить статус
        #   252 — Закрыто по ESC/крестику
        if [[ $exit_code -eq 0 || $exit_code -eq 252 ]]; then
            exit 0
        fi

        # Определяем, какая кнопка нажата, по содержимому result
        case "$result" in
            *"▸ Запустить Xray"*)       action_start_xray ;;
            *"▸ Остановить Xray"*)       action_stop_xray ;;
            *"▸ Перезапустить Xray"*)    action_restart_xray ;;
            *"▸ Включить прокси"*)       action_proxy_on ;;
            *"▸ Выключить прокси"*)      action_proxy_off ;;
            *"Диагностика сети"*)        action_run_diagnose ;;
            *"Диагностика мобильного"*)  action_run_mobile ;;
            *"Тип блокировки"*)          action_detect_block ;;
            *"Захват трафика"*)          action_traffic_capture ;;
            *"Ротация SNI"*)             action_rotate_sni ;;
            *"Двухсерверная схема"*)     action_two_server ;;
            *"Оптимизация мобильного"*)  action_optimize ;;
            *"Kill Switch"*)             action_kill_switch ;;
            *"Обновить geoip"*)          action_update_rules ;;
            *"Исправить всё"*)           action_fix_all ;;
            *"Восстановить настройки"*)  action_restore ;;
            *"Логи Xray"*)               action_view_logs ;;
            *"Просмотр конфига"*)        action_view_config ;;
            *"Редактировать конфиг"*)    action_edit_config ;;
            *"О программе"*)             action_about ;;
        esac
    done
}

# ─── Запуск ─────────────────────────────────────────────────────────────────

# Проверка YAD
if ! command -v yad &>/dev/null; then
    echo "Ошибка: yad не установлен. Установите: sudo apt install yad"
    exit 1
fi

# Проверка DISPLAY
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "Ошибка: нет графического окружения (DISPLAY не установлен)"
    echo "Используйте TUI-версию или запустите из терминала с DISPLAY"
    exit 1
fi

main_loop
