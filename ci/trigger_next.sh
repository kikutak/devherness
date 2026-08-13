#!/usr/bin/env bash
# 使い方: trigger_next.sh <design|code|merge> [ref]
# 現在のjobの処理が終わった際に、次フェーズのパイプラインを
# Pipeline Trigger API経由で明示的に起動する。
# ref省略時は $AI_LOOP_TRACKING_BRANCH (専用トラッキングブランチ)を使う。
#
# GitLabはラベル変更単独ではパイプラインを起動しないため、
# 「ジョブが次のジョブを明示的に呼ぶ」ことでループを駆動する
# (docs/adr/0001-orchestration-gitlab-ci-only.md 参照)。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/gitlab_api.sh"

phase="${1:?usage: trigger_next.sh <design|code|merge> [ref]}"
ref="${2:-${AI_LOOP_TRACKING_BRANCH:-}}"
: "${ISSUE_IID:?ISSUE_IID is required}"

if [[ -z "$ref" ]]; then
  echo "trigger_next: refが指定されておらずAI_LOOP_TRACKING_BRANCHも未設定です" >&2
  exit 1
fi

echo "trigger_next: phase=${phase} ref=${ref} issue=${ISSUE_IID}"
gl_trigger_pipeline "$ref" "$phase" "$ISSUE_IID"
