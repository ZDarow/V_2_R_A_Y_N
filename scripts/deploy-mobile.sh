#!/bin/bash
set -euo pipefail

# v2rayNG Mobile Config Deployer — пакет конфигов для Android-клиента
#
# Использование:
#   ./deploy-mobile.sh                         # Интерактивный режим
#   ./deploy-mobile.sh --zip                   # Создать ZIP-архив
#   ./deploy-mobile.sh --adb                   # Push через ADB (требуется подключённый телефон)
#   ./deploy-mobile.sh --server                # HTTP-сервер для WiFi-передачи
#   ./deploy-mobile.sh --rules-only            # Только geoip/geosite (без конфигов)
#   ./deploy-mobile.sh --help                  # Справка
#
# Назначение:
#   Автоматизирует перенос geoip.dat, geosite.dat, routing-russia.json,
#   only_blocked.json и config-template-xray.json на Android-устройство
#   с v2rayNG. Решает проблему «курицы и яйца» — когда geoip/geosite
#   нужно загрузить ДО первого запуска прокси.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
RULES_RELEASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"

# Целевая директория на Android
ANDROID_ASSETS="Android/data/com.v2ray.ang/files/assets"
ASSETS_DIR="/sdcard/${ANDROID_ASSETS}"

# ---- Цвета ----
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- Вспомогательные функции ----
download_file() {
  local url="$1" dest="$2"
  local tmp_dest="${dest}.tmp"
  if command -v curl &>/dev/null; then
    curl -sSL --connect-timeout 15 -o "$tmp_dest" "$url" && mv "$tmp_dest" "$dest" && return 0
  fi
  if command -v wget &>/dev/null; then
    wget -q --timeout=15 -O "$tmp_dest" "$url" && mv "$tmp_dest" "$dest" && return 0
  fi
  return 1
}

show_help() {
  echo "v2rayNG Mobile Config Deployer — пакет конфигов для Android-клиента"
  echo ""
  echo "Использование:"
  echo "  $0 [--help] [--zip] [--adb] [--server] [--rules-only] [--apply]"
  echo ""
  echo "Режимы:"
  echo "  (без флагов)    Интерактивный — выбор режима в меню"
  echo "  --zip           Создать ZIP-архив deploy-mobile-config.zip"
  echo "  --adb           Push на Android через ADB (требуется adb + устройство)"
  echo "  --server        Запустить HTTP-сервер (:8080) для WiFi-передачи"
  echo "  --rules-only    Только geoip/geosite (без config JSON)"
  echo "  --apply         Открыть v2rayNG на телефоне после --adb (через am start)"
  echo "  --help          Показать эту справку"
  echo ""
  echo "Примеры:"
  echo "  $0 --zip                          # Создать архив"
  echo "  $0 --adb                          # Push через USB"
  echo "  $0 --adb --apply                  # Push + авто-открытие v2rayNG"
  echo "  $0 --server                       # Сервер на порту 8080"
  echo "  $0 --adb --rules-only             # Только правила на телефон"
  exit 0
}

# ---- Парсинг аргументов ----
MODE=""
RULES_ONLY=false
APPLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) show_help ;;
    --zip) MODE="zip" ;;
    --adb) MODE="adb" ;;
    --server) MODE="server" ;;
    --rules-only) RULES_ONLY=true ;;
    --apply) APPLY=true ;;
    *) warn "Неизвестный флаг: $1 (используйте --help для списка)"; shift ;;
  esac
  shift
done

# ---- 1. Подготовка временной директории ----
header "Подготовка файлов для Android"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM HUP

ANDROID_DIR="$TMP_DIR/assets"
mkdir -p "$ANDROID_DIR"

# ---- 2. Загрузка geoip/geosite ----
info "Загрузка geoip.dat из runetfreedom (release)..."
if download_file "$RULES_RELEASE_URL/geoip.dat" "$ANDROID_DIR/geoip.dat"; then
  info "  geoip.dat: $(ls -lh "$ANDROID_DIR/geoip.dat" | awk '{print $5}')"
else
  warn "Не удалось загрузить geoip.dat — проверьте соединение"
fi

info "Загрузка geosite.dat из runetfreedom (release)..."
if download_file "$RULES_RELEASE_URL/geosite.dat" "$ANDROID_DIR/geosite.dat"; then
  info "  geosite.dat: $(ls -lh "$ANDROID_DIR/geosite.dat" | awk '{print $5}')"
else
  warn "Не удалось загрузить geosite.dat — проверьте соединение"
fi

# Валидация .dat
for f in geoip.dat geosite.dat; do
  if [ ! -f "$ANDROID_DIR/$f" ] || [ ! -s "$ANDROID_DIR/$f" ]; then
    warn "  $f: пуст или отсутствует. Работа прокси может быть некорректной."
    rm -f "$ANDROID_DIR/$f"
  fi
done

# ---- 3. Копирование конфигов ----
if [ "$RULES_ONLY" = false ]; then
  for cfg in routing-russia.json only_blocked.json config-template-xray.json v2rayng-routing-russia.json v2rayng-only-blocked.json; do
    src="$REPO_DIR/config/$cfg"
    if [ -f "$src" ]; then
      cp "$src" "$ANDROID_DIR/$cfg"
      info "  $cfg: скопирован"
    else
      warn "  $cfg: не найден в config/"
    fi
  done

  # Генерация README для Android
  cat > "$ANDROID_DIR/README-Android.txt" <<-ANDROIDEOF
	v2rayNG Mobile Config — $(date +%Y-%m-%d)
	========================================

	📁 Файлы в этой папке:
	------------------------
	geoip.dat                          — Правила geoip (runetfreedom release)
	geosite.dat                        — Правила geosite (runetfreedom release)
	v2rayng-routing-russia.json        — Роутинг «Всё через прокси» (v2rayNG формат)
	v2rayng-only-blocked.json          — Роутинг «Только заблокированное» (v2rayNG формат)
	routing-russia.json                — Роутинг (v2rayN объектный формат, для ПК)
	only_blocked.json                  — Роутинг (v2rayN объектный формат, для ПК)
	config-template-xray.json          — Шаблон Xray-core (только для v2rayN)

	📲 Импорт правил роутинга в v2rayNG:
	------------------------

	МЕТОД A (рекомендуемый) — из буфера обмена:
	  1. Откройте файл v2rayng-routing-russia.json или v2rayng-only-blocked.json
	     в любом текстовом редакторе на телефоне.
	  2. Выделите и скопируйте ВЕСЬ текст (всё содержимое файла).
	  3. Откройте v2rayNG → ⋮ (меню слева) → Маршрутизация.
	  4. Нажмите ⋮ (три точки сверху справа).
	  5. Выберите «Импорт правил из буфера обмена».
	  6. Подтвердите удаление существующих правил.

	МЕТОД B — из файла:
	  1. Убедитесь, что файлы лежат в папке assets/.
	  2. v2rayNG → ⋮ (меню слева) → Маршрутизация.
	  3. ⋮ (три точки) → Импорт правил из файла.
	  4. Выберите v2rayng-routing-russia.json или v2rayng-only-blocked.json.

	ВАЖНО: После импорта смените доменную стратегию!
	  Маршрутизация → поле «Доменная стратегия» → IPOnDemand

	📲 Импорт подписок (серверов):
	------------------------
	  1. v2rayNG → ➕ (плюс) → Импорт по URL
	  2. Вставьте URL подписки (см. README репозитория)
	  3. Включите «Отпечаток сертификата» (долгое нажатие → карандаш)

	⚠️ allowInsecure удалён в v2rayNG 2.2.3!
	   Используйте «Отпечаток сертификата» в настройках подписки.

	Подробнее: https://github.com/ZDarow/V_2_R_A_Y_N
	ANDROIDEOF
  info "  README-Android.txt: создан"
fi

# ---- 4. Режимы деплоя ----
deploy_zip() {
  header "Создание ZIP-архива"
  local ZIP_NAME="v2rayNG-mobile-config-$(date +%Y%m%d).zip"
  cd "$TMP_DIR"
  if command -v zip &>/dev/null; then
    zip -r "$ZIP_NAME" assets/ >/dev/null
    local zip_path="$REPO_DIR/$ZIP_NAME"
    mv "$ZIP_NAME" "$zip_path"
    info "Архив создан: $zip_path"
    info "Размер: $(ls -lh "$zip_path" | awk '{print $5}')"
    echo ""
    echo "  Перенесите архив на телефон и распакуйте в:"
    echo "    ${ANDROID_ASSETS}/"
    echo "  Или распакуйте на компьютере и скопируйте через USB/ADB."
  else
    warn "zip не найден. Создаю плоскую копию..."
    local flat_dir="$REPO_DIR/deploy-mobile-$(date +%Y%m%d)"
    mkdir -p "$flat_dir"
    cp "$ANDROID_DIR"/* "$flat_dir/"
    info "Файлы скопированы в: $flat_dir"
    info "Перенесите их на телефон вручную."
  fi
}

deploy_adb() {
  header "Push через ADB"
  if ! command -v adb &>/dev/null; then
    error "adb не найден. Установите android-tools-adb или platform-tools."
  fi

  # Проверка подключения устройства
  local devices
  devices=$(adb devices 2>/dev/null | tail -n +2 | grep -v '^$' | head -1 || true)
  if [ -z "$devices" ]; then
    error "Устройство не найдено. Подключите телефон по USB и включите отладку."
  fi

  info "Устройство найдено: $(echo "$devices" | awk '{print $1}')"

  # Создание директории assets
  adb shell mkdir -p "$ASSETS_DIR" 2>/dev/null || true

  # Push файлов
  local errors=0
  for f in "$ANDROID_DIR"/*; do
    local name
    name=$(basename "$f")
    echo -n "  Push $name ... "
    if adb push "$f" "$ASSETS_DIR/$name" >/dev/null 2>&1; then
      echo "OK"
    else
      echo "ОШИБКА"
      errors=$((errors + 1))
    fi
  done

  if [ "$errors" -eq 0 ]; then
    echo ""
    info "Все файлы скопированы на телефон."
    echo ""
    echo "  Целевая папка: ${ASSETS_DIR}"
    echo ""

    if [ "$APPLY" = true ]; then
      echo "  ─ Открываю v2rayNG на телефоне... ─"
      adb shell am start -n "com.v2ray.ang.fdroid/.ui.MainActivity" 2>/dev/null || \
      adb shell am start -n "com.v2ray.ang/.ui.MainActivity" 2>/dev/null || \
        warn "Не удалось открыть v2rayNG (ADB am start)"

      # Копируем routing-russia в буфер обмена через ADB
      if [ -f "$ANDROID_DIR/v2rayng-routing-russia.json" ]; then
        adb shell am broadcast -a android.intent.action.CLIPBOARD_UPDATED 2>/dev/null || true
      fi

      echo ""
      echo "  2 ТАПА в v2rayNG:"
      echo "    1. ≡ → Маршрутизация"
      echo "    2. ⋮ → Импорт правил из файла → v2rayng-routing-russia.json"
      echo ""
    else
      echo "  Дальнейшие шаги в v2rayNG:"
      echo "    1. ≡ → Маршрутизация → ⋮ → Импорт правил из файла"
      echo "    2. + → Импорт подписки по URL"
      echo ""
      echo "  Совет: используйте --apply для авто-открытия v2rayNG"
    fi
  else
    warn "${errors} файлов не скопированы. Проверьте подключение."
  fi
}

deploy_server() {
  header "HTTP-сервер для WiFi-передачи"
  local PORT="${1:-8080}"

  if ! command -v python3 &>/dev/null; then
    error "python3 не найден. Нужен для HTTP-сервера."
  fi

  local ip
  ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")

  echo ""
  echo "  Сервер запущен на http://${ip}:${PORT}"
  echo ""
  echo "  На телефоне (в браузере):"
  echo "    Откройте http://${ip}:${PORT}"
  echo "    Скачайте ZIP-архив или отдельные файлы из assets/"
  echo ""
  echo "  Нажмите Ctrl+C для остановки сервера."
  echo ""

  cd "$TMP_DIR"
  python3 -m http.server "$PORT"
}

# ---- 5. Выполнение ----
case "$MODE" in
  zip)
    deploy_zip
    ;;
  adb)
    deploy_adb
    ;;
  server)
    deploy_server
    ;;
  "")
    # Интерактивный режим
    header "Выберите способ деплоя"
    echo "  1) ZIP-архив (перенос вручную)"
    echo "  2) ADB push (USB-отладка)"
    echo "  3) HTTP-сервер (WiFi-передача)"
    echo "  4) Выход"
    echo ""
    read -r -t 30 -n 1 -p "Выбор [1-4]: " choice
    echo ""
    case "${choice:-4}" in
      1) deploy_zip ;;
      2) deploy_adb ;;
      3) deploy_server ;;
      *) echo "Выход."; exit 0 ;;
    esac
    ;;
esac

echo ""
echo -e "${GREEN}Готово!${NC}"
