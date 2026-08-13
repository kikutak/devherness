#!/usr/bin/env bash
# 設計役jobの最後に実行する。
# ワーキングツリーにClaude Codeが書き込んだ変更(設計doc・実装の雛形)を
# 専用ブランチ agent-loop/issue-<iid> にコミット&pushし、
# 対応するMRが無ければ作成、あれば説明文を更新する。
#
# 前提: このjobのgit remoteは AI_LOOP_TOKEN で認証済み(template.yml側で
# `git remote set-url` 等により設定する)。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

: "${ISSUE_IID:?ISSUE_IID is required}"
: "${CI_DEFAULT_BRANCH:?}"

branch="agent-loop/issue-${ISSUE_IID}"
title_file=".agent-loop/mr-title.txt"
desc_file=".agent-loop/mr-description.md"

if [[ ! -f "$title_file" ]]; then
  echo "gitlab_open_or_update_mr: ${title_file} がありません(design-role.mdの出力契約を確認してください)" >&2
  exit 1
fi

title=$(cat "$title_file")
description=$(cat "$desc_file" 2>/dev/null || echo "")
description="${description}

---
Agent-Loop-Issue: ${ISSUE_IID}"

git add -A
if git diff --cached --quiet; then
  echo "gitlab_open_or_update_mr: 差分がありません。コミットをスキップします。"
else
  git commit -m "chore(ai-loop): design output for issue #${ISSUE_IID}"
fi

git push origin "HEAD:refs/heads/${branch}"

existing_iid=$(gl_mr_find_by_source_branch "$branch")

if [[ -z "$existing_iid" ]]; then
  echo "gitlab_open_or_update_mr: MRを新規作成します (branch=${branch})"
  mr_json=$(gl_mr_create "$branch" "$CI_DEFAULT_BRANCH" "$title" "$description" "state::coding,loop::0")
  mr_iid=$(echo "$mr_json" | jq -r '.iid')
else
  echo "gitlab_open_or_update_mr: 既存MR #${existing_iid} を更新します"
  mr_iid="$existing_iid"
  gl_curl PUT "/merge_requests/${mr_iid}" "$(jq -n --arg d "$description" '{description:$d}')" >/dev/null
  gl_mr_update_labels "$mr_iid" "state::coding" ""
fi

echo "MR_IID=${mr_iid}" > "${CI_PROJECT_DIR:-.}/mr.env"
echo "gitlab_open_or_update_mr: done (MR #${mr_iid})"
