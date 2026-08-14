#!/usr/bin/env bash
# 使い方: trigger_next.sh <design|code|merge> <issue_number>
# GitLab版のPipeline Trigger APIに相当。repository_dispatchイベントを
# event_type=ai-loop-<phase> で飛ばし、呼び出し側ワークフローの
# 該当jobを起動する(.github/workflows/ai-loop-reusable.yml のon.workflow_call
# を呼び出しているCaller workflow側でrepository_dispatchを受ける)。

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/github_api.sh"

phase="${1:?usage: trigger_next.sh <design|code|merge> <issue_number>}"
issue_number="${2:?usage: trigger_next.sh <design|code|merge> <issue_number>}"

echo "trigger_next: phase=${phase} issue=${issue_number}"
gh_dispatch "ai-loop-${phase}" "$issue_number"
