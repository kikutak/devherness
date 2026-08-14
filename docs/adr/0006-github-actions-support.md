# ADR-0006: GitHub Actions版を独立した並行実装として追加する

## Status

Accepted (2026-08-14)

## Context

[ADR-0001](0001-orchestration-gitlab-ci-only.md)〜[ADR-0005](0005-gitlab-integration-mcp-vs-cli.md)で設計・実装したマルチエージェント自動開発ループはGitLab CI/CDに深く依存している(スコープ付きラベル、Pipeline Trigger API、GitLab CI/CD Components、GitLab REST API等)。これをGitHub(GitHub.com)でも使えるようにしたいという要望が出た。

GitHub ActionsとGitLab CI/CDは以下の点で構造的に異なり、単一の設定ファイルで両対応させることはできない。

- YAML構文・実行モデルが別物(GitLab CI/CD Components の `spec:inputs`/`!reference` と、GitHub Actionsの reusable workflow `workflow_call` は互換性がない)。
- トリガーモデルが異なる。GitHub Actionsは `issues: types: [labeled]` で**Issueへのラベル付与を直接トリガーできる**(GitLabにはこの仕組みがなく、[ADR-0001](0001-orchestration-gitlab-ci-only.md)ではスケジュールポーリング(`reconcile`)で代替した)。
- ラベルの挙動が異なる。GitLabの「スコープ付きラベル」(`key::value`、同一スコープの旧ラベルを自動置換)に相当する機能がGitHubには無く、状態遷移のたびに明示的に旧ラベルを削除してから新ラベルを追加する実装が必要。
- API・認証モデルが異なる(GitLab REST API v4 と GitHub REST API、GitLab Project Access Token と GitHub Fine-grained PAT/GitHub App)。
- 「MR→マージ」の仕組みに相当するのが「PR→マージ」で、名称・APIエンドポイントが異なる。

## Decision

GitLab版(`templates/multi-agent-loop/template.yml` 一式)には一切手を加えず、**GitHub Actions向けの完全に独立した並行実装**を追加する。

- 連携スクリプト: `ci/github/`(GitLab版 `ci/*.sh` に1対1対応する形で新設。共通ヘルパーは `ci/github/lib/github_api.sh`)
- ロールプロンプト: `prompts/github/`(GitLab版のMR/GitLab用語をPR/GitHub用語に書き換えたもの)
- オーケストレーション本体: `.github/workflows/ai-loop-reusable.yml`(`on: workflow_call` のreusable workflow。GitLab版 `template.yml` に相当)
- 利用側テンプレート: `examples/github/caller-workflow.yml`(トリガー定義はreusable workflow側に持たせられないため、利用側リポジトリにコピーして使うテンプレートとして提供)
- 実行イメージ: `docker/agent-runner/Dockerfile` は共用し、`gh` CLI(GitHub公式CLI)を追加。GitLab版・GitHub版のスクリプト・プロンプト双方を同一イメージに焼き込む(言語ランタイム等の重複を避けるため)。

### GitHub固有の設計判断

1. **状態管理**: `state:value` / `loop:N` 形式のラベルを使うが、GitHubにはスコープ付きラベルの自動置換が無いため、`gh_set_scoped_label()`(`ci/github/lib/github_api.sh`)が「同一スコープの既存ラベルを検索して削除→新ラベルを追加」を明示的に行う。
2. **初回起動**: `issues: types: [labeled]` イベントを直接トリガーとして使い、GitLab版で必須だったポーリング(reconcile)への依存を下げる。`reconcile`は取りこぼし救済の保険として残す(スケジュール実行の遅延特性は[未解決事項](#未解決将来検討事項)参照)。
3. **フェーズ間チェーン**: GitLabのPipeline Trigger APIに相当する仕組みとして `repository_dispatch` イベント(`event_type: ai-loop-design/ai-loop-code/ai-loop-merge`、`client_payload.issue_number`)を使う。
4. **マージの分離**: [ADR-0004](0004-merge-gate-separation.md)と同様、レビュー役(Claude)と実マージ実行を別jobに分離する方針を維持する。
5. **手動起動**: GitLabの「Run pipeline」画面に相当する`workflow_dispatch`(`issue_number`/`loop_phase`入力)を利用側テンプレートに用意する。

## Consequences

**メリット**
- GitLab版の実装・実運用に一切影響を与えずにGitHub対応を追加できる。
- `issues:labeled`の直接トリガーにより、GitLab版より初動の即時性を高めやすい。
- Dockerイメージ・プロンプトの一部・全体アーキテクチャ(ロール分離・安全機構・マージ分離の考え方)を再利用でき、ゼロから設計し直すコストを避けられる。

**デメリット・トレードオフ**
- スクリプト・ワークフロー定義を二重に保守する必要がある(共通化はDockerイメージと設計思想レベルにとどまる)。
- **本実装はまだ実際のGitHubリポジトリ上で動作検証していない。** GitLab版は多数回の実機デバッグ(認証方式・TLS・権限・YAML構文の落とし穴など)を経て安定化させた経緯があり、GitHub版でも同種・別種の問題が実機テストで見つかる可能性が高い。導入時は同様の検証サイクルを想定すること。

## 未解決・将来検討事項

- **Dockerイメージの配布先**: `container: ${{ inputs.image }}` でprivateなghcr.ioイメージをpullする際の認証方法(`GITHUB_TOKEN`の`packages:read`権限で足りるか、別途credentialsが必要か)は未検証。
- **Botトークンの方式**: 初期実装はFine-grained Personal Access Token(GitLab版のProject Access Tokenに相当)を前提に書いているが、失効管理・監査性の観点ではGitHub App + Installation Tokenへの移行が望ましい。
- **schedule実行の最小間隔・遅延**: GitHub Actionsのcronトリガーは公称間隔より遅延することが知られている(実行負荷が高い時間帯は特に)。即時性が必要な場合は`issues:labeled`の直接トリガーに一本化し、reconcileはあくまで保険と位置付ける。
- **`container:` ジョブでの`actions/checkout@v4`の動作**: Node.js製アクションがカスタムコンテナ内で正常に動くか(agent-runnerイメージはnode:20-slimベースのため動作するはずだが未検証)。
- **PR差分の取得**: `review-role`で`fetch-depth: 0`としているが、実際に`git diff`が意図通り機能するか(GitHubのPRチェックアウトは`refs/pull/<n>/merge`等の特殊refを使うことがあるため)は要確認。
- GitLab版で見つかったのと同種の問題(YAMLの`#`前スペースによるコメント誤解釈、`git push`のrefspec、Protected相当の設定、Botユーザーの権限)がGitHub版でも起こり得るため、実機テスト時は同じ観点でチェックすること。
