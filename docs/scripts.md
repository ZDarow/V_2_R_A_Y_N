# Скрипты управления

Проект включает 9 shell-скриптов и общую библиотеку.

## lib/common.sh — общая библиотека (source)

Подключается через `source lib/common.sh`. Предоставляет:

| Функция | Описание |
|---------|----------|
| `download_with_retry <url> <dest> [retries=3] [delay=2]` | Скачивание с экспоненциальной задержкой (2→4→8с) |
| `verify_sha256 <data_file> <sha256_url>` | Проверка SHA256 (возвращает 0/1/2) |
| `acquire_lock [name]` | Блокировка от конкурентного запуска |
| `release_lock [name]` | Снятие блокировки |
| `log_init` | Инициализация логирования в `~/.local/share/v2rayN/logs/` |
| `log_info / log_warn / log_error / log_header` | Структурированный лог |
| `validate_dat <file>` | Проверка .dat файла (>10KB) |
| `detect_arch` | Определение архитектуры (64/arm64) |

## update-rules.sh — обновление geoip/geosite

Скачивает свежие `geoip.dat` и `geosite.dat` из репозитория
`runetfreedom/russia-v2ray-rules-dat` (ветка `release`).

### Флаги

| Флаг | Описание |
|------|----------|
| _(без флагов)_ | Однократное обновление правил |
| `--install-timer` | Установить systemd timer (еженедельное авто-обновление) |
| `--remove-timer` | Удалить systemd timer |
| `--status` | Показать статус: timer, версии файлов, последнее обновление |

### Использование

```bash
# Локально (после git clone):
./scripts/update-rules.sh

# Удалённо (из любого места):
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)

# Установить таймер:
./scripts/update-rules.sh --install-timer

# Проверить статус:
./scripts/update-rules.sh --status

# С другой директорией правил:
V2RAYN_BIN_DIR=/custom/path ./scripts/update-rules.sh
```

### Что делает

```
 1. Инициализация лога: ~/.local/share/v2rayN/logs/update-rules.log
 2. Блокировка конкурентного запуска (lock-файл)
 3. Скачивание geoip.dat       — retry 3x, SHA256, кэш fallback
 4. Скачивание geosite.dat     — retry 3x, SHA256, кэш fallback
 5. Валидация: файл существует, >10KB
 6. Установка новых правил
 7. Системный лог (journald) при запуске через systemd timer
```

### Переменные окружения

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `V2RAYN_BIN_DIR` | `~/.local/share/v2rayN/bin` | Директория с правилами |
| `LOG_DIR` | `~/.local/share/v2rayN/logs` | Директория логов |

## proxy-toggle.sh — вкл/выкл системного прокси

Включает и выключает системный прокси на Linux. Поддерживает GNOME и KDE.

### Использование

```bash
# Включить прокси (SOCKS5 127.0.0.1:10808, HTTP 127.0.0.1:10809):
./scripts/proxy-toggle.sh on

# Выключить прокси:
./scripts/proxy-toggle.sh off

# Показать статус:
./scripts/proxy-toggle.sh status
```

### Сценарии использования

**После запуска v2rayN:**
```bash
v2rayn &
sleep 2
~/.config/v2rayN/proxy-toggle.sh on
```

**Перед остановкой v2rayN:**
```bash
~/.config/v2rayN/proxy-toggle.sh off
pkill v2rayn
```

### GNOME (gsettings)

Включение:
```bash
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.http host '127.0.0.1'
gsettings set org.gnome.system.proxy.http port 10809
gsettings set org.gnome.system.proxy.https host '127.0.0.1'
gsettings set org.gnome.system.proxy.https port 10809
gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
gsettings set org.gnome.system.proxy.socks port 10808
gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']"
```

Выключение:
```bash
gsettings set org.gnome.system.proxy mode 'none'
```

### KDE (kwriteconfig)

```bash
kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 1
kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key httpProxy "http://127.0.0.1:10809"
kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key httpsProxy "http://127.0.0.1:10809"
kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key socksProxy "http://127.0.0.1:10808"
dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:""
```

Выключение:
```bash
kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 0
dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:""
```

## proxy_set_linux_sh.sh — библиотека установки прокси

Внутренняя библиотека, используемая `proxy-toggle.sh` через `source`.
Содержит функции для GNOME и KDE.

### Функции

| Функция | Параметры | Описание |
|---------|-----------|----------|
| `trim` | Имя переменной (по ссылке) | Удаляет пробельные символы из строки |
| `build_gsettings_array` | Строка (опционально) | Формирует gsettings-совместимый массив из строки |
| `set_gnome_proxy` | mode, ip, port, ignore_hosts | Настройка прокси GNOME |
| `set_kde_proxy` | mode, ip, port, ignore_hosts | Настройка прокси KDE |

### Использование как библиотеки

```bash
source scripts/proxy_set_linux_sh.sh
set_gnome_proxy "manual" "127.0.0.1" "10809" "localhost,127.0.0.0/8,::1,.ru,.su,.xn--p1ai"
```

## deploy-mobile.sh — деплой на Android

См. [mobile.md](mobile.md) — полная документация мобильного деплоя.

**Флаги:**
| Флаг | Описание |
|------|----------|
| `--zip` | Создать ZIP-архив |
| `--adb` | Push на телефон через USB |
| `--adb --apply` | Push + авто-открытие v2rayNG на телефоне |
| `--server` | HTTP-сервер для WiFi-передачи |
| `--rules-only` | Только geoip/geosite (без config) |

## mobile-apply-routing.sh — применение правил в v2rayNG (Android/Termux)

Автоматизирует импорт правил роутинга в v2rayNG через буфер обмена + `am start`.

### Использование

```bash
# Спросит какой пресет:
bash scripts/mobile-apply-routing.sh

# Прямое указание:
bash scripts/mobile-apply-routing.sh russia    # «Всё через прокси»
bash scripts/mobile-apply-routing.sh blocked   # «Только заблокированное»
```

### Что делает

```
 1. Загружает JSON правил из репозитория
 2. Валидирует JSON (python3 -m json.tool)
 3. Копирует содержимое в буфер обмена (termux-clipboard-set)
 4. Открывает v2rayNG (am start)
 5. Показывает deep link для подписки (v2rayng://install-sub/)
 6. Инструкция: 2 тапа до готовности
```

### Зависимости

- Termux, `curl`, `termux-api` (termux-clipboard-set)

## mobile-setup-termux.sh — полная настройка v2rayNG (Android/Termux)

Комплексный скрипт для настройки v2rayNG на Android без ПК.
Решает проблему «курицы и яйца» — работает до первого запуска прокси.

### Использование

```bash
# Установите Termux из F-Droid, затем:
pkg install curl
curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/mobile-setup-termux.sh | bash
```

### Что делает (v1.2.0)

```
 1. Проверка: Termux, v2rayNG, termux-api
 2. Загрузка geoip.dat / geosite.dat (retry 3x, offline fallback)
 3. Загрузка v2rayng-routing-russia.json / v2rayng-only-blocked.json
 4. Копирование всех файлов в Android/data/com.v2ray.ang/files/assets/
 5. Выбор пресета → копирование в буфер обмена
 6. Авто-открытие v2rayNG (am start)
 7. Deep link для подписки (v2rayng://install-sub/)
 8. Инструкция: 2 тапа для импорта + настройка IPOnDemand
```

## generate-mobile-url.sh — генерация VLESS URL

Генерирует VLESS-ссылку для импорта в v2rayNG из JSON-конфига Xray.

### Использование

```bash
./scripts/generate-mobile-url.sh [путь_к_config.json]
./scripts/generate-mobile-url.sh config/config-template-xray.json
```

Если аргумент не указан — использует `config/config-template-xray.json`.

## install.sh / uninstall.sh

См. [install.md](install.md) — документация установки и деинсталляции.

## Сводная таблица скриптов

| Скрипт | Назначение | Источник данных | Целевая платформа |
|--------|-----------|----------------|-------------------|
| `install.sh` | Установка v2rayN + конфиги + systemd timer | GitHub releases, runetfreedom | Linux (dpkg) |
| `uninstall.sh` | Удаление v2rayN + timer + кэш | — | Linux |
| `update-rules.sh` | Обновление geoip/geosite (retry, SHA256, lock) | runetfreedom release | Linux |
| `proxy-toggle.sh` | Вкл/выкл системного прокси | — | Linux (GNOME/KDE) |
| `proxy_set_linux_sh.sh` | Библиотека для прокси | — | Linux (GNOME/KDE) |
| `deploy-mobile.sh` | Деплой конфигов на Android (ZIP/ADB/HTTP) | runetfreedom + репозиторий | Android (v2rayNG) |
| `mobile-setup-termux.sh` | Полная автонастройка v2rayNG через Termux | runetfreedom + репозиторий | Android (Termux) |
| `mobile-apply-routing.sh` | Применение правил роутинга в 2 тапа | репозиторий | Android (Termux) |
| `generate-mobile-url.sh` | Генерация VLESS URL из JSON | — | Linux |
| `lib/common.sh` | Общая библиотека (retry, SHA256, lock, лог) | — | Linux |
