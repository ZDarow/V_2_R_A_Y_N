#!/usr/bin/env bash
# apply-configs.sh — Применение настроек из репозитория V_2_R_A_Y_N
# Использование: ./apply-configs.sh [--all|--routing|--dns|--systemd|--mobile] [--dry-run]

set -euo pipefail

# ─── Цвета и логирование ────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" >&2; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

# ─── Пути ────────────────────────────────────────────────────────────
_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR="$_script_dir"
readonly V2RAYN_CONFIG_DIR="${HOME}/.config/v2rayN"
readonly SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
_backup_ts="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="${HOME}/.cache/v2rayN-backups/${_backup_ts}"
readonly ANDROID_DIR="${SCRIPT_DIR}/mobile/config"

# ─── Флаги ───────────────────────────────────────────────────────────
APPLY_ALL=false
APPLY_ROUTING=false
APPLY_DNS=false
APPLY_SYSTEMD=false
APPLY_MOBILE=false
DRY_RUN=false

# ─── Парсинг аргументов ──────────────────────────────────────────────
usage() {
    cat <<EOF
Использование: $0 [ОПЦИИ]

Опции:
  --all          Применить все настройки (по умолчанию)
  --routing      Только правила роутинга
  --dns          Только настройки DNS
  --systemd      Только systemd юниты
  --mobile       Только для Android (через ADB)
  --dry-run      Показать, что будет сделано, без изменений
  -h, --help     Эта справка

Примеры:
  $0 --routing --dry-run    # Проверить, что изменится в роутинге
  $0 --all                  # Применить всё
  $0 --mobile               # Отправить конфиги на телефон
EOF
    exit 0
}

[[ $# -eq 0 ]] && APPLY_ALL=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)      APPLY_ALL=true ;;
        --routing)  APPLY_ROUTING=true ;;
        --dns)      APPLY_DNS=true ;;
        --systemd)  APPLY_SYSTEMD=true ;;
        --mobile)   APPLY_MOBILE=true ;;
        --dry-run)  DRY_RUN=true ;;
        -h|--help)  usage ;;
        *)          warn "Неизвестный аргумент: $1"; usage ;;
    esac
    shift
done

# Если не выбран ни один режим — применяем всё
if ! $APPLY_ROUTING && ! $APPLY_DNS && ! $APPLY_SYSTEMD && ! $APPLY_MOBILE && $APPLY_ALL; then
    APPLY_ROUTING=true
    APPLY_DNS=true
    APPLY_SYSTEMD=true
fi

# ─── Вспомогательные функции ─────────────────────────────────────────
backup_file() {
    local src="$1"
    [[ ! -e "$src" ]] && return 0
    mkdir -p "$BACKUP_DIR"
    local bname
    bname="$(basename "$src")"
    local dest="${BACKUP_DIR}/${bname}"
    if $DRY_RUN; then
        info "[dry-run] Бэкап: $src → $dest"
    else
        cp -a "$src" "$dest"
        info "Бэкап создан: $(basename "$src")"
    fi
    return 0
}

validate_json() {
    local file="$1"
    if command -v jq &>/dev/null; then
        if ! jq empty "$file" 2>/dev/null; then
            error "Невалидный JSON: $file"
        fi
    else
        warn "jq не установлен — пропуск валидации JSON"
    fi
    return 0
}

safe_copy() {
    local src="$1"
    local dest="$2"
    [[ ! -f "$src" ]] && { warn "Источник не найден: $src"; return 1; }
    
    if $DRY_RUN; then
        info "[dry-run] Копирование: $src → $dest"
        return 0
    fi
    
    mkdir -p "$(dirname "$dest")"
    [[ -f "$dest" ]] && backup_file "$dest"
    cp -f "$src" "$dest"
    info "Применено: $(basename "$dest")"
    return 0
}

# ─── Применение роутинга ─────────────────────────────────────────────
apply_routing() {
    step "Применение правил роутинга"
    
    local routing_dir="${SCRIPT_DIR}/config"
    if [[ ! -d "$routing_dir" ]]; then
        warn "Папка config/ не найдена"
        return 0
    fi
    
    local count=0
    for f in "$routing_dir"/routing-*.json "$routing_dir"/only_blocked.json; do
        [[ ! -f "$f" ]] && continue
        validate_json "$f"
        safe_copy "$f" "${V2RAYN_CONFIG_DIR}/$(basename "$f")"
        count=$((count + 1))
    done
    
    if [[ $count -eq 0 ]]; then
        warn "Файлы роутинга не найдены в $routing_dir"
    fi
    
    return 0
}

# ─── Применение DNS ──────────────────────────────────────────────────
apply_dns() {
    step "Применение настроек DNS"
    
    local template="${SCRIPT_DIR}/config/config-template-xray.json"
    if [[ ! -f "$template" ]]; then
        warn "Шаблон DNS не найден: $template"
        return 0
    fi
    
    validate_json "$template"
    
    # Ищем активный конфиг v2rayN
    local active_config=""
    if [[ -d "$V2RAYN_CONFIG_DIR" ]]; then
        active_config=$(find "$V2RAYN_CONFIG_DIR" -maxdepth 2 -name "config.json" -print -quit 2>/dev/null || true)
    fi
    
    if [[ -n "$active_config" ]]; then
        info "Найден активный конфиг: $active_config"
        # Обновляем только секцию dns, не трогая outbounds/inbounds
        if command -v jq &>/dev/null; then
            local new_dns
            new_dns=$(jq '.dns' "$template")
            if $DRY_RUN; then
                info "[dry-run] Обновление DNS в $active_config"
            else
                backup_file "$active_config"
                local tmp
                tmp=$(mktemp)
                jq --argjson dns "$new_dns" '.dns = $dns' "$active_config" > "$tmp"
                mv "$tmp" "$active_config"
                info "DNS обновлён в активном конфиге"
            fi
        else
            warn "jq не установлен — копирую шаблон целиком"
            safe_copy "$template" "$active_config"
        fi
    else
        info "Активный конфиг не найден — копирую шаблон как config.json"
        safe_copy "$template" "${V2RAYN_CONFIG_DIR:-${HOME}/.config/v2rayN}/config.json"
    fi
    
    return 0
}

# ─── Применение systemd ──────────────────────────────────────────────
apply_systemd() {
    step "Применение systemd юнитов"
    
    local systemd_src="${SCRIPT_DIR}/lib/systemd"
    if [[ ! -d "$systemd_src" ]]; then
        warn "Папка lib/systemd/ не найдена"
        return 0
    fi
    
    mkdir -p "$SYSTEMD_USER_DIR"
    
    for f in "$systemd_src"/*.service "$systemd_src"/*.timer; do
        [[ ! -f "$f" ]] && continue
        local base
        base=$(basename "$f")
        local dest="${SYSTEMD_USER_DIR}/$base"
        
        # Подставляем реальный путь HOME в ExecStart
        if $DRY_RUN; then
            info "[dry-run] Установка юнита: $base"
        else
            backup_file "$dest"
            sed "s|%h|${HOME}|g; s|%t|${XDG_RUNTIME_DIR:-/run/user/$(id -u)}|g" "$f" > "$dest"
            info "Юнит установлен: $base"
        fi
    done
    
    if ! $DRY_RUN; then
        if systemctl --user daemon-reload 2>/dev/null; then
            info "systemd daemon перезагружен"
        else
            warn "Не удалось перезагрузить systemd"
        fi
    fi
    
    return 0
}

# ─── Применение для Android ──────────────────────────────────────────
apply_mobile() {
    step "Применение настроек для Android"
    
    if ! command -v adb &>/dev/null; then
        error "adb не установлен. Установите: sudo apt install android-tools-adb"
    fi
    
    if ! adb devices 2>/dev/null | awk '$2 == "device" {found=1; exit} END {exit !found}'; then
        error "Android-устройство не подключено. Проверьте USB-отладку."
    fi
    
    if [[ ! -d "$ANDROID_DIR" ]]; then
        warn "Папка android/ не найдена"
        return 0
    fi
    
    local device_id
    device_id=$(adb devices 2>/dev/null | awk '$2 == "device" {print $1; exit}')
    info "Устройство: $device_id"
    
    # Определяем пакет v2rayNG
    local pkg="com.v2ray.ang"
    if ! adb shell pm list packages | grep -q "$pkg"; then
        pkg="com.github.kr328.fcm.push"  # альтернативный пакет
        if ! adb shell pm list packages | grep -q "$pkg"; then
            error "v2rayNG не установлен на устройстве"
        fi
    fi
    
    local assets_dir="/data/data/${pkg}/assets"
    info "Целевая папка: $assets_dir"
    
    local errors=0
    for f in "$ANDROID_DIR"/*.json "$ANDROID_DIR"/*.dat; do
        [[ ! -f "$f" ]] && continue
        local name
        name=$(basename "$f")
        
        if $DRY_RUN; then
            info "[dry-run] Push: $name → $assets_dir/"
        else
            if adb push "$f" "${assets_dir}/${name}" >/dev/null 2>&1; then
                info "  ✓ $name"
            else
                warn "  ✗ $name (попробуйте с root)"
                errors=$((errors + 1))
            fi
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        info "Все файлы скопированы на устройство"
    else
        warn "Ошибок: $errors"
    fi
    
    return 0
}

# ─── Перезапуск сервиса ──────────────────────────────────────────────
restart_service() {
    if $DRY_RUN; then
        info "[dry-run] Перезапуск v2rayn.service"
        return 0
    fi
    
    if systemctl --user is-active --quiet v2rayn.service 2>/dev/null; then
        if systemctl --user restart v2rayn.service; then
            info "v2rayN перезапущен"
        else
            warn "Не удалось перезапустить v2rayN"
        fi
    else
        warn "v2rayN не запущен — пропуск перезапуска"
    fi
    
    return 0
}

# ─── Основной поток ──────────────────────────────────────────────────
main() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  V_2_R_A_Y_N — Применение настроек            ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo
    info "Режим: $(if $DRY_RUN; then echo 'DRY-RUN (без изменений)'; else echo 'LIVE'; fi)"
    info "Репозиторий: $SCRIPT_DIR"
    
    if $APPLY_ROUTING; then
        apply_routing
    fi
    
    if $APPLY_DNS; then
        apply_dns
    fi
    
    if $APPLY_SYSTEMD; then
        apply_systemd
    fi
    
    if $APPLY_MOBILE; then
        apply_mobile
    fi
    
    # Перезапускаем только если не mobile и не dry-run
    if ! $APPLY_MOBILE && ! $DRY_RUN; then
        step "Перезапуск сервиса"
        restart_service
    fi
    
    echo
    info "Готово! Бэкапы: ${BACKUP_DIR:-'не создавались (dry-run)'}"
    
    if $DRY_RUN; then
        echo
        warn "Это был dry-run. Для реального применения уберите флаг --dry-run"
    fi
    
    return 0
}

main "$@"