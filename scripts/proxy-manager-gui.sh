#!/bin/bash
# proxy-manager-gui.sh — Панель управления v2rayN/Xray (вкладки)
# ============================================================================
# Зависимости: yad, jq, curl, gsettings (GNOME прокси)
# Установка:   sudo apt install yad
# ============================================================================

set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-$HOME/.config/v2rayN/config.json}"
XRAY_EXEC="${XRAY_EXEC:-$HOME/.local/share/v2rayN/bin/xray}"
[[ -x "$XRAY_EXEC" ]] || XRAY_EXEC="xray"
LOCK_FILE="/tmp/proxy-manager-gui.lock"
ICON="dialog-information"
TITLE="Панель управления v2rayN"

# ─── Блокировка от множественных экземпляров ───────────────────────────────
acquire_gui_lock() {
  if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    local pid
    pid=$(cat "$LOCK_FILE/pid" 2>/dev/null || echo "")
    # Проверка на stale lock (PID не существует)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$LOCK_FILE"
      mkdir "$LOCK_FILE"
    else
      echo "Панель уже запущена (PID: ${pid:-unknown}). Используйте единственный экземпляр." >&2
      exit 1
    fi
  fi
  echo "$$" > "$LOCK_FILE/pid"
  trap 'rm -rf "$LOCK_FILE"' EXIT
}

notify() { notify-send "$TITLE" "$1" -t 3000 -i "$ICON" 2>/dev/null || true; }

# ─── Прокси: GNOME / KDE ────────────────────────────────────────────────────
set_proxy_manual() {
  # GNOME
  if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.system.proxy mode 'manual'
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
    gsettings set org.gnome.system.proxy.socks port 10808
    gsettings set org.gnome.system.proxy.http host '127.0.0.1'
    gsettings set org.gnome.system.proxy.http port 10809
    gsettings set org.gnome.system.proxy.https host '127.0.0.1'
    gsettings set org.gnome.system.proxy.https port 10809
  fi
  # KDE
  local kwc
  kwc=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
  if [[ -n "$kwc" ]]; then
    "$kwc" --file kioslaverc --group "Proxy Settings" --key ProxyType 1
    "$kwc" --file kioslaverc --group "Proxy Settings" --key httpProxy "http://127.0.0.1:10809"
    "$kwc" --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://127.0.0.1:10809"
    "$kwc" --file kioslaverc --group "Proxy Settings" --key socksProxy "socks://127.0.0.1:10808"
    "$kwc" --file kioslaverc --group "Proxy Settings" --key NoProxyFor "localhost,127.0.0.0/8,::1,*.local,.ru,.su,.xn--p1ai"
    dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
  fi
  # Sway / Hyprland / Wayland (env vars)
  export http_proxy="http://127.0.0.1:10809"
  export https_proxy="http://127.0.0.1:10809"
  export socks_proxy="socks5://127.0.0.1:10808"
  export no_proxy="localhost,127.0.0.0/8,::1,*.local,.ru,.su,.xn--p1ai"
  export HTTP_PROXY="$http_proxy"
  export HTTPS_PROXY="$https_proxy"
  export SOCKS_PROXY="$socks_proxy"
  export NO_PROXY="$no_proxy"
}

set_proxy_none() {
  command -v gsettings &>/dev/null && gsettings set org.gnome.system.proxy mode 'none'
  local kwc
  kwc=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
  if [[ -n "$kwc" ]]; then
    "$kwc" --file kioslaverc --group "Proxy Settings" --key ProxyType 0
    dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
  fi
}

proxy_status_text() {
  local pm
  pm=$(gsettings get org.gnome.system.proxy mode 2>/dev/null | tr -d "'")
  if [[ "$pm" == "manual" ]]; then echo "🟢 ВКЛ"
  else
    local kwc
    kwc=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
    if [[ -n "$kwc" ]] && "$kwc" --file kioslaverc --group "Proxy Settings" --key ProxyType 2>/dev/null | grep -q "1"; then
      echo "🟢 ВКЛ (KDE)"
    else
      echo "🔴 ВЫКЛ"
    fi
  fi
}

# ─── Действия ──────────────────────────────────────────────────────────────

xray_on() {
    systemctl --user start xray.service 2>/dev/null && sleep 2
    if systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null; then
        notify "▶ Xray запущен"; else notify "❌ Xray не запустился"; fi
}
xray_off() {
    systemctl --user stop xray.service 2>/dev/null || pkill -x xray 2>/dev/null || true
    notify "⏹ Xray остановлен"
}
xray_restart() {
    systemctl --user restart xray.service 2>/dev/null && notify "🔄 Xray перезапущен"
}
proxy_on() {
    set_proxy_manual
    notify "🔌 Прокси включён"
}
proxy_off() {
    set_proxy_none
    notify "🔌 Прокси выключен"
}

run_scr() {
    local s="$1" t="$2"
    [[ ! -f "$s" ]] && { yad --error --text="Не найден: $s" 2>/dev/null; return; }
    bash "$s" 2>&1 | yad --text-info --title="$t" --width=750 --height=550 \
        --fontname="Monospace 10" --button="Закрыть:0" 2>/dev/null &
}
run_term() {
    local s="$1" t="$2"
    [[ ! -f "$s" ]] && { yad --error --text="Не найден: $s" 2>/dev/null; return; }
    local term
    term=$(command -v x-terminal-emulator 2>/dev/null \
        || command -v gnome-terminal 2>/dev/null \
        || command -v konsole 2>/dev/null \
        || command -v xterm 2>/dev/null \
        || echo "")
    [[ -z "$term" ]] && { yad --error --text="Терминал не найден" 2>/dev/null; return; }
    if [[ "$term" == *konsole* ]]; then
        "$term" --title "$t" -e bash -c "bash '$s'; echo; echo 'Нажмите Enter...'; read" 2>/dev/null &
    else
        "$term" --title="$t" -e bash -c "bash '$s'; echo; echo 'Нажмите Enter...'; read" 2>/dev/null &
    fi
}

detect_block() {
    local s="$SCRIPTS_DIR/detect-block-type.sh"
    [[ ! -f "$s" ]] && return
    local mode
    mode=$(yad --list --title="Тип блокировки" --text="Режим:" \
        --column="" --column="" --width=400 --height=150 \
        --button="Запустить:0" --button="Отмена:1" \
        "full" "Полная (8 тестов)" "quick" "Быстрая (основные)" 2>/dev/null)
    [[ $? -ne 0 || -z "$mode" ]] && return
    bash "$s" "--$mode" 2>&1 | yad --text-info --title="Тип блокировки" \
        --width=800 --height=600 --fontname="Monospace 9" --button="Закрыть:0" 2>/dev/null &
}

rotate_sni() {
    local s="$SCRIPTS_DIR/rotate-sni.sh"
    [[ ! -f "$s" ]] && return
    bash "$s" 2>&1 | yad --text-info --title="SNI" --width=400 --height=150 \
        --fontname="Monospace 10" --button="OK:0" 2>/dev/null &
    notify "🔄 SNI сменён"
}

view_logs() {
    local d
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then
        d=$(journalctl --user -u xray.service --no-pager -n 200 2>&1)
    elif [[ -f "$HOME/.local/share/v2rayN/logs/v2rayN.log" ]]; then
        d=$(tail -200 "$HOME/.local/share/v2rayN/logs/v2rayN.log" 2>/dev/null)
    else d="Логи не найдены"; fi
    echo "$d" | yad --text-info --title="Логи Xray" --width=900 --height=600 \
        --fontname="Monospace 9" --button="Закрыть:0" 2>/dev/null &
}

view_config() {
    if [[ -f "$CONFIG" ]]; then
        jq '.' "$CONFIG" 2>/dev/null | yad --text-info --title="config.json" \
            --width=800 --height=600 --fontname="Monospace 9" --button="Закрыть:0" 2>/dev/null &
    else yad --error --text="Конфиг не найден" 2>/dev/null; fi
}

about_win() {
    local xv
    xv=$("$XRAY_EXEC" version 2>/dev/null | head -1 || echo "N/A")
    yad --info --title="О программе" --text="<b>🌐 Панель управления v2rayN</b>

<b>Версия:</b> 1.0 &nbsp; <b>Платформа:</b> Linux (YAD)
<b>Xray:</b> $xv
<b>Лицензия:</b> MIT" --width=400 --height=200 2>/dev/null
}

# ─── Сборка вкладок ───────────────────────────────────────────────────────

build_status_tab() {
    local xr
    if systemctl --user is-active --quiet xray.service 2>/dev/null; then xr="🟢 systemd"
    elif pgrep -x xray >/dev/null; then xr="🟢 PID $(pgrep -x xray | head -1)"
    else xr="🔴 Остановлен"; fi

    local ps; ps=$(proxy_status_text)

    local s8="○"; ss -tln 2>/dev/null | grep -q ':10808 ' && s8="🟢"
    local s9="○"; ss -tln 2>/dev/null | grep -q ':10809 ' && s9="🟢"

    local di pr
    di=$(curl -s -m 3 https://ipinfo.io/ip 2>/dev/null || echo "⏳")
    pr=$(curl -s -m 3 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null || echo "⏳")
    local xv; xv=$("$XRAY_EXEC" version 2>/dev/null | head -1 || echo "N/A")

    yad --plug --tabnum=1 --form \
        --field="<b>● СТАТУС</b>:LBL" \
        --field="🛡️ Xray:LBL" --field="<b>$xr</b>:LBL" \
        --field="🔌 Системный прокси:LBL" --field="<b>$ps</b>:LBL" \
        --field="🔌 Порты:LBL" --field="SOCKS5 :10808 $s8 | HTTP :10809 $s9:LBL" \
        --field="🌍 $xv:LBL" \
        --field="Прямой: $di:LBL" \
        --field="Через прокси: $pr:LBL" 2>/dev/null &
}

build_control_tab() {
    yad --plug --tabnum=2 --form --columns=2 \
        --field="<b>● Xray</b>:LBL" :LBL \
        --field="▶ Запустить:BTN" --field="⏹ Остановить:BTN" \
        --field="🔄 Перезапустить:BTN" :LBL \
        --field=":LBL" :LBL \
        --field="<b>● Системный прокси</b>:LBL" :LBL \
        --field="🔌 Включить:BTN" --field="🔌 Выключить:BTN" \
        2>/dev/null &
}

build_diag_tab() {
    yad --plug --tabnum=3 --form --columns=2 \
        --field="🔍 Диагностика сети:BTN" --field="📱 Мобильная:BTN" \
        --field="🚦 Тип блокировки:BTN" --field="📡 Захват трафика:BTN" \
        --field="🔄 Ротация SNI:BTN" --field="🔧 Two-server схема:BTN" \
        --field="🛡️ Kill Switch:BTN" --field="⚡ Оптимизация:BTN" \
        2>/dev/null &
}

build_tools_tab() {
    yad --plug --tabnum=4 --form --columns=2 \
        --field="<b>● Просмотр</b>:LBL" :LBL \
        --field="📜 Логи Xray:BTN" --field="⚙️ Конфиг:BTN" \
        --field=":LBL" :LBL \
        --field="<b>● Обслуживание</b>:LBL" :LBL \
        --field="🔄 Обновить правила:BTN" --field="🔧 Исправить всё:BTN" \
        --field="♻️ Восстановить:BTN" --field="🔌 Toggle прокси:BTN" \
        --field=":LBL" :LBL \
        --field="<b>● Мониторинг</b>:LBL" :LBL \
        --field="🏥 Health Check:BTN" --field="📋 Статус:BTN" \
        2>/dev/null &
}

# ─── Запуск панели ─────────────────────────────────────────────────────────

main() {
    if ! command -v yad &>/dev/null; then
        echo "Ошибка: yad не установлен. Установите: sudo apt install yad"; exit 1
    fi
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        echo "Ошибка: нет графического окружения (DISPLAY)"; exit 1
    fi
    acquire_gui_lock

    local key=54321

    build_status_tab
    build_control_tab
    build_diag_tab
    build_tools_tab

    yad --notebook --key="$key" --tab="📊 Статус" --tab="🎮 Управление" \
        --tab="🔍 Диагностика" --tab="🛠️ Инструменты" \
        --title="$TITLE" --window-icon="$ICON" --center \
        --width=620 --height=400 \
        --button="🔄:2" --button="ℹ️:3" --button="Выход:0" \
        2>/dev/null
}

# ─── Обработка результата ─────────────────────────────────────────────────

process_result() {
    local result="$1" code="$2"
    case $code in
        0|252) exit 0 ;;
        3) about_win; return ;;
    esac
    case "$result" in
        *"Запустить"*)   xray_on ;;
        *"Остановить"*)  xray_off ;;
        *"Перезапустить"*) xray_restart ;;
        *"Включить"*)    proxy_on ;;
        *"Выключить"*)   proxy_off ;;
        *"Диагностика сети"*)  run_scr "$SCRIPTS_DIR/netcheck.sh" "Диагностика сети" ;;
        *"Мобильная"*)        run_scr "$SCRIPTS_DIR/mobile-netcheck.sh" "Мобильная диагностика" ;;
        *"Тип блокировки"*)   detect_block ;;
        *"Захват трафика"*)   run_scr "$SCRIPTS_DIR/traffic-capture.sh" "Захват трафика" ;;
        *"Ротация SNI"*)      rotate_sni ;;
        *"Two-server"*)       run_term "$SCRIPTS_DIR/setup-two-server.sh" "Двухсерверная схема" ;;
        *"Kill Switch"*)      run_scr "$SCRIPTS_DIR/kill-switch.sh" "Kill Switch" ;;
        *"Оптимизация"*)      run_scr "$SCRIPTS_DIR/optimize-mobile.sh" "Оптимизация" ;;
        *"Логи Xray"*)        view_logs ;;
        *"Конфиг"*)           view_config ;;
        *"Обновить правила"*) run_scr "$SCRIPTS_DIR/update-rules.sh" "Обновление правил" ;;
        *"Исправить всё"*)    run_term "$SCRIPTS_DIR/v2ray-fix-all.sh" "Диагностика v2rayN" ;;
        *"Восстановить"*)     run_scr "$SCRIPTS_DIR/restore-all.sh" "Восстановление" ;;
        *"Toggle"*)           
            [[ "$(proxy_status_text)" == *"ВКЛ"* ]] && proxy_off || proxy_on
            ;;
        *"Health Check"*)
            run_scr "$SCRIPTS_DIR/v2ray-health.sh" "Health Check"
            ;;
        *"Статус"*)
            run_scr "$SCRIPTS_DIR/status.sh" "Статус v2rayN"
            ;;
    esac
}

loop() {
    while true; do
        local result code
        result=$(main)
        code=$?
        process_result "$result" "$code"
    done
}

loop
