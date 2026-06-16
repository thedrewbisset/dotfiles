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
- `.claude/` — managed by the `claude` recipe (see below)

### Claude Code configuration

`source/.claude/` holds source-controlled Claude Code configuration:

```
source/.claude/
├── CLAUDE.md           # Global user instructions
├── settings.json       # Claude Code settings (no secrets)
├── skills/             # Custom slash-command skills
│   ├── patch-bundler/
│   └── patch-bundler-poetry/
└── plugins/            # Plugin registry config
    ├── config.json
    ├── installed_plugins.json
    ├── blocklist.json
    └── known_marketplaces.json
```

`settings.json` intentionally omits `AWS_BEARER_TOKEN_BEDROCK` and any other secrets. Those are stored in the macOS Keychain and resolved at runtime — see [Secrets management](#secrets-management).

The `claude` recipe symlinks these into `~/.claude/`. Live Claude Code state (`history.jsonl`, `projects/`, `local/`, etc.) is never touched.

---

## Installation

```bash
# Install everything
bin/install.sh all

# Install a specific recipe
bin/install.sh dotfiles
bin/install.sh claude
bin/install.sh vim-plugins
bin/install.sh homebrews
bin/install.sh postgresql
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
bin/install.sh --target /tmp/test-home claude
```

---

## Teardown

Removes symlinks created by a recipe. Only removes symlinks — real files are never touched.

```bash
# Remove all managed symlinks
bin/teardown.sh all

# Remove symlinks for a specific recipe
bin/teardown.sh dotfiles
bin/teardown.sh claude

# Remove installed artifacts for project-local recipes
bin/teardown.sh vim-plugins   # removes cloned plugin dirs from source/.vim/
bin/teardown.sh bats          # removes cloned bats from source/.bats/
bin/teardown.sh python        # removes base-dev and base-ml conda environments
bin/teardown.sh npm           # uninstalls global npm packages

# Teardown into a non-$HOME target (mirrors --target from install)
bin/teardown.sh --target /tmp/test-home dotfiles
```

Recipes that install global packages (homebrews, rubies, postgresql, etc.) print a message instead of attempting teardown.

---

## PostgreSQL Setup

The `postgresql` recipe bootstraps a local PostgreSQL 16 instance for development:

```bash
bin/install.sh postgresql
```

**What it does:**
- Ensures PostgreSQL@16 is running via Homebrew services
- Creates `postgres` role with password `mysecretpassword` (standard dev password)
- Offers to clean up old PostgreSQL installations (14, 17)

**Requirements:**
- Must run `bin/install.sh homebrews` first (installs postgresql@16)

**Connection details:**
- Host: `localhost`
- Port: `5432`
- Role: `postgres`
- Password: `mysecretpassword`
- Database: `postgres` (default)

Use `psql -U postgres -d postgres` to connect (will prompt for password).

---

## Disk cleanup

`bin/diskclean` reclaims disk space from the caches and build artifacts that development tools accumulate. It's recipe-based like the installer, but the recipes are `cleanup` scripts that *scan* rather than install.

```bash
# Scan everything, then pick what to delete
bin/diskclean all

# Scan a single category
bin/diskclean library        # ~/Library: iOS device backups + app caches
bin/diskclean simulators     # Xcode DerivedData, iOS DeviceSupport, simulators, Android AVDs
bin/diskclean homebrews      # Homebrew download cache, stale formulae, logs
bin/diskclean docker         # images, stopped containers, build cache, dangling volumes
bin/diskclean npm            # npm/yarn/pnpm caches + project node_modules
bin/diskclean python         # conda/pip/poetry caches, pyenv versions, .venv, __pycache__
bin/diskclean rubies         # rbenv versions, gem/bundler caches, project .bundle
bin/diskclean build          # .build, Rust target/, Gradle, Maven, .next/.nuxt, dist/, _build
bin/diskclean cocoapods      # CocoaPods spec repos, cache, project Pods/
```

**How it works:** each recipe registers candidate artifacts (with size and last-modified date), then everything is shown in an `fzf` multi-select. You pick items, review a confirmation manifest, and only then are they deleted. Nothing is removed without explicit confirmation, and tool-native reclaim (`brew cleanup`, `docker rmi`, `pod cache clean`, etc.) is preferred over raw `rm` where available.

**Notes:**
- Requires [`fzf`](https://github.com/junegunn/fzf) for the interactive picker (`bin/install.sh homebrews` installs it).
- Recipes that scan for project artifacts (`npm`, `python`, `rubies`, `build`, `cocoapods`, and `all`) prompt for a base directory to scan, defaulting to `~/dev`. Large project trees can take a few minutes to size.
- `library`, `simulators`, `homebrews`, and `docker` target `~/Library` and system caches — they don't walk your project tree, so they return quickly.
- `iOS DeviceSupport` keeps the current (latest) version and only offers older ones; `library` flags iOS device backups as **DATA** since deleting one loses that backup.
- Docker space is reclaimed via the daemon, but macOS doesn't auto-shrink the `Docker.raw` disk image — reclaim that via Docker Desktop → Settings → Resources → Disk.

---

## Claude Code backup and restore

Two scripts manage snapshots of `~/.claude/`:

```bash
# Create a snapshot (excludes large/ephemeral dirs: local/, debug/, projects/)
bin/claude-backup

# Create a full snapshot (includes history.jsonl, projects/)
bin/claude-backup --full

# Write snapshot to a custom directory
bin/claude-backup --dir /path/to/backups

# Restore most recent snapshot
bin/claude-restore

# Restore a specific snapshot
bin/claude-restore claude-20260101-120000

# Preview what would be restored without extracting
bin/claude-restore --dry-run
```

Snapshots are written to `~/.claude-snapshots/` by default. Override with the `CLAUDE_SNAPSHOTS_DIR` environment variable.

Shell aliases (available after installing dotfiles):
- `cb` → `claude-backup`
- `cr` → `claude-restore`

---

## Containerized Claude Code (C3)

Run Claude Code in an ephemeral Docker container against an isolated git worktree. Useful for sandboxed sessions that don't touch your working tree.

Infrastructure lives in `recipes/claude/docker/`:

```
recipes/claude/docker/
├── base/Dockerfile     # Ubuntu 24.04 + Node LTS + Claude Code CLI
├── python/Dockerfile   # Extends base + Python 3.12 + Poetry
├── node/Dockerfile     # Extends base + Yarn
├── docker-compose.yml  # Service definitions
└── .env.example        # Template for local secrets (never committed)
```

### Quick start

```bash
bin/claude-worktree <repo-path> [platform] [branch-name]
```

```bash
# Start a base session against a repo
bin/claude-worktree ~/dev/projects/my-app

# Start a Python session with a specific branch name
bin/claude-worktree ~/dev/projects/my-app python fix/dependency-updates
```

The script:
1. Creates a git worktree at `<repo>/.worktrees/<branch>`
2. Launches the container with the worktree mounted at `/workspace`
3. Mounts `~/.claude/` config read-only into the container
4. Passes `AWS_BEARER_TOKEN_BEDROCK` from your host environment (never baked into the image)
5. On exit, prompts whether to remove the worktree

### Authentication

The bearer token is passed into the container at runtime via environment variable — never stored in the image or committed. Source it from the Keychain (see [Secrets management](#secrets-management)) so it's never typed in plaintext:

```bash
export AWS_BEARER_TOKEN_BEDROCK="$(security find-generic-password -s claude-bedrock-token -w)"
bin/claude-worktree ~/dev/projects/my-app
```

### Building images manually

```bash
docker build -t claude-base -f recipes/claude/docker/base/Dockerfile .
docker build -t claude-python -f recipes/claude/docker/python/Dockerfile .
docker build -t claude-node -f recipes/claude/docker/node/Dockerfile .
```

---

## Secrets management

Secrets are **never** stored in plaintext in committed files or shell history. They live encrypted at rest in the macOS Keychain and are resolved at runtime via command substitution — committed files contain only the *lookup*, never the value.

### Pattern

**Store** a secret. Always use `pbpaste` for long values — the interactive `-w` prompt silently truncates long pastes (see gotcha below). `tr -d '[:space:]'` strips any stray whitespace the clipboard carried (safe, since base64 keys contain none):

```bash
security add-generic-password -a "$USER" -s <service-name> -U -w "$(pbpaste | tr -d '[:space:]')"
```

**Verify** without printing the secret:

```bash
security find-generic-password -s <service-name> -w >/dev/null && echo "stored OK"
printf '%s' "$(security find-generic-password -s <service-name> -w)" | wc -c   # confirm expected length
```

**Reference** it where needed — committed files hold only this lookup:

```bash
export SOME_TOKEN="$(security find-generic-password -s <service-name> -w)"
```

**Rotate** by revoking the old credential at its source, then re-running the store command.

### Worked example: AWS Bedrock API key

`claude-chartpro()` (`source/.zshrc`) loads the Bedrock API key from Keychain only when invoked, so personal Claude sessions never carry it:

```bash
export AWS_BEARER_TOKEN_BEDROCK="$(security find-generic-password -s claude-bedrock-token -w)"
```

Store the key under service name `claude-bedrock-token` using the `pbpaste` method above.

### Gotcha: the `-w` prompt truncates long pastes

`security add-generic-password … -w` (with `-w` last) prompts for hidden input, but the terminal can **silently drop characters** from a long paste. A truncated Bedrock key (128 chars instead of the expected ~132) is accepted into Keychain yet rejected by AWS as invalid — a confusing failure. Always store long secrets via `pbpaste`, then verify the length.

---

## SSH key setup

After running the dotfiles recipe, generate SSH keys for each GitHub profile:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github.com-profile1 -C "profile1@example.com"
cat ~/.ssh/github.com-profile1.pub  # add to GitHub account
```

The SSH config is symlinked from `source/.ssh/config`. Private keys are generated locally and never committed.
