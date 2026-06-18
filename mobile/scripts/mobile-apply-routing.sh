#!/bin/bash
# mobile-apply-routing.sh — применение правил роутинга в v2rayNG через clipboard
# shellcheck disable=SC2034
# SC2034: content/APP_OPENED зарезервированы для будущего использования
# ============================================================================
# Автоматизирует импорт правил роутинга в v2rayNG на Android:
#   1. Загружает JSON-файл правил из репозитория
#   2. Копирует содержимое в буфер обмена через termux-clipboard-set
#   3. Открывает v2rayNG (главный экран)
#   4. Выводит минимальную инструкцию — остаётся 2 тапа пользователя
#
# Запуск в Termux:
#   bash mobile-apply-routing.sh          # спросит какой пресет
#   bash mobile-apply-routing.sh russia   # «Всё через прокси»
#   bash mobile-apply-routing.sh blocked  # «Только заблокированное»
#
# Зависимости: curl, termux-clipboard-set (termux-api)
# ============================================================================

SCRIPT_VERSION="1.0.0"
REPO="https://github.com/ZDarow/V_2_R_A_Y_N"
BRANCH="main"
PACKAGE="com.v2ray.ang.fdroid"  # F-Droid версия; fallback на com.v2ray.ang

# ---- Цвета ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- Определяем правильный package name ----
detect_package() {
  if pm list packages 2>/dev/null | grep -q "com.v2ray.ang.fdroid"; then
    PACKAGE="com.v2ray.ang.fdroid"
    return 0
  elif pm list packages 2>/dev/null | grep -q "com.v2ray.ang"; then
    PACKAGE="com.v2ray.ang"
    return 0
  fi
  return 1
}

# ---- Получение контента JSON ----
fetch_routing_json() {
  local preset="$1"
  local filename url content

  case "$preset" in
    russia|routing-russia|v2rayng-routing-russia)
      filename="v2rayng-routing-russia.json"
      label="Всё через прокси"
      ;;
    blocked|only-blocked|v2rayng-only-blocked)
      filename="v2rayng-only-blocked.json"
      label="Только заблокированное"
      ;;
    *)
      echo "  Неизвестный пресет: $preset"
      echo "  Используйте: russia | blocked"
      exit 1
      ;;
  esac

  url="$REPO/raw/$BRANCH/config/$filename"
  echo "$label"
  echo "$filename"
  echo "$url"
}

# ---- Проверка окружения ----
header "Проверка"

if [ ! -d "/data/data/com.termux" ]; then
  error "Скрипт предназначен для Termux на Android."
fi

if ! detect_package; then
  warn "v2rayNG не установлен. Установите APK:"
  warn "  https://github.com/2dust/v2rayNG/releases"
  # не завершаем — можно установить clipboard и показать инструкцию
fi
info "v2rayNG: $PACKAGE"

if command -v termux-clipboard-set &>/dev/null; then
  HAS_CLIPBOARD=true
  info "termux-clipboard-set: доступен"
else
  HAS_CLIPBOARD=false
  warn "termux-clipboard-set не найден"
  warn "  pkg install termux-api"
fi

# ---- Выбор пресета ----
PRESET="${1:-}"
if [ -z "$PRESET" ]; then
  header "Выбор пресета"
  echo "  1) russia  — Всё через прокси (весь трафик)"
  echo "  2) blocked — Только заблокированное (экономия трафика)"
  echo ""
  read -r -t 15 -n 1 -p "  Выбор [1/2]: " choice
  echo ""
  case "${choice:-1}" in
    2|b|B) PRESET="blocked" ;;
    *)     PRESET="russia"  ;;
  esac
fi

# ---- Загрузка ----
header "Загрузка"
read -r LABEL FILENAME URL < <(fetch_routing_json "$PRESET")
info "Пресет: $LABEL"

TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

if ! curl -sSL --connect-timeout 15 -o "$TEMP_FILE" "$URL"; then
  error "Не удалось загрузить $URL"
fi

# Валидация JSON
if ! python3 -m json.tool "$TEMP_FILE" > /dev/null 2>&1; then
  error "Загруженный файл не является валидным JSON"
fi
info "JSON: валиден ($(wc -c < "$TEMP_FILE") байт)"

# ---- Буфер обмена ----
header "Буфер обмена"

if [ "$HAS_CLIPBOARD" = true ]; then
  if TERMUX_CLIPBOARD_JSON=true termux-clipboard-set "$(cat "$TEMP_FILE")"; then
    info "JSON-правила скопированы в буфер обмена!"
    CLIPBOARD_OK=true
  else
    warn "Не удалось скопировать в буфер обмена"
    CLIPBOARD_OK=false
  fi
else
  CLIPBOARD_OK=false
  echo "  Содержимое файла:"
  echo ""
  cat "$TEMP_FILE"
  echo ""
fi

# ---- Открыть v2rayNG ----
header "Запуск v2rayNG"

if command -v am &>/dev/null; then
  echo -n "  Открываю v2rayNG ... "
  if am start -n "$PACKAGE/.ui.MainActivity" 2>/dev/null; then
    echo "OK"
    APP_OPENED=true
    sleep 1
  else
    echo "ОШИБКА"
    warn "Не удалось открыть v2rayNG через am start"
    warn "Откройте вручную"
    APP_OPENED=false
  fi
else
  warn "am (ActivityManager) не найден"
  warn "Откройте v2rayNG вручную"
  APP_OPENED=false
fi

# ---- Deep link для подписки ----
# v2rayNG поддерживает deep link: v2rayng://install-sub?url=...
# Показываем примеры для igareck BLACK (russia) / WHITE (blocked)
header "Deep link для подписок"
echo "  v2rayNG поддерживает однокликовый импорт подписок:"
echo ""

case "$PRESET" in
  russia)
    SUB_LABEL="igareck BLACK (весь трафик через прокси)"
    SUB_URL="https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt"
    ;;
  blocked)
    SUB_LABEL="igareck WHITE (только РФ через прокси)"
    SUB_URL="https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt"
    ;;
esac

echo "  Рекомендуемая подписка: $SUB_LABEL"
echo ""
echo "  Нажмите на ссылку в браузере:"
echo "    v2rayng://install-sub/$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SUB_URL', safe=''))" 2>/dev/null || echo "$SUB_URL")"
echo ""
echo "  Или скопируйте URL и вставьте в v2rayNG ➕ → Import from URL:"
echo "    $SUB_URL"

# ---- Инструкция ----
header "Осталось сделать в v2rayNG"

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║  2 ТАПА в v2rayNG — и всё готово!            ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

echo "  ─── ШАГ 1: Откройте меню слева ───"
echo ""
echo "    Нажмите ≡ (три полоски) или свайпните слева"
echo "    → выберите «Маршрутизация»"
echo ""

echo "  ─── ШАГ 2: Импортируйте правила ───"
echo ""
echo "    Нажмите ⋮ (три точки) сверху справа"
if [ "$CLIPBOARD_OK" = true ]; then
  echo "    → «Импорт правил из буфера обмена» ✅ (уже в буфере)"
else
  echo "    → «Импорт правил из файла»"
  echo "    → Выберите $FILENAME в assets/"
fi
echo "    → Нажмите OK для подтверждения"
echo ""

echo "  ─── ДОПОЛНИТЕЛЬНО: Доменная стратегия ───"
echo ""
echo "    В этом же экране Маршрутизация → поле"
echo "    «Доменная стратегия» → выберите IPOnDemand"
echo ""

echo "  ─── ДОПОЛНИТЕЛЬНО: Подписка ───"
echo ""
echo "    v2rayNG → ➕ (плюс) → Import from URL"
echo "    Вставьте URL подписки (см. выше)"
echo ""

echo ""
echo -e "${GREEN}✅ Готово!${NC}"
echo "   Версия скрипта: $SCRIPT_VERSION"
