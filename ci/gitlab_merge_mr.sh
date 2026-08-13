#!/usr/bin/env bash
# merge-gate job: レビュー役(Claude)の合否判断とは別プロセスとして、
# 決定論的にマージを実行する(Claudeは呼ばない)。
# docs/adr/0004-merge-gate-separation.md 参照。
#
# このjobは Pipeline Trigger API 経由(LOOP_PHASE=merge)で起動されるため
# CI_MERGE_REQUEST_IID は設定されていない。ISSUE_IID からトラッキングブランチ名を
# 逆算し、対応するMRを検索する。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

: "${ISSUE_IID:?ISSUE_IID is required}"

branch="agent-loop/issue-${ISSUE_IID}"
mr_iid=$(gl_mr_find_by_source_branch "$branch")

if [[ -z "$mr_iid" ]]; then
  echo "gitlab_merge_mr: branch=${branch} に対応するopen MRが見つかりません" >&2
  exit 1
fi

labels_json=$(gl_mr_labels "$mr_iid")
state=$(gl_scoped_label_value "$labels_json" "state")

if [[ "$state" != "approved" ]]; then
  echo "gitlab_merge_mr: MR #${mr_iid} の状態が state::approved ではありません (現在: ${state:-<none>})。マージを中止します。" >&2
  exit 1
fi

echo "gitlab_merge_mr: MR #${mr_iid} をマージします"
# 注意: プロジェクト設定で「パイプラインの成功」がマージ条件になっている場合、
# 本jobを含む現在のパイプラインが完了していないため、マージAPIが拒否される可能性がある。
# 導入先GitLabインスタンスの Merge checks 設定を確認し、必要であれば
# 本jobをこのパイプラインの最終stageに置く/`merge_when_pipeline_succeeds` の扱いを見直すこと。
gl_mr_merge "$mr_iid" >/dev/null

gl_mr_update_labels "$mr_iid" "state::merged" "state::${state}"
echo "gitlab_merge_mr: done"
