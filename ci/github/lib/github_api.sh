#!/usr/bin/env bash
# GitHub REST API の共通ヘルパー(GitLab版 ci/lib/gitlab_api.sh に対応)。
# 各ロールスクリプト(ci/github/*.sh)からsourceして使う。
#
# 前提環境変数(GitHub Actionsが自動注入するもの):
#   GITHUB_API_URL   - 例: https://api.github.com (GHESでは https://<host>/api/v3)
#   GITHUB_REPOSITORY - 例: my-org/my-repo
#   AI_LOOP_TOKEN     - ロールごとにワークフロー側で払い出すアクセストークン(最小権限)
#
# 注意: GitHubの労働 "issue" API は Pull Request のラベル/コメント操作も兼ねる
# (PRは内部的にissueの一種として扱われるため、/issues/{number}/... で両方に使える)。
#
# 依存: curl, jq

set -euo pipefail

: "${GITHUB_API_URL:?GITHUB_API_URL is required (set by GitHub Actions)}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required (set by GitHub Actions)}"
: "${AI_LOOP_TOKEN:?AI_LOOP_TOKEN is required (role-scoped GitHub access token)}"

_gh_base="${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}"

# gh_curl <METHOD> <PATH_FROM_REPO_ROOT> [JSON_BODY]
# 例: gh_curl GET "/issues/${ISSUE_NUMBER}"
gh_curl() {
  local method="$1" path="$2" body="${3:-}"
  local url="${_gh_base}${path}"
  local args=(-sS -f -X "$method"
    -H "Authorization: Bearer ${AI_LOOP_TOKEN}"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  if [[ -n "$body" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi
  curl "${args[@]}" "$url"
}

# gh_issue_get <number> -> JSON (PRにも使える)
gh_issue_get() {
  gh_curl GET "/issues/$1"
}

# gh_issue_labels <number> -> ラベル名の配列(JSON)
gh_issue_labels() {
  gh_issue_get "$1" | jq -c '[.labels[].name]'
}

# gh_scoped_label_value <labels_json_array> <scope>
# 例: gh_scoped_label_value "$labels" "state" -> "reviewing"
# GitHubにはGitLabの「スコープ付きラベル自動置換」が無いため、
# 同一スコープの値は常に高々1つになるよう gh_set_scoped_label 側で管理する。
gh_scoped_label_value() {
  local labels_json="$1" scope="$2"
  echo "$labels_json" | jq -r --arg scope "$scope" '
    map(select(startswith($scope + ":")))
    | if length > 0 then .[0][($scope | length) + 1:] else "" end
  '
}

# gh_set_scoped_label <number> <scope> <new_value>
# 同一スコープ(例: "state")の既存ラベルを全て外してから新しい値のラベルを付与する。
# GitHubはissueに付けるラベルが未作成でも自動作成されるため事前登録は不要。
gh_set_scoped_label() {
  local number="$1" scope="$2" value="$3"
  local labels_json current
  labels_json=$(gh_issue_labels "$number")
  current=$(echo "$labels_json" | jq -r --arg scope "$scope" '.[] | select(startswith($scope + ":"))')
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local enc
    enc=$(jq -rn --arg n "$name" '$n|@uri')
    gh_curl DELETE "/issues/${number}/labels/${enc}" >/dev/null 2>&1 || true
  done <<< "$current"
  gh_curl POST "/issues/${number}/labels" "$(jq -n --arg l "${scope}:${value}" '{labels: [$l]}')" >/dev/null
}

# gh_remove_scoped_label <number> <scope>
gh_remove_scoped_label() {
  local number="$1" scope="$2"
  local labels_json current name
  labels_json=$(gh_issue_labels "$number")
  current=$(echo "$labels_json" | jq -r --arg scope "$scope" '.[] | select(startswith($scope + ":"))')
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    local enc
    enc=$(jq -rn --arg n "$name" '$n|@uri')
    gh_curl DELETE "/issues/${number}/labels/${enc}" >/dev/null 2>&1 || true
  done <<< "$current"
}

# gh_issue_note <number> <body_text> (PRにも使える、issuesエンドポイント共通)
gh_issue_note() {
  local number="$1" text="$2"
  gh_curl POST "/issues/${number}/comments" "$(jq -n --arg b "$text" '{body:$b}')" >/dev/null
}

# gh_issue_notes <number> -> コメント配列(JSON)
gh_issue_notes() {
  gh_curl GET "/issues/$1/comments?per_page=100"
}

# gh_issue_close <number>
gh_issue_close() {
  gh_curl PATCH "/issues/$1" '{"state":"closed"}' >/dev/null
}

# gh_pr_create <head_branch> <base_branch> <title> <body> -> JSON
gh_pr_create() {
  local head="$1" base="$2" title="$3" body="$4"
  gh_curl POST "/pulls" "$(jq -n --arg h "$head" --arg b "$base" --arg t "$title" --arg d "$body" \
    '{head:$h, base:$b, title:$t, body:$d}')"
}

# gh_pr_find_by_head_branch <head_branch> -> PR番号 もしくは空文字
gh_pr_find_by_head_branch() {
  local head="$1" owner="${GITHUB_REPOSITORY%%/*}"
  gh_curl GET "/pulls?head=${owner}:$(jq -rn --arg h "$head" '$h|@uri')&state=open" \
    | jq -r 'if length > 0 then .[0].number else "" end'
}

# gh_pr_update_body <number> <body_text>
gh_pr_update_body() {
  gh_curl PATCH "/pulls/$1" "$(jq -n --arg b "$2" '{body:$b}')" >/dev/null
}

# gh_pr_merge <number>
gh_pr_merge() {
  gh_curl PUT "/pulls/$1/merge" '{"merge_method":"merge"}'
}

# gh_dispatch <event_type> <issue_number> [extra_client_payload_json_object]
# GitLabのPipeline Trigger APIに相当。repository_dispatchイベントを飛ばして
# 呼び出し側ワークフロー(.github/workflows/ai-loop-reusable.yml)の
# 次フェーズ相当のjobを起動する。event_typeで design/code/merge を区別する。
gh_dispatch() {
  local event_type="$1" issue_number="$2" extra="${3:-}"
  if [[ -z "$extra" ]]; then
    extra='{}'
  fi
  : "${AI_LOOP_TOKEN:?}"
  local payload
  payload=$(jq -n --arg et "$event_type" --arg iss "$issue_number" --argjson extra "$extra" \
    '{event_type: $et, client_payload: ({issue_number: ($iss|tonumber)} + $extra)}')
  gh_curl POST "/dispatches" "$payload" >/dev/null
}
