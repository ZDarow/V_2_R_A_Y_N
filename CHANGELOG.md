# Changelog

Все значимые изменения проекта v2rayN Russia Setup.

## [1.0.0] — 2026-06-20

### Added
- `scripts/detect-block-type.sh` — определение типа блокировки (SNI/IP/Combined/CGNAT/BGP/UDP)
- `scripts/rotate-sni.sh` — ротация SNI для обхода SNI-блокировок
- `scripts/setup-two-server.sh` — настройка двухсерверной схемы (РФ→зарубежье)
- `spec/mobile_spec.bash` — BATS тесты для мобильных скриптов (20 тестов)
- `.env` — централизованная конфигурация проекта
- `CONTRIBUTING.md` — правила для контрибьюторов
- `.github/ISSUE_TEMPLATE.md` — шаблон для issue
- `.github/PULL_REQUEST_TEMPLATE.md` — шаблон для PR
- Git tag `v1.0.0` — первый стабильный релиз

### Changed
- `scripts/mobile-netcheck.sh` — расширен: CGNAT, BGP ASN, UDP порты, SNI vs IP тест (16 секций)
- `scripts/optimize-mobile.sh` — переписан: автоподбор MTU, fragment TLS (tlshello), ротация SNI по whitelist-доменам, two-server инструкция
- `.github/workflows/ci.yml` — восстановлен shellcheck (был случайно перезаписан), добавлены mobile-скрипты, CONTRIBUTING.md, валидация mobile/config/*.json
- `README.md` — добавлены detect-block-type.sh, rotate-sni.sh, setup-two-server.sh
- `subscriptions/README.md` — добавлены Tor Bridges (5 типов), hxehex whitelist, SourceHut, Bitbucket, Yandex
- `config-template-xray.json` — обновлён с учётом fragment TLS

### Removed
- `1.txt` — Wireshark PCAP дамп (7.8 МБ, удалён из рабочей директории, в .gitignore через *.txt)

## [Unreleased]

### Added
- `docs/ARCHITECTURE.md` — архитектура проекта: компоненты, потоки данных, схемы
- `docs/USAGE.md` — инструкция по ежедневному использованию
- `docs/TROUBLESHOOTING.md` — устранение неполадок (8 категорий проблем)
- `docs/CONFIGURATION.md` — детальное описание всех конфигурационных файлов
- `docs/INDEX.md` — карта документации с навигацией
- `scripts/diagnose-network.sh` — полная сетевая диагностика v2.0.0 (14 секций, 2021 строка)
- `scripts/deploy-mobile.sh` — деплой конфигов на Android (ZIP/ADB/HTTP)
- `.editorconfig` — единый стиль кода
- `.gitattributes` — нормализация строк, diff-настройки
- `config/v2rayng-routing-russia.json` — формат JSON array для v2rayNG
- `config/v2rayng-only-blocked.json` — формат JSON array (только заблокированное)
- `scripts/generate-mobile-url.sh` — генерация VLESS URL из JSON-конфига
- `scripts/mobile-setup-termux.sh` — автонастройка v2rayNG через Termux (v1.1.0)
- `lib/common.sh` — общая библиотека: retry-download, SHA256, блокировки, логирование
- `lib/systemd/v2rayn-rules-update.service` — systemd oneshot для авто-обновления
- `lib/systemd/v2rayn-rules-update.timer` — еженедельный таймер для geoip/geosite (6ч задержка)
- `scripts/mobile-apply-routing.sh` — применение правил роутинга в 2 тапа
- `.github/workflows/ci.yml`: jobs actionlint, yamllint, docs в markdown-check
- `.yamllint.yml` — конфигурация yamllint для CI

### Changed
- `docs/` — полная переработка документации: 8 файлов вместо 5, +300% объёма
- `docs/install.md` — расширена: Fedora/Arch, WSL2, специфичные системы
- `docs/scripts.md` — расширена: добавлены status.sh, diagnose.sh, diagnose-network.sh, kill-switch.sh, migrate-allowinsecure.sh, apply-configs.sh
- `docs/faq.md` — дополнена: fingerprint, allowInsecure, Let's Encrypt
- `README.md` — полностью переработан: карта документации, быстрый старт, ссылки
- `install.sh`: замена `download_file()` на `download_with_retry()` (3 попытки)
- `install.sh`: SHA256 верификация geoip/geosite при загрузке
- `install.sh`: кэш `~/.cache/v2rayN/rules/` для offline fallback
- `install.sh`: копирование `v2rayng-routing-russia.json`, `v2rayng-only-blocked.json`
- `install.sh`: установка `update-rules.sh` + systemd timer
- `install.sh`: алиас `~/.local/bin/v2rayn-update-rules`
- `install.sh`: BASH_SOURCE fallback для pipe-режима
- `install.sh`: MS repository для dotnet-runtime-10.0 на свежих системах
- `scripts/update-rules.sh`: полный рефакторинг — retry 3x, SHA256, кэш fallback, lock
- `scripts/update-rules.sh`: аргументы `--install-timer`, `--remove-timer`, `--status`
- `scripts/update-rules.sh`: логирование в `~/.local/share/v2rayN/logs/`
- `scripts/deploy-mobile.sh`: флаг `--apply` для авто-открытия v2rayNG после ADB push
- `scripts/deploy-mobile.sh`: копирование `v2rayng-routing-russia.json`, `v2rayng-only-blocked.json`
- `scripts/mobile-setup-termux.sh` v1.2.0: retry 3x, offline fallback, auto-open, deep link
- `deploy/index.html`: Copy JSON + clipboard API, deep link, CDN jsDelivr
- `uninstall.sh`: удаление systemd timer, кэша, symlink, shared библиотек
- `apply-configs.sh`: исправлены 3 предупреждения SC2155 (shellcheck clean)

### Fixed
- `install.sh`: удалён fallback на .NET 8.0 (v2rayN 7.22+ требует только 10.0)
- `install.sh`: `dpkg -i` без `|| true`, проверка кода возврата
- `install.sh`: удалён мёртвый код `rules/` (.gitignored)
- `install.sh`: `gsettings list-schemas` проверка схемы GNOME
- `install.sh`: `$EUID` → `$(id -u)` (POSIX)
- `install.sh`: `apt-get update` без `2>/dev/null`
- `uninstall.sh`: таймаут 30с на подтверждение
- `uninstall.sh`: поддержка `dnf` и `pacman` для удаления
- `uninstall.sh`: `--help` и `--backup-dir <путь>`
- `proxy-toggle.sh`: ignore-hosts формируется из переменной (был хардкод)
- `proxy-toggle.sh`: `set -euo pipefail`
- `proxy_set_linux_sh.sh`: удалён ftp из протоколов
- `proxy_set_linux_sh.sh`: `set -euo pipefail`
- `update-rules.sh`: `CLEANUP_TMP` → `trap EXIT`, SHA256, retry
- `update-rules.sh`: lock-файл для предотвращения конкурентного запуска
- `config/routing-russia.json`: ads-блокировка выше ru-blocked
- `config/v2rayng-*.json`: добавлено поле `looked: false`
- `config/config-template-xray.json`: убран хардкод «осталось 45 дней»
- `scripts/diagnose-network.sh`: grep -c + || echo 0 → дублирование вывода
- `scripts/diagnose-network.sh`: systemd-detect-virt дублирование "none"
- `scripts/diagnose-network.sh`: ss -tan grep 'tcp' → wc -l (нет 'tcp' в выводе)
- `apply-configs.sh`: 3 предупреждения SC2155 (declare and assign separately)
- `.github/workflows/ci.yml`: `ludeeus/action-shellcheck@master` → `@2.0.0`
- `.github/workflows/ci.yml`: добавлен bash-syntax job
- `.github/workflows/ci.yml`: uninstall.sh в shellcheck
- `.github/workflows/ci.yml`: покрытие всех config/*.json, всех .sh, всех .md

## [1.0.0] — 2026-06-15

### Added
- `install.sh` — полностью автоматизированный установщик v2rayN
- `uninstall.sh` — деинсталлятор с отключением прокси
- `config/routing-russia.json` — роутинг «Всё через прокси»
- `config/only_blocked.json` — роутинг «Только заблокированное»
- `config/config-template-xray.json` — шаблон Xray-core (REALITY, fragment)
- `scripts/update-rules.sh` — обновление geoip/geosite из runetfreedom
- `scripts/proxy-toggle.sh` — вкл/выкл системного прокси (GNOME + KDE)
- `scripts/proxy_set_linux_sh.sh` — библиотека прокси
- `subscriptions/README.md` — список подписок
- `.github/workflows/ci.yml` — CI: shellcheck, JSON валидация, markdown
- Поддержка x86_64 и aarch64
- Поддержка apt/dnf/pacman
- Импорт 4 подписок в SQLite
- allowInsecure warning
