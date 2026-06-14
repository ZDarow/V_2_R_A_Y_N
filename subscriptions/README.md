# Подписки v2rayN для РФ

Список всех подписок, импортируемых в базу v2rayN.

## Чёрные списки (весь трафик через VPN)

| ID | Название | Источник |
|----|----------|----------|
| BLACK-RUS-001 | Чёрные списки РФ (весь трафик через VPN) | igareck/vpn-configs-for-russia |

**Основной URL:**
```
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt
```

**Дополнительные URL:**
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS.txt
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_SS+All_RUS.txt

## Белые списки (только РФ через VPN)

| ID | Название | Источник |
|----|----------|----------|
| WHITE-RUS-001 | Белые списки РФ (только РФ через VPN) | igareck/vpn-configs-for-russia |

**Основной URL:**
```
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt
```

**Дополнительные URL:**
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile-2.txt
- https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/WHITE-CIDR-RU-all.txt
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

## Whitelist CIDR/IP для мобильного интернета (hxehex)

| ID | Название | Источник |
|----|----------|----------|
| WHITELIST-IPS-001 | Whitelist IP (hxehex) — CIDR для мобильных | hxehex/russia-mobile-internet-whitelist |

**Основной URL (CIDR):**
```
https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/cidrwhitelist.txt
```

**Дополнительные URL:**
- https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/ipwhitelist.txt
- https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/main/whitelist.txt

> **Назначение:** эти списки содержат IP-адреса и подсети, которые остаются доступными
> на мобильных операторах РФ (МТС, Билайн, МегаФон, Tele2, Yota) при включении
> «белых списков». Используются для SNI-спуфинга и поиска VPS с «белым» IP.
>
> **Дискорд-сообщество:** https://discord.gg/QPBdMf8dxG

## Зеркала (на случай блокировки GitHub)

При блокировке GitHub используйте следующие зеркала:

| Платформа | igareck | zieng2 | hxehex |
|-----------|---------|--------|--------|
| **GitLab** | https://gitlab.com/igareck/vpn-configs-for-russia | https://gitlab.com/zieng2/wl | — |
| **Codeberg** | https://codeberg.org/igareck/vpn-configs-for-russia | https://codeberg.org/zieng2/wl | — |
| **Gitea** | https://gitea.com/igareck/vpn-configs-for-russia | — | — |
| **GitHack** (RAW proxy) | https://raw.githack.com/igareck/vpn-configs-for-russia/main/ | — | — |
