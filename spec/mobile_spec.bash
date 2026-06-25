#!/usr/bin/env bats
# mobile_spec.bash — BATS тесты для мобильных скриптов
# ============================================================================

setup() {
    load 'test_helper.bash'
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "detect-block-type.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/detect-block-type.sh" ]
}

@test "detect-block-type.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/detect-block-type.sh"
}

@test "detect-block-type.sh: --help показывает справку и возвращает 0" {
    run bash "$PROJECT_ROOT/scripts/detect-block-type.sh" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "использование\|usage\|справка\|диагностика"
}

@test "detect-block-type.sh: set -uo pipefail включён" {
    grep -q "set -uo pipefail" "$PROJECT_ROOT/scripts/detect-block-type.sh"
}

@test "detect-block-type.sh: проверка обязательных команд (curl, dig, ping)" {
    grep -q "curl\|dig\|ping" "$PROJECT_ROOT/scripts/detect-block-type.sh"
}

@test "mobile-netcheck.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/mobile-netcheck.sh" ]
}

@test "mobile-netcheck.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/mobile-netcheck.sh"
}

@test "mobile-netcheck.sh: set -uo pipefail включён" {
    head -5 "$PROJECT_ROOT/scripts/mobile-netcheck.sh" | grep -q "set -uo pipefail"
}

@test "mobile-netcheck.sh: содержит тест CGNAT (секция 13)" {
    grep -q "CGNAT\|Carrier-Grade NAT" "$PROJECT_ROOT/scripts/mobile-netcheck.sh"
}

@test "mobile-netcheck.sh: содержит тест BGP ASN (секция 14)" {
    grep -q "BGP ASN\|ipinfo.io.*asn" "$PROJECT_ROOT/scripts/mobile-netcheck.sh"
}

@test "mobile-netcheck.sh: содержит тест UDP портов (секция 15)" {
    grep -q "UDP.*WireGuard\|udp_ports\|QUIC\|doq" "$PROJECT_ROOT/scripts/mobile-netcheck.sh"
}

@test "mobile-netcheck.sh: содержит SNI vs IP тест (секция 16)" {
    grep -q "SNI vs IP\|sni.*ip.*test\|SNI.*спуфинг\|openssl s_client" "$PROJECT_ROOT/scripts/mobile-netcheck.sh"
}

@test "optimize-mobile.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/optimize-mobile.sh" ]
}

@test "optimize-mobile.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/optimize-mobile.sh"
}

@test "optimize-mobile.sh: содержит fragment TLS" {
    grep -q "fragment\|tlshello\|packets.*tls" "$PROJECT_ROOT/scripts/optimize-mobile.sh"
}

@test "optimize-mobile.sh: содержит SNI ротацию" {
    grep -q "rotate.*SNI\|SNI.*whitelist\|SNI_WHITELIST\|random_sni" "$PROJECT_ROOT/scripts/optimize-mobile.sh"
}

@test "optimize-mobile.sh: содержит two-server инструкцию" {
    grep -q "two-server\|Two.server\|двухсерверн" "$PROJECT_ROOT/scripts/optimize-mobile.sh"
}

@test "rotate-sni.sh: существует" {
    [ -f "$PROJECT_ROOT/scripts/rotate-sni.sh" ]
}

@test "rotate-sni.sh: bash синтаксис без ошибок" {
    bash -n "$PROJECT_ROOT/scripts/rotate-sni.sh"
}

@test "mobile/scripts/ скрипты: существуют" {
    [ -f "$PROJECT_ROOT/mobile/scripts/deploy-mobile.sh" ]
    [ -f "$PROJECT_ROOT/mobile/scripts/generate-mobile-url.sh" ]
    [ -f "$PROJECT_ROOT/mobile/scripts/mobile-apply-routing.sh" ]
    [ -f "$PROJECT_ROOT/mobile/scripts/mobile-setup-termux.sh" ]
}

@test "mobile/scripts/ скрипты: bash синтаксис" {
    for f in deploy-mobile.sh generate-mobile-url.sh mobile-apply-routing.sh mobile-setup-termux.sh; do
        bash -n "$PROJECT_ROOT/mobile/scripts/$f"
    done
}
