# Воркфлоу проекта

Этот документ — операционный мануал для агентов. Здесь описано как взаимодействовать с трекером задач, менять статусы, работать с кодом в данном конкретном проекте.

---

## Трекер задач

**Сервис:** YouGile
**Инстанс:** https://ru.yougile.com
**Проект:** WORKFLOW
**Доска:** Разработка

### Интеграция

Все операции с задачами (чтение, создание, комментарии, смена статусов, назначения) выполняются **строго через CLI-скрипт**:

```
workflow/carono-ai/scripts/tracker <команда> [аргументы]
```

Скрипт читает креденшиалы из `workflow/carono-ai/.env`. Прямые HTTP-запросы к YouGile API из агентов **запрещены** — если чего-то не хватает в текущем наборе команд, доработай скрипт (или повторно запусти скилл `carono-wf:tracker-setup`).

Вывод команд — JSON в stdout; ошибки — в stderr; коды возврата:
- `0` — успех
- `1` — общая ошибка (неизвестная команда, неверный аргумент)
- `2` — проблема с конфигурацией / `.env`
- `3` — ресурс не найден (задача/колонка/пользователь)
- `4` — сетевая или API-ошибка

---

## Жизненный цикл задачи

Задачи проходят через колонки доски в порядке:

```
Задачи → Обсуждение → Разработка → На проверке → Готово
```

Бот discussion **не перемещает** задачи между колонками. Его роль — только читать задачи из колонки «Обсуждение», задавать уточняющие вопросы и отвечать на них. Решение о готовности к разработке и перенос в колонку «Разработка» принимает человек.

### Статусы задачи

| Статус | Значение в трекере | Кто переводит |
|--------|--------------------|---------------|
| Новая | Колонка «Задачи» | Человек (создаёт) |
| В обсуждении | Колонка «Обсуждение» | Человек или бот (переносит для уточнения) |
| В разработке | Колонка «Разработка» | Человек (после завершения обсуждения) |
| На проверке | Колонка «На проверке» | Бот worker (после создания MR) |
| Готово | Колонка «Готово» | Человек (после проверки и мёржа MR) |

---

## Операции с задачами

Все команды выполняются из корня репозитория. Вывод — JSON, ошибки — в stderr.

### Проверить себя (валидность токена)

```
./workflow/carono-ai/scripts/tracker whoami
```

### Список колонок

```
./workflow/carono-ai/scripts/tracker list-columns
```

### Найти задачи в колонке

```
./workflow/carono-ai/scripts/tracker list-tasks --column "Обсуждение"
./workflow/carono-ai/scripts/tracker list-tasks --column "Обсуждение" --assignee me
./workflow/carono-ai/scripts/tracker list-tasks --column "Разработка" --assignee none
./workflow/carono-ai/scripts/tracker list-tasks --column "На проверке" --limit 100
```

Спец-значения `--assignee`: `me` — текущий пользователь (токен), `none` — без исполнителя, логин/email — конкретный пользователь.

### Прочитать задачу

```
./workflow/carono-ai/scripts/tracker get-task <id>
```

Возвращает `{id, number, title, description, column, assignees, url, created_at, updated_at}`.

### Прочитать переписку задачи

```
./workflow/carono-ai/scripts/tracker list-comments <id>
./workflow/carono-ai/scripts/tracker list-comments <id> --since <last-comment-id>
```

### Написать комментарий

```
./workflow/carono-ai/scripts/tracker comment <id> "короткий текст"
./workflow/carono-ai/scripts/tracker comment <id> --file /tmp/comment.md
```

Для многострочных / с markdown — используй `--file`, надёжнее чем экранирование в shell.

### Сменить статус (перенести в колонку)

```
./workflow/carono-ai/scripts/tracker move-task <id> --column "Разработка"
```

**Важно:** при переносе задачи в «Разработку», если на задаче ещё нет исполнителя — бот worker **обязан** назначить себя через `assign-task ... --user me` перед/после `move-task`.

### Назначить исполнителя

```
./workflow/carono-ai/scripts/tracker assign-task <id> --user me
./workflow/carono-ai/scripts/tracker assign-task <id> --user ai@carono.ru
./workflow/carono-ai/scripts/tracker assign-task <id> --user none
```

### Создать задачу

```
./workflow/carono-ai/scripts/tracker create-task --title "..." --column "Задачи" --description "..."
./workflow/carono-ai/scripts/tracker create-task --title "..." --description-file /tmp/desc.md --assignee ai@carono.ru
```

### Удалить / архивировать задачу

```
./workflow/carono-ai/scripts/tracker delete-task <id>
```

### Список участников проекта

```
./workflow/carono-ai/scripts/tracker list-users
```

---

## Работа с кодом

### Синхронизация перед началом работы

Перед любой работой с кодом (создание ветки, чтение, правки, ответ на замечания ревью) обязательно обновить локальную копию:

```bash
git fetch --all --prune
git pull --ff-only
```

Правило действует для **всех** агентов на **каждом** запуске — даже если работа ведётся только в существующем worktree. Цель — не строить правки поверх устаревшего состояния удалённого репозитория.

- Для worker: `pull` выполняется в основной рабочей копии на ветке `master`, чтобы worktree задачи ответвлялся от свежего состояния.
- Для reviewer: `pull` выполняется внутри worktree ветки задачи — вдруг автор/другой ревьюер дополнил код после прошлого запуска.
- Если `pull --ff-only` не прошёл (non-fast-forward, конфликты, расхождение с remote) — остановить работу и сообщить, не решать автоматически.

### Ветки

- Создавать от: `master`
- Формат имени: `task/<номер>-<краткое-описание>`, где:
  - номер — локальный WF-номер (например WF-18 → 18)
  - описание — на английском, kebab-case
  - Пример: `task/18-fix-worker-worktrees`
- Целевая ветка для код-ревью: `master`

### Создание код-ревью

Платформа: GitHub (репозиторий `carono/workflow`). MR открывается в ветку `master`. В описании MR обязательно указывать полную ссылку на задачу в YouGile.

После создания MR бот worker **обязан** перевести задачу в колонку «На проверке» (ID: `a82fc016-5ad0-43a0-ad94-40740c04ce0e`).

### Поиск и чтение код-ревью

Использовать MCP-сервер GitHub для поиска и чтения MR/PR по репозиторию.

### Формат коммита

В сообщении коммита обязательно:
1. **Полная ссылка на задачи** в YouGile
2. Человекопонятное описание того, что было сделано

### Формат ссылки на задачу YouGile

Ссылка формируется по шаблону:

```
https://ru.yougile.com/team/3300fcb64048/WORKFLOW#WF-{номер}
```

Где:
- `3300fcb64048` — Team ID (константа для данного инстанса YouGile)
- Номер задачи берётся из поля `idTaskProject` API YouGile (например `WF-21` → номер `21`)

Пример: `https://ru.yougile.com/team/3300fcb64048/WORKFLOW#WF-21`

Ссылки указываются везде: в тексте коммитов и в описаниях Pull Request.

### Стейт-файл агента discussion

Агент discussion хранит стейт обработанных задач в файле:

```
workflow/carono-ai/discussion-state.json
```

Значение `updated_at` в стейте — ID последнего сообщения в чате задачи (поле `id` из последнего элемента ответа `./scripts/tracker list-comments <id>`). Используется для того, чтобы при повторном запуске не реагировать повторно на уже обработанные комментарии.

### Предварительные проверки

Перед началом работы агент worker должен проверить:

1. **gh CLI установлен:** `which gh` — если не установлен, установить согласно инструкции ниже
2. **GitHub токен доступен:** переменная `GITHUB_TOKEN` или `GITHUB_API_TOKEN` должна быть установлена
3. **Авторизация в gh:** `gh auth status` — проверить что есть доступ к репозиторию `carono/workflow`

#### Установка gh CLI (Ubuntu/Debian)

```bash
curl -sL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install -y gh
```

#### Настройка токена

Токен должен быть установлен в переменной окружения `GITHUB_TOKEN` или `GITHUB_API_TOKEN`. Если токена нет — запросить у пользователя.
