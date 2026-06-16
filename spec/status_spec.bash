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

@test "status.sh: запуск без флагов (допустимый exit 1 — v2rayN не запущен)" {
  run bash "${PROJECT_ROOT}/scripts/status.sh" 2>&1 || true
  # Без запущенного v2rayN exit может быть 0 или 1 — оба допустимы
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
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
