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

- **ОС:** Linux (Ubuntu 22.04+, Debian 12+, Fedora 38+, Arch Linux)
- **Зависимости:** Git, SQLite3, GSettings (GNOME) или KDE Plasma
- **v2rayN:** Установлен из `.deb` или AppImage (скачать с [releases](https://github.com/2dust/v2rayN/releases))
- **.NET Runtime:** Установлен (требуется для v2rayN)

## Быстрая установка

```bash
git clone <repo-url>
cd v2rayN-russia-setup
chmod +x install.sh && ./install.sh
```

## Подробное описание шагов

### 1. Установка v2rayN

Скачайте последнюю версию `.deb` с [страницы релизов](https://github.com/2dust/v2rayN/releases) и установите:

```bash
sudo dpkg -i v2rayN*.deb
sudo apt-get install -f
```

### 2. Запуск установщика

```bash
git clone <repo-url>
cd v2rayN-russia-setup
chmod +x install.sh
./install.sh
```

Установщик выполнит:

1. Проверку наличия v2rayN
2. Клонирование и установку правил geoip/geosite из `runetfreedom/russia-v2ray-rules-dat`
3. Установку конфигурации роутинга `routing-russia.json`
4. Установку шаблона Xray-core `config-template-xray.json`
5. Установку скриптов управления прокси
6. Импорт подписок в базу v2rayN (SQLite)
7. Настройку системного прокси (GNOME/KDE)

### 3. Ручной импорт подписок

Если база данных v2rayN ещё не создана, откройте v2rayN, затем выполните скрипт повторно.

### 4. Обновление правил

```bash
./scripts/update-rules.sh
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
