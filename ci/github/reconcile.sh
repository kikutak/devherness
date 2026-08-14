#!/usr/bin/env bash
# schedule イベントから起動される取りこぼし救済ジョブ(GitLab版 ci/reconcile.sh に対応)。
# GitHub Actionsは `issues: types: [labeled]` で即時起動できるため、GitLab版ほど
# reconcileへの依存度は高くないが、ワークフロー起動失敗時の再送・救済として残す。
#
# 行うこと:
#   (a) label:agent:ready が付いているが、まだループが開始していない
#       (state:* ラベルが無い) Issueを検知し、設計フェーズを起動する。
#   (b) label:rate-limited が付いた(Claude利用枠のレート制限で一時停止中の)
#       Issue/PRを検知し、phase:* ラベルに応じて再試行する。
#
# 前提環境変数:
#   AI_LOOP_TOKEN      - Issue/PR読み書き用(state::REVIEW相当)
#   AI_LOOP_PUSH_TOKEN - review再試行(空コミットpush)用。Contents: Read and write が必要。

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

echo "reconcile: rate-limitedのIssue/PRを再試行します"

rate_limited_json=$(gh_curl GET "/issues?labels=$(jq -rn --arg l 'rate-limited' '$l|@uri')&state=all&per_page=100")

echo "$rate_limited_json" | jq -c '.[]' | while read -r item; do
  number=$(echo "$item" | jq -r '.number')
  is_pr=$(echo "$item" | jq -r 'has("pull_request")')
  labels=$(echo "$item" | jq -c '[.labels[].name]')
  phase=$(gh_scoped_label_value "$labels" "phase")

  if [[ -z "$phase" ]]; then
    echo "reconcile: #${number} はphaseラベルが無いためスキップします" >&2
    continue
  fi

  if [[ "$is_pr" == "true" ]]; then
    head_ref=$(gh_curl GET "/pulls/${number}" | jq -r '.head.ref')
    issue_number="${head_ref##*/issue-}"
  else
    issue_number="$number"
  fi

  echo "reconcile: #${number} (phase=${phase}) を再試行します"

  case "$phase" in
    design|code|verify)
      gh_curl DELETE "/issues/${number}/labels/rate-limited" >/dev/null 2>&1 || true
      gh_dispatch "ai-loop-${phase}" "$issue_number"
      ;;
    review)
      # review/testはpull_requestイベント(synchronize)経由でのみ起動できるため、
      # 空コミットをpushしてsynchronizeイベントを誘発する(要 Contents: write権限)。
      : "${AI_LOOP_PUSH_TOKEN:?AI_LOOP_PUSH_TOKEN is required to retry review phase}"
      branch="agent-loop/issue-${issue_number}"
      git config --global --add safe.directory '*' || true
      git config --global user.email "ai-loop-bot@users.noreply.github.com"
      git config --global user.name "ai-loop-bot"
      git remote set-url origin "https://x-access-token:${AI_LOOP_PUSH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
      git fetch origin "$branch"
      git checkout -B "$branch" "origin/${branch}"
      git commit --allow-empty -m "chore(ai-loop): retry review after rate limit (issue #${issue_number})"
      git push origin "HEAD:refs/heads/${branch}"
      gh_curl DELETE "/issues/${number}/labels/rate-limited" >/dev/null 2>&1 || true
      ;;
    *)
      echo "reconcile: 未知のphase '${phase}' です(#${number})" >&2
      ;;
  esac
done

echo "reconcile: done"
