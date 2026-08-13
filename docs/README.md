# docs

## design/

設計ドキュメント。機能や仕組みの全体アーキテクチャ・仕様を記録する。

- [multi-agent-dev-loop.md](design/multi-agent-dev-loop.md) — Claude Codeマルチエージェント自動開発ループのアーキテクチャ設計

## adr/

Architecture Decision Record(ADR)。個々の設計判断とその根拠・トレードオフを、後から経緯を追えるように記録する。番号順に並べ、一度Acceptedになったものは基本的に上書きせず、方針転換時は新しいADRで前のADRをSupersedeする。

- [0001-orchestration-gitlab-ci-only.md](adr/0001-orchestration-gitlab-ci-only.md) — オーケストレーション基盤をGitLab CI/CDのみに限定する
- [0002-state-management-labels-and-repo-file.md](adr/0002-state-management-labels-and-repo-file.md) — 状態管理をラベル+リポジトリ内stateファイルで行う
- [0003-headless-per-stage-agent-execution.md](adr/0003-headless-per-stage-agent-execution.md) — エージェント実行モデルをステージごとの独立headless実行にする
- [0004-merge-gate-separation.md](adr/0004-merge-gate-separation.md) — レビュー判断とマージ実行を別jobに分離する
- [0005-gitlab-integration-mcp-vs-cli.md](adr/0005-gitlab-integration-mcp-vs-cli.md) — GitLab連携をMCPサーバとCLI/API直叩きのハイブリッドにする
