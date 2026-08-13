#!/usr/bin/env bash
# レビュー役jobの最後に実行する。
# reviewer-role.md の出力契約により、Claudeは作業ディレクトリに
# review-result.json を書き出す想定:
#   {
#     "verdict": "approve" | "changes_requested",
#     "summary": "string",
#     "comments": [{"path": "string", "line": number, "body": "string"}, ...]
#   }
#
# verdict=approve      -> state::approved を付与し、merge-gateへ引き渡す
# verdict=changes_requested -> loopをインクリメントし、state::changes-requested を付与、
#                              コーディング役へ差し戻す
#
# 前提: guard job の dotenv (guard.env) が同一パイプライン内で needs 経由で
# 読み込まれ、AI_LOOP_COUNT / AI_LOOP_TARGET_IID が利用可能なこと。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

: "${CI_MERGE_REQUEST_IID:?CI_MERGE_REQUEST_IID is required}"
: "${ISSUE_IID:?ISSUE_IID is required}"

result_file="review-result.json"
if [[ ! -f "$result_file" ]]; then
  echo "gitlab_post_review: ${result_file} がありません(reviewer-role.mdの出力契約を確認してください)" >&2
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

gl_mr_note "$CI_MERGE_REQUEST_IID" "$comment_body"

labels_json=$(gl_mr_labels "$CI_MERGE_REQUEST_IID")
current_state=$(gl_scoped_label_value "$labels_json" "state")
current_loop=$(gl_scoped_label_value "$labels_json" "loop")
current_loop="${current_loop:-0}"

case "$verdict" in
  approve)
    echo "gitlab_post_review: approve -> merge-gateへ"
    gl_mr_update_labels "$CI_MERGE_REQUEST_IID" "state::approved" "state::${current_state}"
    gl_trigger_pipeline "${AI_LOOP_TRACKING_BRANCH:-${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME}}" "merge" "$ISSUE_IID"
    ;;
  changes_requested)
    next_loop=$((current_loop + 1))
    echo "gitlab_post_review: changes_requested -> loop ${current_loop} -> ${next_loop}"
    gl_mr_update_labels "$CI_MERGE_REQUEST_IID" \
      "state::changes-requested,loop::${next_loop}" \
      "state::${current_state},loop::${current_loop}"
    gl_trigger_pipeline "${AI_LOOP_TRACKING_BRANCH:-${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME}}" "code" "$ISSUE_IID"
    ;;
  *)
    echo "gitlab_post_review: 不明なverdict '${verdict}'" >&2
    exit 1
    ;;
esac
