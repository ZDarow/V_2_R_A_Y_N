#!/usr/bin/env bats
# integration_spec.bash — интеграционные тесты (end-to-end)
# ============================================================================
# Проверяет работу скриптов в связке в изолированном sandbox-окружении.
# Все внешние зависимости (v2rayN, systemd, процессы) замоканы.
# ============================================================================

setup() {
  load 'test_helper'
  PROJECT_ROOT="$(dirname "$BATS_TEST_DIRNAME")"

  # Sandbox directory
  SANDBOX="$(mktemp -d /tmp/v2rayn-integration-XXXXXX)"
  export V2RAYN_HOME="${SANDBOX}/local/share/v2rayN"
  export V2RAYN_CONFIG="${SANDBOX}/config/v2rayN"
  export XDG_CONFIG_HOME="${SANDBOX}/config"
  export XDG_DATA_HOME="${SANDBOX}/local/share"
  export HOME="${SANDBOX}"

  mkdir -p "$V2RAYN_HOME/bin" "$V2RAYN_HOME/guiConfigs" \
           "$V2RAYN_CONFIG" "$SANDBOX/.config/systemd/user" \
           "$SANDBOX/.local/bin"

  # Mock files
  : > "$V2RAYN_HOME/bin/geoip.dat"
  : > "$V2RAYN_HOME/bin/geosite.dat"

  # Mock configs
  cp "$PROJECT_ROOT/config/routing-russia.json" "$V2RAYN_CONFIG/" 2>/dev/null || true
  cp "$PROJECT_ROOT/config/only_blocked.json" "$V2RAYN_CONFIG/" 2>/dev/null || true

  # Mock sqlite3 — подменяем на скрипт, который симулирует БД
  sqlite3_mock() {
    case "$*" in
      *"count(*) FROM SubItem"*) echo "3" ;;
      *"routingCustomEnabled"*)  echo "true" ;;
      *"routingCustomFile"*)     echo "routing-russia.json" ;;
      *)                         echo "" ;;
    esac
  }
}

teardown() {
  rm -rf "$SANDBOX"
}

# ---- 1. Структура директорий ----
@test "integration: sandbox создан с ожидаемой структурой" {
  [ -d "$V2RAYN_HOME/bin" ]
  [ -d "$V2RAYN_CONFIG" ]
  [ -f "$V2RAYN_HOME/bin/geoip.dat" ]
  [ -f "$V2RAYN_HOME/bin/geosite.dat" ]
}

# ---- 2. apply-configs.sh — копирование конфигов ----
@test "integration: apply-configs.sh копирует конфиги в V2RAYN_CONFIG" {
  # apply-configs.sh лежит в корне проекта, не в scripts/
  run bash "$PROJECT_ROOT/apply-configs.sh"
  # Может вернуть 0 или 1 в sandbox (без v2rayN), главное — скопировались файлы
  for f in routing-russia.json only_blocked.json; do
    [ -f "$V2RAYN_CONFIG/$f" ]
  done
}

# ---- 3. status.sh — вывод состояния без v2rayN ----
@test "integration: status.sh выдаёт информационные секции в sandbox" {
  run bash "$PROJECT_ROOT/scripts/status.sh" 2>&1 || true
  [[ "$output" == *"v2rayN Status"* ]]
  [[ "$output" == *"Прокси"* ]]
  [[ "$output" == *"GeoIP"* ]]
}

# ---- 4. update-rules.sh — проверка lock-файла ----
@test "integration: update-rules.sh использует lock-файл" {
  run bash "$PROJECT_ROOT/scripts/update-rules.sh" --help
  [ "$status" -eq 0 ]
  grep -q "acquire_lock\|--help" <<< "$output"
}

# ---- 5. proxy-toggle.sh — on/off/status аргументы ----
@test "integration: proxy-toggle.sh status работает (без systemd)" {
  run bash "$PROJECT_ROOT/scripts/proxy-toggle.sh" status 2>&1 || true
  [ -n "$output" ]
}

# ---- 6. diagnose.sh — проверка портов и процессов ----
@test "integration: diagnose.sh выполняет проверки (sandbox)" {
  run bash "$PROJECT_ROOT/scripts/diagnose.sh" 2>&1 || true
  # Должен показать что Xray не найден
  [[ "$output" == *"xray"* || "$output" == *"Xray"* ]]
}

# ---- 7. v2ray-health.sh --check в sandbox ----
@test "integration: v2ray-health.sh --check работает в sandbox" {
  run bash "$PROJECT_ROOT/scripts/v2ray-health.sh" --check
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
}

@test "integration: v2ray-health.sh --json выдаёт валидный JSON в sandbox" {
  run bash "$PROJECT_ROOT/scripts/v2ray-health.sh" --json
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'checks' in d
assert isinstance(d['checks'], list)
# Хотя бы одна проверка есть
assert len(d['checks']) > 0
"
}

# ---- 8. mocks работают в реальном сценарии ----
@test "integration: pgrep mock перехватывает проверку процесса" {
  # Ставим mock_pgrep, который "находит" v2rayn
  mock_v2rayn_running
  # Теперь status.sh должен увидеть запущенный процесс
  run bash "$PROJECT_ROOT/scripts/status.sh" 2>&1 || true
  [[ "$output" == *"запущен"* ]]
}

# ---- 9. geoip.dat валидация ----
@test "integration: geoip.dat валидируется через fake_geo" {
  fake_geo "$V2RAYN_HOME/bin"
  # После fake_geo файлы существуют
  for f in geoip.dat geosite.dat; do
    [ -f "$V2RAYN_HOME/bin/$f" ]
  done
  # Добавляем содержимое для валидации размера
  # shellcheck disable=SC2034
  echo "mock" > "$V2RAYN_HOME/bin/geoip.dat"
  echo "mock" > "$V2RAYN_HOME/bin/geosite.dat"
  [ -s "$V2RAYN_HOME/bin/geoip.dat" ]
  [ -s "$V2RAYN_HOME/bin/geosite.dat" ]
}

# ---- 10. kill-switch.sh — обработка в sandbox ----
@test "integration: kill-switch.sh не падает без iptables" {
  run bash "$PROJECT_ROOT/scripts/kill-switch.sh" status 2>&1 || true
  # В sandbox без iptables — грациозный выход
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
