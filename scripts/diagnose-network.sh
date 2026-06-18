#!/bin/bash
# diagnose-network.sh — полная самодостаточная диагностика сети
# ==============================================================================
# Версия: 2.0.0
# Лицензия: MIT
#
# Проверяет: систему, интерфейсы, маршрутизацию, DNS, прокси, файрвол,
# sysctl (30+ параметров), TUN, соединения, связность, VPN, безопасность.
#
# Особенности:
#   - модульная архитектура с реестром секций и проверок
#   - автоматическая установка всех зависимостей (apt/dnf/pacman)
#   - не останавливается на ошибках
#   - три формата вывода: плоский отчёт + JSON + цветной stdout
#   - scoring pass/warn/fail/skip + рекомендации
# ==============================================================================

set -u -o pipefail
# set -e НЕ используется — скрипт продолжается при ошибках

# ─── КОНФИГУРАЦИЯ ───────────────────────────────────────────────────────────
readonly SCRIPT_NAME="diagnose-network.sh"
readonly SCRIPT_VERSION="2.0.0"

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
readonly TIMESTAMP
TIMESTAMP_FILE=$(date '+%Y%m%d-%H%M%S')
readonly TIMESTAMP_FILE

readonly REPORT_DIR="${HOME}/.local/share/v2rayN/logs"
readonly REPORT_FILE="${REPORT_DIR}/network-diagnostic-${TIMESTAMP_FILE}.log"
readonly JSON_FILE="${REPORT_DIR}/network-diagnostic-${TIMESTAMP_FILE}.json"
TMP_DIR=$(mktemp -d "/tmp/diag-network-XXXXXX")
readonly TMP_DIR
trap 'rm -rf "${TMP_DIR:-}" 2>/dev/null' EXIT

# Флаги
MODE="full"                    # full | quick | security | connectivity | section
GENERATE_JSON=false
CUSTOM_REPORT=""
AUTO_INSTALL=true

# ─── ЦВЕТА ───────────────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# ─── СТАТИСТИКА ──────────────────────────────────────────────────────────────
TOTAL_CHECKS=0
PASSED=0
WARNINGS=0
FAILED=0
SKIPPED=0

declare -a RECOMMENDATIONS=()
declare -a CHECK_LOG=()
declare -A JSON_DATA=()

# ==============================================================================
#  ДВИЖОК — БАЗОВЫЕ ФУНКЦИИ
# ==============================================================================

cmd_exists() { command -v "$1" &>/dev/null; }

service_active() {
  systemctl --user is-active "$1" &>/dev/null || systemctl is-active "$1" &>/dev/null
}

# ─── ЗАПИСЬ В ОТЧЁТ ─────────────────────────────────────────────────────────
report()   { echo "$1" >> "$REPORT_FILE"; }
report_n() { printf "%s" "$1" >> "$REPORT_FILE"; }

section() {
  local title="$1" sep
  sep="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "" >> "$REPORT_FILE"
  report "${sep}"
  report "  ${title}"
  report "${sep}"
}

subsection() { report "─── $1 ───"; }

# ─── СЧЁТЧИКИ ───────────────────────────────────────────────────────────────
_inc() {
  local type="$1" msg="$2"
  ((TOTAL_CHECKS++))
  case "$type" in
    pass) ((PASSED++));   report "  [✓] ${msg}"; CHECK_LOG+=("PASS:${msg}") ;;
    warn) ((WARNINGS++)); report "  [!] ${msg}"; CHECK_LOG+=("WARN:${msg}") ;;
    fail) ((FAILED++));   report "  [✗] ${msg}"; CHECK_LOG+=("FAIL:${msg}") ;;
    skip) ((SKIPPED++));  report "  [−] ${msg}"; CHECK_LOG+=("SKIP:${msg}") ;;
  esac
}
ok()   { _inc pass "$1"; }
warn() { _inc warn "$1"; }
fail() { _inc fail "$1"; }
skip() { _inc skip "$1"; }

recommend() { RECOMMENDATIONS+=("$1"); }

# ─── ВЫПОЛНЕНИЕ КОМАНД ──────────────────────────────────────────────────────
run_cmd() {
  local label="$1" cmd="$2" optional="${3:-false}"
  report "  >> ${label}"
  if eval "$cmd" >> "$REPORT_FILE" 2>&1; then return 0; fi
  if [ "$optional" = "true" ]; then return 0; fi
  return 1
}

# ─── ЗАПИСЬ В JSON ──────────────────────────────────────────────────────────
json_set() {
  local section="$1" key="$2" value="$3"
  JSON_DATA["${section}.${key}"]="$value"
}

# ─── ВЫПОЛНЕНИЕ СЕКЦИЙ ──────────────────────────────────────────────────────
declare -a REGISTERED_SECTIONS=()

register_section() {
  local name="$1" desc="$2" func="$3"
  REGISTERED_SECTIONS+=("${name}|${desc}|${func}")
}

run_section() {
  local entry="$1"
  local name="${entry%%|*}"
  local rest="${entry#*|}"
  local desc="${rest%%|*}"
  local func="${rest#*|}"
  report ""
  section "${name}. ${desc}"
  json_set "sections" "${name}" "${desc}"
  $func
}

# ==============================================================================
#  УСТАНОВКА ЗАВИСИМОСТЕЙ
# ==============================================================================

detect_pm() {
  if cmd_exists apt-get;  then echo "apt-get";  return; fi
  if cmd_exists dnf;     then echo "dnf";      return; fi
  if cmd_exists pacman;  then echo "pacman";   return; fi
  if cmd_exists zypper;  then echo "zypper";   return; fi
  if cmd_exists apk;     then echo "apk";      return; fi
  if cmd_exists emerge;  then echo "emerge";   return; fi
  echo "unknown"
}

install_packages() {
  local pm="$1"
  shift
  local pkgs=("$@")
  [ ${#pkgs[@]} -eq 0 ] && return 0

  report "  >> Пакетный менеджер: ${pm}"
  report "  >> Пакеты: ${pkgs[*]}"

  case "$pm" in
    apt-get)
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkgs[@]}" 2>/dev/null
      return $?
      ;;
    dnf)
      sudo dnf install -y -q "${pkgs[@]}" 2>/dev/null
      return $?
      ;;
    pacman)
      sudo pacman -S --noconfirm "${pkgs[@]}" 2>/dev/null
      return $?
      ;;
    zypper)
      sudo zypper install -y "${pkgs[@]}" 2>/dev/null
      return $?
      ;;
    apk)
      sudo apk add "${pkgs[@]}" 2>/dev/null
      return $?
      ;;
    emerge)
      sudo emerge "${pkgs[@]}" 2>/dev/null
      return $?
      ;;
  esac
  return 1
}

check_deps() {
  section "0. Зависимости и установка пакетов"

  local pm
  pm=$(detect_pm)
  report "  >> Пакетный менеджер: ${pm}"
  json_set "deps" "pm" "${pm}"

  # Критические — без них ничего не работает
  local critical=("ip" "ss" "curl")
  local missing_critical=()
  for bin in "${critical[@]}"; do
    cmd_exists "$bin" || missing_critical+=("$bin")
  done
  if [ ${#missing_critical[@]} -gt 0 ]; then
    fail "Критические утилиты отсутствуют: ${missing_critical[*]}"
    recommend "Установите iproute2, iproute2, curl через пакетный менеджер"
  else
    ok "Критические утилиты есть: ip, ss, curl"
  fi

  # Опциональные — разбивка по пакетным менеджерам
  local apt_pkgs=() dnf_pkgs=() pacman_pkgs=()
  local zypper_pkgs=() apk_pkgs=() emerge_pkgs=()

  # resolve
  if ! cmd_exists dig && ! cmd_exists nslookup; then
    apt_pkgs+=(dnsutils); dnf_pkgs+=(bind-utils); pacman_pkgs+=(bind)
    zypper_pkgs+=(bind-utils); apk_pkgs+=(bind-tools); emerge_pkgs+=(net-dns/bind-tools)
  fi

  # ping
  if ! cmd_exists ping; then
    apt_pkgs+=(iputils-ping); dnf_pkgs+=(iputils); pacman_pkgs+=(iputils)
    zypper_pkgs+=(iputils); apk_pkgs+=(iputils); emerge_pkgs+=(net-misc/iputils)
  fi

  # traceroute
  if ! cmd_exists traceroute; then
    apt_pkgs+=(inetutils-traceroute); dnf_pkgs+=(traceroute); pacman_pkgs+=(traceroute)
    zypper_pkgs+=(traceroute); apk_pkgs+=(traceroute); emerge_pkgs+=(net-analyzer/traceroute)
  fi

  # mtr
  if ! cmd_exists mtr; then
    apt_pkgs+=(mtr); dnf_pkgs+=(mtr); pacman_pkgs+=(mtr)
    zypper_pkgs+=(mtr); apk_pkgs+=(mtr); emerge_pkgs+=(net-analyzer/mtr)
  fi

  # ethtool
  if ! cmd_exists ethtool; then
    apt_pkgs+=(ethtool); dnf_pkgs+=(ethtool); pacman_pkgs+=(ethtool)
    zypper_pkgs+=(ethtool); apk_pkgs+=(ethtool); emerge_pkgs+=(sys-apps/ethtool)
  fi

  # conntrack
  if ! cmd_exists conntrack; then
    apt_pkgs+=(conntrack); dnf_pkgs+=(conntrack); pacman_pkgs+=(conntrack-tools)
    zypper_pkgs+=(conntrack-tools); apk_pkgs+=(conntrack-tools); emerge_pkgs+=(net-analyzer/conntrack-tools)
  fi

  # nmap (опционально — для сканирования портов)
  if ! cmd_exists nmap; then
    apt_pkgs+=(nmap); dnf_pkgs+=(nmap); pacman_pkgs+=(nmap)
    zypper_pkgs+=(nmap); apk_pkgs+=(nmap); emerge_pkgs+=(net-analyzer/nmap)
  fi

  # iperf3 (опционально — для тестов пропускной способности)
  if ! cmd_exists iperf3; then
    apt_pkgs+=(iperf3); dnf_pkgs+=(iperf3); pacman_pkgs+=(iperf3)
    zypper_pkgs+=(iperf3); apk_pkgs+=(iperf3); emerge_pkgs+=(net-misc/iperf)
  fi

  # jq (для JSON)
  if ! cmd_exists jq; then
    apt_pkgs+=(jq); dnf_pkgs+=(jq); pacman_pkgs+=(jq)
    zypper_pkgs+=(jq); apk_pkgs+=(jq); emerge_pkgs+=(app-misc/jq)
  fi

  # nc (netcat) — для тестов портов
  if ! cmd_exists nc && ! cmd_exists ncat; then
    apt_pkgs+=(netcat-openbsd); dnf_pkgs+=(nmap-ncat); pacman_pkgs+=(gnu-netcat)
    zypper_pkgs+=(netcat-openbsd); apk_pkgs+=(netcat-openbsd)
  fi

  # iptables / nft (хотя бы один)
  if ! cmd_exists iptables && ! cmd_exists nft; then
    apt_pkgs+=(iptables); dnf_pkgs+=(iptables); pacman_pkgs+=(iptables)
    zypper_pkgs+=(iptables); apk_pkgs+=(iptables)
  fi

  # Определяем, какие пакеты ставить
  local to_install=()
  case "$pm" in
    apt-get) to_install=("${apt_pkgs[@]}") ;;
    dnf)     to_install=("${dnf_pkgs[@]}") ;;
    pacman)  to_install=("${pacman_pkgs[@]}") ;;
    zypper)  to_install=("${zypper_pkgs[@]}") ;;
    apk)     to_install=("${apk_pkgs[@]}") ;;
    emerge)  to_install=("${emerge_pkgs[@]}") ;;
  esac

  # Удаляем дубликаты
  if [ ${#to_install[@]} -gt 0 ]; then
    mapfile -t to_install < <(printf '%s\n' "${to_install[@]}" | sort -u)
  fi

  # Установка
  if [ ${#to_install[@]} -gt 0 ] && [ "$AUTO_INSTALL" = true ]; then
    if [ "$pm" != "unknown" ]; then
      report "  >> Установка ${#to_install[@]} пакетов..."
      if install_packages "$pm" "${to_install[@]}"; then
        ok "${#to_install[@]} пакетов установлено"
      else
        warn "Некоторые пакеты не установились (проверьте sudo/подключение)"
      fi
    else
      warn "Пакетный менеджер не определён — установка вручную: ${to_install[*]}"
      recommend "Установите вручную: ${to_install[*]}"
    fi
  elif [ ${#to_install[@]} -gt 0 ] && [ "$AUTO_INSTALL" = false ]; then
    warn "Пропущена установка (--no-install). Нужны: ${to_install[*]}"
  else
    ok "Все пакеты установлены"
  fi

  # Python-зависимости (опционально)
  if cmd_exists python3; then
    local pip_pkgs=()
    if ! python3 -c "import json" &>/dev/null; then
      pip_pkgs+=("json")
    fi
    # yamllint для проверки YAML
    if ! python3 -c "import yamllint" &>/dev/null 2>&1 && ! cmd_exists yamllint; then
      pip_pkgs+=("yamllint")
    fi
    if [ ${#pip_pkgs[@]} -gt 0 ] && [ "$AUTO_INSTALL" = true ]; then
      if cmd_exists pip3; then
        pip3 install --quiet "${pip_pkgs[@]}" 2>/dev/null && \
          report "  >> pip: ${pip_pkgs[*]} установлены" || true
      elif cmd_exists pip; then
        pip install --quiet "${pip_pkgs[@]}" 2>/dev/null && \
          report "  >> pip: ${pip_pkgs[*]} установлены" || true
      fi
    fi
  fi
}

# ==============================================================================
#  1. ОБЩАЯ ИНФОРМАЦИЯ О СИСТЕМЕ
# ==============================================================================

section_01_system() {
  # ОС
  if [ -f /etc/os-release ]; then
    local os_name os_id os_version_id
    os_name=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || echo "N/A")
    os_id=$(grep -oP '^ID=\K.+' /etc/os-release 2>/dev/null || echo "N/A")
    os_version_id=$(grep -oP 'VERSION_ID="\K[^"]+' /etc/os-release 2>/dev/null || echo "N/A")
    report "  ОС: ${os_name} (${os_id} ${os_version_id})"
    json_set "system" "os" "${os_name}"
    json_set "system" "os_id" "${os_id}"
    json_set "system" "os_version" "${os_version_id}"
    ok "ОС: ${os_name}"
  else
    fail "/etc/os-release не найден"
  fi

  # Ядро
  local kernel kernel_release
  kernel=$(uname -s 2>/dev/null || echo "N/A")
  kernel_release=$(uname -r 2>/dev/null || echo "N/A")
  report "  Ядро: ${kernel} ${kernel_release}"
  json_set "system" "kernel" "${kernel} ${kernel_release}"
  ok "Версия ядра: ${kernel_release}"

  # Аптайм
  local uptime_sec uptime_pretty
  uptime_sec=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
  uptime_pretty=$(uptime -p 2>/dev/null || echo "N/A")
  report "  Аптайм: ${uptime_pretty} (${uptime_sec}s)"
  json_set "system" "uptime_sec" "${uptime_sec}"
  ok "Система работает: ${uptime_pretty}"

  # Хостнейм
  local hostname_str fqdn
  hostname_str=$(hostname 2>/dev/null || echo "N/A")
  fqdn=$(hostname -f 2>/dev/null || echo "N/A")
  report "  Хостнейм: ${hostname_str} (FQDN: ${fqdn})"
  json_set "system" "hostname" "${hostname_str}"
  ok "Хостнейм: ${hostname_str}"

  # Архитектура
  local arch
  arch=$(uname -m 2>/dev/null || echo "N/A")
  report "  Архитектура: ${arch}"
  json_set "system" "arch" "${arch}"

  # Дата/время
  report "  Время отчёта: ${TIMESTAMP}"
  json_set "system" "timestamp" "${TIMESTAMP}"

  # NTP
  if cmd_exists timedatectl; then
    local ntp_sync ntp_service
    ntp_sync=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null || echo "no")
    ntp_service=$(timedatectl show --property=NTP --value 2>/dev/null || echo "inactive")
    json_set "system" "ntp_sync" "${ntp_sync}"
    json_set "system" "ntp_service" "${ntp_service}"
    if [ "$ntp_sync" = "yes" ]; then
      ok "NTP синхронизация: включена"
    else
      warn "NTP синхронизация: отключена"
      recommend "Включите NTP: timedatectl set-ntp true"
    fi
  fi

  # CPU
  local cpu_info cpu_cores
  cpu_info=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //' || echo "N/A")
  cpu_cores=$(nproc 2>/dev/null || echo "N/A")
  report "  CPU: ${cpu_info} (${cpu_cores} ядер)"
  json_set "system" "cpu" "${cpu_info}"
  json_set "system" "cpu_cores" "${cpu_cores}"

  # Память
  local mem_total mem_avail
  mem_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo "N/A")
  mem_avail=$(free -h 2>/dev/null | awk '/^Mem:/{print $7}' || echo "N/A")
  report "  Память: ${mem_avail} доступно из ${mem_total}"
  json_set "system" "memory_total" "${mem_total}"
  json_set "system" "memory_avail" "${mem_avail}"

  # Load average
  local loadavg
  loadavg=$(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || echo "N/A")
  report "  Load average: ${loadavg}"
  json_set "system" "loadavg" "${loadavg}"

  # SELinux / AppArmor
  if cmd_exists getenforce; then
    local se_status
    se_status=$(getenforce 2>/dev/null || echo "N/A")
    json_set "system" "selinux" "${se_status}"
    if [ "$se_status" = "Enforcing" ]; then
      warn "SELinux: Enforcing — может блокировать сетевые сокеты"
      recommend "Проверьте SELinux: getenforce. Для отладки: setenforce 0"
    else
      report "  SELinux: ${se_status}"
    fi
  elif [ -f /sys/module/apparmor/parameters/enabled ]; then
    local aa_status
    aa_status=$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)
    json_set "system" "apparmor" "${aa_status}"
    [ "$aa_status" = "Y" ] && report "  AppArmor: включён" || report "  AppArmor: выключен"
  fi

  # Виртуализация
  if cmd_exists systemd-detect-virt; then
    local virt
    virt=$(systemd-detect-virt 2>/dev/null | head -1 || echo "none")
    report "  Виртуализация: ${virt}"
    json_set "system" "virtualization" "${virt}"
    if [ "$virt" != "none" ] && [ "$virt" != "kvm" ]; then
      warn "Обнаружена виртуализация: ${virt} — возможны ограничения сети"
    fi
  fi
}

register_section "1" "Общая информация о системе" section_01_system

# ==============================================================================
#  2. СЕТЕВЫЕ ИНТЕРФЕЙСЫ
# ==============================================================================

section_02_interfaces() {
  if ! cmd_exists ip; then
    fail "ip (iproute2) не найден — пропуск секции"
    return
  fi

  subsection "Список интерфейсов"
  run_cmd "ip -br addr" "ip -br addr" true

  local interfaces
  interfaces=$(ip -br link 2>/dev/null | awk '{print $1}')
  local iface_count=0 up_count=0

  report "  >> Анализ интерфейсов:"
  for iface in $interfaces; do
    ((iface_count++))
    local state mtu mac
    state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')
    mtu=$(ip link show "$iface" 2>/dev/null | grep -oP 'mtu \K\d+' || echo "N/A")
    mac=$(ip link show "$iface" 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' || echo "N/A")

    if [ "$state" = "UP" ]; then
      ((up_count++))
      report "    ${iface}: UP, MTU=${mtu}, MAC=${mac}"
      json_set "interfaces.${iface}" "state" "UP"
      json_set "interfaces.${iface}" "mtu" "${mtu}"
      json_set "interfaces.${iface}" "mac" "${mac}"

      if [ "$mtu" != "N/A" ] && [ "$mtu" -lt 1400 ] 2>/dev/null; then
        warn "MTU ${mtu} на ${iface} ниже 1400 — проблемы с VPN/прокси"
        recommend "Увеличьте MTU: ip link set dev ${iface} mtu 1500"
      fi
    else
      report "    ${iface}: ${state}"
      json_set "interfaces.${iface}" "state" "${state}"
    fi
  done
  ok "Интерфейсов: ${iface_count}, активных: ${up_count}"
  json_set "interfaces" "count" "${iface_count}"
  json_set "interfaces" "up_count" "${up_count}"

  # Loopback
  if cmd_exists ping; then
    if ping -c 1 -W 1 127.0.0.1 &>/dev/null; then
      ok "Loopback (127.0.0.1) доступен"
    else
      fail "Loopback (127.0.0.1) НЕ доступен"
    fi
  fi

  # ethtool
  if cmd_exists ethtool; then
    subsection "NIC-параметры (ethtool)"
    local phys_ifaces
    phys_ifaces=$(ip -br link 2>/dev/null | awk '/^[^l]/ {print $1}')
    for iface in $phys_ifaces; do
      local state
      state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')
      # Только физические (не veth, не bridge)
      if [ "$state" != "LOOPBACK" ]; then
        local speed duplex driver
        speed=$(ethtool "$iface" 2>/dev/null | grep -i 'Speed:' | awk '{print $2}' || echo "N/A")
        duplex=$(ethtool "$iface" 2>/dev/null | grep -i 'Duplex:' | awk '{print $2}' || echo "N/A")
        driver=$(ethtool -i "$iface" 2>/dev/null | grep 'driver:' | awk '{print $2}' || echo "N/A")
        report "  >> ${iface}: Speed=${speed}, Duplex=${duplex}, Driver=${driver}"
        json_set "ethtool.${iface}" "speed" "${speed}"
        json_set "ethtool.${iface}" "duplex" "${duplex}"
        json_set "ethtool.${iface}" "driver" "${driver}"

        # Offload-фичи
        local gro gso tso
        gro=$(ethtool -k "$iface" 2>/dev/null | grep 'generic-receive-offload' | awk '{print $2}' || echo "N/A")
        gso=$(ethtool -k "$iface" 2>/dev/null | grep 'generic-segmentation-offload' | awk '{print $2}' || echo "N/A")
        tso=$(ethtool -k "$iface" 2>/dev/null | grep 'tcp-segmentation-offload' | awk '{print $2}' || echo "N/A")
        report "      GRO=${gro}, GSO=${gso}, TSO=${tso}"
        json_set "ethtool.${iface}" "gro" "${gro}"
        json_set "ethtool.${iface}" "gso" "${gso}"
        json_set "ethtool.${iface}" "tso" "${tso}"

        # Проверка TSO — может вызывать проблемы с VPN
        if [ "$tso" = "on" ]; then
          warn "TSO включён на ${iface} — может вызывать фрагментацию VPN-пакетов"
          recommend "Отключите TSO: ethtool -K ${iface} tso off"
        fi
        if [ "$gro" = "on" ]; then
          warn "GRO включён на ${iface} — может влиять на VPN-производительность"
          recommend "Отключите GRO: ethtool -K ${iface} gro off"
        fi
      fi
    done
  fi

  # Wireless
  if cmd_exists iwconfig; then
    local wl_ifaces
    wl_ifaces=$(iwconfig 2>/dev/null | grep -oP '^\S+' || echo "")
    if [ -n "$wl_ifaces" ]; then
      subsection "Wi-Fi интерфейсы"
      run_cmd "iwconfig" "iwconfig 2>/dev/null" true
      for wl in $wl_ifaces; do
        local wl_signal wl_essid
        wl_signal=$(iwconfig "$wl" 2>/dev/null | grep -oP 'Signal level[=:]\S+' || echo "N/A")
        wl_essid=$(iwconfig "$wl" 2>/dev/null | grep -oP 'ESSID:"\K[^"]+' || echo "N/A")
        report "  >> ${wl}: ESSID=${wl_essid}, ${wl_signal}"
        json_set "wireless.${wl}" "essid" "${wl_essid}"
        json_set "wireless.${wl}" "signal" "${wl_signal}"
      done
    fi
  fi

  # NetworkManager
  if cmd_exists nmcli; then
    subsection "NetworkManager"
    local nm_state nm_connectivity
    nm_state=$(nmcli -t -f STATE general 2>/dev/null || echo "N/A")
    nm_connectivity=$(nmcli -t -f CONNECTIVITY general 2>/dev/null || echo "N/A")
    report "  >> Состояние: ${nm_state}"
    report "  >> Связность: ${nm_connectivity}"
    json_set "networkmanager" "state" "${nm_state}"
    json_set "networkmanager" "connectivity" "${nm_connectivity}"

    if [ "$nm_state" != "connected" ] && [ "$nm_state" != "N/A" ]; then
      warn "NetworkManager: ${nm_state} — возможны проблемы с сетью"
    fi
  fi
}

register_section "2" "Сетевые интерфейсы" section_02_interfaces

# ==============================================================================
#  3. МАРШРУТИЗАЦИЯ
# ==============================================================================

section_03_routing() {
  if ! cmd_exists ip; then
    fail "ip не найден — пропуск"
    return
  fi

  subsection "Основная таблица маршрутизации"
  run_cmd "ip route" "ip route show 2>/dev/null" true

  # Дефолтный шлюз
  local gateway gw_ip gw_iface
  gateway=$(ip route show default 2>/dev/null | head -1 || echo "N/A")
  if [ "$gateway" != "N/A" ] && [ -n "$gateway" ]; then
    gw_ip=$(echo "$gateway" | awk '{print $3}')
    gw_iface=$(echo "$gateway" | awk '{print $5}')
    report "  >> Default gateway: ${gw_ip} via ${gw_iface}"
    json_set "routing" "gateway_ip" "${gw_ip}"
    json_set "routing" "gateway_iface" "${gw_iface}"

    if cmd_exists ping; then
      if ping -c 1 -W 2 "$gw_ip" &>/dev/null; then
        ok "Шлюз ${gw_ip} (${gw_iface}) отвечает на ping"
      else
        warn "Шлюз ${gw_ip} НЕ отвечает на ping"
        recommend "Проверьте L2-связность: ip neigh show ${gw_ip}"
      fi
    fi
  else
    warn "Дефолтный шлюз НЕ найден"
    recommend "Проверьте маршрутизацию: ip route show default"
  fi

  # Несколько шлюзов
  local gw_count
  gw_count=$(ip route show default 2>/dev/null | wc -l)
  if [ "$gw_count" -gt 1 ]; then
    warn "${gw_count} дефолтных шлюзов — возможны проблемы"
    recommend "Оставьте один gateway: ip route del default via ..."
  fi
  json_set "routing" "gateway_count" "${gw_count}"

  # IPv6
  subsection "IPv6 маршрутизация"
  if ip -6 route show default &>/dev/null; then
    local gw6
    gw6=$(ip -6 route show default 2>/dev/null | head -1)
    report "  >> IPv6 default: ${gw6}"
    json_set "routing" "ipv6_gateway" "$(echo "$gw6" | awk '{print $3}')"
    ok "IPv6 маршрутизация активна"
  else
    warn "IPv6 маршрут по умолчанию не найден"
  fi

  # Таблица маршрутизации (все)
  subsection "Все маршруты (первые 40)"
  run_cmd "ip route show table all" "ip route show table all 2>/dev/null | head -40" true

  # Правила маршрутизации (policy routing)
  subsection "Правила маршрутизации (ip rule)"
  run_cmd "ip rule show" "ip rule show 2>/dev/null" true
  local rule_count
  rule_count=$(ip rule show 2>/dev/null | wc -l)
  json_set "routing" "policy_rules" "${rule_count}"
  if [ "$rule_count" -gt 10 ]; then
    warn "${rule_count} policy rules — сложная маршрутизация"
  fi

  # ARP/neighbour
  subsection "ARP-таблица (neighbours)"
  run_cmd "ip neigh" "ip neigh show 2>/dev/null" true
  local neigh_count neigh_failed
    neigh_count=$(ip neigh show 2>/dev/null | grep -cE 'REACHABLE|STALE|DELAY')
    neigh_failed=$(ip neigh show 2>/dev/null | grep -cE 'FAILED|INCOMPLETE')
  json_set "routing" "arp_reachable" "${neigh_count}"
  json_set "routing" "arp_failed" "${neigh_failed}"
  report "  >> Доступных: ${neigh_count}, проблемных: ${neigh_failed}"
  if [ "$neigh_count" -eq 0 ]; then
    warn "Нет доступных ARP-записей — возможны проблемы с L2"
  fi
  if [ "$neigh_failed" -gt 0 ]; then
    warn "${neigh_failed} ARP-записей FAILED/INCOMPLETE"
    recommend "Проверьте ARP: ip neigh show | grep -E 'FAILED|INCOMPLETE'"
  fi
}

register_section "3" "Маршрутизация" section_03_routing

# ==============================================================================
#  4. DNS
# ==============================================================================

section_04_dns() {
  # /etc/resolv.conf
  subsection "resolv.conf"
  if [ -f /etc/resolv.conf ]; then
    run_cmd "cat /etc/resolv.conf" "cat /etc/resolv.conf" true
    local resolv_type
    resolv_type=$(file /etc/resolv.conf 2>/dev/null | grep -oP 'symbolic link to \K.*' || echo "regular file")
    report "  >> Тип: ${resolv_type}"
    json_set "dns" "resolv_type" "${resolv_type}"

    local ns_list ns_count
    mapfile -t ns_list < <(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    ns_count=${#ns_list[@]}
    json_set "dns" "nameservers" "${ns_list[*]}"
    if [ "$ns_count" -eq 0 ]; then
      fail "Нет nameserver в /etc/resolv.conf"
      recommend "Настройте DNS: добавьте nameserver в /etc/resolv.conf"
    else
      ok "nameserver в resolv.conf: ${ns_count} (${ns_list[*]})"
    fi

    # Поиск Cloudflare/Google DNS — признак кастомного DNS
    for ns in "${ns_list[@]}"; do
      if [[ "$ns" == "127.0.0.1" ]] || [[ "$ns" == "::1" ]]; then
        if cmd_exists ss; then
          if ss -ulnp "sport = :53" 2>/dev/null | grep -q LISTEN; then
            report "  >> Зарезолверен на localhost:53 (dnsmasq/systemd-resolved)"
          fi
        fi
      fi
    done
  else
    fail "/etc/resolv.conf не существует"
  fi

  # systemd-resolved
  subsection "systemd-resolved / resolvectl"
  if cmd_exists resolvectl; then
    run_cmd "resolvectl status" "resolvectl status 2>/dev/null" true
    local dns_servers
    dns_servers=$(resolvectl dns 2>/dev/null | grep -oP '[0-9.]+' | head -5 | tr '\n' ' ' || echo "N/A")
    json_set "dns" "resolvectl_servers" "${dns_servers}"
    ok "systemd-resolved: ${dns_servers}"
  else
    report "  systemd-resolved: не обнаружен"
  fi

  # /etc/hosts
  subsection "/etc/hosts"
  if [ -f /etc/hosts ]; then
    local hosts_total hosts_active
    hosts_total=$(wc -l < /etc/hosts 2>/dev/null || echo 0)
    hosts_active=$(grep -vcE '^\s*(#|$)' /etc/hosts 2>/dev/null || echo 0)
    local has_localhost
    grep -qE '127\.0\.0\.1\s+localhost' /etc/hosts 2>/dev/null && has_localhost="yes" || has_localhost="no"
    json_set "dns" "hosts_total" "${hosts_total}"
    json_set "dns" "hosts_active" "${hosts_active}"

    report "  >> Всего строк: ${hosts_total}, активных: ${hosts_active}, localhost: ${has_localhost}"
    if grep -q '^0\.0\.0\.0' /etc/hosts 2>/dev/null; then
      local blocked
      blocked=$(grep -c '^0\.0\.0\.0' /etc/hosts 2>/dev/null)
      warn "/etc/hosts содержит ${blocked} заблокированных доменов (0.0.0.0)"
      json_set "dns" "hosts_blocked" "${blocked}"
    fi
    if grep -qE '(vk\.com|ok\.ru|yandex\.ru|mail\.ru)' /etc/hosts 2>/dev/null; then
      warn "/etc/hosts блокирует российские ресурсы"
    fi
    ok "/etc/hosts: ${hosts_active} активных записей"
  else
    fail "/etc/hosts не существует"
  fi

  # DNS-тесты
  subsection "DNS-резолвинг (тесты)"

  local dns_servers=(
    "8.8.8.8:Google DNS"
    "1.1.1.1:Cloudflare DNS"
    "77.88.8.8:Yandex DNS"
  )
  local dns_names=(
    "google.com"
    "github.com"
    "runetfreedom.github.io"
  )

  if cmd_exists dig; then
    for server_entry in "${dns_servers[@]}"; do
      local server="${server_entry%%:*}"
      local sname="${server_entry##*:}"
      if dig @"${server}" google.com +short +time=2 +tries=1 &>/dev/null; then
        ok "DNS ${sname} (${server}) отвечает"
      else
        warn "DNS ${sname} (${server}) НЕ отвечает"
        recommend "Проверьте: dig @${server} google.com"
      fi
    done

    for name in "${dns_names[@]}"; do
      local resolved_ip
      resolved_ip=$(dig +short "$name" +time=2 +tries=1 2>/dev/null | head -1)
      if [ -n "$resolved_ip" ]; then
        ok "Резолвинг ${name}: ${resolved_ip}"
        json_set "dns.resolve.${name}" "ip" "${resolved_ip}"
      else
        warn "Резолвинг ${name}: не удался"
        recommend "Проверьте DNS: dig ${name}"
      fi
    done
  elif cmd_exists nslookup; then
    for name in "${dns_names[@]}"; do
      local resolved_ip
      resolved_ip=$(nslookup "$name" 2>/dev/null | grep -A1 'Name:' | grep -oP 'Address: \K[0-9.]+' | head -1)
      [ -n "$resolved_ip" ] && ok "Резолвинг ${name}: ${resolved_ip}" || warn "Резолвинг ${name}: не удался"
    done
  else
    warn "dig и nslookup не найдены — DNS-тесты пропущены"
  fi

  # DoH
  if cmd_exists curl; then
    subsection "DNS-over-HTTPS (DoH)"
    local doh_ok=true
    for doh_url in "https://dns.google/dns-query?name=google.com&type=A" \
                   "https://cloudflare-dns.com/dns-query?name=google.com&type=A"; do
      local doh_code
      doh_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$doh_url" 2>/dev/null || echo "000")
      if echo "$doh_code" | grep -qE '200|405'; then
        report "  >> DoH: $(echo "$doh_url" | cut -d/ -f3) OK (${doh_code})"
      else
        report "  >> DoH: $(echo "$doh_url" | cut -d/ -f3) = ${doh_code}"
        doh_ok=false
      fi
    done
    if $doh_ok; then
      ok "DoH-серверы доступны"
    else
      warn "Некоторые DoH-серверы недоступны — DNS через прокси может не работать"
    fi
    json_set "dns" "doh_ok" "${doh_ok}"
  fi

  # DNS-задержка
  if cmd_exists dig; then
    local dns_rtt
    dns_rtt=$(dig +stats google.com 2>/dev/null | grep 'Query time' | grep -oP '\d+' || echo "N/A")
    report "  >> DNS latency: ${dns_rtt} ms"
    json_set "dns" "latency_ms" "${dns_rtt}"
    if [ "$dns_rtt" != "N/A" ] && [ "$dns_rtt" -gt 500 ] 2>/dev/null; then
      warn "Высокая задержка DNS: ${dns_rtt}ms"
      recommend "Смените DNS-сервер на более быстрый (1.1.1.1 или 8.8.8.8)"
    fi
  fi
}

register_section "4" "DNS" section_04_dns

# ==============================================================================
#  5. СИСТЕМНЫЙ ПРОКСИ
# ==============================================================================

section_05_proxy() {
  # GNOME
  subsection "GNOME — gsettings"
  if cmd_exists gsettings && gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.system.proxy'; then
    local proxy_mode
    proxy_mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "N/A")
    json_set "proxy" "gnome_mode" "${proxy_mode}"
    case "$proxy_mode" in
      "'manual'")
        local http_host http_port socks_host socks_port ignore_hosts
        http_host=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null || echo "N/A")
        http_port=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null || echo "N/A")
        socks_host=$(gsettings get org.gnome.system.proxy.socks host 2>/dev/null || echo "N/A")
        socks_port=$(gsettings get org.gnome.system.proxy.socks port 2>/dev/null || echo "N/A")
        ignore_hosts=$(gsettings get org.gnome.system.proxy ignore-hosts 2>/dev/null || echo "N/A")
        json_set "proxy" "gnome_http" "${http_host}:${http_port}"
        json_set "proxy" "gnome_socks" "${socks_host}:${socks_port}"
        report "  >> HTTP: ${http_host}:${http_port}, SOCKS: ${socks_host}:${socks_port}"
        ok "GNOME прокси: manual"

        if echo "$ignore_hosts" | grep -q '\.ru'; then
          ok "Российские домены в ignore-hosts"
        else
          warn "В ignore-hosts нет .ru"
          recommend "Добавьте .ru, .su, .xn--p1ai в ignore-hosts"
        fi
        ;;
      "'none'")       warn "GNOME прокси выключен" ;;
      *)              report "  GNOME прокси: ${proxy_mode}" ;;
    esac
  else
    report "  GNOME gsettings: не обнаружен"
  fi

  # KDE
  subsection "KDE — kioslaverc"
  local kioslaverc=""
  [ -f "${HOME}/.config/kioslaverc" ] && kioslaverc="${HOME}/.config/kioslaverc"
  [ -f "${HOME}/.config/kioslaverc5" ] && kioslaverc="${HOME}/.config/kioslaverc5"
  if [ -n "$kioslaverc" ]; then
    local kde_proxy_type
    kde_proxy_type=$(grep -oP 'ProxyType=\K\d' "$kioslaverc" 2>/dev/null || echo "?")
    json_set "proxy" "kde_proxy_type" "${kde_proxy_type}"
    case "$kde_proxy_type" in
      1) ok "KDE прокси: включён" ;;
      0) warn "KDE прокси: выключен" ;;
      *) report "KDE ProxyType: ${kde_proxy_type}" ;;
    esac
  else
    report "  KDE kioslaverc: не найден"
  fi

  # Переменные окружения
  subsection "Переменные окружения"
  local env_vars=("http_proxy" "https_proxy" "HTTP_PROXY" "HTTPS_PROXY" "no_proxy" "NO_PROXY" "all_proxy" "ALL_PROXY")
  local env_found=false
  for var in "${env_vars[@]}"; do
    if [ -n "${!var:-}" ]; then
      report "  >> ${var}=${!var}"
      json_set "proxy.env.${var}" "value" "${!var}"
      env_found=true
    fi
  done
  if $env_found; then
    warn "Переменные окружения прокси — могут конфликтовать с gsettings"
    recommend "Проверьте /etc/environment и ~/.bashrc на http_proxy"
  else
    ok "Переменные окружения прокси не установлены"
  fi

  # Слушающие прокси-порты
  subsection "Прокси-порты"
  if cmd_exists ss; then
    for port in 10808 10809 1080 3128 8080 9050; do
      if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q LISTEN; then
        local proc
        proc=$(ss -tlnp "sport = :${port}" 2>/dev/null | grep -oP 'users:\(\(\K[^)]+' || echo "?")
        report "  >> ${port}: слушается (${proc})"
        json_set "proxy.ports" "${port}" "${proc}"
      fi
    done
  fi
}

register_section "5" "Системный прокси" section_05_proxy

# ==============================================================================
#  6. ФАЙРВОЛ
# ==============================================================================

section_06_firewall() {
  # iptables
  if cmd_exists iptables; then
    subsection "iptables — filter INPUT"
    run_cmd "iptables -L INPUT -n" "sudo iptables -L INPUT -n --line-numbers 2>/dev/null || iptables -L INPUT -n --line-numbers 2>/dev/null || echo '(требуются права root)'" true

    subsection "iptables — filter OUTPUT"
    run_cmd "iptables -L OUTPUT -n" "sudo iptables -L OUTPUT -n --line-numbers 2>/dev/null || iptables -L OUTPUT -n --line-numbers 2>/dev/null || echo '(требуются права root)'" true

    # V2RAYN chain
    if iptables -L V2RAYN &>/dev/null 2>&1; then
      ok "Цепочка V2RAYN (kill-switch) активна"
      json_set "firewall" "v2rayn_chain" "active"
      run_cmd "iptables V2RAYN" "iptables -L V2RAYN -n --line-numbers 2>/dev/null || sudo iptables -L V2RAYN -n --line-numbers 2>/dev/null" true
    else
      warn "Цепочка V2RAYN не найдена (kill-switch не установлен)"
      json_set "firewall" "v2rayn_chain" "none"
      recommend "Установите kill-switch: ./scripts/kill-switch.sh on"
    fi

    # NAT
    iptables -t nat -L POSTROUTING 2>/dev/null | grep -q 'MASQUERADE\|SNAT\|DNAT' && {
      warn "NAT активен — возможен TUN-режим"
      run_cmd "iptables nat" "iptables -t nat -L POSTROUTING -n 2>/dev/null || sudo iptables -t nat -L POSTROUTING -n 2>/dev/null" true
    }

    # Политики по умолчанию
    local pol_input pol_output
    pol_input=$(sudo iptables -L INPUT -n 2>/dev/null | head -1 | awk '{print $4}' || iptables -L INPUT -n 2>/dev/null | head -1 | awk '{print $4}' || echo "N/A")
    pol_output=$(sudo iptables -L OUTPUT -n 2>/dev/null | head -1 | awk '{print $4}' || iptables -L OUTPUT -n 2>/dev/null | head -1 | awk '{print $4}' || echo "N/A")
    report "  >> Политики: INPUT=${pol_input}, OUTPUT=${pol_output}"
    json_set "firewall" "policy_input" "${pol_input}"
    json_set "firewall" "policy_output" "${pol_output}"

    if [ "${pol_input}" = "DROP" ] || [ "${pol_input}" = "REJECT" ]; then
      ok "INPUT политика: ${pol_input} (безопасно)"
    fi
  else
    report "  iptables: не найден"
  fi

  # nftables
  if cmd_exists nft; then
    subsection "nftables"
    run_cmd "nft list ruleset" "sudo nft list ruleset 2>/dev/null" true
    if sudo nft list table inet filter 2>/dev/null | grep -q 'v2ray\|V2RAYN' 2>/dev/null; then
      ok "V2RAYN правила в nftables"
      json_set "firewall" "v2rayn_nftables" "active"
    fi
    json_set "firewall" "nftables" "available"
  fi

  # ufw
  if cmd_exists ufw; then
    subsection "ufw"
    local ufw_status
    ufw_status=$(sudo ufw status 2>/dev/null || ufw status 2>/dev/null || echo "inactive")
    json_set "firewall" "ufw" "${uf_status:-inactive}"
    report "  >> ufw: $(echo "$ufw_status" | head -1)"
    echo "$ufw_status" | grep -qi 'active' && ok "ufw активен"
  fi

  # firewalld
  if cmd_exists firewall-cmd; then
    subsection "firewalld"
    local fw_state
    fw_state=$(sudo firewall-cmd --state 2>/dev/null || firewall-cmd --state 2>/dev/null || echo "not running")
    json_set "firewall" "firewalld" "${fw_state}"
    report "  >> firewalld: ${fw_state}"
  fi

  # Открытые порты (из вне)
  subsection "Открытые порты (nmap localhost)"
  if cmd_exists nmap && [ "$AUTO_INSTALL" = true ]; then
    run_cmd "nmap localhost" "nmap -sT -p 1-1024 localhost 2>/dev/null || echo '(требуются права)'" true
  else
    skip "nmap не найден"
  fi
}

register_section "6" "Файрвол (iptables/nftables)" section_06_firewall

# ==============================================================================
#  7. ПАРАМЕТРЫ ЯДРА (SYSCTL)
# ==============================================================================

section_07_sysctl() {
  # Каждый элемент: "key:desc:expected:type"
  # type: eq (равно), ge (>=), le (<=), ne (не равно), range, str
  local sysctl_keys=(
    "net.ipv4.ip_forward:IP forwarding:1:eq"
    "net.ipv6.conf.all.forwarding:IPv6 forwarding:-:info"
    "net.ipv4.conf.all.rp_filter:Reverse Path Filter (all):-:info"
    "net.ipv4.tcp_congestion_control:TCP congestion control:bbr:str"
    "net.core.default_qdisc:Default qdisc:-:info"
    "net.ipv4.tcp_fastopen:TCP Fast Open:3:ge"
    "net.ipv4.tcp_mtu_probing:TCP MTU probing:1:ge"
    "net.ipv4.conf.all.accept_redirects:Accept redirects:0:eq"
    "net.ipv4.conf.all.send_redirects:Send redirects:0:eq"
    "net.ipv4.tcp_syncookies:TCP SYN cookies:1:eq"
    "net.ipv4.conf.all.accept_source_route:Accept source route:0:eq"
    "net.ipv4.icmp_echo_ignore_broadcasts:ICMP broadcast ignore:1:eq"
    "net.ipv4.tcp_tw_reuse:TCP TIME_WAIT reuse:-:info"
    "net.ipv4.tcp_fin_timeout:TCP FIN timeout:30:le"
    "net.ipv4.tcp_keepalive_time:TCP keepalive time:-:info"
    "net.ipv4.tcp_keepalive_intvl:TCP keepalive interval:-:info"
    "net.ipv4.tcp_keepalive_probes:TCP keepalive probes:-:info"
    "net.core.netdev_max_backlog:Netdev max backlog:-:info"
    "net.core.somaxconn:Max socket backlog (SOMAXCONN):-:info"
    "net.ipv4.tcp_max_syn_backlog:TCP max SYN backlog:-:info"
    "net.netfilter.nf_conntrack_max:Conntrack max entries:262144:ge"
    "net.ipv4.tcp_rmem:TCP receive memory:-:info"
    "net.ipv4.tcp_wmem:TCP send memory:-:info"
    "net.ipv4.tcp_slow_start_after_idle:TCP slow start after idle:0:eq"
    "net.core.rmem_default:Default socket receive buffer:-:info"
    "net.core.wmem_default:Default socket send buffer:-:info"
    "net.ipv4.tcp_max_tw_buckets:TCP max TIME_WAIT buckets:-:info"
    "net.ipv4.udp_mem:UDP memory:-:info"
    "net.ipv4.tcp_notsent_lowat:TCP notsent lowat:-:info"
  )

  local bbr_enabled=false

  for entry in "${sysctl_keys[@]}"; do
    IFS=':' read -r key desc expected check_type <<< "$entry"
    local value
    value=$(sysctl -n "$key" 2>/dev/null || echo "N/A")

    if [ "$value" = "N/A" ]; then
      skip "${desc} (${key})"
      json_set "sysctl.${key}" "value" "N/A"
      continue
    fi

    json_set "sysctl.${key}" "value" "${value}"

    case "$check_type" in
      eq)
        if [ "$value" = "$expected" ]; then
          ok "${desc}: ${value} ✓"
        else
          warn "${desc}: ${value} (ожидается ${expected})"
          recommend "Исправьте: sysctl -w ${key}=${expected}"
        fi
        ;;
      ge)
        if [ "$value" -ge "$expected" ] 2>/dev/null; then
          ok "${desc}: ${value} ✓"
        else
          warn "${desc}: ${value} (минимум ${expected})"
          recommend "Увеличьте: sysctl -w ${key}=${expected}"
        fi
        ;;
      le)
        if [ "$value" -le "$expected" ] 2>/dev/null; then
          ok "${desc}: ${value} ✓"
        else
          warn "${desc}: ${value} (максимум ${expected})"
          recommend "Уменьшите: sysctl -w ${key}=${expected}"
        fi
        ;;
      str)
        if [ "$value" = "$expected" ]; then
          ok "${desc}: ${value} ✓"
          [ "$key" = "net.ipv4.tcp_congestion_control" ] && bbr_enabled=true
        else
          warn "${desc}: ${value} (рекомендуется ${expected})"
          if [ "$key" = "net.ipv4.tcp_congestion_control" ]; then
            recommend "Включите BBR: sysctl -w net.ipv4.tcp_congestion_control=bbr"
          fi
        fi
        ;;
      info|*)
        report "  ${desc}: ${value} (${key})"
        # Дополнительный анализ для некоторых ключей
        case "$key" in
          net.netfilter.nf_conntrack_max)
            report "  >> Conntrack max: ${value}"
            ;;
          net.ipv4.tcp_rmem)
            report "  >> TCP receive: ${value}"
            ;;
        esac
        ;;
    esac
  done

  # BBR + fq (рекомендуемая связка)
  if $bbr_enabled; then
    local qdisc
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "N/A")
    if [ "$qdisc" = "fq" ]; then
      ok "BBR + fq — оптимальная связка"
    else
      warn "BBR включён, но qdisc=${qdisc} (рекомендуется fq)"
      recommend "Включите fq: sysctl -w net.core.default_qdisc=fq"
    fi
  fi

  # Connection tracking
  local ct_count ct_max
  ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo "N/A")
  ct_count=$(sudo conntrack -C 2>/dev/null || conntrack -C 2>/dev/null || echo "N/A")
  if [ "$ct_count" != "N/A" ] && [ "$ct_max" != "N/A" ]; then
    local ct_pct=$(( ct_count * 100 / ct_max ))
    json_set "sysctl.conntrack" "usage_pct" "${ct_pct}"
    json_set "sysctl.conntrack" "current" "${ct_count}"
    json_set "sysctl.conntrack" "max" "${ct_max}"
    if [ "$ct_pct" -gt 80 ]; then
      warn "Conntrack: ${ct_count}/${ct_max} (${ct_pct}% — критично!)"
      recommend "Увеличьте nf_conntrack_max: sysctl -w net.netfilter.nf_conntrack_max=524288"
    elif [ "$ct_pct" -gt 50 ]; then
      report "  Conntrack: ${ct_count}/${ct_max} (${ct_pct}%)"
    else
      ok "Conntrack: ${ct_count}/${ct_max} (${ct_pct}%)"
    fi
  fi
}

register_section "7" "Параметры ядра (sysctl)" section_07_sysctl

# ==============================================================================
#  8. TUN-УСТРОЙСТВО
# ==============================================================================

section_08_tun() {
  # Устройство
  if [ -c /dev/net/tun ]; then
    local tun_perms tun_owner tun_group
    tun_perms=$(stat -c '%A' /dev/net/tun 2>/dev/null || echo "N/A")
    tun_owner=$(stat -c '%U' /dev/net/tun 2>/dev/null || echo "N/A")
    tun_group=$(stat -c '%G' /dev/net/tun 2>/dev/null || echo "N/A")
    report "  >> Права: ${tun_perms} (${tun_owner}:${tun_group})"
    json_set "tun" "device" "exists"
    json_set "tun" "permissions" "${tun_perms}"
    json_set "tun" "owner" "${tun_owner}"

    if (exec 3<>/dev/net/tun) 2>/dev/null; then
      exec 3>&-
      ok "TUN-устройство доступно для записи"
    else
      warn "TUN-устройство НЕ доступно (нужны права)"
      recommend "Добавьте пользователя в группу tun: sudo usermod -aG tun ${USER}"
    fi
  else
    fail "/dev/net/tun не существует"
    json_set "tun" "device" "missing"
    recommend "Загрузите TUN: sudo modprobe tun && echo tun | sudo tee -a /etc/modules"
  fi

  # Модуль ядра
  local tun_module=false
  if grep -q '^tun ' /proc/modules 2>/dev/null; then
    tun_module=true
  elif lsmod 2>/dev/null | grep -q '^tun'; then
    tun_module=true
  fi
  json_set "tun" "module_loaded" "${tun_module}"
  if $tun_module; then
    ok "Модуль tun загружен"
  else
    warn "Модуль tun не загружен"
    recommend "Добавьте tun в /etc/modules: echo tun | sudo tee -a /etc/modules"
  fi

  # Активные TUN-интерфейсы
  local tun_ifaces
  tun_ifaces=$(ip -br link 2>/dev/null | grep -oiP '^(tun|tap|utun)\S*' || echo "")
  if [ -n "$tun_ifaces" ]; then
    local tun_count
    tun_count=$(echo "$tun_ifaces" | wc -l)
    report "  >> TUN-интерфейсы: ${tun_ifaces//$'\n'/ }"
    json_set "tun" "active_interfaces" "${tun_ifaces//$'\n'/,}"
    ok "Активных TUN-интерфейсов: ${tun_count}"
  else
    report "  TUN-интерфейсы: нет активных"
    json_set "tun" "active_interfaces" "none"
  fi

  # Дополнительно: FDB (Forwarding Database) для TAP
  if cmd_exists bridge; then
    subsection "Bridge FDB"
    run_cmd "bridge fdb show" "bridge fdb show 2>/dev/null | head -20" true
  fi
}

register_section "8" "TUN-устройство" section_08_tun

# ==============================================================================
#  9. СЕТЕВЫЕ СОЕДИНЕНИЯ
# ==============================================================================

section_09_connections() {
  if ! cmd_exists ss; then
    fail "ss не найден — пропуск"
    return
  fi

  # TCP слушающие
  subsection "TCP — слушающие порты (30)"
  run_cmd "ss -tlnp" "ss -tlnp 2>/dev/null | tail -n +2 | awk '{print \$4}' | sort -t: -k2 -n | head -30" true

  # UDP слушающие
  subsection "UDP — слушающие порты (20)"
  run_cmd "ss -ulnp" "ss -ulnp 2>/dev/null | tail -n +2 | awk '{print \$4}' | sort -t: -k2 -n | head -20" true

  # ESTABLISHED
  subsection "ESTABLISHED TCP (топ-20)"
  run_cmd "ss -tn state established" "ss -tn state established 2>/dev/null | tail -n +2 | awk '{print \$4}' | sort | uniq -c | sort -rn | head -20" true

  # Количественные метрики
  local total_est total_listen total_timewait total_syn_sent
  total_est=$(ss -tn state established 2>/dev/null | tail -n +2 | wc -l || echo 0)
  total_listen=$(ss -tln 2>/dev/null | tail -n +2 | wc -l || echo 0)
  total_timewait=$(ss -tan state time-wait 2>/dev/null | tail -n +2 | wc -l || echo 0)
  total_syn_sent=$(ss -tan state syn-sent 2>/dev/null | tail -n +2 | wc -l || echo 0)

  json_set "connections" "established" "${total_est}"
  json_set "connections" "listen" "${total_listen}"
  json_set "connections" "timewait" "${total_timewait}"
  json_set "connections" "syn_sent" "${total_syn_sent}"

  report "  >> ESTABLISHED=${total_est}, LISTEN=${total_listen}, TIME_WAIT=${total_timewait}, SYN_SENT=${total_syn_sent}"

  ok "TCP: ESTABLISHED=${total_est}, LISTEN=${total_listen}"

  if [ "$total_timewait" -gt 1000 ]; then
    warn "TIME_WAIT: ${total_timewait} — может исчерпать порты"
    recommend "Настройте tcp_tw_reuse или увеличьте tcp_max_tw_buckets"
  elif [ "$total_timewait" -gt 0 ]; then
    report "  TIME_WAIT: ${total_timewait}"
  fi

  if [ "$total_syn_sent" -gt 100 ]; then
    warn "SYN_SENT: ${total_syn_sent} — возможны проблемы с исходящими"
    recommend "Проверьте связность: ss -tan state syn-sent"
  fi

  # v2rayN порты
  subsection "v2rayN-специфичные порты"
  for port in 10808 10809 62789; do
    if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q LISTEN; then
      local proc
      proc=$(ss -tlnp "sport = :${port}" 2>/dev/null | grep -oP 'users:\(\(\K[^)]+' || echo "?")
      ok "Порт ${port} (v2rayN) слушается: ${proc}"
      json_set "connections.v2rayn" "${port}" "listening"
    else
      report "  Порт ${port}: не слушается"
    fi
  done

  # conntrack
  if cmd_exists conntrack; then
    subsection "Connection tracking (conntrack)"
    local ct_count
    ct_count=$(sudo conntrack -C 2>/dev/null || conntrack -C 2>/dev/null || echo "N/A")
    local ct_max
    ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo "N/A")
    report "  >> Записей: ${ct_count}, Максимум: ${ct_max}"

    if [ "$ct_count" != "N/A" ] && [ "$ct_max" != "N/A" ] && [ "$ct_max" -gt 0 ] 2>/dev/null; then
      local ct_pct=$(( ct_count * 100 / ct_max ))
      json_set "connections.conntrack" "current" "${ct_count}"
      json_set "connections.conntrack" "max" "${ct_max}"
      json_set "connections.conntrack" "pct" "${ct_pct}"
      if [ "$ct_pct" -gt 80 ]; then
        warn "Conntrack: ${ct_count}/${ct_max} (${ct_pct}%)"
        recommend "Увеличьте nf_conntrack_max"
      else
        ok "Conntrack: ${ct_count}/${ct_max} (${ct_pct}%)"
      fi
    fi

    # Статистика по протоколам
    run_cmd "conntrack statistics" "sudo conntrack -S 2>/dev/null | head -10 || echo '(требуются права root)'" true
  fi

  # Все соединения (тотально — сокеты)
  local total_sockets tcp_sockets udp_sockets
  total_sockets=$(ss -tan 2>/dev/null | tail -n +2 | wc -l || echo 0)
    tcp_sockets=$(ss -tan 2>/dev/null | tail -n +2 | wc -l)
  udp_sockets=$(ss -uan 2>/dev/null | tail -n +2 | wc -l || echo 0)
  report "  >> Всего сокетов: ${total_sockets} (TCP: ${tcp_sockets}, UDP: ${udp_sockets})"
  json_set "connections" "total_sockets" "${total_sockets}"
  json_set "connections" "tcp_sockets" "${tcp_sockets}"
  json_set "connections" "udp_sockets" "${udp_sockets}"
}

register_section "9" "Сетевые соединения и порты" section_09_connections

# ==============================================================================
#  10. ТЕСТЫ СВЯЗНОСТИ
# ==============================================================================

section_10_connectivity() {
  local endpoints=(
    "1.1.1.1:Cloudflare DNS|http://1.1.1.1"
    "8.8.8.8:Google DNS|http://8.8.8.8"
    "github.com:GitHub|https://github.com"
    "raw.githubusercontent.com:GitHub RAW|https://raw.githubusercontent.com"
    "google.com:Google|https://google.com"
    "runetfreedom.github.io:runetfreedom|https://runetfreedom.github.io"
  )

  local total=0 passed=0

  if ! cmd_exists curl && ! cmd_exists wget; then
    warn "curl и wget не найдены — тесты ограничены"
  fi

  for entry in "${endpoints[@]}"; do
    local host="${entry%%:*}"
    local rest="${entry#*:}"
    local label="${rest%%|*}"
    local url="${rest#*|}"

    if cmd_exists curl; then
      local code
      code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 4 --max-time 6 "$url" 2>/dev/null || echo "000")
      if echo "$code" | grep -qE '200|301|302|307|308'; then
        ok "Связность с ${label} (${host}) = ${code}"
        ((passed++))
      elif [ "$code" = "000" ]; then
        warn "Связность с ${label} (${host}): таймаут"
      else
        warn "Связность с ${label} (${host}): HTTP ${code}"
      fi
      ((total++))
    elif cmd_exists wget; then
      if wget -q --timeout=5 --tries=1 -O /dev/null "$url" 2>/dev/null; then
        ok "Связность с ${label}"
        ((passed++))
      else
        warn "Связность с ${label}: не удалась"
      fi
      ((total++))
    fi
  done

  json_set "connectivity" "endpoints_tested" "${total}"
  json_set "connectivity" "endpoints_passed" "${passed}"

  if [ "$total" -gt 0 ]; then
    report "  >> Результат: ${passed}/${total}"
  fi

  # Ping + RTT
  if cmd_exists ping; then
    subsection "Ping + задержка"
    local ping_targets=("8.8.8.8" "1.1.1.1" "github.com")

    for target in "${ping_targets[@]}"; do
      if ping -c 1 -W 3 "$target" &>/dev/null; then
        local rtt
        rtt=$(ping -c 3 -W 2 "$target" 2>/dev/null | tail -1 | grep -oP '([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+)' || echo "")
        if [ -n "$rtt" ]; then
          local avg_rtt min_rtt max_rtt mdev
          avg_rtt=$(echo "$rtt" | cut -d/ -f2)
          min_rtt=$(echo "$rtt" | cut -d/ -f1)
          max_rtt=$(echo "$rtt" | cut -d/ -f3)
          mdev=$(echo "$rtt" | cut -d/ -f4)
          report "  >> ${target}: avg=${avg_rtt}ms, min=${min_rtt}ms, max=${max_rtt}ms, mdev=${mdev}ms"
          json_set "ping.${target}" "avg_ms" "${avg_rtt}"

          if (( $(echo "${avg_rtt:-0} > 300" | bc -l 2>/dev/null || echo 0) )); then
            warn "Высокая задержка до ${target}: ${avg_rtt}ms"
          fi
        fi
      else
        warn "Ping до ${target}: не удался"
        json_set "ping.${target}" "reachable" "false"
      fi
    done
  fi

  # mtr — path diagnostics
  if cmd_exists mtr; then
    subsection "Путь до 8.8.8.8 (mtr)"
    local mtr_out
    mtr_out=$(mtr -r -c 2 -n 8.8.8.8 2>/dev/null || echo "")
    if [ -n "$mtr_out" ]; then
      echo "$mtr_out" >> "$REPORT_FILE"
      local loss
      loss=$(echo "$mtr_out" | tail -1 | grep -oP '\d+\.\d+%' || echo "0.0%")
      json_set "mtr" "loss_percent" "${loss}"
      if [ "${loss}" != "0.0%" ] && [ "${loss}" != "0%" ]; then
        warn "Потери до 8.8.8.8: ${loss}"
        recommend "Проверьте путь: mtr -r -c 10 8.8.8.8"
      else
        ok "Потери до 8.8.8.8: ${loss}"
      fi
    fi
  fi

  # Локальный прокси-тест
  subsection "Локальный прокси"
  if ss -tlnp "sport = :10808" 2>/dev/null | grep -q LISTEN; then
    # SOCKS5
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 \
         --socks5-hostname 127.0.0.1:10808 "https://google.com" 2>/dev/null | grep -qE '200|301|302'; then
      ok "SOCKS5 прокси (127.0.0.1:10808) работает"
    else
      warn "SOCKS5 прокси (127.0.0.1:10808) НЕ работает"
    fi

    # HTTP
    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 \
         --proxy http://127.0.0.1:10809 "https://google.com" 2>/dev/null | grep -qE '200|301|302'; then
      ok "HTTP прокси (127.0.0.1:10809) работает"
    else
      warn "HTTP прокси (127.0.0.1:10809) НЕ работает"
    fi

    # IP через прокси
    local proxy_ip
    proxy_ip=$(curl -s --connect-timeout 3 --max-time 5 \
      --socks5-hostname 127.0.0.1:10808 "https://api.ipify.org" 2>/dev/null || echo "N/A")
    if [ -n "$proxy_ip" ] && [ "$proxy_ip" != "N/A" ]; then
      report "  >> Внешний IP через прокси: ${proxy_ip}"
      json_set "connectivity" "proxy_external_ip" "${proxy_ip}"
    fi

    json_set "connectivity" "proxy_active" "true"
  else
    report "  Прокси: не запущен"
    json_set "connectivity" "proxy_active" "false"
  fi

  # Внешний IP (без прокси)
  if cmd_exists curl; then
    local external_ip
    external_ip=$(curl -s --connect-timeout 3 --max-time 5 "https://api.ipify.org" 2>/dev/null || \
                  curl -s --connect-timeout 3 --max-time 5 "https://icanhazip.com" 2>/dev/null || \
                  echo "N/A")
    if [ "$external_ip" != "N/A" ] && [ -n "$external_ip" ]; then
      report "  >> Внешний IP (прямой): ${external_ip}"
      json_set "connectivity" "external_ip" "${external_ip}"
    fi
  fi

  # Пропускная способность (скорость)
  if cmd_exists curl; then
    subsection "Скорость загрузки (тест)"
    local speed_result
    speed_result=$(curl -s -o /dev/null -w "%{speed_download}" --connect-timeout 5 --max-time 10 \
      "https://speed.cloudflare.com/__down?bytes=10485760" 2>/dev/null) || speed_result="N/A"
    if [ "$speed_result" != "N/A" ] && [ -n "$speed_result" ]; then
      local speed_mbps
      speed_mbps=$(echo "scale=1; ${speed_result} * 8 / 1000000" | bc -l 2>/dev/null || echo "N/A")
      report "  >> Скорость загрузки: ${speed_mbps} Mbps"
      json_set "connectivity" "download_speed_mbps" "${speed_mbps}"
    fi
  fi
}

register_section "10" "Тесты связности" section_10_connectivity

# ==============================================================================
#  11. VPN-ИНТЕРФЕЙСЫ
# ==============================================================================

section_11_vpn() {
  # Поиск VPN-интерфейсов
  local vpn_ifaces
  vpn_ifaces=$(ip -br link 2>/dev/null | grep -oiP '^(tun|tap|wg|wg[0-9]|utun|vpn|ppp|ipsec|vxlan|gretap|erspan)\S*' || echo "")
  if [ -n "$vpn_ifaces" ]; then
    report "  >> VPN-интерфейсы: ${vpn_ifaces//$'\n'/ }"
    local vpn_count
    vpn_count=$(echo "$vpn_ifaces" | wc -l)
    ok "VPN-интерфейсов: ${vpn_count}"
    json_set "vpn" "interfaces" "${vpn_ifaces//$'\n'/,}"
  else
    report "  VPN-интерфейсы: не обнаружены"
    json_set "vpn" "interfaces" "none"
  fi

  # WireGuard
  if cmd_exists wg; then
    subsection "WireGuard"
    local wg_out
    wg_out=$(sudo wg show 2>/dev/null || wg show 2>/dev/null || echo "")
    if [ -n "$wg_out" ]; then
      echo "$wg_out" >> "$REPORT_FILE"
      if echo "$wg_out" | grep -q 'interface:'; then
        ok "WireGuard активен"
        json_set "vpn" "wireguard" "active"
        # Количество пиров
        local peers
        peers=$(echo "$wg_out" | grep -c 'peer:')
        json_set "vpn" "wireguard_peers" "${peers}"
        report "  >> Пиров: ${peers}"
      fi
    else
      report "  WireGuard: не запущен"
      json_set "vpn" "wireguard" "inactive"
    fi
  fi

  # OpenVPN
  if cmd_exists openvpn; then
    subsection "OpenVPN"
    if pgrep -x openvpn &>/dev/null; then
      ok "OpenVPN запущен"
      json_set "vpn" "openvpn" "active"
    else
      report "  OpenVPN: не запущен"
    fi
  fi

  # Xray-core (v2rayN backend)
  if cmd_exists xray || cmd_exists xray_runtime; then
    subsection "Xray-core"
    local xray_proc
    xray_proc=$(pgrep -x xray 2>/dev/null || pgrep -f 'xray_runtime' 2>/dev/null || echo "")
    if [ -n "$xray_proc" ]; then
      ok "Xray-core запущен (PID: ${xray_proc})"
      json_set "vpn" "xray" "active"
    else
      report "  Xray-core: не запущен"
    fi
  fi

  # systemd VPN-сервисы
  subsection "Systemd VPN-сервисы"
  local vpn_services=("wg-quick@wg0" "openvpn@client" "v2rayn" "xray")
  for svc in "${vpn_services[@]}"; do
    if systemctl --user is-active "$svc" &>/dev/null 2>&1; then
      ok "Сервис ${svc}: активен"
      json_set "vpn.services" "${svc}" "active"
    elif systemctl is-active "$svc" &>/dev/null 2>&1; then
      ok "Сервис ${svc} (system): активен"
    fi
  done

  # IPSec
  if cmd_exists ipsec; then
    subsection "IPsec"
    run_cmd "ipsec status" "sudo ipsec status 2>/dev/null | head -20 || ipsec status 2>/dev/null | head -20" true
    if ipsec status 2>/dev/null | grep -q 'ESTABLISHED'; then
      ok "IPsec: установлен"
    fi
  fi
}

register_section "11" "VPN-интерфейсы" section_11_vpn

# ==============================================================================
#  12. БЕЗОПАСНОСТЬ СЕТИ
# ==============================================================================

section_12_security() {
  # Проверка открытых портов (сканирование)
  subsection "Открытые порты (локальные)"
  if cmd_exists ss; then
    local listening
    listening=$(ss -tlnp 2>/dev/null | tail -n +2 | awk '{print $4}' | grep -oP '\d+$' | sort -n | uniq | tr '\n' ' ')
    report "  >> Слушающие порты TCP: ${listening}"
    json_set "security" "listening_ports" "${listening}"

    # Опасные порты
    local dangerous_ports=(22 23 3389 5900 5901 6379 27017)
    for dport in "${dangerous_ports[@]}"; do
      if ss -tlnp "sport = :${dport}" 2>/dev/null | grep -q LISTEN; then
        local dproc
        dproc=$(ss -tlnp "sport = :${dport}" 2>/dev/null | grep -oP 'users:\(\(\K[^)]+' || echo "?")
        warn "Порт ${dport} открыт (${dproc}) — потенциальная уязвимость"
        json_set "security.dangerous_ports" "${dport}" "${dproc}"
      fi
    done
  fi

  # ARP-spoofing проверка (дублирующиеся MAC)
  subsection "ARP-безопасность"
  if cmd_exists ip; then
    local dup_macs
    dup_macs=$(ip neigh show 2>/dev/null | grep -oP 'lladdr \K[0-9a-f:]+' | sort | uniq -d)
    if [ -n "$dup_macs" ]; then
      warn "Обнаружены дублирующиеся MAC-адреса — возможен ARP-spoofing"
      json_set "security" "arp_spoofing" "detected"
      report "  >> Дубликаты MAC: ${dup_macs}"
    else
      ok "Дублирующихся MAC не обнаружено"
      json_set "security" "arp_spoofing" "clean"
    fi
  fi

  # IPv6 privacy extensions
  subsection "IPv6 privacy"
  if [ -f /proc/sys/net/ipv6/conf/all/use_tempaddr ]; then
    local ip6_privacy
    ip6_privacy=$(cat /proc/sys/net/ipv6/conf/all/use_tempaddr 2>/dev/null || echo "N/A")
    json_set "security" "ipv6_privacy" "${ip6_privacy}"
    if [ "$ip6_privacy" -ge 2 ]; then
      ok "IPv6 privacy extensions: ${ip6_privacy}"
    elif [ "$ip6_privacy" -eq 1 ]; then
      report "  IPv6 privacy: ${ip6_privacy} (частично)"
    else
      warn "IPv6 privacy: выключена (0)"
      recommend "Включите IPv6 privacy: sysctl -w net.ipv6.conf.all.use_tempaddr=2"
    fi
  fi

  # Проверка DNS-прокси
  subsection "DNS-безопасность"
  if ss -ulnp "sport = :53" 2>/dev/null | grep -q LISTEN; then
    local dns_proc
    dns_proc=$(ss -ulnp "sport = :53" 2>/dev/null | grep -oP 'users:\(\(\K[^)]+' || echo "?")
    report "  >> DNS на localhost:53 (${dns_proc})"
    json_set "security" "dns_local" "${dns_proc}"
  fi

  # DNSSEC
  if cmd_exists dig; then
    local dnssec
    dnssec=$(dig +dnssec google.com 2>/dev/null | grep 'flags:' | grep -oP 'ad' || echo "N/A")
    json_set "security" "dnssec" "${dnssec}"
    [ "$dnssec" = "ad" ] && ok "DNSSEC: подтверждён" || report "  DNSSEC: не проверен (это нормально для клиента)"
  fi

  # Проверка на общедоступные IPv4/IPv6
  subsection "Публичные адреса"
  if cmd_exists ip; then
    local pub_ipv4 pub_ipv6
    pub_ipv4=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[0-9./]+' | head -1 || echo "нет")
    pub_ipv6=$(ip -6 addr show scope global 2>/dev/null | grep -oP 'inet6 \K[0-9a-f:/]+' | head -1 || echo "нет")
    report "  >> IPv4 public: ${pub_ipv4}"
    report "  >> IPv6 public: ${pub_ipv6}"
    json_set "security" "public_ipv4" "${pub_ipv4}"
    json_set "security" "public_ipv6" "${pub_ipv6}"
  fi

  # TCP timestamps (уязвимость)
  local tcp_ts
  tcp_ts=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null || echo "N/A")
  json_set "security" "tcp_timestamps" "${tcp_ts}"
  if [ "$tcp_ts" = "1" ]; then
    report "  TCP timestamps: включены (информация о системе доступна)"
  fi
}

register_section "12" "Безопасность сети" section_12_security

# ==============================================================================
#  13. РЕКОМЕНДАЦИИ
# ==============================================================================

section_13_recommendations() {
  section "13. Рекомендации"

  if [ ${#RECOMMENDATIONS[@]} -eq 0 ]; then
    report "  ✓ Все проверки пройдены успешно."
    report "  ✓ Критических замечаний нет."
    json_set "recommendations" "count" "0"
    return
  fi

  report "  Найдено ${#RECOMMENDATIONS[@]} рекомендаций:"
  report ""

  local i=1
  for rec in "${RECOMMENDATIONS[@]}"; do
    report "  ${i}. ${rec}"
    ((i++))
  done

  report ""
  report "  Для применения большинства рекомендаций требуются права root (sudo)."
  report "  После изменений перепроверьте: ./scripts/diagnose-network.sh --quick"

  json_set "recommendations" "count" "${#RECOMMENDATIONS[@]}"
}

register_section "13" "Рекомендации" section_13_recommendations

# ==============================================================================
#  ГЕНЕРАЦИЯ JSON
# ==============================================================================

generate_json() {
  local json_file="${1:-${JSON_FILE}}"

  # Формируем JSON вручную (без jq, для совместимости)
  {
    echo "{"
    echo "  \"script\": \"${SCRIPT_NAME}\","
    echo "  \"version\": \"${SCRIPT_VERSION}\","
    echo "  \"timestamp\": \"${TIMESTAMP}\","
    echo "  \"mode\": \"${MODE}\","
    echo "  \"summary\": {"
    echo "    \"total\": ${TOTAL_CHECKS},"
    echo "    \"passed\": ${PASSED},"
    echo "    \"warnings\": ${WARNINGS},"
    echo "    \"failed\": ${FAILED},"
    echo "    \"skipped\": ${SKIPPED}"
    echo "  },"
    echo "  \"recommendations\": ["

    local first=true
    for rec in "${RECOMMENDATIONS[@]}"; do
      $first && first=false || echo ","
      echo -n "    \"${rec}\""
    done
    echo ""
    echo "  ],"
    echo "  \"checks\": ["

    first=true
    for check in "${CHECK_LOG[@]}"; do
      local ctype="${check%%:*}"
      local cmsg="${check#*:}"
      $first && first=false || echo ","
      echo -n "    {\"type\": \"${ctype}\", \"message\": \"${cmsg}\"}"
    done
    echo ""
    echo "  ],"
    echo "  \"data\": {"

    # JSON_DATA
    local keys
    keys=("${!JSON_DATA[@]}")
    first=true
    for key in "${keys[@]}"; do
      $first && first=false || echo ","
      echo -n "    \"${key}\": \"${JSON_DATA[${key}]}\""
    done
    echo ""
    echo "  }"
    echo "}"
  } > "$json_file"

  report "  >> JSON: ${json_file}"
}

# ==============================================================================
#  ВЫВОД РЕЗЮМЕ
# ==============================================================================

output_summary() {
  # Цветной вывод в stdout
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${BOLD}Диагностика сети завершена${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Всего проверок: ${TOTAL_CHECKS}"
  echo -e "  ${GREEN}✓ Успешно:     ${PASSED}${NC}"
  echo -e "  ${YELLOW}! Предупреждений: ${WARNINGS}${NC}"
  echo -e "  ${RED}✗ Ошибок:      ${FAILED}${NC}"
  echo -e "  ${CYAN}− Пропущено:   ${SKIPPED}${NC}"
  echo ""
  echo -e "  ${BOLD}Отчёт:${NC}  ${REPORT_FILE}"
  [ "$GENERATE_JSON" = true ] && echo -e "  ${BOLD}JSON:${NC}   ${JSON_FILE}"
  echo ""

  if [ ${#RECOMMENDATIONS[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}${#RECOMMENDATIONS[@]} рекомендаций:${NC}"
    local i=1
    for rec in "${RECOMMENDATIONS[@]}"; do
      echo -e "    ${i}. ${rec}"
      ((i++))
    done
    echo ""
  fi

  local health
  if [ "$FAILED" -gt 0 ]; then
    health="ПЛОХО"
    echo -e "  ${RED}✗ Состояние сети: ${health} — требуются исправления${NC}"
  elif [ "$WARNINGS" -gt 10 ]; then
    health="УДОВЛЕТВОРИТЕЛЬНО"
    echo -e "  ${YELLOW}! Состояние сети: ${health} — ${WARNINGS} предупреждений${NC}"
  elif [ "$WARNINGS" -gt 0 ]; then
    health="ХОРОШО"
    echo -e "  ${YELLOW}! Состояние сети: ${health} — ${WARNINGS} предупреждений${NC}"
  else
    health="ОТЛИЧНО"
    echo -e "  ${GREEN}✓ Состояние сети: ${health}${NC}"
  fi
  echo ""
}

# ==============================================================================
#  HELP
# ==============================================================================

show_help() {
  cat << 'HELP'
╔══════════════════════════════════════════════════════════════════════════╗
║                  diagnose-network.sh v2.0.0                             ║
║         Полная самодостаточная диагностика системы и сети               ║
╚══════════════════════════════════════════════════════════════════════════╝

Использование:
  ./scripts/diagnose-network.sh                   Полная диагностика (13 секций)
  ./scripts/diagnose-network.sh --quick           Сокращённый режим
  ./scripts/diagnose-network.sh --json            Дополнительно JSON-отчёт
  ./scripts/diagnose-network.sh --report <file>   Указать путь к отчёту
  ./scripts/diagnose-network.sh --no-install      Не устанавливать пакеты
  ./scripts/diagnose-network.sh --security        Только безопасность
  ./scripts/diagnose-network.sh --connectivity    Только связность
  ./scripts/diagnose-network.sh --section <N>     Только секция N
  ./scripts/diagnose-network.sh --help            Эта справка

Режимы:
  full (по умолч.)   — все 13 секций
  quick              — система, DNS, прокси, связность, рекомендации
  security           — файрвол, sysctl, безопасность
  connectivity       — тесты связности, ping, mtr, прокси

Секции:
   0. Зависимости и установка пакетов
   1. Общая информация о системе
   2. Сетевые интерфейсы (ip, ethtool, Wi-Fi, NM)
   3. Маршрутизация (IPv4, IPv6, ARP, policy routing)
   4. DNS (resolv.conf, systemd-resolved, /etc/hosts, DoH)
   5. Системный прокси (GNOME, KDE, env vars, порты)
   6. Файрвол (iptables, nftables, ufw, firewalld, nmap)
   7. Параметры ядра (30+ sysctl c анализом)
   8. TUN-устройство (device, модуль, интерфейсы)
   9. Сетевые соединения (TCP/UDP, TIME_WAIT, conntrack)
  10. Тесты связности (HTTP, ping, mtr, прокси, скорость)
  11. VPN-интерфейсы (WireGuard, OpenVPN, Xray, IPsec)
  12. Безопасность сети (порты, ARP, IPv6, DNSSEC)
  13. Рекомендации

Автоматическая установка:
  Скрипт определяет пакетный менеджер (apt/dnf/pacman/zypper/apk/emerge)
  и устанавливает: dnsutils, iputils-ping, mtr, ethtool, conntrack,
  traceroute, nmap, iperf3, jq, netcat и др. при необходимости.

Вывод:
  - Плоский отчёт: ~/.local/share/v2rayN/logs/network-diagnostic-*.log
  - JSON (--json): там же *.json
  - Цветное резюме: stdout

Примеры:
  ./scripts/diagnose-network.sh
  ./scripts/diagnose-network.sh --quick --no-install
  ./scripts/diagnose-network.sh --json --report /tmp/report.log
  ./scripts/diagnose-network.sh --security
HELP
}

# ==============================================================================
#  ПАРСИНГ АРГУМЕНТОВ
# ==============================================================================

parse_args() {
  local section_filter=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quick)        MODE="quick"; shift ;;
      --json)         GENERATE_JSON=true; shift ;;
      --report)       CUSTOM_REPORT="$2"; shift 2 ;;
      --no-install)   AUTO_INSTALL=false; shift ;;
      --security)     MODE="security"; shift ;;
      --connectivity) MODE="connectivity"; shift ;;
      --section)      MODE="section"; section_filter="$2"; shift 2 ;;
      --help|-h)      show_help; exit 0 ;;
      *)
        echo "Неизвестный флаг: $1"
        echo "Используйте --help для справки."
        exit 1
        ;;
    esac
  done

  if [ -n "$CUSTOM_REPORT" ]; then
    REPORT_FILE="$CUSTOM_REPORT"
    mkdir -p "$(dirname "$REPORT_FILE")" 2>/dev/null || true
  fi
}

# ==============================================================================
#  MAIN
# ==============================================================================

main() {
  parse_args "$@"

  # Создаём директорию
  mkdir -p "$REPORT_DIR" 2>/dev/null || true

  # Инициализируем отчёт
  {
    echo "══════════════════════════════════════════════════════════════════════"
    echo "  СЕТЕВАЯ ДИАГНОСТИКА"
    echo "  Скрипт: ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "  Создан: ${TIMESTAMP}"
    echo "  Режим:  ${MODE}"
    echo "══════════════════════════════════════════════════════════════════════"
    echo ""
  } > "$REPORT_FILE"

  # Заголовок в stdout
  echo ""
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
  echo -e "  ${BOLD}СЕТЕВАЯ ДИАГНОСТИКА v${SCRIPT_VERSION}${NC}"
  echo -e "  Режим: ${MODE}"
  echo -e "  Отчёт: ${REPORT_FILE}"
  echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
  echo ""

  # --- Зависимости (всегда) ---
  check_deps

  # --- Выбор секций ---
  case "$MODE" in
    full)
      for entry in "${REGISTERED_SECTIONS[@]}"; do
        run_section "$entry"
      done
      ;;
    quick)
      for entry in "${REGISTERED_SECTIONS[@]}"; do
        local name="${entry%%|*}"
        # секции 1,4,5,10,13
        case "$name" in
          1|4|5|10|13) run_section "$entry" ;;
        esac
      done
      ;;
    security)
      for entry in "${REGISTERED_SECTIONS[@]}"; do
        local name="${entry%%|*}"
        case "$name" in
          6|7|12|13) run_section "$entry" ;;
        esac
      done
      ;;
    connectivity)
      for entry in "${REGISTERED_SECTIONS[@]}"; do
        local name="${entry%%|*}"
        case "$name" in
          4|10|13) run_section "$entry" ;;
        esac
      done
      ;;
    section)
      local found=false
      for entry in "${REGISTERED_SECTIONS[@]}"; do
        local name="${entry%%|*}"
        if [ "$name" = "$section_filter" ]; then
          run_section "$entry"
          found=true
          break
        fi
      done
      if ! $found; then
        echo "Секция ${section_filter} не найдена. Доступны:"
        for entry in "${REGISTERED_SECTIONS[@]}"; do
          local name="${entry%%|*}"
          local rest="${entry#*|}"
          local desc="${rest%%|*}"
          echo "  ${name} — ${desc}"
        done
        exit 1
      fi
      ;;
  esac

  # --- Вывод ---
  output_summary
  report ""
  report "══════════════════════════════════════════════════════════════════════"
  report "  Диагностика завершена: ${PASSED}/${TOTAL_CHECKS} успешно, ${WARNINGS} предупреждений, ${FAILED} ошибок"
  report "══════════════════════════════════════════════════════════════════════"

  # --- JSON ---
  if [ "$GENERATE_JSON" = true ]; then
    generate_json "${JSON_FILE}"
  fi

  # --- Очистка ---
  rm -rf "$TMP_DIR" 2>/dev/null || true
}

main "$@"
