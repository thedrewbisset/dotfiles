# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dotfiles repository designed to bootstrap a macOS development environment. It uses a recipe-based system to install and configure various tools including dotfiles, vim plugins, homebrew packages, and language runtime managers.

## Architecture

The project is organized around **recipes** - bash scripts that handle specific setup tasks:

- **Main installer**: `bin/install.sh` - orchestrates recipe execution
- **Recipe system**: Individual scripts in `recipes/` directory handle specific components
- **Dotfiles source**: `source/` contains actual dotfiles that get symlinked to `$HOME`
- **Utility functions**: `bin/lib/tools` provides common functions like `set_link` for symlinking

### Key Components

- **Dotfiles recipe** (`recipes/dotfiles`): Creates symlinks from `source/` to `$HOME`, with conflict resolution
- **Vim plugins recipe** (`recipes/vim-plugins`): Manages vim 8 plugins using git repositories in `source/.vim/pack/core/`
- **Homebrew recipe** (`recipes/homebrews`): Installs development tools via homebrew
- **Language runtimes**: Separate recipes for Ruby (rbenv), Elixir (kiex), Python (miniconda)

## Common Commands

```bash
# Install all components
bin/install.sh all

# Install specific components
bin/install.sh dotfiles
bin/install.sh vim-plugins
bin/install.sh homebrews
bin/install.sh rubies
bin/install.sh kiex
bin/install.sh zsh
```

## Development Notes

- The installer uses interactive prompts for conflicting files (overwrite/skip)
- Vim plugins are cloned/updated from GitHub using SSH URLs
- All recipes are designed to be idempotent (safe to run multiple times)
- The project targets macOS and assumes bash shell environment

## SSH Key Setup

After running the dotfiles recipe, generate SSH keys for GitHub access:

```bash
# Generate SSH key for GitHub profile
ssh-keygen -t ed25519 -f ~/.ssh/github.com-profile1 -C "profile1@example.com"

# Add public key to GitHub account
cat ~/.ssh/github.com-profile1.pub
```

The SSH config will be symlinked from `source/.ssh/config` but private keys are generated locally and never committed.