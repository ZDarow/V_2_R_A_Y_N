#!/bin/bash
# migrate-allowinsecure.sh — миграция конфигов с allowInsecure на pinnedPeerCertSha256
# ============================================================================
# Xray-core ОТКЛЮЧАЕТ allowInsecure с 1 августа 2026.
# Этот скрипт находит все конфиги с allowInsecure и помогает их исправить.
#
# Использование:
#   ./scripts/migrate-allowinsecure.sh               # Поиск allowInsecure в конфигах
#   ./scripts/migrate-allowinsecure.sh --check        # Только проверка (по умолчанию)
#   ./scripts/migrate-allowinsecure.sh --list         # Список конфигов с allowInsecure
#   ./scripts/migrate-allowinsecure.sh --help         # Справка
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- Директории поиска ----
SEARCH_DIRS=(
  "$HOME/.config/v2rayN"
  "$HOME/.local/share/v2rayN/ binConfigs"
  "$HOME/.local/share/v2rayN/guiConfigs"
  "/opt/v2rayN"
)

# ---- Парсинг аргументов ----
MODE="check"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --list)  MODE="list" ;;
    --help)
      echo "migrate-allowinsecure.sh — миграция allowInsecure → pinnedPeerCertSha256"
      echo ""
      echo "Использование:"
      echo "  $0 [--check]           # Поиск allowInsecure (по умолчанию)"
      echo "  $0 --list              # Показать файлы с allowInsecure"
      echo "  $0 --help              # Справка"
      echo ""
      echo "Что делать:"
      echo "  1. Узнайте SHA256 отпечаток сертификата вашего сервера:"
      echo "     v2rayNG: лог подключения → Certificate pinning"
      echo "     openssl: openssl s_client -connect <host>:<port> < /dev/null | openssl x509 -fingerprint -sha256 -noout"
      echo "  2. В v2rayN: Настройки подписки → ✏️ → Отпечаток сертификата → Вкл"
      echo "  3. Уберите allowInsecure: true из config-template-xray.json"
      exit 0
      ;;
    *) warn "Неизвестный флаг: $1"; exit 1 ;;
  esac
  shift
done

header "Поиск allowInsecure в конфигах v2rayN"

FOUND_FILES=()
for dir in "${SEARCH_DIRS[@]}"; do
  # Убираем лишний пробел в имени директории
  dir_clean="${dir//  /}"
  if [ -d "$dir_clean" ]; then
    while IFS= read -r -d '' f; do
      if grep -q 'allowInsecure.*true' "$f" 2>/dev/null; then
        FOUND_FILES+=("$f")
      fi
    done < <(find "$dir_clean" -name '*.json' -type f -print0 2>/dev/null || true)
  fi
done

if [ "${#FOUND_FILES[@]}" -eq 0 ]; then
  info "allowInsecure не найден в конфигах — ваша установка готова к августу 2026."
  exit 0
fi

warn "Найдено ${#FOUND_FILES[@]} файлов с allowInsecure:"

case "$MODE" in
  list)
    for f in "${FOUND_FILES[@]}"; do
      echo "  - $f"
      # Показываем строки с allowInsecure
      grep -n 'allowInsecure' "$f" 2>/dev/null | while IFS= read -r line; do
        echo "      $line"
      done
    done
    ;;
  check)
    for f in "${FOUND_FILES[@]}"; do
      echo "  - $f"
    done
    echo ""
    warn "Xray-core отключает allowInsecure с 1 августа 2026."
    echo ""
    echo "  Что нужно сделать:"
    echo ""
    echo "  1. Получите SHA256 отпечаток сертификата вашего сервера:"
    echo "     openssl s_client -connect <host>:<port> < /dev/null 2>/dev/null \\"
    echo "       | openssl x509 -fingerprint -sha256 -noout \\"
    echo "       | cut -d= -f2"
    echo ""
    echo "  2. В v2rayN откройте Настройки подписки → ✏️ (карандаш)"
    echo "     → Отпечаток сертификата → Вкл"
    echo "     → Вставьте SHA256 отпечаток."
    echo ""
    echo "  3. Замените allowInsecure на pinnedPeerCertSha256:"
    echo "     В config-template-xray.json уберите allowInsecure: true"
    echo "     и добавьте pinnedPeerCertSha256: ['<SHA256-отпечаток>']"
    echo ""
    echo "  Подробнее: https://xtls.github.io/config/features/certValidate.html"
    ;;
esac
