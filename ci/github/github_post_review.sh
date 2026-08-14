#!/usr/bin/env bash
# レビュー役jobの最後に実行する(GitLab版 ci/gitlab_post_review.sh に対応)。
# reviewer-role.md(GitHub版)の出力契約により、Claudeは作業ディレクトリに
# review-result.json を書き出す想定:
#   {"verdict": "approve"|"changes_requested", "summary": "...", "comments": [...]}
#
# verdict=approve            -> state:approved を付与し、merge-gateへ引き渡す
# verdict=changes_requested  -> loopをインクリメントし、state:changes-requested を付与、
#                                コーディング役へ差し戻す

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"

result_file="review-result.json"
if [[ ! -f "$result_file" ]]; then
  echo "github_post_review: ${result_file} がありません(reviewer-role.mdの出力契約を確認してください)" >&2
  exit 1
fi

verdict=$(jq -r '.verdict' "$result_file")
summary=$(jq -r '.summary' "$result_file")

comment_body="## AI Review

${summary}

"
comment_body+=$(jq -r '
  .comments[]?
  | "- `" + .path + ":" + (.line|tostring) + "` " + .body
' "$result_file")

gh_issue_note "$PR_NUMBER" "$comment_body"

labels_json=$(gh_issue_labels "$PR_NUMBER")
current_loop=$(gh_scoped_label_value "$labels_json" "loop")
current_loop="${current_loop:-0}"

case "$verdict" in
  approve)
    echo "github_post_review: approve -> merge-gateへ"
    gh_set_scoped_label "$PR_NUMBER" "state" "approved"
    gh_dispatch "ai-loop-merge" "$ISSUE_NUMBER"
    ;;
  changes_requested)
    next_loop=$((current_loop + 1))
    echo "github_post_review: changes_requested -> loop ${current_loop} -> ${next_loop}"
    gh_set_scoped_label "$PR_NUMBER" "state" "changes-requested"
    gh_set_scoped_label "$PR_NUMBER" "loop" "$next_loop"
    gh_dispatch "ai-loop-code" "$ISSUE_NUMBER"
    ;;
  *)
    echo "github_post_review: 不明なverdict '${verdict}'" >&2
    exit 1
    ;;
esac
