#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# ─── Блок 1: Получение задач ───────────────────────────────────────────────────

# Читаем конфигурацию бота
BOT_NAME=$(ls -d workflow/*/ 2>/dev/null | head -1 | tr -d '/')
BOT_NAME=${BOT_NAME##*/}

if [ -z "$BOT_NAME" ]; then
    echo "Ошибка: нет папок в workflow/. Запусти агента configure." >&2
    exit 1
fi

# Параметры YouGile из переменных окружения — никаких секретов в файле
if [ -z "${YOUGILE_API_KEY:-}" ]; then
    # Пробуем прочитать из .mcp.json
    YOUGILE_API_KEY=$(python3 -c "
import json
cfg = json.load(open('.mcp.json'))
print(cfg['mcpServers']['yougile']['env']['YOUGILE_API_KEY'])
" 2>/dev/null || echo "")
fi

if [ -z "${YOUGILE_API_KEY:-}" ]; then
    echo "Ошибка: YOUGILE_API_KEY не задан и не найден в .mcp.json" >&2
    exit 1
fi

export YOUGILE_API_KEY

# Получаем все задачи с доски «разработка» проекта WORKFLOW
ISSUES_JSON=$(python3 -c "
import json, os, urllib.request

api_key = os.environ['YOUGILE_API_KEY']

# Находим проект WORKFLOW
req = urllib.request.Request('https://yougile.com/api-v2/projects')
req.add_header('Authorization', f'Bearer {api_key}')
req.add_header('Content-Type', 'application/json')
with urllib.request.urlopen(req) as resp:
    projects = json.loads(resp.read())
workflow_proj = next((p for p in projects['content'] if p['title'] == 'WORKFLOW'), None)
if not workflow_proj:
    print('[]')
    exit(0)

# Находим доску «разработка»
req = urllib.request.Request('https://yougile.com/api-v2/boards?projectId=' + workflow_proj['id'])
req.add_header('Authorization', f'Bearer {api_key}')
req.add_header('Content-Type', 'application/json')
with urllib.request.urlopen(req) as resp:
    boards = json.loads(resp.read())
dev_board = next((b for b in boards['content'] if b['title'] == 'Разработка'), None)
if not dev_board:
    print('[]')
    exit(0)

# Находим колонки
req = urllib.request.Request('https://yougile.com/api-v2/columns?boardId=' + dev_board['id'])
req.add_header('Authorization', f'Bearer {api_key}')
req.add_header('Content-Type', 'application/json')
with urllib.request.urlopen(req) as resp:
    columns = json.loads(resp.read())
col_map = {c['title']: c['id'] for c in columns['content']}

# Собираем задачи из всех колонок
all_tasks = []
for col_name, col_id in col_map.items():
    req = urllib.request.Request(f'https://yougile.com/api-v2/tasks?columnId={col_id}')
    req.add_header('Authorization', f'Bearer {api_key}')
    req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
            for task in data['content']:
                task['_column'] = col_name
                all_tasks.append(task)
    except Exception:
        pass

print(json.dumps(all_tasks, ensure_ascii=False))
")

# ─── Блок 2: Подсчёт задач по каждому агенту ───────────────────────────────────

# ID агента Carono AI (читаем из bot.local.md — логин ai@carono.ru, но ID берём из API)
AI_USER_ID=$(python3 -c "
import json, os, urllib.request
api_key = os.environ['YOUGILE_API_KEY']
req = urllib.request.Request('https://yougile.com/api-v2/users')
req.add_header('Authorization', f'Bearer {api_key}')
req.add_header('Content-Type', 'application/json')
with urllib.request.urlopen(req) as resp:
    users = json.loads(resp.read())
ai_user = next((u for u in users['content'] if 'carono' in u.get('email', '').lower() or 'ai' in u.get('realName', '').lower()), None)
print(ai_user['id'] if ai_user else '')
" 2>/dev/null || echo "")

COUNT_DISCUSSION=$(python3 -c "
import json
issues = json.loads('''$ISSUES_JSON''')
ai_user = '$AI_USER_ID'
# Обсуждение: задачи в колонке 'Обсуждение', неназначенные ИЛИ назначенные на AI
print(sum(
    1 for i in issues
    if i.get('_column') == 'Обсуждение' and (
        not i.get('assigned') or
        (ai_user and ai_user in i.get('assigned', []))
    )
))
")

COUNT_WORKER=$(python3 -c "
import json
issues = json.loads('''$ISSUES_JSON''')
ai_user = '$AI_USER_ID'
# Разработка: задачи в колонке 'Разработка', назначенные на AI
print(sum(
    1 for i in issues
    if i.get('_column') == 'Разработка' and
    ai_user in i.get('assigned', [])
))
")

# Reviewer: колонка «на ревью» может не существовать — проверяем
HAS_REVIEW_COLUMN=$(python3 -c "
import json
issues = json.loads('''$ISSUES_JSON''')
print('yes' if any(i.get('_column') == 'на ревью' for i in issues) else 'no')
")

if [ "$HAS_REVIEW_COLUMN" = "yes" ]; then
    COUNT_REVIEWER=$(python3 -c "
import json
issues = json.loads('''$ISSUES_JSON''')
ai_user = '$AI_USER_ID'
print(sum(
    1 for i in issues
    if i.get('_column') == 'на ревью' and
    ai_user in i.get('assigned', [])
))
")
else
    COUNT_REVIEWER=0
fi

# ─── Блок 3: Определение NEEDED ────────────────────────────────────────────────

NEEDED_DISCUSSION="no"
[ "$COUNT_DISCUSSION" -gt 0 ] && NEEDED_DISCUSSION="yes"

NEEDED_WORKER="no"
[ "$COUNT_WORKER" -gt 0 ] && NEEDED_WORKER="yes"

NEEDED_REVIEWER="no"
[ "$COUNT_REVIEWER" -gt 0 ] && NEEDED_REVIEWER="yes"

# ─── Блок 4: Вывод таблицы (режим по умолчанию) ────────────────────────────────

MODE="${1:-status}"

if [ "$MODE" = "status" ]; then
    printf "%-15s %-8s %s\n" "AGENT" "TASKS" "NEEDED"
    printf "%-15s %-8s %s\n" "discussion" "$COUNT_DISCUSSION" "$NEEDED_DISCUSSION"
    printf "%-15s %-8s %s\n" "worker" "$COUNT_WORKER" "$NEEDED_WORKER"
    if [ "$HAS_REVIEW_COLUMN" = "yes" ]; then
        printf "%-15s %-8s %s\n" "reviewer" "$COUNT_REVIEWER" "$NEEDED_REVIEWER"
    fi
    exit 0
fi

# ─── Блок 5: Запуск агентов ────────────────────────────────────────────────────

if [ "$MODE" = "--run" ]; then
    TARGET="${2:-}"
    if [ -z "$TARGET" ]; then
        echo "Укажи агента: --run <agent|all>" >&2
        exit 1
    fi

    run_agent() {
        local agent="$1"
        echo "[start] $agent"
        if claude -p "Выполни свои задачи" --agent "$agent" > "logs/${agent}-$(date +%s).log" 2>&1; then
            echo "[ok]    $agent"
        else
            echo "[fail]  $agent (см. logs/)"
        fi
    }

    mkdir -p logs

    if [ "$TARGET" = "all" ]; then
        PIDS=()
        for agent_needed in \
            "discussion:$NEEDED_DISCUSSION" \
            "worker:$NEEDED_WORKER" \
            "reviewer:$NEEDED_REVIEWER"; do
            agent="${agent_needed%%:*}"
            needed="${agent_needed##*:}"
            if [ "$needed" = "yes" ]; then
                run_agent "$agent" &
                PIDS+=($!)
            fi
        done
        for pid in "${PIDS[@]}"; do
            wait "$pid"
        done
    else
        run_agent "$TARGET"
    fi

    exit 0
fi

echo "Использование: $0 [--run <agent|all>]" >&2
exit 1
