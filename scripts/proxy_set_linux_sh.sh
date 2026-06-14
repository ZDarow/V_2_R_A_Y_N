#!/bin/bash
set -euo pipefail

# proxy_set_linux_sh.sh — библиотека настройки системного прокси (GNOME + KDE)
# Используется через source: source proxy_set_linux_sh.sh

trim() {
  local -n ref=$1
  ref="${ref#"${ref%%[![:space:]]*}"}"
  ref="${ref%"${ref##*[![:space:]]}"}"
}

build_gsettings_array() {
  [[ -z "$1" ]] && echo "[]" && return
  local host joined hosts=() saved_ifs="$IFS"
  IFS=','
  read -ra parts <<< "$1"
  IFS="$saved_ifs"
  for host in "${parts[@]}"; do
    trim host
    [[ -n "$host" ]] && hosts+=("$host")
  done
  [[ ${#hosts[@]} -eq 0 ]] && echo "[]" && return
  printf -v joined "'%s'," "${hosts[@]}"
  echo "[${joined%,}]"
}

set_gnome_proxy() {
  local MODE=$1
  local PROXY_IP=$2
  local PROXY_PORT=$3
  local IGNORE_HOSTS=$4

  gsettings set org.gnome.system.proxy mode "$MODE"

  if [ "$MODE" == "manual" ]; then
    local PROTOCOLS=("http" "https" "socks")

    for PROTOCOL in "${PROTOCOLS[@]}"; do
      gsettings set org.gnome.system.proxy.$PROTOCOL host "$PROXY_IP"
      gsettings set org.gnome.system.proxy.$PROTOCOL port "$PROXY_PORT"
    done

    gsettings set org.gnome.system.proxy ignore-hosts "$(build_gsettings_array "$IGNORE_HOSTS")"

    echo "GNOME: Manual proxy settings applied."
    echo "Proxy IP: $PROXY_IP"
    echo "Proxy Port: $PROXY_PORT"
    echo "Ignored Hosts: $IGNORE_HOSTS"
  elif [ "$MODE" == "none" ]; then
    echo "GNOME: Proxy disabled."
  fi
}

set_kde_proxy() {
  local MODE=$1
  local PROXY_IP=$2
  local PROXY_PORT=$3
  local IGNORE_HOSTS=$4

  KWRITECONFIG="kwriteconfig6"
  if ! command -v "$KWRITECONFIG" &>/dev/null; then
    KWRITECONFIG="kwriteconfig5"
    if ! command -v "$KWRITECONFIG" &>/dev/null; then
      echo "KDE: kwriteconfig не найден. Установите kf6-kconfig-bin или kf5-kconfig-bin."
      return 1
    fi
  fi

  if [ "$MODE" == "manual" ]; then
    $KWRITECONFIG --file kioslaverc --group "Proxy Settings" --key ProxyType 1
    $KWRITECONFIG --file kioslaverc --group "Proxy Settings" --key httpProxy "http://$PROXY_IP:$PROXY_PORT"
    $KWRITECONFIG --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://$PROXY_IP:$PROXY_PORT"
    $KWRITECONFIG --file kioslaverc --group "Proxy Settings" --key socksProxy "http://$PROXY_IP:$PROXY_PORT"

    $KWRITECONFIG --file kioslaverc --group "Proxy Settings" --key NoProxyFor "$IGNORE_HOSTS"

    echo "KDE: Manual proxy settings applied."
    echo "Proxy IP: $PROXY_IP"
    echo "Proxy Port: $PROXY_PORT"
    echo "Ignored Hosts: $IGNORE_HOSTS"
  elif [ "$MODE" == "none" ]; then
    $KWRITECONFIG --file kioslaverc --group "Proxy Settings" --key ProxyType 0
    echo "KDE: Proxy disabled."
  fi

  dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:""
}

detect_desktop_environment() {
  if [[ "$XDG_CURRENT_DESKTOP" == *"GNOME"* ]] || [[ "$XDG_SESSION_DESKTOP" == *"GNOME"* ]]; then
    echo "gnome"
    return
  fi

  if [[ "$XDG_CURRENT_DESKTOP" == *"XFCE"* ]] || [[ "$XDG_SESSION_DESKTOP" == *"XFCE"* ]]; then
    echo "gnome"
    return
  fi

  if [[ "$XDG_CURRENT_DESKTOP" == *"X-Cinnamon"* ]] || [[ "$XDG_SESSION_DESKTOP" == *"cinnamon"* ]]; then
    echo "gnome"
    return
  fi

  if [[ "$XDG_CURRENT_DESKTOP" == *"UKUI"* ]] || [[ "$XDG_SESSION_DESKTOP" == *"ukui"* ]]; then
    echo "gnome"
    return
  fi

  if [[ "$XDG_CURRENT_DESKTOP" == *"DDE"* ]] || [[ "$XDG_SESSION_DESKTOP" == *"dde"* ]]; then
    echo "gnome"
    return
  fi

  if [[ "$XDG_CURRENT_DESKTOP" == *"MATE"* ]] || [[ "$XDG_SESSION_DESKTOP" == *"mate"* ]]; then
    echo "gnome"
    return
  fi

  local KDE_ENVIRONMENTS=("KDE" "plasma")
  for ENV in "${KDE_ENVIRONMENTS[@]}"; do
    if [ "$XDG_CURRENT_DESKTOP" == "$ENV" ] || [ "$XDG_SESSION_DESKTOP" == "$ENV" ]; then
      echo "kde"
      return
    fi
  done

  if command -v gsettings >/dev/null 2>&1; then
    echo "gnome"
    return
  fi

  echo "unsupported"
}

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <mode> [proxy_ip proxy_port ignore_hosts]"
  echo "  mode: 'none' or 'manual'"
  echo "  If mode is 'manual', provide proxy IP, port, and ignore hosts."
  exit 1
fi

MODE=$1
PROXY_IP=$2
PROXY_PORT=$3
IGNORE_HOSTS=$4

if ! [[ "$MODE" =~ ^(manual|none)$ ]]; then
  echo "Invalid mode. Use 'none' or 'manual'." >&2
  exit 1
fi

DE=$(detect_desktop_environment)

if [ "$DE" == "gnome" ]; then
  set_gnome_proxy "$MODE" "$PROXY_IP" "$PROXY_PORT" "$IGNORE_HOSTS"
elif [ "$DE" == "kde" ]; then
  set_kde_proxy "$MODE" "$PROXY_IP" "$PROXY_PORT" "$IGNORE_HOSTS"
else
  echo "Unsupported desktop environment: $DE" >&2
  exit 1
fi
