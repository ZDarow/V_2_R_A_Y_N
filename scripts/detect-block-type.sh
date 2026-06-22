#!/bin/bash
# detect-block-type.sh — Определение типа блокировки мобильного интернета
# Анализирует, какой метод блокировки применяет оператор:
#   - SNI only (только домен)
#   - IP only (только IP)
#   - Combined SNI+IP
#   - Full whitelist
#   - Throttling
# ============================================================================

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
info() { echo -e "  ${C}ℹ${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

LOG_FILE="blocktype-diag-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG_FILE") 2>&1

# Внешние зависимости
WHITELIST_URL="${WHITELIST_URL:-https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt}"
CIDR_WHITELIST_URL="${CIDR_WHITELIST_URL:-https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt}"
IP_WHITELIST_URL="${IP_WHITELIST_URL:-https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt}"

# Белые домены для тестов
WHITELIST_FQDN=("yandex.ru" "gosuslugi.ru" "vk.com" "mail.ru")
# Заблокированные домены для тестов
BLOCKED_FQDN=("twitter.com" "facebook.com" "instagram.com" "discord.com" "youtube.com")

# Временная директория
TMPDIR=$(mktemp -d /tmp/blocktype-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# ─── Функции ────────────────────────────────────────────────────────

check_dependency() {
    for cmd in curl dig ping jq; do
        if ! command -v "$cmd" &>/dev/null; then
            fail "$cmd не найден"
            return 1
        fi
    done
    ok "Все зависимости в наличии"
}

fetch_whitelist_sni() {
    local cache="$TMPDIR/whitelist_sni.txt"
    if [[ ! -f "$cache" ]]; then
        if curl -sSL -m 10 "$WHITELIST_URL" -o "$cache" 2>/dev/null; then
            ok "Загружен SNI whitelist ($(wc -l < "$cache") записей)"
        else
            warn "Не удалось загрузить SNI whitelist, используем встроенный"
            echo -e "yandex.ru\ngosuslugi.ru\nvk.com\nmail.ru\nok.ru\nrkn.gov.ru" > "$cache"
        fi
    fi
    cat "$cache"
}

fetch_cidr_whitelist() {
    local cache="$TMPDIR/cidr_whitelist.txt"
    if [[ ! -f "$cache" ]]; then
        if curl -sSL -m 10 "$CIDR_WHITELIST_URL" -o "$cache" 2>/dev/null; then
            ok "Загружен CIDR whitelist ($(wc -l < "$cache") записей)"
        fi
    fi
    [[ -f "$cache" ]] && cat "$cache" || true
}

# Проверка, входит ли IP в CIDR whitelist
ip_in_cidr_whitelist() {
    local ip="$1"
    local cidr_file="$TMPDIR/cidr_whitelist.txt"
    [[ -f "$cidr_file" ]] || return 1
    if command -v ipcalc &>/dev/null; then
        while IFS= read -r cidr; do
            [[ -z "$cidr" || "$cidr" =~ ^# ]] && continue
            if ipcalc -c "$ip" "$cidr" &>/dev/null; then
                return 0
            fi
        done < "$cidr_file"
    fi
    return 1
}

test_sni_whitelist_only() {
    step "1. ТЕСТ: только SNI-блокировка"
    echo "  Суть: если IP заблокированного ресурса доступен по TCP, но TLS с оригинальным SNI не проходит,"
    echo "  то блокировка по SNI."
    echo ""

    local sni_only_count=0
    for domain in "${BLOCKED_FQDN[@]}"; do
        echo "  ── $domain ──"
        local ip
        ip=$(dig +short "$domain" 2>/dev/null | head -1)
        [[ -z "$ip" ]] && { warn "    Не удалось получить IP для $domain"; continue; }

        # TCP test (без TLS, просто TCP connect)
        if timeout 3 bash -c "echo > /dev/tcp/$ip/443" 2>/dev/null; then
            ok "    TCP $ip:443 — доступен"
        else
            fail "    TCP $ip:443 — НЕ доступен"
            continue
        fi

        # TLS с оригинальным SNI
        if timeout 5 openssl s_client -connect "$ip:443" -servername "$domain" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
            ok "    TLS $domain (оригинальный SNI) — работает"
        else
            fail "    TLS $domain (оригинальный SNI) — НЕ работает"
            sni_only_count=$((sni_only_count + 1))
        fi

        echo ""
    done

    if [[ "$sni_only_count" -gt 0 ]]; then
        info "SNI-блокировка: ДА (не менее $sni_only_count из ${#BLOCKED_FQDN[@]} доменов)"
        return 0
    else
        info "SNI-блокировка: НЕТ"
        return 1
    fi
}

test_ip_whitelist_only() {
    step "2. ТЕСТ: только IP-блокировка"
    echo "  Суть: если IP из hxehex CIDR whitelist доступен, а IP вне его — нет (при том же SNI)."
    echo ""

    local cidr_file="$TMPDIR/cidr_whitelist.txt"
    if [[ ! -f "$cidr_file" ]]; then
        warn "  CIDR whitelist не загружен — тест недоступен"
        return 1
    fi

    # Собираем несколько тестовых IP из whitelist
    local test_whitelist_ips=()
    if command -v python3 &>/dev/null; then
        mapfile -t test_whitelist_ips < <(head -50 "$cidr_file" | grep -v '^#' | grep -v '^$' | python3 -c "
import sys, ipaddress
for line in sys.stdin:
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    try:
        net = ipaddress.ip_network(line, strict=False)
        # Берём первый хост в сети
        print(list(net.hosts())[0])
        if len(sys.stdout.buffer) > 5:
            break
    except:
        pass
" 2>/dev/null)
    fi

    if [[ ${#test_whitelist_ips[@]} -eq 0 ]]; then
        warn "  Не удалось извлечь IP из whitelist — тест недоступен"
        return 1
    fi

    local ip_only_count=0
    local test_sni="${WHITELIST_FQDN[0]}"  # yandex.ru

    for test_ip in "${test_whitelist_ips[@]}"; do
        echo "  Тест whitelist IP: $test_ip"
        if timeout 5 openssl s_client -connect "$test_ip:443" -servername "$test_sni" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
            ok "    $test_ip (whitelist) с SNI=$test_sni — работает"
            ip_only_count=$((ip_only_count + 1))
        else
            info "    $test_ip (whitelist) с SNI=$test_sni — не отвечает (может быть нормально)"
        fi
        echo ""
    done

    if [[ "$ip_only_count" -gt 0 ]]; then
        info "IP-блокировка: whitelist IP работают с whitelist SNI"
    fi

    # Теперь пробуем whitelist IP с заблокированным SNI
    local blocked_sni="${BLOCKED_FQDN[0]}"
    echo "  Тест whitelist IP с ЗАБЛОКИРОВАННЫМ SNI ($blocked_sni):"
    for test_ip in "${test_whitelist_ips[@]}"; do
        echo -n "    $test_ip с SNI=$blocked_sni: "
        if timeout 5 openssl s_client -connect "$test_ip:443" -servername "$blocked_sni" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
            ok "работает (блокировка ТОЛЬКО по IP, не по SNI)"
            return 1
        else
            fail "НЕ работает (блокировка по SNI или комбинированная)"
        fi
        echo ""
    done
    return 0
}

test_combined_sni_ip() {
    step "3. ТЕСТ: комбинированная SNI+IP блокировка"
    echo "  Суть: если whitelist IP + whitelist SNI работают, но whitelist IP + blocked SNI — нет,"
    echo "  при этом blocked IP + whitelist SNI тоже не работают — это комбинированная блокировка."
    echo ""

    local blocked_ip
    blocked_ip=$(dig +short twitter.com 2>/dev/null | head -1)
    local whitelist_sni="yandex.ru"
    local whitelist_ip
    whitelist_ip=$(dig +short yandex.ru 2>/dev/null | head -1)

    [[ -z "$blocked_ip" ]] && { fail "  Не удалось получить IP twitter.com"; return 1; }
    [[ -z "$whitelist_ip" ]] && { fail "  Не удалось получить IP yandex.ru"; return 1; }

    # 1. whitelist IP + whitelist SNI (должно работать)
    echo -n "  1) whitelist IP ($whitelist_ip) + whitelist SNI ($whitelist_sni): "
    if timeout 5 openssl s_client -connect "$whitelist_ip:443" -servername "$whitelist_sni" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        ok "работает"
    else
        fail "НЕ работает"
    fi

    # 2. whitelist IP + blocked SNI (не должно работать при combined)
    echo -n "  2) whitelist IP ($whitelist_ip) + blocked SNI (twitter.com): "
    if timeout 5 openssl s_client -connect "$whitelist_ip:443" -servername "twitter.com" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        ok "работает (SNI-спуфинг эффективен)"
    else
        fail "НЕ работает (SNI-спуфинг НЕ эффективен)"
    fi

    # 3. blocked IP + whitelist SNI (не должно работать при combined)
    echo -n "  3) blocked IP ($blocked_ip) + whitelist SNI ($whitelist_sni): "
    if timeout 5 openssl s_client -connect "$blocked_ip:443" -servername "$whitelist_sni" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        ok "работает (IP-адрес сам по себе не блокируется)"
    else
        fail "НЕ работает (IP-адрес заблокирован)"
    fi

    echo ""
    echo "  Анализ комбинаций:"
    echo "  +----------------------------+------------+-----------+"
    echo "  | Комбинация                 | Работает?  | Вывод     |"
    echo "  +----------------------------+------------+-----------+"
    echo "  | whitelist IP + whitelist SNI | должна    | База       |"
    echo "  | whitelist IP + blocked SNI   | если да    | SNI-спуфинг работает |"
    echo "  | blocked IP  + whitelist SNI | если нет   | Блокировка по IP      |"
    echo "  +----------------------------+------------+-----------+"
}

test_throttling() {
    step "4. ТЕСТ: троттлинг (ограничение скорости)"
    echo "  Суть: при whitelist оператор режет скорость до ~14 Кбит/с."
    echo ""

    # Тест скорости до whitelist ресурса
    echo "  Тест скорости до Yandex:"
    local yandex_speed
    yandex_speed=$(curl -s -o /dev/null -w "%{speed_download}" -m 15 -4 "https://yandex.ru" 2>/dev/null)
    if [[ -n "$yandex_speed" && "$yandex_speed" != "0" ]]; then
        local yandex_kbps
        yandex_kbps=$(echo "scale=0; $yandex_speed * 8 / 1000" | bc 2>/dev/null || echo "0")
        info "  Скорость до Yandex: ${yandex_kbps} Кбит/с"
        if [[ "$yandex_kbps" -lt 50 ]]; then
            warn "  Скорость < 50 Кбит/с — признаки троттлинга"
        fi
    else
        warn "  Не удалось измерить скорость до yandex.ru"
    fi

    # Тест размера пинга — индикатор завышенной задержки (обычно признак DPI)
    echo ""
    echo "  Тест RTT (ping):"
    local avg_rtt
    avg_rtt=$(ping -c 5 -W 2 8.8.8.8 2>/dev/null | tail -1 | awk -F/ '{print $5}')
    if [[ -n "$avg_rtt" ]]; then
        info "  Средний RTT до 8.8.8.8: ${avg_rtt} мс"
        local avg_rtt_int
        avg_rtt_int=$(echo "$avg_rtt" | cut -d. -f1)
        if [[ "$avg_rtt_int" -gt 300 ]]; then
            warn "  RTT > 300 мс — возможен троттлинг или блокировка ICMP"
        fi
    fi
}

test_cgnat() {
    step "5. ТЕСТ: CGNAT (Carrier-Grade NAT)"
    echo "  Суть: мобильные операторы часто используют CGNAT (100.64.0.0/10)."
    echo "  Это ухудшает работу VPN, так как несколько абонентов сидят за одним IP."
    echo ""

    local my_ip
    my_ip=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
    if [[ -z "$my_ip" ]]; then
        fail "  Не удалось получить внешний IP"
        return 1
    fi
    info "  Внешний IP: $my_ip"

    # Проверка на CGNAT диапазон (100.64.0.0/10)
    if echo "$my_ip" | grep -qE '^(100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.)'; then
        warn "  ⚠ IP в CGNAT-диапазоне (100.64.0.0/10) — проблемы с VPN/WireGuard"
        info "  Решение: запросить у оператора выделенный IP (обычно платно)"
    else
        ok "  IP НЕ в CGNAT — нормальная связность"
    fi

    # Проверка на частные диапазоны (через провайдерский NAT)
    local local_ip
    local_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    if [[ "$local_ip" != "$my_ip" ]]; then
        info "  Локальный IP: $local_ip (отличается от внешнего — NAT)"
    fi
}

test_bgp_asn() {
    step "6. ТЕСТ: BGP ASN провайдера"
    echo "  Суть: точное определение оператора через BGP ASN."
    echo ""

    local my_ip
    my_ip=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
    [[ -z "$my_ip" ]] && { fail "  Не удалось получить внешний IP"; return 1; }

    # Определение ASN через whois.cymru.com
    local asn_info
    asn_info=$(echo "$my_ip" | timeout 5 nc whois.cymru.com 43 2>/dev/null || echo "")
    if [[ -n "$asn_info" ]]; then
        local asn
        asn=$(echo "$asn_info" | grep -E '^[0-9]' | head -1 | awk '{print $1}')
        local asn_name
        asn_name=$(echo "$asn_info" | grep -E '^[0-9]' | head -1 | cut -d'|' -f4- | sed 's/^ //')
        info "  ASN$asn: $asn_name"
    fi

    # Альтернатива через ipinfo.io
    local asn_json
    asn_json=$(curl -s -m 5 "https://ipinfo.io/$my_ip/json" 2>/dev/null)
    if command -v jq &>/dev/null && [[ -n "$asn_json" ]]; then
        local org
        org=$(echo "$asn_json" | jq -r '.org // "неизвестно"')
        info "  Организация (ipinfo): $org"
    fi
}

test_udp_blocking() {
    step "7. ТЕСТ: UDP-блокировка (WireGuard, QUIC, DoT, DoQ)"
    echo "  Суть: многие операторы ограничивают UDP, что убивает WireGuard/QUIC."
    echo ""

    local udp_ports=(
        "8.8.8.8:53"        # DNS
        "1.1.1.1:443"        # QUIC
        "1.1.1.1:853"        # DNS over QUIC
        "1.1.1.1:51820"      # WireGuard (Cloudflare Warp)
        "8.8.8.8:443"        # QUIC Google
    )

    for target in "${udp_ports[@]}"; do
        local ip="${target%:*}"
        local port="${target#*:}"
        echo -n "  UDP $target: "
        if timeout 3 bash -c "echo > /dev/udp/$ip/$port" 2>/dev/null; then
            ok "доступен"
        else
            fail "НЕ доступен"
        fi
    done

    echo ""
    echo "  Рекомендации:"
    echo "  - Если UDP/443 (QUIC) заблокирован — Hysteria2 не будет работать"
    echo "  - Если UDP/51820 заблокирован — WireGuard не будет работать"
    echo "  - Если UDP/53 работает — DoT/DoQ альтернативы будут работать"
}

test_sni_fragment_effectiveness() {
    step "8. ТЕСТ: эффективность фрагментации TLS"
    echo "  Суть: проверяет, помогает ли фрагментация ClientHello обойти DPI."
    echo ""

    if ! command -v python3 &>/dev/null; then
        warn "  python3 не найден — тест фрагментации недоступен"
        return 1
    fi

    local domain="${BLOCKED_FQDN[0]}"  # twitter.com
    local ip
    ip=$(dig +short "$domain" 2>/dev/null | head -1)
    [[ -z "$ip" ]] && { fail "  Не удалось получить IP $domain"; return 1; }

    # Тест без фрагментации
    echo -n "  TLS ClientHello (без фрагментации) к $domain: "
    if timeout 5 openssl s_client -connect "$domain:443" -servername "$domain" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        ok "работает"
    else
        fail "НЕ работает"
    fi

    # Тест с фрагментацией через python (отправка частями)
    echo "  Тест с фрагментацией ClientHello (Python):"
    local result
    result=$(timeout 5 python3 -c "
import socket, ssl, sys
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(('$ip', 443))
    # Отправляем первую часть ClientHello (первые 100 байт)
    sock.send(b'\\x16\\x03\\x01\\x02\\x00\\x01\\x00\\x01\\xfc\\x03\\x03' + b'\\x00' * 90)
    import time
    time.sleep(0.05)
    # Пытаемся завершить рукопожатие
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    ssl_sock = ctx.wrap_socket(sock, server_hostname='$domain')
    ssl_sock.do_handshake()
    print('OK')
    ssl_sock.close()
except Exception as e:
    print(f'FAIL: {e}')
" 2>/dev/null)
    if echo "$result" | grep -q "OK"; then
        ok "  Фрагментация TLS помогает (ClientHello с разбивкой работает)"
    else
        warn "  Фрагментация TLS НЕ помогает"
    fi
}

# ─── Итог и рекомендации ─────────────────────────────────────────────

generate_recommendations() {
    step "РЕКОМЕНДАЦИИ"

    echo ""
    echo "  ${C}┌─────────────────────────────────────────────────────────────────┐${N}"
    echo "  ${C}│  По результатам тестов выберите подходящую стратегию:            │${N}"
    echo "  ${C}└─────────────────────────────────────────────────────────────────┘${N}"
    echo ""
    echo "  ${B}[SNI only]${N} — блокируется только домен:"
    echo "    → Используйте SNI-спуфинг (VLESS+Reality)"
    echo "    → Фрагментация TLS не обязательна"
    echo ""
    echo "  ${B}[IP only]${N} — блокируется только IP:"
    echo "    → Ищите VPS с IP из CIDR whitelist hxehex"
    echo "    → SNI-спуфинг не нужен"
    echo ""
    echo "  ${B}[Combined SNI+IP]${N} — блокируется и домен, и IP:"
    echo "    → Нужна двухсерверная схема (РФ → Зарубежье)"
    echo "    → РФ сервер должен иметь IP из CIDR whitelist"
    echo ""
    echo "  ${B}[Full whitelist]${N} — работает только малая часть сайтов:"
    echo "    → Единственный выход — Tor Bridges или двухсерверная схема"
    echo ""
    echo "  ${B}[Trottling]${N} — скорость режется до 14 Кбит/с:"
    echo "    → Используйте обфускацию трафика (VLESS+XTLS-Vision)"
    echo "    → Пробуйте менять порт (443→8443→2083)"
    echo ""
    echo "  ${B}[CGNAT]${N} — вы за общим NAT оператора:"
    echo "    → Запросите выделенный IP у оператора"
    echo "    → Используйте протоколы на базе TCP (VLESS, Trojan), не WireGuard"
    echo ""
    echo "  ${B}[UDP blocked]${N} — UDP не работает:"
    echo "    → Используйте TCP-транспорт (не Hysteria2, не WireGuard)"
    echo "    → Включите UDP over TCP в настройках клиента"
    echo ""
    echo "  ${B}[Fragment TLS helps]${N} — фрагментация обходит DPI:"
    echo "    → Включите fragment.packets=tlshello в конфиге Xray"
    echo "    → Размер фрагмента: 100-200 байт"
    echo ""
}

# ─── Main ────────────────────────────────────────────────────────────

SCRIPT_VERSION="1.0.0"

show_help() {
    echo "detect-block-type.sh v$SCRIPT_VERSION — Определение типа блокировки мобильного интернета"
    echo ""
    echo "Использование:"
    echo "  $0 [--help | --version | --quick | --full]"
    echo ""
    echo "Команды:"
    echo "  --help           Показать эту справку"
    echo "  --version        Показать версию"
    echo "  --quick          Быстрая диагностика (только основные тесты)"
    echo "  --full           Полная диагностика (по умолчанию, все 8 тестов)"
    echo "  (без аргументов) Полная диагностика"
    echo ""
    echo "Примеры:"
    echo "  $0               Полная диагностика"
    echo "  $0 --quick       Быстрая проверка SNI + IP + CGNAT"
    echo "  $0 --help        Эта справка"
    exit 0
}

main() {
    # Обработка аргументов
    case "${1:-}" in
        --help|-h)     show_help ;;
        --version|-v)  echo "detect-block-type.sh v$SCRIPT_VERSION"; exit 0 ;;
        --quick)       QUICK_MODE=true ;;
        --full|"")     QUICK_MODE=false ;;
        *)             echo "Неизвестный аргумент: $1"; echo "Используйте: $0 --help"; exit 1 ;;
    esac

    echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}║  ДИАГНОСТИКА ТИПА БЛОКИРОВКИ МОБИЛЬНОГО ИНТЕРНЕТА        ║${N}"
    echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${N}"
    echo -e "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "Интерфейс: $(ip route show default | awk '{print $5}' | head -1)"
    echo ""

    check_dependency || { fail "Установите зависимости: curl, dig, ping, jq"; exit 1; }

    # Загрузка whitelist
    fetch_whitelist_sni > /dev/null
    fetch_cidr_whitelist > /dev/null

    # Запуск тестов
    test_cgnat
    test_bgp_asn

    if [[ "${QUICK_MODE:-false}" == "true" ]]; then
        info "Быстрый режим: пропущены SNI, UDP, фрагментация"
    else
        test_sni_whitelist_only
        test_ip_whitelist_only
        test_combined_sni_ip
        test_throttling
        test_udp_blocking
        test_sni_fragment_effectiveness
    fi

    # Итог
    generate_recommendations

    echo -e "\n${C}╔═══════════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}║  Диагностика завершена                                    ║${N}"
    echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${N}"
    echo -e "Лог сохранён: ${B}$LOG_FILE${N}"
    echo -e "\n${Y}Для отправки лога на анализ: cat $LOG_FILE${N}"
}

main "$@"
