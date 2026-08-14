#!/usr/bin/env bash
# test jobでテストが失敗した場合に呼ばれる(GitLab版 ci/test_failed.sh に対応)。
# レビュー役の changes_requested と同様に扱う: loopをインクリメントし、
# state:tests-failed を付与してコーディング役へ差し戻す。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"

labels_json=$(gh_issue_labels "$PR_NUMBER")
current_loop=$(gh_scoped_label_value "$labels_json" "loop")
current_loop="${current_loop:-0}"
next_loop=$((current_loop + 1))

echo "test_failed: loop ${current_loop} -> ${next_loop}"
gh_set_scoped_label "$PR_NUMBER" "state" "tests-failed"
gh_set_scoped_label "$PR_NUMBER" "loop" "$next_loop"
gh_issue_note "$PR_NUMBER" "テストが失敗しました。CIログを確認の上、修正します。(loop ${next_loop})"
gh_dispatch "ai-loop-code" "$ISSUE_NUMBER"
