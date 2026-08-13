#!/usr/bin/env bash
# 検証役jobの最後に実行する。
# verifier-role.md の出力契約により、Claudeは作業ディレクトリに
#   .agent-loop/verification/report.md   (人間可読レポート)
#   .agent-loop/verification/result.json ({"status": "ok"|"failed", "feedback": "string"})
# を書き出す想定。これを専用トラッキングブランチへコミット&pushし、
# push自体が次パイプライン(再設計 or 完了)のトリガーになる
# (docs/design/multi-agent-dev-loop.md 5.2節 参照)。
#
# ISSUE_IID は、mainにマージされた直近コミットのtrailer
# `Agent-Loop-Issue: <iid>` から復元する。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

issue_iid="${ISSUE_IID:-}"
if [[ -z "$issue_iid" ]]; then
  # マージコミット(GitLabのデフォルト)の場合、trailerは直近コミットではなく
  # その親(featコミット)にあるため、直近数コミットを遡って検索する。
  issue_iid=$(git log -5 --format=%B | grep -oP 'Agent-Loop-Issue\s+\K[0-9]+' | head -1 || true)
fi

if [[ -z "$issue_iid" ]]; then
  echo "verify_report_push: ISSUE_IID を特定できませんでした(コミットtrailerを確認してください)" >&2
  exit 1
fi

result_file=".agent-loop/verification/result.json"
if [[ ! -f "$result_file" ]]; then
  echo "verify_report_push: ${result_file} がありません(verifier-role.mdの出力契約を確認してください)" >&2
  exit 1
fi

status=$(jq -r '.status' "$result_file")
branch="agent-loop/issue-${issue_iid}"

git fetch origin "$branch" || true
git checkout -B "$branch" "origin/${branch}" 2>/dev/null || git checkout -B "$branch"

git add .agent-loop/verification
git commit -m "chore(ai-loop): verification result for issue #${issue_iid} (${status})"
git push origin "HEAD:refs/heads/${branch}"

case "$status" in
  ok)
    echo "verify_report_push: 検証OK。Issueをdoneにしてクローズします。"
    gl_issue_update_labels "$issue_iid" "state::done" "state::verifying"
    gl_issue_note "$issue_iid" "検証環境での動作確認が完了しました。詳細: .agent-loop/verification/report.md (branch: ${branch})"
    gl_issue_close "$issue_iid"
    ;;
  failed)
    feedback=$(jq -r '.feedback' "$result_file")
    echo "verify_report_push: 検証NG。再設計フェーズへ差し戻します。"
    gl_issue_update_labels "$issue_iid" "state::verify-failed" "state::verifying"
    gl_issue_note "$issue_iid" "検証環境での動作確認に失敗しました。再設計を開始します。

${feedback}"
    ISSUE_IID="$issue_iid" gl_trigger_pipeline "$branch" "design" "$issue_iid"
    ;;
  *)
    echo "verify_report_push: 不明なstatus '${status}'" >&2
    exit 1
    ;;
esac
