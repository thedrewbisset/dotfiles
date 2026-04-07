FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Core utilities
RUN apt-get update && apt-get install -y \
  curl \
  wget \
  git \
  jq \
  zsh \
  sudo \
  ca-certificates \
  gnupg \
  ripgrep \
  && rm -rf /var/lib/apt/lists/*

# Node.js LTS via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
  && apt-get install -y nodejs \
  && rm -rf /var/lib/apt/lists/*

# Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Non-root user with sudo
RUN useradd -m -s /bin/zsh dev \
  && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER dev
WORKDIR /workspace

CMD ["zsh"]
