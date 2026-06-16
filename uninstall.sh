#!/bin/bash
set -euo pipefail

# v2rayN Russia Setup Uninstaller

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

show_help() {
  echo "v2rayN Russia Setup — Деинсталлятор"
  echo ""
  echo "Использование: $0 [--help] [--backup-dir <путь>]"
  echo ""
  echo "Флаги:"
  echo "  --help              Показать эту справку"
  echo "  --backup-dir <путь> Сохранить конфиги в указанную директорию вместо удаления"
  echo ""
  echo "Без флагов: удаление с подтверждением."
  exit 0
}

BACKUP_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help) show_help ;;
    --backup-dir) BACKUP_DIR="$2"; shift 2 ;;
    *) warn "Неизвестный флаг: $1 (используйте --help для списка)"; shift ;;
  esac
done

echo -e "${CYAN}━━━ v2rayN Russia Setup — Деинсталляция ━━━${NC}"
echo ""
echo "Будут удалены:"
echo "  - v2rayN (пакет + /opt/v2rayN/)"
echo "  - ~/.config/v2rayN/"
echo "  - ~/.local/share/v2rayN/"
echo "  - ~/.local/bin/v2rayn (symlink)"
echo "  - ~/.local/bin/v2rayn-update-rules (symlink)"
echo "  - systemd service v2rayn (будет отключён)"
echo "  - systemd timer v2rayn-rules-update (будет отключён)"
echo "  - XDG автозапуск v2rayn.desktop"
echo "  - Системный прокси (будет выключен)"
echo "  - .NET Runtime НЕ удаляется (общий компонент)"
if [ -n "$BACKUP_DIR" ]; then
  echo ""
  echo "  Конфиги будут сохранены в: $BACKUP_DIR"
fi
echo ""

read -r -t 30 -n 1 -p "Продолжить? [y/N] " confirm
echo
case "${confirm:-n}" in
  [yY]) ;;
  *) echo "Отменено."; exit 0 ;;
esac

# 0. Backup (если указан --backup-dir)
if [ -n "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
  for dir in "$HOME/.config/v2rayN" "$HOME/.local/share/v2rayN"; do
    if [ -d "$dir" ]; then
      cp -r "$dir" "$BACKUP_DIR/" 2>/dev/null || true
      info "Сохранено: $dir → $BACKUP_DIR/"
    fi
  done
fi

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

# 2. Удаление v2rayN (dpkg / dnf / pacman)
if command -v dpkg &>/dev/null; then
  if dpkg -l v2rayn &>/dev/null 2>&1; then
    info "Удаление пакета v2rayN (dpkg)..."
    sudo dpkg -r v2rayn 2>/dev/null || sudo apt-get remove -y -qq v2rayn 2>/dev/null || true
  fi
elif command -v dnf &>/dev/null; then
  if dnf list installed v2rayn &>/dev/null 2>&1; then
    info "Удаление пакета v2rayN (dnf)..."
    sudo dnf remove -y v2rayn 2>/dev/null || true
  fi
elif command -v pacman &>/dev/null; then
  if pacman -Q v2rayn &>/dev/null 2>&1; then
    info "Удаление пакета v2rayN (pacman)..."
    sudo pacman -Rs --noconfirm v2rayn 2>/dev/null || true
  fi
fi

# 3. Удаление /opt/v2rayN/ (остатки после dpkg)
if [ -d /opt/v2rayN ]; then
  info "Удаление /opt/v2rayN/..."
  sudo rm -rf /opt/v2rayN 2>/dev/null || true
fi

# 4. Отключение systemd service + timer
# v2rayn.service (сам v2rayN)
if systemctl --user is-enabled v2rayn.service &>/dev/null 2>&1; then
  info "Отключение systemd service v2rayn..."
  systemctl --user stop v2rayn.service 2>/dev/null || true
  systemctl --user disable v2rayn.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/v2rayn.service"
  systemctl --user daemon-reload 2>/dev/null || true
  info "Systemd service v2rayn удалён"
fi

# v2rayn-rules-update.timer (авто-обновление правил)
if systemctl --user list-timers v2rayn-rules-update.timer &>/dev/null 2>&1; then
  info "Отключение systemd timer v2rayn-rules-update..."
  systemctl --user stop v2rayn-rules-update.timer 2>/dev/null || true
  systemctl --user disable v2rayn-rules-update.timer 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/v2rayn-rules-update.service"
  rm -f "$HOME/.config/systemd/user/v2rayn-rules-update.timer"
  systemctl --user daemon-reload 2>/dev/null || true
  info "Systemd timer удалён"
fi

# 5. Удаление XDG autostart
if [ -f "$HOME/.config/autostart/v2rayn.desktop" ]; then
  rm -f "$HOME/.config/autostart/v2rayn.desktop"
  info "Автозапуск v2rayn.desktop удалён"
fi

# 7. Удаление symlink
for link in v2rayn v2rayn-update-rules; do
  if [ -L "$HOME/.local/bin/$link" ]; then
    rm -f "$HOME/.local/bin/$link"
    info "Symlink ~/.local/bin/$link удалён"
  fi
done

# 8. Удаление конфигов
for dir in "$HOME/.config/v2rayN" "$HOME/.local/share/v2rayN"; do
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    info "Удалено: $dir"
  fi
done

# 9. Удаление кэша
if [ -d "$HOME/.cache/v2rayN" ]; then
  rm -rf "$HOME/.cache/v2rayN"
  info "Кэш удалён: ~/.cache/v2rayN"
fi

# 10. Удаление shared библиотеки
for libpath in "$HOME/.local/share/v2rayN/lib/common.sh" "$HOME/.local/lib/v2rayN/common.sh"; do
  if [ -f "$libpath" ]; then
    rm -f "$libpath"
    info "Удалено: $libpath"
  fi
done

echo ""
echo -e "${GREEN}v2rayN и конфигурация удалены.${NC}"
echo -e "${YELLOW}Примечание: .NET Runtime не был удалён.${NC}"
echo -e "${YELLOW}Для удаления .NET: sudo apt-get remove dotnet-runtime-*${NC}"
