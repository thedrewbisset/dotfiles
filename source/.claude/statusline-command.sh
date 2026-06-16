#!/bin/sh
# Status line mirroring the robbyrussell Oh My Zsh theme
# Input: JSON via stdin from Claude Code

input=$(cat)

# Current directory (basename, like %c in robbyrussell)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // empty')
dir=$(basename "$cwd")

# Git branch from workspace repo or worktree info
branch=""
git_root=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  # Dirty check: any uncommitted changes?
  dirty=""
  if [ -n "$branch" ]; then
    git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null || dirty="1"
    git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null || dirty="1"
  fi
fi

# Build output with ANSI colors (terminal will display dimmed)
# robbyrussell: green arrow, cyan dir, blue "git:(", red branch, blue ")", yellow dirty mark
GREEN=$(printf '\033[1;32m')
CYAN=$(printf '\033[0;36m')
BLUE=$(printf '\033[1;34m')
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[0;33m')
RESET=$(printf '\033[0m')

if [ -n "$branch" ]; then
  if [ -n "$dirty" ]; then
    git_part=" ${BLUE}git:(${RED}${branch}${BLUE}) ${YELLOW}✗${RESET}"
  else
    git_part=" ${BLUE}git:(${RED}${branch}${BLUE})${RESET}"
  fi
else
  git_part=""
fi

# Context usage indicator (only shown after the first API response)
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  # Color the percentage: green < 50%, yellow 50-79%, red >= 80%
  if [ "$used_int" -ge 80 ]; then
    ctx_color="$RED"
  elif [ "$used_int" -ge 50 ]; then
    ctx_color="$YELLOW"
  else
    ctx_color="$GREEN"
  fi
  ctx_part="  ${ctx_color}ctx:${used_int}%${RESET}"
else
  ctx_part=""
fi

printf "${GREEN}➜${RESET}  ${CYAN}%s${RESET}%s%s" "$dir" "$git_part" "$ctx_part"
