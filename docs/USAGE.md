# Использование

Руководство по ежедневной работе с v2rayN Russia Setup.

## Содержание

1. [Запуск v2rayN](#запуск-v2rayn)
2. [Системный прокси](#системный-прокси)
3. [Режимы роутинга](#режимы-роутинга)
4. [Обновление правил](#обновление-правил)
5. [Мониторинг](#мониторинг)
6. [Диагностика сети](#диагностика-сети)
7. [Kill-switch (аварийное отключение)](#kill-switch-аварийное-отключение)
8. [Миграция allowInsecure → pinnedPeerCertSha256](#миграция-allowinsecure--pinnedpeercertsha256)
9. [Применение конфигов](#применение-конфигов)

---

## Запуск v2rayN

После установки v2rayN доступен как команда `v2rayn`:

```bash
# Запуск в фоне
v2rayn &

# Или через systemd (если установлен сервис)
systemctl --user start v2rayn.service

# Автозапуск при входе в систему
systemctl --user enable v2rayn.service
```

После запуска v2rayN слушает порты:
- **SOCKS5**: `127.0.0.1:10808` — для приложений с поддержкой SOCKS5
- **HTTP**: `127.0.0.1:10809` — для системного прокси и HTTP-клиентов

### Выбор сервера

После запуска откроется GUI v2rayN. Выберите сервер из списка подписок
(они импортируются автоматически при установке). Нажмите **Enter** или
дважды кликните для активации сервера.

### Автозапуск

v2rayN интегрируется в систему через XDG Autostart:

```bash
# Проверить автозапуск
ls -la ~/.config/autostart/v2rayn.desktop

# Файл создаётся при установке
# Содержимое: запуск v2rayn со скрытым окном
```

---

## Системный прокси

v2rayN работает как прокси-сервер на локальной машине. Чтобы направить
весь трафик системы через v2rayN, включите системный прокси.

### Включение/выключение

```bash
# Включить прокси
~/.local/share/v2rayN/scripts/proxy-toggle.sh on

# Выключить прокси
~/.local/share/v2rayN/scripts/proxy-toggle.sh off

# Проверить статус
~/.local/share/v2rayN/scripts/proxy-toggle.sh status
```

Поддерживаемые DE: **GNOME** (gsettings), **KDE** (kwriteconfig).

### Ручная настройка (для других DE)

Настройте прокси в вашем окружении:

| Параметр | Значение |
|----------|----------|
| SOCKS5 Host | `127.0.0.1` |
| SOCKS5 Port | `10808` |
| HTTP Host | `127.0.0.1` |
| HTTP Port | `10809` |
| Ignore hosts | `localhost, 127.0.0.0/8, ::1, *.local, .ru, .su, .xn--p1ai` |

### Автоматизация

Рекомендуется включить прокси **после** запуска v2rayN
и выключить **перед** остановкой:

```bash
v2rayn &
sleep 2
~/.local/share/v2rayN/scripts/proxy-toggle.sh on

# ... работа с v2rayN ...

~/.local/share/v2rayN/scripts/proxy-toggle.sh off
pkill v2rayn
```

---

## Режимы роутинга

Проект предоставляет два режима маршрутизации. Выбор зависит от
ситуации и требований к приватности.

### «Всё через прокси» (routing-russia.json) — для дома/ПК

Весь трафик идёт через VPN, кроме российских ресурсов и приватных сетей.

**Когда использовать:**
- Домашний WiFi
- Максимальная приватность
- Нет ограничений по трафику
- Проводной интернет

**Как применить:**
1. v2rayN → Настройки → Настройки маршрутизации
2. Загрузить `routing-russia.json`
3. Применить

### «Только заблокированное» (only_blocked.json) — для IP-whitelist

Через прокси идёт только то, что реально заблокировано в РФ.
Остальное — напрямую.

**Когда использовать:**
- IP-whitelist блокировки
- Экономия трафика прокси
- Лимитный тариф
- Низкая скорость прокси

**Как применить:**
1. v2rayN → Настройки → Настройки маршрутизации
2. Загрузить `only_blocked.json`
3. Применить

### Доменная стратегия

После импорта правил установите доменную стратегию:

| Стратегия | Описание |
|-----------|----------|
| **IPOnDemand (рекомендуется)** | DNS-запросы только для реально используемых доменов |
| IPIfNonMatch | Разрешать домены в IP, если не нашлось доменного правила |
| AsIs | Не использовать geoip (отключает `geoip:ru` и `geoip:ru-blocked`) |

Настройка: v2rayN → Настройки → Настройки маршрутизации → Доменная стратегия.

Подробнее о правилах роутинга — в [CONFIGURATION.md](CONFIGURATION.md).

---

## Обновление правил

Правила geoip/geosite обновляются **автоматически раз в неделю**
через systemd timer. Для ручного обновления:

```bash
# Через алиас
v2rayn-update-rules

# Или напрямую
~/.local/share/v2rayN/scripts/update-rules.sh

# Удалённо (из любого места)
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)
```

### Проверка статуса обновлений

```bash
# Статус таймера
systemctl --user list-timers v2rayn-rules-update.timer
# Ожидаемый вывод:
# NEXT                      LEFT     LAST PASSED UNIT
# Mon 2026-06-22 00:...    2 days   n/a  n/a    v2rayn-rules-update.timer

# Последний лог обновления
journalctl --user -u v2rayn-rules-update.service --since "1 week ago"

# Статус скрипта (версии файлов, дата)
./scripts/update-rules.sh --status
```

### Что происходит при обновлении

```
1. Инициализация лога
2. Блокировка конкурентного запуска (lock-файл)
3. Скачивание geoip.dat (retry 3x, SHA256, кэш fallback)
4. Скачивание geosite.dat (retry 3x, SHA256, кэш fallback)
5. Валидация: файл >10KB
6. Установка новых правил
7. Логирование в journald (при запуске через systemd timer)
```

---

## Мониторинг

### Статус v2rayN

```bash
# Полная проверка состояния
~/.local/share/v2rayN/scripts/status.sh
```

Вывод включает:
- Процесс v2rayN (запущен/остановлен)
- Порты 10808/10809 (слушаются/нет)
- Версия v2rayN и Xray-core
- Статус systemd сервиса
- Наличие geoip.dat / geosite.dat
- Их версии и размеры

### Сбор диагностики

```bash
# Сбор всей диагностической информации
./scripts/diagnose.sh
```

Создаёт архив с логами, конфигами, выводом `status.sh`, журналом systemd.
Используется для прикрепления к GitHub Issues.

---

## Диагностика сети

Скрипт `diagnose-network.sh` выполняет глубокий анализ сети
на наличие проблем, влияющих на работу VPN.

```bash
# Полная диагностика (все 13 секций)
./scripts/diagnose-network.sh

# Быстрая проверка (только ключевые секции)
./scripts/diagnose-network.sh --quick

# Только безопасность
./scripts/diagnose-network.sh --security

# Только связность (пинг, DNS, прокси)
./scripts/diagnose-network.sh --connectivity

# Только одна секция
./scripts/diagnose-network.sh --section 5
```

### Что проверяется

| № | Секция | Что анализирует |
|---|--------|-----------------|
| 0 | Информация | Версия скрипта, ОС, ядро |
| 1 | Система | CPU, RAM, диски, NTP, SELinux, виртуализация |
| 2 | Интерфейсы | Состояние, MTU, скорость, TSO/GRO, ошибки |
| 3 | Маршрутизация | Таблица, дефолтный шлюз, multicast |
| 4 | DNS | resolv.conf, systemd-resolved, DoH, DoT |
| 5 | Прокси | SOCKS5, HTTP — доступность, ignore-hosts |
| 6 | Файрвол | iptables/nftables, kill-switch, открытые порты |
| 7 | Sysctl | 30+ параметров ядра (BBR, TFO, MTU probing) |
| 8 | TUN | Модуль tun, устройства, Xray TUN |
| 9 | Соединения | conntrack, сокеты, TIME_WAIT |
| 10 | Связность | Пинг, mtr, speedtest, прокси, внешний IP |
| 11 | VPN | Xray, WireGuard, порты |
| 12 | Безопасность | открытые порты, ARP-spoofing, IPv6, DHCP |
| 13 | Рекомендации | Итоговые рекомендации на основе всех проверок |

Подробнее: [SCRIPTS.md](SCRIPTS.md#diagnose-networksh).

---

## Kill-switch (аварийное отключение)

Если VPN отключился, kill-switch блокирует весь трафик вне прокси,
предотвращая утечку данных.

```bash
# Включить kill-switch
./scripts/kill-switch.sh on

# Выключить kill-switch
./scripts/kill-switch.sh off

# Проверить статус
./scripts/kill-switch.sh status
```

**Принцип работы:**
- Создаётся цепочка `V2RAYN` в iptables
- Разрешается трафик только через порты v2rayN (10808, 10809)
- Весь остальной трафик блокируется
- При выключении — цепочка удаляется, правила восстанавливаются

**Важно:** Kill-switch **не устанавливается автоматически** при install.sh.
Включите его вручную после настройки v2rayN.

---

## Миграция allowInsecure → pinnedPeerCertSha256

Xray-core v26.2.6+ (февраль 2026) полностью удалил `allowInsecure`.
Необходимо заменить его на `pinnedPeerCertSha256`.

```bash
# Автоматическая миграция
./scripts/migrate-allowinsecure.sh

# Принудительная (без подтверждения)
./scripts/migrate-allowinsecure.sh --force

# Показать изменения без применения
./scripts/migrate-allowinsecure.sh --dry-run
```

Подробнее: [FAQ.md](FAQ.md#allowinsecure--что-делать).

---

## Применение конфигов

Для ручного применения или восстановления конфигураций:

```bash
# Применить все настройки
./apply-configs.sh --all

# Только правила роутинга
./apply-configs.sh --routing

# Только DNS
./apply-configs.sh --dns

# Только systemd юниты
./apply-configs.sh --systemd

# Только на Android (через ADB)
./apply-configs.sh --mobile

# Показать, что изменится (без применения)
./apply-configs.sh --routing --dry-run
```

Команда создаёт бэкапы в `~/.cache/v2rayN-backups/` перед перезаписью.
