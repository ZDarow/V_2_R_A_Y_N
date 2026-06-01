#!/bin/bash
set -e
echo "[v2rayN Russia Rules Updater]"
echo "Обновление правил geoip/geosite из runetfreedom/russia-v2ray-rules-dat..."

TMP_DIR=$(mktemp -d)
git clone --depth=1 https://github.com/runetfreedom/russia-v2ray-rules-dat.git "$TMP_DIR/rules" 2>/dev/null

BACKUP_DIR="$HOME/.local/share/v2rayN/bin/backup-rules-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -f "$HOME/.local/share/v2rayN/bin/geoip.dat" "$BACKUP_DIR/" 2>/dev/null || true
cp -f "$HOME/.local/share/v2rayN/bin/geosite.dat" "$BACKUP_DIR/" 2>/dev/null || true

cp -f "$TMP_DIR/rules/geoip.dat" "$HOME/.local/share/v2rayN/bin/geoip.dat"
cp -f "$TMP_DIR/rules/geosite.dat" "$HOME/.local/share/v2rayN/bin/geosite.dat"

rm -rf "$TMP_DIR"

echo "✅ Правила обновлены."
echo "   geoip.dat:    $(ls -lh $HOME/.local/share/v2rayN/bin/geoip.dat | awk '{print $5}')"
echo "   geosite.dat:  $(ls -lh $HOME/.local/share/v2rayN/bin/geosite.dat | awk '{print $5}')"
echo "   Бэкап:        $BACKUP_DIR"
