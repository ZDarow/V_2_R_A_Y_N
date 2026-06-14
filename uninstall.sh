#!/bin/bash
set -euo pipefail

# v2rayN Russia Setup Uninstaller

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo -e "${CYAN}━━━ v2rayN Russia Setup — Деинсталляция ━━━${NC}"
echo ""
echo "Будут удалены:"
echo "  - v2rayN (пакет + /opt/v2rayN/)"
echo "  - ~/.config/v2rayN/"
echo "  - ~/.local/share/v2rayN/"
echo "  - ~/.local/bin/v2rayn (symlink)"
echo "  - Системный прокси (будет выключен)"
echo "  - .NET Runtime НЕ удаляется (общий компонент)"
echo ""

read -rp "Продолжить? [y/N] " confirm
case "$confirm" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Отменено."; exit 0 ;;
esac

# 1. Отключение системного прокси
info "Отключение системного прокси..."
command -v gsettings &>/dev/null && {
  gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null || true
  info "Системный прокси выключен (GNOME)"
}
KWC=$(command -v kwriteconfig6 2>/dev/null || command -v kwriteconfig5 2>/dev/null || true)
if [ -n "$KWC" ]; then
  "$KWC" --file kioslaverc --group "Proxy Settings" --key ProxyType 0 2>/dev/null || true
  dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:"" 2>/dev/null || true
  info "Системный прокси выключен (KDE)"
fi

# 2. Удаление v2rayN
if command -v dpkg &>/dev/null; then
  if dpkg -l v2rayn &>/dev/null 2>&1; then
    info "Удаление пакета v2rayN..."
    sudo dpkg -r v2rayn 2>/dev/null || sudo apt-get remove -y -qq v2rayn 2>/dev/null || true
  fi
fi

# 3. Удаление /opt/v2rayN/ (остатки после dpkg)
if [ -d /opt/v2rayN ]; then
  info "Удаление /opt/v2rayN/..."
  sudo rm -rf /opt/v2rayN 2>/dev/null || true
fi

# 4. Удаление symlink
if [ -L "$HOME/.local/bin/v2rayn" ]; then
  rm -f "$HOME/.local/bin/v2rayn"
  info "Symlink ~/.local/bin/v2rayn удалён"
fi

# 5. Удаление конфигов
for dir in "$HOME/.config/v2rayN" "$HOME/.local/share/v2rayN"; do
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    info "Удалено: $dir"
  fi
done

echo ""
echo -e "${GREEN}v2rayN и конфигурация удалены.${NC}"
echo -e "${YELLOW}Примечание: .NET Runtime не был удалён.${NC}"
echo -e "${YELLOW}Для удаления .NET: sudo apt-get remove dotnet-runtime-*${NC}"
