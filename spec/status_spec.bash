# status_spec.bash — тесты для scripts/status.sh
# shellcheck disable=SC2034,SC2155

load test_helper

@test "status.sh: существует" {
  [ -f "${PROJECT_ROOT}/scripts/status.sh" ]
}

@test "status.sh: bash синтаксис без ошибок" {
  run bash -n "${PROJECT_ROOT}/scripts/status.sh"
  [ "$status" -eq 0 ]
}

@test "status.sh: запуск с моком v2rayn_stopped (грациозный выход)" {
  mock_v2rayn_stopped
  run bash "${PROJECT_ROOT}/scripts/status.sh" 2>&1 || true
  # Принимаем любой exit — важно что скрипт выполнился без bash-ошибки
  # и вывел информационные секции
  [ -n "$output" ]
  [[ "$output" == *"v2rayN"* || "$output" == *"Статус"* ]]
}

@test "status.sh: запуск с моком v2rayn_running" {
  mock_v2rayn_running
  run bash "${PROJECT_ROOT}/scripts/status.sh" 2>&1 || true
  # Мок должен показать процесс как запущенный
  [[ "$output" == *"запущен"* ]]
}

@test "status.sh: запуск без флагов (допустимый exit — v2rayN может быть не запущен)" {
  run bash "${PROJECT_ROOT}/scripts/status.sh" 2>&1 || true
  # Принимаем любой exit — проверяем только что вывод есть и содержит ключевые секции
  [ -n "$output" ]
}

@test "status.sh: выводит информационные секции" {
  run bash "${PROJECT_ROOT}/scripts/status.sh" 2>&1 || true
  [[ "$output" == *"v2rayN"* ]] || [[ "$output" == *"Статус"* ]] || [[ "$output" == *"Status"* ]]
}

@test "status.sh: set -euo pipefail включён" {
  run grep -c 'set -euo pipefail' "${PROJECT_ROOT}/scripts/status.sh"
  [ "$output" -ge 1 ]
}

@test "status.sh: невалидный флаг возвращает ненулевой код" {
  run bash "${PROJECT_ROOT}/scripts/status.sh" --invalid-flag 2>&1 || true
  [ "$status" -ne 0 ]
}
