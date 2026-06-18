# Документация v2rayN Russia Setup

Навигация по полной документации проекта.

## Разделы

| Раздел | Описание | Для кого |
|--------|----------|----------|
| [📦 Установка](INSTALL.md) | Полное руководство по установке и удалению | Все пользователи |
| [🚀 Использование](USAGE.md) | Ежедневная работа: запуск, прокси, обновление | Все пользователи |
| [🏗 Архитектура](ARCHITECTURE.md) | Обзор компонентов, потоков данных, зависимостей | Разработчики |
| [⚙️ Конфигурация](CONFIGURATION.md) | Описание всех конфигурационных файлов | Продвинутые пользователи |
| [🔧 Скрипты](SCRIPTS.md) | Справочник всех скриптов и библиотек | Администраторы |
| [🛠 Устранение неполадок](TROUBLESHOOTING.md) | Диагностика и решение проблем | Все пользователи |
| [❓ FAQ](FAQ.md) | Часто задаваемые вопросы | Все пользователи |
| [🔄 CI/CD](ci.md) | Непрерывная интеграция GitHub Actions | Разработчики |
| [📱 Мобильное устройство](../mobile/docs/mobile.md) | Настройка v2rayNG на Android | Пользователи Android |
| [📋 Подписки](../subscriptions/README.md) | Список подписок для импорта | Все пользователи |

## Быстрый старт за 30 секунд

```bash
# Установка одной командой
bash <(curl -sSL https://raw.githubusercontent.com/ZDarow/V_2_R_A_Y_N/main/install.sh)

# Запуск v2rayN
v2rayn

# Включение системного прокси
~/.local/share/v2rayN/scripts/proxy-toggle.sh on
```

## Структура репозитория

```
V_2_R_A_Y_N/
├── config/               # Конфигурационные файлы Xray-core
├── docs/                 # Документация (этот раздел)
├── lib/                  # Библиотеки: common.sh, systemd, logrotate, autostart
├── mobile/               # Всё для Android (v2rayNG)
├── scripts/              # Скрипты управления и диагностики
├── spec/                 # BATS-тесты и JSON Schema
├── subscriptions/        # Список подписок
├── install.sh            # Установщик
├── uninstall.sh          # Деинсталлятор
├── apply-configs.sh      # Применение конфигов
├── .github/workflows/    # CI/CD пайплайны
└── .vscode/              # Конфигурация редактора
```

## Где искать

| Если нужно... | Откройте |
|---------------|----------|
| Установить v2rayN | [INSTALL.md](INSTALL.md) |
| Настроить роутинг | [CONFIGURATION.md](CONFIGURATION.md) |
| Включить/выключить прокси | [SCRIPTS.md](SCRIPTS.md#proxy-togglesh) |
| Обновить geoip/geosite | [SCRIPTS.md](SCRIPTS.md#update-rulessh) |
| Проверить состояние | [USAGE.md](USAGE.md#мониторинг) |
| Диагностировать сеть | [SCRIPTS.md](SCRIPTS.md#diagnose-networksh) |
| Включить kill-switch | [SCRIPTS.md](SCRIPTS.md#kill-switchsh) |
| Настроить Android | [mobile/docs/mobile.md](../mobile/docs/mobile.md) |
| Исправить ошибку | [TROUBLESHOOTING.md](TROUBLESHOOTING.md) |
| Понять архитектуру | [ARCHITECTURE.md](ARCHITECTURE.md) |

## Условные обозначения

- `$` — команда от обычного пользователя
- `#` — команда от root
- `~/.config/v2rayN/` — конфигурационные файлы v2rayN
- `~/.local/share/v2rayN/` — данные: бинарники, скрипты, geoip/geosite
- `~/.local/bin/v2rayn` — symlink для запуска v2rayN
