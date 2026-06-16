#!/bin/bash
# kill-switch.sh — блокировка трафика при падении v2rayN
# ============================================================================
# Блокирует любой трафик, не проходящий через v2rayN прокси.
# Предотвращает утечку данных при падении/остановке v2rayN.
#
# Использование:
#   ./scripts/kill-switch.sh {on|off|status}
#
# Принцип:
#   - Разрешён только трафик через порты прокси (10808, 10809)
#   - Разрешён DNS (53), loopback (lo)
#   - Весь остальной исходящий трафик блокируется
# ============================================================================

set -euo pipefail

ACTION="${1:-status}"
IPTABLES=$(command -v iptables 2>/dev/null || true)
NFT=$(command -v nft 2>/dev/null || true)
PROXY_SOCKS=10808
PROXY_HTTP=10809

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Проверка прав
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "Kill-switch требует root. Запустите с sudo: sudo $0 $ACTION"
  fi
}

# Проверка iptables
check_iptables() {
  if [ -z "$IPTABLES" ]; then
    error "iptables не найден. Установите: sudo apt-get install iptables"
  fi
}

# ---- Включить kill-switch ----
enable() {
  check_root
  check_iptables

  # Проверяем, не включён ли уже
  if $IPTABLES -C OUTPUT -p tcp ! --dport "${PROXY_SOCKS}:${PROXY_HTTP}" -j REJECT --reject-with tcp-reset 2>/dev/null; then
    warn "Kill-switch уже включён"
    return 0
  fi

  info "Включение kill-switch..."

  # Создаём цепочку V2RAYN
  $IPTABLES -N V2RAYN 2>/dev/null || true

  # Очищаем цепочку (на случай повторного включения)
  $IPTABLES -F V2RAYN 2>/dev/null || true

  # Разрешаем loopback
  $IPTABLES -A V2RAYN -o lo -j ACCEPT

  # Разрешаем уже установленные соединения
  $IPTABLES -A V2RAYN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Разрешаем DNS (udp 53)
  $IPTABLES -A V2RAYN -p udp --dport 53 -j ACCEPT
  $IPTABLES -A V2RAYN -p tcp --dport 53 -j ACCEPT

  # Разрешаем трафик через прокси-порты v2rayN
  $IPTABLES -A V2RAYN -p tcp --dport "${PROXY_SOCKS}:${PROXY_HTTP}" -j ACCEPT

  # Разрешаем ICMP (ping)
  $IPTABLES -A V2RAYN -p icmp -j ACCEPT

  # Блокируем всё остальное
  $IPTABLES -A V2RAYN -p tcp -j REJECT --reject-with tcp-reset
  $IPTABLES -A V2RAYN -p udp -j REJECT --reject-with icmp-port-unreachable

  # Применяем цепочку к OUTPUT
  $IPTABLES -A OUTPUT -j V2RAYN 2>/dev/null || {
    warn "Цепочка V2RAYN уже подключена к OUTPUT, пропускаю"
  }

  info "Kill-switch включён. Весь трафик кроме прокси :${PROXY_SOCKS}/:${PROXY_HTTP} заблокирован."
}

# ---- Выключить kill-switch ----
disable() {
  check_root
  check_iptables

  info "Выключение kill-switch..."

  # Удаляем ссылку на цепочку из OUTPUT
  $IPTABLES -D OUTPUT -j V2RAYN 2>/dev/null || true

  # Очищаем и удаляем цепочку
  $IPTABLES -F V2RAYN 2>/dev/null || true
  $IPTABLES -X V2RAYN 2>/dev/null || true

  info "Kill-switch выключен. Трафик не блокируется."
}

# ---- Статус ----
status() {
  if $IPTABLES -L V2RAYN &>/dev/null 2>&1; then
    echo -e "${GREEN}Kill-switch: ВКЛЮЧЁН${NC}"
    echo ""
    echo "Правила:"
    $IPTABLES -L V2RAYN -v 2>/dev/null | head -20
  else
    echo -e "${YELLOW}Kill-switch: ВЫКЛЮЧЕН${NC}"
  fi
}

case "$ACTION" in
  on|enable|start)  enable  ;;
  off|disable|stop) disable ;;
  status)           status  ;;
  *) echo "Использование: $0 {on|off|status}"; exit 1 ;;
esac
