#!/usr/bin/env bash
# Проверка состояния задач и запуск агентов.
# Получение задач — только через workflow/carono-ai/scripts/tracker (CLI-контракт tracker-setup).
# Регенерируется скиллом carono-wf:checker-setup — руками не редактировать.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.."

BOT_DIR="workflow/carono-ai"
TRACKER="$BOT_DIR/scripts/tracker"

# ─── Шапка-помощь ─────────────────────────────────────────────────────────────

SELF="$(basename "$0")"

print_help() {
  cat <<EOF
Использование:
  ./$SELF                — показать текущие статусы задач
  ./$SELF --run <agent>  — запустить конкретного агента
  ./$SELF --run all      — запустить всех агентов со статусом NEEDED=yes
  ./$SELF --help         — показать это сообщение

Доступные агенты: discussion, worker, reviewer
EOF
}

# Ранний выход по --help — без обращения к трекеру и без требования настроенного $TRACKER
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  print_help
  exit 0
fi

if [[ ! -x "$TRACKER" ]]; then
  echo "ERROR: $TRACKER not found or not executable. Run the carono-wf:tracker-setup skill first." >&2
  exit 2
fi

# ─── Получение задач ──────────────────────────────────────────────────────────

# discussion: «Обсуждение», на боте ИЛИ без исполнителя
TASKS_discussion=$(
  {
    "$TRACKER" list-tasks --column "Обсуждение" --assignee me
    "$TRACKER" list-tasks --column "Обсуждение" --assignee none
  } | jq -s 'add | unique_by(.id)'
)

# worker: «Разработка», на боте ИЛИ без исполнителя
TASKS_worker=$(
  {
    "$TRACKER" list-tasks --column "Разработка" --assignee me
    "$TRACKER" list-tasks --column "Разработка" --assignee none
  } | jq -s 'add | unique_by(.id)'
)

# reviewer: «На проверке», только на боте
TASKS_reviewer=$("$TRACKER" list-tasks --column "На проверке" --assignee me)

# ─── Подсчёт ──────────────────────────────────────────────────────────────────

COUNT_discussion_TOTAL=$(echo "$TASKS_discussion" | jq 'length')
COUNT_worker=$(echo "$TASKS_worker" | jq 'length')
COUNT_reviewer=$(echo "$TASKS_reviewer" | jq 'length')

# discussion — stateful: считаем только задачи с новой активностью
# State-файл хранит для каждой задачи id последнего обработанного комментария
STATE_discussion="$BOT_DIR/discussion-state.json"

COUNT_discussion_NEW=$(TRACKER="$TRACKER" STATE="$STATE_discussion" TASKS="$TASKS_discussion" python3 - <<'PY'
import json, os, subprocess

tracker = os.environ["TRACKER"]
state_path = os.environ["STATE"]
tasks = json.loads(os.environ["TASKS"])

state = {}
if os.path.exists(state_path):
    try:
        state = json.load(open(state_path))
    except Exception:
        state = {}
issues = state.get("issues", {})

new = 0
for t in tasks:
    tid = str(t["id"])
    try:
        out = subprocess.check_output([tracker, "list-comments", t["id"]])
        comments = json.loads(out)
    except Exception:
        comments = []
    last = comments[-1]["id"] if comments else ""
    saved = issues.get(tid, {}).get("updated_at", "")
    # normalize: state can hold either string or int, API returns int
    if str(saved) != str(last):
        new += 1
print(new)
PY
)

NEEDED_discussion="no"; [[ "$COUNT_discussion_NEW" -gt 0 ]] && NEEDED_discussion="yes"
NEEDED_worker="no";     [[ "$COUNT_worker" -gt 0 ]]         && NEEDED_worker="yes"
NEEDED_reviewer="no";   [[ "$COUNT_reviewer" -gt 0 ]]       && NEEDED_reviewer="yes"

# ─── Режим вывода ────────────────────────────────────────────────────────────

MODE="${1:-status}"

if [[ "$MODE" == "status" ]]; then
  print_help
  echo
  printf "%-12s %-14s %s\n" "AGENT" "TASKS" "NEEDED"
  printf "%-12s %-14s %s\n" "discussion" "$COUNT_discussion_NEW (из $COUNT_discussion_TOTAL)" "$NEEDED_discussion"
  printf "%-12s %-14s %s\n" "worker"     "$COUNT_worker"                                       "$NEEDED_worker"
  printf "%-12s %-14s %s\n" "reviewer"   "$COUNT_reviewer"                                     "$NEEDED_reviewer"
  exit 0
fi

# ─── Режим --run ──────────────────────────────────────────────────────────────

if [[ "$MODE" == "--run" ]]; then
  TARGET="${2:-}"
  if [[ -z "$TARGET" ]]; then
    echo "Использование: $0 --run <discussion|worker|reviewer|all>" >&2
    exit 1
  fi

  mkdir -p "$BOT_DIR/logs"

  run_agent() {
    local agent="$1"
    echo "[start] $agent"
    if claude -p "Выполни свои задачи" --agent "carono-wf:$agent" \
         > "$BOT_DIR/logs/${agent}-$(date +%s).log" 2>&1; then
      echo "[ok]    $agent"
    else
      echo "[fail]  $agent (см. $BOT_DIR/logs/)"
    fi
  }

  if [[ "$TARGET" == "all" ]]; then
    PIDS=()
    for pair in \
      "discussion:$NEEDED_discussion" \
      "worker:$NEEDED_worker" \
      "reviewer:$NEEDED_reviewer"; do
      agent="${pair%%:*}"
      needed="${pair##*:}"
      if [[ "$needed" == "yes" ]]; then
        run_agent "$agent" &
        PIDS+=($!)
      fi
    done
    for pid in "${PIDS[@]}"; do wait "$pid"; done
  else
    run_agent "$TARGET"
  fi

  exit 0
fi

print_help >&2
exit 1
