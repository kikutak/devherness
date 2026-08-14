#!/usr/bin/env bash
# schedule イベントから起動される取りこぼし救済ジョブ(GitLab版 ci/reconcile.sh に対応)。
# GitHub Actionsは `issues: types: [labeled]` で即時起動できるため、GitLab版ほど
# reconcileへの依存度は高くないが、ワークフロー起動失敗時の再送・救済として残す。
#
# label:agent:ready が付いているが、まだループが開始していない
# (state:* ラベルが無い) Issueを検知し、設計フェーズを起動する。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

echo "reconcile: agent:ready かつ未着手のIssueを検索します"

issues_json=$(gh_curl GET "/issues?labels=$(jq -rn --arg l 'agent:ready' '$l|@uri')&state=open&per_page=100")

echo "$issues_json" | jq -c '[.[] | select(has("pull_request") | not)] | .[]' | while read -r issue; do
  number=$(echo "$issue" | jq -r '.number')
  labels=$(echo "$issue" | jq -c '[.labels[].name]')
  state=$(gh_scoped_label_value "$labels" "state")
  if [[ -n "$state" ]]; then
    continue
  fi
  echo "reconcile: issue #${number} は未着手です。設計フェーズを起動します。"
  gh_set_scoped_label "$number" "state" "design"
  gh_dispatch "ai-loop-design" "$number"
done

echo "reconcile: done"
