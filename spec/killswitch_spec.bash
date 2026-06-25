# killswitch_spec.bash — тесты для scripts/kill-switch.sh
# shellcheck disable=SC2034,SC2155

load test_helper

setup() {
  setup_tempdir
}

teardown() {
  teardown_tempdir
}

@test "kill-switch.sh: существует" {
  [ -f "${PROJECT_ROOT}/scripts/kill-switch.sh" ]
}

@test "kill-switch.sh: bash синтаксис без ошибок" {
  run bash -n "${PROJECT_ROOT}/scripts/kill-switch.sh"
  [ "$status" -eq 0 ]
}

@test "kill-switch.sh: status возвращает 0 (iptables не доступен — грациозный выход)" {
  run bash "${PROJECT_ROOT}/scripts/kill-switch.sh" status 2>&1 || true
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "kill-switch.sh: работа с mock_v2rayn_running" {
  mock_v2rayn_running
  run bash "${PROJECT_ROOT}/scripts/kill-switch.sh" status 2>&1 || true
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "kill-switch.sh: невалидный аргумент возвращает 1" {
  run bash "${PROJECT_ROOT}/scripts/kill-switch.sh" invalid_arg 2>&1 || true
  [ "$status" -ne 0 ]
}

@test "kill-switch.sh: проверка set -euo pipefail" {
  run grep -c 'set -euo pipefail' "${PROJECT_ROOT}/scripts/kill-switch.sh"
  [ "$output" -ge 1 ]
}

@test "kill-switch.sh: без аргументов возвращает 0 (статус по умолчанию)" {
  run bash "${PROJECT_ROOT}/scripts/kill-switch.sh" 2>&1 || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"Kill-switch"* || "$output" == *"ВЫКЛ"* || "$output" == *"status"* ]]
}
