#!/usr/bin/env bash
# 検証役jobの最後に実行する(GitLab版 ci/verify_report_push.sh に対応)。
# verifier-role.md(GitHub版)の出力契約により、Claudeは作業ディレクトリに
#   .agent-loop/verification/report.md   (人間可読レポート)
#   .agent-loop/verification/result.json ({"status": "ok"|"failed", "feedback": "string"})
# を書き出す想定。これを専用トラッキングブランチへコミット&pushし、
# 検証NGの場合はrepository_dispatchで再設計フェーズを起動する。
#
# ISSUE_NUMBER は、マージ後のコミット履歴(直近数コミット、マージコミットの
# 場合trailerは親コミット側にあるため)から `Agent-Loop-Issue <n>` を検索して復元する。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

issue_number="${ISSUE_NUMBER:-}"
if [[ -z "$issue_number" ]]; then
  issue_number=$(git log -5 --format=%B | grep -oP 'Agent-Loop-Issue\s+\K[0-9]+' | head -1 || true)
fi

if [[ -z "$issue_number" ]]; then
  echo "verify_report_push: ISSUE_NUMBER を特定できませんでした(コミットtrailerを確認してください)" >&2
  exit 1
fi

result_file=".agent-loop/verification/result.json"
if [[ ! -f "$result_file" ]]; then
  echo "verify_report_push: ${result_file} がありません(verifier-role.mdの出力契約を確認してください)" >&2
  exit 1
fi

status=$(jq -r '.status' "$result_file")
branch="agent-loop/issue-${issue_number}"

git fetch origin "$branch" || true
git checkout -B "$branch" "origin/${branch}" 2>/dev/null || git checkout -B "$branch"

git add .agent-loop/verification
git commit -m "chore(ai-loop): verification result for issue #${issue_number} (${status})"
git push origin "HEAD:refs/heads/${branch}"

case "$status" in
  ok)
    echo "verify_report_push: 検証OK。Issueをdoneにしてクローズします。"
    gh_set_scoped_label "$issue_number" "state" "done"
    gh_issue_note "$issue_number" "検証環境での動作確認が完了しました。詳細: .agent-loop/verification/report.md (branch: ${branch})"
    gh_issue_close "$issue_number"
    ;;
  failed)
    feedback=$(jq -r '.feedback' "$result_file")
    echo "verify_report_push: 検証NG。再設計フェーズへ差し戻します。"
    gh_set_scoped_label "$issue_number" "state" "verify-failed"
    gh_issue_note "$issue_number" "検証環境での動作確認に失敗しました。再設計を開始します。

${feedback}"
    gh_dispatch "ai-loop-design" "$issue_number"
    ;;
  *)
    echo "verify_report_push: 不明なstatus '${status}'" >&2
    exit 1
    ;;
esac
