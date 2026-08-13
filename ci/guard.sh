#!/usr/bin/env bash
# guard stage: パイプライン先頭で実行し、
#   - state::blocked-human が既に付いていないか
#   - loop::N が MAX_LOOP を超えていないか
# を確認する。超過を検知した場合はここで state::blocked-human を付与して
# 非0終了する(GitLab CIのデフォルト挙動により後続stageは実行されない)。
# escalate stageは `rules: when: always` + ラベル判定で、guardの成否に関わらず
# 独立して起動する(詳細は templates/multi-agent-loop/template.yml 参照)。
#
# 対象は MR(CI_MERGE_REQUEST_IID) または Issue(ISSUE_IID) のどちらか。
# 前提環境変数: MAX_LOOP (既定5, component input経由)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

MAX_LOOP="${MAX_LOOP:-5}"

issue_iid="${ISSUE_IID:-}"

if [[ -n "${CI_MERGE_REQUEST_IID:-}" ]]; then
  target_kind="mr"
  iid="${CI_MERGE_REQUEST_IID}"
  labels_json=$(gl_mr_labels "$iid")
  # merge_request_event パイプラインでは ISSUE_IID がtrigger変数として
  # 渡ってこないため、ブランチ名 agent-loop/issue-<iid> から復元する。
  if [[ -z "$issue_iid" ]]; then
    src_branch="${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-}"
    issue_iid="${src_branch##*/issue-}"
    if ! [[ "$issue_iid" =~ ^[0-9]+$ ]]; then
      echo "guard: ブランチ名 '${src_branch}' からISSUE_IIDを復元できませんでした" >&2
      exit 1
    fi
  fi
elif [[ -n "$issue_iid" ]]; then
  target_kind="issue"
  iid="$issue_iid"
  labels_json=$(gl_issue_get "$iid" | jq -c '.labels')
else
  echo "guard: CI_MERGE_REQUEST_IID も ISSUE_IID も設定されていません。スキップします。" >&2
  exit 0
fi

state=$(gl_scoped_label_value "$labels_json" "state")
loop=$(gl_scoped_label_value "$labels_json" "loop")
loop="${loop:-0}"

echo "guard: target=${target_kind}#${iid} state=${state:-<none>} loop=${loop}/${MAX_LOOP}"

if [[ "$state" == "blocked-human" ]]; then
  echo "guard: 既に state::blocked-human です。人間の対応待ちのため自動化を停止します。" >&2
  exit 1
fi

if (( loop > MAX_LOOP )); then
  echo "guard: loop(${loop}) が MAX_LOOP(${MAX_LOOP}) を超過しました。state::blocked-human を付与します。" >&2
  if [[ "$target_kind" == "mr" ]]; then
    gl_mr_update_labels "$iid" "state::blocked-human" "state::${state}"
  else
    gl_issue_update_labels "$iid" "state::blocked-human" "state::${state}"
  fi
  exit 1
fi

{
  echo "AI_LOOP_COUNT=${loop}"
  echo "AI_LOOP_TARGET_KIND=${target_kind}"
  echo "AI_LOOP_TARGET_IID=${iid}"
  echo "ISSUE_IID=${issue_iid}"
} > guard.env

echo "guard: OK"
