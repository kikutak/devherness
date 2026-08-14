# マルチエージェント自動開発ループの各roleジョブが使う実行イメージ。
# Claude Code CLIと、GitLab連携用のスクリプト・プロンプトを焼き込む。
#
# 注意: @anthropic-ai/claude-code の正確なパッケージ名・バージョン、
# および GitLab MCPサーバのパッケージ名・バージョン(mcp/gitlab.mcp.json.tmpl参照)は
# 社内npmレジストリ/許可リストと突き合わせて導入時に確定すること。

FROM node:20-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    ca-certificates \
    gettext-base \
    make \
    && rm -rf /var/lib/apt/lists/*

# glab CLI (GitLab公式CLI)。バージョンは導入時に固定/更新すること。
ARG GLAB_VERSION=1.51.0
RUN curl -sSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz" \
    -o /tmp/glab.tar.gz \
    && tar -xzf /tmp/glab.tar.gz -C /tmp \
    && mv /tmp/bin/glab /usr/local/bin/glab \
    && rm -rf /tmp/glab.tar.gz /tmp/bin

# gh CLI (GitHub公式CLI)。バージョンは導入時に固定/更新すること。
ARG GH_VERSION=2.63.2
RUN curl -sSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    -o /tmp/gh.tar.gz \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && mv "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" /usr/local/bin/gh \
    && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_amd64"

# gosu (root起動のコンテナ内で、claude実行時だけ非rootユーザーへ切り替えるため)。
# GitHub Actionsのcontainer:ジョブはroot前提の内部動作(actions/checkout等)があるため、
# コンテナ全体は非rootにできない。claude CLIの--permission-mode bypassPermissionsは
# root実行を拒否するため、claude呼び出しの瞬間だけgosuでnodeユーザーに切り替える。
ARG GOSU_VERSION=1.17
RUN curl -sSL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64" \
    -o /usr/local/bin/gosu \
    && chmod +x /usr/local/bin/gosu

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# このループの仕組み一式(GitLab版・GitHub版のスクリプト・プロンプト・MCPテンプレート)を焼き込む
COPY ci/ /opt/ai-loop/ci/
COPY prompts/ /opt/ai-loop/prompts/
COPY mcp/ /opt/ai-loop/mcp/
RUN chmod +x /opt/ai-loop/ci/*.sh /opt/ai-loop/ci/lib/*.sh \
    /opt/ai-loop/ci/github/*.sh /opt/ai-loop/ci/github/lib/*.sh

ENV PATH="/opt/ai-loop/ci:${PATH}"

# claude CLIは --permission-mode bypassPermissions (非対話CI実行に必須) を
# root/sudo権限では拒否するため、claude実行時のみ非rootユーザーに切り替える
# (gosu、上記参照)。コンテナ自体のデフォルトユーザーはroot のままにする。
# node:20-slim には既にUID 1000の "node" ユーザーが存在するためそれを再利用する。
RUN mkdir -p /workspace && chown -R node:node /workspace

WORKDIR /workspace
