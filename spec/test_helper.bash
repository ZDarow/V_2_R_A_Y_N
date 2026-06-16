# test_helper.bash — общие утилиты для bats-тестов v2rayN Russia Setup
# shellcheck disable=SC2034,SC2155

# Корень проекта (запуск из spec/)
export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."

# Подключение библиотек
setup_project_env() {
  # shellcheck source=../lib/common.sh
  source "${PROJECT_ROOT}/lib/common.sh"
}

# Временная директория для тестов (автоочистка)
setup_tempdir() {
  export BATS_TEMP_DIR=$(mktemp -d "/tmp/v2rayn-test.XXXXXX")
}

teardown_tempdir() {
  rm -rf "${BATS_TEMP_DIR:-/tmp/v2rayn-test.nonexistent}"
}

# Создать фейковый GEOIP/GEOSITE для тестов
fake_geo() {
  local dir="${1:-${PROJECT_ROOT}/rules}"
  mkdir -p "$dir"
  touch "$dir/geoip.dat" "$dir/geosite.dat"
}

rm_fake_geo() {
  local dir="${1:-${PROJECT_ROOT}/rules}"
  rm -f "$dir/geoip.dat" "$dir/geosite.dat"
  rmdir "$dir" 2>/dev/null || true
}

# Замокать v2rayN процесс
mock_v2rayn_running() {
  # Создаём фейковый PID в /proc если /proc смонтирован
  if [ -d /proc/self ]; then
    # Используем test для симуляции pgrep
    eval 'pgrep() { [ "${1}" = "-x" ] && [ "${2}" = "v2rayn" ] && return 0; return 1; }'
    export -f pgrep 2>/dev/null || true
  fi
  # Замокать формат ss в определении порта
  eval 'ss() { echo "LISTEN 0 128 127.0.0.1:10809 0.0.0.0:*"; }'
  export -f ss 2>/dev/null || true
}

mock_v2rayn_stopped() {
  eval 'pgrep() { return 1; }'
  export -f pgrep 2>/dev/null || true
  eval 'ss() { return 1; }'
  export -f ss 2>/dev/null || true
}

# Фейковый лог-файл
create_fake_log() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<'EOF'
2026-06-15 10:00:00 [Info] v2rayN запущен
2026-06-15 10:00:01 [Info] Подключение к прокси установлено
2026-06-15 10:00:05 [Info] Обновление правил: успешно
EOF
}

# Проверка JSON
assert_json_valid() {
  local file="$1"
  run python3 -m json.tool "$file" >/dev/null 2>&1
  [ "$status" -eq 0 ] || {
    echo "JSON невалиден: $file"
    python3 -m json.tool "$file" 2>&1 || true
    return 1
  }
}

# Проверка что переменная не пустая
assert_not_empty() {
  local var_name="$1" var_val="$2"
  [ -n "$var_val" ] && return 0
  echo "ОШИБКА: $var_name пустая"
  return 1
}

# Вывод отладочной информации
debug_test_env() {
  echo "# PROJECT_ROOT=$PROJECT_ROOT" >&3
  echo "# BATS_TEMP_DIR=${BATS_TEMP_DIR:-unset}" >&3
  echo "# SHELL=$SHELL" >&3
  echo "# PWD=$PWD" >&3
}
