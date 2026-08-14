# devherness

Claude Codeによるマルチエージェント自動開発ループ(設計・コーディング・レビュー・テスト・検証)を、CI/CDの機能のみで実現するための**コンポーネント/テンプレートリポジトリ**です。GitLab CI/CD Component版(実機検証済み)とGitHub Actions版(実機未検証、[ADR-0006](docs/adr/0006-github-actions-support.md)参照)の2系統を提供しています。他プロジェクトはこのリポジトリが発行するコンポーネント/reusable workflowとコンテナイメージを利用します。

設計の背景・アーキテクチャの詳細は [docs/design/multi-agent-dev-loop.md](docs/design/multi-agent-dev-loop.md)(GitLab版がベース)、個々の設計判断は [docs/adr/](docs/adr/) を参照してください。GitHub版固有の情報は本READMEの [GitHub Actions版について](#github-actions版について) を参照してください。

## 構成

```
templates/multi-agent-loop/template.yml  - GitLab CI/CD Component定義
.github/workflows/ai-loop-reusable.yml   - GitHub Actions reusable workflow定義
examples/github/caller-workflow.yml      - GitHub利用側リポジトリ向けテンプレート
docker/agent-runner/Dockerfile           - 各roleジョブの実行イメージ(ci/・prompts/を焼き込む、GitLab/GitHub共用)
ci/                                       - GitLab連携スクリプト(イメージにCOPYされる)
ci/github/                                - GitHub連携スクリプト(イメージにCOPYされる)
prompts/                                  - GitLab版ロールのシステムプロンプト(イメージにCOPYされる)
prompts/github/                           - GitHub版ロールのシステムプロンプト(イメージにCOPYされる)
mcp/                                      - GitLab MCPサーバ設定テンプレート
docs/                                     - 設計ドキュメント・ADR
```

`ci/`・`prompts/`・`mcp/`はコンポーネント利用側のリポジトリには配置されません。`docker/agent-runner/Dockerfile`でビルドしたイメージの`/opt/ai-loop/`配下に焼き込まれ、各jobはそのイメージ内のパスを直接呼び出します。

## 前提: devhernessプロジェクトの可視性

devhernessは**Private不可、Internal以上**にしてください。理由は、`merge_request_event`パイプライン(コーディング役のpushで自動発火するテスト/レビュー等)は、pushを行ったBotユーザー(各`AI_LOOP_BOT_TOKEN_*`に紐づくProject Access Token所有者)の権限で`include: component:`が解決されるため、devhernessがPrivateのままだとBotユーザーがdevhernessへのアクセス権を持たず、`Component '...' - project does not exist or you don't have sufficient permissions`エラーでパイプライン自体が作成できなくなる(実機検証で確認済み)。devhernessにはCI/CD変数等の秘密情報は含まれない(すべて利用側プロジェクトのCI/CD変数として管理される)ため、Internal公開は安全である。

## 利用方法(コンポーネント利用側プロジェクト)

対象プロジェクトの`.gitlab-ci.yml`に以下を追加します。

```yaml
include:
  - component: $CI_SERVER_FQDN/<group>/devherness/multi-agent-loop@<version>
    inputs:
      image: "$CI_REGISTRY/<group>/devherness/agent-runner:<version>"
      test_command: "npm test"        # 対象プロジェクトの言語・テストランナーに合わせる
      max_loop: 5
      verify_environment: "staging"
      mcp_allowed_tools: ""           # MCPサーバ導入後に許可ツール名を設定(下記参照)
      runner_tags: ["docker"]         # プロジェクトのRunnerがuntagged jobを拾わない設定の場合は必須。Settings > CI/CD > Runnersで確認
```

`<version>`はこのリポジトリのタグ(例: `1.0.0`)を指定してください。

## 必要なCI/CD変数(利用側プロジェクトで設定)

| 変数名 | 用途 | 備考 |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude Code CLIの認証(従量課金APIキー、本番運用向け) | console.anthropic.comで発行。Protected + Masked推奨 |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code CLIの認証(Pro/Maxサブスクリプション、PoC向け) | 手元で`claude setup-token`を実行して発行(1年間有効、推論専用)。`ANTHROPIC_API_KEY`とどちらか一方を設定すればよい。継続的な自動ループ運用では利用枠超過・利用規約上の懸念があるため、本番は`ANTHROPIC_API_KEY`推奨(README下部の注意点も参照) |
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
   - **GitLabの「Run pipeline」画面**(プロジェクト > Build > Pipelines > Run pipeline)から、ブランチ/タグを選択し、CI/CD変数に `LOOP_PHASE=design`, `ISSUE_IID=<issue iid>` を入力して実行する。トークン不要でブラウザだけで完結する(動作確認時におすすめ)。
   - Pipeline Trigger APIを `LOOP_PHASE=design`, `ISSUE_IID=<issue iid>` 変数付きでPOST呼び出しする(即時起動、CI外の自動化から使う想定)。
   - Pipeline Schedule(cron)を設定しておけば、`reconcile` jobが定期的に `agent::ready` かつ未着手のIssueを検知して自動的に起動する(取りこぼし救済、詳細は [ADR-0001](docs/adr/0001-orchestration-gitlab-ci-only.md))。

上記いずれの方法でも、`guard`・`design-role`等のjobは `$CI_PIPELINE_SOURCE` が `web`(Run pipeline画面) または `trigger`(Trigger API)のいずれかにマッチするよう `template.yml` 側で対応済み。

以降はレビュー→修正→マージ→検証→(必要なら再設計)まで自動で進行します。詳細なシーケンスは [docs/design/multi-agent-dev-loop.md 3章](docs/design/multi-agent-dev-loop.md#3-ループ全体のシーケンス) を参照してください。

## 未確定・導入時に確認が必要な事項

実装にあたり、以下は本リポジトリ単独では検証できないため、導入先のGitLabインスタンス/Claude Code CLIのバージョンで確認してください。

- `claude` CLIの正確なフラグ名(`--allowedTools` 等)はバージョンにより変わる可能性があるため、`claude --help` で確認する。
- **`--permission-mode bypassPermissions` について**: `-p`(非対話)モードではTTYが無く承認プロンプトを表示できないため、`--allowedTools`を指定していてもWrite/Edit/Bash等の書き込み系ツール呼び出しが「承認待ち」のまま拒否される(実機検証で確認済み)。これを回避するため全ロールのclaude呼び出しに`--permission-mode bypassPermissions`を付与している。**この設定下でも`--allowedTools`によるツール制限が実効的に機能するかは要検証**(bypassPermissionsが承認プロンプトの省略のみを行うのか、allowedTools自体も無効化してしまうのかを、実際のGitLab環境で確認すること)。仮にallowedToolsが効かなくなる場合、Claudeへのツール制限による安全設計([docs/design/multi-agent-dev-loop.md 9章](docs/design/multi-agent-dev-loop.md#9-セキュリティ権限設計))が機能しなくなるため、コンテナ・ネットワーク・GitLabトークン権限など他の防御層を主たる境界として見直す必要がある。
- GitLab MCPサーバのパッケージ名・バージョン・提供ツール名([mcp/gitlab.mcp.json.tmpl](mcp/gitlab.mcp.json.tmpl)、[ADR-0005](docs/adr/0005-gitlab-integration-mcp-vs-cli.md))。選定後、`mcp_allowed_tools` inputに実際のツール名を設定すること。
- スコープ付きラベル(`key::value`)がAPI経由でも自動的に旧ラベルを置換するか、対象GitLabのバージョン/設定で実地検証する([ADR-0002](docs/adr/0002-state-management-labels-and-repo-file.md))。
- プロジェクトの「マージ条件(pipelines must succeed等)」設定と、`merge-gate` job(同一パイプライン内からのマージAPI呼び出し)の組み合わせが問題なく動作するか([ci/gitlab_merge_mr.sh](ci/gitlab_merge_mr.sh)のコメント参照)。
- Pipeline Scheduleの最小実行間隔([ADR-0001](docs/adr/0001-orchestration-gitlab-ci-only.md))。
- **TLS証明書の検証について**: 自己署名/内部CA証明書を使うGitLabインスタンスの場合、Dockerレジストリ・dind・git等、複数の箇所で個別にTLS検証を回避する設定が必要になった(このリポジトリでは動作確認の速度を優先し、Runnerホストの`insecure-registries`設定や`git config http.sslVerify false`等のクイックな回避策を採用している)。**本番導入時は、内部CA証明書を`docker/agent-runner/Dockerfile`のOS信頼ストアに登録し`update-ca-certificates`する方式に切り替え、TLS検証を有効なままにすることを強く推奨する。**

その他の未解決事項は [docs/design/multi-agent-dev-loop.md 11章](docs/design/multi-agent-dev-loop.md#11-未解決将来検討事項) にまとめています。

## GitHub Actions版について

**このGitHub Actions版は実際のGitHubリポジトリでの動作検証をまだ行っていません。** 上記GitLab版は多数回の実機デバッグを経て安定化させたものですが、GitHub版は設計・実装のみの段階です。導入時は同様の検証サイクル(認証・権限・YAML構文・イベント条件などのデバッグ)が必要になる前提で進めてください。詳細な設計判断は [ADR-0006](docs/adr/0006-github-actions-support.md) を参照してください。

### イメージの準備(devherness側、初回のみ)

`.github/workflows/build-image.yml` が `main` へのpush(`docker/agent-runner/**`等の変更時)で自動的に `ghcr.io/<owner>/devherness/agent-runner` へイメージを発行する。devhernessがPrivateリポジトリの場合、発行されるパッケージも既定でPrivateになるため、**利用側リポジトリからpullできるようにパッケージ側でアクセス許可が必要**(GitLab版で`Component`解決のためにInternal可視性が必要だったのと同種の注意点)。

1. `https://github.com/<owner>?tab=packages` からパッケージ `devherness/agent-runner` を開く
2. **Package settings > Manage Actions access** で、利用側リポジトリ(例: `test`)を追加し、Role を **Read** にする

### 利用方法(GitHub側、対象リポジトリ)

1. [examples/github/caller-workflow.yml](examples/github/caller-workflow.yml) を対象リポジトリの `.github/workflows/ai-loop.yml` としてコピーする。
2. `<org>`・`branches: [main]`・`image:` 等、コメントに従って調整する(`image:` は `ghcr.io/<owner>/devherness/agent-runner:latest` 等)。
3. 対象リポジトリの **Settings > Secrets and variables > Actions** に以下を登録する。

| Secret名 | 用途 | 備考 |
|---|---|---|
| `ANTHROPIC_API_KEY` または `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code CLIの認証 | GitLab版と同様、詳細は上記表参照 |
| `AI_LOOP_GH_TOKEN_DESIGN` | 設計役用GitHubアクセストークン(Fine-grained PAT推奨) | 対象リポジトリへの読み取り+Issue/PR書き込み権限 |
| `AI_LOOP_GH_TOKEN_CODE` | コーディング役用GitHubアクセストークン | 対象リポジトリへのpush(contents: write)権限 |
| `AI_LOOP_GH_TOKEN_REVIEW` | レビュー役/guard/test/escalate用GitHubアクセストークン | Issue/PRコメント・ラベル操作権限のみ、マージ権限は付与しない |
| `AI_LOOP_GH_TOKEN_MERGE` | merge-gate用GitHubアクセストークン | マージ権限(pull_requests: write)を持つのはこのトークンのみ |
| `AI_LOOP_GH_TOKEN_VERIFY` | 検証役用GitHubアクセストークン | Environment secretsとしてのスコープ限定を推奨 |
| `AI_LOOP_NOTIFY_WEBHOOK` | (任意)エスカレーション通知先Slack Incoming Webhook URL | 未設定時はIssue/PRコメントのみ |

GitLabの Pipeline Trigger Token に相当するものはGitHub版では不要(`repository_dispatch`は各Botトークン自体に`repo`スコープがあれば呼び出せる)。

### ループの起動方法(GitHub版)

1. GitHub Issueを作成し、ラベル `agent:ready` を付与する。**この時点で `issues: types: [labeled]` トリガーにより即座に設計フェーズが起動する**(GitLab版のようなポーリング待ちが基本的に不要)。
2. 手動起動したい場合は Actions タブから対象ワークフローを選び、「Run workflow」で `issue_number` / `loop_phase` を指定して実行する(GitLab版の「Run pipeline」画面に相当)。

以降のレビュー→修正→マージ→検証→(必要なら再設計)の流れはGitLab版と同じ考え方で実装している([docs/design/multi-agent-dev-loop.md 3章](docs/design/multi-agent-dev-loop.md#3-ループ全体のシーケンス)参照、GitHub版はイベント名・API呼び出しが異なる)。
