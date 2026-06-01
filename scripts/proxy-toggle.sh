#!/bin/bash
PROXY_SCRIPT=~/.local/share/v2rayN/binConfigs/proxy_set_linux_sh.sh
case "${1:-status}" in
  on|enable|manual)
    bash "$PROXY_SCRIPT" manual "127.0.0.1" "10809" "localhost,127.0.0.0/8,::1,*.local,.local,.ru,.su,.xn--p1ai"
    ;;
  off|disable|none)
    bash "$PROXY_SCRIPT" none
    ;;
  status)
    MODE=$(gsettings get org.gnome.system.proxy mode 2>/dev/null)
    echo "Proxy mode: $MODE"
    if [ "$MODE" = "'manual'" ]; then
      echo "HTTP proxy: $(gsettings get org.gnome.system.proxy.http host 2>/dev/null):$(gsettings get org.gnome.system.proxy.http port 2>/dev/null)"
    fi
    ;;
  *)
    echo "Usage: $0 {on|off|status}"
    exit 1
    ;;
esac
