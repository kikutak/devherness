# devherness

Claude Codeによるマルチエージェント自動開発ループ(設計・コーディング・レビュー・テスト・検証)を、社内GitLab CI/CDの機能のみで実現するための**コンポーネント/テンプレートリポジトリ**です。他プロジェクトはこのリポジトリが発行するCI/CD Componentとコンテナイメージを`include:`して利用します。

設計の背景・アーキテクチャの詳細は [docs/design/multi-agent-dev-loop.md](docs/design/multi-agent-dev-loop.md)、個々の設計判断は [docs/adr/](docs/adr/) を参照してください。

## 構成

```
templates/multi-agent-loop/template.yml  - GitLab CI/CD Component定義
docker/agent-runner/Dockerfile           - 各roleジョブの実行イメージ(ci/・prompts/を焼き込む)
ci/                                       - GitLab連携スクリプト(イメージにCOPYされる)
prompts/                                  - 各ロールのシステムプロンプト(イメージにCOPYされる)
mcp/                                      - GitLab MCPサーバ設定テンプレート
docs/                                     - 設計ドキュメント・ADR
```

`ci/`・`prompts/`・`mcp/`はコンポーネント利用側のリポジトリには配置されません。`docker/agent-runner/Dockerfile`でビルドしたイメージの`/opt/ai-loop/`配下に焼き込まれ、`template.yml`の各jobはそのイメージ内のパスを直接呼び出します。

## 利用方法(コンポーネント利用側プロジェクト)

対象プロジェクトの`.gitlab-ci.yml`に以下を追加します。

```yaml
include:
  - component: $CI_SERVER_FQDN/<group>/devherness/multi-agent-loop@<version>
    inputs:
      image: "$CI_REGISTRY_FQDN/<group>/devherness/agent-runner:<version>"
      test_command: "npm test"        # 対象プロジェクトの言語・テストランナーに合わせる
      max_loop: 5
      verify_environment: "staging"
      mcp_allowed_tools: ""           # MCPサーバ導入後に許可ツール名を設定(下記参照)
```

`<version>`はこのリポジトリのタグ(例: `1.0.0`)を指定してください。

## 必要なCI/CD変数(利用側プロジェクトで設定)

| 変数名 | 用途 | 備考 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude Code CLIの認証 | Protected + Masked推奨 |
| `AI_LOOP_BOT_TOKEN_DESIGN` | 設計役用GitLabアクセストークン | 最小権限(MR/Issue読み取り、docs書き込み相当) |
| `AI_LOOP_BOT_TOKEN_CODE` | コーディング役用GitLabアクセストークン | 最小権限(ソースpush) |
| `AI_LOOP_BOT_TOKEN_REVIEW` | レビュー役/guard/test/escalate用GitLabアクセストークン | コメント・ラベル操作のみ、マージ権限は付与しない |
| `AI_LOOP_BOT_TOKEN_MERGE` | merge-gate用GitLabアクセストークン | マージ権限を持つのはこのトークンのみ |
| `AI_LOOP_BOT_TOKEN_VERIFY` | 検証役用GitLabアクセストークン | Protected Environment限定を推奨 |
| `AI_LOOP_TRIGGER_TOKEN` | フェーズ間チェーン用Pipeline Trigger Token | プロジェクト設定のPipeline trigger tokensで発行 |
| `AI_LOOP_NOTIFY_WEBHOOK` | (任意)エスカレーション通知先Slack Incoming Webhook URL | 未設定時はMR/Issueコメントのみ |
| `AI_LOOP_NOTIFY_ASSIGNEE_ID` | (任意)エスカレーション時にアサインするGitLabユーザーID | |

セキュリティ設計の詳細(トークンの権限分離の考え方等)は [docs/design/multi-agent-dev-loop.md 9章](docs/design/multi-agent-dev-loop.md#9-セキュリティ権限設計) を参照してください。

## ループの起動方法

1. GitLab Issueを作成し、ラベル `agent::ready` を付与する。
2. 以下のいずれかで設計フェーズを起動する:
   - Pipeline Trigger APIを `LOOP_PHASE=design`, `ISSUE_IID=<issue iid>` 変数付きで直接呼び出す(即時起動)。
   - Pipeline Schedule(cron)を設定しておけば、`reconcile` jobが定期的に `agent::ready` かつ未着手のIssueを検知して自動的に起動する(取りこぼし救済、詳細は [ADR-0001](docs/adr/0001-orchestration-gitlab-ci-only.md))。

以降はレビュー→修正→マージ→検証→(必要なら再設計)まで自動で進行します。詳細なシーケンスは [docs/design/multi-agent-dev-loop.md 3章](docs/design/multi-agent-dev-loop.md#3-ループ全体のシーケンス) を参照してください。

## 未確定・導入時に確認が必要な事項

実装にあたり、以下は本リポジトリ単独では検証できないため、導入先のGitLabインスタンス/Claude Code CLIのバージョンで確認してください。

- `claude` CLIの正確なフラグ名(`--allowedTools` 等)はバージョンにより変わる可能性があるため、`claude --help` で確認する。
- GitLab MCPサーバのパッケージ名・バージョン・提供ツール名([mcp/gitlab.mcp.json.tmpl](mcp/gitlab.mcp.json.tmpl)、[ADR-0005](docs/adr/0005-gitlab-integration-mcp-vs-cli.md))。選定後、`mcp_allowed_tools` inputに実際のツール名を設定すること。
- スコープ付きラベル(`key::value`)がAPI経由でも自動的に旧ラベルを置換するか、対象GitLabのバージョン/設定で実地検証する([ADR-0002](docs/adr/0002-state-management-labels-and-repo-file.md))。
- プロジェクトの「マージ条件(pipelines must succeed等)」設定と、`merge-gate` job(同一パイプライン内からのマージAPI呼び出し)の組み合わせが問題なく動作するか([ci/gitlab_merge_mr.sh](ci/gitlab_merge_mr.sh)のコメント参照)。
- Pipeline Scheduleの最小実行間隔([ADR-0001](docs/adr/0001-orchestration-gitlab-ci-only.md))。

その他の未解決事項は [docs/design/multi-agent-dev-loop.md 11章](docs/design/multi-agent-dev-loop.md#11-未解決将来検討事項) にまとめています。
