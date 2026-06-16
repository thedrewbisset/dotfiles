#!/usr/bin/env bash
set -e

# Parse --target option before the recipe argument
export TARGET_HOME="$HOME"
RECIPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_HOME="$2"
      shift 2
      ;;
    *)
      RECIPE="$1"
      shift
      ;;
  esac
done

if [[ "$RECIPE" == "all" ]]; then
  source "$PWD/recipes/dotfiles/teardown"
  source "$PWD/recipes/claude/teardown"
  source "$PWD/recipes/vim-plugins/teardown"
  source "$PWD/recipes/bats/teardown"
  source "$PWD/recipes/python/teardown"
  source "$PWD/recipes/nvm/teardown"
  for recipe in oh-my-zsh homebrews kiex rubies miniconda nix; do
    echo "No teardown available for recipe: $recipe (remove manually)"
  done
else
  case "$RECIPE" in
    dotfiles)
      source "$PWD/recipes/dotfiles/teardown"
      ;;
    claude)
      source "$PWD/recipes/claude/teardown"
      ;;
    vim-plugins)
      source "$PWD/recipes/vim-plugins/teardown"
      ;;
    bats)
      source "$PWD/recipes/bats/teardown"
      ;;
    python)
      source "$PWD/recipes/python/teardown"
      ;;
    nvm)
      source "$PWD/recipes/nvm/teardown"
      ;;
    oh-my-zsh|homebrews|kiex|rubies|miniconda|nix|zsh)
      echo "No teardown available for recipe: $RECIPE (remove manually)"
      ;;
    "")
      echo "Usage: bin/teardown.sh [--target <dir>] <recipe|all>"
      exit 1
      ;;
    *)
      echo "Unknown recipe: $RECIPE"
      exit 1
      ;;
  esac
fi
