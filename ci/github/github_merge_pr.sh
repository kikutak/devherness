#!/usr/bin/env bash
# merge-gate job: レビュー役(Claude)の合否判断とは別プロセスとして、
# 決定論的にマージを実行する(Claudeは呼ばない。GitLab版 ADR-0004に対応)。
#
# repository_dispatch(event_type=ai-loop-merge)経由で起動されるため、
# ISSUE_NUMBER から head branch 名を逆算してPRを検索する。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"

branch="agent-loop/issue-${ISSUE_NUMBER}"
pr_number=$(gh_pr_find_by_head_branch "$branch")

if [[ -z "$pr_number" ]]; then
  echo "github_merge_pr: branch=${branch} に対応するopen PRが見つかりません" >&2
  exit 1
fi

labels_json=$(gh_issue_labels "$pr_number")
state=$(gh_scoped_label_value "$labels_json" "state")

if [[ "$state" != "approved" ]]; then
  echo "github_merge_pr: PR #${pr_number} の状態が state:approved ではありません (現在: ${state:-<none>})。マージを中止します。" >&2
  exit 1
fi

echo "github_merge_pr: PR #${pr_number} をマージします"
gh_pr_merge "$pr_number" >/dev/null

gh_set_scoped_label "$pr_number" "state" "merged"
echo "github_merge_pr: done"
