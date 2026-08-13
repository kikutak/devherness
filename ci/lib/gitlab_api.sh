#!/usr/bin/env bash
# GitLab REST API v4 の共通ヘルパー。
# 各ロールスクリプト(ci/*.sh)からsourceして使う。
#
# 前提環境変数:
#   CI_API_V4_URL   - GitLabが自動的に注入する (例: https://gitlab.example.com/api/v4)
#   CI_PROJECT_ID   - GitLabが自動的に注入する
#   AI_LOOP_TOKEN   - ロールごとに template.yml 側で払い出すアクセストークン(最小権限)
#
# 依存: curl, jq

set -euo pipefail

: "${CI_API_V4_URL:?CI_API_V4_URL is required (set by GitLab CI)}"
: "${CI_PROJECT_ID:?CI_PROJECT_ID is required (set by GitLab CI)}"
: "${AI_LOOP_TOKEN:?AI_LOOP_TOKEN is required (role-scoped GitLab access token)}"

_gl_base="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}"

# gl_curl <METHOD> <PATH_FROM_PROJECT_ROOT> [JSON_BODY]
# 例: gl_curl GET "/merge_requests/${CI_MERGE_REQUEST_IID}"
gl_curl() {
  local method="$1" path="$2" body="${3:-}"
  local url="${_gl_base}${path}"
  local args=(-sS -f -X "$method" -H "PRIVATE-TOKEN: ${AI_LOOP_TOKEN}")
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}" "$url"
}

# gl_mr_get <iid> -> JSON
gl_mr_get() {
  gl_curl GET "/merge_requests/$1"
}

# gl_mr_labels <iid> -> labels配列(JSON)
gl_mr_labels() {
  gl_mr_get "$1" | jq -c '.labels'
}

# gl_scoped_label_value <labels_json_array> <scope>
# 例: gl_scoped_label_value "$labels" "state" -> "reviewing"
# 見つからない場合は空文字を返す。
gl_scoped_label_value() {
  local labels_json="$1" scope="$2"
  echo "$labels_json" | jq -r --arg scope "$scope" '
    map(select(startswith($scope + "::")))
    | if length > 0 then .[0][($scope | length) + 2:] else "" end
  '
}

# gl_mr_update_labels <iid> <add_csv> <remove_csv>
# スコープ付きラベルの置換はGitLab側が同一スコープの旧ラベルを自動的に外す前提。
# (要 動作確認: GitLabのバージョン/設定によりAPI経由での自動置換挙動が異なる場合があるため、
#  導入時に対象GitLabインスタンスで実地検証すること)
gl_mr_update_labels() {
  local iid="$1" add_csv="$2" remove_csv="${3:-}"
  local body
  body=$(jq -n --arg add "$add_csv" --arg remove "$remove_csv" \
    '{add_labels: $add} + (if $remove != "" then {remove_labels: $remove} else {} end)')
  gl_curl PUT "/merge_requests/${iid}" "$body" >/dev/null
}

# gl_issue_update_labels <iid> <add_csv> <remove_csv>
gl_issue_update_labels() {
  local iid="$1" add_csv="$2" remove_csv="${3:-}"
  local body
  body=$(jq -n --arg add "$add_csv" --arg remove "$remove_csv" \
    '{add_labels: $add} + (if $remove != "" then {remove_labels: $remove} else {} end)')
  gl_curl PUT "/issues/${iid}" "$body" >/dev/null
}

# gl_mr_note <iid> <body_text>
gl_mr_note() {
  local iid="$1" text="$2"
  local body
  body=$(jq -n --arg body "$text" '{body: $body}')
  gl_curl POST "/merge_requests/${iid}/notes" "$body" >/dev/null
}

# gl_issue_note <iid> <body_text>
gl_issue_note() {
  local iid="$1" text="$2"
  local body
  body=$(jq -n --arg body "$text" '{body: $body}')
  gl_curl POST "/issues/${iid}/notes" "$body" >/dev/null
}

# gl_issue_get <iid>
gl_issue_get() {
  gl_curl GET "/issues/$1"
}

# gl_issue_close <iid>
gl_issue_close() {
  gl_curl PUT "/issues/$1" '{"state_event":"close"}' >/dev/null
}

# gl_issue_notes <iid> -> notes配列(JSON、システム通知除く)
gl_issue_notes() {
  gl_curl GET "/issues/$1/notes?per_page=100&sort=asc&order_by=created_at" \
    | jq -c '[.[] | select(.system == false)]'
}

# gl_mr_create <source_branch> <target_branch> <title> <description> <labels_csv>
gl_mr_create() {
  local source="$1" target="$2" title="$3" desc="$4" labels="$5"
  local body
  body=$(jq -n --arg src "$source" --arg tgt "$target" --arg title "$title" \
    --arg desc "$desc" --arg labels "$labels" \
    '{source_branch:$src, target_branch:$tgt, title:$title, description:$desc, labels:$labels, remove_source_branch:true}')
  gl_curl POST "/merge_requests" "$body"
}

# gl_mr_find_by_source_branch <source_branch> -> MR IID もしくは空文字
gl_mr_find_by_source_branch() {
  local source="$1"
  gl_curl GET "/merge_requests?source_branch=$(jq -rn --arg s "$source" '$s|@uri')&state=opened" \
    | jq -r 'if length > 0 then .[0].iid else "" end'
}

# gl_mr_merge <iid>
gl_mr_merge() {
  local iid="$1"
  gl_curl PUT "/merge_requests/${iid}/merge" '{"should_remove_source_branch":true}'
}

# gl_trigger_pipeline <ref> <phase> <issue_iid> [extra_vars_json_object]
# AI_LOOP_TRIGGER_TOKEN (Pipeline Trigger Token) を使って次フェーズのパイプラインを起動する。
gl_trigger_pipeline() {
  local ref="$1" phase="$2" issue_iid="$3" extra="${4:-{}}"
  : "${AI_LOOP_TRIGGER_TOKEN:?AI_LOOP_TRIGGER_TOKEN is required to trigger the next phase}"
  curl -sS -f -X POST \
    -F "token=${AI_LOOP_TRIGGER_TOKEN}" \
    -F "ref=${ref}" \
    -F "variables[LOOP_PHASE]=${phase}" \
    -F "variables[ISSUE_IID]=${issue_iid}" \
    "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/trigger/pipeline" >/dev/null
}

# gl_repo_file_exists <branch> <file_path>
gl_repo_file_exists() {
  local branch="$1" path="$2"
  local enc
  enc=$(jq -rn --arg p "$path" '$p|@uri')
  curl -sS -o /dev/null -w '%{http_code}' -H "PRIVATE-TOKEN: ${AI_LOOP_TOKEN}" \
    "${_gl_base}/repository/files/${enc}?ref=${branch}" | grep -q '^200$'
}

# gl_repo_commit_file <branch> <file_path> <local_file> <commit_message>
# ファイルの新規作成/更新をCommits APIで行う(存在確認して action を切り替える)。
gl_repo_commit_file() {
  local branch="$1" path="$2" local_file="$3" message="$4"
  local action="create"
  if gl_repo_file_exists "$branch" "$path"; then
    action="update"
  fi
  local content
  content=$(base64 -w0 "$local_file" 2>/dev/null || base64 "$local_file")
  local body
  body=$(jq -n --arg branch "$branch" --arg msg "$message" --arg action "$action" \
    --arg path "$path" --arg content "$content" \
    '{branch:$branch, commit_message:$msg, actions:[{action:$action, file_path:$path, content:$content, encoding:"base64"}]}')
  gl_curl POST "/repository/commits" "$body" >/dev/null
}
