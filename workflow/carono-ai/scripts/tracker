#!/usr/bin/env bash
# Tracker CLI — YouGile.
# Контракт см. в SKILL.md скилла tracker-setup / cli-contract.md.
# Секреты читаются из ../.env рядом с папкой scripts/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$BOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE" >&2
  exit 2
fi

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${TRACKER_API_KEY:?TRACKER_API_KEY is not set in .env}"
: "${TRACKER_BASE_URL:?TRACKER_BASE_URL is not set in .env (expected: https://yougile.com/api-v2)}"
: "${TRACKER_PROJECT_ID:?TRACKER_PROJECT_ID is not set in .env}"
: "${TRACKER_BOARD_ID:?TRACKER_BOARD_ID is not set in .env}"
: "${TRACKER_BOT_LOGIN:=}"
: "${YOUGILE_TEAM_ID:=}"

for dep in curl jq; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: $dep not installed" >&2; exit 2; }
done

AUTH=(-H "Authorization: Bearer $TRACKER_API_KEY" -H "Content-Type: application/json" -H "Accept: application/json")

# ---------- low-level HTTP helpers ----------

api_get() {
  local path="$1"
  curl -sS -f "${AUTH[@]}" "$TRACKER_BASE_URL$path" 2>/dev/null || {
    local code=$?
    echo "ERROR: GET $path failed (curl exit $code)" >&2
    return 4
  }
}

api_post() {
  local path="$1" body="$2"
  curl -sS -f "${AUTH[@]}" -X POST -d "$body" "$TRACKER_BASE_URL$path" 2>/dev/null || {
    echo "ERROR: POST $path failed" >&2
    return 4
  }
}

api_put() {
  local path="$1" body="$2"
  curl -sS -f "${AUTH[@]}" -X PUT -d "$body" "$TRACKER_BASE_URL$path" 2>/dev/null || {
    echo "ERROR: PUT $path failed" >&2
    return 4
  }
}

# ---------- resolvers ----------

resolve_column_id() {
  local name="$1"
  api_get "/columns?boardId=$TRACKER_BOARD_ID&title=$(jq -rn --arg v "$name" '$v|@uri')" \
    | jq -r --arg name "$name" '.content[] | select(.title == $name) | .id' \
    | head -n1
}

resolve_user_id() {
  local login="$1"
  if [[ "$login" == "me" ]]; then
    login="$TRACKER_BOT_LOGIN"
  fi
  api_get "/users?limit=1000" \
    | jq -r --arg login "$login" '.content[] | select(.realName == $login or .email == $login) | .id' \
    | head -n1
}

ms_to_iso() {
  local ms="$1"
  if [[ -z "$ms" || "$ms" == "null" ]]; then
    echo ""
    return
  fi
  local sec=$((ms / 1000))
  date -u -d "@$sec" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo ""
}

build_task_url() {
  local id_task_project="$1"
  if [[ -n "$YOUGILE_TEAM_ID" && -n "${YOUGILE_PROJECT_NAME:-}" ]]; then
    echo "https://ru.yougile.com/team/$YOUGILE_TEAM_ID/$YOUGILE_PROJECT_NAME#$id_task_project"
  else
    echo ""
  fi
}

# ---------- commands ----------

cmd_whoami() {
  local me
  me="$(api_get "/auth/me" 2>/dev/null)" || me=""
  if [[ -n "$me" ]]; then
    echo "$me" | jq '{id, login: .realName, name: .realName, email}'
    return
  fi
  # Fallback: найти по логину бота
  if [[ -n "$TRACKER_BOT_LOGIN" ]]; then
    api_get "/users?limit=1000" \
      | jq --arg login "$TRACKER_BOT_LOGIN" '.content[] | select(.realName == $login or .email == $login) | {id, login: .realName, name: .realName, email}'
  else
    echo '{"error": "whoami unavailable", "detail": "YouGile API doesn'"'"'t expose /auth/me and TRACKER_BOT_LOGIN is empty"}' >&2
    return 1
  fi
}

cmd_list_columns() {
  api_get "/columns?boardId=$TRACKER_BOARD_ID&limit=1000" \
    | jq '[.content[] | {id, name: .title, position: (.order // 0)}] | sort_by(.position)'
}

cmd_list_tasks() {
  local column="" assignee="" limit=50
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --column) column="$2"; shift 2 ;;
      --assignee) assignee="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$column" ]] && { echo "ERROR: --column required" >&2; exit 1; }

  local col_id
  col_id="$(resolve_column_id "$column")"
  [[ -z "$col_id" ]] && { echo "ERROR: column '$column' not found" >&2; exit 3; }

  local raw
  raw="$(api_get "/task-list?columnId=$col_id&limit=$limit")"

  local assignee_id=""
  if [[ -n "$assignee" && "$assignee" != "none" ]]; then
    assignee_id="$(resolve_user_id "$assignee")"
  fi

  echo "$raw" | jq \
    --arg column "$column" \
    --arg assignee_filter "$assignee" \
    --arg assignee_id "$assignee_id" \
    '[.content[]
      | select(
          ($assignee_filter == "") or
          ($assignee_filter == "none" and ((.assigned // []) | length == 0)) or
          ($assignee_filter != "none" and ((.assigned // []) | index($assignee_id)))
        )
      | {
          id,
          number: (.idTaskProject // ""),
          title,
          column: $column,
          assignees: (.assigned // []),
          url: "",
          updated_at: (((.timestamp // 0) / 1000) | todate)
        }
    ]'
}

cmd_get_task() {
  local id="$1"
  [[ -z "$id" ]] && { echo "ERROR: task id required" >&2; exit 1; }

  local raw col_name
  raw="$(api_get "/tasks/$id")" || { echo '{"error": "not found"}'; exit 3; }
  local col_id
  col_id="$(echo "$raw" | jq -r '.columnId')"
  col_name="$(api_get "/columns/$col_id" | jq -r '.title // ""')"

  echo "$raw" | jq --arg column "$col_name" '{
    id,
    number: (.idTaskProject // ""),
    title,
    description: (.description // ""),
    column: $column,
    assignees: (.assigned // []),
    url: "",
    created_at: (((.timestamp // 0) / 1000) | todate),
    updated_at: (((.timestamp // 0) / 1000) | todate)
  }'
}

cmd_list_comments() {
  local id="$1"; shift || true
  [[ -z "$id" ]] && { echo "ERROR: task id required" >&2; exit 1; }
  local since="" limit=100
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --since) since="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    esac
  done

  api_get "/chats/$id/messages?limit=$limit" \
    | jq --arg since "$since" '[
        .content[]
        | select($since == "" or (.id > $since))
        | {
            id,
            author: (.fromUserId // ""),
            text: (.text // ""),
            created_at: (((.timestamp // 0) / 1000) | todate)
          }
      ]'
}

cmd_comment() {
  local id="$1"; shift || true
  [[ -z "$id" ]] && { echo "ERROR: task id required" >&2; exit 1; }
  local text=""
  if [[ "${1:-}" == "--file" ]]; then
    text="$(cat "$2")"
    shift 2
  elif [[ -n "${1:-}" ]]; then
    text="$1"
    shift
  fi
  [[ -z "$text" ]] && { echo "ERROR: comment text required (positional or --file)" >&2; exit 1; }

  local body
  body="$(jq -n --arg text "$text" '{text: $text}')"
  local resp
  resp="$(api_post "/chats/$id/messages" "$body")"
  echo "$resp" | jq '{id, created_at: (((.timestamp // 0) / 1000) | todate)}'
}

cmd_move_task() {
  local id="$1"; shift || true
  [[ -z "$id" ]] && { echo "ERROR: task id required" >&2; exit 1; }
  local column=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --column) column="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$column" ]] && { echo "ERROR: --column required" >&2; exit 1; }

  local col_id
  col_id="$(resolve_column_id "$column")"
  [[ -z "$col_id" ]] && { echo "ERROR: column '$column' not found" >&2; exit 3; }

  local body
  body="$(jq -n --arg col "$col_id" '{columnId: $col}')"
  api_put "/tasks/$id" "$body" >/dev/null
  jq -n --arg id "$id" --arg col "$column" '{ok: true, id: $id, column: $col}'
}

cmd_assign_task() {
  local id="$1"; shift || true
  [[ -z "$id" ]] && { echo "ERROR: task id required" >&2; exit 1; }
  local user=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) user="$2"; shift 2 ;;
      *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$user" ]] && { echo "ERROR: --user required" >&2; exit 1; }

  local body
  if [[ "$user" == "none" ]]; then
    body='{"assigned": []}'
  else
    local uid
    uid="$(resolve_user_id "$user")"
    [[ -z "$uid" ]] && { echo "ERROR: user '$user' not found" >&2; exit 3; }
    body="$(jq -n --arg u "$uid" '{assigned: [$u]}')"
  fi

  local resp
  resp="$(api_put "/tasks/$id" "$body")"
  echo "$resp" | jq --arg id "$id" '{ok: true, id: $id, assignees: (.assigned // [])}'
}

cmd_create_task() {
  local title="" column="" description="" description_file=""
  local -a assignees=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --column) column="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --description-file) description_file="$2"; shift 2 ;;
      --assignee) assignees+=("$2"); shift 2 ;;
      *) echo "ERROR: unknown flag $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$title" ]] && { echo "ERROR: --title required" >&2; exit 1; }
  [[ -n "$description_file" ]] && description="$(cat "$description_file")"

  local col_id=""
  if [[ -n "$column" ]]; then
    col_id="$(resolve_column_id "$column")"
    [[ -z "$col_id" ]] && { echo "ERROR: column '$column' not found" >&2; exit 3; }
  fi

  local -a assignee_ids=()
  for login in "${assignees[@]}"; do
    local uid; uid="$(resolve_user_id "$login")"
    [[ -n "$uid" ]] && assignee_ids+=("$uid")
  done

  local body
  body="$(jq -n \
    --arg title "$title" \
    --arg col "$col_id" \
    --arg desc "$description" \
    --argjson users "$(printf '%s\n' "${assignee_ids[@]}" | jq -R . | jq -s .)" \
    '{title: $title}
     + (if $col != "" then {columnId: $col} else {} end)
     + (if $desc != "" then {description: $desc} else {} end)
     + (if ($users | length) > 0 then {assigned: $users} else {} end)')"

  local resp
  resp="$(api_post "/tasks" "$body")"
  echo "$resp" | jq '{id, number: (.idTaskProject // ""), url: ""}'
}

cmd_delete_task() {
  local id="$1"
  [[ -z "$id" ]] && { echo "ERROR: task id required" >&2; exit 1; }
  api_put "/tasks/$id" '{"deleted": true}' >/dev/null
  jq -n --arg id "$id" '{ok: true, id: $id}'
}

cmd_list_users() {
  api_get "/users?limit=1000" \
    | jq '[.content[] | {id, login: .realName, name: .realName, email}]'
}

usage() {
  cat >&2 <<EOF
Usage: tracker <command> [args]

Commands:
  whoami
  list-columns
  list-tasks --column <name> [--assignee <login|me|none>] [--limit N]
  get-task <id>
  list-comments <id> [--since <id>] [--limit N]
  comment <id> <text> | comment <id> --file <path>
  move-task <id> --column <name>
  assign-task <id> --user <login|me|none>
  create-task --title <t> [--column <c>] [--description <d>] [--description-file <p>] [--assignee <u>]...
  delete-task <id>
  list-users

See skills/tracker-setup/cli-contract.md for the full contract.
EOF
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    whoami)        cmd_whoami "$@" ;;
    list-columns)  cmd_list_columns "$@" ;;
    list-tasks)    cmd_list_tasks "$@" ;;
    get-task)      cmd_get_task "$@" ;;
    list-comments) cmd_list_comments "$@" ;;
    comment)       cmd_comment "$@" ;;
    move-task)     cmd_move_task "$@" ;;
    assign-task)   cmd_assign_task "$@" ;;
    create-task)   cmd_create_task "$@" ;;
    delete-task)   cmd_delete_task "$@" ;;
    list-users)    cmd_list_users "$@" ;;
    ""|-h|--help)  usage; exit 0 ;;
    *)             echo "ERROR: unknown command '$cmd'" >&2; usage; exit 1 ;;
  esac
}

main "$@"
