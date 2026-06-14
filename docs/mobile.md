# Мобильный деплой (v2rayNG)

## v2rayNG — Android-клиент

**v2rayNG** (58k ★) — официальный Android-клиент от 2dust, основанный на Xray-core.
Все конфигурационные файлы из репозитория (`routing-russia.json`, `only_blocked.json`,
`config-template-xray.json`) полностью совместимы с v2rayNG.

### Структура файлов на Android

```
/sdcard/
└── Android/
    └── data/
        └── com.v2ray.ang/
            └── files/
                └── assets/           ← Пользовательские файлы
                    ├── geoip.dat
                    ├── geosite.dat
                    ├── routing-russia.json
                    ├── only_blocked.json
                    └── config-template-xray.json
```

## deploy-mobile.sh — автоматический деплой

Скрипт для автоматической загрузки и доставки конфигов на Android-устройство.
Решает проблему «курицы и яйца» — когда для скачивания geoip/geosite нужен
работающий прокси, а для настройки прокси нужны geoip/geosite.

### Режимы работы

#### 1. ZIP-архив (`--zip`)

Создаёт архив `v2rayNG-mobile-config-YYYYMMDD.zip`, который можно перенести на
телефон любым способом (USB, Bluetooth, облако).

```bash
./scripts/deploy-mobile.sh --zip
# → создан v2rayNG-mobile-config-20260615.zip (2.3 MB)
```

На телефоне распакуйте содержимое папки `assets/` в:
`Android/data/com.v2ray.ang/files/assets/`

#### 2. ADB push (`--adb`)

Прямая передача файлов на подключённый телефон через USB-отладку.

```bash
# Установка adb (если не установлен):
sudo apt-get install android-tools-adb

# Включите на телефоне: Настройки → Для разработчиков → Отладка по USB

# Подключите телефон по USB и подтвердите отладку

# Запуск деплоя:
./scripts/deploy-mobile.sh --adb
```

Скрипт проверяет:
- Наличие `adb` в системе
- Подключено ли устройство (`adb devices`)
- Создаёт целевую директорию на телефоне
- Push всех файлов с индикацией прогресса

#### 3. HTTP-сервер (`--server`)

Запускает HTTP-сервер на компьютере. Телефон скачивает файлы через браузер по WiFi.

```bash
./scripts/deploy-mobile.sh --server
# → Сервер запущен на http://192.168.1.100:8080
```

На телефоне (в браузере):
1. Откройте `http://<IP-компьютера>:8080`
2. Перейдите в папку `assets/`
3. Скачайте ZIP-архив или отдельные файлы

**Плюсы:** не требует установки ПО на телефон, не требует USB-кабеля.
**Минусы:** требуется одна WiFi-сеть.

#### 4. Только правила (`--rules-only`)

Комбинируется с любым режимом для загрузки только geoip/geosite без конфигов:

```bash
./scripts/deploy-mobile.sh --adb --rules-only
./scripts/deploy-mobile.sh --zip --rules-only
```

### Что делает скрипт (все режимы)

```
 1. Создаёт временную директорию с trap-очисткой
 2. Скачивает geoip.dat     — из runetfreedom (ветка release)
 3. Скачивает geosite.dat   — из runetfreedom (ветка release)
 4. Валидирует .dat файлы   — проверка на пустоту/повреждение
 5. Копирует конфиги        — routing-russia.json, only_blocked.json, config-template-xray.json
 6. Создаёт README-Android   — инструкция на русском для телефона
 7. Доставляет на телефон    — ZIP / ADB / HTTP
```

### Требования

| Режим | Зависимость |
|-------|------------|
| `--zip` | `zip` (apt install zip) |
| `--adb` | `adb` (android-tools-adb), USB-отладка на телефоне |
| `--server` | python3 (есть в любой системе) |

## Настройка v2rayNG после деплоя

### Шаг 1. Импорт подписок

В приложении v2rayNG:
1. Нажмите `+` → `Импорт из буфера обмена` или `Импорт по URL`
2. Добавьте подписки из `subscriptions/README.md`

**URL подписок для быстрого копирования:**
- Чёрные списки (весь трафик через VPN): https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/BLACK_VLESS_RUS_mobile.txt
- Белые списки (только РФ через VPN): https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/refs/heads/main/Vless-Reality-White-Lists-Rus-Mobile.txt
- WL от zieng2: https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt

### Шаг 2. Выбор файла роутинга

1. Настройки → Настройки маршрутизации
2. Включите «Пользовательский файл роутинга»
3. Выберите файл:
   - `routing-russia.json` — весь трафик через прокси (домашний WiFi)
   - `only_blocked.json` — только заблокированные ресурсы (мобильный интернет)

### Шаг 3. Отпечаток сертификата (allowInsecure)

**v2rayNG 2.2.3 полностью удалил allowInsecure.** Вместо него используется
только `pinnedPeerCertSha256` (привязка к отпечатку SHA256 сертификата).

Для каждой подписки:
1. Откройте настройки подписки (долгое нажатие → карандаш)
2. Включите «Отпечаток сертификата» (certificate fingerprint)
3. Если fingerprint не указан — скопируйте из конфигурации v2rayN (или
   получите через openssl: `openssl s_client -connect example.com:443 | openssl x509 -noout -fingerprint -sha256`)

### Шаг 4. Проверка

1. Выберите сервер из подписки
2. Нажмите «V» (вибро) для подключения
3. Проверьте: https://www.google.com — должен открываться
4. Проверьте: https://yandex.ru — может открываться напрямую (в режиме only_blocked)

## Проблема «курицы и яйца»

При первом запуске v2rayNG не может скачать geoip/geosite из runetfreedom,
потому что у него ещё нет работающего прокси.

**Решения (в порядке предпочтения):**

1. **deploy-mobile.sh (рекомендуется):**
   ```bash
   ./scripts/deploy-mobile.sh --adb
   ```
   Переносит geoip/geosite на телефон до первого запуска.

2. **Временный публичный VPN:**
   Установите любой VPN, скачайте geoip/geosite в v2rayNG через меню обновления,
   отключите VPN.

3. **Встроенные правила Loyalsoldier:**
   v2rayNG поставляется с geoip/geosite от Loyalsoldier — они уже есть в APK.
   Можно не заменять их сразу, а обновить позже через меню v2rayNG
   (требуется работающий прокси).

## Отличия v2rayNG от v2rayN

| Возможность | v2rayN (Linux) | v2rayNG (Android) |
|-------------|----------------|-------------------|
| Интерфейс | Avalonia (десктоп) | Material Design (мобильный) |
| TUN-режим | Через Xray-core TUN | Стандартный Android VPN |
| Системный прокси | GNOME/KDE Settings | Android VPN API (встроен) |
| Fragment | ✓ (конфиг Xray) | ✓ (через Xray-core) |
| XHTTP | ✓ (через подписки) | ✓ (через подписки) |
| Подписки | URL-импорт в SQLite | URL-импорт напрямую |
| geoip/geosite | automatic (update-rules.sh) | deploy-mobile.sh или ручная замена |
| allowInsecure | удалён в 7.22.6+ | удалён в 2.2.3 |
| pinnedPeerCertSha256 | поддерживается | **обязателен** |
