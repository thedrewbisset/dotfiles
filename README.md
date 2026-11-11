# Dotfiles

Bootstrap and maintain a macOS development environment, with a smaller [Windows](#windows) counterpart. Recipes handle installation of dotfiles, tools, and configuration. All recipes are idempotent — safe to run multiple times.

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

## Windows

Windows recipes are PowerShell files beside the bash ones — `recipes/<name>/install.ps1` and `teardown.ps1` — run by `bin/install.ps1` and `bin/teardown.ps1` with the same `<recipe|all>` interface. Neither installer reads the other platform's files. The Windows side is deliberately small: a recipe is added when it is needed there, not for parity.

They target Windows PowerShell 5.1, which ships with Windows, and install through `winget`, so a fresh machine needs nothing first. Re-running a winget recipe upgrades the package.

| Recipe | In `all` | What it does |
|---|---|---|
| `git` | yes | Git for Windows. Installed with `core.autocrlf=false` and Windows' own OpenSSH, both in Git's system config so `~/.gitconfig` stays shared with macOS |
| `dotfiles` | yes | Links the three files Windows reads (`.gitconfig`, `.git-excludes-file`, `.ssh/config`) plus `source/windows/profile.ps1`, and sets `DEV_ROOT`. Needs symlink privilege: run it over SSH or elevated |
| `gh` | yes | GitHub CLI, config pinned to `~\.config\gh`; offers to log in |
| `uv` | yes | uv and a uv-managed Python 3.14, which provides the `python3` the git hooks call |
| `fnm` | yes | [fnm](https://github.com/Schniz/fnm) and Node 24, with the versions and npm's cache on the Dev Drive ([below](#node)) |
| `hooks` | yes | The privacy gate hooks. Fails if `python3` does not actually run |
| `claude` | yes | Claude Code CLI via Anthropic's native installer |
| `devdrive` | no | A [Dev Drive](https://learn.microsoft.com/windows/dev-drive/) at `D:` (expandable virtual disk, 64 GB cap) with `src`, `caches`, `models`, re-attached at boot. Run elevated, normally first |
| `openssh-server` | no | LAN-only, key-only SSH server ([below](#ssh-server)). Run elevated |
| `ollama` | no | Ollama, weights pinned to `D:\models\ollama`, plus four models an 8 GB-class GPU keeps resident and one derived for agent work ([below](#llm-cluster)). Downloads ~17.1 GB, so it is never part of `all` |
| `opencode` | no | The OpenCode CLI, a second agentic harness for the local models ([below](#driving-a-local-model)) |
| `pi` | no | [Pi](https://pi.dev) and its ollama provider — the leanest prompt of the three harnesses, which is what matters on a local model ([below](#driving-a-local-model)). Needs `fnm` |

Every recipe has a teardown. `git`, `gh` and `uv` uninstall the package they installed; `claude` removes the CLI binary and leaves `~\.claude` alone; `hooks` puts this clone's `core.hooksPath` back; `dotfiles` removes only links that point inside this repo, restoring any `.pre-dotfiles` copy it made; `devdrive`'s detaches the drive and deletes it only on a typed confirmation; `openssh-server`'s undoes its configuration; `ollama`'s uninstalls the runtime and clears its variables, then asks *separately* about deleting the weights, since those are the one part a re-install does not bring back in seconds, and `fnm`'s, `opencode`'s and `pi`'s ask the same way about the Node versions, the sessions and the cache. `pi`'s also removes only its own `ollama` key from a `models.json` that may hold other providers. `bin\teardown.ps1 all` does nothing yet, on purpose: each one is run deliberately.

### Node

The macOS side uses `nvm`, which cannot be ported: nvm-sh is not a program but a few thousand lines of POSIX shell sourced into bash or zsh, so the thing itself is the shell. Windows uses **fnm** instead — a single Rust binary that runs on both platforms, reads the same `.nvmrc` and `.node-version` files, and is in winget. macOS could move onto it later for free.

Not `nvm-windows`, despite the name: it is an unrelated program with its own CLI, and it switches versions by replacing a *symlink*, which needs `SeCreateSymbolicLinkPrivilege` — Administrators only. fnm uses directory **junctions**, which need no privilege at all, so it installs and switches from an ordinary shell. (Volta is the other serious option; it shims rather than hooking the shell, which is tidier, but it pins versions in `package.json` instead of reading `.nvmrc`, so it would not share version files with macOS.)

Everything that gets written a lot goes on the Dev Drive, which is the workload Dev Drives exist for — `node_modules` is hundreds of thousands of small files on ReFS with Defender in performance mode:

| | |
|---|---|
| `FNM_DIR` | `D:\caches\fnm` — the Node versions and the `default` alias |
| `npm_config_cache` | `D:\caches\npm` — npm's default is `%LOCALAPPDATA%\npm-cache`, off the drive and inside the AppData a packaged app redirects |
| `COREPACK_HOME` | `D:\caches\corepack`, for if yarn or pnpm ever arrive |

`npm config get prefix` then resolves *through* the alias junction, so global installs land on the Dev Drive as well with no prefix set. Setting one would be a mistake — a fixed prefix is shared across every Node version, which is the conflict the macOS `nvm` recipe deletes a leftover prefix to avoid. Without the Dev Drive attached the recipe falls back to home-relative XDG paths and says so, the way `uv` pins uv, so it is safe in `all`.

The recipe puts fnm's `aliases\default` junction on the user PATH, so `node` works in any new shell — cmd, Git Bash, anything that does not read the PowerShell profile. Per-directory switching is separate and comes from the fnm block in `source/windows/profile.ps1`: it aliases `cd` to run `fnm use --silent-if-unchanged` when the directory holds `.nvmrc`, `.node-version` or `package.json`. That block is guarded on `FNM_DIR` *and* a default alias existing on disk, both because evaluating `fnm env` is a ~40 ms process spawn on every shell start and because without a default alias it would otherwise leave a shell with a `cd` hook and no node — a worse state to debug than no integration at all.

Three files in `source/` are linked here, because they are the ones Windows tools read. The rest belong to tools this side does not have — zsh, oh-my-zsh, tmux, ruby, psql, bats, paperclip, vim — and `.claude` is skipped for the same reason as on macOS: it is Claude Code's live home, not config. `source/windows/` holds the Windows-only files that have no `$HOME` dotfile path of their own; `profile.ps1` is linked to `$PROFILE.CurrentUserAllHosts`, read from `$PROFILE` rather than built by hand because Documents is often redirected into OneDrive.

The dev root is `DEV_ROOT` (`D:\src`, following `DEVDRIVE_LETTER`). `sshd` has no working-directory option and drops a login in `%USERPROFILE%`, so the linked profile moves there — but only when the shell starts in the home directory, so a terminal opened inside a project stays put and an explicit `cd` in an SSH command still wins, and only when the drive is attached, since the boot-time mount task can be slower than the first login.

### First run

**[`docs/windows.md`](docs/windows.md)** is the runbook: the order that works, from a zip of this repo on a fresh machine to an SSH login from another computer, including the manual steps (antivirus, network trust, router, keys, deny-list) and why each is manual. In short: Defender only, `devdrive` from the unpacked zip, move the repo to `D:\src`, `git`, turn the folder into a clone, then `all`.

A Dev Drive's lighter scanning comes from Microsoft Defender's performance mode. A third-party antivirus does not provide it, and heuristic engines tend to quarantine installer scripts like these.

### Gotchas

- **AppData redirection.** Packaged (MSIX) apps — the Claude desktop app among them — silently redirect `%APPDATA%` and `%LOCALAPPDATA%` writes made by any process they launch into the app's private storage. A tool installed from such a terminal ends up somewhere your own shells cannot see. Recipes pin tool state elsewhere with `Set-UserEnv` (`bin/lib/tools.ps1`), preferring the paths the tool uses on macOS; registry writes are not redirected, which is why that works. When in doubt, run recipes from a plain terminal or an SSH session.
- **The python stubs.** `WindowsApps` holds `python.exe` / `python3.exe` stubs that only open the Microsoft Store. The `uv` recipe puts `~\.local\bin` first on the user `PATH` so uv's Python wins.
- **Line endings.** `.gitattributes` forces LF everywhere. Most bash recipes have no extension, so without it a CRLF checkout breaks them on the next commit to macOS.

### SSH server

`bin\install.ps1 openssh-server`, from an elevated PowerShell:

- Installs Windows' built-in OpenSSH Server and writes `sshd_config` from [`recipes/openssh-server/sshd_config`](recipes/openssh-server/sshd_config): keys only, the current user only, local port forwarding only (enough for VS Code Remote-SSH). The new config is checked with `sshd -t` before it replaces the live one; the original is kept as `sshd_config.pre-dotfiles`.
- Replaces the feature's own firewall rule, which allows every network and address, with TCP 22 from the **local subnet on Private networks only**. It never changes a network's Public/Private type — trusting a network is your decision — and warns if the active one is Public.
- Copies `~\.ssh\authorized_keys` into `C:\ProgramData\ssh\administrators_authorized_keys`, with an Administrators/SYSTEM-only ACL. Windows sshd ignores the per-user file for administrators. Re-run the recipe after adding a key.
- Makes PowerShell the login shell and prints the host key fingerprint to check on first connect.

To keep traffic off the WAN, also make sure the router forwards no port to the machine and has UPnP off. On the client, give the machine its own key and put the host entry in `~/.ssh/config.local`, which `source/.ssh/config` includes but this repo never tracks, since it holds an IP and username:

```
Host <alias>
  HostName <lan-ip>
  User <windows-user>
  IdentityFile ~/.ssh/<alias>
  IdentitiesOnly yes
```

`IdentitiesOnly yes` matters: the server allows three attempts, and an agent holding several GitHub keys uses them all up first.

`bin\teardown.ps1 openssh-server` stops and disables sshd, removes the firewall rule, restores the original config, and offers to remove the Windows feature. Host keys are kept, so a reinstall keeps the same fingerprint.

---

## LLM cluster

**[`docs/llm-cluster.md`](docs/llm-cluster.md)** is the planning document for running local models across the machines on a private LAN: why pooling VRAM over Ethernet buys capacity rather than speed, which of the available tools is worth the effort, and what the hardware on hand actually supports. In short: wire the nodes up before installing anything, and prefer one runtime per machine behind a single endpoint over splitting one model across six.

The first runtime is in place. `bin\install.ps1 ollama` installs Ollama on a Windows node and pulls a default set of four models that an 8 GB-class GPU can keep fully resident — `qwen3:8b` for interactive work, `qwen2.5-coder:7b` for editor completion, `qwen3:4b` for anything that should feel instant, and `qwen2.5vl:7b` for image input, which the other three cannot do — about 17.1 GB of weights into `D:\models\ollama`. Four models fit because `OLLAMA_MAX_LOADED_MODELS` is 1: they swap rather than compete, so each one past the first costs disk, not VRAM. Picking a vision model goes by encoder resolution rather than parameter count, and its VRAM cost is visual tokens in the KV cache — so what an 8 GB card limits is image size per prompt, not whether the model loads. Override the set with `OLLAMA_RECIPE_MODELS`, or the location with `OLLAMA_MODELS`. The recipe also pins the four server settings an 8 GB budget calls for (a `q8_0` KV cache being the one that matters most) and restarts the server onto them, since Ollama reads those in the server rather than the CLI. It then derives two more models from the same 4B weights with context windows baked in — `qwen3-agent:4b` at 32768 and `qwen3-agent64:4b` at 65536 — because the right window is per *harness*, not per machine ([below](#driving-a-local-model)). Both cost a manifest and no measurable disk, since a derived model shares its parent's blobs. Finally it registers a logon task so the server comes back after a restart: verified, a `winget` install leaves no `Run` entry, Startup shortcut, service or task of its own, so without it the server lives only as long as the shell that started it. Still missing, and the reason this is only half a cluster: a gateway putting one endpoint in front of the per-machine runtimes.

The doc is design and method only — [Sizing a node](docs/llm-cluster.md#sizing-a-node) gives the formulas for working out what a given card can hold, with no machine's numbers in it. Per-machine profiles and sizing notes live beside the collected inventory under `$XDG_DATA_HOME/dotfiles/inventory/`, outside this repo, for the same reason the fleet host list does: a hardware profile tied to a named machine is correlatable inventory a public repo should not carry.

Nothing in that network discussion applies to a single machine, incidentally — no bytes cross the wire per token. Ethernet is a clustering concern and a weights-download convenience, not a constraint on local inference.

Three read-only scripts collect the numbers that planning needs. None of them install or change anything.

| Script | Runs on | What it does |
|---|---|---|
| `scripts/inventory.ps1` | Windows | Prints this machine's inventory as JSON |
| `scripts/inventory.sh` | macOS, Linux | The same, in the same schema |
| `scripts/fleet-inventory.sh` | the machine you drive from | Collects from every node over SSH and prints a comparison |

```bash
# Hosts from the config file
scripts/fleet-inventory.sh

# Or named as arguments, with a platform where it is not unix
scripts/fleet-inventory.sh studio box:windows
```

Hosts are ssh aliases rather than addresses, and both the host list and the collected results live outside the repo: a collected set names every machine on the LAN and its address, which is the kind of inventory this repo deliberately withholds (see [Privacy gate](#privacy-gate)). The collector is piped to each node over SSH on stdin, so nothing is copied and no node can run a stale version.

### Driving a local model

**[`docs/local-llm.md`](docs/local-llm.md)** is the other half: how to talk to the server once it is running, and what it takes to put an agentic coding harness in front of it. One Ollama server answers three different request shapes at the same port — its own API, an OpenAI-compatible route, and, since v0.14.0, the Anthropic Messages API, which is why a Claude Code harness needs no translation proxy.

Two things measured there decide everything else, and neither is visible in a model card.

**A declared `tools` capability does not mean a model emits tool calls.** The flag only says the chat template has a tools section. The template tells the model to wrap each call in `<tool_call>` tags, and Ollama's parser turns those into a structured `tool_use` block — so a model that ignores the convention and prints bare JSON returns a response no harness can act on. In practice the agent prints an object at you and the file it was asked to edit is untouched, which reads like a confused model rather than a format mismatch. Of the installed set, both Qwen3 models pass and `qwen2.5-coder:7b` fails despite declaring the capability: a code-completion model is tuned for fill-in-the-middle, and agentic formatting is a different objective. **Do not reach for the model with "coder" in the name to drive an agent** — it belongs in editor completion, where there are no tools to call. `bin\llm-probe.ps1` checks any model in about a second.

**An agentic harness spends about 14K tokens before the conversation starts.** It sends its system prompt and the JSON schema of every tool it owns on every turn; measured, a Claude Code run asking *"what is 2+2"* was 13,821 input tokens. That inverts the sizing question: a 16K window leaves ~2.5K for the conversation, the files read and every tool result, so the model that wins is the one holding the biggest window on the GPU rather than the one with the most parameters. On an 8 GB card a 4B model at 32768 stays 100% GPU at full speed where an 8B at 32768 spills — hence the derived `qwen3-agent:4b`, since `OLLAMA_CONTEXT_LENGTH` is server-wide and raising it would spill the 8B that chat uses.

**Which means the harness's prompt is a first-order cost, not a detail.** Measured on the same prompt, same model, same server, reading the usage each harness reports for itself:

| | Claude Code | OpenCode | Pi |
|---|---|---|---|
| *"What is 2+2?"* | 13,821 input tokens | 7,215 | **699** |
| After a full read-edit-confirm turn | 15,061 | 8,305 | 1,753 |
| Of a 32K window, spent before you speak | 42% | 22% | **2%** |

Almost 20× end to end, because Pi's core is four tools — read, bash, edit, write — where the other two ship a full surface every turn. That is not a verdict on the harnesses: Claude Code's prompt buys subagents, skills, MCP and much more tooling, and against a hosted 200K window the overhead is a rounding error. It is a verdict about this hardware. **On a local model, start with Pi.**

Nor is 32768 a hard wall — it is the largest window that costs *nothing*. Weights and KV cache share VRAM, so 8 GB decides how much window stays GPU-resident; past that llama.cpp offloads the overflow to system RAM rather than failing, so **RAM buys window, paid for in bandwidth**: 65536 lands at 26%/74% CPU/GPU and 46.9 tok/s, 131072 at 57%/43% and 21.5 tok/s, where system RAM runs out.

That turns the overhead table into something concrete. Same three files, one cross-file bug, each harness reading all three to find it:

| Harness | Window | Result | Time |
|---|---|---|---|
| Pi | 32768 | fixed | **25–54 s** |
| OpenCode | 32768 | fixed | 101–115 s |
| Claude Code | 65536 | fixed, 5 turns | 319 s |
| Claude Code | 32768 | **failed** — *"autocompact is thrashing"* | 379 s |

Monotonic in prompt overhead, which is the point. [`docs/local-llm.md`](docs/local-llm.md) has the full method, separates the cases where more RAM helps from the ones where it buys nothing, and says what clustering does and does not address — short version: it raises the capacity ceiling, it does not reduce harness overhead or make a given model faster.

| | What to run | Window it uses |
|---|---|---|
| Pi on a local model (leanest prompt) | `bin\install.ps1 pi`, then `pi --model ollama/qwen3-agent:4b` | 32768, 100% GPU |
| OpenCode on a local model | `bin\install.ps1 opencode`, then `opencode` | 32768, 100% GPU |
| Claude Code on a local model | `bin\claude-local.ps1` | 65536, spills — see above |
| Check a model can drive an agent | `bin\llm-probe.ps1` | — |
| Check the whole stack, end to end | `bin\llm-verify.ps1` | — |

`bin\claude-local.ps1` sets four variables for one child process and nothing else — persisting `ANTHROPIC_BASE_URL` as a user variable would silently redirect *every* Claude Code session on the machine, including the ones meant for the real API. The one that is easy to miss is `CLAUDE_CODE_MAX_CONTEXT_TOKENS`: Claude Code cannot discover the window of a model ID it does not recognise, assumes 200K, and so never compacts. (`CLAUDE_CODE_AUTO_COMPACT_WINDOW` is not the knob — it clamps to a 100K floor, far above anything local hardware offers.)

OpenCode is the contrast, and the reason that recipe exists: it discovers a running server on the default port and enumerates its models, derived ones included, with nothing written to a config file. All three drive the same server — Claude Code over the Anthropic surface, the other two over the OpenAI one — which makes it cheap to tell a harness problem from a model problem.

**`bin\llm-verify.ps1`** checks all of that on a machine rather than taking it on faith, in about 45 seconds and changing nothing: the server and what started it, the pinned settings as the *server* sees them, all three API surfaces, the window each model loads with, both harnesses' model lists, and the Node toolchain. It prints the value each check read rather than a verdict — `PASS` from a script is only another claim to take on faith, and a number is what makes a wrong one obvious. Lines beginning `!!` are checks that read something they can argue is wrong, and the exit code is the count of those, so it works from another script. Slow or destructive checks are opt-in: `-Tools` (tool-call compliance across every installed model), `-Runs` (one real turn through each harness), `-Restart` (kill the server, bring it back through the logon task), `-All`, or `-Only <names>` for a subset.

**[`docs/verify-local-llm.md`](docs/verify-local-llm.md)** is the same ground by hand, and the explanation: what each check is doing, what its output means, and the `-Only` flag that runs just that one. It is written for the shell an SSH logon gets, Windows PowerShell 5.1. The last section maps symptom to cause for the failures that look like something else — a 404 that reads like a dead server, an empty `ollama list` from a healthy one, raw `<think>` tags in a reply, a task result code that reports success as a failure.

One finding from writing it is worth stating here, because it is the kind of thing that only surfaces when something is verified from where it will actually be used: the `ollama` recipe's logon task uses an at-logon trigger, and **an OpenSSH logon arrives as logon type 3, Network, which a logon trigger does not fire for** — it fires for console, RDP and unlock. A machine that reboots and is then reached only over SSH therefore had the task sitting `Ready` and nothing listening. The profile now probes the port when `SSH_CONNECTION` is set and starts the task if it finds it closed; the guard keeps that cost off every other shell, since a console logon was already covered. For a genuinely headless box the right fix is a task that runs whether or not the user is logged on, which needs elevation and is left as a deliberate choice — the runbook gives the command.

Pi's configuration lives in `~\.pi\agent\models.json`, already home-relative rather than under AppData, so there is nothing to pin. Its `contextWindow` field is the same problem `CLAUDE_CODE_MAX_CONTEXT_TOKENS` solves (Pi defaults an unknown model to 128000) except that it sits in the same file as the provider, so there is no variable to forget. The recipe merges into that file rather than overwriting it — a hosted provider's proxy or a model override can live there too, and it only owns the `ollama` key; the teardown removes that key alone. `qwen2.5-coder:7b` is deliberately left unregistered, since offering a model that returns tool calls as prose is worse than not offering it.

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

### Finding where memory goes

`bin/memmap` is the same idea for memory, and `bin/memclean` is its `diskclean`:

```bash
bin/memmap               # top 3 owners overall, then every dev unit
bin/memmap --min-mb 200  # roll up dev units below 200 MB
bin/memclean             # fzf multi-select of what to stop, then a confirmation manifest
```

Figures are `top`'s footprint, the number Activity Monitor shows, not `ps` RSS. The top 3 counts each app with all its helpers (a browser's dozens of content processes are one row), whatever it is. The dev section groups processes by kind (node, python, ruby, beam, java, database, lsp, claude, simulator, the VM), folding each into its nearest ancestor of the same kind, so `npm run dev` and its `next-server` child are one unit, labelled with the directory it runs in.

The colima VM is broken down by container group (compose project, else Supabase project, else container name). Memory a stopped container used stays inside the VM, so the gap is shown as held by the VM: only `colima stop` returns it to macOS.

`memclean` stops containers with `docker stop`, the VM with `colima stop`, dev units with `SIGTERM`, and top apps by asking them to quit. The terminal and any session it runs inside are never offered. Neither are processes owned by another user, such as a root-installed postgres: there is no sudo flow yet, so `memmap` shows them but they cannot be stopped from here.

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
