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
│   └── install     # installs the Claude Code CLI (agent config lives elsewhere)
├── homebrews/
│   └── install
├── vim-plugins/
│   └── install
├── tmux/
│   ├── install     # clones tpm and installs the plugins .tmux.conf declares
│   └── teardown    # removes cloned plugins (saved sessions are kept)
└── ...             # all other recipes follow the same pattern
```

The main installer (`bin/install.sh`) and teardown script (`bin/teardown.sh`) source the appropriate recipe file. Recipes that install global system packages (homebrews, rubies, kiex, etc.) do not have teardown scripts — those must be removed manually.

### Dotfiles

`source/` contains the actual dotfiles. The `dotfiles` recipe creates symlinks from `$HOME` to each file in `source/`, making configuration easy to track and remove without touching the source.

Conflict handling is interactive — you'll be prompted to overwrite or skip any file that already exists at the target path.

**Special cases:**
- `.ssh/` — the directory is created with correct permissions (`700`); only `.ssh/config` is symlinked (private keys are never committed)
- `.claude/` — skipped entirely; agent configuration is managed outside this repo (see below)

### Claude Code configuration

**This repo no longer manages `~/.claude`.** Agent configuration — instructions, rules,
skills and settings — lives in its own version-controlled repository with its own
installer, which symlinks it into `~/.claude/`.

`recipes/claude` installs the Claude Code CLI and nothing else. It still refuses to run
if `~/.claude/` is a symlink rather than a real directory: that directory is Claude
Code's live home and holds runtime state (sessions, history, caches, hydrated plugins)
that must never enter a repository. `recipes/dotfiles` skips `.claude/` for the same
reason — symlinking the whole directory would replace that state.

Two launchers in `.zshrc` start Claude Code as one identity or the other:

- `claude-lge` (personal, and what plain `claude` is aliased to) adds
  `--settings ~/.claude/settings.identity.json`, which sandboxes the session away from
  paths that identity must never touch. The file comes from the configuration repository;
  without it the launcher refuses to start.
- `claude-chartpro` (work, AWS Bedrock) runs without those limits.

Both call `command claude`, so the alias never recurses. The IDE extension, desktop app and
`command claude` itself bypass the launchers.

### tmux session persistence

`source/.tmux.conf` declares its plugins with tpm (`set -g @plugin`), and `recipes/tmux`
is the non-interactive half: it clones tpm if absent and runs tpm's own
`bin/install_plugins`, so a fresh machine comes up with the plugins already present
rather than waiting for someone to press `prefix + I`. tpm parses the `@plugin` lines
straight out of `~/.tmux.conf`, so **this recipe must run after `dotfiles`** — that is
the symlink it reads. tmux itself does not need to be running.

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) saves the session tree —
windows, panes, layouts, working directories, and pane contents — to disk, and restores it
into a server that has lost it. Saves land in `~/.local/share/tmux/resurrect/` (XDG data),
pinned with `@resurrect-dir` so the location does not depend on machine history.
[tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) is the timer that drives
the save. Two decisions to know before changing either:

- **Saving is both periodic and detach-driven.** continuum saves every 15 minutes, which
  bounds what a crash or reboot *while attached* can cost. A `client-detached` hook saves
  on top of that, because detaching is the one moment the state is known-final; tmux fires
  that hook on an abrupt client death (closed terminal, dropped ssh) exactly as it does on
  a polite detach. The hook is guarded on the script existing, so a machine that has not
  run this recipe yet still loads the config cleanly.
- **Restore is manual: `prefix + Ctrl-r`.** `@continuum-restore` is explicitly `off`.
  It would rebuild every saved session the moment a server starts, which races a
  `tmuxinator start` for the same session name and leaves duplicates behind.

`prefix` is `C-a` here, so the full bindings are `C-a Ctrl-s` to save now and
`C-a Ctrl-r` to restore. `bin/teardown.sh tmux` removes the cloned plugins and leaves saved state
alone — that is data, not an installed artifact, and it lives outside the plugin
directory anyway.

The bindings, the recovery runbook, and the fix for a server that has lost its socket
are in [`docs/tmux.md`](docs/tmux.md). One thing it covers that bites in practice: a
server that was already running when the plugins were installed does not have them
until the config is reloaded (`prefix + r`).

---

## Installation

```bash
# Install everything
bin/install.sh all

# Install a specific recipe
bin/install.sh dotfiles
bin/install.sh claude
bin/install.sh vim-plugins
bin/install.sh tmux
bin/install.sh homebrews
bin/install.sh postgresql
bin/install.sh rubies
bin/install.sh kiex
bin/install.sh uv
bin/install.sh python
bin/install.sh nvm
bin/install.sh bats
bin/install.sh zsh

# Opt-in recipes (deliberately excluded from `all`)
bin/install.sh paperclip
bin/install.sh ml
```

### Python

uv manages every Python we run. `bin/install.sh uv` installs uv (Homebrew also lists it, so either recipe can come first) and a uv-managed Python 3.14. Homebrew's own `python@3.14` stays only because other formulae depend on it.

- **Global tools** — `bin/install.sh python` installs only tools that never import project code, currently just `ruff`. Each uv tool runs in its own environment and cannot see a project's packages or Python, so `pytest`, `ipython` and the like are per-project dev dependencies (`uv add --dev`).
- **Poetry** — installed as a uv tool on Python 3.12, the version its projects pin. Poetry builds sdists and seeds new venvs with its *own* interpreter, so a Poetry on another Python silently produces a venv or C extensions for the wrong version (`poetry env use` is affected too). To (re)build a Poetry project's in-project venv, create it with uv first, then let Poetry fill it:

  ```bash
  uv venv --python 3.12 --managed-python --seed .venv && poetry install
  ```
- **ML environment** — `bin/install.sh ml` is opt-in. It syncs `recipes/ml/pyproject.toml` into `~/.venvs/ml`. `uv.lock` is gitignored, so versions float until one is pinned in `pyproject.toml`. Add packages with `uv add --project recipes/ml <package>`.

### Paperclip

[Paperclip](https://github.com/paperclipai/paperclip) is a self-hosted control plane for AI agents. The recipe provisions the CLI and links curated config; it never runs onboarding for you.

- **Provisioning** — checks for Node.js >= 20 (run `bin/install.sh nvm` first if missing), then prompts before running `npx --yes paperclipai@$PAPERCLIP_VERSION install --version $PAPERCLIP_VERSION`. CLI payloads land in `~/.paperclip/cli/`, with a stable shim at `~/.local/bin/paperclipai` (already on `PATH` via `.zshrc`). Upgrades are the CLI's job: `paperclipai update`, or `paperclipai update --rollback`.

- **Version pin** — `PAPERCLIP_VERSION` at the top of the recipe pins a *canary* build. The managed CLI store, the background service and `update --rollback` don't exist in the stable tag yet: `@latest` is 2026.722.0 and has no `install`, `service`, `update` or `uninstall` commands, even though Paperclip's own website installer and docs are written against them. Canary publishes several times a day, so the pin is what keeps two machines reproducible. Drop it for `@latest` once these commands reach stable:

  ```bash
  npx --yes paperclipai@latest --help | grep -E '^\s+(install|service)\b'
  ```

  The recipe also skips Paperclip's documented bootstrap (`https://paperclip.ing/install.sh`). That script verifies the platform, ensures Node.js >= 20, then makes exactly the `npx` call above — but it uses bash 4 lowercase expansion (`${value,,}`) and macOS is frozen on bash 3.2 for GPLv3 licensing reasons, so it aborts before doing any work. It would fail on Linux too, since it resolves the package at `@latest`, where the `install` command it invokes doesn't exist yet.
- **Configuration** — `~/.paperclip` is Paperclip's live home: embedded Postgres, uploads, logs, secrets and agent workspaces all live under `instances/`. Like `~/.claude`, it stays a real directory and the recipe refuses to run if it has been replaced by a symlink. Only curated, secret-free files from `source/.paperclip/` are symlinked in, and `.gitignore` denies that directory by default so a stray API key can't be committed by accident.
- **Service** — probes `paperclipai --help` for a `service` command before offering anything, then prompts before installing the macOS LaunchAgent (`paperclipai service install`), which serves the dashboard on `http://localhost:3100` and starts on login. On a build without it, the recipe says so and points at `paperclipai run` instead of erroring mid-run.

- **Service PATH patch** — launchd hands a LaunchAgent a bare `PATH` of `/usr/bin:/bin:/usr/sbin:/sbin`, and Paperclip's generated plist adds none. Agent adapters spawn helpers like `claude-agent-acp` whose shebang is `#!/usr/bin/env node`, so with node anywhere else (e.g. `/usr/local/bin/node`) every agent run fails with `env: node: No such file or directory` — while the service itself stays healthy, since launchd starts it by absolute path. The recipe patches `PATH` into the plist's `EnvironmentVariables` and reloads. Two traps it works around:

  - `paperclipai service restart` **regenerates the plist** and silently drops the patch. Re-run `bin/install.sh paperclip` to repair; the patch is idempotent and only reloads when it detects drift.
  - launchd re-reads `EnvironmentVariables` only on a full `launchctl bootout` + `bootstrap`. A hot restart keeps the old environment and makes the patch look like it failed.
- **Onboarding** — run `paperclipai onboard` yourself. It is interactive and writes secrets, so it is not automated here.

- **Backup & restore** — see [`recipes/paperclip/BACKUP-RESTORE.md`](recipes/paperclip/BACKUP-RESTORE.md). Paperclip backs up hourly but ships **no restore command**, and its docs cover neither restore nor machine migration, so that file is a playbook rather than a script. The one thing to know without reading it: `secrets/master.key` decrypts every secret in the database, and a dump without it is unrestorable.

- **Org export** — `recipes/paperclip/export-company` materializes the company as a portable file tree (`COMPANY.md`, per-agent `AGENTS/HEARTBEAT/SOUL/TOOLS.md`, `SKILL.md` files) into `recipes/paperclip/company/<slug>/`, via Paperclip's own `company export:preview`. Gitignored by default: it carries no API keys, but it is every agent prompt you have written. `paperclipai company import:apply` reverses it.

**Nothing is versioned in `source/.paperclip/`, by design.** That stub was built on the assumption that a curated slice of `~/.paperclip` would be worth tracking; inspecting a live instance showed otherwise. `config.json` embeds absolute `/Users/...` paths and is rewritten by `paperclipai configure`; `.env` holds `PAPERCLIP_AGENT_JWT_SECRET`; and `companies/`, `skills/` and `projects/` are UUID-keyed materializations of database rows, meaningless on an instance with different UUIDs. The portable state is the org export above; the recoverable state is the database. The symlink mechanism stays in the recipe in case a future version grows a genuinely portable config file — if it does, drop the file into `source/.paperclip/`, allowlist it in `.gitignore`, and re-run `bin/install.sh paperclip`.

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
bin/teardown.sh tmux          # removes cloned tmux plugins; keeps saved sessions
bin/teardown.sh bats          # removes cloned bats from source/.bats/
bin/teardown.sh python        # removes uv's global tools and its managed Python 3.14
bin/teardown.sh ml            # removes ~/.venvs/ml
bin/teardown.sh nvm           # removes nvm and all installed Node.js versions
bin/teardown.sh paperclip     # unlinks config; leaves the CLI, service and instance data

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
bin/diskclean python         # pip/poetry caches, pyenv versions, .venv, __pycache__
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
- Docker space is reclaimed via the daemon, but macOS doesn't auto-shrink the `Docker.raw` disk image — reclaim that via Docker Desktop → Settings → Resources → Disk. Under Colima, run `colima ssh -- sudo fstrim -av` instead.

### Finding where space goes

`diskclean` only finds what its recipes know about. `bin/diskmap` is the read-only complement: it accounts for *all* of it.

```bash
bin/diskmap                              # the data volume (also what `bin/diskmap /` maps)
bin/diskmap ~/Library                    # any path
bin/diskmap ~ --usage-above-pcent 5      # coarser: only entries using at least 5% of the path
```

It prints a heat-map tree of the path. An entry is shown, and expanded further, only if it uses at least the given percentage of the path (default 1); everything smaller rolls up into one line per level, so every level sums to its parent. Directories whose usage is essentially one child fold into a single row, and single files over the threshold are named, so the tree ends where the space actually is.

It never deletes, and it takes one `du` pass (a couple of minutes for the whole volume).

Entries `du` cannot read are marked ⚠ with a count. Their usage is invisible to `du`, so for an arbitrary path it is excluded from every figure and cannot be bounded. Only the volume root has an independent total (APFS's in-use figure), so only there does the tree end in an `undiscoverable` row: in use minus everything measured. Full Disk Access for your terminal (System Settings → Privacy & Security) or a `sudo` run shrinks it.

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

## Privacy gate

This repository is public, so a check runs before anything leaves the machine.

```
scripts/install-hooks.sh                    # once per clone
mkdir -p ~/.config/exponential
cp scripts/denylist.local.txt.example ~/.config/exponential/denylist.txt   # then edit
```

Findings come in two tiers, split by *why* something is sensitive:

**Block — secret by format.** AWS keys, GitHub and Slack tokens, private key blocks,
JWTs, credentials in URLs, absolute home paths. These have an unambiguous shape, so
they block, and **nothing switches them off** — a credential inside a vendored
dependency is a live credential regardless of who committed it.

**Warn — sensitive by identity.** Email addresses, `owner/repo` references, internal
hostnames. No shape distinguishes yours from a third party's copyright header, so
matching them precisely is impossible and matching them loosely misfires constantly.
They warn, and `scripts/allowlist.txt` silences what is already known to be somebody
else's. Warnings are aggregated: duplicates collapse with a count, a dominating path
is reported once as a path to allowlist, and the listing is capped.

| | Committed? | Effect |
|---|---|---|
| `${XDG_CONFIG_HOME:-~/.config}/exponential/denylist.txt` | **no** — outside the repo, shared by every clone and worktree; `scripts/denylist.local.txt` (gitignored) is the fallback | **blocks**; your other handles, clients, employers |
| `scripts/allowlist.txt` | **yes** | silences identity **warnings**; third-party links, vendored paths |

Two hooks: `pre-commit` checks the working tree; `pre-push` runs the full check
including the deny-list over the commits actually being pushed. Git cannot make a hook
mandatory, so the point is putting the real gate at the boundary that matters —
`--no-verify` on a commit is typed by habit, on a push it is not.

The check covers the change being made, not existing history: a check that cannot be
satisfied is one people learn to bypass.

## Git identities

`.gitconfig` includes one local routing file, `~/.gitconfig-identities`, which selects an
identity per directory:

```
[include]
  path = ~/.gitconfig-personal              # default
[includeIf "gitdir:~/dev/projects/<group>/"]
  path = ~/.gitconfig-<group>               # overrides it under that tree
```

Each identity holds a real name, address and SSH key path, and the routing names them all,
so **every one of these files is gitignored** — this repo is public. Two templates are
committed: one for the routing, and one for any identity, however many there are:

```
cp source/.gitconfig-identities.example source/.gitconfig-identities
cp source/.gitconfig-identity.example source/.gitconfig-personal    # once per identity
$EDITOR source/.gitconfig-identities source/.gitconfig-personal
bin/install.sh dotfiles
```

Adding an identity later is local only: copy the identity template, and add an
`includeIf` for it to `.gitconfig-identities`.

**These files are required, not optional.** If a target is missing, git ignores the
include *silently* — no warning, and nothing in `git config` output to show it. Commits
fall back to the default identity, and pushes may authenticate as the wrong account,
because `core.sshCommand` lives in the same file. The first symptom is usually a
misattributed commit or a `Repository not found` error pointing at the remote rather
than at local config.

`recipes/dotfiles/install` checks every include target after linking `.gitconfig`, in
both `.gitconfig` and the routing file, and warns loudly about any that are missing. It does not create them from the templates on
purpose: a working identity reading `<github-username>` is worse than no identity.

Verify at any point with:

```
git -C <some-repo> config user.email
```

## SSH key setup

After running the dotfiles recipe, generate SSH keys for each GitHub profile:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github.com-profile1 -C "profile1@example.com"
cat ~/.ssh/github.com-profile1.pub  # add to GitHub account
```

The SSH config is symlinked from `source/.ssh/config`. Private keys are generated locally and never committed.
