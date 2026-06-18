# Установка и деинсталляция

## install.sh — автоматический установщик

### Режимы запуска

**Pipe-режим (curl | bash):**
```bash
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)
```
Скрипт клонирует репозиторий во временную директорию, выполняет установку и очищает временные файлы.

**Локальный режим:**
```bash
git clone https://github.com/ZDarow/V_2_R_A_Y_N.git
cd V_2_R_A_Y_N
./install.sh
```
Скрипт использует файлы из локального клона. Не требует перезагрузки после клонирования.

### Флаги

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--force-reinstall` | Переустановить v2rayN, даже если уже установлен |
| `--skip-v2rayn` | Не устанавливать v2rayN (только конфиги, правила и подписки) |
| `--repo-url <url>` | URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N) |

### Что делает install.sh

```
 1. Определение системы     — архитектура (x86_64/aarch64), OS, root-проверка
 2. Установка зависимостей  — git, wget, curl, sqlite3, ca-certificates
 3. Установка .NET 10.0     — dotnet-runtime-10.0 (+ MS repo fallback)
 4. Установка v2rayN        — загрузка .deb с GitHub, dpkg -i, symlink
 5. Установка geoip/geosite — retry 3x, SHA256 верификация, кэш fallback
 6. Конфигурация            — 3 JSON: routing, only_blocked, config-template
 7. Скрипты управления      — proxy-toggle, proxy_set, update-rules (+ systemd timer)
 8. Импорт подписок         — 4 подписки в SQLite (guiNDB.db)
 9. Системный прокси        — GNOME (gsettings) или KDE (kwriteconfig)
10. Очистка                 — удаление временных файлов
```

### Детали каждого шага

#### 1. Определение системы
- Архитектура определяется через `uname -m`: `x86_64` → deb-архитектура `64`, `aarch64` → `arm64`
- OS определяется через `/etc/os-release`
- Скрипт проверяет, что он НЕ запущен от root (используется `sudo` по мере необходимости)

#### 2. Установка зависимостей
Поддерживаемые пакетные менеджеры:
- `apt-get` (Debian/Ubuntu) — `git wget curl sqlite3 ca-certificates`
- `dnf` (Fedora/RHEL) — `git wget curl sqlite ca-certificates`
- `pacman` (Arch) — `git wget curl sqlite ca-certificates`

Если ни один пакетный менеджер не сработал, установка продолжается с предупреждением.

#### 3. Установка .NET 10.0
- Проверяется наличие `dotnet` и версия (должна быть 10+)
- Если не установлен или версия ниже — устанавливается `dotnet-runtime-10.0`
- Fallback на более старые версии .NET **отсутствует** — v2rayN 7.22+ строго требует .NET 10.0

#### 4. Установка v2rayN
- Скачивание: сначала GitHub API (определяет последний релиз), затем fallback на прямой URL
- Валидация: проверяется, что файл скачан и не пуст
- Установка: `sudo dpkg -i`, при ошибке зависимостей — `sudo apt-get install -f`
- После установки: `v2rayn --version`, создание symlink в `~/.local/bin/`

#### 5. Правила роутинга (geoip/geosite)
- Скачиваются из `runetfreedom/russia-v2ray-rules-dat` (ветка `release`)
- **Retry 3 попытки** с экспоненциальной задержкой (2→4→8с) при сетевых ошибках
- **SHA256 верификация** через `.sha256` файлы (если доступны)
- **Кэширование** в `~/.cache/v2rayN/rules/` — при неудаче загрузки используется кэш
- При полном отсутствии файла — предупреждение, установка продолжается

#### 6. Конфигурация
Копируются файлы в целевые директории:
| Файл | Назначение | Целевая директория |
|------|-----------|-------------------|
 | `routing-russia.json` | Роутинг «Всё через прокси» | `~/.config/v2rayN/` |
| `only_blocked.json` | Роутинг «Только заблокированное» | `~/.config/v2rayN/` |
| `config-template-xray.json` | Шаблон Xray-core | `~/.local/share/v2rayN/binConfigs/` |

#### 7. Скрипты управления + авто-обновление

Устанавливаются в `~/.local/share/v2rayN/scripts/`:

| Скрипт | Назначение |
|--------|-----------|
| `proxy-toggle.sh` | Вкл/выкл системного прокси (GNOME/KDE) |
| `proxy_set_linux_sh.sh` | Библиотека настройки прокси |
| `update-rules.sh` | Обновление geoip/geosite с retry, SHA256, кэшем |

Создаётся алиас:
```bash
~/.local/bin/v2rayn-update-rules   # → ~/.local/share/v2rayN/scripts/update-rules.sh
```

**Systemd timer** для авто-обновления правил:
```bash
# Timer устанавливается автоматически при install.sh
systemctl --user list-timers v2rayn-rules-update.timer
# Расписание: еженедельно + случайная задержка до 6ч
# Просмотр лога:
journalctl --user -u v2rayn-rules-update.service
```

#### 8. Импорт подписок
Создаётся таблица `SubItem` в `guiNDB.db` (если не существует) и добавляются подписки:
1. **BLACK-RUS-001** — Чёрные списки РФ (весь трафик через VPN), интервал 1440 мин
2. **WHITE-RUS-001** — Белые списки РФ, интервал 1440 мин
3. **WL-ZIENG2-001** — WL от zieng2, интервал 60 мин

Используется `INSERT OR IGNORE` — существующие подписки не перезаписываются.

#### 9. Системный прокси
- GNOME/Cinnamon/XFCE/MATE: `gsettings set org.gnome.system.proxy`
- KDE Plasma: `kwriteconfig5`/`kwriteconfig6` + dbus-send
- Другие DE: предупреждение, настройка вручную

Параметры: SOCKS5 127.0.0.1:10808, HTTP 127.0.0.1:10809, ignore-hosts: `.ru`, `.su`, `.xn--p1ai`.

## uninstall.sh — деинсталлятор

### Флаги

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--backup-dir <путь>` | Сохранить конфиги в директорию перед удалением |

### Что удаляется

1. **Системный прокси** — выключается (mode 'none')
2. **Systemd timer v2rayn-rules-update** — отключается и удаляется
3. **Пакет v2rayN** — `dpkg -r` / `dnf remove` / `pacman -Rs`
4. **/opt/v2rayN/** — остатки после удаления пакета
5. **~/.local/bin/v2rayn, ~/.local/bin/v2rayn-update-rules** — symlink
6. **~/.config/v2rayN/** — все конфиги
7. **~/.local/share/v2rayN/** — бинарники, скрипты, конфиги Xray
8. **~/.cache/v2rayN/** — кэш правил geoip/geosite

**.NET Runtime не удаляется** — он может использоваться другими приложениями.

### Бэкап

При указании `--backup-dir <путь>` перед удалением создаётся копия:
- `~/.config/v2rayN/` → `$BACKUP_DIR/v2rayN/`
- `~/.local/share/v2rayN/` → `$BACKUP_DIR/v2rayN/`

## Системные требования

| Компонент | Требование |
|-----------|-----------|
| ОС | Linux (Ubuntu 20.04+, Debian 11+, Fedora 38+, Arch) |
| Архитектура | x86_64 (amd64) или aarch64 (arm64) |
| .NET Runtime | 10.0+ (устанавливается автоматически на Debian/Ubuntu) |
| Память | минимум 1 GB RAM, рекомендуется 2 GB |
| Диск | минимум 500 MB свободного места |
