# v2rayN Russia Setup

Автоматизированная настройка **v2rayN** для работы в условиях блокировок
на территории Российской Федерации.

[![CI](https://github.com/ZDarow/V_2_R_A_Y_N/actions/workflows/ci.yml/badge.svg)](https://github.com/ZDarow/V_2_R_A_Y_N/actions/workflows/ci.yml)

---

## Возможности

- **Автоматическая установка** v2rayN одной командой (Linux)
- **Два режима роутинга**: «Всё через прокси» и «Только заблокированное»
- **Актуальные правила** geoip/geosite от runetfreedom с еженедельным авто-обновлением
- **Проверенные подписки** VLESS + REALITY + XTLS-Vision
- **Фрагментация TLS** для обхода DPI
- **Kill-switch** на iptables (защита от утечек)
- **Системный прокси** для GNOME и KDE
- **Сетевая диагностика** (14 секций проверок)
- **Мобильный деплой** на Android (ADB / ZIP / HTTP / Termux)
- **CI/CD**: shellcheck, bash -n, JSON Schema, BATS тесты, markdown

---

## Быстрый старт

```bash
# Установка одной командой
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)

# Запуск v2rayN
v2rayn &

# Включение системного прокси
~/.local/share/v2rayN/scripts/proxy-toggle.sh on

# Проверка состояния
~/.local/share/v2rayN/scripts/status.sh
```

---

## Краткая документация

| Раздел | Содержание |
|--------|-----------|
| [📦 Установка](docs/INSTALL.md) | Полное руководство по установке и удалению |
| [🚀 Использование](docs/USAGE.md) | Ежедневная работа: запуск, прокси, обновление, диагностика |
| [🏗 Архитектура](docs/ARCHITECTURE.md) | Компоненты, потоки данных, ключевые решения |
| [⚙️ Конфигурация](docs/CONFIGURATION.md) | Все конфигурационные файлы, режимы роутинга |
| [🔧 Скрипты](docs/SCRIPTS.md) | Справочник всех скриптов и библиотек |
| [🛠 Устранение неполадок](docs/TROUBLESHOOTING.md) | Диагностика и решение проблем |
| [❓ FAQ](docs/faq.md) | Часто задаваемые вопросы |
| [🔄 CI/CD](docs/ci.md) | Непрерывная интеграция GitHub Actions |
| [📱 Android](mobile/docs/mobile.md) | Настройка v2rayNG на Android |
| [📋 Подписки](subscriptions/README.md) | Список подписок для импорта |

---

## Флаги установщика

```bash
./install.sh [--help] [--force-reinstall] [--skip-v2rayn] [--repo-url <url>]
```

| Флаг | Описание |
|------|----------|
| `--help` | Показать справку |
| `--force-reinstall` | Переустановить v2rayN, даже если уже установлен |
| `--skip-v2rayn` | Не устанавливать v2rayN (только конфиги и подписки) |
| `--repo-url <url>` | URL репозитория (по умолчанию: ZDarow/V_2_R_A_Y_N) |

---

## Режимы роутинга

Проект предоставляет два режима для разных сценариев:

### `routing-russia.json` — Всё через прокси (чёрный список)

Весь TCP/UDP трафик идёт через прокси, кроме российских ресурсов
и приватных сетей. **Рекомендуется для ПК и домашнего WiFi.**

### `only_blocked.json` — Только заблокированное (белый список)

Через прокси идёт только то, что реально заблокировано в РФ.
Остальное — напрямую. **Для IP-whitelist и экономии трафика.**

Подробнее: [CONFIGURATION.md](docs/CONFIGURATION.md).

---

## Рекомендуемый протокол: VLESS + REALITY + XTLS-Vision

REALITY полностью устраняет TLS fingerprint сервера — DPI видит обычное
TLS-соединение с реальным сайтом (Microsoft, Cloudflare и т.д.).

```
Базовая конфигурация сервера:
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

### Фрагментация TLS (анти-DPI)

Для протоколов без REALITY включена фрагментация TLS ClientHello:
- `length: 100-200` — размер фрагментов (байт)
- `interval: 10-20` — интервал между фрагментами (мс)

---

## ⚠️ allowInsecure удалён в Xray v26.2.6+ (февраль 2026)

**Заменён на `pinnedPeerCertSha256`.** Миграция:

```bash
./scripts/migrate-allowinsecure.sh
```

Подробнее: [faq.md](docs/faq.md#allowinsecure--что-делать).

---

## Two-server схема (обход IP-whitelist)

```
Клиент (РФ) → РФ-сервер (белый IP) → Иностранный сервер → Интернет
```

1. VPS в РФ с IP, не находящимся под whitelist-блокировкой
2. Xray как прокси-переходник
3. Трафик через РФ-сервер → иностранный сервер → цель

---

## Источники

- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — правила geoip/geosite для РФ
- [runetfreedom/russia-v2ray-custom-routing-list](https://github.com/runetfreedom/russia-v2ray-custom-routing-list) — шаблоны маршрутизации
- [igareck/vpn-configs-for-russia](https://github.com/igareck/vpn-configs-for-russia) — конфиги и списки
- [zieng2/wl](https://github.com/zieng2/wl) — белые списки
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — Xray-core
- [2dust/v2rayN](https://github.com/2dust/v2rayN) — v2rayN GUI

## Лицензия

MIT License. Copyright (c) 2026.

## 🛠️ Пользовательские скрипты

### Диагностика
- `scripts/netcheck.sh` — полная диагностика сети
- `scripts/mobile-netcheck.sh` — диагностика мобильного интернета
- `scripts/detect-block-type.sh` — определение типа блокировки (SNI/IP/Combined)

### Управление
- `scripts/v2ray-manager.sh` — единый менеджер (CLI + GUI)
- `scripts/proxy-manager-gui.sh` — графический интерфейс
- `scripts/rotate-sni.sh` — смена SNI для обхода блокировок

### Обслуживание
- `scripts/restore-all.sh` — восстановление настроек
- `scripts/optimize-mobile.sh` — оптимизация для мобильного
- `scripts/v2ray-fix-all.sh` — полная диагностика и автоисправление
- `scripts/setup-two-server.sh` — настройка двухсерверной схемы

### Анализ
- `scripts/traffic-capture.sh` — захват трафика для Wireshark

### Использование
```bash
# Диагностика
./scripts/netcheck.sh
./scripts/detect-block-type.sh          # Определить тип блокировки

# GUI менеджер
./scripts/proxy-manager-gui.sh

# Ротация SNI
./scripts/rotate-sni.sh                 # Случайная смена SNI
./scripts/rotate-sni.sh --list          # Показать доступные SNI

# Захват трафика
./scripts/traffic-capture.sh --all

# Two-server схема
./scripts/setup-two-server.sh --check   # Проверить, нужна ли
./scripts/setup-two-server.sh --gen-config  # Сгенерировать конфиги
