#!/usr/bin/env bash
set -e

# Make sure bin/install is being run from project root
# if [[ ! "$PWD/bin/install" -ef "$0" ]]; then
#   echo "Please run 'bin/install' from dotfiles root"
#   exit 1
# fi

# Parse --target option before the recipe argument
export TARGET_HOME="$HOME"
RECIPE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET_HOME="$2"
      shift 2
      ;;
    --help|-h|help)
      echo "Usage: bin/install.sh [--target <dir>] <recipe|all>"
      echo ""
      echo "Recipes:"
      echo "  all         Run all recipes in order"
      echo "  zsh         Install oh-my-zsh"
      echo "  dotfiles    Symlink dotfiles to \$HOME"
      echo "  claude      Symlink Claude Code config"
      echo "  vim-plugins Install vim 8 plugins"
      echo "  homebrews   Install Homebrew packages"
      echo "  postgresql  Install PostgreSQL"
      echo "  kiex        Install Elixir version manager"
      echo "  rubies      Install Ruby via rbenv"
      echo "  python      Install Python via miniconda"
      echo "  nvm         Install Node.js via nvm"
      echo "  bats        Install bats test framework"
      echo ""
      echo "Options:"
      echo "  --target <dir>  Install to an alternate home directory"
      exit 0
      ;;
    *)
      RECIPE="$1"
      shift
      ;;
  esac
done

if [[ -n "$TARGET_HOME" && "$TARGET_HOME" != "$HOME" ]]; then
  echo "Installing to target: $TARGET_HOME"
  mkdir -p "$TARGET_HOME"
fi

if [[ "$RECIPE" == "all" ]]; then
  source "$PWD/recipes/oh-my-zsh/install"
  source "$PWD/recipes/dotfiles/install"
  source "$PWD/recipes/claude/install"
  source "$PWD/recipes/vim-plugins/install"
  source "$PWD/recipes/homebrews/install"
  source "$PWD/recipes/postgresql/install"
  source "$PWD/recipes/kiex/install"
  source "$PWD/recipes/rubies/install"
  source "$PWD/recipes/python/install"
  source "$PWD/recipes/nvm/install"
  source "$PWD/recipes/bats/install"
else
  case "$RECIPE" in
    zsh)
      source "$PWD/recipes/oh-my-zsh/install"
      ;;
    dotfiles)
      source "$PWD/recipes/dotfiles/install"
      ;;
    claude)
      source "$PWD/recipes/claude/install"
      ;;
    vim-plugins)
      source "$PWD/recipes/vim-plugins/install"
      ;;
    homebrews)
      source "$PWD/recipes/homebrews/install"
      ;;
    postgresql)
      source "$PWD/recipes/postgresql/install"
      ;;
    kiex)
      source "$PWD/recipes/kiex/install"
      ;;
    rubies)
      source "$PWD/recipes/rubies/install"
      ;;
    python)
      source "$PWD/recipes/python/install"
      ;;
    nvm)
      source "$PWD/recipes/nvm/install"
      ;;
    bats)
      source "$PWD/recipes/bats/install"
      ;;
    "")
      echo "Usage: bin/install.sh [--target <dir>] <recipe|all>"
      exit 1
      ;;
    *)
      echo "Unknown recipe: $RECIPE"
      exit 1
      ;;
  esac
fi
