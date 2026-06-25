#!/bin/bash
# sync-time.sh — синхронизация времени через HTTP Date header (для блокированных сетей)
# Замена systemd-timesyncd, когда NTP (UDP 123) заблокирован
# Использует HTTP-прокси 127.0.0.1:10809 (v2rayN)

set -euo pipefail

LOG_FILE="/home/mi/logs/time-sync.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

get_server_time() {
  local url="$1"
  local date_str
  date_str=$(curl -s -m 10 -x http://127.0.0.1:10809 -I "$url" 2>/dev/null | grep -i '^date:' | sed 's/^[Dd]ate: //; s/\r$//' | head -1)
  if [ -z "$date_str" ]; then return 1; fi
  date -d "$date_str" +%s 2>/dev/null || return 1
}

# Пробуем несколько популярных сайтов для получения времени
for url in "https://www.google.com" "https://www.github.com" "https://www.yandex.ru"; do
  server_epoch=$(get_server_time "$url") && break
done

if [ -z "${server_epoch:-}" ]; then
  log "ОШИБКА: не удалось получить время ни с одного сервера"
  exit 1
fi

current_epoch=$(date +%s)
delta=$((current_epoch - server_epoch))
delta_abs="${delta#-}"

log "Сервер: $(date -d "@$server_epoch" '+%Y-%m-%d %H:%M:%S') | Система: $(date '+%Y-%m-%d %H:%M:%S') | Дельта: ${delta}s"

if [ "$delta_abs" -gt 2 ]; then
  log "КОРРЕКЦИЯ: устанавливаю время (дельта ${delta}s)"
  date -s "@$server_epoch" >/dev/null 2>&1 || sudo date -s "@$server_epoch" >/dev/null 2>&1
  log "Установлено: $(date '+%Y-%m-%d %H:%M:%S')"
else
  log "OK: время синхронизировано (дельта ${delta}s)"
fi
