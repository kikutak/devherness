#!/usr/bin/env bash
# test stage: 言語・スタックを問わないテスト実行ラッパー。
# 対象プロジェクト側で TEST_COMMAND (component input `test_command`) を
# 定義してもらう想定。既定値は `make test`。
#
# 対象プロジェクトは Makefile 等のタスクランナーで `test` ターゲットを
# 用意することで、本コンポーネントに変更を加えずに任意言語へ対応できる。

set -euo pipefail

: "${TEST_COMMAND:?TEST_COMMAND is required (component input: test_command)}"

echo "run_project_tests: \$ ${TEST_COMMAND}"
sh -c "$TEST_COMMAND"
