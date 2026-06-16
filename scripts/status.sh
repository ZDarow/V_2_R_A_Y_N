#!/bin/bash
# status.sh — проверка состояния v2rayN и всех компонентов
# ============================================================================
# Использование:
#   ./scripts/status.sh
#
# Exit code:
#   0 — всё OK
#   1 — есть проблемы (WARNING)
#   2 — критические проблемы (ERROR)
# ============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
OK()   { echo -e "  ${GREEN}✔${NC} $1"; }
WARN() { echo -e "  ${YELLOW}⚠${NC} $1"; }
FAIL() { echo -e "  ${RED}✘${NC} $1"; }

EXIT_CODE=0
V2RAYN_HOME="${V2RAYN_HOME:-$HOME/.local/share/v2rayN}"
V2RAYN_CONFIG="${V2RAYN_CONFIG:-$HOME/.config/v2rayN}"
DB_PATH="$V2RAYN_HOME/guiConfigs/guiNDB.db"
BIN_DIR="$V2RAYN_HOME/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo -e "${CYAN}  v2rayN Status Check${NC}"
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
echo ""

# ---- 1. Процесс v2rayN ----
echo -e "${CYAN}━━━ Процесс v2rayN ━━━${NC}"
if systemctl --user is-active v2rayn.service &>/dev/null 2>&1; then
  OK "systemd: v2rayn.service активен"
elif pgrep -x v2rayn &>/dev/null; then
  OK "Процесс v2rayn запущен (без systemd)"
else
  WARN "v2rayN не запущен"
  [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
fi

# ---- 2. Прокси-порты ----
echo ""
echo -e "${CYAN}━━━ Прокси ━━━${NC}"
if command -v ss &>/dev/null; then
  SOCKS_OK=$(ss -tlnp 2>/dev/null | grep -c ":10808 " || true)
  HTTP_OK=$(ss -tlnp 2>/dev/null | grep -c ":10809 " || true)
elif command -v netstat &>/dev/null; then
  SOCKS_OK=$(netstat -tlnp 2>/dev/null | grep -c ":10808 " || true)
  HTTP_OK=$(netstat -tlnp 2>/dev/null | grep -c ":10809 " || true)
else
  SOCKS_OK=0; HTTP_OK=0
fi

[ "$SOCKS_OK" -gt 0 ] && OK "SOCKS5 :10808 — слушает" || { FAIL "SOCKS5 :10808 — НЕ слушает"; EXIT_CODE=2; }
[ "$HTTP_OK" -gt 0 ] && OK "HTTP :10809 — слушает" || { FAIL "HTTP :10809 — НЕ слушает"; EXIT_CODE=2; }

# Проверка через curl (если прокси активен)
if [ "$SOCKS_OK" -gt 0 ] && command -v curl &>/dev/null; then
  TEST_RESULT=$(curl -s --connect-timeout 3 -x socks5://127.0.0.1:10808 https://www.google.com -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
  if [ "$TEST_RESULT" = "200" ] || [ "$TEST_RESULT" = "301" ] || [ "$TEST_RESULT" = "302" ]; then
    OK "Прокси-тест: google.com через SOCKS5 — OK ($TEST_RESULT)"
  else
    WARN "Прокси-тест: google.com через SOCKS5 — ответ $TEST_RESULT (v2rayN не подключён к серверу?)"
    [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
  fi
fi

# ---- 3. GeoIP/Geosite ----
echo ""
echo -e "${CYAN}━━━ GeoIP / Geosite ━━━${NC}"
for f in geoip.dat geosite.dat; do
  FILE="$BIN_DIR/$f"
  if [ -f "$FILE" ] && [ -s "$FILE" ]; then
    AGE=$((($(date +%s) - $(stat -c %Y "$FILE")) / 86400))
    if [ "$AGE" -le 30 ]; then
      OK "$f: $(ls -lh "$FILE" | awk '{print $5}'), $AGE дней"
    else
      WARN "$f: $AGE дней (рекомендуется < 30). Запустите: v2rayn-update-rules"
      [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
    fi
  else
    FAIL "$f: отсутствует"
    EXIT_CODE=2
  fi
done

# ---- 4. Конфиги роутинга ----
echo ""
echo -e "${CYAN}━━━ Конфиги роутинга ━━━${NC}"
for f in routing-russia.json only_blocked.json v2rayng-routing-russia.json v2rayng-only-blocked.json; do
  FILE="$V2RAYN_CONFIG/$f"
  if [ -f "$FILE" ]; then
    python3 -m json.tool "$FILE" >/dev/null 2>&1 && OK "$f" || WARN "$f: невалидный JSON"
  else
    WARN "$f: отсутствует"
  fi
done

# ---- 5. Подписки в БД ----
echo ""
echo -e "${CYAN}━━━ Подписки ━━━${NC}"
if [ -f "$DB_PATH" ] && command -v sqlite3 &>/dev/null; then
  SUB_COUNT=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM SubItem;" 2>/dev/null || echo "0")
  if [ "$SUB_COUNT" -gt 0 ]; then
    OK "Подписок в БД: $SUB_COUNT"
    sqlite3 "$DB_PATH" "SELECT remarks, url FROM SubItem;" 2>/dev/null | while IFS='|' read -r name url; do
      echo "    - $name"
    done
  else
    WARN "Подписки не найдены в БД"
    [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
  fi

  # Проверка GlobalConfig (роутинг)
  ROUTING_FILE=$(sqlite3 "$DB_PATH" "SELECT value FROM GlobalConfig WHERE key='routingCustomFile';" 2>/dev/null || true)
  ROUTING_ENABLED=$(sqlite3 "$DB_PATH" "SELECT value FROM GlobalConfig WHERE key='routingCustomEnabled';" 2>/dev/null || true)
  if [ -n "$ROUTING_FILE" ] && [ "$ROUTING_ENABLED" = "true" ]; then
    OK "Роутинг: $ROUTING_FILE"
  fi
else
  WARN "БД guiNDB.db не найдена (v2rayN не запускался?)"
  [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
fi

# ---- 6. Systemd timer ----
echo ""
echo -e "${CYAN}━━━ Systemd timer ━━━${NC}"
if systemctl --user list-timers v2rayn-rules-update.timer &>/dev/null 2>&1; then
  TIMER_INFO=$(systemctl --user list-timers v2rayn-rules-update.timer --no-legend 2>/dev/null | head -1)
  OK "Timer: v2rayn-rules-update.timer"
  echo "    $TIMER_INFO"
else
  WARN "Timer v2rayn-rules-update.timer не установлен"
  [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1
fi

# ---- 7. Системный прокси ----
echo ""
echo -e "${CYAN}━━━ Системный прокси ━━━${NC}"
if command -v gsettings &>/dev/null; then
  PROXY_MODE=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "'none'")
  if [ "$PROXY_MODE" = "'manual'" ]; then
    OK "GNOME: системный прокси включён (manual)"
  else
    WARN "GNOME: системный прокси выключен ($PROXY_MODE)"
  fi
elif command -v kwriteconfig5 &>/dev/null || command -v kwriteconfig6 &>/dev/null; then
  OK "KDE: проверка прокси не поддерживается в cli"
fi

# ---- 8. Автозапуск ----
echo ""
echo -e "${CYAN}━━━ Автозапуск ━━━${NC}"
if [ -f "$HOME/.config/autostart/v2rayn.desktop" ]; then
  OK "XDG autostart: v2rayn.desktop"
else
  info "XDG autostart: не установлен"
fi

# ---- Итог ----
echo ""
echo -e "${CYAN}══════════════════════════════════════════════${NC}"
case "$EXIT_CODE" in
  0) echo -e "${GREEN}  Статус: ВСЁ OK${NC}" ;;
  1) echo -e "${YELLOW}  Статус: ЕСТЬ ПРЕДУПРЕЖДЕНИЯ${NC}" ;;
  2) echo -e "${RED}  Статус: КРИТИЧЕСКИЕ ПРОБЛЕМЫ${NC}" ;;
esac
echo -e "${CYAN}══════════════════════════════════════════════${NC}"

exit "$EXIT_CODE"
