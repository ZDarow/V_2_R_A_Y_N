# Архитектура проекта

Обзор компонентов, потоков данных, зависимостей и ключевых решений.

## Содержание

1. [Общая схема](#общая-схема)
2. [Компоненты](#компоненты)
3. [Поток данных](#поток-данных)
4. [Скрипты и их взаимосвязи](#скрипты-и-их-взаимосвязи)
5. [CI/CD пайплайн](#cicd-пайплайн)
6. [Мобильная архитектура](#мобильная-архитектура)
7. [Ключевые решения](#ключевые-решения)

---

## Общая схема

```
┌────────────────────────────────────────────────────────────┐
│                    ПОЛЬЗОВАТЕЛЬ                            │
│  v2rayN GUI  ←→  systemctl  ←→  command line              │
└──────────────────┬─────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────┐
│              СКРИПТЫ УПРАВЛЕНИЯ                             │
│  status.sh  diagnose.sh  proxy-toggle.sh  kill-switch.sh   │
│  update-rules.sh  migrate-allowinsecure.sh  apply-configs  │
│  diagnose-network.sh                                        │
└──────────────────┬─────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────┐
│              БИБЛИОТЕКИ                                     │
│  lib/common.sh (retry, SHA256, lock, log)                  │
│  proxy_set_linux_sh.sh (GNOME/KDE proxy helpers)           │
└──────────────────┬─────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────┐
│              КОНФИГУРАЦИЯ                                   │
│  config/config-template-xray.json  (шаблон Xray-core)      │
│  config/routing-russia.json        (роутинг #1)            │
│  config/only_blocked.json          (роутинг #2)            │
│  ~/.config/v2rayN/                 (пользовательские)      │
└──────────────────┬─────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────┐
│              СИСТЕМНЫЕ КОМПОНЕНТЫ                           │
│  v2rayN (GUI) → Xray-core (прокси)                        │
│  systemd user services + timers                            │
│  iptables/nftables (kill-switch)                           │
│  gsettings/kwriteconfig (системный прокси)                 │
└────────────────────────────────────────────────────────────┘
```

---

## Компоненты

### 1. v2rayN (GUI)

**Назначение:** графический интерфейс для управления Xray-core.

- Платформа: Linux (и Windows)
- Язык: C# (.NET 10.0+)
- Управление: подписки, серверы, роутинг, логи
- Порт GUI: не использует сетевые порты (взаимодействует с Xray-core локально)

### 2. Xray-core (ядро)

**Назначение:** прокси-ядро, обеспечивающее маршрутизацию и шифрование трафика.

- Версия: v26.3.27+ (автоматически обновляется вместе с v2rayN)
- Конфигурация: `config-template-xray.json` → `{dataDir}/binConfigs/`
- Inbounds:
  - SOCKS5 `127.0.0.1:10808`
  - HTTP `127.0.0.1:10809`
- Поддерживаемые протоколы: VLESS, VMess, Shadowsocks, Trojan, Hysteria2
- Рекомендуемый: **VLESS + REALITY + XTLS-Vision**

### 3. Конфигурационные файлы

| Файл | Формат | Назначение |
|------|--------|-----------|
| `config-template-xray.json` | JSON Object | Шаблон Xray-core (policy, DNS, inbounds, outbounds, routing) |
| `routing-russia.json` | JSON Object | Правила роутинга «Всё через прокси» |
| `only_blocked.json` | JSON Object | Правила роутинга «Только заблокированное» |

### 4. Systemd-интеграция

| Юнит | Тип | Назначение |
|------|-----|-----------|
| `v2rayn.service` | user service | Запуск v2rayN как демона |
| `v2rayn-rules-update.service` | oneshot | Обновление geoip/geosite |
| `v2rayn-rules-update.timer` | timer | Еженедельный запуск update |

### 5. Systemd-интеграция (продолжение)

| Компонент | Назначение |
|-----------|-----------|
| `v2rayn.desktop` | XDG Autostart — автозапуск при входе |
| `v2rayn` logrotate | Ротация логов v2rayN |

### 6. Правила geoip/geosite

- **Источник:** `runetfreedom/russia-v2ray-rules-dat` (ветка `release`)
- **Обновление:** каждые 6 часов в источнике, еженедельно на клиенте
- **Формат:** `.dat` бинарные файлы (geoip.dat, geosite.dat)
- **Местоположение:** `~/.local/share/v2rayN/bin/`
- **Кэш:** `~/.cache/v2rayN/rules/` (offline fallback)

---

## Поток данных

```
Пользовательское приложение (браузер, Telegram, ...)
    │
    ▼
┌──────────────────┐
│  Системный прокси │  ← SOCKS5 :10808 / HTTP :10809
│  (если включён)   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Xray-core       │  ← policy, routing, DNS
│  (локально)      │
└────────┬─────────┘
         │
    ┌────┴────┐
    ▼         ▼
 direct    proxy (VPN-сервер)
    │         │
    ▼         ▼
 локально   Интернет через
 (РФ,       VPN (иностранный
 приватно)  сервер)
```

### DNS-поток

```
DNS-запрос → Xray-core → Routing:
  - Если домен в geosite:ru-blocked → proxy → DoH (dns.google, cloudflare-dns.com, dns.yandex.ru, dns.technic.su)
  - Если домен .ru / geoip:ru → direct → системный резолвер
  - Остальное → proxy → DoH
```

**DoH-серверы (4 шт.):** Google (8.8.8.8, 8.8.4.4), Cloudflare (1.1.1.1, 1.0.0.1), Yandex (77.88.8.8, 77.88.8.1), Technic (185.238.130.141).  
Маппинг доменов → IP в `dns.hosts` обеспечивает резолвинг DoH-серверов до включения DNS.

### Фрагментация (anti-DPI)

```
TLS ClientHello → Xray → Fragment:
  - Разбить на 2 части (length: 100-200 байт)
  - Интервал: 10-20 мс
  - Режим: tcp

Цель: DPI не может собрать TLS-рукопожатие целиком
и не может определить, что это VPN-соединение
```

---

## Скрипты и их взаимосвязи

```
install.sh ──→ устанавливает всё: v2rayN, geoip/geosite, конфиги,
│               подписки, скрипты, systemd, автозапуск
│
├── lib/common.sh ──→ общая библиотека (retry, SHA256, lock)
├── scripts/update-rules.sh ──→ обновление geoip/geosite
├── scripts/proxy-toggle.sh ──→ вкл/выкл системного прокси
├── scripts/proxy_set_linux_sh.sh ──→ библиотека прокси (source)
├── scripts/status.sh ──→ проверка состояния
├── scripts/diagnose.sh ──→ сбор диагностики
├── scripts/diagnose-network.sh ──→ сетевая диагностика
├── scripts/kill-switch.sh ──→ iptables kill-switch
└── scripts/migrate-allowinsecure.sh ──→ миграция сертификатов

uninstall.sh ──→ удаляет всё, создаёт бэкап

apply-configs.sh ──→ применяет/восстанавливает конфиги
```

---

## CI/CD пайплайн

```yaml
on: [push, pull_request, workflow_dispatch]

jobs:
  actionlint:      # Линтинг GitHub Actions YAML
  yamllint:        # Линтинг YAML-файлов
  shellcheck:      # Статический анализ shell-скриптов (severity: warning)
  bash-syntax:     # Проверка синтаксиса (bash -n)
  validate-json:   # Валидация JSON (python3 json.tool + JSON Schema)
  bats-tests:      # Модульные тесты (bats)
  markdown-check:  # Проверка Markdown-файлов
```

Подробнее: [ci.md](ci.md).

---

## Мобильная архитектура

Android-часть полностью отделена в директорию `mobile/`:

```
mobile/
├── config/         # Правила роутинга в JSON array (для v2rayNG)
├── scripts/        # deploy-mobile, generate-mobile-url, apply-routing, termux-setup
├── deploy-portal/  # Web-портал для деплоя на Android через браузер
├── docs/           # Документация мобильного деплоя
└── spec/           # JSON Schema для правил роутинга v2rayNG
```

**Методы деплоя** на Android (по приоритету):
1. **ADB** — через USB-отладку (стабильно, все файлы)
2. **HTTP/HTTPS** — через deploy-portal (браузер на телефоне)
3. **ZIP-архив** — скачать и распаковать на телефоне
4. **Termux** — автоматическая настройка через Termux-скрипты

Подробнее: [mobile/docs/mobile.md](../mobile/docs/mobile.md).

---

## Ключевые решения

### 1. Разделение Linux и Android

Основной проект — Linux-only. Всё Android-содержимое вынесено в `mobile/`.
Это упрощает CI, документацию и поддержку.

### 2. runetfreedom как источник geoip/geosite

Используется ветка `release` репозитория `runetfreedom/russia-v2ray-rules-dat`:
- Оптимизирована для РФ
- Обновляется каждые 6 часов
- SHA256 верификация
- Кэш для offline fallback

### 3. Три независимых JSON-конфига

- `config-template-xray.json` — шаблон для Xray-core (политики, DNS, fragment)
- `routing-russia.json` — роутинг «чёрный список» (всё через прокси)
- `only_blocked.json` — роутинг «белый список» (только заблокированное)

Это позволяет переключать режимы без перезаписи конфигурации ядра.

### 4. allowInsecure → pinnedPeerCertSha256

Xray-core v26.2.6+ (февраль 2026) удалил `allowInsecure`. Проект предоставляет:
- Миграционный скрипт (`migrate-allowinsecure.sh`)
- Документацию с примерами fingerprint'ов
- Два формата fingerprint: hex (64 символа) и OpenSSL (с двоеточиями)

### 5. Systemd timer для авто-обновления

- Предпочтительнее cron (user-level без root, логирование в journald)
- Еженедельный запуск со случайной задержкой до 6 часов
- Retry 3 попытки с экспоненциальной задержкой
- SHA256 верификация
- Lock-файл для предотвращения конкурентного запуска

### 6. Фрагментация TLS (anti-DPI)

На outbound `proxy` включена фрагментация:
- `packets: tlshello` — только TLS ClientHello
- `length: 100-200` — малые фрагменты
- `interval: 10-20` — интервал между фрагментами

Обходит DPI, анализирующий TLS-рукопожатие целиком.

### 7. JSON Schema валидация

- `config-template-xray.json` проверяется по `spec/json-schema/xray-config.json`
- `mobile/config/v2rayng-*.json` проверяются по `mobile/spec/json-schema/routing-rules.json`
- CI включает ajv (JSON Schema валидатор) в пайплайн
