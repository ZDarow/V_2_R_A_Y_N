#!/bin/bash
# diagnose.sh — сбор диагностической информации
# shellcheck disable=SC2009,SC2012,SC2034
# SC2009: ps aux | grep — стандартный паттерн диагностики
# SC2012: ls -lh fallback совместимости с macOS
# SC2034: цвета используются в info/warn/header
# ============================================================================
# Выводит всю информацию для отладки/issues в одном месте.
# Использование:
#   ./scripts/diagnose.sh
#   ./scripts/diagnose.sh > diagnose.txt  # для отправки
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

V2RAYN_HOME="$HOME/.local/share/v2rayN"
V2RAYN_CONFIG="$HOME/.config/v2rayN"
DB_PATH="$V2RAYN_HOME/guiConfigs/guiNDB.db"

echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  v2rayN Russia Setup — Диагностика               ║${NC}"
echo -e "${CYAN}║  $(date '+%Y-%m-%d %H:%M:%S %Z')                    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"

# ---- 1. Система ----
header "Система"
echo "  ОС:     $(uname -a 2>/dev/null)"
  echo "  Дистр:  $(lsb_release -ds 2>/dev/null || < /etc/os-release head -1 || echo 'N/A')"
echo "  Ядро:   $(uname -r)"
echo "  Архит:  $(uname -m)"
echo "  Память: $(free -h | awk '/^Mem:/{print $3"/"$2}')"
echo "  Диск:   $(df -h / | awk 'NR==2{print $3"/"$2}')"

# ---- 2. .NET ----
header ".NET Runtime"
if command -v dotnet &>/dev/null; then
  echo "  Версия: $(dotnet --version 2>/dev/null || echo 'N/A')"
  echo "  Путь:   $(which dotnet)"
else
  warn ".NET не установлен"
fi

# ---- 3. v2rayN ----
header "v2rayN"
echo "  Бинарь: $(which v2rayn 2>/dev/null || echo 'не найден')"
echo "  Домашн: $V2RAYN_HOME"
echo "  Конфиг: $V2RAYN_CONFIG"

if pgrep -x v2rayn &>/dev/null; then
  info "Процесс: запущен"
  ps aux | grep -E "[v]2rayn" | awk '{print "   PID: " $2 ", CPU: " $3 "%, MEM: " $4 "%, Запущен: " $9}'
else
  warn "Процесс: не запущен"
fi

# ---- 4. guiNDB.db ----
header "БД guiNDB.db"
if [ -f "$DB_PATH" ] && command -v sqlite3 &>/dev/null; then
  echo "  Размер: $(stat -c%s "$DB_PATH" 2>/dev/null | numfmt --to=iec 2>/dev/null || ls -lh "$DB_PATH" | awk '{print $5}')"
  echo "  Таблицы:"
  sqlite3 "$DB_PATH" ".tables" 2>/dev/null | tr ' ' '\n' | sed 's/^/    - /'
  echo "  GlobalConfig:"
  sqlite3 "$DB_PATH" "SELECT key, value FROM GlobalConfig;" 2>/dev/null | while IFS='|' read -r k v; do
    echo "    $k = $v"
  done
  echo "  Подписки:"
  sqlite3 "$DB_PATH" "SELECT remarks, url FROM SubItem;" 2>/dev/null | while IFS='|' read -r name url; do
    echo "    $name"
    echo "      $url"
  done
else
  warn "БД не найдена или sqlite3 не установлен"
fi

# ---- 5. Файлы ----
header "Файлы конфигов"
for f in routing-russia.json only_blocked.json v2rayng-routing-russia.json "v2rayng-only-blocked.json" config-template-xray.json; do
  FILE="$V2RAYN_CONFIG/$f"
  if [ -f "$FILE" ]; then
    VALID=$(python3 -c "import json; json.load(open('$FILE')); print('OK')" 2>/dev/null || echo "ERROR")
    echo "  $f: $(stat -c%s "$FILE" 2>/dev/null | numfmt --to=iec 2>/dev/null || ls -lh "$FILE" | awk '{print $5}') — JSON: $VALID"
  else
    warn "  $f: отсутствует"
  fi
done

header "GeoIP / Geosite"
for f in geoip.dat geosite.dat; do
  FILE="$V2RAYN_HOME/bin/$f"
  if [ -f "$FILE" ]; then
    AGE=$((($(date +%s) - $(stat -c %Y "$FILE" 2>/dev/null || echo "0")) / 86400))
    echo "  $f: $(stat -c%s "$FILE" 2>/dev/null | numfmt --to=iec 2>/dev/null || ls -lh "$FILE" | awk '{print $5}'), $AGE дней"
  else
    warn "  $f: отсутствует"
  fi
done

# ---- 6. Systemd ----
header "Systemd"
for unit in v2rayn.service v2rayn-rules-update.service v2rayn-rules-update.timer; do
  if systemctl --user list-units --all "$unit" &>/dev/null 2>&1; then
    STATUS=$(systemctl --user is-active "$unit" 2>/dev/null || echo 'inactive')
    ENABLED=$(systemctl --user is-enabled "$unit" 2>/dev/null || echo 'disabled')
    echo "  $unit: $STATUS / $ENABLED"
  else
    warn "  $unit: не найден"
  fi
done

# ---- 7. Прокси ----
header "Прокси"
echo "  SOCKS5 :10808: $(ss -tlnp 2>/dev/null | grep -q ':10808 ' && echo 'слушает' || echo 'НЕ слушает')"
echo "  HTTP   :10809: $(ss -tlnp 2>/dev/null | grep -q ':10809 ' && echo 'слушает' || echo 'НЕ слушает')"

# ---- 8. Логи ----
header "Логи (последние 30 строк)"
LOG_DIR="$V2RAYN_HOME/logs"
if [ -d "$LOG_DIR" ]; then
  for log in "$LOG_DIR"/*.log; do
    if [ -f "$log" ]; then
      echo "  --- $(basename "$log") ---"
      tail -30 "$log" 2>/dev/null | sed 's/^/  /'
      echo ""
    fi
  done
else
  warn "Директория логов не найдена"
fi

header "Journalctl (последние 20 строк)"
journalctl --user -u v2rayn.service --since "1 hour ago" --no-pager -n 20 2>/dev/null | sed 's/^/  /' || warn "journalctl недоступен"

# ---- 9. Сеть ----
header "Сеть"
echo "  DNS:"
resolvectl status 2>/dev/null | grep -E "DNS Server|Current DNS" | sed 's/^/    /' || echo "    resolvectl недоступен"
echo ""
echo "  Доступность хостов:"
for host in "github.com" "raw.githubusercontent.com" "google.com"; do
  PING_RESULT=$(ping -c 1 -W 2 "$host" 2>/dev/null | grep -oP '\d+(?=%)' || echo "таймаут")
  echo "    $host: ${PING_RESULT}ms"
done

# ---- 10. Установленные скрипты ----
header "Скрипты"
for s in "$SCRIPT_DIR"/*.sh; do
  NAME=$(basename "$s")
  SIZE=$(stat -c%s "$s" 2>/dev/null | numfmt --to=iec 2>/dev/null || ls -lh "$s" | awk '{print $5}')
  echo "  $NAME ($SIZE)"
done

echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo "  Диагностика завершена. Для отправки в issue:"
echo "  ./scripts/diagnose.sh > diagnose.txt"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
