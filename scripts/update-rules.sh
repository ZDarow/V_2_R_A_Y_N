#!/bin/bash
set -euo pipefail

# v2rayN Russia Rules Updater — обновление geoip/geosite из runetfreedom/russia-v2ray-rules-dat

cleanup() {
  local ec=$?
  [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
  exit $ec
}
trap cleanup EXIT

V2RAYN_BIN_DIR="${V2RAYN_BIN_DIR:-$HOME/.local/share/v2rayN/bin}"

echo "[v2rayN Russia Rules Updater]"
echo "Обновление правил geoip/geosite..."

if [ ! -d "$V2RAYN_BIN_DIR" ]; then
  echo "Ошибка: директория $V2RAYN_BIN_DIR не найдена."
  echo "Убедитесь, что v2rayN установлен."
  exit 1
fi

TMP_DIR=$(mktemp -d)
echo "Клонирование runetfreedom/russia-v2ray-rules-dat..."
if ! git clone --depth=1 https://github.com/runetfreedom/russia-v2ray-rules-dat.git "$TMP_DIR/rules" 2>/dev/null; then
  echo "Ошибка: не удалось клонировать репозиторий. Проверьте подключение к интернету."
  exit 1
fi

# Бэкап текущих правил
BACKUP_DIR="$V2RAYN_BIN_DIR/backup-rules-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "$V2RAYN_BIN_DIR/geoip.dat" "$BACKUP_DIR/" 2>/dev/null || true
cp -f "$V2RAYN_BIN_DIR/geosite.dat" "$BACKUP_DIR/" 2>/dev/null || true

# Копирование новых правил
cp -f "$TMP_DIR/rules/geoip.dat" "$V2RAYN_BIN_DIR/geoip.dat"
cp -f "$TMP_DIR/rules/geosite.dat" "$V2RAYN_BIN_DIR/geosite.dat"

echo "✅ Правила обновлены."
echo "   geoip.dat:    $(ls -lh "$V2RAYN_BIN_DIR/geoip.dat" | awk '{print $5}')"
echo "   geosite.dat:  $(ls -lh "$V2RAYN_BIN_DIR/geosite.dat" | awk '{print $5}')"
echo "   Бэкап:        $BACKUP_DIR"
echo ""
echo "Перезапустите v2rayN для применения изменений."
