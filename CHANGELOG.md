# Changelog

Все значимые изменения проекта v2rayN Russia Setup.

## [Unreleased]

### Added
- `scripts/deploy-mobile.sh` — деплой конфигов на Android (ZIP/ADB/HTTP)
- `docs/` — полная техническая документация (7 файлов, 954 строки)
- `.editorconfig` — единый стиль кода
- `.gitattributes` — нормализация строк, diff-настройки

### Fixed
- `install.sh`: удалён fallback на .NET 8.0 (v2rayN 7.22+ требует только 10.0)
- `install.sh`: `dpkg -i` без `|| true`, проверка кода возврата
- `install.sh`: `validate_dat()` для .dat файлов
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
- `update-rules.sh`: SHA256-верификация загруженных .dat
- `update-rules.sh`: `CLEANUP_TMP` → `trap EXIT`
- `config/routing-russia.json`: ads-блокировка выше ru-blocked
- `.github/workflows/ci.yml`: `ludeeus/action-shellcheck@master` → `@2.0.0`
- `.github/workflows/ci.yml`: добавлен bash-syntax job
- `.github/workflows/ci.yml`: uninstall.sh в shellcheck

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
