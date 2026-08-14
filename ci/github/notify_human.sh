#!/usr/bin/env bash
# escalate job: state:blocked-human になったIssue/PRについて、
# これまでの経緯を集約したコメントを投稿し、Slack Webhookが設定されていれば通知する
# (GitLab版 ci/notify_human.sh に対応)。
#
# 任意環境変数:
#   AI_LOOP_NOTIFY_WEBHOOK - Slack Incoming Webhook URL (未設定ならコメント投稿のみ)
#   AI_LOOP_NOTIFY_ASSIGNEE - 通知先としてアサインするGitHubユーザー名

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

if [[ -n "${PR_NUMBER:-}" ]]; then
  target_kind="pr"
  number="${PR_NUMBER}"
elif [[ -n "${ISSUE_NUMBER:-}" ]]; then
  target_kind="issue"
  number="${ISSUE_NUMBER}"
else
  echo "notify_human: 対象(Issue/PR)を特定できません" >&2
  exit 1
fi

labels_json=$(gh_issue_labels "$number")
state=$(gh_scoped_label_value "$labels_json" "state")

# escalate jobは常にワークフローに含めるため、実際に state:blocked-human でない
# 場合は何もせず正常終了する。
if [[ "$state" != "blocked-human" ]]; then
  echo "notify_human: state:blocked-human ではありません(現在: ${state:-<none>})。エスカレーション対象外のためスキップします。"
  exit 0
fi

url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/issues/${number}"
message="⚠️ AI開発ループが上限回数に達したため自動化を停止しました。
対象: ${target_kind} #${number}
URL: ${url}
人間による調査・対応をお願いします。
再開する場合は state:blocked-human ラベルを外し loop:0 を付与してください。"

gh_issue_note "$number" "$message"

if [[ -n "${AI_LOOP_NOTIFY_ASSIGNEE:-}" ]]; then
  gh_curl POST "/issues/${number}/assignees" "$(jq -n --arg a "$AI_LOOP_NOTIFY_ASSIGNEE" '{assignees:[$a]}')" >/dev/null
fi

if [[ -n "${AI_LOOP_NOTIFY_WEBHOOK:-}" ]]; then
  curl -sS -f -X POST -H 'Content-Type: application/json' \
    -d "$(jq -n --arg text "$message" '{text:$text}')" \
    "$AI_LOOP_NOTIFY_WEBHOOK" >/dev/null
  echo "notify_human: Slack Webhookに通知しました"
else
  echo "notify_human: AI_LOOP_NOTIFY_WEBHOOK未設定のため、コメント投稿のみ行いました"
fi
