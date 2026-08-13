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
    && rm -rf /var/lib/apt/lists/*

# glab CLI (GitLab公式CLI)。バージョンは導入時に固定/更新すること。
ARG GLAB_VERSION=1.51.0
RUN curl -sSL "https://gitlab.com/gitlab-org/cli/-/releases/v${GLAB_VERSION}/downloads/glab_${GLAB_VERSION}_linux_amd64.tar.gz" \
    -o /tmp/glab.tar.gz \
    && tar -xzf /tmp/glab.tar.gz -C /tmp \
    && mv /tmp/bin/glab /usr/local/bin/glab \
    && rm -rf /tmp/glab.tar.gz /tmp/bin

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# このループの仕組み一式(スクリプト・プロンプト・MCPテンプレート)を焼き込む
COPY ci/ /opt/ai-loop/ci/
COPY prompts/ /opt/ai-loop/prompts/
COPY mcp/ /opt/ai-loop/mcp/
RUN chmod +x /opt/ai-loop/ci/*.sh /opt/ai-loop/ci/lib/*.sh

ENV PATH="/opt/ai-loop/ci:${PATH}"

# claude CLIは --permission-mode bypassPermissions (非対話CI実行に必須) を
# root/sudo権限では拒否するため、非rootユーザーで実行する。
# node:20-slim には既にUID 1000の "node" ユーザーが存在するためそれを再利用する。
RUN mkdir -p /workspace && chown -R node:node /workspace

USER node
WORKDIR /workspace
