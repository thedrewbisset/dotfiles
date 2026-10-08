#!/usr/bin/env bash
#
# Point this repository's git hooks at the tracked hooks/ directory.
#
#     scripts/install-hooks.sh
#
# Uses core.hooksPath rather than copying into .git/hooks, so the hooks stay
# version-controlled and editing one takes effect without reinstalling.
#
# Exits non-zero on failure, unlike the dotfiles recipes: a machine that silently
# has no privacy gate is the situation this exists to prevent.

set -eu

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [ ! -d hooks ]; then
  printf 'install-hooks: no hooks/ directory at %s\n' "$repo_root" >&2
  exit 1
fi

git config core.hooksPath hooks
chmod +x hooks/* 2>/dev/null || true

printf 'install-hooks: core.hooksPath -> hooks/\n'
printf 'install-hooks: active hooks: %s\n' "$(ls hooks | tr '\n' ' ')"

if [ ! -f scripts/denylist.local.txt ]; then
  printf '\ninstall-hooks: WARNING: no scripts/denylist.local.txt.\n'
  printf 'install-hooks: pre-push will refuse until you create one:\n'
  printf 'install-hooks:   cp scripts/denylist.local.txt.example scripts/denylist.local.txt\n'
fi
