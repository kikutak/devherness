#!/usr/bin/env bash
# guard job: ワークフロー先頭で実行し、
#   - state:blocked-human が既に付いていないか
#   - loop:N が MAX_LOOP を超えていないか
# を確認する。超過を検知した場合はここで state:blocked-human を付与して
# 非0終了する(後続jobは `needs: [guard]` の失敗により自動的にスキップされる)。
# escalate jobのみ `if: always()` 相当で独立して起動する
# (.github/workflows/ai-loop-reusable.yml 参照)。
#
# 対象は Issue(ISSUE_NUMBER) または PR(PR_NUMBER) のどちらか。
# 前提環境変数: MAX_LOOP (既定5, workflow input経由)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

MAX_LOOP="${MAX_LOOP:-5}"

issue_number="${ISSUE_NUMBER:-}"

if [[ -n "${PR_NUMBER:-}" ]]; then
  target_kind="pr"
  number="${PR_NUMBER}"
  labels_json=$(gh_issue_labels "$number")
  # PRイベントではISSUE_NUMBERが渡ってこないため、PRのhead branch名
  # (agent-loop/issue-<n>)から復元する。
  if [[ -z "$issue_number" ]]; then
    head_ref="${PR_HEAD_REF:-}"
    issue_number="${head_ref##*/issue-}"
    if ! [[ "$issue_number" =~ ^[0-9]+$ ]]; then
      echo "guard: head ref '${head_ref}' からISSUE_NUMBERを復元できませんでした" >&2
      exit 1
    fi
  fi
elif [[ -n "$issue_number" ]]; then
  target_kind="issue"
  number="$issue_number"
  labels_json=$(gh_issue_labels "$number")
else
  echo "guard: ISSUE_NUMBER も PR_NUMBER も設定されていません。スキップします。" >&2
  exit 0
fi

state=$(gh_scoped_label_value "$labels_json" "state")
loop=$(gh_scoped_label_value "$labels_json" "loop")
loop="${loop:-0}"

echo "guard: target=${target_kind}#${number} state=${state:-<none>} loop=${loop}/${MAX_LOOP}"

if [[ "$state" == "blocked-human" ]]; then
  echo "guard: 既に state:blocked-human です。人間の対応待ちのため自動化を停止します。" >&2
  exit 1
fi

if (( loop > MAX_LOOP )); then
  echo "guard: loop(${loop}) が MAX_LOOP(${MAX_LOOP}) を超過しました。state:blocked-human を付与します。" >&2
  gh_set_scoped_label "$number" "state" "blocked-human"
  exit 1
fi

{
  echo "blocked=false"
  echo "loop_count=${loop}"
  echo "target_kind=${target_kind}"
  echo "number=${number}"
  echo "issue_number=${issue_number}"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

echo "guard: OK"
