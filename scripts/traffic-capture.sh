#!/bin/bash
# traffic-capture.sh — Захват трафика для анализа блокировок мобильного интернета

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
info() { echo -e "  ${C}ℹ${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

# Конфигурация
CAPTURE_DIR="$HOME/traffic-captures"
INTERFACE=$(ip route show default | awk '{print $5}' | head -1)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DURATION=30  # Длительность захвата в секундах

# Тестовые домены
BLOCKED_SITES=("twitter.com" "facebook.com" "instagram.com" "linkedin.com" "discord.com")
RUSSIAN_SITES=("gosuslugi.ru" "yandex.ru" "vk.com" "mail.ru")

mkdir -p "$CAPTURE_DIR"

# ─── Функции захвата ──────────────────────────────────────────────

capture_start() {
    local filter="$1"
    local output="$2"
    info "Запуск tcpdump: $output"
    sudo tcpdump -i "$INTERFACE" -w "$output" -c 10000 "$filter" &
    TCPDUMP_PID=$!
    sleep 1
}

capture_stop() {
    if [[ -n "${TCPDUMP_PID:-}" ]]; then
        sudo kill "$TCPDUMP_PID" 2>/dev/null
        wait "$TCPDUMP_PID" 2>/dev/null
        unset TCPDUMP_PID
    fi
}

# ─── Тесты ─────────────────────────────────────────────────────────

test_dns() {
    step "1. Тест DNS-запросов"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-dns.pcap"
    
    capture_start "port 53" "$pcap"
    
    for domain in "${BLOCKED_SITES[@]}" "${RUSSIAN_SITES[@]}"; do
        echo -n "  DNS $domain: "
        result=$(dig +short +time=2 "$domain" @8.8.8.8 2>&1)
        if [[ -n "$result" && "$result" != *"timed out"* ]]; then
            echo -e "${G}✓${N} $result"
        else
            echo -e "${R}✗${N} заблокирован/таймаут"
        fi
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_http() {
    step "2. Тест HTTP (порт 80)"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-http.pcap"
    
    capture_start "port 80" "$pcap"
    
    for site in "${BLOCKED_SITES[@]}"; do
        echo -n "  HTTP $site: "
        code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "http://$site" 2>/dev/null)
        if [[ "$code" =~ ^(200|301|302)$ ]]; then
            echo -e "${G}✓${N} код $code"
        elif [[ "$code" == "000" ]]; then
            echo -e "${R}✗${N} заблокирован"
        else
            echo -e "${Y}!${N} код $code"
        fi
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_https() {
    step "3. Тест HTTPS (порт 443)"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-https.pcap"
    
    capture_start "port 443" "$pcap"
    
    for site in "${BLOCKED_SITES[@]}"; do
        echo -n "  HTTPS $site: "
        code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "https://$site" 2>/dev/null)
        if [[ "$code" =~ ^(200|301|302)$ ]]; then
            echo -e "${G}✓${N} код $code"
        elif [[ "$code" == "000" ]]; then
            echo -e "${R}✗${N} заблокирован"
        else
            echo -e "${Y}!${N} код $code"
        fi
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_tls_versions() {
    step "4. Тест TLS-версий"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-tls.pcap"
    
    capture_start "port 443" "$pcap"
    
    for site in "twitter.com" "facebook.com"; do
        echo "  Тест $site:"
        for tls in tls1 tls1_1 tls1_2 tls1_3; do
            echo -n "    $tls: "
            if curl -s --$tls -o /dev/null -m 5 "https://$site" 2>/dev/null; then
                echo -e "${G}✓${N} работает"
            else
                echo -e "${R}✗${N} заблокирован/не поддерживается"
            fi
        done
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_sni_blocking() {
    step "5. Тест SNI-блокировки"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-sni.pcap"
    
    capture_start "port 443" "$pcap"
    
    # Тест с разным SNI
    echo "  Тест с поддельным SNI:"
    echo -n "    twitter.com с SNI=google.com: "
    if curl -s --resolve "twitter.com:443:$(dig +short twitter.com | head -1)" \
            --cacert /etc/ssl/certs/ca-certificates.crt \
            -o /dev/null -m 5 "https://twitter.com" 2>/dev/null; then
        echo -e "${G}✓${N} работает"
    else
        echo -e "${R}✗${N} заблокировано"
    fi
    
    # Тест IP-адреса напрямую (без SNI)
    echo "  Тест IP напрямую (без SNI):"
    for site in "twitter.com" "facebook.com"; do
        ip=$(dig +short "$site" | head -1)
        echo -n "    $site ($ip): "
        if timeout 3 bash -c "echo > /dev/tcp/$ip/443" 2>/dev/null; then
            echo -e "${G}✓${N} TCP работает"
        else
            echo -e "${R}✗${N} TCP заблокирован"
        fi
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_fragmentation() {
    step "6. Тест фрагментации (MTU)"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-fragment.pcap"
    
    capture_start "icmp" "$pcap"
    
    echo "  Тест MTU:"
    for mtu in 1500 1492 1460 1400 1360 1300; do
        echo -n "    MTU $mtu: "
        # shellcheck disable=SC1010
        if ping -c 1 -M do -s $((mtu - 28)) 8.8.8.8 &>/dev/null; then
            echo -e "${G}✓${N} работает"
        else
            echo -e "${R}✗${N} фрагментируется/блокируется"
        fi
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_udp() {
    step "7. Тест UDP-трафика"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-udp.pcap"
    
    capture_start "udp" "$pcap"
    
    echo "  Тест UDP:"
    echo -n "    DNS (порт 53): "
    if timeout 3 bash -c 'echo > /dev/udp/8.8.8.8/53' 2>/dev/null; then
        echo -e "${G}✓${N} работает"
    else
        echo -e "${R}✗${N} заблокирован"
    fi
    
    echo -n "    QUIC (порт 443): "
    if timeout 3 bash -c 'echo > /dev/udp/8.8.8.8/443' 2>/dev/null; then
        echo -e "${G}✓${N} работает"
    else
        echo -e "${R}✗${N} заблокирован"
    fi
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_proxy() {
    step "8. Тест прокси v2rayN"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-proxy.pcap"
    
    capture_start "port 10808 or port 10809 or port 8443" "$pcap"
    
    echo "  Тест через SOCKS5 прокси:"
    for site in "${BLOCKED_SITES[@]}"; do
        echo -n "    $site: "
        code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --socks5-hostname 127.0.0.1:10808 "https://$site" 2>/dev/null)
        if [[ "$code" =~ ^(200|301|302)$ ]]; then
            echo -e "${G}✓${N} код $code"
        else
            echo -e "${R}✗${N} код $code"
        fi
    done
    
    sleep 2
    capture_stop
    ok "Сохранено: $pcap"
}

test_full_capture() {
    step "9. Полный захват всего трафика"
    local pcap="$CAPTURE_DIR/${TIMESTAMP}-full.pcap"
    
    info "Захват всего трафика на $DURATION секунд..."
    info "Откройте браузер и посетите заблокированные сайты!"
    
    sudo timeout "$DURATION" tcpdump -i "$INTERFACE" -w "$pcap" -c 50000 &
    TCPDUMP_PID=$!
    
    echo -e "\n  ${Y}У вас $DURATION секунд! Откройте:${N}"
    echo "    - https://twitter.com"
    echo "    - https://facebook.com"
    echo "    - https://instagram.com"
    echo "    - https://youtube.com"
    echo ""
    
    # Обратный отсчёт
    for i in $(seq "$DURATION" -1 1); do
        echo -ne "\r  Осталось: $i секунд..."
        sleep 1
    done
    echo ""
    
    capture_stop
    ok "Сохранено: $pcap"
}

# ─── Анализ ────────────────────────────────────────────────────────

analyze_captures() {
    step "Анализ захваченных файлов"
    
    echo -e "  ${C}Сохранённые pcap-файлы:${N}"
    ls -lh "$CAPTURE_DIR"/*.pcap 2>/dev/null | awk '{print "    " $9 " (" $5 ")"}'
    
    echo -e "\n  ${C}Для анализа в Wireshark:${N}"
    echo "    1. Откройте Wireshark"
    echo "    2. File → Open → выберите pcap-файл"
    echo "    3. Используйте фильтры:"
    echo "       - dns (DNS-запросы)"
    echo "       - http (HTTP-трафик)"
    echo "       - tls (HTTPS/TLS)"
    echo "       - tcp.flags.reset (RST-пакеты — признак блокировки)"
    echo "       - ip.addr (трафик к конкретному IP)"
    
    echo -e "\n  ${C}Признаки блокировки DPI:${N}"
    echo "    - TCP RST после Client Hello (SNI-блокировка)"
    echo "    - Таймауты на определённых доменах"
    echo "    - Разные ответы для разных TLS-версий"
    echo "    - Блокировка по IP vs домену"
}

# ─── Главное меню ──────────────────────────────────────────────────

show_menu() {
    echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
    echo -e "${C}║  Захват трафика для анализа блокировок          ║${N}"
    echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
    echo -e "Интерфейс: ${B}$INTERFACE${N}"
    echo -e "Папка захвата: ${B}$CAPTURE_DIR${N}"
    echo ""
    echo "  1) Тест DNS-запросов"
    echo "  2) Тест HTTP (порт 80)"
    echo "  3) Тест HTTPS (порт 443)"
    echo "  4) Тест TLS-версий"
    echo "  5) Тест SNI-блокировки"
    echo "  6) Тест фрагментации (MTU)"
    echo "  7) Тест UDP-трафика"
    echo "  8) Тест прокси v2rayN"
    echo "  9) Полный захват (ручной режим)"
    echo "  10) Запустить ВСЕ тесты"
    echo "  11) Анализ захваченных файлов"
    echo "  0) Выход"
    echo ""
    echo -n "Выберите действие: "
}

# ─── Основной цикл ────────────────────────────────────────────────

main() {
    if [[ $EUID -ne 0 ]]; then
        warn "Скрипт требует sudo для tcpdump"
        echo -n "Введите пароль sudo: "
        sudo -v
    fi
    
    while true; do
        show_menu
        read -r choice
        
        case "$choice" in
            1)  test_dns ;;
            2)  test_http ;;
            3)  test_https ;;
            4)  test_tls_versions ;;
            5)  test_sni_blocking ;;
            6)  test_fragmentation ;;
            7)  test_udp ;;
            8)  test_proxy ;;
            9)  test_full_capture ;;
            10) test_dns; test_http; test_https; test_tls_versions; test_sni_blocking; test_fragmentation; test_udp; test_proxy; test_full_capture ;;
            11) analyze_captures ;;
            0)  exit 0 ;;
            *)  warn "Неверный выбор" ;;
        esac
        
        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# Запуск с аргументами или интерактивно
if [[ $# -gt 0 ]]; then
    case "$1" in
        --dns)          test_dns ;;
        --http)         test_http ;;
        --https)        test_https ;;
        --tls)          test_tls_versions ;;
        --sni)          test_sni_blocking ;;
        --fragment)     test_fragmentation ;;
        --udp)          test_udp ;;
        --proxy)        test_proxy ;;
        --full)         test_full_capture ;;
        --all)          test_dns; test_http; test_https; test_tls_versions; test_sni_blocking; test_fragmentation; test_udp; test_proxy; test_full_capture ;;
        --analyze)      analyze_captures ;;
        *)              echo "Использование: $0 [--dns|--http|--https|--tls|--sni|--fragment|--udp|--proxy|--full|--all|--analyze]" ;;
    esac
else
    main
fi
