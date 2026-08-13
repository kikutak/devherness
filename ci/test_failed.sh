#!/usr/bin/env bash
# test stageでテストが失敗した場合に呼ばれる。
# レビュー役の changes_requested と同様に扱う: loopをインクリメントし、
# state::tests-failed を付与してコーディング役へ差し戻す。
# (テスト失敗もループ回数として数えることで、失敗を無限に繰り返す事態を防ぐ)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

: "${CI_MERGE_REQUEST_IID:?CI_MERGE_REQUEST_IID is required}"
: "${ISSUE_IID:?ISSUE_IID is required}"

labels_json=$(gl_mr_labels "$CI_MERGE_REQUEST_IID")
current_state=$(gl_scoped_label_value "$labels_json" "state")
current_loop=$(gl_scoped_label_value "$labels_json" "loop")
current_loop="${current_loop:-0}"
next_loop=$((current_loop + 1))

echo "test_failed: loop ${current_loop} -> ${next_loop}"
gl_mr_update_labels "$CI_MERGE_REQUEST_IID" \
  "state::tests-failed,loop::${next_loop}" \
  "state::${current_state},loop::${current_loop}"
gl_mr_note "$CI_MERGE_REQUEST_IID" "テストが失敗しました。CIログを確認の上、修正します。(loop ${next_loop})"
gl_trigger_pipeline "${AI_LOOP_TRACKING_BRANCH:-${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME}}" "code" "$ISSUE_IID"
