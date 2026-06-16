#!/bin/bash
set -euo pipefail
# proxy-toggle.sh — вкл/выкл/статус системного прокси (GNOME + KDE)

PROXY_SCRIPT="${BASH_SOURCE[0]%/*}/proxy_set_linux_sh.sh"
# Альтернативный путь после установки
[ ! -f "$PROXY_SCRIPT" ] && PROXY_SCRIPT="$HOME/.local/share/v2rayN/binConfigs/proxy_set_linux_sh.sh"
[ ! -f "$PROXY_SCRIPT" ] && PROXY_SCRIPT="$HOME/.config/v2rayN/proxy_set_linux_sh.sh"

IGNORE_HOSTS="localhost,127.0.0.0/8,::1,*.local,.ru,.su,.xn--p1ai"

case "${1:-status}" in
  on|enable|manual)
    if [ -f "$PROXY_SCRIPT" ]; then
      bash "$PROXY_SCRIPT" manual "127.0.0.1" "10809" "$IGNORE_HOSTS"
    else
# Прямая установка GNOME
      command -v gsettings &>/dev/null && {
        gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.http port 10809 2>/dev/null || true
        gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.https port 10809 2>/dev/null || true
        gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null || true
        gsettings set org.gnome.system.proxy.socks port 10808 2>/dev/null || true
        # Convert comma-separated to gsettings array of strings
        IFS=',' read -ra HOSTS_ARR <<< "$IGNORE_HOSTS"
        GSETTINGS_IGNORE="["
        FIRST=true
        for H in "${HOSTS_ARR[@]}"; do
          $FIRST || GSETTINGS_IGNORE+=", "
          GSETTINGS_IGNORE+="'${H}'"
          FIRST=false
        done
        GSETTINGS_IGNORE+="]"
        gsettings set org.gnome.system.proxy ignore-hosts "$GSETTINGS_IGNORE" 2>/dev/null || true
        echo "Прокси включён (GNOME)"
      }
      # Прямая установка KDE
      KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
      if [ -n "$KWC" ]; then
        "$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 1 2>/dev/null || true
        "$KWC" --file kioslaverc --group "Proxy Settings" --key httpProxy "http://127.0.0.1:10809" 2>/dev/null || true
        "$KWC" --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://127.0.0.1:10809" 2>/dev/null || true
        "$KWC" --file kioslaverc --group "Proxy Settings" --key socksProxy "http://127.0.0.1:10808" 2>/dev/null || true
        "$KWC" --file kioslaverc --group "Proxy Settings" --key NoProxyFor "$IGNORE_HOSTS" 2>/dev/null || true
        dbus-send --type=signal /IO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
        echo "Прокси включён (KDE)"
      fi
    fi
    command -v notify-send &>/dev/null && \
      notify-send -i v2rayN "v2rayN" "Системный прокси включён" 2>/dev/null || true
    ;;
  off|disable|none)
    if [ -f "$PROXY_SCRIPT" ]; then
      bash "$PROXY_SCRIPT" none
    else
      command -v gsettings &>/dev/null && {
        gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
        echo "Прокси выключен (GNOME)"
      }
      KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
      if [ -n "$KWC" ]; then
        "$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 0 2>/dev/null || true
        dbus-send --type=signal /IO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
        echo "Прокси выключен (KDE)"
      fi
    fi
    command -v notify-send &>/dev/null && \
      notify-send -i v2rayN "v2rayN" "Системный прокси выключен" 2>/dev/null || true
    ;;
  status)
    if command -v gsettings &>/dev/null; then
      MODE=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "unsupported")
      echo "Proxy mode: $MODE"
      if echo "$MODE" | grep -q "manual"; then
        HTTP_HOST=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo "''")
        HTTP_PORT=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null || echo "''")
        echo "HTTP proxy: ${HTTP_HOST}:${HTTP_PORT}"
      fi
    fi
    KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
    if [ -n "$KWC" ]; then
      KDE_MODE=$("$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 2>/dev/null || echo "unknown")
      echo "KDE ProxyType: $KDE_MODE (0=direct, 1=manual)"
    fi
    if ! command -v gsettings &>/dev/null && [ -z "$KWC" ]; then
      echo "Не удалось определить DE. Настройте прокси вручную: HTTP 127.0.0.1:10809, SOCKS 127.0.0.1:10808"
    fi
    ;;
  *)
    echo "Использование: $0 {on|off|status}"
    exit 1
    ;;
esac
