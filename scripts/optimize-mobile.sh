#!/bin/bash
# optimize-mobile.sh — Безопасная оптимизация для мобильного интернета
# Добавляет: фрагментацию TLS, ротацию SNI по whitelist-доменам,
# подбор MTU, оптимизацию port/protocol, fallback-сервер
# ============================================================================

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

CONFIG="$HOME/.config/v2rayN/config.json"
BACKUP="${CONFIG}.before-optimize"
INTERFACE=$(ip route show default | awk '{print $5}' | head -1)

# Белые SNI домены для ротации (hxehex + igareck)
SNI_WHITELIST=(
    "yandex.ru" "vk.com" "mail.ru" "gosuslugi.ru"
    "ok.ru" "rkn.gov.ru" "xn--80af2al1c.xn--p1ai"
    "sberbank.ru" "mos.ru" "nalog.ru" "cbr.ru"
)

echo -e "${C}╔═══════════════════════════════════════════════════════════════╗${N}"
echo -e "${C}║  ОПТИМИЗАЦИЯ ДЛЯ МОБИЛЬНОГО ИНТЕРНЕТА                    ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${N}"

# ─── 1. Создание бэкапа ───────────────────────────────────────────
step "1. Создание бэкапа"
cp "$CONFIG" "$BACKUP" 2>/dev/null || cp "$CONFIG" "${BACKUP}.manual"
ok "Бэкап создан: ${BACKUP}"
info "Если что-то пошло не так:"
info "  cp ${BACKUP} ${CONFIG} && systemctl --user restart xray.service"

# ─── 2. Автоподбор MTU ─────────────────────────────────────────────
step "2. Автоподбор оптимального MTU"
current_mtu=$(ip link show "$INTERFACE" | grep mtu | awk '{print $5}')
info "Текущий MTU: $current_mtu"

best_mtu=0
for mtu in 1500 1492 1472 1460 1440 1420 1400 1380 1360 1340 1320 1300 1280; do
    if ping -c 1 -M do -s $((mtu - 28)) -W 1 8.8.8.8 &>/dev/null; then
        best_mtu=$mtu
    else
        break
    fi
done

if [[ "$best_mtu" -gt 0 ]]; then
    # Для мобильного интернета берём чуть ниже найденного (запас) в пределах 1360-1400
    suggested_mtu=$best_mtu
    if [[ "$suggested_mtu" -gt 1400 ]]; then
        suggested_mtu=1400
    fi
    if [[ "$suggested_mtu" -ne "$current_mtu" ]]; then
        sudo ip link set dev "$INTERFACE" mtu "$suggested_mtu" 2>/dev/null && \
            ok "MTU изменён: $current_mtu → $suggested_mtu (найден: $best_mtu)" || \
            warn "Не удалось изменить MTU (нет прав)"
    else
        ok "MTU $current_mtu — оптимален"
    fi
else
    warn "Тест MTU не удался — используем 1360"
    sudo ip link set dev "$INTERFACE" mtu 1360 2>/dev/null && ok "MTU установлен на 1360" || true
fi

# ─── 3. Фрагментация TLS (ClientHello) ─────────────────────────────
step "3. Добавление фрагментации TLS (обход DPI)"

cat > /tmp/fragment.json << 'JSONEOF'
{
  "packets": "tlshello",
  "length": "100-200",
  "interval": "10-20"
}
JSONEOF

cat > /tmp/sockopt.json << 'JSONEOF'
{
  "tcpFastOpen": true,
  "tcpKeepAliveIdle": 45,
  "tcpKeepAliveInterval": 15,
  "tcpUserTimeout": 10000,
  "tcpcongestion": "bbr"
}
JSONEOF

# Добавляем или обновляем fragment в streamSettings
if jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.fragment' "$CONFIG" >/dev/null 2>&1; then
    jq --slurpfile frag /tmp/fragment.json '.outbounds |= map(if .tag == "proxy" then .streamSettings.fragment = $frag[0] else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "Fragment TLS обновлён (packets=tlshello, length=100-200)"
else
    jq --slurpfile frag /tmp/fragment.json '.outbounds |= map(if .tag == "proxy" then .streamSettings.fragment = $frag[0] else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "Fragment TLS добавлен (packets=tlshello)"
fi

# Добавляем sockopt (если нет)
if ! jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.sockopt' "$CONFIG" >/dev/null 2>&1; then
    jq --slurpfile sockopt /tmp/sockopt.json '.outbounds |= map(if .tag == "proxy" then .streamSettings.sockopt = $sockopt[0] else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "Добавлены TCP оптимизации (FastOpen, KeepAlive, BBR)"
fi

# ─── 4. Ротация SNI (Server Name маскировка) ───────────────────────
step "4. Настройка SNI-спуфинга (ротация по whitelist)"

# Выбираем случайный домен из whitelist для SNI-spoofing
random_sni=${SNI_WHITELIST[$RANDOM % ${#SNI_WHITELIST[@]}]}
info "Выбран SNI для спуфинга: $random_sni"

# Для XTLS/REALITY — serverName
if jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.realitySettings' "$CONFIG" >/dev/null 2>&1; then
    jq --arg sni "$random_sni" '.outbounds |= map(if .tag == "proxy" then .streamSettings.realitySettings.serverName = $sni else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "REALITY serverName → $random_sni"
fi

# Для других TLS — serverName
if jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.tlsSettings' "$CONFIG" >/dev/null 2>&1; then
    jq --arg sni "$random_sni" '.outbounds |= map(if .tag == "proxy" then .streamSettings.tlsSettings.serverName = $sni else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "TLS serverName → $random_sni"
fi

# WebSocket Host header
if jq -e '.outbounds[] | select(.tag=="proxy") | .streamSettings.wsSettings' "$CONFIG" >/dev/null 2>&1; then
    jq --arg sni "$random_sni" '.outbounds |= map(if .tag == "proxy" then .streamSettings.wsSettings.headers = {"Host": $sni} else . end)' "$CONFIG" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG"
    ok "WebSocket Host → $random_sni"
fi

# Сохраняем список SNI для справки
echo "${SNI_WHITELIST[*]}" | tr ' ' '\n' > "$HOME/.config/v2rayN/sni-whitelist.txt"
ok "SNI whitelist сохранён: $HOME/.config/v2rayN/sni-whitelist.txt"
info "Для смены SNI: отредактируйте конфиг или запустите заново"

# ─── 5. Оптимизация протокола и порта ──────────────────────────────
step "5. Рекомендации по протоколу и порту"

# Определяем текущий протокол
current_protocol=$(jq -r '.outbounds[] | select(.tag=="proxy") | .protocol // "неизвестно"' "$CONFIG" 2>/dev/null)
current_port=$(jq -r '.outbounds[] | select(.tag=="proxy") | .port // "неизвестно"' "$CONFIG" 2>/dev/null)

info "Текущий протокол: $current_protocol"
info "Текущий порт: $current_port"

echo ""
echo "  Рекомендации для мобильных сетей:"
echo "  ┌──────────────┬──────────────────────┬────────────────────────┐"
echo "  │ Ситуация     │ Рекомендуемый        │ Причина                │"
echo "  ├──────────────┼──────────────────────┼────────────────────────┤"
echo "  │ Быстрый LTE  │ VLESS + Reality      │ Лучшая скорость/скрытие │"
echo "  │ Медленный 3G │ VLESS + Reality      │ Минимальный оверхед    │"
echo "  │ UDP блокирован│ VLESS + TCP (Reality)│ UDP-протоколы не пойдут│"
echo "  │ DPI-блокировка│ Fragment TLS + Reality│ Разбивка ClientHello  │"
echo "  │ WHITELIST    │ Two-server схема     │ Обход IP+SNI блокировки│"
echo "  └──────────────┴──────────────────────┴────────────────────────┘"

# ─── 6. Проверка валидности ───────────────────────────────────────
step "6. Проверка валидности конфига"
if jq empty "$CONFIG" 2>/dev/null; then
    ok "JSON валиден"
else
    fail "JSON сломан! Восстанавливаю бэкап..."
    cp "$BACKUP" "$CONFIG"
    exit 1
fi

# ─── 7. Создание fallback-сервера (two-server, если есть) ──────────
step "7. Two-server схема (инструкция)"

echo -e "  ${C}Если вы под FULL WHITELIST (IP+SNI блокировка):${N}"
echo ""
echo "  Схема:"
echo "    Телефон → [РФ VPS с белым IP] → [Зарубежный VPS] → Интернет"
echo ""
echo "  Шаги:"
echo "    1. Проверьте свой IP на вхождение в CIDR whitelist:"
echo "       https://github.com/hxehex/russia-mobile-internet-whitelist"
echo "       или запустите: scripts/detect-block-type.sh"
echo ""
echo "    2. Купите дешёвый РФ VPS (примеры хостингов с белыми IP):"
echo "       — Timeweb (cloud.timeweb.com)"
echo "       — JustHost (justhost.ru)"
echo "       — RUVDS (ruvds.com)"
echo ""
echo "    3. Установите Xray на оба сервера"
echo "    4. Настройте chain: inbound→РФ outbound→зарубеж outbound→inet"
echo ""
echo "  Альтернатива: Tor Bridges"
echo "    — Подписки: https://raw.githack.com/igareck/vpn-configs-for-russia/main/TOR-BRIDGES/TOR_BRIDGES_TOP100.txt"
echo "    — Клиент: OnionHop V2 (Tor Browser)"

# ─── 8. Тест скорости ─────────────────────────────────────────────
step "8. Тест скорости"
speed=$(curl -s -o /dev/null -w "%{speed_download}" -m 10 http://speedtest.tele2.net/1MB.zip 2>/dev/null)
if [[ -n "$speed" && "$speed" != "0" ]]; then
    speed_mb=$(echo "scale=2; $speed / 1024 / 1024" | bc 2>/dev/null || echo "N/A")
    speed_kbps=$(echo "scale=0; $speed * 8 / 1000" | bc 2>/dev/null || echo "0")
    ok "Скорость: ${speed_mb} MB/s (~${speed_kbps} Кбит/с)"
    if [[ "$speed_kbps" -lt 100 ]]; then
        warn "Скорость < 100 Кбит/с — возможен троттлинг!"
    fi
else
    warn "Не удалось измерить скорость"
fi

# ─── 9. Финальная проверка ────────────────────────────────────────
step "9. Финальная проверка"
proxy_ip=$(curl -s -m 5 --socks5-hostname 127.0.0.1:10808 https://ipinfo.io/ip 2>/dev/null)
if [[ -n "$proxy_ip" ]]; then
    ok "IP через прокси: $proxy_ip"
    
    # Проверка CGNAT
    if echo "$proxy_ip" | grep -qE '^(100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.)'; then
        warn "⚠ Прокси IP в CGNAT диапазоне"
    fi
    
    # Тест доступности через прокси
    test_proxy_url="https://google.com"
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --socks5-hostname 127.0.0.1:10808 "$test_proxy_url" 2>/dev/null)
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
        ok "Прокси функционален (HTTP $code)"
    else
        fail "Прокси НЕ отвечает по HTTP"
    fi
else
    fail "Прокси не отвечает"
fi

# ─── Итог ──────────────────────────────────────────────────────────
echo -e "\n${C}╔═══════════════════════════════════════════════════════════════╗${N}"
echo -e "${C}║  ИТОГ                                                     ║${N}"
echo -e "${C}╚═══════════════════════════════════════════════════════════════╝${N}"

if systemctl --user is-active --quiet xray.service 2>/dev/null || pgrep -x xray >/dev/null; then
    echo -e "${G}✅ ОПТИМИЗАЦИЯ:${N}"
    echo -e "${G}   • Fragment TLS: tlshello (100-200 байт)${N}"
    echo -e "${G}   • TCP: FastOpen + KeepAlive + BBR${N}"
    echo -e "${G}   • SNI spoof: $random_sni${N}"
    echo -e "${G}   • MTU: $(ip link show "$INTERFACE" 2>/dev/null | grep mtu | awk '{print $5}' || echo "?")${N}"
    echo -e "${G}   • IP через прокси: ${proxy_ip:-неизвестно}${N}"
    
    # Проверяем, стоит ли использовать двухсерверную схему
    direct_code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 https://twitter.com 2>/dev/null)
    if [[ "$direct_code" == "000" ]]; then
        echo ""
        echo -e "${Y}⚠ Рекомендация:${N}"
        echo -e "${Y}   Прямой доступ к twitter.com заблокирован.${N}"
        echo -e "${Y}   Если прокси тоже не открывает — нужна two-server схема.${N}"
    fi
else
    echo -e "${R}❌ Оптимизация не удалась — Xray не запущен${N}"
    if [[ -f "$BACKUP" ]]; then
        echo -e "${Y}   Восстановите бэкап:${N}"
        echo -e "   ${C}cp $BACKUP $CONFIG${N}"
        echo -e "   ${C}systemctl --user restart xray.service${N}"
    fi
fi

echo -e "\n${B}Бэкап: $BACKUP${N}"
echo -e "${B}SNI whitelist: $HOME/.config/v2rayN/sni-whitelist.txt${N}"
echo -e "${B}Ротация SNI:${N}"
echo -e "  ${C}scripts/rotate-sni.sh${N}        — случайная смена SNI"
echo -e "  ${C}scripts/rotate-sni.sh --list${N}  — показать доступные SNI"
echo -e "  ${C}scripts/rotate-sni.sh --set yandex.ru${N} — установить конкретный SNI"
