#!/usr/bin/env bash
# 使い方: handle_claude_output.sh <issue_or_pr_number> <phase> <claude_output_json_file>
#
# claude -p --output-format json の出力を検査する。
#   - 正常終了(is_error=false)なら何もせず exit 0
#   - Claude Pro/Maxサブスクリプションのレート制限(usage limit)によるエラーの場合、
#     label "rate-limited" と "phase:<phase>" を付与して exit 3 で終了する。
#     呼び出し元はexit 3を「今回はスキップ、reconcileが後で自動的に再試行する」
#     という意味として扱うこと(ループ回数にはカウントしない)。
#   - それ以外のエラーは exit 1(通常のエラーとして扱われ、ループ回数にカウントされる)。
#
# phase は design|code|review|verify のいずれか。reconcile.sh が再試行時に
# どのフェーズを再開すべきかを判断するために使う。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

number="${1:?usage: handle_claude_output.sh <number> <phase> <output_file>}"
phase="${2:?usage: handle_claude_output.sh <number> <phase> <output_file>}"
output_file="${3:?usage: handle_claude_output.sh <number> <phase> <output_file>}"

if [[ ! -f "$output_file" ]]; then
  echo "handle_claude_output: ${output_file} が見つかりません" >&2
  exit 1
fi

is_error=$(jq -r '.is_error // false' "$output_file" 2>/dev/null || echo "true")

if [[ "$is_error" != "true" ]]; then
  exit 0
fi

result=$(jq -r '.result // ""' "$output_file" 2>/dev/null || echo "")

# claude CLI内部のレート制限メッセージパターン(実機のバイナリ文字列調査に基づく)。
if echo "$result" | grep -qiE 'usage limit|rate limit|usage_cap_reached|reached your specified.*usage limits'; then
  echo "handle_claude_output: レート制限を検知しました(number=${number}, phase=${phase})。reconcileによる自動再試行を待ちます。" >&2
  gh_set_scoped_label "$number" "phase" "$phase"
  gh_curl POST "/issues/${number}/labels" '{"labels":["rate-limited"]}' >/dev/null
  gh_issue_note "$number" "⏳ Claude利用枠のレート制限を検知しました。上限がリセットされ次第、自動的に再試行します(手動対応は不要です)。"
  exit 3
fi

echo "handle_claude_output: claudeがエラー終了しました: ${result}" >&2
exit 1
