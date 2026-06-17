# Правила роутинга

## Форматы файлов

В проекте правила роутинга представлены в **двух форматах**, каждый для своей платформы:

| Формат | Файлы | v2rayN | v2rayNG |
|--------|-------|--------|---------|
| **JSON object** | `routing-russia.json`, `only_blocked.json` | Пользовательский файл роутинга (Настройки → Настройки маршрутизации) | — |
| **JSON array** | `v2rayng-routing-russia.json`, `v2rayng-only-blocked.json` | Встроенный редактор правил (Маршрутизация → Правила → ⋮ → Импорт из файла) | Импорт правил из файла/буфера (Маршрутизация → ⋮ → Импорт правил из буфера обмена) |

**JSON object** — содержит `domainStrategy`, `domainMatcher` и `rules` (массив). Используется v2rayN как отдельный файл пользовательской маршрутизации.

**JSON array** — массив объектов с полями `domain`, `ip`, `protocol`, `network`, `port`,
`outboundTag`, `enabled`, `looked`, `remarks`. Формат соответствует обсуждению
[v2rayNG Discussion #4761](https://github.com/2dust/v2rayNG/discussions/4761).
Используется как v2rayNG (импорт из буфера обмена или файла), так и встроенным
редактором правил v2rayN.

### Поля JSON array

| Поле | Тип | Обязательное | Описание |
|------|-----|-------------|----------|
| `domain` | string[] | нет | Доменные правила (geosite:, domain:, regexp:, full:) |
| `ip` | string[] | нет | IP-правила (geoip:, CIDR, отдельные IP) |
| `protocol` | string[] | нет | Протоколы (bittorrent) |
| `network` | string | нет | Тип сети (tcp, udp, tcp,udp) |
| `port` | string | нет | Порт или диапазон (0-65535, 443, 50000-65535) |
| `outboundTag` | string | **да** | Куда направлять (proxy/direct/block) |
| `enabled` | bool | **да** | Включено ли правило |
| `looked` | bool | нет | Внутренний флаг v2rayNG (рекомендуется false) |
| `remarks` | string | **да** | Описание правила |

**Источник формата:** [v2rayN Wiki — Description of custom routing rules](https://github.com/2dust/v2rayN/wiki/Description-of-custom-routing-rules)
и [v2rayNG Discussion #4761](https://github.com/2dust/v2rayNG/discussions/4761) (подтверждение поля `looked`).

### Способы импорта в v2rayNG

1. **Из буфера обмена (рекомендуется):** Откройте JSON в браузере → копировать всё
   → v2rayNG → Маршрутизация → ⋮ → Импорт правил из буфера обмена
2. **Из файла:** Скачайте JSON → переместите в `assets/` → Маршрутизация → ⋮ → Импорт правил из файла
3. **Deep link:** НЕ поддерживается (issue [#4280](https://github.com/2dust/v2rayNG/issues/4280) — «Not planned»)

### Доменная стратегия

После импорта правил обязательно смените доменную стратегию:

- **IPOnDemand (рекомендуется):** Запрашивать DNS только для доменов, которые
  реально используются. Наиболее эффективно для мобильных устройств.
- **IPIfNonMatch:** Разрешать домены в IP, если не нашлось доменного правила.
- **AsIs:** Не использовать geoip (отключает правила с `geoip:ru` и `geoip:ru-blocked`).

Настройка: v2rayNG → Маршрутизация → поле «Доменная стратегия».

## Сценарии использования

Два режима маршрутизации для разных сценариев:

| Файл (object) | Файл (array) | Сценарий | Дефолтный outbound |
|---------------|-------------|----------|-------------------|
| `routing-russia.json` | `v2rayng-routing-russia.json` | Домашний WiFi, ПК | proxy |
| `only_blocked.json` | `v2rayng-only-blocked.json` | Мобильный интернет РФ | direct |

## routing-russia.json — «Всё через прокси»

**Назначение:** максимальная защита приватности. Весь трафик идёт через VPN,
кроме явно разрешённого (российские ресурсы, приватные сети).

### Порядок правил

```
правила применяются СВЕРХУ ВНИЗ, первое совпадение побеждает
```

```
 1. geosite:category-ads-all      → block      ← блокировка рекламы (приоритет)
 2. geosite:ru-blocked            → proxy      ← заблокированные домены РФ
 3. geoip:ru-blocked              → proxy      ← заблокированные IP РФ
 4. DNS (1.0.0.1, 1.1.1.1,       → proxy      ← DoH через прокси (обходит блокировки)
     8.8.8.8, 8.8.4.4)
 5. UDP 50000-65535               → proxy      ← Discord VoIP
 6. geoip:ru                      → direct     ← все IP РФ напрямую
 7. .ru, .su, .xn--p1ai,          → direct     ← российские домены
    geosite:ru-available-only-inside
 8. geoip:ru-whitelist            → direct     ← CIDR вайтлист (hxehex)
 9. geoip:private                 → direct     ← локальные сети
10. geosite:private               → direct     ← приватные домены
11. ВСЁ ОСТАЛЬНОЕ (tcp,udp)      → proxy      ← через прокси
```

### Ключевые особенности

**Реклама блокируется приоритетно:** правила `category-ads-all` → block стоят
выше `ru-blocked` → proxy. Это гарантирует, что даже если рекламный домен
входит в список заблокированных, реклама всё равно будет заблокирована, а не
продавлена через прокси.

**Discord VoIP:** UDP-порт 50000-65535 выделен для голосовых вызовов.
Discord использует этот диапазон для прямых P2P-соединений, которые
блокируются на многих операторах РФ.

**DNS через прокси:** DoH-серверы Cloudflare (1.1.1.1) и Google (8.8.8.8)
маршрутизируются через прокси, так как прямые DNS-запросы к ним могут
подвергаться DPI-блокировке.

## only_blocked.json — «Только заблокированное»

**Назначение:** экономия трафика на мобильном интернете. Через прокси идёт
только то, что реально заблокировано на территории РФ. Остальное — напрямую.

### Порядок правил

```
 1. geosite:category-ads-all      → block      ← реклама
 2. geosite:ru-blocked            → proxy      ← заблокированные домены
 3. geoip:ru-blocked              → proxy      ← заблокированные IP
 4. DNS                           → proxy      ← DoH
 5. UDP 50000-65535               → proxy      ← Discord VoIP
 6. BitTorrent                    → direct     ← торренты напрямую
 7. geoip:ru                      → direct     ← все IP РФ
 8. .ru, .su, .xn--p1ai,          → direct     ← российские домены
    geosite:ru-available-only-inside
 9. geoip:ru-whitelist            → direct     ← CIDR вайтлист (hxehex)
10. geoip:private                 → direct     ← локальные сети
11. geosite:private               → direct     ← приватные домены
12. ВСЁ ОСТАЛЬНОЕ (tcp,udp)      → direct     ← напрямую (НЕ через прокси!)
```

### Ключевые отличия от routing-russia.json

| Аспект | routing-russia.json | only_blocked.json |
|--------|---------------------|-------------------|
| Default outbound | proxy | direct |
| BitTorrent | через прокси | напрямую |
| Использование трафика | высокий (весь трафик через VPN) | низкий (только заблокированное) |
| Когда использовать | Домашний WiFi, ПК | Мобильный интернет, лимитный трафик |

## config-template-xray.json — шаблон Xray-core

Шаблон используется v2rayN как основа для генерации конфигурации Xray-core.

### Структура

```json
{
  "policy":        // Политики: уровни логирования, соединений
  "dns":           // DNS: DoH через Cloudflare + Google + localhost
  "inbounds":      // Входящие: SOCKS5 :10808, HTTP :10809
  "outbounds":     // Исходящие: proxy, direct, block (+ reality-фрагменты)
  "routing":       // Роутинг: ru-blocked, ru-whitelist, private
}
```

### Outbound-ы

| Tag | Протокол | Назначение |
|-----|----------|-----------|
| `proxy` | VLESS/XTLS/REALITY | Основное прокси-соединение |
| `direct` | freedom | Прямой выход без прокси |
| `block` | blackhole | Блокировка трафика (роняет пакеты) |

**Фрагментация (fragment):**
- `packets: tlshello`
- `length: 100-200`
- `interval: 10-20`
- Режим: `tcp`

Параметры фрагментации подобраны для обхода DPI-блокировок на основе
анализа TLS-рукопожатия.

### DNS

```
1. https://1.1.1.1/dns-query    (Cloudflare, через прокси)
2. https://1.0.0.1/dns-query    (Cloudflare fallback)
3. localhost                     (системный резолвер, fallback)
```

**Важно:** DNS-запросы маршрутизируются через прокси правилами в
`routing-russia.json` / `only_blocked.json` (правило №4 в обоих файлах).

### Важные настройки

- `domainStrategy: IPOnDemand` — DNS-запросы только для доменов, которые реально
  используются (эффективно для мобильных и экономит трафик)
- `tcpUserTimeout: 10000` — таймаут TCP (Linux-specific)
- `tcpcongestion: bbr` — алгоритм перегрузки BBR (требуется поддержка ядра)
- `pinnedPeerCertSha256` — замена `allowInsecure`. Два формата: hex (`ae24...77`)
  или OpenSSL (`AE:24:...:77`). Документация: [xtls.github.io](https://xtls.github.io/config/features/certValidate.html)
