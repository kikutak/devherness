#!/usr/bin/env bash
# 設計役jobの最後に実行する(GitLab版 ci/gitlab_open_or_update_mr.sh に対応)。
# ワーキングツリーにClaude Codeが書き込んだ変更(設計doc・実装の雛形)を
# 専用ブランチ agent-loop/issue-<n> にコミット&pushし、
# 対応するPRが無ければ作成、あれば説明文を更新する。
#
# 前提: git remoteは AI_LOOP_TOKEN で認証済み(ワークフロー側で設定する)。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${DEFAULT_BRANCH:?DEFAULT_BRANCH is required}"

branch="agent-loop/issue-${ISSUE_NUMBER}"
title_file=".agent-loop/mr-title.txt"
desc_file=".agent-loop/mr-description.md"

if [[ ! -f "$title_file" ]]; then
  echo "github_open_or_update_pr: ${title_file} がありません(design-role.mdの出力契約を確認してください)" >&2
  exit 1
fi

title=$(cat "$title_file")
description=$(cat "$desc_file" 2>/dev/null || echo "")
description="${description}

---
Agent-Loop-Issue ${ISSUE_NUMBER}"

git add -A
if git diff --cached --quiet; then
  echo "github_open_or_update_pr: 差分がありません。コミットをスキップします。"
else
  git commit -m "chore(ai-loop): design output for issue #${ISSUE_NUMBER}"
fi

git push origin "HEAD:refs/heads/${branch}"

existing_number=$(gh_pr_find_by_head_branch "$branch")

if [[ -z "$existing_number" ]]; then
  echo "github_open_or_update_pr: PRを新規作成します (branch=${branch})"
  pr_json=$(gh_pr_create "$branch" "$DEFAULT_BRANCH" "$title" "$description")
  pr_number=$(echo "$pr_json" | jq -r '.number')
  gh_set_scoped_label "$pr_number" "state" "coding"
  gh_set_scoped_label "$pr_number" "loop" "0"
else
  echo "github_open_or_update_pr: 既存PR #${existing_number} を更新します"
  pr_number="$existing_number"
  gh_pr_update_body "$pr_number" "$description"
  gh_set_scoped_label "$pr_number" "state" "coding"
fi

echo "pr_number=${pr_number}" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "github_open_or_update_pr: done (PR #${pr_number})"
