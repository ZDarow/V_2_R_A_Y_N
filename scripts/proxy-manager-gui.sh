#!/bin/bash
# proxy-manager-gui.sh — Графический интерфейс управления прокси

set -uo pipefail

# Цвета для терминала
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; N='\033[0m'

# Проверка zenity
if ! command -v zenity &>/dev/null; then
    echo -e "${R}Ошибка: zenity не установлен${N}"
    echo "Установите: sudo apt install zenity"
    exit 1
fi

# ─── Функции получения статуса ─────────────────────────────────────

get_xray_status() {
    if systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null; then
        echo "✅ Xray: работает"
    else
        echo "❌ Xray: остановлен"
    fi
}

get_proxy_status() {
    local mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
    if [[ "$mode" == "manual" ]]; then
        echo "✅ Прокси: ВКЛ"
    else
        echo "❌ Прокси: ВЫКЛ"
    fi
}

get_ip_info() {
    local direct_ip=$(curl -s -m 3 https://ipinfo.io/ip 2>/dev/null || echo "нет")
    local proxy_ip=$(curl -s -m 3 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null || echo "нет")
    echo "Прямой: $direct_ip | Прокси: $proxy_ip"
}

get_speed() {
    local speed=$(curl -s -o /dev/null -w "%{speed_download}" -m 5 http://speedtest.tele2.net/1MB.zip 2>/dev/null)
    if [[ -n "$speed" && "$speed" != "0" ]]; then
        local speed_mb=$(echo "scale=2; $speed / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
        echo "${speed_mb} MB/s"
    else
        echo "N/A"
    fi
}

# ─── Функции действий ──────────────────────────────────────────────

action_start_xray() {
    systemctl --user start xray.service
    sleep 2
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        zenity --info --text="✅ Xray запущен" --timeout=2 --width=300
    else
        zenity --error --text="❌ Xray не запустился\nПроверьте логи" --width=300
    fi
}

action_stop_xray() {
    systemctl --user stop xray.service
    zenity --info --text="✅ Xray остановлен" --timeout=2 --width=300
}

action_restart_xray() {
    systemctl --user restart xray.service
    sleep 2
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        zenity --info --text="✅ Xray перезапущен" --timeout=2 --width=300
    else
        zenity --error --text="❌ Xray не запустился" --width=300
    fi
}

action_proxy_on() {
    gsettings set org.gnome.system.proxy mode 'manual'
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
    gsettings set org.gnome.system.proxy.socks port 10808
    gsettings set org.gnome.system.proxy.http host '127.0.0.1'
    gsettings set org.gnome.system.proxy.http port 10809
    gsettings set org.gnome.system.proxy.https host '127.0.0.1'
    gsettings set org.gnome.system.proxy.https port 10809
    zenity --info --text="✅ Системный прокси ВКЛЮЧЁН" --timeout=2 --width=300
}

action_proxy_off() {
    gsettings set org.gnome.system.proxy mode 'none'
    zenity --info --text="✅ Системный прокси ВЫКЛЮЧЕН" --timeout=2 --width=300
}

action_diagnose() {
    if [[ -f "$HOME/netcheck.sh" ]]; then
        ~/netcheck.sh 2>&1 | zenity --text-info --width=700 --height=500 --title="Диагностика сети" --font="Monospace 9"
    else
        zenity --error --text="Скрипт netcheck.sh не найден" --width=300
    fi
}

action_mobile_diagnose() {
    if [[ -f "$HOME/mobile-netcheck.sh" ]]; then
        ~/mobile-netcheck.sh 2>&1 | zenity --text-info --width=700 --height=500 --title="Диагностика мобильного" --font="Monospace 9"
    else
        zenity --error --text="Скрипт mobile-netcheck.sh не найден" --width=300
    fi
}

action_traffic_capture() {
    if [[ -f "$HOME/traffic-capture.sh" ]]; then
        # Интерактивный выбор теста
        test_type=$(zenity --list --title="Захват трафика" --text="Выберите тип теста:" \
            --column="Тест" \
            "DNS-запросы" \
            "HTTPS (порт 443)" \
            "SNI-блокировка" \
            "Полный захват (30 сек)" \
            "Все тесты" --width=400 --height=300)
        
        case "$test_type" in
            "DNS-запросы") ~/traffic-capture.sh --dns ;;
            "HTTPS (порт 443)") ~/traffic-capture.sh --https ;;
            "SNI-блокировка") ~/traffic-capture.sh --sni ;;
            "Полный захват (30 сек)") ~/traffic-capture.sh --full ;;
            "Все тесты") ~/traffic-capture.sh --all ;;
        esac
        
        zenity --info --text="✅ Захват завершён\nФайлы: ~/traffic-captures/" --timeout=3 --width=300
    else
        zenity --error --text="Скрипт traffic-capture.sh не найден" --width=300
    fi
}

action_view_logs() {
    journalctl --user -u xray.service --no-pager -n 100 | zenity --text-info --width=700 --height=500 --title="Логи Xray" --font="Monospace 9"
}

action_view_config() {
    if [[ -f "$HOME/.config/v2rayN/config.json" ]]; then
        jq '.' "$HOME/.config/v2rayN/config.json" 2>/dev/null | zenity --text-info --width=700 --height=500 --title="Конфиг v2rayN" --font="Monospace 9"
    else
        zenity --error --text="Конфиг не найден" --width=300
    fi
}

action_restore() {
    if [[ -f "$HOME/restore-all.sh" ]]; then
        if zenity --question --text="Восстановить все настройки?\nЭто сбросит прокси и перезапустит Xray" --width=300; then
            ~/restore-all.sh 2>&1 | zenity --text-info --width=700 --height=500 --title="Восстановление" --font="Monospace 9"
            zenity --info --text="✅ Восстановление завершено" --timeout=2 --width=300
        fi
    else
        zenity --error --text="Скрипт restore-all.sh не найден" --width=300
    fi
}

action_optimize() {
    if [[ -f "$HOME/optimize-mobile.sh" ]]; then
        if zenity --question --text="Применить оптимизацию для мобильного интернета?\nMTU, TCP BBR, маскировка Host" --width=300; then
            ~/optimize-mobile.sh 2>&1 | zenity --text-info --width=700 --height=500 --title="Оптимизация" --font="Monospace 9"
            zenity --info --text="✅ Оптимизация применена" --timeout=2 --width=300
        fi
    else
        zenity --error --text="Скрипт optimize-mobile.sh не найден" --width=300
    fi
}

action_open_wireshark() {
    if command -v wireshark &>/dev/null; then
        if [[ -d "$HOME/traffic-captures" ]]; then
            wireshark "$HOME/traffic-captures"/*.pcap 2>/dev/null &
        else
            zenity --info --text="Нет захваченных файлов\nСначала запустите захват трафика" --width=300
        fi
    else
        zenity --error --text="Wireshark не установлен\nУстановите: sudo apt install wireshark" --width=300
    fi
}

action_about() {
    zenity --info --title="О программе" \
        --text="🌐 Менеджер прокси v2rayN/Xray\n\nВерсия: 1.0\nАвтор: Универсальный агент\n\nКомпоненты:\n• Xray-core 26.6.1\n• v2rayN (GUI клиент)\n• systemd сервисы\n\nСкрипты:\n• netcheck.sh - диагностика\n• mobile-netcheck.sh - мобильная диагностика\n• traffic-capture.sh - захват трафика\n• restore-all.sh - восстановление\n• optimize-mobile.sh - оптимизация" \
        --width=400
}

# ─── Главное меню ──────────────────────────────────────────────────

main_loop() {
    while true; do
        # Получаем текущий статус
        xray_status=$(get_xray_status)
        proxy_status=$(get_proxy_status)
        ip_info=$(get_ip_info)
        
        # Показываем главное меню
        choice=$(zenity --list --title="🌐 Менеджер прокси" \
            --text="$xray_status\n$proxy_status\n$ip_info\n\nВыберите действие:" \
            --column="Действие" \
            "▶️ Запустить Xray" \
            "⏹ Остановить Xray" \
            "🔄 Перезапустить Xray" \
            "─────────────────────" \
            "🔌 Включить системный прокси" \
            "🔌 Выключить системный прокси" \
            "─────────────────────" \
            "🔍 Диагностика сети" \
            "📱 Диагностика мобильного" \
            "📡 Захват трафика (Wireshark)" \
            "🔬 Открыть Wireshark" \
            "─────────────────────" \
            "🚀 Оптимизация для мобильного" \
            "🔧 Восстановление настроек" \
            "─────────────────────" \
            "📜 Просмотр логов Xray" \
            "⚙️ Просмотр конфига" \
            "─────────────────────" \
            "ℹ️ О программе" \
            "🚪 Выход" \
            --width=450 --height=600)
        
        # Обработка выбора
        case "$choice" in
            "▶️ Запустить Xray") action_start_xray ;;
            "⏹ Остановить Xray") action_stop_xray ;;
            "🔄 Перезапустить Xray") action_restart_xray ;;
            "🔌 Включить системный прокси") action_proxy_on ;;
            "🔌 Выключить системный прокси") action_proxy_off ;;
            "🔍 Диагностика сети") action_diagnose ;;
            "📱 Диагностика мобильного") action_mobile_diagnose ;;
            "📡 Захват трафика (Wireshark)") action_traffic_capture ;;
            "🔬 Открыть Wireshark") action_open_wireshark ;;
            "🚀 Оптимизация для мобильного") action_optimize ;;
            "🔧 Восстановление настроек") action_restore ;;
            "📜 Просмотр логов Xray") action_view_logs ;;
            "⚙️ Просмотр конфига") action_view_config ;;
            "ℹ️ О программе") action_about ;;
            "🚪 Выход"|"") exit 0 ;;
            "─────────────────────") continue ;;
        esac
    done
}

# Запуск
main_loop
