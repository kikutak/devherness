#!/usr/bin/env bash
# escalate stage: state::blocked-human になったMR/Issueについて、
# これまでの経緯を集約したコメントを投稿し、Slack Webhookが設定されていれば通知する。
# (docs/design/multi-agent-dev-loop.md 6.1節 参照)
#
# 任意環境変数:
#   AI_LOOP_NOTIFY_WEBHOOK - Slack Incoming Webhook URL (未設定ならコメント投稿のみ)
#   AI_LOOP_NOTIFY_ASSIGNEE_ID - 通知先としてアサインするGitLabユーザーID

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

if [[ -n "${CI_MERGE_REQUEST_IID:-}" ]]; then
  target_kind="mr"
  iid="${CI_MERGE_REQUEST_IID}"
  url="${CI_MERGE_REQUEST_PROJECT_URL:-${CI_PROJECT_URL}}/-/merge_requests/${iid}"
  state=$(gl_scoped_label_value "$(gl_mr_labels "$iid")" "state")
elif [[ -n "${ISSUE_IID:-}" ]]; then
  target_kind="issue"
  iid="${ISSUE_IID}"
  url="${CI_PROJECT_URL}/-/issues/${iid}"
  state=$(gl_scoped_label_value "$(gl_issue_get "$iid" | jq -c '.labels')" "state")
else
  echo "notify_human: 対象(MR/Issue)を特定できません" >&2
  exit 1
fi

# escalate jobは(guardの成否に関わらず)常にパイプラインに含まれるため、
# 実際に state::blocked-human でない場合は何もせず正常終了する。
if [[ "$state" != "blocked-human" ]]; then
  echo "notify_human: state::blocked-human ではありません(現在: ${state:-<none>})。エスカレーション対象外のためスキップします。"
  exit 0
fi

message="⚠️ AI開発ループが上限回数に達したため自動化を停止しました。
対象: ${target_kind} #${iid}
URL: ${url}
人間による調査・対応をお願いします。
再開する場合は state::blocked-human ラベルを外し loop::0 を付与してください。"

if [[ "$target_kind" == "mr" ]]; then
  gl_mr_note "$iid" "$message"
  if [[ -n "${AI_LOOP_NOTIFY_ASSIGNEE_ID:-}" ]]; then
    gl_curl PUT "/merge_requests/${iid}" "$(jq -n --arg id "$AI_LOOP_NOTIFY_ASSIGNEE_ID" '{assignee_ids:[($id|tonumber)]}')" >/dev/null
  fi
else
  gl_issue_note "$iid" "$message"
  if [[ -n "${AI_LOOP_NOTIFY_ASSIGNEE_ID:-}" ]]; then
    gl_curl PUT "/issues/${iid}" "$(jq -n --arg id "$AI_LOOP_NOTIFY_ASSIGNEE_ID" '{assignee_ids:[($id|tonumber)]}')" >/dev/null
  fi
fi

if [[ -n "${AI_LOOP_NOTIFY_WEBHOOK:-}" ]]; then
  curl -sS -f -X POST -H 'Content-Type: application/json' \
    -d "$(jq -n --arg text "$message" '{text:$text}')" \
    "$AI_LOOP_NOTIFY_WEBHOOK" >/dev/null
  echo "notify_human: Slack Webhookに通知しました"
else
  echo "notify_human: AI_LOOP_NOTIFY_WEBHOOK未設定のため、コメント投稿のみ行いました"
fi
