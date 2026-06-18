# Установка и деинсталляция

Полное руководство по установке, настройке и удалению v2rayN Russia Setup.

## Содержание

1. [Системные требования](#системные-требования)
2. [Быстрая установка одной командой](#быстрая-установка-одной-командой)
3. [Локальная установка](#локальная-установка)
4. [Флаги установщика](#флаги-установщика)
5. [Что делает установщик — пошагово](#что-делает-установщик--пошагово)
6. [После установки](#после-установки)
7. [Деинсталляция](#деинсталляция)
8. [Обновление правил geoip/geosite](#обновление-правил-geoipgeosite)
9. [Установка на специфичные системы](#установка-на-специфичные-системы)

---

## Системные требования

| Компонент | Требование |
|-----------|-----------|
| **ОС** | Linux: Ubuntu 20.04+, Debian 11+, Fedora 38+, Arch Linux |
| **Архитектура** | x86_64 (amd64) или aarch64 (arm64) |
| **.NET Runtime** | 10.0+ (устанавливается автоматически) |
| **Память** | минимум 1 GB RAM, рекомендуется 2 GB |
| **Диск** | минимум 500 MB свободного места |
| **Интернет** | Требуется для загрузки компонентов при установке |

**Важно:** v2rayN — Linux-приложение. Для Android используется отдельный клиент v2rayNG — см. [mobile/docs/mobile.md](../mobile/docs/mobile.md).

---

## Быстрая установка одной командой

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)
```

Скрипт клонирует репозиторий во временную директорию, устанавливает все компоненты
и автоматически очищает временные файлы.

**Если GitHub заблокирован** — используйте зеркало репозитория.

---

## Локальная установка

```bash
# 1. Клонирование
git clone https://github.com/ZDarow/V_2_R_A_Y_N.git

# 2. Переход в директорию
cd V_2_R_A_Y_N

# 3. Установка
./install.sh
```

Локальный режим использует файлы из клона репозитория. Рекомендуется,
если вы планируете вносить изменения или запускать скрипты вручную.

---

## Флаги установщика

```bash
./install.sh [--help] [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]
```

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--force-reinstall` | Переустановить v2rayN, даже если уже установлен |
| `--skip-v2rayn` | Не устанавливать v2rayN (только конфиги, правила и подписки) |
| `--repo-url <url>` | URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N) |

### Примеры использования флагов

```bash
# Восстановить конфиги после обновления v2rayN
./install.sh --skip-v2rayn

# Переустановить всё с нуля
./install.sh --force-reinstall

# Установить из зеркала
./install.sh --repo-url https://gitlab.com/ZDarow/V_2_R_A_Y_N
```

---

## Что делает установщик — пошагово

Установщик полностью автоматизирован и пошагово выполняет:

### Шаг 1: Определение системы

- Архитектура: `uname -m` → `x86_64` / `aarch64`
- ОС: `/etc/os-release`
- Проверка, что скрипт **не запущен от root** (используется `sudo` по необходимости)

### Шаг 2: Установка зависимостей

Поддерживаемые пакетные менеджеры:

| Менеджер | Системы | Пакеты |
|----------|---------|--------|
| `apt-get` | Debian, Ubuntu, Mint | `git wget curl sqlite3 ca-certificates` |
| `dnf` | Fedora, RHEL | `git wget curl sqlite ca-certificates` |
| `pacman` | Arch, Manjaro | `git wget curl sqlite ca-certificates` |

Если ни один пакетный менеджер не определён — установка продолжается
с предупреждением. Установите зависимости вручную.

### Шаг 3: Установка .NET Runtime 10.0

- Проверка `dotnet --version` (требуется 10+)
- Если не установлен или версия ниже — установка `dotnet-runtime-10.0`
- На Debian/Ubuntu: официальный Microsoft-репозиторий
- На Fedora/Arch: предупреждение, установка вручную

**Важно:** v2rayN 7.22+ строго требует .NET 10.0.
Если ваша система не поддерживает .NET 10.0 — установка прервётся.

### Шаг 4: Установка v2rayN

1. Скачивание .deb-пакета с GitHub Releases (последняя версия)
2. Валидация: проверка, что файл скачан и не пуст
3. Установка: `sudo dpkg -i` (или копирование в `/opt/v2rayN/` для non-Debian)
4. При ошибке зависимостей: `sudo apt-get install -f`
5. Создание symlink: `~/.local/bin/v2rayn`

### Шаг 5: Установка правил geoip/geosite

- Источник: `runetfreedom/russia-v2ray-rules-dat` (ветка `release`)
- **Retry 3 попытки** с экспоненциальной задержкой (2 с → 4 с → 8 с)
- **SHA256 верификация** через `.sha256` файлы
- **Кэш** в `~/.cache/v2rayN/rules/` — offline fallback при недоступности сети
- Файлы устанавливаются в `~/.local/share/v2rayN/bin/`

### Шаг 6: Копирование конфигурационных файлов

| Файл | Назначение | Целевая директория |
|------|-----------|-------------------|
| `routing-russia.json` | Роутинг «Всё через прокси» | `~/.config/v2rayN/` |
| `only_blocked.json` | Роутинг «Только заблокированное» | `~/.config/v2rayN/` |
| `config-template-xray.json` | Шаблон Xray-core (DNS, policy, фрагментация) | `~/.local/share/v2rayN/binConfigs/` |

### Шаг 7: Установка скриптов управления + systemd timer

Устанавливаются в `~/.local/share/v2rayN/scripts/`:

| Скрипт | Назначение |
|--------|-----------|
| `proxy-toggle.sh` | Вкл/выкл системного прокси |
| `proxy_set_linux_sh.sh` | Библиотека настройки прокси |
| `update-rules.sh` | Обновление geoip/geosite с retry и SHA256 |

Создаётся алиас: `~/.local/bin/v2rayn-update-rules`

**Systemd timer** устанавливается для еженедельного авто-обновления правил:

```bash
# Расписание: еженедельно + случайная задержка до 6 часов
systemctl --user list-timers v2rayn-rules-update.timer
journalctl --user -u v2rayn-rules-update.service
```

### Шаг 8: Импорт подписок

В базу `guiNDB.db` добавляются 3 подписки:

| ID | Описание | Интервал |
|----|----------|----------|
| BLACK-RUS-001 | Чёрные списки РФ (весь трафик через VPN) | 1440 мин |
| WHITE-RUS-001 | Белые списки РФ | 1440 мин |
| WL-ZIENG2-001 | WL от zieng2 | 60 мин |

Используется `INSERT OR IGNORE` — существующие подписки не перезаписываются.

### Шаг 9: Настройка системного прокси

- GNOME/Cinnamon/XFCE/MATE: `gsettings set org.gnome.system.proxy`
- KDE Plasma: `kwriteconfig5`/`kwriteconfig6` + dbus-send
- Другие DE: предупреждение, настройка вручную

Параметры:
- SOCKS5 `127.0.0.1:10808`
- HTTP `127.0.0.1:10809`
- ignore-hosts: `.ru`, `.su`, `.xn--p1ai`, `localhost`, `127.0.0.0/8`, `::1`, `*.local`

### Шаг 10: Очистка

Удаление временных файлов. При pipe-режиме удаляется клон репозитория.

---

## После установки

```bash
# Запуск v2rayN
v2rayn &

# Включение системного прокси (GNOME/KDE)
~/.local/share/v2rayN/scripts/proxy-toggle.sh on

# Проверка состояния
~/.local/share/v2rayN/scripts/status.sh

# Или с помощью встроенного статуса
systemctl --user status v2rayn.service
```

---

## Деинсталляция

```bash
./uninstall.sh [--help] [--backup-dir <путь>]
```

### Флаги

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--backup-dir <путь>` | Сохранить конфиги в указанную директорию перед удалением |

### Что удаляется

1. **Системный прокси** — выключается (mode: `none`)
2. **Systemd timer** `v2rayn-rules-update` — отключается и удаляется
3. **Пакет v2rayN** — `dpkg -r` / `dnf remove` / `pacman -Rs`
4. **`/opt/v2rayN/`** — остатки после удаления пакета
5. **Symlink'и** — `~/.local/bin/v2rayn`, `~/.local/bin/v2rayn-update-rules`
6. **`~/.config/v2rayN/`** — все конфигурационные файлы
7. **`~/.local/share/v2rayN/`** — бинарники, скрипты, конфиги Xray, geoip/geosite
8. **`~/.cache/v2rayN/`** — кэш правил

**.NET Runtime не удаляется** — он может использоваться другими приложениями.

### Примеры

```bash
# Полное удаление
./uninstall.sh

# Удаление с бэкапом конфигов
./uninstall.sh --backup-dir ~/v2rayn-backup-2026

# Просмотр справки
./uninstall.sh --help
```

---

## Обновление правил geoip/geosite

После установки правила обновляются автоматически (systemd timer — еженедельно).
Ручное обновление:

```bash
# Локально
./scripts/update-rules.sh

# Удалённо
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)

# Статус таймера
systemctl --user list-timers v2rayn-rules-update.timer

# Просмотр лога
journalctl --user -u v2rayn-rules-update.service
```

---

## Установка на специфичные системы

### Ubuntu/Debian (рекомендуется)

Установка одной командой — полная поддержка .deb пакетов.

### Fedora/RHEL

install.sh определит `dnf`. v2rayN скопируется в `/opt/v2rayN/`,
так как официальный .deb не поддерживается. Все остальные компоненты
(конфиги, скрипты, systemd) устанавливаются штатно.

### Arch Linux

install.sh определит `pacman`. v2rayN скопируется в `/opt/v2rayN/`.
.NET 10.0 установите вручную: `sudo pacman -S dotnet-runtime`.

### Ubuntu на WSL2 (Windows)

1. Установите WSL2 с Ubuntu 24.04
2. Установите v2rayN через `curl | bash`
3. На Windows установите [v2rayN-Windows](https://github.com/2dust/v2rayN/releases)
4. Скопируйте конфиги в Windows-версию

### Linux Mint 22.x

Полностью поддерживается как Ubuntu-совместимая система.
