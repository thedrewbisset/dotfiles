#!/usr/bin/env bash
set -e

# Make sure bin/install is being run from project root
# if [[ ! "$PWD/bin/install" -ef "$0" ]]; then
#   echo "Please run 'bin/install' from dotfiles root"
#   exit 1
# fi

if [[ "$1" == "all" ]]; then
  source "$PWD/recipes/oh-my-zsh"
  source "$PWD/recipes/dotfiles"
  source "$PWD/recipes/vim-plugins"
  source "$PWD/recipes/homebrews"
  source "$PWD/recipes/rubies"
else
  case "$1" in
    zsh)
      source "$PWD/recipes/oh-my-zsh"
      ;;
    dotfiles)
      source "$PWD/recipes/dotfiles"
      ;;
    vim-plugins)
      source "$PWD/recipes/vim-plugins"
      ;;
    homebrews)
      source "$PWD/recipes/homebrews"
      ;;
    rubies)
      source "$PWD/recipes/rubies"
      ;;
  esac
fi
