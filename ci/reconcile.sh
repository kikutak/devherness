#!/usr/bin/env bash
# schedule stage (Pipeline Schedule / cron) から起動されるリコンサイラ。
# 常駐サーバを持たない代わりに、定期実行で以下を救済する:
#   (a) label `agent::ready` が付いているが、まだループが開始していない
#       (state::* ラベルが無い) Issueを検知し、設計フェーズを起動する。
#
# 未実装(将来課題, docs/design/multi-agent-dev-loop.md 11章参照):
#   (b) Trigger API呼び出し失敗等で停止した状態の検知・再送
#   (c) 検証環境タイムアウトの検知
# これらはstate::*ラベルの updated_at と現在時刻の差分から「滞留」を検知する
# ロジックが必要になるため、誤検知でループを暴走させないよう別途慎重に設計すること。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

: "${CI_DEFAULT_BRANCH:?}"

echo "reconcile: agent::ready かつ未着手のIssueを検索します"

issues_json=$(gl_curl GET "/issues?labels=agent::ready&state=opened&per_page=50")

echo "$issues_json" | jq -c '.[]' | while read -r issue; do
  iid=$(echo "$issue" | jq -r '.iid')
  labels=$(echo "$issue" | jq -c '.labels')
  state=$(gl_scoped_label_value "$labels" "state")
  if [[ -n "$state" ]]; then
    continue
  fi
  echo "reconcile: issue #${iid} は未着手です。設計フェーズを起動します。"
  gl_issue_update_labels "$iid" "state::design" ""
  ISSUE_IID="$iid" gl_trigger_pipeline "$CI_DEFAULT_BRANCH" "design" "$iid"
done

echo "reconcile: done"
