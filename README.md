# v2rayN Russia Setup — оптимизированная настройка v2rayN/v2rayNG для РФ

Автоматизированная настройка **v2rayN** (Linux/Windows) и **v2rayNG** (Android) для работы в условиях блокировок на территории Российской Федерации. Включает оптимизированные правила роутинга, конфигурацию Xray-core, скрипты управления системным прокси и импорт актуальных подписок.

## Назначение

Репозиторий предназначен для быстрого развёртывания v2rayN с:

- Правилами geoip/geosite от **runetfreedom/russia-v2ray-rules-dat** (ветка release, адаптированными под российские блокировки)
- Чёрными и белыми списками для маршрутизации трафика
- Оптимизированной конфигурацией Xray-core (Policy, DNS, Sockopt, Fragment)
- Автоматическим импортом подписок в базу v2rayN

## Структура репозитория

```
v2rayN-russia-setup/
├── config/
│   ├── routing-russia.json          # Правила роутинга «Всё через прокси» (v2rayN + v2rayNG)
│   ├── only_blocked.json            # Правила «Только заблокированное» (v2rayN + v2rayNG)
│   └── config-template-xray.json    # Шаблон Xray-core (v2rayN + v2rayNG)
├── scripts/
│   ├── deploy-mobile.sh              # Деплой конфигов на Android (ZIP/ADB/HTTP)
│   ├── update-rules.sh               # Обновление geoip/geosite (ветка release)
│   ├── proxy-toggle.sh               # Вкл/выкл системного прокси (GNOME+KDE)
│   └── proxy_set_linux_sh.sh         # Установка прокси (GNOME/KDE)
├── subscriptions/
│   └── README.md                    # Список подписок
├── deploy/
│   └── index.html                    # Мобильный портал (скачать конфиги с телефона)
├── install.sh                       # Автоматический установщик v2rayN (Linux)
├── uninstall.sh                     # Деинсталлятор v2rayN
├── LICENSE                          # MIT License
├── README.md                        # Этот файл
└── docs/                            # Подробная документация
    ├── install.md                   # Установка и флаги
    ├── mobile.md                    # Мобильный деплой (Android)
    ├── routing.md                   # Правила роутинга
    ├── scripts.md                   # Скрипты управления
    ├── ci.md                        # CI/CD пайплайн
    └── faq.md                       # Частые вопросы

Полная документация: [docs/README.md](docs/README.md)

## Системные требования

- **ОС:** Linux (Ubuntu 20.04+, Debian 11+, Fedora 38+, Arch Linux)
- **Архитектура:** x86_64 (amd64) или aarch64 (arm64)
- **Зависимости:** Git, SQLite3 (устанавливаются автоматически)
- **.NET Runtime 10.0+** (требуется для v2rayN, устанавливается автоматически на Debian/Ubuntu)

## Быстрая установка (одной командой)

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)
```

### Или через клонирование

```bash
git clone https://github.com/ZDarow/V_2_R_A_Y_N.git
cd V_2_R_A_Y_N
./install.sh
```

## Флаги

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--force-reinstall` | Переустановить v2rayN, даже если уже установлен |
| `--skip-v2rayn` | Не устанавливать v2rayN (только конфиги и подписки) |
| `--repo-url <url>` | URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N) |

## Что делает установщик

Установщик полностью автоматизирован и не требует участия пользователя:

1. Определяет ОС и архитектуру (x86_64 / aarch64)
2. Устанавливает зависимости (git, wget, curl, sqlite3, .NET Runtime 10.0+)
3. Скачивает последнюю версию v2rayN с GitHub и устанавливает
4. Загружает правила geoip/geosite из **ветки release** `runetfreedom/russia-v2ray-rules-dat`
5. Устанавливает конфигурации роутинга: `routing-russia.json` (всё через прокси) + `only_blocked.json` (только заблокированное — для мобильного интернета)
6. Устанавливает шаблон Xray-core с оптимизациями (outbound `proxy` с фрагментацией, DNS через прокси, Discord VoIP)
7. Импортирует подписки в базу v2rayN (SQLite), включая whitelist CIDR/IP от hxehex
8. Настраивает системный прокси (GNOME/KDE)
9. Выводит предупреждение об отключении allowInsecure с 1 августа 2026

Работает как при локальном запуске, так и через `curl | bash`. Временные файлы автоматически очищаются.

## v2rayNG — Android-клиент

**v2rayNG** (58k ★) — официальный Android-клиент от 2dust, основанный на том же Xray-core, что и v2rayN.
Все конфигурационные файлы из этого репозитория (`routing-russia.json`, `only_blocked.json`, `config-template-xray.json`, подписки) **полностью совместимы** с v2rayNG.

### Установка v2rayNG

| Источник | Ссылка | Примечание |
|----------|--------|------------|
| **GitHub Releases** | [2dust/v2rayNG/releases](https://github.com/2dust/v2rayNG/releases) | APK файлы: `v2rayNG_<version>.apk`, `v2rayNG_<version>-arm64-v8a.apk` |
| **F-Droid** | [F-Droid](https://f-droid.org/packages/com.v2ray.ang/) | Подписанная сборка (рекомендуется) |
| **Google Play** | [Play Market](https://play.google.com/store/apps/details?id=com.v2ray.ang) | Требуется Google-сервисы |

**Текущая версия:** `2.2.3` (2 июня 2026), Xray-core v26.6.1, target SDK 37 (Android 17+)

### 📱 Мобильный портал (без терминала)

Откройте на телефоне **одну страницу** и скачайте все файлы нажатиями:

> **👉 [v2rayNG — установка конфигов РФ](https://ZDarow.github.io/V_2_R_A_Y_N/deploy/)**
>
> Или используйте зеркало: [cdn.jsdelivr.net](https://cdn.jsdelivr.net/gh/ZDarow/V_2_R_A_Y_N@main/deploy/index.html)
>
> На странице: скачивание JSON + geoip/geosite, копирование подписок, инструкция.

### Настройка для РФ на Android

1. **Установите v2rayNG** любым из способов выше
2. **Импортируйте подписки** через меню + → «Импорт из буфера обмена» или по URL
3. **Настройте правила роутинга:**
   - Скопируйте `routing-russia.json` или `only_blocked.json` в `Android/data/com.v2ray.ang/files/assets/`
   - В приложении: Настройки → Настройки маршрутизации → «Пользовательский файл роутинга» → выберите файл
4. **Обновите geoip/geosite** (по умолчанию v2rayNG использует Loyalsoldier, замените на runetfreedom):
   - Поместите `geoip.dat` и `geosite.dat` из [runetfreedom release](https://github.com/runetfreedom/russia-v2ray-rules-dat) в папку `Android/data/com.v2ray.ang/files/assets/`
   - **Важно:** скачивание правил внутри v2rayNG требует работающего прокси (курица-яйцо). Скачайте вручную на компьютере и перенесите на телефон
5. **⚡ Проблема «курицы и яйца»:** для первой загрузки geoip/geosite понадобится либо:
   - Временно использовать публичный VPN для скачивания правил
   - Перенести файлы через USB/ADB с компьютера, где уже настроен v2rayN
   - Использовать скрипт `deploy-mobile.sh` (см. ниже)
   - Использовать встроенные правила Loyalsoldier (они уже есть в APK)

### 🚀 Автоматизированный деплой (deploy-mobile.sh)

Скрипт `scripts/deploy-mobile.sh` решает проблему «курицы и яйца» — загружает свежие geoip/geosite, пакует конфиги и переносит на телефон в один шаг.

```bash
# Из корня репозитория:
./scripts/deploy-mobile.sh --help

# Создать ZIP-архив для ручного переноса:
./scripts/deploy-mobile.sh --zip

# Push напрямую на телефон через USB (требуется adb + отладка):
./scripts/deploy-mobile.sh --adb

# Запустить HTTP-сервер — скачайте ZIP с телефона через браузер:
./scripts/deploy-mobile.sh --server

# Только geoip/geosite, без конфигов:
./scripts/deploy-mobile.sh --adb --rules-only
```

**Что делает скрипт:**
1. Скачивает `geoip.dat` и `geosite.dat` из runetfreedom (ветка release)
2. Копирует `routing-russia.json`, `only_blocked.json`, `config-template-xray.json`
3. Создаёт `README-Android.txt` с инструкцией
4. Доставляет на телефон выбранным способом: ZIP / ADB / HTTP

**Требования:**
- Для `--zip`: утилита `zip` (apt install zip)
- Для `--adb`: `adb` из android-tools-adb, USB-отладка на телефоне
- Для `--server`: python3 (есть в любой системе)

### ⚠️ allowInsecure на Android

**v2rayNG 2.2.3 полностью удалил настройку allowInsecure.** Вместо неё используется **только pinnedPeerCertSha256** (привязка к отпечатку SHA256 сертификата).

- Убедитесь, что в настройках вашей подписки включён «Отпечаток сертификата» (certificate fingerprint)
- [Инструкция по allowInsecure → pinnedPeerCertSha256](https://github.com/2dust/v2rayN/discussions/9460)

### Отличия v2rayNG от v2rayN

| Возможность | v2rayN (Linux) | v2rayNG (Android) |
|-------------|----------------|-------------------|
| Интерфейс | Avalonia (десктоп) | Material Design (мобильный) |
| TUN-режим | Через Xray-core TUN | Стандартный Android VPN |
| Системный прокси | GNOME/KDE Settings | Android VPN API (встроен) |
| Fragment | ✓ (конфиг Xray) | ✓ (через Xray-core) |
| XHTTP | ✓ (через подписки) | ✓ (через подписки) |
| Подписки | URL-импорт в SQLite | URL-импорт напрямую |
| geoip/geosite | automatic (update-rules.sh) | ручная замена файлов |
| allowInsecure | удалён в 7.22.6+ | удалён в 2.2.3 |

## Деинсталляция

```bash
./uninstall.sh
```

Удаляет v2rayN, конфиги, отключает системный прокси. .NET Runtime не удаляется.

## Обновление правил

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)
```

Правила загружаются из **ветки release** репозитория `runetfreedom/russia-v2ray-rules-dat` (не требуется git clone).

## Список подписок

### Чёрные списки (весь трафик через VPN)

| Подписка | URL |
|----------|-----|
| BLACK VLESS RUS Mobile | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt |
| BLACK VLESS RUS | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt |
| BLACK SS+All RUS | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt |

### Белые списки (только РФ через VPN)

| Подписка | URL |
|----------|-----|
| Vless-Reality White Lists Rus Mobile | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt |
| WHITE CIDR RU all | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt |
| WHITE SNI RU all | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-SNI-RU-all.txt |

### Дополнительно (zieng2/wl)

| Подписка | URL |
|----------|-----|
| vless_universal | https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt |

### Whitelist CIDR/IP для мобильного интернета (hxehex)

| Подписка | URL | Назначение |
|----------|-----|------------|
| CIDR Whitelist | https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt | CIDR-сети, не заблокированные на мобильных операторах |
| IP Whitelist | https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt | Отдельные IP-адреса из белого списка |
| SNI Whitelist | https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt | Домены (SNI), доступные при вайтлисте |

> **Примечание:** При блокировке GitHub используйте зеркала: GitLab, Codeberg, Gitea, GitHack.
> Полный список зеркал: https://github.com/igareck/vpn-configs-for-russia#readme
>
> **Дискорд-сообщество по мобильным блокировкам:** https://discord.gg/QPBdMf8dxG

## Режимы маршрутизации

Проект предоставляет два файла роутинга для разных сценариев:

### `routing-russia.json` — Всё через прокси (режим «Чёрный список»)
Рекомендуется для проводного интернета. Весь TCP/UDP трафик идёт через прокси, кроме:
- Российских доменов и IP напрямую (`.ru`, `.su`, `.рф`, `geoip:ru`)
- Приватных сетей (`geoip:private`)
- Блокировки рекламы (`geosite:category-ads-all`)

### `only_blocked.json` — Только заблокированное (режим «Белый список», для мобильного интернета)
Рекомендуется для **мобильных операторов** (МТС, Билайн, МегаФон, Tele2, Yota) при вайтлисте:
- `geoip:ru-blocked` + `geosite:ru-blocked` → proxy
- **DNS-серверы (1.1.1.1, 8.8.8.8) через прокси** — критично при белых списках
- **Discord VoIP (UDP 50000-65535) через прокси**
- BitTorrent → напрямую (чтобы не нагружать прокси)
- Всё остальное (включая geoip:ru, .ru домены) → напрямую

## Протоколы и защита от DPI

### Рекомендуемый протокол: VLESS + REALITY + XTLS-Vision

```
REALITY — THE NEXT FUTURE (XTLS, 5.3k ★)
```

REALITY **полностью устраняет TLS fingerprint сервера**. DPI видит обычное TLS-соединение
с реальным сайтом (Microsoft, Cloudflare и т.д.). Не требует собственного сертификата или домена.

Базовая конфигурация сервера:
```json
{
  "streamSettings": {
    "security": "reality",
    "realitySettings": {
      "target": "www.microsoft.com:443",
      "serverNames": ["microsoft.com"],
      "privateKey": "<xray x25519>",
      "shortIds": ["0123456789abcdef"]
    }
  }
}
```

### fragment (анти-DPI) — для протоколов без REALITY

- `packets: tlshello` — фрагментация TLS ClientHello (на outbound **proxy**)
- `length: 100-200` — размер фрагментов
- `interval: 10-20` — интервал между фрагментами (ms)

## ⚠️ allowInsecurity будет отключён с 1 августа 2026

**Xray-core отключает параметр `allowInsecure`** с 1 августа 2026.
Вместо него используйте:
- **`verifyPeerCertByName`** — проверка сертификата по имени (рекомендуется)
- **FP (fingerprint) pinning** — привязка к отпечатку сертификата

**v2rayN 7.22.7+** и **v2rayNG 2.2.3+** уже заменили allowInsecure на `verifyPeerCertByName` / `pinnedPeerCertSha256`.
Убедитесь, что в настройках подписки включена эта опция, а не allowInsecure.

## Two-server схема (для обхода IP-whitelist)

Самый надёжный способ обхода мобильных блокировок (IP + SNI whitelist):

```
Клиент (РФ, мобильный) → РФ-сервер (белый IP) → Иностранный сервер → Интернет
```

1. Купите VPS в РФ с IP из `cidrwhitelist.txt` (hxehex)
2. Настройте на нём Xray как прокси-переходник
3. Весь трафик идёт через РФ-сервер с «белым» IP → иностранный сервер → цель

## Оптимизации

### Policy

- `handshake: 4` — таймаут рукопожатия 4 секунды
- `connIdle: 120` — idle-соединение 2 минуты
- `bufferSize: 512` — увеличенный буфер

### DNS

- DoH через Google DNS (`https://dns.google/dns-query`)
- DoH через Cloudflare DNS (`https://cloudflare-dns.com/dns-query`)
- `queryStrategy: UseIP` — получение всех типов записей
- **DNS через прокси** (IP 1.1.1.1, 8.8.8.8 маршрутизируются через proxy)

### Sockopt

- `tcpFastOpen: true` — ускорение TCP-соединений
- `tcpKeepAliveIdle: 45` — keepalive через 45 секунд
- `domainStrategy: UseIP` — стратегия разрешения доменов
- `tcpcongestion: bbr` — BBR congestion control

## Источники

- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — правила geoip/geosite для РФ (ветка release)
- [runetfreedom/russia-v2ray-custom-routing-list](https://github.com/runetfreedom/russia-v2ray-custom-routing-list) — шаблоны маршрутизации v2rayN
- [igareck/vpn-configs-for-russia](https://github.com/igareck/vpn-configs-for-russia) — конфиги и списки
- [zieng2/wl](https://github.com/zieng2/wl) — белые списки
- [hxehex/russia-mobile-internet-whitelist](https://github.com/hxehex/russia-mobile-internet-whitelist) — whitelist CIDR/IP/SNI для мобильных операторов РФ
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — Xray-core (v26.3.27+)
- [XTLS/REALITY](https://github.com/XTLS/REALITY) — протокол REALITY (THE NEXT FUTURE)
- [2dust/v2rayN](https://github.com/2dust/v2rayN) — v2rayN GUI (Linux/Windows)
- [2dust/v2rayNG](https://github.com/2dust/v2rayNG) — v2rayNG for Android (58k ★, v2.2.3)
- [Xray-core Documentation](https://xtls.github.io/) — документация Xray
