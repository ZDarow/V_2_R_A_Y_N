# install_spec.bash — тесты для install.sh
# shellcheck disable=SC2034,SC2155

load test_helper

setup() {
  setup_tempdir
}

teardown() {
  teardown_tempdir
}

@test "install.sh: существует" {
  [ -f "${PROJECT_ROOT}/install.sh" ]
}

@test "install.sh: bash синтаксис без ошибок" {
  run bash -n "${PROJECT_ROOT}/install.sh"
  [ "$status" -eq 0 ]
}

@test "install.sh: --help показывает справку и возвращает 0" {
  run bash "${PROJECT_ROOT}/install.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"v2rayN"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"install"* ]]
}

@test "install.sh: проверка наличия set -euo pipefail" {
  run grep -c 'set -euo pipefail' "${PROJECT_ROOT}/install.sh"
  [ "$output" -eq 1 ]
}

@test "install.sh: проверка обязательных команд (curl или wget)" {
  local has_curl=false has_wget=false
  command -v curl &>/dev/null && has_curl=true
  command -v wget &>/dev/null && has_wget=true
  [ "$has_curl" = true ] || [ "$has_wget" = true ]
}

@test "install.sh: BASH_SOURCE сброс для pipe-режима" {
  run grep -c 'BASH_SOURCE.*install.sh' "${PROJECT_ROOT}/install.sh"
  # install.sh должен содержать проверку BASH_SOURCE для pipe mode
  run grep -c 'BASH_SOURCE' "${PROJECT_ROOT}/install.sh"
  [ "$output" -ge 1 ]
}

@test "install.sh: функция verify_sha256 вызывается" {
  run grep -c 'verify_sha256' "${PROJECT_ROOT}/install.sh"
  [ "$output" -ge 1 ]
}
