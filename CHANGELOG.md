# Changelog

Все значимые изменения проекта v2rayN Russia Setup.

## [Unreleased]

### Added
- `scripts/deploy-mobile.sh` — деплой конфигов на Android (ZIP/ADB/HTTP)
- `docs/` — полная техническая документация (7 файлов, 954 строки)
- `.editorconfig` — единый стиль кода
- `.gitattributes` — нормализация строк, diff-настройки
- `config/v2rayng-routing-russia.json` — формат JSON array для v2rayNG (Discussion #4761)
- `config/v2rayng-only-blocked.json` — формат JSON array (только заблокированное)
- `scripts/generate-mobile-url.sh` — генерация VLESS URL из JSON-конфига
- `scripts/mobile-setup-termux.sh` — автонастройка v2rayNG через Termux (v1.1.0)
- `lib/common.sh` — общая библиотека: retry-download, SHA256, блокировки, логирование
- `lib/systemd/v2rayn-rules-update.service` — systemd oneshot для авто-обновления
- `lib/systemd/v2rayn-rules-update.timer` — еженедельный таймер для geoip/geosite (6ч задержка)
- `scripts/mobile-apply-routing.sh` — применение правил роутинга в 2 тапа (clipboard + am start)

### Changed
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
- `scripts/deploy-mobile.sh`: README-Android.txt с методами A/B и IPOnDemand
- `scripts/mobile-setup-termux.sh` v1.2.0: retry 3x с экспоненциальной задержкой
- `scripts/mobile-setup-termux.sh` v1.2.0: offline fallback из assets/
- `scripts/mobile-setup-termux.sh` v1.2.0: авто-открытие v2rayNG через `am start`
- `scripts/mobile-setup-termux.sh` v1.2.0: deep link для подписки
- `deploy/index.html`: кнопки Copy JSON (fetch + clipboard API) для v2rayng-*.json
- `deploy/index.html`: deep link `v2rayng://install-sub/URL` для однокликового импорта
- `deploy/index.html`: CDN зеркало (jsDelivr)
- `uninstall.sh`: удаление systemd timer v2rayn-rules-update
- `uninstall.sh`: удаление кэша `~/.cache/v2rayN/`
- `uninstall.sh`: удаление symlink `v2rayn-update-rules`
- `uninstall.sh`: удаление shared библиотек

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
- `config/v2rayng-*.json`: добавлено поле `looked: false` (Discussion #4761)
- `config/config-template-xray.json`: убран хардкод «осталось 45 дней»
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
