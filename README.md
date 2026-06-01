# v2rayN Russia Setup — оптимизированная настройка v2rayN для РФ

Автоматизированная настройка **v2rayN** для работы в условиях блокировок на территории Российской Федерации. Включает оптимизированные правила роутинга, конфигурацию Xray-core, скрипты управления системным прокси и импорт актуальных подписок.

## Назначение

Репозиторий предназначен для быстрого развёртывания v2rayN с:

- Правилами geoip/geosite от **runetfreedom/russia-v2ray-rules-dat** (адаптированными под российские блокировки)
- Чёрными и белыми списками для маршрутизации трафика
- Оптимизированной конфигурацией Xray-core (Policy, DNS, Sockopt, Fragment)
- Автоматическим импортом подписок в базу v2rayN

## Структура репозитория

```
v2rayN-russia-setup/
├── config/
│   ├── routing-russia.json          # Правила роутинга для РФ
│   └── config-template-xray.json    # Шаблон Xray-core
├── scripts/
│   ├── update-rules.sh              # Обновление geoip/geosite
│   ├── proxy-toggle.sh              # Вкл/выкл системного прокси
│   └── proxy_set_linux_sh.sh        # Установка прокси (GNOME/KDE)
├── subscriptions/
│   └── README.md                    # Список подписок
├── install.sh                       # Автоматический установщик
├── LICENSE                          # MIT License
└── README.md                        # Этот файл
```

## Системные требования

- **ОС:** Linux (Ubuntu 20.04+, Debian 11+, Fedora 38+, Arch Linux)
- **Архитектура:** x86_64 (amd64) или aarch64 (arm64)
- **Зависимости:** Git, SQLite3 (устанавливаются автоматически)
- **.NET Runtime 8.0+** (требуется для v2rayN, устанавливается автоматически на Debian/Ubuntu)

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
| `--force-reinstall` | Переустановить v2rayN, даже если уже установлен |
| `--skip-v2rayn` | Не устанавливать v2rayN (только конфиги и подписки) |
| `--repo-url <url>` | URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N) |

## Что делает установщик

Установщик полностью автоматизирован и не требует участия пользователя:

1. Определяет ОС и архитектуру (x86_64 / aarch64)
2. Устанавливает зависимости (git, wget, curl, sqlite3, .NET Runtime)
3. Скачивает последнюю версию v2rayN с GitHub и устанавливает
4. Клонирует правила geoip/geosite из `runetfreedom/russia-v2ray-rules-dat`
5. Устанавливает конфигурацию роутинга `routing-russia.json`
6. Устанавливает шаблон Xray-core с оптимизациями
7. Импортирует подписки в базу v2rayN (SQLite)
8. Настраивает системный прокси (GNOME/KDE)

Работает как при локальном запуске, так и через `curl | bash`. Временные файлы автоматически очищаются.

## Обновление правил

```bash
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/scripts/update-rules.sh)
```

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

## Оптимизации

### Policy

- `handshake: 4` — таймаут рукопожатия 4 секунды
- `connIdle: 120` — idle-соединение 2 минуты
- `bufferSize: 512` — увеличенный буфер

### DNS

- DoH через Google DNS (`https://dns.google/dns-query`)
- DoH через Cloudflare DNS (`https://cloudflare-dns.com/dns-query`)
- `queryStrategy: UseIP` — получение всех типов записей

### Sockopt

- `tcpFastOpen: true` — ускорение TCP-соединений
- `tcpKeepAliveIdle: 45` — keepalive через 45 секунд
- `domainStrategy: UseIP` — стратегия разрешения доменов
- `tcpcongestion: bbr` — BBR congestion control

### Fragment (анти-DPI)

- `packets: tlshello` — фрагментация TLS ClientHello
- `length: 100-200` — размер фрагментов
- `interval: 10-20` — интервал между фрагментами (ms)

### Routing

- Блокировка рекламы (`geosite:category-ads-all`)
- Маршрутизация заблокированных в РФ ресурсов через прокси
- Прямое соединение с .ru/.su/.рф и geoip:ru
- Fallback на прокси для всего остального

## Источники

- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — правила geoip/geosite для РФ
- [igareck/vpn-configs-for-russia](https://github.com/igareck/vpn-configs-for-russia) — конфиги и списки
- [zieng2/wl](https://github.com/zieng2/wl) — белые списки
- [2dust/v2rayN](https://github.com/2dust/v2rayN) — v2rayN GUI
- [Xray-core Documentation](https://xtls.github.io/) — документация Xray
