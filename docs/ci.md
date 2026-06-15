# CI/CD — GitHub Actions

Пайплайн непрерывной интеграции для проекта v2rayN Russia Setup.

**Файл:** `.github/workflows/ci.yml`

**События запуска:**
- `push` в ветку `main`
- `pull_request` в ветку `main`
- `workflow_dispatch` (ручной запуск через GitHub UI)

## Jobs

### 1. Shellcheck (`shellcheck`)

Проверка Bash-скриптов статическим анализатором ShellCheck.

```yaml
- uses: ludeeus/action-shellcheck@2.0.0
  with:
    severity: warning
    additional_files: install.sh uninstall.sh scripts/*.sh
```

**Проверяемые файлы:**
- `install.sh`
- `uninstall.sh`
- `lib/common.sh`
- `scripts/update-rules.sh`
- `scripts/proxy-toggle.sh`
- `scripts/proxy_set_linux_sh.sh`
- `scripts/deploy-mobile.sh`
- `scripts/generate-mobile-url.sh`
- `scripts/mobile-setup-termux.sh`
- `scripts/mobile-apply-routing.sh`

**Уровень:** `warning` (ошибки и предупреждения).

### 2. Bash Syntax (`bash-syntax`)

Проверка синтаксиса всех shell-скриптов через `bash -n`.

```bash
for f in \
  install.sh uninstall.sh \
  lib/common.sh \
  scripts/update-rules.sh scripts/proxy-toggle.sh \
  scripts/proxy_set_linux_sh.sh scripts/deploy-mobile.sh \
  scripts/generate-mobile-url.sh scripts/mobile-setup-termux.sh \
  scripts/mobile-apply-routing.sh
do
  bash -n "$f" || errors=$((errors+1))
done
```

Ловит:
- Пропущенные `done`, `fi`, `esac`
- Ошибки подстановки `${var:?}`
- Некорректные here-documents

### 3. Validate JSON (`validate-json`)

Валидация JSON-файлов через `python3 -m json.tool`.

```bash
for f in config/*.json; do
  python3 -m json.tool "$f" > /dev/null
done
```

**Проверяемые файлы:** все `config/*.json`:
- `config/routing-russia.json`
- `config/config-template-xray.json`
- `config/only_blocked.json`
- `config/v2rayng-routing-russia.json`
- `config/v2rayng-only-blocked.json`

### 4. Markdown Check (`markdown-check`)

Проверка наличия и, по возможности, линтинг Markdown-файлов.

```bash
for f in \
  README.md CHANGELOG.md \
  docs/README.md docs/install.md docs/mobile.md \
  docs/routing.md docs/scripts.md docs/ci.md docs/faq.md \
  subscriptions/README.md
do
  # проверка существования
  # markdownlint (если установлен)
done
```

При установленном `markdownlint-cli2` или `markdownlint` выполняет
проверку синтаксиса Markdown.

## Правила ShellCheck, используемые в проекте

### SC2317 — функция не вызывается, но используется через trap

```bash
# shellcheck disable=SC2317
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
```

Shellcheck считает функцию мёртвым кодом, если она не вызывается явно,
но вызывается через `trap`. Отключено через `# shellcheck disable=SC2317`
в начале файла.

## Ручной запуск

Через GitHub UI:
1. Перейдите в Actions → CI → Run workflow
2. Выберите ветку `main`
3. Нажмите «Run workflow»

Через GitHub CLI:
```bash
gh workflow run ci.yml --ref main
```

## Добавление нового скрипта

1. Создайте файл в корне или `scripts/`
2. Добавьте его в `additional_files` в job `shellcheck`
3. Добавьте его в список `bash -n` в job `bash-syntax`
4. Убедитесь, что CI проходит:

```bash
# Локальная проверка перед push:
bash -n новый-скрипт.sh
shellcheck новый-скрипт.sh
```
