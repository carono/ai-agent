# carono/workflow

Универсальные агенты и скилл для автоматизации цикла разработки (обсуждение → реализация → код-ревью). Не привязаны к конкретному трекеру — вся специфика проекта описывается в `workflow/{bot-name}/*.md`, которые читаются в рантайме.

Репозиторий одновременно:
- **маркетплейс** `carono` — каталог плагинов;
- **плагин** `carono-wf` — единственный в этом маркетплейсе пока.

Префикс для всех компонентов в Claude Code — `carono-wf:` (например `carono-wf:tracker-setup`, `carono-wf:worker`).

## Что внутри

- **Агенты** (`agents/`) — subagent'ы: `configure`, `discussion`, `worker`, `reviewer`, а также сервисные `checker`, `doc`, `tracker`
- **Скиллы** (`skills/`) — `tracker-setup`: генерирует CLI-скрипт `workflow/{bot-name}/scripts/tracker` для работы с трекером

## Установка — Claude Code

```
/plugin marketplace add carono/workflow
/plugin install carono-wf@carono
```

После этого в `/skills` появится `carono-wf:tracker-setup`, в `/agents` — `carono-wf:worker`, `carono-wf:discussion` и остальные.

## Установка — OpenCode

У OpenCode нет концепции плагинов. Ставится старым способом через `degit`:

```
npx degit carono/workflow/dist/opencode/agents .opencode/agents --force
npx degit carono/workflow/dist/opencode/tools .opencode/agents --force
```

Содержимое `dist/opencode/skills/` — подключай под свой харнесс вручную как считаешь нужным.

## Первичная настройка проекта

1. Вызови агент **`configure`** — расспросит про воркфлоу, создаст `workflow/{bot-name}/WORKFLOW.md`, `PROJECT.md`, `TECH.md`, `bot.local.md`.
2. Вызови скилл **`/carono-wf:tracker-setup`** — спросит про трекер, соберёт токен в `workflow/{bot-name}/.env`, сгенерирует `workflow/{bot-name}/scripts/tracker` (единый CLI), прогонит smoke-test и актуализирует `WORKFLOW.md` под CLI.
3. Дальше штатно: `discussion` → `worker` → `reviewer`. Все агенты работают с трекером только через сгенерированный `scripts/tracker` — CLI унифицирован и не зависит от того, какой трекер под капотом.

## Разработка

Правки — только в `src/`. Собранные артефакты (`agents/`, `skills/`, `dist/opencode/`) коммитятся, но не редактируются руками.

Сборка:

```bash
python3 src/scripts/build.py             # всё
python3 src/scripts/build.py plugin      # только плагин (agents/, skills/ в корне)
python3 src/scripts/build.py opencode    # только dist/opencode/
```

Манифесты `.claude-plugin/plugin.json` и `.claude-plugin/marketplace.json` — статические, не генерируются сборкой.

Подробнее про шаблонизацию (`{{RULES_*}}`, `{{TEMPLATE_*}}`) — в `CLAUDE.md`.
