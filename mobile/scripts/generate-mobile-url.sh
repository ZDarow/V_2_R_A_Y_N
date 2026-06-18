#!/bin/bash
# generate-mobile-url.sh — генерация VLESS URL из JSON конфига для импорта в v2rayNG
# shellcheck disable=SC2034
# ================================================================================
# Использование:
#   bash scripts/generate-mobile-url.sh                    # из config-template-xray.json
#   bash scripts/generate-mobile-url.sh config/custom.json # из указанного файла
#
# Что делает:
#   Извлекает параметры outbound с тегом "proxy" из Xray JSON-конфига
#   и генерирует vless:// URL для импорта в v2rayNG через буфер обмена.
#
# Зависимости: jq (установите: apt install jq)
#
# Внимание:
#   Скрипт предназначен для ДЕСКТОПНОЙ генерации URL.
#   Для мобильной настройки без ПК используйте Termux-скрипт:
#     bash scripts/mobile-setup-termux.sh

SCRIPT_VERSION="1.0.0"

# Цвета
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ---- Парсинг аргументов ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/../config/config-template-xray.json}"

if [ ! -f "$CONFIG_FILE" ]; then
  error "Файл $CONFIG_FILE не найден.
Укажите путь к JSON-конфигу Xray:
  bash $0 путь/к/config.json"
fi

# ---- Проверка jq ----
if ! command -v jq &>/dev/null; then
  warn "jq не найден. Попытка парсинга через grep/sed..."
  USE_JQ=false
else
  USE_JQ=true
fi

# ---- Извлечение параметров ----
extract_param() {
  local key="$1"
  if [ "$USE_JQ" = true ]; then
    jq -r "$key" "$CONFIG_FILE" 2>/dev/null || echo ""
  else
    # Fallback: grep-парсинг (ненадёжный, лучше установить jq)
    grep -oP "\"$key\"\s*:\s*\"\K[^\"]*" "$CONFIG_FILE" 2>/dev/null | head -1 || echo ""
  fi
}

echo ""
echo "━━━ Генерация VLESS URL из $CONFIG_FILE ━━━"
echo ""

# Ищем outbound с tag=proxy
if [ "$USE_JQ" = true ]; then
  # Проверяем, есть ли jq и структура с tag=proxy
  PROXY_COUNT=$(jq '[.outbounds[] | select(.tag == "proxy")] | length' "$CONFIG_FILE" 2>/dev/null || echo "0")

  if [ "$PROXY_COUNT" -eq 0 ]; then
    # fallback: берём первый outbound с protocol vless/vmess
    PROTO=$(jq -r '.outbounds[0].protocol' "$CONFIG_FILE" 2>/dev/null || echo "unknown")
    if [ "$PROTO" = "vless" ] || [ "$PROTO" = "vmess" ]; then
      warn "Outbound с tag='proxy' не найден. Использую первый outbound."
      UUID=$(jq -r '.outbounds[0].settings.vnext[0].users[0].id' "$CONFIG_FILE" 2>/dev/null || echo "")
      SERVER=$(jq -r '.outbounds[0].settings.vnext[0].address' "$CONFIG_FILE" 2>/dev/null || echo "")
      PORT=$(jq -r '.outbounds[0].settings.vnext[0].port' "$CONFIG_FILE" 2>/dev/null || echo "")
      ENCRYPTION=$(jq -r '.outbounds[0].settings.vnext[0].users[0].encryption' "$CONFIG_FILE" 2>/dev/null || echo "none")
      FLOW=$(jq -r '.outbounds[0].settings.vnext[0].users[0].flow' "$CONFIG_FILE" 2>/dev/null || echo "")
      NETWORK=$(jq -r '.outbounds[0].streamSettings.network' "$CONFIG_FILE" 2>/dev/null || echo "tcp")
      SECURITY=$(jq -r '.outbounds[0].streamSettings.security' "$CONFIG_FILE" 2>/dev/null || echo "")
      SNI=$(jq -r '.outbounds[0].streamSettings.tlsSettings.serverName // .outbounds[0].streamSettings.realitySettings.serverNames[0] // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    else
      error "Не удалось найти outbound с protocol=vless в $CONFIG_FILE"
    fi
  else
    UUID=$(jq -r '.outbounds[] | select(.tag == "proxy") | .settings.vnext[0].users[0].id // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    SERVER=$(jq -r '.outbounds[] | select(.tag == "proxy") | .settings.vnext[0].address // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    PORT=$(jq -r '.outbounds[] | select(.tag == "proxy") | .settings.vnext[0].port // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    ENCRYPTION=$(jq -r '.outbounds[] | select(.tag == "proxy") | .settings.vnext[0].users[0].encryption // "none"' "$CONFIG_FILE" 2>/dev/null || echo "none")
    FLOW=$(jq -r '.outbounds[] | select(.tag == "proxy") | .settings.vnext[0].users[0].flow // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    NETWORK=$(jq -r '.outbounds[] | select(.tag == "proxy") | .streamSettings.network // "tcp"' "$CONFIG_FILE" 2>/dev/null || echo "tcp")
    SECURITY=$(jq -r '.outbounds[] | select(.tag == "proxy") | .streamSettings.security // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
    SNI=$(jq -r '.outbounds[] | select(.tag == "proxy") | .streamSettings.tlsSettings.serverName // .streamSettings.realitySettings.serverNames[0] // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  fi
else
  # Fallback без jq
  UUID=$(extract_param "id")
  SERVER=$(extract_param "address")
  PORT=$(extract_param "port")
  ENCRYPTION=$(extract_param "encryption")
  FLOW=$(extract_param "flow")
  NETWORK=$(extract_param "network")
  SECURITY=$(extract_param "security")
  SNI=$(extract_param "serverName")
fi

# ---- Валидация ----
if [ -z "$UUID" ] || [ -z "$SERVER" ] || [ -z "$PORT" ]; then
  error "Не удалось извлечь параметры сервера из $CONFIG_FILE.
Убедитесь, что файл содержит outbound с protocol=vless и tag=proxy."
fi

# ---- Генерация VLESS URL ----
# Формат: vless://uuid@server:port?params#name
VLESS_URL="vless://${UUID}@${SERVER}:${PORT}"

# Параметры запроса
QUERY_PARAMS=""
ADD_PARAM() {
  local key="$1" val="$2"
  if [ -n "$val" ]; then
    if [ -z "$QUERY_PARAMS" ]; then
      QUERY_PARAMS="?${key}=${val}"
    else
      QUERY_PARAMS="${QUERY_PARAMS}&${key}=${val}"
    fi
  fi
}

ADD_PARAM "encryption" "$ENCRYPTION"
ADD_PARAM "security" "$SECURITY"
ADD_PARAM "type" "$NETWORK"
[ -n "$FLOW" ] && ADD_PARAM "flow" "$FLOW"
[ -n "$SNI" ] && ADD_PARAM "sni" "$SNI"
# Дополнительные параметры для REALITY
if [ "$SECURITY" = "reality" ]; then
  FP=$(jq -r '.outbounds[] | select(.tag == "proxy") | .streamSettings.realitySettings.fingerprint // "chrome"' "$CONFIG_FILE" 2>/dev/null || echo "chrome")
  PBKEY=$(jq -r '.outbounds[] | select(.tag == "proxy") | .streamSettings.realitySettings.publicKey // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  SHORTID=$(jq -r '.outbounds[] | select(.tag == "proxy") | .streamSettings.realitySettings.shortIds[0] // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
  ADD_PARAM "fp" "$FP"
  ADD_PARAM "pbk" "$PBKEY"
  ADD_PARAM "sid" "$SHORTID"
fi

# Извлекаем имя сервера (первая часть user@host)
SERVER_NAME=$(jq -r '.outbounds[] | select(.tag == "proxy") | .settings.vnext[0].users[0].email // empty' "$CONFIG_FILE" 2>/dev/null || echo "")

VLESS_URL="${VLESS_URL}${QUERY_PARAMS}"

if [ -n "$SERVER_NAME" ]; then
  VLESS_URL="${VLESS_URL}#${SERVER_NAME}"
else
  VLESS_URL="${VLESS_URL}#Mobile-$(date +%Y%m%d)"
fi

# ---- Вывод ----
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  VLESS URL для импорта в v2rayNG:"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo -e "${CYAN}${VLESS_URL}${NC}"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ---- Копирование в буфер обмена (если возможно) ----
if command -v termux-clipboard-set &>/dev/null; then
  echo -n "$VLESS_URL" | termux-clipboard-set
  info "URL скопирован в буфер обмена Termux!"
elif command -v xclip &>/dev/null; then
  echo -n "$VLESS_URL" | xclip -selection clipboard
  info "URL скопирован в буфер обмена (X11)!"
elif command -v pbcopy &>/dev/null; then
  echo -n "$VLESS_URL" | pbcopy
  info "URL скопирован в буфер обмена (macOS)!"
else
  echo "  Скопируйте URL вручную (выделите выше и Ctrl+Shift+C)."
fi

echo ""
echo "  В v2rayNG: ➕ → Импорт из буфера обмена"
echo ""
