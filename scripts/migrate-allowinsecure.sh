#!/bin/bash
# migrate-allowinsecure.sh — миграция allowInsecure → pinnedPeerCertSha256
# ============================================================================
# Xray-core v26.2.6+ уже удалил allowInsecure (2026-02).
# При подключении с allowInsecure: true Xray выдаёт:
#   The feature "allowInsecure" has been removed and migrated to "pinnedPeerCertSha256".
#   Please use "pinnedPeerCertSha256" array field in the stream settings.
#
# Этот скрипт находит конфиги с allowInsecure и даёт инструкции по замене.
#
# Использование:
#   ./scripts/migrate-allowinsecure.sh                # Поиск + инструкции
#   ./scripts/migrate-allowinsecure.sh --check         # Только проверка
#   ./scripts/migrate-allowinsecure.sh --list          # Список конфигов с allowInsecure
#   ./scripts/migrate-allowinsecure.sh --force         # Автозамена allowInsecure → pinnedPeerCertSha256
#   ./scripts/migrate-allowinsecure.sh --help          # Справка
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

SEARCH_DIRS=(
  "$HOME/.config/v2rayN"
  "$HOME/.local/share/v2rayN/binConfigs"
  "$HOME/.local/share/v2rayN/guiConfigs"
  "/opt/v2rayN"
)

MODE="check"
AUTO_FIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --list)  MODE="list" ;;
    --force) MODE="check"; AUTO_FIX=true ;;
    --help)
      echo "migrate-allowinsecure.sh — миграция allowInsecure → pinnedPeerCertSha256"
      echo ""
      echo "Использование:"
      echo "  $0 [--check]      Поиск allowInsecure + инструкции"
      echo "  $0 --list         Только список файлов"
      echo "  $0 --force        Автозамена allowInsecure: true → pinnedPeerCertSha256: []"
      echo "  $0 --help         Справка"
      exit 0
      ;;
    *) warn "Неизвестный флаг: $1"; exit 1 ;;
  esac
  shift
done

header "Xray-core: allowInsecure удалён"

echo ""
echo "  Xray-core v26.2.6+ (февраль 2026) полностью удалил поддержку allowInsecure."
echo "  v2rayNG 2.2.3+ также убрал UI-галочку allowInsecure в настройках подписки."
echo ""

# ---- Определяем версию Xray-core ----
XRAY_VERSION=""
if command -v xray &>/dev/null; then
  XRAY_VERSION=$(xray version 2>/dev/null | head -1 | grep -oP 'Xray\s+\K[\d.]+' || true)
fi
if command -v xray &>/dev/null && command -v v2rayNG &>/dev/null; then
  warn "Установлены оба: xray ($XRAY_VERSION) и v2rayNG"
fi
# Очищаем версию — только мажор.минор.патч
XRAY_VERSION_CLEAN="${XRAY_VERSION%%-*}"
XRAY_VERSION_CLEAN="${XRAY_VERSION_CLEAN%%+*}"

if [ -n "$XRAY_VERSION" ]; then
  # Сравниваем версии: 26.2.6+
  IFS='.' read -ra VER_PARTS <<< "$XRAY_VERSION_CLEAN"
  MAJOR="${VER_PARTS[0]:-0}"; MINOR="${VER_PARTS[1]:-0}"; PATCH="${VER_PARTS[2]:-0}"
  if [ "$MAJOR" -gt 26 ] || { [ "$MAJOR" -eq 26 ] && [ "$MINOR" -gt 2 ]; } || { [ "$MAJOR" -eq 26 ] && [ "$MINOR" -eq 2 ] && [ "$PATCH" -ge 6 ]; }; then
    warn "Xray-core $XRAY_VERSION — allowInsecure уже удалён. Найденные allowInsecure вызовут ошибку."
  elif [ -n "$XRAY_VERSION" ]; then
    info "Xray-core $XRAY_VERSION — allowInsecure ещё поддерживается. Рекомендуется миграция."
  fi
fi

header "Поиск allowInsecure в конфигах v2rayN"

FOUND_FILES=()
for dir in "${SEARCH_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    while IFS= read -r -d '' f; do
      if grep -q 'allowInsecure.*true' "$f" 2>/dev/null; then
        FOUND_FILES+=("$f")
      fi
    done < <(find "$dir" -name '*.json' -type f -print0 2>/dev/null || true)
  fi
done

if [ "${#FOUND_FILES[@]}" -eq 0 ]; then
  info "allowInsecure не найден в конфигах — установка готова."
  exit 0
fi

warn "Найдено ${#FOUND_FILES[@]} файлов с allowInsecure:"
echo ""

# ---- Автозамена --force ----
if $AUTO_FIX; then
  header "Автозамена allowInsecure → pinnedPeerCertSha256"
  for f in "${FOUND_FILES[@]}"; do
    echo "  Обработка: $f"
    # Замена allowInsecure: true → pinnedPeerCertSha256: []
    # Сохраняем оригинал
    cp "$f" "${f}.bak.$(date +%s)"
    sed -i 's/allowInsecure.*true/pinnedPeerCertSha256: []/g' "$f"
    info "  Исправлено: $f"
    echo "  Резервная копия: ${f}.bak.*"
  done
  echo ""
  warn "ПРИМЕЧАНИЕ: pinnedPeerCertSha256: [] — отключает валидацию! Заполните массив отпечатками."
  echo "  Запустите $0 --check после заполнения отпечатков."
  exit 0
fi

# ---- Режимы отображения ----
case "$MODE" in
  list)
    for f in "${FOUND_FILES[@]}"; do
      echo "  - $f"
      grep -n 'allowInsecure' "$f" 2>/dev/null | while IFS= read -r line; do
        echo "      $line"
      done
    done
    exit 0
    ;;
  check)
    for f in "${FOUND_FILES[@]}"; do
      echo "  - $f"
    done
    echo ""
    ;;
esac

# ============================================================================
# ИНСТРУКЦИЯ ПО ЗАМЕНЕ allowInsecure → pinnedPeerCertSha256
# ============================================================================
header "Инструкция по миграции"

cat << 'MIGRATION_GUIDE'

┌─────────────────────────────────────────────────────────────────────────┐
│                 ЗАМЕНА allowInsecure → pinnedPeerCertSha256             │
│              Xray-core v26.2.6+ / v2rayNG 2.2.3+ / v2rayN 7.x         │
└─────────────────────────────────────────────────────────────────────────┘

1. ПОЛУЧЕНИЕ SHA256-ОТПЕЧАТКА СЕРТИФИКАТА
   ───────────────────────────────────────

   Вариант А: TLS/TCP (обычные серверы, openssl работает)
     openssl s_client -connect <host>:<port> -servername <host> </dev/null 2>/dev/null \
       | openssl x509 -fingerprint -sha256 -noout \
       | cut -d= -f2

     Вывод: AE:24:3D:66:8E:C9:C7:F7:4A:0D:CD:1A:D2:1C:66:76:...

   Вариант Б: Hysteria / Hysteria2 (UDP-based, openssl НЕ РАБОТАЕТ)
     openssl s_client не поддерживает UDP. Получите SHA256 на сервере:
       openssl x509 -fingerprint -sha256 -noout -in /path/to/cert.pem \
         | cut -d= -f2

   Вариант В: Промежуточный CA (рекомендуется для Let's Encrypt)
     Let's Encrypt меняет leaf-сертификаты каждые ~90 дней.
     Лучше фиксировать промежуточный CA (действителен 2+ года).

     Получение SHA256 промежуточного CA:
       1. openssl s_client -connect <host>:443 -showcerts </dev/null 2>/dev/null
       2. Извлеките второй сертификат в цепочке (Issuer: R11 / Let's Encrypt)
       3. Сохраните его в ca.pem и выполните:
            openssl x509 -fingerprint -sha256 -noout -in ca.pem | cut -d= -f2

     Отпечаток промежуточного CA Let's Encrypt R11:
       (будет опубликован на https://letsencrypt.org/certificates/)

2. ДВА ФОРМАТА ОТПЕЧАТКОВ
   ────────────────────────

   Формат hex (без разделителей) — предпочтительный:
     "pinnedPeerCertSha256": [
       "ae243d668ec9c7f74a0dcd1ad21c6676b4efe30c39728934b362093af886bf77"
     ]

   Формат OpenSSL (с двоеточиями) — тоже поддерживается:
     "pinnedPeerCertSha256": [
       "AE:24:3D:66:8E:C9:C7:F7:4A:0D:CD:1A:D2:1C:66:76:B4:EF:E3:0C:39:72:89:34:B3:62:09:3A:F8:86:BF:77"
     ]

   Xray-core автоматически нормализует оба формата.

3. ГДЕ МЕНЯТЬ
   ───────────

   • v2rayN: Настройки подписки → ✏️ (карандаш) → Отпечаток сертификата
   • v2rayNG (Android): Настройки подписки → Certificate pinning
   • Ручное редактирование: найдите секцию "streamSettings" (обычно рядом с "security": "tls")
     и замените:
       "security": "tls",
       "tlsSettings": {
         "allowInsecure": true,
         ...
       }
     на:
       "security": "tls",
       "tlsSettings": {
         "pinnedPeerCertSha256": ["<SHA256-отпечаток>"],
         ...
       }

4. ПРОВЕРКА ПОСЛЕ ЗАМЕНЫ
   ───────────────────────

   • Запустите $0 --check — скрипт не должен найти allowInsecure
   • Попробуйте подключиться: если Xray-core выбрасывает ошибку:
       The feature "allowInsecure" has been removed...
     значит, где-то остался старый allowInsecure
   • В логах v2rayNG: раздел Certificate pinning должен показывать
     "verified" с вашим SHA256

5. ЧАСТЫЕ ВОПРОСЫ
   ───────────────

   Q: Что если allowInsecure НЕ найден, но подключение не работает?
   A: Проверьте DNS-резолвинг в конфиге — domainStrategy: IPOnDemand
      (см. config-template-xray.json)

   Q: Можно ли просто убрать allowInsecure без pinnedPeerCertSha256?
   A: Да, если сертификат сервера подписан публичным CA (Let's Encrypt, ZeroSSL),
      Xray-core проверит цепочку доверия самостоятельно.

   Q: pinnedPeerCertSha256: [] — что это?
   A: Отключает валидацию сертификата (как старый allowInsecure).
      НЕ ИСПОЛЬЗУЙТЕ — это дыра в безопасности.

   Q: Почему не добавить поддержку verifyPeerCertByName (SNI-фиксация)?
   A: verifyPeerCertByName — это отдельное поле ниже pinnedPeerCertSha256.
      Используйте его, если хотите фиксировать SNI:
        "verifyPeerCertByName": false    # (по умолчанию true)

   Q: Как проверить, что allowInsecure действительно удалён из Xray-core?
   A: xray version | head -1   # >= 26.2.6 — удалён
      v2rayNG → О программе    # >= 2.2.3 — удалён из UI

   Q: Можно ли автоматически конвертировать все конфиги?
   A: $0 --force — заменит allowInsecure: true на pinnedPeerCertSha256: []
      (НО нужно вручную заполнить SHA256!)

ССЫЛКИ
──────
  • Документация Xray-core: https://xtls.github.io/config/features/certValidate.html
  • v2rayNG Discussion #9460: https://github.com/2dust/v2rayNG/discussions/9460
  • Let's Encrypt CA: https://letsencrypt.org/certificates/
MIGRATION_GUIDE


