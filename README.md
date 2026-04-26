# carono/workflow

Универсальные агенты и скиллы для автоматизации цикла разработки (обсуждение → реализация → код-ревью). Не привязаны к конкретному трекеру — вся специфика проекта описывается в `workflow/{bot-name}/*.md`, которые читаются в рантайме.

Репозиторий одновременно:
- **маркетплейс** `carono` — каталог плагинов;
- **плагин** `carono-wf` — единственный в этом маркетплейсе пока.

Префикс для всех компонентов в Claude Code — `carono-wf:` (например `carono-wf:tracker-setup`, `carono-wf:worker`).

## Что внутри

- **Агенты** (`agents/`) — subagent'ы для потоковой обработки задач:
  - `discussion` — уточняет требования по задачам в трекере
  - `worker` — реализует задачи, открывает MR/PR
  - `reviewer` — разбирает замечания код-ревью, закрывает задачи
- **Скиллы** (`skills/`) — разовые операции через диалог:
  - `configure` — собирает воркфлоу проекта, создаёт `workflow/{bot-name}/WORKFLOW.md`, `PROJECT.md`, `TECH.md`, `bot.local.md`
  - `tracker-setup` — генерирует CLI-скрипт `workflow/{bot-name}/scripts/tracker` для работы с трекером
  - `checker-setup` — генерирует `workflow/{bot-name}/scripts/check.sh` для проверки состояния задач и запуска агентов
  - `tracker-check` — диагностика работающей интеграции (тестовая задача, проверка MCP-операций, очистка)
  - `analyst` — нарезает новые задачи на основе `MISSION.md` (конституция) и `ROADMAP.md` (вектор), фильтрует идеи через миссию, создаёт принятые в трекере, ведёт журнал прогонов

## Установка — Claude Code

```
/plugin marketplace add carono/workflow
/plugin install carono-wf@carono
```

После этого в `/skills` появятся `carono-wf:configure`, `carono-wf:tracker-setup` и др., в `/agents` — `carono-wf:worker`, `carono-wf:discussion`, `carono-wf:reviewer`.

## Установка — OpenCode

Поддержка OpenCode временно отключена — сборка `dist/opencode/` закомментирована в `src/scripts/build.py`. Вернёмся, когда будет время проверить совместимость.

## Первичная настройка проекта

1. Запусти скилл **`/carono-wf:configure`** — расспросит про воркфлоу, создаст `workflow/{bot-name}/WORKFLOW.md`, `PROJECT.md`, `TECH.md`, `bot.local.md`.
2. Запусти скилл **`/carono-wf:tracker-setup`** — спросит про трекер, соберёт токен в `workflow/{bot-name}/.env`, сгенерирует `workflow/{bot-name}/scripts/tracker` (единый CLI), прогонит smoke-test и актуализирует `WORKFLOW.md` под CLI.
3. Запусти скилл **`/carono-wf:checker-setup`** — сгенерирует `workflow/{bot-name}/scripts/check.sh` для проверки состояния задач и запуска агентов.
4. Дальше штатно: `discussion` → `worker` → `reviewer`. Все агенты работают с трекером только через сгенерированный `scripts/tracker` — CLI унифицирован и не зависит от того, какой трекер под капотом.

Если интеграция перестала работать — запусти `/carono-wf:tracker-check` для диагностики.

## Разработка

Правки — только в `src/`. Собранные артефакты (`agents/`, `skills/`) коммитятся, но не редактируются руками.

Сборка:

```bash
python3 src/scripts/build.py             # всё (только plugin сейчас) + Tier-1 валидация
python3 src/scripts/build.py plugin      # только плагин (agents/, skills/ в корне)
python3 src/scripts/build.py --check     # CI-режим: собрать в tempdir, провалидировать,
                                         # сравнить с рабочим деревом — exit 1 при расхождении
```

`--check` крутится в CI (`.github/workflows/build-check.yml`) на каждом PR — гарантирует, что артефакты в `agents/`/`skills/` соответствуют `src/` побайтово.

Манифесты `.claude-plugin/plugin.json` и `.claude-plugin/marketplace.json` — статические, не генерируются сборкой.

Подробнее про шаблонизацию (`{{RULES_*}}`, `{{TEMPLATE_*}}`) — в `CLAUDE.md`.
