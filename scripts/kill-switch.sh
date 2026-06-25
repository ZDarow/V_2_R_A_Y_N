#!/bin/bash
# kill-switch.sh — блокировка трафика при падении v2rayN
# shellcheck disable=SC2034
# SC2034: цвета используются в info/warn/error
# ============================================================================
# Блокирует любой трафик, не проходящий через v2rayN прокси.
# Предотвращает утечку данных при падении/остановке v2rayN.
#
# Использование:
#   ./scripts/kill-switch.sh {on|off|status}
#
# Принцип:
#   - Разрешён loopback (lo) — для подключения к локальному прокси
#   - Разрешён трафик от процесса Xray (по UID владельца)
#   - Разрешён DNS (53)
#   - Разрешены уже установленные соединения
#   - Весь остальной исходящий трафик блокируется
# ============================================================================

set -euo pipefail

ACTION="${1:-status}"
IPTABLES=$(command -v iptables 2>/dev/null || true)
PROXY_SOCKS=10808
PROXY_HTTP=10809

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
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
  if $IPTABLES -C OUTPUT -j V2RAYN 2>/dev/null; then
    warn "Kill-switch уже включён"
    return 0
  fi

  # Определяем UID процесса Xray (если запущен) или текущего пользователя
  # ВАЖНО: owner UID пропускает ВЕСЬ трафик от указанного пользователя,
  #        а не только от процесса xray. Для полной изоляции запускайте
  #        xray под отдельным системным пользователем (--uid-owner xray).
  XRAY_UID=""
  if XRAY_PID=$(pgrep -f '/xray/xray' 2>/dev/null | head -1); then
    XRAY_UID=$(stat -c '%u' "/proc/${XRAY_PID}" 2>/dev/null || true)
  fi
  if [ -z "${XRAY_UID}" ]; then
    XRAY_UID=$(id -u)
    warn "Xray не запущен, использую UID ${XRAY_UID} (текущий пользователь)"
  fi

  info "Включение kill-switch (UID xray: ${XRAY_UID})..."

  # Создаём цепочку V2RAYN
  $IPTABLES -N V2RAYN 2>/dev/null || true

  # Очищаем цепочку (на случай повторного включения)
  $IPTABLES -F V2RAYN 2>/dev/null || true

  # Разрешаем loopback (для подключения к локальному прокси)
  $IPTABLES -A V2RAYN -o lo -j ACCEPT

  # Разрешаем трафик от процесса Xray (по UID владельца)
  # Это необходимо, чтобы xray мог делать исходящие соединения к серверу.
  # owner UID ~ uid-1000 пропускает ВСЕ процессы mi, не только xray.
  # Для полной изоляции: создайте пользователя xray и настройте запуск.
  $IPTABLES -A V2RAYN -m owner --uid-owner "${XRAY_UID}" -j ACCEPT

  # Разрешаем уже установленные соединения
  $IPTABLES -A V2RAYN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # Разрешаем DNS (udp 53/tcp 53)
  $IPTABLES -A V2RAYN -p udp --dport 53 -j ACCEPT
  $IPTABLES -A V2RAYN -p tcp --dport 53 -j ACCEPT

  # Разрешаем ICMP (ping, traceroute)
  $IPTABLES -A V2RAYN -p icmp -j ACCEPT

  # Блокируем всё остальное
  $IPTABLES -A V2RAYN -p tcp -j REJECT --reject-with tcp-reset
  $IPTABLES -A V2RAYN -p udp -j REJECT --reject-with icmp-port-unreachable

  # Применяем цепочку к OUTPUT
  $IPTABLES -A OUTPUT -j V2RAYN 2>/dev/null || {
    warn "Цепочка V2RAYN уже подключена к OUTPUT, пропускаю"
  }

  info "Kill-switch включён. Трафик кроме Xray/lo/DNS/ICMP блокирован."
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
