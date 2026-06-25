#!/bin/bash
# Установка v2rayN Manager GUI
set -euo pipefail

GUI_DIR="$(cd "$(dirname "$0")" && pwd)"

# Иконка
sudo cp "$GUI_DIR/icons/v2rayn-manager.svg" /usr/share/icons/hicolor/scalable/apps/v2rayn-manager.svg 2>/dev/null || true
sudo gtk-update-icon-cache /usr/share/icons/hicolor/ 2>/dev/null || true

# Главный скрипт
# Главный скрипт (Python)
sudo cp "$GUI_DIR/main.py" /usr/local/bin/v2rayn-manager.py
sudo chmod +x /usr/local/bin/v2rayn-manager.py

# Обёртка (shell) — задаёт DISPLAY, если не установлен
sudo bash -c 'cat > /usr/local/bin/v2rayn-manager << '"'"'EOF'"'"'
#!/bin/bash
export DISPLAY="${DISPLAY:-:0}"
exec python3 /usr/local/bin/v2rayn-manager.py "$@"
EOF'
sudo chmod +x /usr/local/bin/v2rayn-manager

# Desktop entry
mkdir -p "$HOME/.local/share/applications"
cp "$GUI_DIR/v2rayn-manager.desktop" "$HOME/.local/share/applications/v2rayn-manager.desktop"
sed -i "s|Icon=v2rayn-manager|Icon=/usr/share/icons/hicolor/scalable/apps/v2rayn-manager.svg|" \
  "$HOME/.local/share/applications/v2rayn-manager.desktop"

echo "✓ v2rayN Manager GUI установлен"
echo "  Запуск: v2rayn-manager"
echo "  Или через меню приложений → v2rayN Manager"
