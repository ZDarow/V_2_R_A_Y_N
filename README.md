# v2rayN Russia Setup — оптимизированная настройка v2rayN для РФ

Автоматизированная настройка **v2rayN** (Linux/Windows) для работы в условиях блокировок на территории Российской Федерации. Включает оптимизированные правила роутинга, конфигурацию Xray-core, скрипты управления системным прокси и импорт актуальных подписок.

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
│   ├── routing-russia.json          # Правила роутинга «Всё через прокси»
│   ├── only_blocked.json            # Правила «Только заблокированное»
│   └── config-template-xray.json    # Шаблон Xray-core
├── scripts/
│   ├── update-rules.sh              # Обновление geoip/geosite (ветка release)
│   ├── proxy-toggle.sh              # Вкл/выкл системного прокси (GNOME+KDE)
│   └── proxy_set_linux_sh.sh        # Установка прокси (GNOME/KDE)
├── subscriptions/
│   └── README.md                    # Список подписок
├── install.sh                       # Автоматический установщик v2rayN (Linux)
├── uninstall.sh                     # Деинсталлятор v2rayN
├── LICENSE                          # MIT License
├── README.md                        # Этот файл
└── docs/                            # Подробная документация
    ├── install.md                   # Установка и флаги
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
4. Загружает правила geoip/geosite из **ветки release** `runetfreedom/russia-v2ray-rules-dat` (retry 3x + SHA256 + кэш)
5. Устанавливает конфигурации роутинга: 3 JSON-файла
6. Устанавливает шаблон Xray-core с оптимизациями (outbound `proxy` с фрагментацией, DNS через прокси, Discord VoIP)
7. Устанавливает скрипты управления + **systemd timer** для еженедельного авто-обновления geoip/geosite
8. Импортирует подписки в базу v2rayN (SQLite)
9. Настраивает системный прокси (GNOME/KDE)
10. Выводит предупреждение об отключении allowInsecure с 1 августа 2026

Работает как при локальном запуске, так и через `curl | bash`. Временные файлы автоматически очищаются.

### Авто-обновление правил

После установки `update-rules.sh` запускается **еженедельно** через systemd timer:
```bash
# Проверить статус:
systemctl --user list-timers v2rayn-rules-update.timer

# Посмотреть лог:
journalctl --user -u v2rayn-rules-update.service

# Ручной запуск:
~/.local/bin/v2rayn-update-rules
```

Все загрузки имеют retry 3 попытки с экспоненциальной задержкой,
SHA256 верификацию и защиту от конкурентного запуска (lock-файл).



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
| BLACK VLESS RUS | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt |
| BLACK SS+All RUS | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt |

### Белые списки (только РФ через VPN)

| Подписка | URL |
|----------|-----|
| WHITE CIDR RU all | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt |
| WHITE SNI RU all | https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-SNI-RU-all.txt |

### Дополнительно (zieng2/wl)

| Подписка | URL |
|----------|-----|
| vless_universal | https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt |

> **Примечание:** При блокировке GitHub используйте зеркала: GitLab, Codeberg, Gitea, GitHack.
> Полный список зеркал: https://github.com/igareck/vpn-configs-for-russia#readme

## Режимы маршрутизации

Проект предоставляет два файла роутинга для разных сценариев:

### `routing-russia.json` — Всё через прокси (режим «Чёрный список»)
Рекомендуется для проводного интернета. Весь TCP/UDP трафик идёт через прокси, кроме:
- Российских доменов и IP напрямую (`.ru`, `.su`, `.рф`, `geoip:ru`)
- Приватных сетей (`geoip:private`)
- Блокировки рекламы (`geosite:category-ads-all`)

### `only_blocked.json` — Только заблокированное (режим «Белый список»)
Рекомендуется при whitelist-блокировках (IP-вайтлист), когда прокси нужен только для заблокированных ресурсов:
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

## ⚠️ allowInsecure удалён в Xray v26.2.6+

**Xray-core v26.2.6+ (февраль 2026) полностью удалил `allowInsecure`.**
Вместо него используйте **`pinnedPeerCertSha256`** — привязку к SHA256 отпечатку сертификата.

**v2rayN 7.22.7+** уже заменил allowInsecure на `pinnedPeerCertSha256`.
Убедитесь, что в настройках подписки включён «Отпечаток сертификата», а не allowInsecure.

## Two-server схема (для обхода IP-whitelist)

Обход блокировок на уровне IP (IP-whitelist):

```
Клиент (РФ) → РФ-сервер (белый IP) → Иностранный сервер → Интернет
```

1. Купите VPS в РФ с IP, не находящимся под whitelist-блокировкой
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
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — Xray-core (v26.3.27+)
- [XTLS/REALITY](https://github.com/XTLS/REALITY) — протокол REALITY (THE NEXT FUTURE)
- [2dust/v2rayN](https://github.com/2dust/v2rayN) — v2rayN GUI (Linux/Windows)
- [Xray-core Documentation](https://xtls.github.io/) — документация Xray
