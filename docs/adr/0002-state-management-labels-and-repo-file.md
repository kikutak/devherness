# ADR-0002: 状態管理をラベル+リポジトリ内stateファイルで行う

## Status

Accepted (2026-08-13)

## Context

[ADR-0001](0001-orchestration-gitlab-ci-only.md)によりオーケストレーション基盤をGitLab CI/CDのみに限定したため、ループの「現在フェーズ」「ループ回数(revision数)」「履歴」を記録する専用データベースを持たない。しかし、以下の情報は自律ループを安全に運用するために必須である。

- 現在どのフェーズ(設計中/コーディング中/レビュー中/検証中/停止中 等)にあるか(状態機械の単一状態)。
- レビュー→修正ループが何回発生したか(上限回数判定に使用)。
- 各フェーズでエージェントが何を行い、何を判断したかの履歴(人間がエスカレーション時に参照する監査ログ)。

## Decision

専用DBを持たず、以下の三層構成で状態を表現する。

1. **MR/Issueのスコープ付きラベル(`key::value`形式)** — 「現在状態」を表現する。GitLabは同一スコープ内の旧ラベルを新ラベル付与時に自動置換するため、状態機械の「単一状態」表現に適している。
   - `state::design | coding | testing | changes-requested | reviewing | approved | merged | verifying | verify-failed | blocked-human | done`
   - `loop::0`〜`loop::N`(revisionカウンタ)
2. **リポジトリ内stateファイル**(専用トラッキングブランチ`agent-loop/issue-<iid>`配下、`.agent-loop/state.yml`) — 「履歴」を表現する。タイムスタンプ、関連pipeline ID、エージェント出力サマリなどラベルでは表現しきれない詳細を保持する。mainブランチには影響しない専用ブランチに隔離する。
3. **MR/Issueコメント** — 「人間可読ログ」を表現する。各フェーズの結果を時系列コメントとして残し、Issueを機能要求全体のライフサイクルの親、MRを1回の実装試行の子として扱う。

補助的に、コミットメッセージ/MR descriptionのtrailer(`Agent-Loop-Issue: <iid>`)で、どのjobからでもIssue IIDを復元できる相関IDを持たせる。

詳細は [設計ドキュメント 5.1節](../design/multi-agent-dev-loop.md#51-状態の記録先専用dbなし) を参照。

## Consequences

**メリット**
- 追加インフラ不要で[ADR-0001](0001-orchestration-gitlab-ci-only.md)の制約に合致する。
- GitLab UIだけで現在の状態・履歴がすべて可視化され、運用者が特別なツールなしに状況を把握できる。
- ラベルのスコープ機能により、状態の二重付与や不整合が起きにくい。

**デメリット・トレードオフ**
- 複雑なクエリ(例:全プロジェクト横断でのループ回数分布の集計・分析)ができない。必要になれば別途集計バッチを検討する。
- ラベル数の増加によりMR/Issue一覧のUIが煩雑化する可能性がある。
- 同時更新時のレースコンディション(例:guard jobとreview jobが同時にラベルを更新)が起こり得るため、[ADR-0001](0001-orchestration-gitlab-ci-only.md)で触れた`resource_group`によるMR単位の直列化で緩和する必要がある。
