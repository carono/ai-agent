# Воркфлоу проекта

Этот документ — операционный мануал для агентов. Здесь описано как взаимодействовать с трекером задач, менять статусы, работать с кодом в данном конкретном проекте.

---

## Трекер задач

**Сервис:** *(уточнить)*
**Инстанс:** *(уточнить)*
**Проект:** *(уточнить)*
**Доска:** *(уточнить, если применимо)*

### Интеграция

Все операции с задачами (чтение, создание, комментарии, смена статусов) выполняются **строго через CLI-скрипт**:

```
workflow/{bot-name}/scripts/tracker <команда> [аргументы]
```

Скрипт читает креденшиалы из `workflow/{bot-name}/.env`. Прямые HTTP-запросы к API и прямые MCP-вызовы из агентов запрещены — единственный интерфейс к трекеру — этот скрипт.

Вывод команд — JSON в stdout. Ошибки — в stderr. Коды возврата: `0` успех, `1` общая ошибка, `2` проблема с конфигурацией, `3` ресурс не найден, `4` сетевая/API ошибка.

### Настройка

Скрипт генерирует скилл `tracker-setup`. Запусти его:
- при первом подключении бота,
- при смене трекера,
- при ротации токена,
- при добавлении новых команд (если чего-то не хватает).

Для диагностики работающей интеграции — используй агент `tracker` (`tools/tracker.md`).

---

## Жизненный цикл задачи

*(уточнить — перечислить колонки/статусы по порядку)*

### Статусы задачи

| Статус | Значение в трекере | Кто переводит |
|--------|--------------------|---------------|
| *(уточнить)* | | |

---

## Операции с задачами

Все команды выполняются из корня репозитория. Подразумевается, что `workflow/{bot-name}/scripts/tracker` существует и настроен.

### Проверить себя

```
./workflow/{bot-name}/scripts/tracker whoami
```

### Список колонок/статусов

```
./workflow/{bot-name}/scripts/tracker list-columns
```

### Найти задачи в колонке

```
./workflow/{bot-name}/scripts/tracker list-tasks --column "<название>"
./workflow/{bot-name}/scripts/tracker list-tasks --column "<название>" --assignee me
./workflow/{bot-name}/scripts/tracker list-tasks --column "<название>" --assignee none
```

### Прочитать задачу

```
./workflow/{bot-name}/scripts/tracker get-task <id>
```

### Прочитать переписку задачи

```
./workflow/{bot-name}/scripts/tracker list-comments <id>
./workflow/{bot-name}/scripts/tracker list-comments <id> --since <last-comment-id>
```

### Написать комментарий

```
./workflow/{bot-name}/scripts/tracker comment <id> "текст"
./workflow/{bot-name}/scripts/tracker comment <id> --file /tmp/comment.md
```

Для многострочных комментариев используй `--file` — надёжнее чем экранирование в позиционном аргументе.

### Сменить статус

```
./workflow/{bot-name}/scripts/tracker move-task <id> --column "<название>"
```

### Назначить исполнителя

```
./workflow/{bot-name}/scripts/tracker assign-task <id> --user me
./workflow/{bot-name}/scripts/tracker assign-task <id> --user <login>
./workflow/{bot-name}/scripts/tracker assign-task <id> --user none
```

### Создать задачу

```
./workflow/{bot-name}/scripts/tracker create-task --title "..." --column "..." --description "..."
```

### Участники проекта

```
./workflow/{bot-name}/scripts/tracker list-users
```

---

## Работа с кодом

### Ветки

- Создавать от: *(уточнить)*
- Формат имени: *(уточнить)*
- Целевая ветка для код-ревью: *(уточнить)*

### Создание код-ревью

*(уточнить — как открывается MR/PR, куда, какие обязательные поля)*

### Поиск и чтение код-ревью

*(уточнить)*

### Формат коммита

*(уточнить)*
