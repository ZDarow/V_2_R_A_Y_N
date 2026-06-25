# Подписки v2rayN для РФ

Список всех подписок, импортируемых в базу v2rayN.

## Чёрные списки (весь трафик через VPN)

| ID | Название | Источник |
|----|----------|----------|
| BLACK-RUS-001 | Чёрные списки РФ (весь трафик через VPN) | igareck/vpn-configs-for-russia |

**Основной URL:**
```
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt
```

**Дополнительные URL:**
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt

## Белые списки (только РФ через VPN)

| ID | Название | Источник |
|----|----------|----------|
| WHITE-RUS-001 | Белые списки РФ (только РФ через VPN) | igareck/vpn-configs-for-russia |

**Основной URL:**
```
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt
```

**Дополнительные URL:**
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-checked.txt
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-SNI-RU-all.txt

## Дополнительно (zieng2/wl)

| ID | Название | Источник |
|----|----------|----------|
| WL-ZIENG2-001 | WL Белый список (zieng2) | zieng2/wl |

**Основной URL:**
```
https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt
```

**Дополнительный URL:**
- https://codeberg.org/zieng2/wl/raw/branch/main/vless_universal.txt

## Tor Bridges (альтернатива VPN при FULL WHITELIST)

Если VPN не работает из-за полного белого списка — используйте Tor Bridges.

| ID | Название | Ссылка |
|----|----------|--------|
| TOR-TOP100 | Tor Bridges TOP-100 | `https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/TOR-BRIDGES/TOR_BRIDGES_TOP100.txt` |
| TOR-ALL | Tor Bridges ALL | `https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/TOR-BRIDGES/TOR_BRIDGES_ALL.txt` |
| TOR-OBFS4 | Tor obfs4 | `https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/TOR-BRIDGES/TOR_BRIDGES_OBFS4.txt` |
| TOR-WEBTUNNEL | Tor webtunnel | `https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/TOR-BRIDGES/TOR_BRIDGES_WEBTUNNEL.txt` |
| TOR-VANILLA | Tor vanilla | `https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/TOR-BRIDGES/TOR_BRIDGES_VANILLA.txt` |

**Клиент:** OnionHop V2 (Tor Browser) для Android/PC.

**Особенности:**
- Устойчивее VPN в белых списках
- Соединение держится днями
- Типы: obfs4, webtunnel, vanilla (если obfs4 не работает)

## CIDR and SNI Whitelists (hxehex — для self-hosted серверов)

Список IP/доменов, гарантированно работающих в режиме белых списков РФ.
Необходим для настройки собственного сервера (two-server схема).

| Файл | Что содержит | Ссылка |
|------|-------------|--------|
| `cidrwhitelist.txt` | CIDR-подсети (тысячи) | `https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt` |
| `ipwhitelist.txt` | Отдельные IP-адреса | `https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt` |
| `whitelist.txt` | Домены для SNI-спуфинга | `https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt` |

**Использование:**
1. Проверьте свой VPS на вхождение в CIDR whitelist
2. Выберите домен из whitelist.txt для SNI-спуфинга
3. Настройте two-server схему: клиент → РФ сервер → зарубежный сервер

## Зеркала (на случай блокировки GitHub)

При блокировке GitHub используйте следующие зеркала:

| Платформа | igareck | zieng2 |
|-----------|---------|--------|
| **GitLab** | https://gitlab.com/igareck/vpn-configs-for-russia | https://gitlab.com/zieng2/wl |
| **Codeberg** | https://codeberg.org/igareck/vpn-configs-for-russia | https://codeberg.org/zieng2/wl |
| **Gitea** | https://gitea.com/igareck/vpn-configs-for-russia | — |
| **SourceHut** | https://git.sr.ht/~igareck/vpn-configs-for-russia | — |
| **Bitbucket** | https://bitbucket.org/igareck/vpn-configs-for-russia/ | — |
| **GitHack** (RAW proxy) | https://raw.githack.com/igareck/vpn-configs-for-russia/main/ | — |
| **Yandex** (whitelist proxy) | `https://translate.yandex.ru/translate?url=https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/ФАЙЛ.txt&lang=de-de` | — |
