#!/bin/bash
# v2ray-health.sh — health check v2rayN/Xray с выводом в journald
# ============================================================================
# Использование:
#   ./scripts/v2ray-health.sh              # журнал + exit код
#   ./scripts/v2ray-health.sh --json       # только JSON в stdout
#   ./scripts/v2ray-health.sh --check      # exit код, без вывода
#   ./scripts/v2ray-health.sh --install    # установка systemd таймера
#   ./scripts/v2ray-health.sh --remove     # удаление systemd таймера
#
# Exit code:
#   0 — healthy
#   1 — degraded (warnings)
#   2 — critical
# ============================================================================

set -euo pipefail

MODE="${1:-full}"
V2RAYN_HOME="${V2RAYN_HOME:-$HOME/.local/share/v2rayN}"
V2RAYN_CONFIG="${V2RAYN_CONFIG:-$HOME/.config/v2rayN}"
BIN_DIR="$V2RAYN_HOME/bin"
DB_PATH="$V2RAYN_HOME/guiConfigs/guiNDB.db"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR}/../lib/systemd"

# ---- JSON output helpers ----
JSON_OUTPUT=""
JSON_FIRST=true
json_start()   { JSON_OUTPUT="{"; }
json_end()     { JSON_OUTPUT+="}"; }
json_key()     { [ "$JSON_FIRST" = true ] && JSON_FIRST=false || JSON_OUTPUT+=","; JSON_OUTPUT+="\"$1\":"; }
json_bool()    { json_key "$1"; JSON_OUTPUT+="$2"; }
json_string()  { json_key "$1"; JSON_OUTPUT+="\"$2\""; }
json_int()     { json_key "$1"; JSON_OUTPUT+="$2"; }
json_obj_start()  { json_key "$1"; JSON_OUTPUT+="{"; JSON_FIRST=true; }
json_obj_end()    { JSON_OUTPUT+="}"; JSON_FIRST=false; }
json_arr_start()  { json_key "$1"; JSON_OUTPUT+="["; JSON_FIRST=true; }
json_arr_end()    { JSON_OUTPUT+="]"; JSON_FIRST=false; }
json_arr_item()   { [ "$JSON_FIRST" = true ] && JSON_FIRST=false || JSON_OUTPUT+=","; }

# ---- journald logging ----
journal_emerg()   { logger -p user.emerg   -t "v2ray-health[$$]" "$1"; }
journal_alert()   { logger -p user.alert   -t "v2ray-health[$$]" "$1"; }
journal_crit()    { logger -p user.crit    -t "v2ray-health[$$]" "$1"; }
journal_error()   { logger -p user.err     -t "v2ray-health[$$]" "$1"; }
journal_warn()    { logger -p user.warning -t "v2ray-health[$$]" "$1"; }
journal_notice()  { logger -p user.notice  -t "v2ray-health[$$]" "$1"; }
journal_info()    { logger -p user.info    -t "v2ray-health[$$]" "$1"; }
journal_debug()   { logger -p user.debug   -t "v2ray-health[$$]" "$1"; }

# ---- health state ----
EXIT_CODE=0
declare -a CHECKS=()

record_check() {
  local status="$1" name="$2" message="$3"
  CHECKS+=("$(printf '{"status":"%s","name":"%s","message":"%s"}' "$status" "$name" "$message")")
  case "$status" in
    critical) EXIT_CODE=2; journal_crit "[$name] $message" ;;
    degraded) [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1; journal_warn "[$name] $message" ;;
    ok)       journal_info "[$name] $message" ;;
  esac
}

# ====================================================================
# 1. Process check
# ====================================================================
check_process() {
  if systemctl --user is-active v2rayn.service &>/dev/null 2>&1; then
    record_check ok "process" "v2rayn.service активен (systemd)"
  elif pgrep -x v2rayn &>/dev/null; then
    record_check ok "process" "v2rayN запущен (без systemd)"
  else
    record_check degraded "process" "v2rayN не запущен"
  fi
}

# ====================================================================
# 2. Proxy ports
# ====================================================================
check_ports() {
  local socks_ok=0 http_ok=0

  if command -v ss &>/dev/null; then
    socks_ok=$(ss -tlnp 2>/dev/null | grep -c ":10808 " || true)
    http_ok=$(ss -tlnp 2>/dev/null | grep -c ":10809 " || true)
  elif command -v netstat &>/dev/null; then
    socks_ok=$(netstat -tlnp 2>/dev/null | grep -c ":10808 " || true)
    http_ok=$(netstat -tlnp 2>/dev/null | grep -c ":10809 " || true)
  fi

  if [ "$socks_ok" -gt 0 ]; then
    record_check ok "socks5" "SOCKS5 :10808 — слушает"
  else
    record_check critical "socks5" "SOCKS5 :10808 — НЕ слушает"
  fi

  if [ "$http_ok" -gt 0 ]; then
    record_check ok "http-proxy" "HTTP :10809 — слушает"
  else
    record_check critical "http-proxy" "HTTP :10809 — НЕ слушает"
  fi

  # Проверка через curl
  if [ "$socks_ok" -gt 0 ] && command -v curl &>/dev/null; then
    local test_result
    test_result=$(curl -s --connect-timeout 3 -x socks5://127.0.0.1:10808 \
      https://www.google.com -o /dev/null -w "%{http_code}" 2>/dev/null || echo "000")
    if [ "$test_result" = "200" ] || [ "$test_result" = "301" ] || [ "$test_result" = "302" ]; then
      record_check ok "proxy-test" "Прокси-тест google.com: $test_result"
    else
      record_check degraded "proxy-test" "Прокси-тест google.com: ответ $test_result"
    fi
  fi
}

# ====================================================================
# 3. GeoIP / Geosite
# ====================================================================
check_geo() {
  for f in geoip.dat geosite.dat; do
    local file="$BIN_DIR/$f"
    if [ -f "$file" ] && [ -s "$file" ]; then
      local age size
      age=$((($(date +%s) - $(stat -c %Y "$file")) / 86400))
      size=$(stat -c%s "$file" 2>/dev/null || echo "0")
      if [ "$age" -le 30 ]; then
        record_check ok "geo-$f" "$f: ${size} байт, $age дней"
      else
        record_check degraded "geo-$f" "$f: $age дней (рекомендуется < 30)"
      fi
    else
      record_check critical "geo-$f" "$f: отсутствует или пуст"
    fi
  done
}

# ====================================================================
# 4. Config files
# ====================================================================
check_configs() {
  for f in routing-russia.json only_blocked.json; do
    local file="$V2RAYN_CONFIG/$f"
    if [ -f "$file" ]; then
      if python3 -m json.tool "$file" >/dev/null 2>&1; then
        record_check ok "config-$f" "$f: валидный JSON"
      else
        record_check degraded "config-$f" "$f: невалидный JSON"
      fi
    else
      record_check degraded "config-$f" "$f: отсутствует"
    fi
  done
}

# ====================================================================
# 5. Database / subscriptions
# ====================================================================
check_db() {
  if [ -f "$DB_PATH" ] && command -v sqlite3 &>/dev/null; then
    local sub_count
    sub_count=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM SubItem;" 2>/dev/null || echo "0")
    if [ "$sub_count" -gt 0 ]; then
      record_check ok "database" "Подписок в БД: $sub_count"
    else
      record_check degraded "database" "Подписки не найдены в БД"
    fi

    local routing_enabled
    routing_enabled=$(sqlite3 "$DB_PATH" \
      "SELECT value FROM GlobalConfig WHERE key='routingCustomEnabled';" 2>/dev/null || echo "false")
    if [ "$routing_enabled" = "true" ]; then
      record_check ok "routing" "Кастомный роутинг включён"
    else
      record_check degraded "routing" "Кастомный роутинг выключен"
    fi
  else
    record_check degraded "database" "БД guiNDB.db не найдена"
  fi
}

# ====================================================================
# 6. Systemd timer
# ====================================================================
check_timer() {
  if systemctl --user list-timers v2rayn-rules-update.timer &>/dev/null 2>&1; then
    record_check ok "timer" "v2rayn-rules-update.timer активен"
  else
    record_check degraded "timer" "Timer v2rayn-rules-update.timer не установлен"
  fi
}

# ====================================================================
# 7. System proxy
# ====================================================================
check_system_proxy() {
  if command -v gsettings &>/dev/null; then
    local mode
    mode=$(gsettings get org.gnome.system.proxy mode 2>/dev/null || echo "'none'")
    if [ "$mode" = "'manual'" ]; then
      record_check ok "system-proxy" "GNOME: системный прокси включён"
    else
      record_check degraded "system-proxy" "GNOME: системный прокси выключен ($mode)"
    fi
  elif command -v kwriteconfig5 &>/dev/null || command -v kwriteconfig6 &>/dev/null; then
    record_check ok "system-proxy" "KDE: прокси-проверка не поддерживается в cli"
  else
    record_check ok "system-proxy" "Системный прокси не настраивается (нет GNOME/KDE)"
  fi
}

# ====================================================================
# 8. Xray API (если API включён в конфиге)
# ====================================================================
check_xray_api() {
  local api_port
  api_port=$(python3 -c "
import json, sys
try:
    with open('$V2RAYN_CONFIG/config.json') as f:
        c = json.load(f)
    api = c.get('api', {})
    print(api.get('tag', '') if api.get('tag') else '')
except Exception:
    print('')
" 2>/dev/null || echo "")

  if [ -n "$api_port" ]; then
    # Проверка API через xray
    if command -v xray &>/dev/null && xray api statsquery --server=127.0.0.1:8080 &>/dev/null 2>&1; then
      record_check ok "xray-api" "Xray API доступен"
    else
      record_check degraded "xray-api" "Xray API настроен, но не отвечает"
    fi
  else
    record_check ok "xray-api" "Xray API не настроен (пропущено)"
  fi
}

# ====================================================================
# Build JSON output
# ====================================================================
build_json() {
  json_start
  json_string "timestamp" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Overall status
  local status_str="healthy"
  [ "$EXIT_CODE" -eq 1 ] && status_str="degraded"
  [ "$EXIT_CODE" -eq 2 ] && status_str="critical"
  json_string "status" "$status_str"
  json_int "exit_code" "$EXIT_CODE"

  # Checks array
  json_arr_start "checks"
  for check in "${CHECKS[@]}"; do
    json_arr_item
    JSON_OUTPUT+="$check"
  done
  json_arr_end
  json_end
  echo "$JSON_OUTPUT"
}

# ====================================================================
# Systemd unit management
# ====================================================================
install_service() {
  local user_unit_dir="$HOME/.config/systemd/user"
  mkdir -p "$user_unit_dir"

  # Copy service
  if [ -f "$SYSTEMD_DIR/v2rayn-health.service" ]; then
    cp "$SYSTEMD_DIR/v2rayn-health.service" "$user_unit_dir/"
    journal_notice "Установлен v2rayn-health.service"
  else
    echo "Ошибка: v2rayn-health.service не найден в $SYSTEMD_DIR"
    exit 1
  fi

  # Copy timer
  if [ -f "$SYSTEMD_DIR/v2rayn-health.timer" ]; then
    cp "$SYSTEMD_DIR/v2rayn-health.timer" "$user_unit_dir/"
    journal_notice "Установлен v2rayn-health.timer"
  else
    echo "Ошибка: v2rayn-health.timer не найден в $SYSTEMD_DIR"
    exit 1
  fi

  systemctl --user daemon-reload
  systemctl --user enable --now v2rayn-health.timer
  journal_notice "Timer v2rayn-health.timer включён и запущен"
  echo "✓ v2rayn-health.timer установлен и запущен"
}

remove_service() {
  systemctl --user disable --now v2rayn-health.timer 2>/dev/null || true
  systemctl --user disable --now v2rayn-health.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/v2rayn-health.service"
  rm -f "$HOME/.config/systemd/user/v2rayn-health.timer"
  systemctl --user daemon-reload
  journal_notice "v2rayn-health удалён"
  echo "✓ v2rayn-health удалён"
}

# ====================================================================
# Main
# ====================================================================
main() {
  case "${MODE}" in
    --install|-i)
      install_service
      exit 0
      ;;
    --remove|-r)
      remove_service
      exit 0
      ;;
    --check|-c)
      check_process
      check_ports
      [ "$EXIT_CODE" -lt 2 ] && check_geo
      [ "$EXIT_CODE" -lt 2 ] && check_configs
      [ "$EXIT_CODE" -lt 2 ] && check_db
      [ "$EXIT_CODE" -lt 2 ] && check_timer
      [ "$EXIT_CODE" -lt 2 ] && check_system_proxy
      [ "$EXIT_CODE" -lt 2 ] && check_xray_api
      exit "$EXIT_CODE"
      ;;
    --json|-j)
      check_process
      check_ports
      check_geo
      check_configs
      check_db
      check_timer
      check_system_proxy
      check_xray_api
      build_json
      exit "$EXIT_CODE"
      ;;
    full|--full|-f|*)
      # Вывод в journald
      journal_info "=== v2rayN Health Check ==="
      check_process
      check_ports
      check_geo
      check_configs
      check_db
      check_timer
      check_system_proxy
      check_xray_api
      journal_notice "Health check завершён: exit=$EXIT_CODE"

      # Если нужно так же в stdout (для ручного запуска)
      echo "v2rayN Health Check — exit code: $EXIT_CODE"
      echo "Проверок: ${#CHECKS[@]}"
      echo "Подробности: journalctl -u v2rayn-health.service --no-pager | tail -20"
      exit "$EXIT_CODE"
      ;;
  esac
}

main "$@"
