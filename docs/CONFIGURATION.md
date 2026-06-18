# Конфигурация

Подробное описание всех конфигурационных файлов проекта, их структуры и назначения.

## Содержание

1. [Обзор конфигурационных файлов](#обзор-конфигурационных-файлов)
2. [config-template-xray.json — шаблон Xray-core](#config-template-xrayjson--шаблон-xray-core)
3. [routing-russia.json — «Всё через прокси»](#routing-russiajson--всё-через-прокси)
4. [only_blocked.json — «Только заблокированное»](#only-blockedjson--только-заблокированное)
5. [Сравнение режимов роутинга](#сравнение-режимов-роутинга)
6. [Доменная стратегия](#доменная-стратегия)
7. [Добавление собственных правил](#добавление-собственных-правил)

---

## Обзор конфигурационных файлов

| Файл | Формат | Назначение | Где хранится |
|------|--------|-----------|-------------|
| `config/config-template-xray.json` | JSON Object | Шаблон Xray-core (policy, DNS, inbounds, outbounds, routing) | `~/.local/share/v2rayN/binConfigs/` |
| `config/routing-russia.json` | JSON Object | Правила роутинга «Всё через прокси» | `~/.config/v2rayN/` |
| `config/only_blocked.json` | JSON Object | Правила роутинга «Только заблокированное» | `~/.config/v2rayN/` |

**Важно:** Файлы подлежат **SHA256 верификации** в CI и **JSON Schema** валидации.

---

## config-template-xray.json — шаблон Xray-core

Шаблон используется v2rayN как основа для генерации конфигурации Xray-core.
Находится в `~/.local/share/v2rayN/binConfigs/config-template-xray.json`.

### Структура

```json
{
  "policy":   { /* политики соединений */ },
  "dns":      { /* DNS-серверы и стратегия */ },
  "inbounds": [ /* входящие прокси-порты */ ],
  "outbounds":[ /* исходящие соединения */ ],
  "routing":  { /* правила маршрутизации */ }
}
```

### Policy (политики)

```json
"policy": {
  "levels": {
    "0": {
      "handshake": 4,
      "connIdle": 120,
      "downlinkOnly": 0,
      "uplinkOnly": 0,
      "bufferSize": 512
    }
  }
}
```

| Параметр | Значение | Описание |
|----------|----------|----------|
| `handshake` | 4 | Таймаут рукопожатия (сек) |
| `connIdle` | 120 | Idle-соединение (сек) |
| `bufferSize` | 512 | Размер буфера (KB) |

### DNS

```json
"dns": {
  "hosts": {
    "domain:geosite:category-ads-all": "0.0.0.0",
    "domain:geosite:yandex-ads": "0.0.0.0"
  },
  "servers": [
    {
      "address": "https://1.1.1.1/dns-query",
      "domains": ["geosite:ru-blocked"],
      "skipFallback": true
    },
    {
      "address": "https://dns.google/dns-query",
      "domains": ["geosite:ru-blocked"],
      "skipFallback": true
    },
    "localhost"
  ],
  "queryStrategy": "UseIP",
  "disableCache": false,
  "disableFallback": false,
  "tag": "dns"
}
```

**Особенности:**
- DoH через Cloudflare (1.1.1.1) и Google (8.8.8.8)
- `skipFallback: true` для DoH-серверов — не переключаться на системный DNS
- `queryStrategy: UseIP` — получать и A, и AAAA записи
- Рекламные домены резолвятся в `0.0.0.0` (блокировка на уровне DNS)

### Inbounds (входящие соединения)

Xray-core слушает два порта на localhost:

| Протокол | Порт | Назначение |
|----------|------|-----------|
| SOCKS5 | 10808 | Для приложений с поддержкой SOCKS5 |
| HTTP | 10809 | Для системного прокси |

```json
{
  "port": 10808,
  "protocol": "socks",
  "settings": { "auth": "noauth", "udp": true }
}
```

**Важно:** Оба inbounds принимают только localhost-соединения (`"listen": "127.0.0.1"`).

### Outbounds (исходящие соединения)

| Tag | Протокол | Назначение |
|-----|----------|-----------|
| `proxy` | VLESS/XTLS/REALITY | Основное прокси-соединение с фрагментацией |
| `direct` | freedom | Прямой выход без прокси |
| `block` | blackhole | Блокировка трафика |

**Фрагментация (fragment):**
```json
"streamSettings": {
  "sockopt": { "tcpFastOpen": true, "tcpcongestion": "bbr" },
  "fragment": {
    "packets": "tlshello",
    "length": "100-200",
    "interval": "10-20"
  }
}
```

Параметры фрагментации:
- `packets: tlshello` — фрагментировать только TLS ClientHello
- `length: 100-200` — размер фрагментов (байт)
- `interval: 10-20` — интервал между отправкой фрагментов (мс)
- Режим: `tcp`

**pinnedPeerCertSha256** — замена allowInsecure:
```json
"security": "tls",
"tlsSettings": {
  "pinnedPeerCertSha256": ["ae243d668ec9c7f74a0dcd1ad21c6676b4efe30c39728934b362093af886bf77"]
}
```

Два формата fingerprint:
- hex (64 символа, без разделителей)
- OpenSSL (с двоеточиями, регистронезависим)

### Sockopt

```json
"sockopt": {
  "tcpFastOpen": true,
  "tcpKeepAliveIdle": 45,
  "domainStrategy": "UseIP",
  "tcpcongestion": "bbr"
}
```

| Параметр | Описание |
|----------|----------|
| `tcpFastOpen` | Ускорение TCP (нужна поддержка ядра) |
| `tcpKeepAliveIdle` | Keepalive через 45 секунд |
| `domainStrategy: UseIP` | Стратегия разрешения доменов |
| `tcpcongestion: bbr` | BBR congestion control |

---

## routing-russia.json — «Всё через прокси»

**Назначение:** максимальная защита приватности на ПК/домашнем WiFi.
Весь трафик идёт через VPN, кроме явно разрешённого.

### Порядок правил

Правила применяются **сверху вниз**, первое совпадение побеждает:

```
 1. geosite:category-ads-all          → block        ← реклама блокируется (приоритет)
 2. geosite:ru-blocked                → proxy        ← заблокированные домены РФ
 3. geoip:ru-blocked                  → proxy        ← заблокированные IP РФ
 4. DNS (1.0.0.1, 1.1.1.1,           → proxy        ← DoH через прокси
      8.8.8.8, 8.8.4.4)
 5. UDP 50000-65535                   → proxy        ← Discord VoIP
 6. geoip:ru                          → direct       ← все IP РФ напрямую
 7. .ru, .su, .xn--p1ai,              → direct       ← российские домены напрямую
    geosite:ru-available-only-inside
 8. geoip:ru-whitelist                → direct       ← CIDR вайтлист (hxehex)
 9. geoip:private                     → direct       ← локальные сети
10. geosite:private                   → direct       ← приватные домены
11. ВСЁ ОСТАЛЬНОЕ (tcp,udp)          → proxy        ← через прокси
```

### Ключевые особенности

| Особенность | Описание |
|-------------|----------|
| **Реклама блокируется приоритетно** | `category-ads-all` → block стоит ВЫШЕ `ru-blocked` → proxy |
| **Discord VoIP** | UDP 50000-65535 через прокси (этот диапазон блокируется РФ-операторами) |
| **DNS через прокси** | 1.1.1.1, 8.8.8.8 маршрутизируются через прокси |
| **BitTorrent** | Идёт через прокси (максимальная приватность) |

---

## only_blocked.json — «Только заблокированное»

**Назначение:** экономия трафика при whitelist-блокировках.
Через прокси идёт только то, что реально заблокировано в РФ.

### Порядок правил

```
 1. geosite:category-ads-all          → block        ← реклама
 2. geosite:ru-blocked                → proxy        ← заблокированные домены РФ
 3. geoip:ru-blocked                  → proxy        ← заблокированные IP РФ
 4. DNS (1.0.0.1, 1.1.1.1,           → proxy        ← DoH через прокси
      8.8.8.8, 8.8.4.4)
 5. UDP 50000-65535                   → proxy        ← Discord VoIP
 6. BitTorrent                        → direct       ← торренты напрямую
 7. geoip:ru                          → direct       ← все IP РФ
 8. .ru, .su, .xn--p1ai,              → direct       ← российские домены
    geosite:ru-available-only-inside
 9. geoip:ru-whitelist                → direct       ← CIDR вайтлист (hxehex)
10. geoip:private                     → direct       ← локальные сети
11. geosite:private                   → direct       ← приватные домены
12. ВСЁ ОСТАЛЬНОЕ (tcp,udp)          → direct       ← напрямую (НЕ через прокси!)
```

---

## Сравнение режимов роутинга

| Характеристика | routing-russia.json | only_blocked.json |
|---------------|---------------------|-------------------|
| **Default outbound** | proxy (всё через VPN) | direct (напрямую) |
| **BitTorrent** | через прокси | напрямую |
| **Расход трафика VPN** | высокий | низкий |
| **Приватность** | максимальная | средняя |
| **Когда использовать** | Домашний WiFi, ПК | IP-whitelist, лимитный трафик |
| **Реклама** | блокируется | блокируется |
| **Discord VoIP** | через прокси | через прокси |
| **DNS** | через прокси | через прокси |
| **Российские ресурсы** | напрямую | напрямую |

---

## Доменная стратегия

После импорта правил роутинга в v2rayN установите доменную стратегию:

| Стратегия | Описание | Рекомендация |
|-----------|----------|--------------|
| **IPOnDemand** | DNS-запросы только для доменов, которые реально используются | **Рекомендуется** |
| IPIfNonMatch | Разрешать домены в IP, если не нашлось доменного правила | Альтернатива |
| AsIs | Не использовать geoip (отключает `geoip:ru` и `geoip:ru-blocked`) | Только для отладки |

Настройка: v2rayN → Настройки → Настройки маршрутизации → Доменная стратегия.

---

## Добавление собственных правил

### Исключение домена

Добавьте правило в соответствующий JSON-файл перед дефолтным правилом:

```json
{
  "type": "field",
  "domain": ["domain:мой-домен.рф"],
  "outboundTag": "direct"
}
```

### Исключение IP-диапазона

```json
{
  "type": "field",
  "ip": ["10.0.0.0/8", "192.168.0.0/16"],
  "outboundTag": "direct"
}
```

### Направление протокола через прокси

```json
{
  "type": "field",
  "protocol": ["bittorrent"],
  "outboundTag": "direct"
}
```

### Порядок добавления

1. Откройте файл роутинга (`routing-russia.json` или `only_blocked.json`)
2. Вставьте новое правило в массив `rules`
3. Разместите правило **ДО** дефолтного (последнего) правила
4. Проверьте JSON: `python3 -m json.tool файл.json`
5. Перезагрузите конфигурацию в v2rayN
