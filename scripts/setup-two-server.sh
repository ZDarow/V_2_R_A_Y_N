#!/bin/bash
# setup-two-server.sh — настройка двухсерверной схемы для обхода IP-whitelist
#
# Схема: Клиент (РФ, мобильный) → РФ-сервер (Xray, белый IP) →
#        Зарубежный сервер (Xray) → Интернет
#
# Использование:
#   setup-two-server.sh --help
#   setup-two-server.sh --check          # Проверка текущей конфигурации
#   setup-two-server.sh --gen-config     # Генерация конфигов для обоих серверов
# ============================================================================

set -uo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $*"; }
fail() { echo -e "  ${R}✗${N} $*"; }
warn() { echo -e "  ${Y}!${N} $*"; }
info() { echo -e "  ${C}ℹ${N} $*"; }
step() { echo -e "\n${B}━━━ $* ━━━${N}"; }

show_help() {
    cat << 'HELP'
Использование: setup-two-server.sh [--help | --check | --gen-config]

Двухсерверная схема для обхода IP-whitelist мобильных операторов РФ.

Схема:
  Клиент (РФ, телефон) → РФ-сервер (Xray, белый IP) →
  → Зарубежный сервер (Xray) → Интернет

Когда нужно:
  - Мобильный оператор проверяет IP (не только SNI)
  - SNI-спуфинг не помогает
  - Прямые подключения к зарубежным серверам блокируются

Что нужно:
  1. РФ VPS с IP из CIDR-белого списка (hxehex)
  2. Зарубежный VPS (любой, без ограничений)
  3. Xray-core на обоих серверах

Команды:
  --help          Показать эту справку
  --check         Проверить, нужна ли two-server схема
  --gen-config    Сгенерировать конфиги для РФ- и зарубежного сервера
HELP
    exit 0
}

# ─── Проверка необходимости ────────────────────────────────────────
do_check() {
    step "1. Проверка: нужна ли two-server схема"

    local my_ip
    my_ip=$(curl -s -m 5 https://ipinfo.io/ip 2>/dev/null)

    if [[ -z "$my_ip" ]]; then
        fail "Не удалось получить внешний IP"
        return 1
    fi
    info "Ваш внешний IP: $my_ip"

    # Проверка CGNAT
    if echo "$my_ip" | grep -qE '^(100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.)'; then
        warn "Вы за CGNAT — двухсерверная схема может не работать напрямую"
    fi

    # Проверка, открывается ли заблокированный сайт
    local direct_code
    direct_code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 https://twitter.com 2>/dev/null)
    if [[ "$direct_code" =~ ^(200|301|302)$ ]]; then
        ok "Twitter открывается напрямую — блокировки нет"
        return 0
    fi
    warn "Twitter НЕ открывается напрямую"

    # Проверка через прокси (если работает)
    if ss -tln 2>/dev/null | grep -q ":10808 "; then
        local proxy_code
        proxy_code=$(curl -s -o /dev/null -w "%{http_code}" -m 5 --socks5-hostname 127.0.0.1:10808 https://twitter.com 2>/dev/null)
        if [[ "$proxy_code" =~ ^(200|301|302)$ ]]; then
            ok "Twitter открывается через прокси — two-server НЕ нужна"
            return 0
        else
            fail "Twitter НЕ открывается даже через прокси"
        fi
    fi

    echo ""
    echo "  ${Y}Признаки необходимости two-server схемы:${N}"
    echo "  - Прямой доступ к заблокированным сайтам: НЕТ"
    echo "  - Прокси: НЕ помогает (IP-блокировка)"
    echo "  - Вердикт: ${R}Two-server схема НУЖНА${N}"
}

# ─── Генерация конфигов ────────────────────────────────────────────
# ─── Генерация ключей X25519 ──────────────────────────────────────────
gen_x25519_keypair() {
    local keypair
    keypair=$(xray x25519 2>/dev/null) || {
        # Плейсхолдеры, если xray недоступен
        echo "Private key: PLACEHOLDER_PRIVATE_KEY_BASE64"
        echo "Public key: PLACEHOLDER_PUBLIC_KEY_BASE64"
        return
    }
    echo "$keypair"
}

do_gen_config() {
    step "2. Генерация конфигов Xray для two-server схемы"
    echo ""
    echo "  Введите параметры РФ-сервера (с белым IP):"
    read -rp "    IP РФ-сервера: " ru_ip
    read -rp "    Порт РФ-сервера (по умолчанию 8443): " ru_port
    ru_port="${ru_port:-8443}"
    read -rp "    Пароль для входящего соединения: " ru_password
    echo ""
    echo "  Введите параметры зарубежного сервера:"
    read -rp "    IP зарубежного сервера: " foreign_ip
    read -rp "    Порт зарубежного сервера (по умолчанию 443): " foreign_port
    foreign_port="${foreign_port:-443}"

    # Генерируем две разные пары ключей (РФ-сервер и зарубежный сервер)
    local ru_kp foreign_kp
    ru_kp=$(gen_x25519_keypair)
    foreign_kp=$(gen_x25519_keypair)

    local ru_priv ru_pub foreign_priv foreign_pub
    ru_priv=$(echo "$ru_kp" | grep 'Private key' | awk '{print $NF}')
    ru_pub=$(echo "$ru_kp" | grep 'Public key' | awk '{print $NF}')
    foreign_priv=$(echo "$foreign_kp" | grep 'Private key' | awk '{print $NF}')
    foreign_pub=$(echo "$foreign_kp" | grep 'Public key' | awk '{print $NF}')

    local ru_config="/tmp/xray-ru-server-config.json"
    local foreign_config="/tmp/xray-foreign-server-config.json"
    local client_config="/tmp/xray-client-config.json"

    # Конфиг РФ-сервера (принимает от клиента, шлёт на зарубежный)
    cat > "$ru_config" << JSONEOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "proxy-in",
      "port": $ru_port,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$ru_password"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["microsoft.com", "www.microsoft.com"],
          "privateKey": "$ru_priv",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "to-foreign",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$foreign_ip",
            "port": $foreign_port,
            "users": [{"id": "$ru_password", "encryption": "none"}]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "cloudflare.com",
          "fingerprint": "chrome"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
JSONEOF

    # Конфиг зарубежного сервера (принимает от РФ, шлёт в интернет)
    cat > "$foreign_config" << JSONEOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "from-ru",
      "port": $foreign_port,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$ru_password"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.cloudflare.com:443",
          "serverNames": ["cloudflare.com", "www.cloudflare.com"],
          "privateKey": "$foreign_priv",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "to-internet",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
JSONEOF

    # Конфиг клиента (для v2rayN) — с publicKey РФ-сервера для REALITY
    cat > "$client_config" << JSONEOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": { "udp": true }
    },
    {
      "tag": "http-in",
      "port": 10809,
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {}
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "$ru_ip",
            "port": $ru_port,
            "users": [{"id": "$ru_password", "encryption": "none"}]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "microsoft.com",
          "fingerprint": "chrome",
          "publicKey": "$ru_pub",
          "shortIds": ["0123456789abcdef"]
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
JSONEOF

    echo ""
    ok "Конфиги сгенерированы:"
    echo "  РФ-сервер:       $ru_config"
    echo "  Зарубежный:      $foreign_config"
    echo "  Клиент:          $client_config"
    echo ""
    echo "  ${Y}Ключи REALITY (сохраните для отладки):${N}"
    echo "  РФ-сервер  privateKey: $ru_priv"
    echo "  РФ-сервер  publicKey:  $ru_pub"
    echo "  Зарубежный privateKey: $foreign_priv"
    echo "  Зарубежный publicKey:  $foreign_pub"
    echo ""
    echo "  ${Y}Действия:${N}"
    echo "  1. Скопируйте xray-ru-server-config.json на РФ-сервер"
    echo "  2. Скопируйте xray-foreign-server-config.json на зарубежный сервер"
    echo "  3. Скопируйте xray-client-config.json в ~/.config/v2rayN/config.json"
    echo "  4. Запустите Xray на обоих серверах и клиенте"
}

# ─── Main ───────────────────────────────────────────────────────────
main() {
    case "${1:-}" in
        --help)      show_help ;;
        --check)     do_check ;;
        --gen-config) do_gen_config ;;
        *)
            echo "Использование: $0 [--help | --check | --gen-config]"
            exit 1
            ;;
    esac
}

main "$@"
