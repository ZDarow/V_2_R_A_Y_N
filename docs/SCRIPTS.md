# Скрипты управления

Полный справочник всех скриптов, библиотек и утилит проекта.

## Содержание

1. [Общая библиотека — lib/common.sh](#общая-библиотека--libcommonsh)
2. [install.sh — установщик](#installsh--установщик)
3. [uninstall.sh — деинсталлятор](#uninstallsh--деинсталлятор)
4. [update-rules.sh — обновление geoip/geosite](#update-rulessh--обновление-geoipgeosite)
5. [proxy-toggle.sh — вкл/выкл системного прокси](#proxy-togglesh--вклвыкл-системного-прокси)
6. [proxy_set_linux_sh.sh — библиотека прокси](#proxy_set_linux_shsh--библиотека-прокси)
7. [status.sh — проверка состояния v2rayN](#statussh--проверка-состояния-v2rayn)
8. [diagnose.sh — сбор диагностики](#diagnosesh--сбор-диагностики)
9. [diagnose-network.sh — сетевая диагностика](#diagnose-networksh--сетевая-диагностика)
10. [kill-switch.sh — iptables kill-switch](#kill-switchsh--iptables-kill-switch)
11. [migrate-allowinsecure.sh — миграция сертификатов](#migrate-allowinsecuresh--миграция-сертификатов)
12. [apply-configs.sh — применение конфигураций](#apply-configsssh--применение-конфигураций)
13. [Сводная таблица](#сводная-таблица)

---

## Общая библиотека — lib/common.sh

**Путь:** `lib/common.sh`
**Назначение:** общая библиотека функций, используемых другими скриптами.
**Подключается:** `source lib/common.sh`

### Функции

| Функция | Описание | Возврат |
|---------|----------|---------|
| `download_with_retry <url> <dest> [retries=3] [delay=2]` | Скачивание с экспоненциальной задержкой (2→4→8с) | 0 успех, 1 ошибка |
| `verify_sha256 <data_file> <sha256_file>` | Проверка SHA256 хеша | 0 совпадает, 1 не совпадает, 2 файл не найден |
| `acquire_lock [name]` | Блокировка от конкурентного запуска (PID-файл) | 0 успех, 1 уже запущен |
| `release_lock [name]` | Снятие блокировки | 0 успех |
| `log_init` | Инициализация логирования в `~/.local/share/v2rayN/logs/` | — |
| `log_info <msg>` | Информационное сообщение в лог | — |
| `log_warn <msg>` | Предупреждение в лог | — |
| `log_error <msg>` | Ошибка в лог | — |
| `log_header <msg>` | Заголовок в лог | — |
| `validate_dat <file>` | Проверка .dat файла (>10KB, не пустой) | 0 валиден, 1 ошибка |
| `detect_arch` | Определение архитектуры (`x86_64` → `64`, `aarch64` → `arm64`) | Вывод в stdout |

### Пример использования

```bash
source lib/common.sh

if acquire_lock "my-script"; then
  if download_with_retry "https://example.com/file.dat" "/tmp/file.dat" 3 2; then
    if verify_sha256 "/tmp/file.dat" "/tmp/file.dat.sha256"; then
      log_info "Файл загружен и проверен"
    fi
  fi
  release_lock "my-script"
fi
```

---

## install.sh — установщик

**Путь:** `install.sh`
**Назначение:** полностью автоматизированная установка v2rayN на Linux.

### Режимы запуска

```bash
# Pipe-режим (curl | bash) — скачивает и устанавливает
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)

# Локальный режим — использует файлы из репозитория
git clone https://github.com/ZDarow/V_2_R_A_Y_N.git && cd V_2_R_A_Y_N && ./install.sh
```

### Флаги

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--force-reinstall` | Переустановить v2rayN, даже если уже установлен |
| `--skip-v2rayn` | Только конфиги, правила и подписки (без v2rayN) |
| `--repo-url <url>` | URL репозитория (для зеркал) |

### Что делает

```
 1. Определение системы (ОС, архитектура)
 2. Установка зависимостей (git, wget, curl, sqlite3)
 3. Установка .NET Runtime 10.0
 4. Установка v2rayN (dpkg / копирование)
 5. Установка geoip/geosite (retry 3x, SHA256, кэш)
 6. Копирование конфигурационных JSON
 7. Установка скриптов управления + systemd timer
 8. Импорт подписок в SQLite
 9. Настройка системного прокси
10. Очистка временных файлов
```

Подробнее: [INSTALL.md](INSTALL.md).

---

## uninstall.sh — деинсталлятор

**Путь:** `uninstall.sh`
**Назначение:** полное удаление v2rayN и всех компонентов.

### Флаги

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--backup-dir <путь>` | Сохранить конфиги в директорию перед удалением |

### Что удаляется

1. Системный прокси → выключается
2. Systemd timer `v2rayn-rules-update` → отключается и удаляется
3. Пакет v2rayN → `dpkg -r` / `dnf remove` / `pacman -Rs`
4. `/opt/v2rayN/` → остатки
5. Symlink'ы: `~/.local/bin/v2rayn`, `~/.local/bin/v2rayn-update-rules`
6. `~/.config/v2rayN/` → конфиги
7. `~/.local/share/v2rayN/` → данные, скрипты, geoip/geosite
8. `~/.cache/v2rayN/` → кэш

**.NET Runtime не удаляется.**

---

## update-rules.sh — обновление geoip/geosite

**Путь:** `scripts/update-rules.sh`
**Назначение:** скачивание свежих `geoip.dat` и `geosite.dat` из
`runetfreedom/russia-v2ray-rules-dat` (ветка `release`).

### Флаги

| Флаг | Описание |
|------|----------|
| _(без флагов)_ | Однократное обновление правил |
| `--install-timer` | Установить systemd timer (еженедельное авто-обновление) |
| `--remove-timer` | Удалить systemd timer |
| `--status` | Показать статус: timer, версии файлов, обновление |

### Использование

```bash
# Ручное обновление
./scripts/update-rules.sh

# Удалённое обновление (из любого места)
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)

# Установка таймера
./scripts/update-rules.sh --install-timer

# Статус
./scripts/update-rules.sh --status
```

### Переменные окружения

| Переменная | По умолчанию | Описание |
|-----------|-------------|----------|
| `V2RAYN_BIN_DIR` | `~/.local/share/v2rayN/bin` | Директория с правилами |
| `LOG_DIR` | `~/.local/share/v2rayN/logs` | Директория логов |

### Алгоритм работы

```
 1. Инициализация лога
 2. Блокировка конкурентного запуска (lock-файл)
 3. Скачивание geoip.dat — retry 3x, SHA256, кэш fallback
 4. Скачивание geosite.dat — retry 3x, SHA256, кэш fallback
 5. Валидация: файл >10KB
 6. Установка новых правил
 7. Логирование в journald (через systemd timer)
```

---

## proxy-toggle.sh — вкл/выкл системного прокси

**Путь:** `scripts/proxy-toggle.sh`
**Назначение:** включение/выключение системного прокси на GNOME и KDE.

### Использование

```bash
# Включить прокси
./scripts/proxy-toggle.sh on

# Выключить прокси
./scripts/proxy-toggle.sh off

# Статус
./scripts/proxy-toggle.sh status
```

### Параметры прокси

| Параметр | Значение |
|----------|----------|
| SOCKS5 | `127.0.0.1:10808` |
| HTTP | `127.0.0.1:10809` |
| HTTPS | `127.0.0.1:10809` |
| Ignore hosts | `localhost`, `127.0.0.0/8`, `::1`, `*.local`, `.ru`, `.su`, `.xn--p1ai` |

### Поддержка DE

| DE | Механизм | Статус |
|----|----------|--------|
| GNOME | `gsettings` | Полная |
| Cinnamon | `gsettings` (GNOME-совместим) | Полная |
| XFCE | `gsettings` | Полная |
| MATE | `gsettings` | Полная |
| KDE Plasma 5 | `kwriteconfig5` + dbus-send | Полная |
| KDE Plasma 6 | `kwriteconfig6` | Полная |
| Другие | — | Предупреждение |

---

## proxy_set_linux_sh.sh — библиотека прокси

**Путь:** `scripts/proxy_set_linux_sh.sh`
**Назначение:** внутренняя библиотека для установки системного прокси.
Используется `proxy-toggle.sh` через `source`.

### Функции

| Функция | Параметры | Описание |
|---------|-----------|----------|
| `trim <var_name>` | Имя переменной (по ссылке) | Удаляет пробельные символы |
| `build_gsettings_array <string>` | Строка | Формирует gsettings-массив |
| `set_gnome_proxy` | mode, ip, port, ignore_hosts | Установка прокси GNOME |
| `set_kde_proxy` | mode, ip, port, ignore_hosts | Установка прокси KDE |

### Пример использования как библиотеки

```bash
source scripts/proxy_set_linux_sh.sh
set_gnome_proxy "manual" "127.0.0.1" "10809" "localhost,127.0.0.0/8,::1,.ru,.su,.xn--p1ai"
```

---

## status.sh — проверка состояния v2rayN

**Путь:** `scripts/status.sh`
**Назначение:** всесторонняя проверка состояния v2rayN.

### Использование

```bash
~/.local/share/v2rayN/scripts/status.sh
```

### Что проверяет

| Проверка | Что анализирует |
|----------|-----------------|
| **Процесс** | Запущен ли v2rayn |
| **Порты** | Слушаются ли 10808 (SOCKS5) и 10809 (HTTP) |
| **Версия** | v2rayN и Xray-core |
| **Systemd** | Статус юнита v2rayn.service |
| **Правила** | Наличие geoip.dat / geosite.dat, их размер и дата |
| **Xray** | Статус Xray-core (runtime) |

### Пример вывода

```
v2rayN: RUNNING
  PID: 12345
  Ports: 10808 (SOCKS5) ✓, 10809 (HTTP) ✓
  Version: v2rayN 7.22.0 | Xray 26.3.27
  Systemd: v2rayn.service active (running)
  Rules: geoip.dat (OK, 4.2MB) geosite.dat (OK, 8.1MB)
```

---

## diagnose.sh — сбор диагностики

**Путь:** `scripts/diagnose.sh`
**Назначение:** сбор всей диагностической информации для GitHub Issues.

### Использование

```bash
./scripts/diagnose.sh
```

### Что собирает

- Вывод `status.sh`
- Логи v2rayN: `~/.local/share/v2rayN/Logs/`
- Лог journald: `journalctl --user -u v2rayn.service`
- Конфигурационные файлы
- Информацию о системе: ОС, ядро, .NET версия
- Список процессов

### Результат

Создаёт архив в текущей директории или stdout.
Архив можно прикрепить к GitHub Issue.

---

## diagnose-network.sh — сетевая диагностика

**Путь:** `scripts/diagnose-network.sh`
**Назначение:** глубокая диагностика сети для выявления проблем,
влияющих на работу VPN. Поддерживает 4 режима и 14 секций проверок.

**Версия:** v2.0.0 (2021 строка)

### Режимы запуска

```bash
# Полная диагностика (все 14 секций)
./scripts/diagnose-network.sh

# Быстрая проверка (ключевые секции)
./scripts/diagnose-network.sh --quick

# Только безопасность
./scripts/diagnose-network.sh --security

# Только связность (пинг, DNS, прокси)
./scripts/diagnose-network.sh --connectivity

# Только одна секция
./scripts/diagnose-network.sh --section 5

# JSON-вывод
./scripts/diagnose-network.sh --json
```

### Секции проверок

| № | Секция | Что проверяет |
|---|--------|---------------|
| 0 | Информация | Версия скрипта, ОС, ядро, время |
| 1 | Система | CPU, RAM, диски, uptime, NTP, SELinux/AppArmor, виртуализация |
| 2 | Интерфейсы | Состояние, MTU, скорость, duplex, TSO/GRO, ошибки, драйверы |
| 3 | Маршрутизация | Таблица маршрутизации, дефолтный шлюз, multicast |
| 4 | DNS | /etc/resolv.conf, systemd-resolved, DoH, DoT, скорость ответа |
| 5 | Прокси | Доступность SOCKS5 (:10808) и HTTP (:10809), ignore-hosts |
| 6 | Файрвол | iptables/nftables, kill-switch, открытые порты |
| 7 | Sysctl | 30+ параметров ядра (BBR, TFO, MTU, send_redirects, conntrack) |
| 8 | TUN | Модуль tun, устройства /dev/net/tun, Xray TUN |
| 9 | Соединения | conntrack, TCP-сокеты (ESTAB, LISTEN, TIME_WAIT) |
| 10 | Связность | Пинг 6 эндпоинтов, mtr path-diagnostics, speedtest, внешний IP |
| 11 | VPN | Xray, WireGuard, порты, внешний IP через прокси |
| 12 | Безопасность | Открытые порты, ARP-spoofing, IPv6 privacy, DHCP |
| 13 | Рекомендации | Итоговые рекомендации на основе scorer (pass/warn/fail) |

### Auto-install

Скрипт автоматически устанавливает необходимые пакеты при запуске:

| Менеджер | Поддержка |
|----------|-----------|
| apt-get | Полная |
| dnf | Полная |
| pacman | Полная |
| zypper | Полная |
| apk | Полная |
| emerge | Полная |

Проверяемые пакеты: `curl`, `jq`, `ethtool`, `mtr`, `netcat-openbsd`/`nmap-ncat`,
`conntrack`, `tcpdump`, `bind9-host`/`bind-utils`, `speedtest-cli`, `iw`, `sudo`.

### Форматы вывода

| Формат | Флаг | Описание |
|--------|------|----------|
| Цветной stdout | _(по умолчанию)_ | Цветной вывод в терминал |
| Лог-файл | _(всегда)_ | Плоский лог в `~/.local/share/v2rayN/logs/` |
| JSON | `--json` | Структурированный JSON-вывод |

### Пример вывода

```
══════════════════════════════════════════════════════════════════════
  СЕТЕВАЯ ДИАГНОСТИКА v2.0.0
  Режим: full
  Отчёт: /home/user/.local/share/v2rayN/logs/network-diagnostic-20260618-234957.log
══════════════════════════════════════════════════════════════════════

  Всего проверок: 63
  ✓ Успешно:     42
  ! Предупреждений: 21
  ✗ Ошибок:      0
  − Пропущено:   0

  16 рекомендаций:
    1. Отключите TSO: ethtool -K enp5s0 tso off
    2. Включите BBR: sysctl -w net.ipv4.tcp_congestion_control=bbr
    ...
```

### Системные рекомендации

На основе результатов проверок формируются рекомендации:

| Категория | Примеры |
|-----------|---------|
| **Сетевые интерфейсы** | TSO/GRO отключить, duplex mismatch |
| **DNS** | Медленный DNS, неверный resolv.conf |
| **Прокси** | Прокси не отвечает, нет ignore-hosts |
| **Файрвол** | Kill-switch не установлен, открытые порты |
| **Sysctl** | BBR не включён, TFO=1, send_redirects=1 |
| **TUN** | Модуль не загружен |
| **Безопасность** | ARP-spoofing, IPv6 без privacy |
| **VPN** | Xray не запущен, порты не слушаются |

---

## kill-switch.sh — iptables kill-switch

**Путь:** `scripts/kill-switch.sh`
**Назначение:** блокировка всего трафика вне прокси при отключении VPN.

### Использование

```bash
# Включить kill-switch
./scripts/kill-switch.sh on

# Выключить kill-switch
./scripts/kill-switch.sh off

# Статус
./scripts/kill-switch.sh status
```

### Принцип работы

```bash
# Создание цепочки V2RAYN
iptables -N V2RAYN
iptables -A OUTPUT -j V2RAYN

# Разрешить трафик только через порты v2rayN
iptables -A V2RAYN -o lo -j ACCEPT
iptables -A V2RAYN -p tcp --dport 10808 -j ACCEPT
iptables -A V2RAYN -p tcp --dport 10809 -j ACCEPT
iptables -A V2RAYN -m owner --uid-owner $(id -u v2rayn) -j ACCEPT

# Блокировать всё остальное
iptables -A V2RAYN -j REJECT
```

### Важно

- Kill-switch **не устанавливается автоматически**. Включите вручную.
- Требует `sudo` (работа с iptables).
- Работает только с iptables (не nftables без iptables-legacy).

---

## migrate-allowinsecure.sh — миграция сертификатов

**Путь:** `scripts/migrate-allowinsecure.sh`
**Назначение:** автоматическая замена `allowInsecure` на `pinnedPeerCertSha256`
в конфигурационных файлах.

### Использование

```bash
# Автоматическая миграция
./scripts/migrate-allowinsecure.sh

# Принудительная миграция (без запроса)
./scripts/migrate-allowinsecure.sh --force

# Показать изменения без применения
./scripts/migrate-allowinsecure.sh --dry-run
```

### Что делает

1. Сканирует конфигурационные файлы Xray-core
2. Находит `allowInsecure: true` / `allowInsecure: false`
3. Заменяет на `pinnedPeerCertSha256: ["<fingerprint>"]`
4. Создаёт бэкапы изменяемых файлов

---

## apply-configs.sh — применение конфигураций

**Путь:** `apply-configs.sh`
**Назначение:** ручное применение и восстановление конфигураций
из репозитория.

### Флаги

| Флаг | Описание |
|------|----------|
| `--all` | Применить все настройки |
| `--routing` | Только правила роутинга |
| `--dns` | Только настройки DNS |
| `--systemd` | Только systemd юниты |
| `--mobile` | Только для Android (через ADB) |
| `--dry-run` | Показать изменения без применения |

### Использование

```bash
# Применить всё
./apply-configs.sh --all

# Применить только роутинг (сухой прогон)
./apply-configs.sh --routing --dry-run

# Применить systemd юниты
./apply-configs.sh --systemd
```

### Бэкапы

Перед каждым изменением создаётся бэкап в `~/.cache/v2rayN-backups/`.

---

## Сводная таблица

| Скрипт | Назначение | Источник | Платформа |
|--------|-----------|----------|-----------|
| `install.sh` | Установка v2rayN + конфиги + systemd | GitHub Releases, runetfreedom | Linux |
| `uninstall.sh` | Удаление v2rayN + timer + кэш | — | Linux |
| `update-rules.sh` | Обновление geoip/geosite (retry, SHA256) | runetfreedom release | Linux |
| `proxy-toggle.sh` | Вкл/выкл системного прокси | — | Linux (GNOME/KDE) |
| `proxy_set_linux_sh.sh` | Библиотека для прокси (source) | — | Linux |
| `status.sh` | Проверка состояния v2rayN | systemd, порты | Linux |
| `diagnose.sh` | Сбор диагностики для Issue | — | Linux |
| `diagnose-network.sh` | Глубокая сетевая диагностика | система | Linux |
| `kill-switch.sh` | iptables kill-switch | iptables | Linux |
| `migrate-allowinsecure.sh` | Миграция allowInsecure → pinned | — | Linux |
| `apply-configs.sh` | Применение/восстановление конфигов | репозиторий | Linux |
| `lib/common.sh` | Общая библиотека (source) | — | Linux |

### Мобильные скрипты

| Скрипт | Назначение | Расположение |
|--------|-----------|-------------|
| `deploy-mobile.sh` | Деплой конфигов на Android (ADB/ZIP/HTTP) | `mobile/scripts/` |
| `generate-mobile-url.sh` | Генерация VLESS URL из JSON | `mobile/scripts/` |
| `mobile-apply-routing.sh` | Применение правил в v2rayNG | `mobile/scripts/` |
| `mobile-setup-termux.sh` | Автонастройка через Termux | `mobile/scripts/` |
