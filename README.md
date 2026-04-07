# Dotfiles

Bootstrap and maintain a macOS development environment. Recipes handle installation of dotfiles, tools, and configuration. All recipes are idempotent — safe to run multiple times.

---

## Architecture

### Recipe system

Recipes live in `recipes/<name>/` and follow a consistent directory structure:

```
recipes/
├── dotfiles/
│   ├── install     # symlinks source/ → $HOME
│   └── teardown    # removes those symlinks
├── claude/
│   ├── install     # symlinks source/.claude/ → ~/.claude/
│   ├── teardown    # removes those symlinks
│   └── docker/     # Containerized Claude Code (C3) — see below
├── homebrews/
│   └── install
├── vim-plugins/
│   └── install
└── ...             # all other recipes follow the same pattern
```

The main installer (`bin/install.sh`) and teardown script (`bin/teardown.sh`) source the appropriate recipe file. Recipes that install global system packages (homebrews, rubies, kiex, etc.) do not have teardown scripts — those must be removed manually.

### Dotfiles

`source/` contains the actual dotfiles. The `dotfiles` recipe creates symlinks from `$HOME` to each file in `source/`, making configuration easy to track and remove without touching the source.

Conflict handling is interactive — you'll be prompted to overwrite or skip any file that already exists at the target path.

**Special cases:**
- `.ssh/` — the directory is created with correct permissions (`700`); only `.ssh/config` is symlinked (private keys are never committed)
---

## Installation

```bash
# Install everything
bin/install.sh all

# Install a specific recipe
bin/install.sh dotfiles
bin/install.sh vim-plugins
bin/install.sh homebrews
bin/install.sh rubies
bin/install.sh kiex
bin/install.sh python
bin/install.sh npm
bin/install.sh bats
bin/install.sh zsh
```

### Test against a temp directory

Use `--target` to point symlinks at a directory other than `$HOME`. Useful for verifying provisioning before touching your live environment:

```bash
mkdir /tmp/test-home
bin/install.sh --target /tmp/test-home dotfiles
```

---

## Teardown

Removes symlinks created by a recipe. Only removes symlinks — real files are never touched.

```bash
# Remove all managed symlinks
bin/teardown.sh all

# Remove symlinks for a specific recipe
bin/teardown.sh dotfiles

# Remove installed artifacts for project-local recipes
bin/teardown.sh vim-plugins   # removes cloned plugin dirs from source/.vim/
bin/teardown.sh bats          # removes cloned bats from source/.bats/
bin/teardown.sh python        # removes base-dev and base-ml conda environments
bin/teardown.sh npm           # uninstalls global npm packages

# Teardown into a non-$HOME target (mirrors --target from install)
bin/teardown.sh --target /tmp/test-home dotfiles
```

Recipes that install global packages (homebrews, rubies, etc.) print a message instead of attempting teardown.

---

## SSH key setup

After running the dotfiles recipe, generate SSH keys for each GitHub profile:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github.com-profile1 -C "profile1@example.com"
cat ~/.ssh/github.com-profile1.pub  # add to GitHub account
```

The SSH config is symlinked from `source/.ssh/config`. Private keys are generated locally and never committed.
