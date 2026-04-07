FROM claude-base:latest

USER root

RUN apt-get update && apt-get install -y \
  python3.12 \
  python3.12-venv \
  python3-pip \
  && rm -rf /var/lib/apt/lists/*

# Poetry
RUN curl -sSL https://install.python-poetry.org | python3 -

ENV PATH="/root/.local/bin:$PATH"

USER dev

ENV PATH="/home/dev/.local/bin:$PATH"

CMD ["zsh"]
