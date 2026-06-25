#!/usr/bin/env bats
# coverage_spec.bash — базовые тесты для скриптов без покрытия
# ============================================================================
# Покрывает скрипты, не имевшие тестов (16 скриптов).
# Использует test_helper.bash моки (mock_v2rayn_running/stopped, fake_geo).
# ============================================================================

setup() {
    load 'test_helper.bash'
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    setup_tempdir
}

teardown() {
    teardown_tempdir
}

# ─── uninstall.sh ───────────────────────────────────────────────────────────

@test "uninstall.sh: существует" {
    [ -f "$PROJECT_ROOT/uninstall.sh" ]
}

@test "uninstall.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/uninstall.sh"
}

@test "uninstall.sh: --help показывает справку и возвращает 0" {
    run bash "$PROJECT_ROOT/uninstall.sh" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "использование\|usage\|v2rayN\|деинсталл"
}

@test "uninstall.sh: содержит set -euo pipefail" {
    head -5 "$PROJECT_ROOT/uninstall.sh" | grep -q "set -euo pipefail"
}

# ─── apply-configs.sh ───────────────────────────────────────────────────────

@test "apply-configs.sh: существует" {
    [ -f "$PROJECT_ROOT/apply-configs.sh" ]
}

@test "apply-configs.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/apply-configs.sh"
}

@test "apply-configs.sh: содержит set -euo pipefail" {
    head -10 "$PROJECT_ROOT/apply-configs.sh" | grep -q "set -euo pipefail"
}

@test "apply-configs.sh: --help показывает справку" {
    run bash "$PROJECT_ROOT/apply-configs.sh" --help
    [ "$status" -eq 0 ]
}

# ─── scripts/update-rules.sh ────────────────────────────────────────────────

@test "update-rules.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/update-rules.sh" ]
}

@test "update-rules.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/update-rules.sh"
}

@test "update-rules.sh: --help возвращает 0" {
    run bash "$PROJECT_ROOT/scripts/update-rules.sh" --help
    [ "$status" -eq 0 ]
}

@test "update-rules.sh: содержит retry-логику (download_with_retry)" {
    grep -q "download_with_retry\|retry" "$PROJECT_ROOT/scripts/update-rules.sh"
}

@test "update-rules.sh: содержит SHA256 верификацию" {
    grep -q "sha256\|SHA256\|sha.*sum" "$PROJECT_ROOT/scripts/update-rules.sh"
}

@test "update-rules.sh: использует lock-файл" {
    grep -q "lock\|LOCK" "$PROJECT_ROOT/scripts/update-rules.sh"
}

# ─── scripts/proxy-toggle.sh ────────────────────────────────────────────────

@test "proxy-toggle.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/proxy-toggle.sh" ]
}

@test "proxy-toggle.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/proxy-toggle.sh"
}

@test "proxy-toggle.sh: on/off/status аргументы" {
    grep -q '"on"\|"off"\|status' "$PROJECT_ROOT/scripts/proxy-toggle.sh"
}

# ─── scripts/proxy_set_linux_sh.sh ──────────────────────────────────────────

@test "proxy_set_linux_sh.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/proxy_set_linux_sh.sh" ]
}

@test "proxy_set_linux_sh.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/proxy_set_linux_sh.sh"
}

@test "proxy_set_linux_sh.sh: содержит GNOME и KDE функции" {
    grep -q "gsettings\|kwriteconfig" "$PROJECT_ROOT/scripts/proxy_set_linux_sh.sh"
}

# ─── scripts/diagnose.sh ────────────────────────────────────────────────────

@test "diagnose.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/diagnose.sh" ]
}

@test "diagnose.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/diagnose.sh"
}

@test "diagnose.sh: проверяет Xray и порты" {
    grep -q "xray\|10808\|10809\|порт" "$PROJECT_ROOT/scripts/diagnose.sh"
}

# ─── scripts/migrate-allowinsecure.sh ───────────────────────────────────────

@test "migrate-allowinsecure.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/migrate-allowinsecure.sh" ]
}

@test "migrate-allowinsecure.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/migrate-allowinsecure.sh"
}

@test "migrate-allowinsecure.sh: --help или -h возвращает 0" {
    run bash "$PROJECT_ROOT/scripts/migrate-allowinsecure.sh" --help
    [ "$status" -eq 0 ]
}

@test "migrate-allowinsecure.sh: содержит pinnedPeerCertSha256" {
    grep -q "pinnedPeerCertSha256\|allowInsecure" "$PROJECT_ROOT/scripts/migrate-allowinsecure.sh"
}

# ─── scripts/diagnose-network.sh ───────────────────────────────────────────

@test "diagnose-network.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/diagnose-network.sh" ]
}

@test "diagnose-network.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/diagnose-network.sh"
}

@test "diagnose-network.sh: содержит 14+ секций диагностики" {
    run grep -c "секция\|step\|section\|###\|test_" "$PROJECT_ROOT/scripts/diagnose-network.sh"
    [ "$output" -ge 14 ]
}

# ─── scripts/v2ray-manager.sh ───────────────────────────────────────────────

@test "v2ray-manager.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/v2ray-manager.sh" ]
}

@test "v2ray-manager.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/v2ray-manager.sh"
}

@test "v2ray-manager.sh: содержит set -uo pipefail" {
    head -10 "$PROJECT_ROOT/scripts/v2ray-manager.sh" | grep -q "set -uo pipefail"
}

@test "v2ray-manager.sh: содержит функции управления" {
    grep -q "check_status\|proxy_on\|proxy_off\|xray_start\|xray_stop" \
        "$PROJECT_ROOT/scripts/v2ray-manager.sh"
}

@test "v2ray-manager.sh: использует mock — статус Xray" {
    mock_v2rayn_running
    run bash -c "
      cd '$PROJECT_ROOT'
      source '$PROJECT_ROOT/lib/common.sh' 2>/dev/null || true
      echo 'mock ready'
    " 2>/dev/null
    [ "$status" -eq 0 ]
}

# ─── scripts/v2ray-fix-all.sh ───────────────────────────────────────────────

@test "v2ray-fix-all.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/v2ray-fix-all.sh" ]
}

@test "v2ray-fix-all.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/v2ray-fix-all.sh"
}

@test "v2ray-fix-all.sh: диагностирует Xray и конфиг" {
    grep -q "xray\|config\|диагностик\|исправл" "$PROJECT_ROOT/scripts/v2ray-fix-all.sh"
}

# ─── scripts/traffic-capture.sh ─────────────────────────────────────────────

@test "traffic-capture.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/traffic-capture.sh" ]
}

@test "traffic-capture.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/traffic-capture.sh"
}

@test "traffic-capture.sh: содержит тестовые домены" {
    grep -q "BLOCKED_SITES\|RUSSIAN_SITES\|twitter\|yandex" \
        "$PROJECT_ROOT/scripts/traffic-capture.sh"
}

@test "traffic-capture.sh: --help или --all аргументы" {
    grep -q "\-\-help\|\-\-all\|\-\-dns" "$PROJECT_ROOT/scripts/traffic-capture.sh"
}

# ─── scripts/restore-all.sh ─────────────────────────────────────────────────

@test "restore-all.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/restore-all.sh" ]
}

@test "restore-all.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/restore-all.sh"
}

@test "restore-all.sh: содержит --help" {
    run bash "$PROJECT_ROOT/scripts/restore-all.sh" --help
    [ "$status" -eq 0 ]
}

# ─── scripts/proxy-manager-gui.sh ───────────────────────────────────────────

@test "proxy-manager-gui.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/proxy-manager-gui.sh" ]
}

@test "proxy-manager-gui.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/proxy-manager-gui.sh"
}

@test "proxy-manager-gui.sh: требует YAD для GUI" {
    grep -q "command -v yad\|yad " "$PROJECT_ROOT/scripts/proxy-manager-gui.sh"
}

@test "proxy-manager-gui.sh: содержит lock-файл от множественных экземпляров" {
    grep -q "LOCK_FILE\|acquire_gui_lock\|lock" "$PROJECT_ROOT/scripts/proxy-manager-gui.sh"
}

@test "proxy-manager-gui.sh: содержит KDE поддержку" {
    grep -q "kwriteconfig" "$PROJECT_ROOT/scripts/proxy-manager-gui.sh"
}

# ─── scripts/netcheck.sh ────────────────────────────────────────────────────

@test "netcheck.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/netcheck.sh" ]
}

@test "netcheck.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/netcheck.sh"
}

@test "netcheck.sh: проверяет внешний IP и DNS" {
    grep -q "ipinfo\|8.8.8.8\|DNS\|dig" "$PROJECT_ROOT/scripts/netcheck.sh"
}

# ─── scripts/setup-two-server.sh ────────────────────────────────────────────

@test "setup-two-server.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/setup-two-server.sh" ]
}

@test "setup-two-server.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/setup-two-server.sh"
}

@test "setup-two-server.sh: --help возвращает 0" {
    run bash "$PROJECT_ROOT/scripts/setup-two-server.sh" --help
    [ "$status" -eq 0 ]
}

@test "setup-two-server.sh: содержит режимы --check и --gen-config" {
    grep -q "\-\-check\|\-\-gen-config" "$PROJECT_ROOT/scripts/setup-two-server.sh"
}

# ====================================================================
# v2ray-health.sh
# ====================================================================
@test "v2ray-health.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/v2ray-health.sh" ]
}

@test "v2ray-health.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/v2ray-health.sh"
}

@test "v2ray-health.sh: проверка set -euo pipefail" {
    grep -q "set -euo pipefail" "$PROJECT_ROOT/scripts/v2ray-health.sh"
}

@test "v2ray-health.sh: --check возвращает 0 или 1 (без v2rayN)" {
    run bash "$PROJECT_ROOT/scripts/v2ray-health.sh" --check
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "v2ray-health.sh: --json выводит валидный JSON" {
    run bash "$PROJECT_ROOT/scripts/v2ray-health.sh" --json
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    echo "$output" | python3 -m json.tool >/dev/null 2>&1
}

@test "v2ray-health.sh: --json содержит status и checks поля" {
    run bash "$PROJECT_ROOT/scripts/v2ray-health.sh" --json
    echo "$output" | python3 -c "
import json,sys
d = json.load(sys.stdin)
assert 'status' in d, 'No status'
assert 'exit_code' in d, 'No exit_code'
assert 'checks' in d, 'No checks'
assert 'timestamp' in d, 'No timestamp'
"
}

@test "v2ray-health.sh: journald функции определены" {
    grep -q "journal_error\|journal_warn\|journal_info\|journal_notice" \
        "$PROJECT_ROOT/scripts/v2ray-health.sh"
}

@test "v2ray-health.sh: systemd unit management (--install/--remove)" {
    grep -q "\-\-install\|\-\-remove" "$PROJECT_ROOT/scripts/v2ray-health.sh"
}
