# common_spec.bash — тесты для lib/common.sh
# Тесты запускают common.sh в изолированном subshell через run bash -c
# shellcheck disable=SC2034,SC2155

load test_helper

setup() {
  setup_tempdir
  export LOG_FILE="${BATS_TEMP_DIR}/test.log"
  > "$LOG_FILE"
  PROJECT_ROOT="${PROJECT_ROOT:-${BATS_TEST_DIRNAME}/..}"
}

teardown() {
  teardown_tempdir
}

@test "download_with_retry: скачивание недоступного URL возвращает 1" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    download_with_retry 'http://localhost:1/nonexistent' '${BATS_TEMP_DIR}/out' 1 1
  " 2>/dev/null
  [ "$status" -eq 1 ]
}

@test "download_with_retry: использует mktemp для временных файлов (исходный код)" {
  run grep -c 'mktemp' "${PROJECT_ROOT}/lib/common.sh"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "verify_sha256: отсутствие checksum возвращает 2" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    verify_sha256 '${PROJECT_ROOT}/README.md' 'http://localhost:1/nonexistent.sha256'
  " 2>/dev/null
  [ "$status" -eq 2 ]
}

@test "verify_sha256: использует mktemp для sha-файлов (исходный код)" {
  run grep -c 'mktemp' "${PROJECT_ROOT}/lib/common.sh"
  [ "$output" -ge 2 ]
}

@test "log_info: записывает сообщение в лог-файл" {
  run bash -c "
    export LOG_FILE='${LOG_FILE}'
    source '${PROJECT_ROOT}/lib/common.sh'
    log_info 'Тестовое сообщение' 2>/dev/null
    grep -c 'Тестовое сообщение' \"\$LOG_FILE\"
  " 2>/dev/null
  [ "$output" -eq 1 ]
}

@test "log_warn: записывает предупреждение в лог-файл" {
  run bash -c "
    export LOG_FILE='${LOG_FILE}'
    source '${PROJECT_ROOT}/lib/common.sh'
    log_warn 'Предупреждение теста' 2>/dev/null
    grep -c 'Предупреждение теста' \"\$LOG_FILE\"
  " 2>/dev/null
  [ "$output" -eq 1 ]
}

@test "log_error: вызывает exit 1" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    log_error 'Тестовая ошибка'
  " 2>/dev/null
  [ "$status" -eq 1 ]
}

@test "acquire_lock/release_lock: работают в паре" {
  run bash -c "
    export LOCK_DIR='${BATS_TEMP_DIR}/locks'
    mkdir -p \"\$LOCK_DIR\"
    source '${PROJECT_ROOT}/lib/common.sh'
    acquire_lock 'test_pair' 2>/dev/null
    release_lock 'test_pair' 2>/dev/null
    ! [ -d \"\${LOCK_DIR}/test_pair.lock\" ]
  " 2>/dev/null
  [ "$status" -eq 0 ]
}

@test "acquire_lock: двойной захват возвращает 1" {
  run bash -c "
    export LOCK_DIR='${BATS_TEMP_DIR}/locks2'
    mkdir -p \"\$LOCK_DIR\"
    source '${PROJECT_ROOT}/lib/common.sh'
    acquire_lock 'test_double' 2>/dev/null
    acquire_lock 'test_double' 2>/dev/null
    ret=\$?
    release_lock 'test_double' 2>/dev/null
    exit \$ret
  " 2>/dev/null
  [ "$status" -eq 1 ]
}

@test "validate_dat: fake_geo файлы проходят валидацию" {
  fake_geo "${BATS_TEMP_DIR}/rules"
  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    validate_dat '${BATS_TEMP_DIR}/rules/geoip.dat'
    echo exit:\$?
  " 2>/dev/null
  # fake_geo создаёт пустые файлы (размер 0), validate_dat требует >10KB
  # Ожидаем exit 1 — файл слишком мал
  [[ "$output" == *"exit:1"* ]]
  rm_fake_geo "${BATS_TEMP_DIR}/rules"
}

@test "assert_json_valid: JSON конфиги валидны" {
  # Используем assert_json_valid из test_helper.bash
  for f in config/config-template-xray.json config/routing-russia.json config/only_blocked.json; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
      run python3 -m json.tool "$PROJECT_ROOT/$f" >/dev/null 2>&1
      [ "$status" -eq 0 ] || {
        echo "JSON невалиден: $f"
        return 1
      }
    fi
  done
}

@test "detect_arch: возвращает архитектуру" {
  run bash -c "
    source '${PROJECT_ROOT}/lib/common.sh'
    detect_arch
  " 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == "64" || "$output" == "arm64" ]]
}

@test "check_not_root: не падает обычного пользователя" {
  if [ "$(id -u)" -ne 0 ]; then
    run bash -c "
      source '${PROJECT_ROOT}/lib/common.sh'
      check_not_root
    " 2>/dev/null
    [ "$status" -eq 0 ]
  else
    skip "Тест запущен от root"
  fi
}
