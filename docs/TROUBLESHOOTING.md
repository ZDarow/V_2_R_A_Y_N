# Устранение неполадок

Диагностика и решение типовых проблем при установке и использовании v2rayN.

## Содержание

1. [Проблемы установки](#проблемы-установки)
2. [Проблемы запуска](#проблемы-запуска)
3. [Проблемы подключения](#проблемы-подключения)
4. [Проблемы сети и DNS](#проблемы-сети-и-dns)
5. [Проблемы прокси](#проблемы-прокси)
6. [Проблемы kill-switch](#проблемы-kill-switch)
7. [Проблемы обновления правил](#проблемы-обновления-правил)
8. [Диагностические команды](#диагностические-команды)
9. [Сбор информации для Issue](#сбор-информации-для-issue)

---

## Проблемы установки

### dotnet-runtime-10.0 не устанавливается

**Симптом:** `install.sh` останавливается на установке .NET 10.0.

**Решение:**

```bash
# Добавить Microsoft-репозиторий вручную (Ubuntu/Debian)
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install dotnet-runtime-10.0
```

**Если ваша система не поддерживает .NET 10.0:**
v2rayN 7.22+ требует .NET 10.0. Используйте Ubuntu 24.04+, Debian 12+ или Fedora 40+.

### install.sh не нашёл пакетный менеджер

**Симптом:** предупреждение «Не удалось определить пакетный менеджер».

**Решение:** Установите зависимости вручную:
- Debian/Ubuntu: `sudo apt-get install git wget curl sqlite3 ca-certificates`
- Fedora/RHEL: `sudo dnf install git wget curl sqlite ca-certificates`
- Arch: `sudo pacman -S git wget curl sqlite ca-certificates`

### v2rayN не запускается после установки

**Пошаговая диагностика:**

```bash
# 1. Проверить .NET
dotnet --version
# Должно быть 10.0+

# 2. Проверить бинарник
which v2rayn
ls -la $(which v2rayn)

# 3. Запустить из терминала (увидеть ошибки)
v2rayn

# 4. Проверить логи
ls -la ~/.local/share/v2rayN/Logs/
cat ~/.local/share/v2rayN/Logs/*.log
```

### install.sh на Fedora/Arch не устанавливает v2rayN

**Причина:** v2rayN распространяется только как .deb пакет.
На Fedora/Arch скрипт копирует бинарник в `/opt/v2rayN/`.

**Решение:** Если `/opt/v2rayN/v2rayn` не создан, установите вручную:
1. Скачайте .deb с GitHub Releases
2. Распакуйте: `dpkg-deb -x v2rayN*.deb /tmp/v2rayn`
3. Скопируйте: `sudo cp -r /tmp/v2rayn/opt/v2rayN /opt/`
4. Создайте symlink: `ln -s /opt/v2rayN/v2rayn ~/.local/bin/v2rayn`

---

## Проблемы запуска

### v2rayN не стартует (ошибка сегментации)

**Симптом:** `Segmentation fault` или `Fatal error.` при запуске.

**Решение:**
1. Проверьте .NET: `dotnet --info`
2. Удалите кэш: `rm -rf ~/.local/share/v2rayN/Logs/`
3. Запустите с отладкой: `dotnet /opt/v2rayN/v2rayn.dll`
4. Если segfault остаётся — проблема в версии .NET или Xray-core

### Systemd сервис не запускается

```bash
# Проверить статус
systemctl --user status v2rayn.service

# Посмотреть лог
journalctl --user -u v2rayn.service -n 50 --no-pager

# Перезапустить
systemctl --user restart v2rayn.service

# Включить автозапуск
systemctl --user enable v2rayn.service
```

**Если сервис в состоянии `failed`:**
```bash
systemctl --user reset-failed v2rayn.service
systemctl --user restart v2rayn.service
```

### Пропали настройки после обновления v2rayN

**Решение:** Восстановите конфиги через install.sh:

```bash
./install.sh --skip-v2rayn
```

Или вручную:

```bash
./apply-configs.sh --all
```

---

## Проблемы подключения

### Нет соединения через прокси

**Пошаговая проверка:**

```bash
# 1. Проверить, что v2rayN запущен
ps aux | grep v2rayn

# 2. Проверить порты
ss -tlnp | grep -E '10808|10809'

# 3. Проверить статус
~/.local/share/v2rayN/scripts/status.sh

# 4. Проверить прокси через curl
curl -x socks5://127.0.0.1:10808 https://ifconfig.me
curl -x http://127.0.0.1:10809 https://ifconfig.me

# 5. Сетевая диагностика
./scripts/diagnose-network.sh
```

### Сервер в подписке не подключается

**Причины:**
1. Сервер заблокирован на стороне провайдера
2. Закончился трафик/срок действия подписки
3. Неверный протокол в конфиге

**Решение:**
1. Попробуйте другой сервер из той же подписки
2. Обновите подписку в v2rayN
3. Используйте другую подписку (BLACK / WHITE)
4. Проверьте allowInsecure → pinnedPeerCertSha256 (см. FAQ)

### Ошибка «The feature allowInsecure has been removed»

**Причина:** Xray-core v26.2.6+ удалил `allowInsecure`.

**Решение:**
```bash
# Автоматическая миграция allowInsecure → pinnedPeerCertSha256
./scripts/migrate-allowinsecure.sh
```

Или вручную: замените в конфиге:
```json
// Было
"allowInsecure": true

// Стало
"pinnedPeerCertSha256": ["ae243d668ec9c7f74a0dcd1ad21c6676b4efe30c39728934b362093af886bf77"]
```

### REALITY не работает

**Причина:** REALITY несовместим с `allowInsecure`.
Убедитесь, что в конфиге нет `allowInsecure` — REALITY работает
поверх TLS 1.3 без обычной валидации сертификата.

---

## Проблемы сети и DNS

### Сайты не открываются после включения прокси

**Симптом:** после `proxy-toggle.sh on` перестали открываться любые сайты.

**Решение:**

```bash
# 1. Проверить, что v2rayN запущен и выбрал работающий сервер
# 2. Проверить ignore-hosts
gsettings get org.gnome.system.proxy ignore-hosts
# Ожидается: ['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']

# 3. Временно выключить прокси для отладки
gsettings set org.gnome.system.proxy mode 'none'
```

### Российские сайты идут через прокси (медленно)

**Причина:** не добавлены `.ru`, `.su`, `.xn--p1ai` в ignore-hosts прокси.

**Решение:**
```bash
# Включить прокси с корректными ignore-hosts
./scripts/proxy-toggle.sh on
```

Проверьте, что ignore-hosts содержат российские домены. Если нет —
отредактируйте `proxy-toggle.sh` или настройте вручную через `gsettings`.

### DNS не резолвится

```bash
# Проверить системный DNS
resolvectl status

# Проверить /etc/resolv.conf
cat /etc/resolv.conf

# Проверить DoH через прокси
curl -x socks5://127.0.0.1:10808 https://1.1.1.1/dns-query?name=google.com

# Сбросить DNS-кэш
sudo systemd-resolve --flush-caches
```

### Discord VoIP не работает

**Симптом:** Discord работает, но голосовые вызовы не соединяются.

**Причина:** Discord использует UDP 50000-65535 для P2P-голоса.
Этот диапазон должен маршрутизироваться через прокси.

**Решение:** Убедитесь, что в файле роутинга есть правило:
```json
{
  "type": "field",
  "port": "50000-65535",
  "network": "udp",
  "outboundTag": "proxy"
}
```

Это правило включено в оба файла роутинга по умолчанию.

---

## Проблемы прокси

### Proxy-toggle.sh не работает

**Симптом:** скрипт сообщает, что DE не поддерживается.

**Решение:**
1. Проверьте, что вы используете GNOME или KDE
2. Для GNOME: проверьте схему: `gsettings list-schemas | grep proxy`
3. Для KDE: проверьте `kwriteconfig5 --version`
4. Если вашего DE нет в списке — настройте прокси вручную

**Ручная настройка:**
```bash
# GNOME
gsettings set org.gnome.system.proxy mode 'manual'
gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
gsettings set org.gnome.system.proxy.socks port 10808
gsettings set org.gnome.system.proxy.http host '127.0.0.1'
gsettings set org.gnome.system.proxy.http port 10809
gsettings set org.gnome.system.proxy.https host '127.0.0.1'
gsettings set org.gnome.system.proxy.https port 10809
gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1', '*.local', '.ru', '.su', '.xn--p1ai']"

# Выключение
gsettings set org.gnome.system.proxy mode 'none'
```

### Telegram не подключается через прокси

**Симптом:** Telegram Desktop не отправляет сообщения при включённом прокси.

**Решение:**
1. Убедитесь, что HTTP-прокси включён (Telegram использует HTTP, а не SOCKS5)
2. Проверьте порт 10809: `curl -x http://127.0.0.1:10809 https://ifconfig.me`
3. В настройках Telegram **не** включайте встроенный SOCKS5 (будет двойное прокси)
4. Перезапустите Telegram

---

## Проблемы kill-switch

### Kill-switch блокирует весь трафик

**Симптом:** после включения kill-switch пропал интернет.

**Решение:**

```bash
# Выключить kill-switch
./scripts/kill-switch.sh off

# Если скрипт не отвечает — сбросить iptables вручную
sudo iptables -F V2RAYN 2>/dev/null
sudo iptables -D OUTPUT -j V2RAYN 2>/dev/null
sudo iptables -X V2RAYN 2>/dev/null
```

### Kill-switch не выключается

```bash
# Принудительный сброс всех правил iptables
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
```

**Внимание:** эта команда сбрасывает **все** правила iptables, не только kill-switch.

---

## Проблемы обновления правил

### update-rules.sh не скачивает правила

**Симптом:** ошибка загрузки или SHA256 не совпадает.

**Решение:**
1. Проверьте интернет: `ping -c 3 github.com`
2. Если GitHub заблокирован — зеркала пока недоступны для runetfreedom
3. Проверьте кэш: `ls -la ~/.cache/v2rayN/rules/`
4. Запустите с отладкой: `V2RAYN_BIN_DIR=/tmp ./scripts/update-rules.sh`

### Systemd timer не срабатывает

```bash
# Проверить список таймеров
systemctl --user list-timers --all | grep v2rayn

# Проверить, что юниты установлены
ls -la ~/.config/systemd/user/v2rayn-rules-update.*

# Переустановить таймер
./scripts/update-rules.sh --remove-timer
./scripts/update-rules.sh --install-timer

# Ручной запуск
systemctl --user start v2rayn-rules-update.service
journalctl --user -u v2rayn-rules-update.service -n 30
```

---

## Диагностические команды

Быстрый чек-лист для самостоятельной диагностики:

```bash
# 1. Статус v2rayN
~/.local/share/v2rayN/scripts/status.sh

# 2. Сетевая диагностика
./scripts/diagnose-network.sh --quick

# 3. Статус systemd
systemctl --user status v2rayn.service

# 4. Проверка портов
ss -tlnp | grep -E '10808|10809'

# 5. Проверка прокси через curl
curl -x socks5://127.0.0.1:10808 https://ifconfig.me
curl -x http://127.0.0.1:10809 https://ifconfig.me

# 6. Логи v2rayN
ls -la ~/.local/share/v2rayN/Logs/
cat ~/.local/share/v2rayN/Logs/*.log | tail -50

# 7. Доступность DNS
resolvectl status
cat /etc/resolv.conf

# 8. Правила iptables
sudo iptables -L V2RAYN -n 2>/dev/null || echo "Цепочка V2RAYN не найдена"
```

---

## Сбор информации для Issue

Если проблема не решается — соберите диагностику и создайте Issue
на [GitHub](https://github.com/ZDarow/V_2_R_A_Y_N/issues).

### Автоматический сбор

```bash
./scripts/diagnose.sh
# Создаёт архив с диагностической информацией
```

### Что включить в Issue

1. **Вывод `diagnose.sh`** или `status.sh`
2. **Вывод `diagnose-network.sh --quick`** (если проблема с сетью)
3. **Версию ОС и ядра:** `cat /etc/os-release && uname -a`
4. **Версию .NET:** `dotnet --version`
5. **Логи v2rayN:** `cat ~/.local/share/v2rayN/Logs/*.log | tail -100`
6. **Описание:** что делали, что ожидали, что получили

### Шаблон Issue

```
**ОС:** [Ubuntu 24.04 / Fedora 40 / ...]
**Версия v2rayN:** [7.22.0]
**Версия Xray-core:** [26.3.27]
**Версия .NET:** [10.0.5]
**Скрипт:** [install.sh / update-rules.sh / ...]

**Описание проблемы:**
[что произошло]

**Ожидаемое поведение:**
[что должно было произойти]

**Логи:**
```
[вставьте вывод status.sh или diagnose.sh]
```

**Дополнительно:**
[любая дополнительная информация]
```
