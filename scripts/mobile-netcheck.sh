#!/bin/bash
# mobile-netcheck.sh — Диагностика мобильного интернета для обхода блокировок

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
info() { echo -e "  ${C}ℹ${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

LOG_FILE="mobile-diag-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee "$LOG_FILE") 2>&1

echo -e "${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Диагностика мобильного интернета                ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
echo -e "Дата: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "Хост: $(hostname) | OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"

# ─── 1. Сетевой интерфейс ──────────────────────────────────────────
step "1. Сетевой интерфейс"
interface=$(ip route show default | awk '{print $5}' | head -1)
info "Интерфейс: $interface"

# Определяем тип подключения
if [[ "$interface" =~ ^(wwan|usb|ppp|ww) ]]; then
    ok "Тип: Мобильная связь (USB/модем)"
elif [[ "$interface" =~ ^(wlp|wlan) ]]; then
    warn "Тип: WiFi (может быть режим модема с телефона)"
else
    info "Тип: Ethernet/другое"
fi

# IP-адрес
ip_addr=$(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
info "IP-адрес интерфейса: $ip_addr"

# ─── 2. Оператор и геолокация ─────────────────────────────────────
step "2. Оператор и геолокация"
direct_ip=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
if [[ -n "$direct_ip" ]]; then
    ip_info=$(curl -s -m 5 https://ipinfo.io/$direct_ip 2>/dev/null)
    org=$(echo "$ip_info" | jq -r '.org // "неизвестно"' 2>/dev/null)
    city=$(echo "$ip_info" | jq -r '.city // "неизвестно"' 2>/dev/null)
    region=$(echo "$ip_info" | jq -r '.region // "неизвестно"' 2>/dev/null)
    country=$(echo "$ip_info" | jq -r '.country // "неизвестно"' 2>/dev/null)
    
    ok "Публичный IP: $direct_ip"
    info "Оператор: $org"
    info "Город: $city, $region"
    info "Страна: $country"
    
    # Определяем мобильного оператора
    if echo "$org" | grep -qiE "mts|мтс"; then
        ok "Определён оператор: МТС"
    elif echo "$org" | grep -qiE "beeline|билайн|vimpelcom"; then
        ok "Определён оператор: Билайн"
    elif echo "$org" | grep -qiE "megafon|мегафон"; then
        ok "Определён оператор: Мегафон"
    elif echo "$org" | grep -qiE "tele2|теле2"; then
        ok "Определён оператор: Tele2"
    elif echo "$org" | grep -qiE "yota|йота"; then
        ok "Определён оператор: Yota"
    else
        warn "Оператор не определён автоматически"
    fi
else
    fail "Не удалось получить публичный IP"
fi

# ─── 3. MTU и фрагментация ────────────────────────────────────────
step "3. MTU и фрагментация"
mtu=$(ip link show "$interface" | grep mtu | awk '{print $5}')
info "Текущий MTU: $mtu"

# Проверяем, работает ли ICMP (ping)
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    ok "ICMP (ping) работает"
else
    warn "ICMP (ping) заблокирован оператором"
fi

# Тест MTU с разными размерами
for test_mtu in 1500 1492 1460 1400 1300; do
    if ping -c 1 -M do -s $((test_mtu - 28)) 8.8.8.8 &>/dev/null; then
        ok "MTU $test_mtu работает"
        break
    else
        info "MTU $test_mtu не работает"
    fi
done

# ─── 4. IPv4 vs IPv6 ──────────────────────────────────────────────
step "4. IPv4 vs IPv6"
if curl -s -4 -m 5 https://ipinfo.io/ip &>/dev/null; then
    ok "IPv4 работает"
else
    fail "IPv4 не работает"
fi

if curl -s -6 -m 5 https://ipinfo.io/ip &>/dev/null; then
    ok "IPv6 работает"
    ipv6_addr=$(curl -s -6 -m 5 https://ipinfo.io/ip 2>/dev/null)
    info "IPv6 адрес: $ipv6_addr"
else
    warn "IPv6 не работает (или не поддерживается оператором)"
fi

# ─── 5. DNS ───────────────────────────────────────────────────────
step "5. DNS-серверы"
dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}')
for dns in $dns_servers; do
    info "DNS: $dns"
done

# Проверяем, работает ли DNS
if dig +short google.com @8.8.8.8 &>/dev/null; then
    ok "Публичный DNS (8.8.8.8) работает"
else
    fail "Публичный DNS (8.8.8.8) заблокирован"
fi

if dig +short google.com @1.1.1.1 &>/dev/null; then
    ok "Cloudflare DNS (1.1.1.1) работает"
else
    warn "Cloudflare DNS (1.1.1.1) может быть заблокирован"
fi

# ─── 6. Проверка DPI (Deep Packet Inspection) ─────────────────────
step "6. Проверка DPI (Deep Packet Inspection)"

# Тест HTTP vs HTTPS
http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 http://example.com 2>/dev/null)
https_code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 https://example.com 2>/dev/null)

if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
    ok "HTTP работает (код $http_code)"
else
    warn "HTTP может быть заблокирован или модифицирован"
fi

if [[ "$https_code" =~ ^(200|301|302)$ ]]; then
    ok "HTTPS работает (код $https_code)"
else
    fail "HTTPS может быть заблокирован"
fi

# Тест TLS-версий
for tls_ver in tls1 tls1_1 tls1_2 tls1_3; do
    if curl -s --$tls_ver -o /dev/null -m 5 https://www.cloudflare.com 2>/dev/null; then
        ok "$tls_ver работает"
    else
        info "$tls_ver не работает"
    fi
done

# ─── 7. Блокировки протоколов ─────────────────────────────────────
step "7. Блокировки протоколов"

# UDP (для VPN)
if timeout 3 bash -c 'echo > /dev/udp/8.8.8.8/53' 2>/dev/null; then
    ok "UDP работает"
else
    warn "UDP может быть ограничен"
fi

# SSH (порт 22)
if timeout 3 bash -c 'echo > /dev/tcp/github.com/22' 2>/dev/null; then
    ok "SSH (порт 22) работает"
else
    warn "SSH (порт 22) может быть заблокирован"
fi

# Tor (порт 9001)
if timeout 3 bash -c 'echo > /dev/tcp/1.1.1.1/9001' 2>/dev/null; then
    ok "Tor-порты доступны"
else
    info "Tor-порты недоступны (может быть нормально)"
fi

# ─── 8. Заблокированные сайты ─────────────────────────────────────
step "8. Проверка заблокированных сайтов (напрямую)"

blocked_sites=("twitter.com" "facebook.com" "instagram.com" "linkedin.com" "discord.com")
for site in "${blocked_sites[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 "https://$site" 2>/dev/null)
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
        warn "$site доступен (код $code) — возможно, блокировка снята"
    elif [[ "$code" == "000" ]]; then
        fail "$site заблокирован (нет ответа)"
    else
        info "$site возвращает код $code"
    fi
done

# ─── 9. Прокси-связность ──────────────────────────────────────────
step "9. Проверка прокси v2rayN"

if ss -tln 2>/dev/null | grep -q ":10808 "; then
    ok "SOCKS-прокси (10808) слушается"
    
    # Тестируем через прокси
    proxy_ip=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null)
    if [[ -n "$proxy_ip" && "$proxy_ip" != "$direct_ip" ]]; then
        ok "Прокси работает: $proxy_ip"
        
        # Тестируем заблокированные сайты через прокси
        for site in "${blocked_sites[@]}"; do
            code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --socks5-hostname 127.0.0.1:10808 "https://$site" 2>/dev/null)
            if [[ "$code" =~ ^(200|301|302)$ ]]; then
                ok "$site через прокси работает (код $code)"
            else
                fail "$site через прокси не работает (код $code)"
            fi
        done
    else
        fail "Прокси не работает или IP не меняется"
    fi
else
    fail "SOCKS-прокси не слушается"
fi

# ─── 10. Скорость соединения ──────────────────────────────────────
step "10. Тест скорости (быстрый)"

# Скачиваем 1MB файл
speed=$(curl -s -o /dev/null -w "%{speed_download}" -m 10 http://speedtest.tele2.net/1MB.zip 2>/dev/null)
if [[ -n "$speed" && "$speed" != "0" ]]; then
    speed_mb=$(echo "scale=2; $speed / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
    info "Скорость загрузки: ${speed_mb} MB/s"
else
    warn "Не удалось измерить скорость"
fi

# ─── 11. Трассировка маршрута ─────────────────────────────────────
step "11. Трассировка до Google (первые 10 хопов)"
if command -v mtr &>/dev/null; then
    mtr -r -c 3 -n 8.8.8.8 2>/dev/null | head -12
elif command -v traceroute &>/dev/null; then
    traceroute -m 10 -w 2 8.8.8.8 2>/dev/null
else
    warn "mtr/traceroute не установлены"
fi

# ─── 12. Рекомендации ─────────────────────────────────────────────
step "12. Рекомендации для мобильного интернета"

echo -e "  ${C}Если прокси работает, но медленно:${N}"
echo -e "    • Попробуйте сменить протокол с VMess на VLESS+Reality"
echo -e "    • Используйте фрагментацию TLS: fragment.packets=tlshello"
echo -e "    • Включите WebSocket с обфускацией"
echo -e ""
echo -e "  ${C}Если заблокированные сайты не открываются:${N}"
echo -e "    • Проверьте, что системный прокси включён"
echo -e "    • Используйте kill-switch для защиты от утечек"
echo -e "    • Попробуйте другой порт (443, 8443, 2083)"
echo -e ""
echo -e "  ${C}Оптимальные настройки для мобильных сетей:${N}"
echo -e "    • Протокол: VLESS + Reality"
echo -e "    • Транспорт: XHTTP (или WebSocket)"
echo -e "    • Шифрование: none (для Reality)"
echo -e "    • Фрагментация: включена"
echo -e "    • Порт: 443"

# ─── 13. CGNAT (Carrier-Grade NAT) ─────────────────────────────────
step "13. Проверка CGNAT (общий NAT оператора)"

my_ip=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)
if [[ -n "$my_ip" ]]; then
    info "Внешний IP: $my_ip"
    if echo "$my_ip" | grep -qE '^(100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.)'; then
        warn "⚠ Вы за CGNAT (100.64.0.0/10)! Проблемы с WireGuard/прямыми соединениями"
        info "Решение: запросите у оператора выделенный внешний IP"
    else
        ok "IP НЕ в CGNAT"
    fi
else
    fail "Не удалось получить внешний IP"
fi

# ─── 14. BGP ASN провайдера ────────────────────────────────────────
step "14. BGP ASN провайдера (точная идентификация)"

if [[ -n "$my_ip" ]]; then
    asn_json=$(curl -s -m 5 "https://ipinfo.io/$my_ip/json" 2>/dev/null)
    if command -v jq &>/dev/null && [[ -n "$asn_json" ]]; then
        org=$(echo "$asn_json" | jq -r '.org // "неизвестно"')
        asn=$(echo "$asn_json" | jq -r '.asn // "неизвестно"')
        info "ASN: $asn"
        info "Организация: $org"

        # Определяем точного оператора по ASN-диапазонам
        asn_num=$(echo "$asn" | sed 's/AS//')
        case "$asn_num" in
            31213|16035|51559)  ok "Оператор: Билайн (AS$asn_num)" ;;
            8359|25513|41733)   ok "Оператор: МТС (AS$asn_num)" ;;
            31246|12389|31257)  ok "Оператор: Мегафон (AS$asn_num)" ;;
            25106|12714|44477)  ok "Оператор: Tele2 (AS$asn_num)" ;;
            41044|61367)        ok "Оператор: Yota (AS$asn_num)" ;;
            *)                  info "Организация: $org (AS$asn_num)" ;;
        esac
    fi
fi

# ─── 15. UDP-сканирование портов (WireGuard, QUIC) ─────────────────
step "15. UDP-порты (WireGuard, QUIC, DoT)"

udp_ports=(
    "8.8.8.8:53"        # DNS
    "1.1.1.1:443"        # QUIC
    "1.1.1.1:853"        # DNS over QUIC
    "1.1.1.1:51820"      # WireGuard (Cloudflare Warp)
    "8.8.8.8:443"        # QUIC Google
)
for target in "${udp_ports[@]}"; do
    ip="${target%:*}"
    port="${target#*:}"
    if timeout 3 bash -c "echo > /dev/udp/$ip/$port" 2>/dev/null; then
        ok "UDP $target — доступен"
    else
        warn "UDP $target — НЕ доступен (может блокироваться)"
    fi
done

# ─── 16. SNI vs IP тест (тип блокировки) ────────────────────────────
step "16. Определение типа блокировки (SNI/IP/Combined)"

BLOCKED_SNIS=("twitter.com" "facebook.com" "instagram.com" "discord.com")
WHITELIST_SNI="yandex.ru"

for domain in "${BLOCKED_SNIS[@]}"; do
    ip=$(dig +short "$domain" 2>/dev/null | head -1)
    [[ -z "$ip" ]] && continue

    # TCP connect (проверка IP-блокировки)
    tcp_ok=false
    if timeout 3 bash -c "echo > /dev/tcp/$ip/443" 2>/dev/null; then
        tcp_ok=true
    fi

    # TLS с оригинальным SNI (проверка SNI-блокировки)
    tls_ok=false
    if $tcp_ok && timeout 5 openssl s_client -connect "$ip:443" -servername "$domain" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        tls_ok=true
    fi

    # Вывод
    if $tcp_ok && $tls_ok; then
        ok "$domain — полностью доступен"
    elif $tcp_ok && ! $tls_ok; then
        fail "$domain — TCP ok, TLS fail (SNI-блокировка!)"
    elif ! $tcp_ok; then
        fail "$domain — TCP fail (IP-блокировка или полный whitelist)"
    fi
done

# Тест SNI-спуфинга (whitelist SNI + blocked IP)
blocked_ip=$(dig +short twitter.com 2>/dev/null | head -1)
if [[ -n "$blocked_ip" ]]; then
    echo -n "  SNI-спуфинг (SNI=$WHITELIST_SNI через IP=$blocked_ip): "
    if timeout 5 openssl s_client -connect "$blocked_ip:443" -servername "$WHITELIST_SNI" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
        ok "SNI-спуфинг РАБОТАЕТ (блокировка только по SNI)"
    else
        warn "SNI-спуфинг НЕ РАБОТАЕТ (IP-блокировка или combined)"
    fi
fi

# ─── Итог ──────────────────────────────────────────────────────────
echo -e "\n${C}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${C}║  Диагностика завершена                            ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════╝${N}"
echo -e "Лог сохранён: ${B}$LOG_FILE${N}"
echo -e "\n${Y}Для анализа отправьте этот лог или покажите мне вывод.${N}"
