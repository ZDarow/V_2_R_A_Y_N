# Часто задаваемые вопросы (FAQ)

## Установка

### Что делать, если dotnet-runtime-10.0 не устанавливается?

Убедитесь, что у вас добавлен Microsoft-репозиторий пакетов:

```bash
# Добавить репозиторий Microsoft (Ubuntu/Debian)
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install dotnet-runtime-10.0
```

Или скачайте вручную с [dotnet.microsoft.com](https://dotnet.microsoft.com/download).

### v2rayN не запускается после установки. Что делать?

1. Проверьте версию .NET: `dotnet --version` (должно быть 10+)
2. Проверьте бинарник: `which v2rayn` или `ls -la /opt/v2rayN/v2rayn`
3. Запустите из терминала: `v2rayn` — посмотрите вывод ошибок
4. Проверьте лог: `~/.local/share/v2rayN/Logs/`

### Работает ли скрипт на Wayland?

Да. Системный прокси через `gsettings` работает и на Wayland (GNOME).
Исключение: старые версии GNOME на Wayland могут не иметь схемы
`org.gnome.system.proxy` — скрипт проверяет её наличие.

### Работает ли на Fedora/RHEL?

Да, поддерживаются:
- Fedora 38+ (dnf)
- RHEL 9+ (dnf)
- Arch Linux (pacman)

Однако v2rayN устанавливается только как `.deb` пакет. На Fedora/Arch
скрипт скопирует бинарник в `/opt/v2rayN/` и создаст symlink.

### Скрипт не нашёл пакетный менеджер

install.sh поддерживает `apt-get`, `dnf`, `pacman`. Если ваша система
использует другой менеджер (apk, emerge, zypper), установите зависимости
вручную: `git wget curl sqlite3 ca-certificates`.

## Конфигурация

### Почему реклама блокируется, а не идёт через прокси?

Правило `geosite:category-ads-all` → `block` стоит ПЕРВЫМ в обоих
конфигах. Это осознанное решение: рекламные домены не должны проксироваться
даже если они есть в списке заблокированных. Реклама не будет грузиться,
а значит не будет тратить трафик прокси.

### Как добавить свой домен в исключения?

Добавьте правило в соответствующий JSON-файл:

```json
{
  "type": "field",
  "domain": ["domain:мой-домен.рф"],
  "outboundTag": "direct"
}
```

Поместите правило ДО дефолтного (последнего) правила.

### Пропали настройки после обновления v2rayN

v2rayN может перезаписать файлы конфигурации при обновлении.
Повторно запустите install.sh для восстановления конфигов:

```bash
./install.sh --skip-v2rayn
```

### allowInsecure — что делать?

**Xray-core отключает allowInsecure с 1 августа 2026.**

В v2rayN:
1. Откройте настройки подписки
2. Найдите параметр allowInsecure — **выключите его**
3. Включите `verifyPeerCertByName` (проверка сертификата по имени)

В v2rayNG:
1. Откройте настройки подписки
2. Включите «Отпечаток сертификата» (pinnedPeerCertSha256)

### Где взять отпечаток SHA256 сертификата (fingerprint)?

```bash
openssl s_client -connect example.com:443 < /dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256
```

Или скопируйте fingerprint из настроек подписки v2rayN (если уже настроено).

## Мобильная версия

### Как перенести конфиги на Android без USB-кабеля?

Используйте HTTP-режим deploy-mobile.sh:

```bash
./scripts/deploy-mobile.sh --server
# → Сервер на http://192.168.1.100:8080
```

На телефоне откройте браузер, перейдите по адресу, скачайте ZIP-архив.

### v2rayNG не видит файлы в assets/

Проверьте:
1. Файлы лежат в правильной папке: `Android/data/com.v2ray.ang/files/assets/`
2. Путь указан относительно внутреннего хранилища (Internal Storage), не SD-карты
3. После копирования файлов перезапустите v2rayNG

### Почему на мобильном интернете лучше использовать only_blocked.json?

Мобильные операторы РФ часто блокируют по IP, а не по DNS.
`only_blocked.json` использует `domainStrategy: IPIfNonMatch` —
сначала проверяет доменные правила, и только если домен не найден —
резолвит IP и проверяет IP-правила. Это экономит трафик и ускоряет
загрузку сайтов.

### Не обновляются geoip/geosite в v2rayNG

Проблема «курицы и яйца»: для обновления правил нужен работающий прокси,
а для работы прокси нужны актуальные правила.

Решение: используйте deploy-mobile.sh:
```bash
./scripts/deploy-mobile.sh --zip   # создайте архив
# или
./scripts/deploy-mobile.sh --adb   # push через USB
```

## Системный прокси

### После включения прокси перестали открываться российские сайты

Проверьте, что в ignore-hosts добавлены `.ru`, `.su`, `.xn--p1ai`:

```bash
gsettings get org.gnome.system.proxy ignore-hosts
# → ['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']
```

### Прокси работает, но Telegram не подключается

Telegram Desktop использует системный прокси HTTP. Убедитесь что:
1. HTTP-прокси включён: `gsettings set org.gnome.system.proxy.http port 10809`
2. В настройках Telegram не включён встроенный SOCKS5 поверх системного
3. v2rayN запущен и выбран работающий сервер

### Как выключить системный прокси?

```bash
./scripts/proxy-toggle.sh off
```

Или вручную:
- GNOME: `gsettings set org.gnome.system.proxy mode 'none'`
- KDE: `kwriteconfig5 --file kioslaverc --group "Proxy Settings" --key ProxyType 0`

## Общие вопросы

### Чем отличаются geoip.dat разных авторов?

| Автор | Источник данных | Особенность |
|-------|----------------|-------------|
| Loyalsoldier | MaxMind GeoLite2 | Стандартный, идёт в составе v2rayNG |
| runetfreedom | РосКомСвобода, DPI-списки | Оптимизирован для РФ, обновляется каждые 6 часов |

Проект использует **runetfreedom** (ветка `release`) — он содержит
актуальные списки заблокированных ресурсов РФ.

### Как часто обновлять geoip/geosite?

- **Рекомендуется:** раз в неделю
- **runetfreedom release** обновляется каждые 6 часов
- Автоматически: через `update-rules.sh` (Linux) или `deploy-mobile.sh` (Android)

### REALITY — что это и зачем?

REALITY — протокол следующего поколения от XTLS, который:
- Устраняет TLS fingerprint сервера (неотличим от обычного HTTPS)
- Не требует фиксированного IP или домена
- Работает поверх TLS 1.3
- Использует CDN-серверы как прикрытие (например, `www.microsoft.com`)

Все подписки в проекте используют REALITY. `allowInsecure` несовместим
с REALITY.

### Могу ли я использовать свои подписки?

Да. install.sh импортирует 4 публичные подписки, но вы можете добавить
свои через GUI v2rayN/v2rayNG. Ваши подписки не будут перезаписаны
при повторном запуске install.sh (используется `INSERT OR IGNORE`).

### Почему BitTorrent в only_blocked.json идёт напрямую?

На мобильном интернете BitTorrent трафик через VPN:
1. Расходует дорогой трафик прокси-сервера
2. Замедляет работу прокси для других приложений
3. Может быть заблокирован хостингом прокси

В режиме «Всё через прокси» (routing-russia.json) BitTorrent идёт
через прокси — для максимальной приватности.
