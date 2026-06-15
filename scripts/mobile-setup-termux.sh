#!/bin/bash
set -euo pipefail

# mobile-setup-termux.sh — Настройка v2rayNG на Android через Termux без ПК
# ============================================================================
# Запуск в Termux:
#   pkg install curl
#   curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/mobile-setup-termux.sh | bash
#
# Или после клонирования:
#   bash scripts/mobile-setup-termux.sh
#
# Назначение:
#   1. Скачивает geoip.dat / geosite.dat из runetfreedom
#   2. Копирует правила роутинга для v2rayNG (файлы + буфер обмена)
#   3. Выводит пошаговую инструкцию с clipboard-импортом
#
# Решает проблему «курицы и яйца»: для geoip/geosite нужен прокси,
# а для прокси нужны geoip/geosite — скрипт работает ДО первого запуска.
#
# Основано на формате из discussion #4761:
#   https://github.com/2dust/v2rayNG/discussions/4761

SCRIPT_VERSION="1.1.0"
REPO="https://github.com/ZDarow/V_2_R_A_Y_N"
BRANCH="main"
RULES_RELEASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
V2RAYNG_ASSETS="/sdcard/Android/data/com.v2ray.ang/files/assets"

# ---- Цвета ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- 1. Проверка окружения ----
header "Проверка окружения"

if [ ! -d "/data/data/com.termux" ]; then
  error "Этот скрипт предназначен для Termux на Android.
Установите Termux из F-Droid: https://f-droid.org/packages/com.termux/"
fi

info "Termux: обнаружен"

if ! pm list packages 2>/dev/null | grep -q "com.v2ray.ang"; then
  warn "v2rayNG не установлен. Скачайте APK:"
  warn "  https://github.com/2dust/v2rayNG/releases"
  warn "  или через F-Droid: https://f-droid.org/packages/com.v2ray.ang/"
  echo ""
  read -r -t 10 -n 1 -p "Продолжить без v2rayNG? [y/N] " skip
  echo
  if [[ ! "${skip:-n}" =~ [yY] ]]; then
    exit 1
  fi
  INSTALL_V2RAYNG=false
else
  info "v2rayNG: установлен"
  INSTALL_V2RAYNG=true
fi

# Проверка termux-clipboard-set
if command -v termux-clipboard-set &>/dev/null; then
  HAS_CLIPBOARD=true
  info "termux-clipboard-set: доступен"
else
  HAS_CLIPBOARD=false
  warn "termux-clipboard-set не найден (установите: pkg install termux-api)"
fi

# ---- 2. Подготовка ----
header "Подготовка"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

info "Создаю временную директорию: $TEMP_DIR"

# Проверка curl
if ! command -v curl &>/dev/null; then
  info "Устанавливаю curl..."
  pkg install -y curl 2>/dev/null || error "Не удалось установить curl"
fi

download_file() {
  local url="$1" dest="$2"
  local tmp_dest="${dest}.tmp"
  curl -sSL --connect-timeout 15 -o "$tmp_dest" "$url" && mv "$tmp_dest" "$dest" && return 0
  return 1
}

# ---- 3. Загрузка geoip/geosite ----
header "Загрузка geoip/geosite (runetfreedom release)"

mkdir -p "$TEMP_DIR/assets"

info "Загрузка geoip.dat..."
if download_file "$RULES_RELEASE_URL/geoip.dat" "$TEMP_DIR/assets/geoip.dat"; then
  info "  geoip.dat: $(ls -lh "$TEMP_DIR/assets/geoip.dat" | awk '{print $5}')"
else
  warn "Не удалось загрузить geoip.dat"
fi

info "Загрузка geosite.dat..."
if download_file "$RULES_RELEASE_URL/geosite.dat" "$TEMP_DIR/assets/geosite.dat"; then
  info "  geosite.dat: $(ls -lh "$TEMP_DIR/assets/geosite.dat" | awk '{print $5}')"
else
  warn "Не удалось загрузить geosite.dat"
fi

# Валидация
for f in geoip.dat geosite.dat; do
  if [ ! -f "$TEMP_DIR/assets/$f" ] || [ ! -s "$TEMP_DIR/assets/$f" ]; then
    warn "  $f: пуст или отсутствует"
    rm -f "$TEMP_DIR/assets/$f"
  fi
done

# ---- 4. Загрузка правил роутинга для v2rayNG ----
header "Загрузка правил роутинга"

for rule_file in v2rayng-routing-russia.json v2rayng-only-blocked.json; do
  url="$REPO/raw/$BRANCH/config/$rule_file"
  info "Загрузка $rule_file..."
  if download_file "$url" "$TEMP_DIR/assets/$rule_file"; then
    info "  $rule_file: загружен"
  else
    warn "  $rule_file: не удалось загрузить"
  fi
done

# ---- 5. Копирование на sdcard + буфер обмена ----
header "Установка файлов"

mkdir -p "$V2RAYNG_ASSETS"

FILES_COPIED=0
for f in "$TEMP_DIR/assets"/*; do
  name=$(basename "$f")
  echo -n "  $name ... "
  if cp "$f" "$V2RAYNG_ASSETS/$name" 2>/dev/null; then
    echo "OK"
    FILES_COPIED=$((FILES_COPIED + 1))
  else
    echo "ОШИБКА"
  fi
done

# Копирование JSON правил в буфер обмена для clipboard-импорта
if [ "$HAS_CLIPBOARD" = true ]; then
  header "Буфер обмена"

  echo ""
  echo "  Выберите пресет для копирования в буфер обмена:"
  echo "    1) v2rayng-routing-russia.json  (всё через прокси — весь трафик)"
  echo "    2) v2rayng-only-blocked.json    (только заблокированное)"
  echo ""
  read -r -t 15 -p "  Ваш выбор [1/2]: " choice
  echo ""

  case "${choice:-1}" in
    2|"only-blocked")
      RULES_FILE="$TEMP_DIR/assets/v2rayng-only-blocked.json"
      RULES_NAME="v2rayng-only-blocked.json"
      ;;
    *)
      RULES_FILE="$TEMP_DIR/assets/v2rayng-routing-russia.json"
      RULES_NAME="v2rayng-routing-russia.json"
      ;;
  esac

  if [ -f "$RULES_FILE" ]; then
    termux-clipboard-set < "$RULES_FILE" && \
      info "Правила ($RULES_NAME) скопированы в буфер обмена!" && \
      CLIPBOARD_OK=true
  fi
fi

if [ "$FILES_COPIED" -gt 0 ]; then
  info "Скопировано $FILES_COPIED файлов в $V2RAYNG_ASSETS"
else
  warn "Не удалось скопировать файлы. Проверьте разрешения."
fi

# ---- 6. Вывод инструкции ----
header "Настройка v2rayNG завершена"

echo ""
echo "  Файлы скопированы в:"
echo "    ${V2RAYNG_ASSETS}/"
echo ""
echo "  Файлы:"
for f in "$TEMP_DIR/assets"/*; do
  echo "    · $(basename "$f")"
done

echo ""
echo "━━━ Пошаговая инструкция для v2rayNG ━━━"
echo ""

echo "  ШАГ 1 — Импорт правил роутинга:"
echo ""
echo "  Метод A (рекомендуемый) — из буфера обмена:"
echo "    Откройте v2rayNG → ⋮ (меню слева) → Маршрутизация"
echo "    → ⋮ (три точки сверху) → Импорт правил из буфера обмена"
echo "    → Нажмите OK для подтверждения"
if [ "${CLIPBOARD_OK:-false}" = true ]; then
  echo "    ✅ Правила уже в буфере обмена!"
else
  echo "    ⚠️  Скопируйте JSON вручную или используйте Метод B"
fi
echo ""
echo "  Метод B — из файла:"
echo "    Откройте v2rayNG → ⋮ (меню слева) → Маршрутизация"
echo "    → ⋮ (три точки сверху) → Импорт правил из файла"
echo "    → Выберите один из файлов в assets/"
echo ""

echo "  ШАГ 2 — Смените доменную стратегию:"
echo "    Маршрутизация → поле «Доменная стратегия» → выберите"
echo ""
echo "    ▸ IPOnDemand (РЕКОМЕНДУЕТСЯ) — запрашивать DNS только"
echo "      для доменов, которые реально используются"
echo "    ▸ IPIfNonMatch — только если IPOnDemand не работает"
echo "    ▸ AsIs — отключает geoip, не используйте с geoip:ru"
echo ""

echo "  ШАГ 3 — Добавьте подписку с серверами:"
echo "    v2rayNG → ➕ (плюс) → Import from URL"
echo "    Вставьте URL своей подписки"
echo ""
echo "    Бесплатные подписки (один из вариантов):"
echo "    · igareck BLACK (весь трафик через прокси):"
echo "      https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt"
echo "    · igareck WHITE (только РФ через прокси):"
echo "      https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt"
echo "    · zieng2/wl:"
echo "      https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt"
echo ""

echo "  ШАГ 4 — Включите отпечаток SHA256 сертификата:"
echo "    Долгое нажатие на подписку → ✏️ (карандаш)"
echo "    → Отпечаток сертификата → Включить"
echo ""

echo "  ШАГ 5 — Обновите подписку и подключитесь:"
echo "    Нажмите значок облака ☁️ или ⋮ → Обновить все подписки"
echo "    Выберите сервер → нажмите V (вибро)"
echo "    Должен загореться зелёный индикатор VPN"
echo ""

echo "  ШАГ 6 — Проверка:"
echo "    Откройте в браузере:"
echo "    - https://2ip.ru — должен показать IP вашего VPN-сервера"
echo "    - https://www.google.com — должен открываться"
echo ""

if [ "$FILES_COPIED" -eq 0 ]; then
  warn "Файлы не скопированы. Выполните шаги вручную:"
  echo "  1. Скачайте файлы в браузере телефона:"
  echo "     $REPO/tree/main/config/"
  echo "  2. Переместите в: $V2RAYNG_ASSETS"
fi

echo ""
echo -e "${GREEN}✅ Готово!${NC}"
echo -e "   Версия скрипта: $SCRIPT_VERSION"
echo -e "   Основано на формате v2rayNG Discussion #4761"
