#!/bin/bash
set -euo pipefail

# v2rayN Russia Rules Updater — обновление geoip/geosite из runetfreedom/russia-v2ray-rules-dat (ветка release)

RULES_RELEASE_URL="https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release"
V2RAYN_BIN_DIR="${V2RAYN_BIN_DIR:-$HOME/.local/share/v2rayN/bin}"

echo "[v2rayN Russia Rules Updater]"
echo "Обновление правил geoip/geosite..."

if [ ! -d "$V2RAYN_BIN_DIR" ]; then
  echo "Ошибка: директория $V2RAYN_BIN_DIR не найдена."
  echo "Убедитесь, что v2rayN установлен."
  exit 1
fi

# Функция загрузки с проверкой
download_file() {
  local url="$1"
  local dest="$2"
  local tmp_dest="${dest}.tmp"

  if command -v curl &>/dev/null; then
    curl -sSL --connect-timeout 20 -o "$tmp_dest" "$url" && mv "$tmp_dest" "$dest" && return 0
  fi
  if command -v wget &>/dev/null; then
    wget -q --timeout=20 -O "$tmp_dest" "$url" && mv "$tmp_dest" "$dest" && return 0
  fi
  return 1
}

# Каталог для загрузки
TMP_RULES=$(mktemp -d)
trap 'rm -rf "$TMP_RULES"' EXIT

# SHA256 верификация
verify_sha256() {
  local dat_file="$1"
  local sha_url="$2"
  local sha_file="${dat_file}.sha256"
  if download_file "$sha_url" "$sha_file"; then
    local expected
    expected=$(cut -d' ' -f1 < "$sha_file" 2>/dev/null || echo "")
    if [ -n "$expected" ]; then
      local actual
      actual=$(sha256sum "$dat_file" 2>/dev/null | cut -d' ' -f1 || echo "")
      rm -f "$sha_file"
      if [ "$expected" = "$actual" ]; then
        return 0
      fi
      echo "⚠️  SHA256 не совпадает (ожидается: $expected, получено: $actual)"
      return 1
    fi
  fi
  echo "⚠️  Нет SHA256 checksum для проверки (пропускаем)"
  return 0
}

# Загрузка geoip.dat
echo "Загрузка geoip.dat..."
if download_file "$RULES_RELEASE_URL/geoip.dat" "$TMP_RULES/geoip.dat" && verify_sha256 "$TMP_RULES/geoip.dat" "$RULES_RELEASE_URL/geoip.dat.sha256"; then
  echo "   geoip.dat:    $(ls -lh "$TMP_RULES/geoip.dat" | awk '{print $5}')"
else
  rm -f "$TMP_RULES/geoip.dat"
  echo "ОШИБКА: не удалось загрузить geoip.dat"
fi

# Загрузка geosite.dat
echo "Загрузка geosite.dat..."
if download_file "$RULES_RELEASE_URL/geosite.dat" "$TMP_RULES/geosite.dat" && verify_sha256 "$TMP_RULES/geosite.dat" "$RULES_RELEASE_URL/geosite.dat.sha256"; then
  echo "   geosite.dat:  $(ls -lh "$TMP_RULES/geosite.dat" | awk '{print $5}')"
else
  rm -f "$TMP_RULES/geosite.dat"
  echo "ОШИБКА: не удалось загрузить geosite.dat"
fi

# Валидация загруженных файлов
VALID=true
for f in geoip.dat geosite.dat; do
  if [ ! -f "$TMP_RULES/$f" ]; then
    echo "⚠️  $f: пропущен (не загружен)"
    VALID=false
  elif [ ! -s "$TMP_RULES/$f" ]; then
    echo "ОШИБКА: $f пуст"
    VALID=false
  fi
done

if [ "$VALID" = true ]; then
  # Бэкап старых правил (только если новые валидны)
  BACKUP_DIR="$V2RAYN_BIN_DIR/backup-rules-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUP_DIR"
  cp -f "$V2RAYN_BIN_DIR/geoip.dat" "$BACKUP_DIR/" 2>/dev/null || true
  cp -f "$V2RAYN_BIN_DIR/geosite.dat" "$BACKUP_DIR/" 2>/dev/null || true
  echo "   Бэкап:        $BACKUP_DIR"

  # Установка новых правил
  cp -f "$TMP_RULES/geoip.dat" "$V2RAYN_BIN_DIR/geoip.dat"
  cp -f "$TMP_RULES/geosite.dat" "$V2RAYN_BIN_DIR/geosite.dat"
  echo "✅ Правила обновлены."
else
  echo "⚠️ Ошибка загрузки. Текущие правила сохранены без изменений."
fi

echo ""
echo "Перезапустите v2rayN для применения изменений."
