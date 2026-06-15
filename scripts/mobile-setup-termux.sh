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

SCRIPT_VERSION="1.2.0"
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
  local max_retries="${3:-3}"
  local delay="${4:-2}"
  local attempt=0

  while [ "$attempt" -lt "$max_retries" ]; do
    attempt=$((attempt + 1))
    if curl -sSL --connect-timeout 20 -o "$tmp_dest" "$url" 2>/dev/null; then
      mv "$tmp_dest" "$dest"
      return 0
    fi
    rm -f "$tmp_dest"
    if [ "$attempt" -lt "$max_retries" ]; then
      echo "    Попытка $attempt/$max_retries не удалась. Повтор через ${delay}с..."
      sleep "$delay"
      delay=$((delay * 2))
    fi
  done
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
    # Offline fallback: пробуем скопировать существующий файл из assets
    if [ -f "$V2RAYNG_ASSETS/$f" ] && [ -s "$V2RAYNG_ASSETS/$f" ]; then
      cp -f "$V2RAYNG_ASSETS/$f" "$TEMP_DIR/assets/$f"
      info "  $f: восстановлен из существующего файла в assets/"
    fi
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
    # Offline fallback
    if [ -f "$V2RAYNG_ASSETS/$rule_file" ] && [ -s "$V2RAYNG_ASSETS/$rule_file" ]; then
      cp -f "$V2RAYNG_ASSETS/$rule_file" "$TEMP_DIR/assets/$rule_file"
      info "  $rule_file: восстановлен из assets/"
    fi
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

# ---- 6. Буфер обмена + авто-открытие v2rayNG ----
if [ "$HAS_CLIPBOARD" = true ]; then
  header "Буфер обмена + авто-импорт"

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
      PRESET_LABEL="Только заблокированное"
      ;;
    *)
      RULES_FILE="$TEMP_DIR/assets/v2rayng-routing-russia.json"
      RULES_NAME="v2rayng-routing-russia.json"
      PRESET_LABEL="Всё через прокси"
      ;;
  esac

  if [ -f "$RULES_FILE" ]; then
    # Копируем в буфер обмена
    CLIPBOARD_JSON=$(cat "$RULES_FILE")
    termux-clipboard-set "$CLIPBOARD_JSON" && \
      info "Правила ($RULES_NAME) скопированы в буфер обмена!" && \
      CLIPBOARD_OK=true

    # Авто-открытие v2rayNG
    if command -v am &>/dev/null && [ "${INSTALL_V2RAYNG:-false}" = true ]; then
      echo ""
      echo -n "  Открываю v2rayNG ... "
      if am start -n "${V2RAYNG_PKG:-com.v2ray.ang.fdroid}/.ui.MainActivity" 2>/dev/null; then
        echo "OK"
        APP_OPENED=true
        sleep 1
      else
        echo "попытка com.v2ray.ang..."
        if am start -n "com.v2ray.ang/.ui.MainActivity" 2>/dev/null; then
          echo "OK"
          APP_OPENED=true
          sleep 1
        else
          echo "ОШИБКА"
          warn "Не удалось открыть v2rayNG. Откройте вручную."
          APP_OPENED=false
        fi
      fi
    fi
  fi
fi

if [ "$FILES_COPIED" -gt 0 ]; then
  info "Скопировано $FILES_COPIED файлов в $V2RAYNG_ASSETS"
else
  warn "Не удалось скопировать файлы. Проверьте разрешения."
fi

# ---- 7. Deep link для подписки (по выбранному пресету) ----
header "Deep link для подписки"
echo "  v2rayNG поддерживает однокликовый импорт подписки:"
echo ""

case "${choice:-1}" in
  2|"only-blocked")
    SUB_LABEL="igareck WHITE (только РФ через прокси)"
    SUB_URL="https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt"
    ;;
  *)
    SUB_LABEL="igareck BLACK (весь трафик через прокси)"
    SUB_URL="https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt"
    ;;
esac

echo "  Рекомендуемая подписка: $SUB_LABEL"
echo ""
echo "  Нажмите на ссылку в браузере телефона:"
echo "    v2rayng://install-sub/$(echo -n "$SUB_URL" | python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))" 2>/dev/null || echo "$SUB_URL")"
echo ""
echo "  Или скопируйте URL:"
echo "    $SUB_URL"

# ---- 8. Финальная инструкция — 2 тапа! ----
header "Осталось 2 тапа в v2rayNG"

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║  ПРАВИЛА УЖЕ В БУФЕРЕ ОБМЕНА!                ║"
if [ "${APP_OPENED:-false}" = true ]; then
echo "  ║  v2rayNG УЖЕ ОТКРЫТ!                          ║"
fi
echo "  ║                                              ║"
echo "  ║  1. Нажмите ≡ → Маршрутизация                ║"
echo "  ║  2. Нажмите ⋮ → Импорт из буфера обмена     ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

echo "  ─── После импорта ───"
echo ""
echo "  • Доменная стратегия: Маршрутизация →"
echo "    поле «Доменная стратегия» → IPOnDemand"
echo ""
echo "  • Подписка: ➕ → Import from URL → вставьте URL"
echo "    (см. deep link выше)"
echo ""
echo "  • Отпечаток SHA256: долгое нажатие на подписку →"
echo "    ✏️ (карандаш) → Отпечаток сертификата → Вкл."
echo ""
echo "  • Подключение: ☁️ (обновить) → выбрать сервер → V"
echo ""

echo ""
echo -e "${GREEN}✅ Готово!${NC}"
echo -e "   Версия скрипта: $SCRIPT_VERSION"
echo -e "   Применение правил: 2 тапа в v2rayNG"
echo -e "   Основано на формате v2rayNG Discussion #4761"

if [ "$FILES_COPIED" -eq 0 ]; then
  warn "Файлы не скопированы. Выполните шаги вручную:"
  echo "  1. Скачайте файлы в браузере телефона:"
  echo "     $REPO/tree/main/config/"
  echo "  2. Переместите в: $V2RAYNG_ASSETS"
fi
