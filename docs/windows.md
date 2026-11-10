# Windows runbook

Bootstrapping a Windows 11 machine with this repo, start to finish, in the order that
works. Each step says whether a recipe does it or you do. Steps marked **manual** are
manual on purpose: they decide what the machine trusts (antivirus, networks, accounts,
keys), so no script makes them for you.

The recipes themselves are described in the README's [Windows](../README.md#windows)
section; this file is the sequence and the reasons.

**Be at the machine** for steps that say *elevated*. A UAC prompt only appears on the
machine's own screen, and if nobody answers it within about a minute Windows reports
"The operation was canceled by the user". Over remote control or SSH that is the
usual cause, not a refusal.

---

## 0. Check the hardware (optional)

Read-only, from any PowerShell:

```powershell
Get-CimInstance Win32_ComputerSystem | Select Manufacturer, Model, @{n='RAM_GB';e={[math]::Round($_.TotalPhysicalMemory/1GB)}}
Get-CimInstance Win32_Processor | Select Name, NumberOfCores, NumberOfLogicalProcessors, VirtualizationFirmwareEnabled
nvidia-smi --query-gpu=name,memory.total,driver_version,compute_cap --format=csv
Get-Volume C | Select @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}}
```

GPU memory decides what local models are sensible: 8 GB fits 7-9B models at 4-5 bit
quantization comfortably. Free space on C: decides the Dev Drive size (step 2); leave
room for Windows updates and, later, WSL and Docker images.

## 1. Antivirus: Microsoft Defender only (manual)

Uninstall any third-party antivirus (Settings > Apps > Installed apps, then restart),
and check Defender took over:

```powershell
Get-MpComputerStatus | Select AMRunningMode, AntivirusEnabled, RealTimeProtectionEnabled
```

Expect `Normal`, `True`, `True`. Two reasons, both learned here: Dev Drive's lighter
scanning is a Defender feature, and a heuristic engine quarantined `bin\install.ps1`
the moment it launched a silent winget install (reported as `IDP.Generic`), then
blocked recreating the file.

## 2. Get the repo and create the Dev Drive (recipe, elevated)

Git is itself a recipe, so the repo starts as a zip. Download the `main` branch zip
from GitHub, unpack it somewhere temporary such as Downloads, and from an **elevated**
PowerShell in that folder:

```powershell
Get-ChildItem -Recurse -File | Unblock-File      # clear the downloaded-from-internet flag
powershell -ExecutionPolicy Bypass -File bin\install.ps1 devdrive
```

This creates `C:\DevDrives\dev.vhdx` (grows as it fills, capped at 64 GB) formatted as
a Dev Drive at `D:` with `D:\src`, `D:\caches` and `D:\models`, and registers the
`\dotfiles\Mount Dev Drive` task that re-attaches it at boot. Override the defaults
with `DEVDRIVE_VHDX`, `DEVDRIVE_SIZE_GB` and `DEVDRIVE_LETTER`. It warns if a
third-party antivirus filter is attached to the volume.

Then move the repo onto it and work from there from now on:

```powershell
Copy-Item -Recurse <unpacked-folder> D:\src\dotfiles
Set-Location D:\src\dotfiles
```

Restart once at some point and confirm `D:` comes back by itself.

Dev Drive needs Windows 11 build 10.0.22621.2338 or later and at least 8 GB of RAM
([Microsoft's requirements](https://learn.microsoft.com/windows/dev-drive)), neither of
which the recipe checks. On a machine that misses them the disk is still created and
attached and only the format fails, leaving an attached, unformatted disk and a `.vhdx`
on `C:`: delete the file and use a plain folder.

Skip this step to use a plain folder instead. Tell the `dotfiles` recipe where it is,
or it will assume `D:\src` and warn that the path is missing:

```powershell
setx DEV_ROOT "$env:USERPROFILE\dev"     # then open a new shell
```

`DEV_ROOT` wins over `DEVDRIVE_LETTER`, and the recipe keeps whatever it already says,
so this survives every re-run.

## 3. Install git and turn the folder into a clone (recipe)

```powershell
powershell -ExecutionPolicy Bypass -File bin\install.ps1 git
```

Git for Windows' installer asks for elevation itself. Then, in a **new** shell so
`git` is on PATH:

```powershell
git init -b main
git remote add origin https://github.com/<owner>/dotfiles.git
git fetch origin
git reset origin/main            # keeps the working tree; any local edits show as a diff
git branch -u origin/main main
git status                       # expect a clean tree, or only your own new files
```

The `.oh-my-zsh` submodule is not in the zip and is not needed on Windows.

## 4. Dotfiles, GitHub CLI, Python and the privacy gate (recipes + manual)

```powershell
powershell -ExecutionPolicy Bypass -File bin\install.ps1 dotfiles
powershell -ExecutionPolicy Bypass -File bin\install.ps1 gh
powershell -ExecutionPolicy Bypass -File bin\install.ps1 uv
powershell -ExecutionPolicy Bypass -File bin\install.ps1 hooks
```

(`bin\install.ps1 all` runs these and `claude` in order.)

- **Symlink privilege.** The `dotfiles` recipe creates symlinks, which needs
  `SeCreateSymbolicLinkPrivilege`: only Administrators hold it, and UAC strips it from
  a local interactive shell. An SSH logon keeps it, so over SSH this just works; at the
  machine itself, use "Run as administrator". The recipe tests it by making one
  throwaway link and stops before writing anything if it cannot. Because `dotfiles` is
  in `all`, the same applies to a full `all` run.
- **What it links.** `.gitconfig`, `.git-excludes-file`, `.ssh/config`, and
  `source/windows/profile.ps1` to the PowerShell profile. An existing *real*
  `~/.ssh/config` is left alone, as on macOS. It also sets `DEV_ROOT`, which is what
  makes an SSH login land in `D:\src` (see [Where things live](#where-things-live)) --
  or wherever `DEV_ROOT` already points, which is how a machine without a Dev Drive
  names its own dev root (step 2).
- **OneDrive must not hold the profile (manual).** Windows often redirects Documents
  into OneDrive ("Known Folder Move"), which puts `$PROFILE` inside a synced folder. The
  recipe refuses to link it there and says so: OneDrive either skips a symlink with a
  sync error or follows it and uploads the file, which would hand every other machine on
  the account a stale copy of `profile.ps1`. Nothing from this repo belongs in a synced
  folder. Turn the redirection off at the machine -- OneDrive > Settings > Sync and
  backup > Manage backup > Documents off -- move anything you want to keep from
  `%USERPROFILE%\OneDrive\Documents` back to `%USERPROFILE%\Documents`, then re-run the
  recipe. `$PROFILE.CurrentUserAllHosts` should then sit under `%USERPROFILE%\Documents`.
  Desktop and Pictures are usually redirected along with it; neither affects the recipes.
- **SSH keys (manual).** `.ssh/config` pins a key per host with `IdentitiesOnly`, so a
  key this machine does not have means "Permission denied (publickey)" rather than a
  fallback to whatever the agent holds. The recipe lists the ones it cannot find;
  generate them as in the README's SSH key setup. HTTPS remotes are unaffected, since
  they authenticate through gh.
- **gh login (manual).** The `gh` recipe offers it; answer the browser or device-code
  prompt yourself. Shells opened before the recipe ran do not have `GH_CONFIG_DIR`
  yet and report "not logged in" -- open a new one.
  Note that an SSH logon session cannot use Credential Manager, so `gh` keeps its
  token in plaintext under `GH_CONFIG_DIR`; see
  [disk encryption](windows-disk-encryption.md) for why that wants an encrypted
  drive and how to turn one on.
- **Deny-list (manual).** The gate blocks every commit until it exists, and the
  `hooks` recipe warns if it is missing. Copy `scripts\denylist.local.txt.example` to
  `~\.config\exponential\denylist.txt` and list the names this public repo must never
  contain.
- **Commit identity (manual).** `.gitconfig` routes identities through
  `~\.gitconfig-identities`, which is gitignored and so never arrives with the repo.
  The `dotfiles` recipe warns when an include is missing, because git ignores one
  silently and the first symptom is a commit under the wrong name. Copy the templates
  **into your home directory**, not into `source\`: `source\.gitconfig-identities.example`
  to `~\.gitconfig-identities`, and `source\.gitconfig-identity.example` to one
  `~\.gitconfig-<name>` per account. The macOS recipe links everything in `source/`, so
  a copy left there becomes `~/<name>`; this one links a fixed list and never links
  identity files, so a copy in `source\` changes nothing. Git reads them as soon as they
  exist -- nothing needs re-running. Remember that `includeIf "gitdir:..."` patterns need
  *this* machine's paths with forward slashes -- `gitdir:D:/src/work/`, not the macOS
  home-relative ones. Or skip all that and set it on the clone:

  ```powershell
  git config user.name <name>
  git config user.email <email>
  ```

- **Pushing over HTTPS** needs no flags: git's credential helper for `github.com` and
  `gist.github.com` points at gh, so gh's own login answers instead of the Git
  Credential Manager, which an SSH logon session cannot reach. Every other host keeps
  GCM. With `dotfiles` run, the helper comes from the tracked `source/.gitconfig`
  through the `~/.gitconfig` link, and the `gh` recipe says so rather than writing it:
  it never writes through a link, since that file is public and this is machine-local
  configuration. On a machine without `dotfiles`, the `gh` recipe writes it into a real
  `~/.gitconfig` instead. Either way `bin\teardown.ps1 gh` leaves a linked file alone.

## 5. Claude Code (recipe)

```powershell
powershell -ExecutionPolicy Bypass -File bin\install.ps1 claude
```

Run it from a plain terminal or an SSH session, **not** from a terminal inside the
Claude desktop app, which redirects AppData writes (see the README's Gotchas). Sign in
on first run; over SSH, open the printed URL on the other computer and paste the code
back.

## 6. SSH from another computer on the LAN

### 6a. Prepare the network (manual)

- Set the home network to **Private**: Settings > Network & internet > Wi-Fi (or
  Ethernet) > *network* > Network profile type. The recipe never changes this.
- Private also enables Windows' other Private-network allowances. Turn off what you do
  not need:
  - **Remote Assistance**: Settings > System > About > Advanced system settings >
    Remote > untick *Allow Remote Assistance connections*.
  - **Network Discovery**: Settings > Network & internet > Advanced network settings >
    Advanced sharing settings > Private networks. Off unless this machine needs to
    browse other devices.
- On the router: **no port forwarding** to this machine and **UPnP off**, so nothing
  can open a port to the internet on its behalf. A DHCP reservation keeps its LAN
  address stable.

### 6b. Run the recipe (recipe, elevated)

```powershell
powershell -ExecutionPolicy Bypass -File bin\install.ps1 openssh-server
```

It prints `ssh <user>@<lan-ip>` and the host key fingerprint. Write the fingerprint
down for 6e.

### 6c. Make a key on the client (manual, on the other computer)

Give this machine its own key rather than reusing a GitHub one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/<alias> -C "<client> to <alias>"
```

Use a passphrase. Put the host entry in `~/.ssh/config.local`, which
`source/.ssh/config` includes and this repo never tracks:

```
Host <alias>
  HostName <lan-ip>
  User <windows-user>
  IdentityFile ~/.ssh/<alias>
  IdentitiesOnly yes
  UseKeychain yes
  AddKeysToAgent yes
```

`IdentitiesOnly yes` is required when the agent holds other keys: the server allows
three attempts, and offering every GitHub key first ends in "Too many authentication
failures". `UseKeychain` is macOS-only. `chmod 600 ~/.ssh/config.local`.

### 6d. Authorize the key (manual + recipe, elevated)

Append the client's `~/.ssh/<alias>.pub` line to `~\.ssh\authorized_keys` on this
machine, then re-run the recipe elevated. Windows sshd ignores that file for
administrators and reads only `C:\ProgramData\ssh\administrators_authorized_keys`;
the recipe copies the keys across and locks the file's permissions. Expect
`1 authorized key(s) installed`.

### 6e. Connect

```bash
ssh <alias>
```

Answer `yes` only if the fingerprint matches 6b. To read it later without elevation:

```powershell
ssh-keyscan -t ed25519 <lan-ip> | ssh-keygen -lf -
```

---

## 7. tmux over SSH (optional, recipe)

Opt-in, elevated, and it needs one restart in the middle:

```powershell
bin\install.ps1 wsl       # enables the WSL features, then stops for a restart
# restart, reconnect, then the same command again:
bin\install.ps1 wsl       # registers the distro, installs tmux, links the config
```

- **Why WSL and not something native.** `sshd` puts each login session in a job object
  marked `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` and keeps the handle itself, so the end
  of a session kills everything still inside the job. A child process inherits that
  membership and `Start-Process` cannot ask to break away, so a backgrounded job dies
  with the connection -- the POSIX reflex does not apply here. WSL's processes are not
  Windows processes and are in no Windows job: they run in the WSL VM under
  `wslservice.exe`, so a tmux server there outlives the session that started it, and
  any terminal can reattach over plain `ssh`.
- **The stub is not the real `wsl.exe`.** Until WSL is installed,
  `C:\Windows\System32\wsl.exe` takes only `--install`, `--update`, `--status` and
  `--help`, and refuses anything else by printing "The Windows Subsystem for Linux is
  not installed" and exiting 1 -- whatever it actually objected to. So the recipe
  enables the features with DISM and installs the WSL package through winget
  (`Microsoft.WSL`), instead of letting the stub's bare `--install` choose a
  distribution and launch it.
- **`--no-launch` matters.** A distro's first run asks for a UNIX account name and
  password on the console, which would hang a recipe driven over SSH. The recipe
  registers the distro without launching it and creates the user itself.
- **Passwordless sudo, deliberately.** `wsl --user root` needs no password and never
  will, so a sudo password inside the distro guards nothing while making every run
  interactive. It is a drop-in at `/etc/sudoers.d/90-dotfiles-wsl`, validated with
  `visudo -c` before it is installed; the recipe says how to swap it for a real
  password.
- **The config is linked, not copied**, from `/mnt/<letter>/.../source/.tmux.conf`, so
  there is one copy of it and an edit on the Windows side is live at the next tmux
  start. `D:` is ReFS and which volumes automount is WSL's call, so the recipe reads
  the file from inside the distro first and links nothing when it cannot, rather than
  leaving a dangling link behind.
- **`claude`, not `claude.exe`.** Claude Code stays on the Windows side -- one
  install, one auth, one session history, and the same project key, since the working
  directory translates back to `D:\src\dotfiles`. The recipe installs a shim at
  `/usr/local/bin/claude` inside the distro, because interop resolves Windows
  executables by extension only and a plain `claude` would not be found. It is a
  script rather than a symlink for a second reason: WSL builds an interop process's
  Windows environment from the `wsl.exe` client that started the distro session, not
  from the Linux environment. When that client was itself a Claude Code tool call --
  as it is whenever an agent starts the server on your behalf -- `claude.exe` inherits
  `CLAUDE_CODE_CHILD_SESSION`, reads itself as a subprocess and stops saving its
  transcript, so that session cannot afterwards be resumed. The shim exports each
  marker empty and names it in `WSLENV`, the one lever that reaches the Windows side,
  which drops it from the child outright.
- **What survives.** A dropped connection, yes. A restart or `wsl --shutdown`, no:
  after either, `prefix + Ctrl-r` restores the tree tmux-resurrect saved, which lives
  in the distro's home rather than on the Windows side.

```powershell
wsl -d Ubuntu -- tmux new -A -s main    # attach, creating it if needed
wsl -d Ubuntu -- tmux ls
claude                                  # inside the session
```

Worth confirming once, because everything above rests on it: start a detached session
(`wsl -d Ubuntu -- tmux new -d -s probe`), drop the SSH connection, reconnect, and
check `wsl -d Ubuntu -- tmux ls` still lists it. Measured here from the other
direction too: `wslservice.exe` is a sibling of the sshd *service*, started before the
login session exists, and a process launched through interop is in no job object at
all, while the SSH shell itself is in one.

---

## Verify

```powershell
Get-MpComputerStatus | Select AMRunningMode, RealTimeProtectionEnabled       # Normal, True
Get-Volume D | Select FileSystem, FileSystemLabel                            # ReFS, Dev
git config --system core.autocrlf                                            # false
git config core.hooksPath                                                    # hooks
(Get-Item ~\.gitconfig -Force).Target                                        # ...\source\.gitconfig
$env:DEV_ROOT                                                                # D:\src
(Get-Item $PROFILE.CurrentUserAllHosts -Force).Target                        # ...\source\windows\profile.ps1
ssh -G github.com | Select-String identityfile                               # the config parses
python3 -c "import sys; print(sys.executable)"                               # under ~\.local\share\uv
gh auth status
Get-Service sshd | Select Status, StartType                                  # Running, Automatic
Get-NetFirewallRule -Name dotfiles-sshd-lan | Get-NetFirewallAddressFilter   # RemoteAddress LocalSubnet
Get-NetConnectionProfile | Select Name, NetworkCategory                      # Private at home
wsl -d Ubuntu -- tmux -V                                                     # tmux 3.x
wsl -d Ubuntu -- readlink -f ~/.tmux.conf                                    # ...\source\.tmux.conf
wsl -d Ubuntu -- command -v claude                                           # /usr/local/bin/claude
wsl -d Ubuntu -- claude --version                                            # 2.x (Claude Code)
```

## Where things live

| What | Where | Set by |
|---|---|---|
| Dev Drive | `D:` from `C:\DevDrives\dev.vhdx`, task `\dotfiles\Mount Dev Drive` | `devdrive` |
| Repos | `D:\src\`, and `DEV_ROOT` points at it (set `DEV_ROOT` first to choose another) | `devdrive`, `dotfiles` |
| Linked dotfiles | `~\.gitconfig`, `~\.git-excludes-file`, `~\.ssh\config` -> `source\` | `dotfiles` |
| PowerShell profile | `$PROFILE.CurrentUserAllHosts` -> `source\windows\profile.ps1` | `dotfiles` |
| Git identities | `~\.gitconfig-identities` and the files it includes | you (gitignored) |
| Git for Windows, GitHub CLI | Program Files | `git`, `gh` (winget) |
| uv, Python 3.14 | winget's folder; `~\.local\share\uv\python`, launchers in `~\.local\bin` | `uv` |
| uv cache, tools | `~\.cache\uv`, `~\.local\share\uv\tools` | `uv` (`UV_*` user variables) |
| gh config | `~\.config\gh`; token in Windows Credential Manager | `gh` (`GH_CONFIG_DIR`) |
| Claude Code | `~\.local\bin\claude.exe`, state in `~\.claude` | `claude` |
| Deny-list | `~\.config\exponential\denylist.txt` | you |
| sshd config, keys | `C:\ProgramData\ssh\` | `openssh-server` |
| WSL distro, tmux | the distro's own ext4 disk; its `~/.tmux.conf` -> `/mnt/d/src/dotfiles/source/.tmux.conf` | `wsl` |

## Teardown

Reverse order. Each one stands alone:

```powershell
bin\teardown.ps1 openssh-server   # elevated; restores the original sshd_config
bin\teardown.ps1 claude           # from a plain shell, not from inside Claude Code
bin\teardown.ps1 hooks            # un-gates commits in this clone
bin\teardown.ps1 uv               # removes the python3 the hooks need
bin\teardown.ps1 gh
bin\teardown.ps1 dotfiles         # unlinks; new shells start at ~ again
bin\teardown.ps1 git              # last thing needing git
bin\teardown.ps1 wsl              # elevated; unregisters the distro only if you type DELETE
bin\teardown.ps1 devdrive         # elevated, from a copy of the repo NOT on D:
```

Each asks before it does anything. What they keep: `claude` keeps `~\.claude` and
`~\.claude.json` (sessions, settings, project history) and refuses to run while a
`claude.exe` is running, because Windows locks a running binary; `hooks` keeps the
deny-list, which is shared with every other clone and worktree; `uv` keeps project
`.venv` directories; `dotfiles` removes only links pointing inside this repo, so a
hand-written file or a link elsewhere is reported and kept, and it restores any
`.pre-dotfiles` copy it made; `devdrive` detaches the drive and deletes the backing
file only if you type `DELETE`; `wsl` stops the distro and unregisters it -- its home
directory and resurrect saves with it -- only on the same typed confirmation, and
leaves the two Windows features enabled. Tearing down `uv` or `hooks` means commits
here stop being checked against the deny-list -- `uv` takes `python3` away, so the
gate refuses every commit until the recipe runs again. The manual steps (Defender,
network type, router) are left as they are.

## Troubleshooting

- **"The operation was canceled by the user"** on an elevated step: nobody answered
  UAC at the machine. Re-run while there.
- **A script vanished, or writing a file fails with EPERM**: an antivirus quarantined
  it. See step 1.
- **A tool installed but nothing can find it, or uv reports "Missing expected target
  directory"**: it ran inside a packaged app's terminal and its AppData writes were
  redirected. Run the recipe from a plain terminal or SSH; the recipes pin their tools
  outside AppData so this only bites tools without a recipe.
- **`python3` opens the Store, or "uv trampoline failed to spawn Python"**: the
  `WindowsApps` stub is first on PATH, or a launcher points at a deleted install.
  Delete `~\.local\bin\python*.exe` and re-run the `uv` recipe.
- **`python3` fails only in elevated shells or over SSH with "The path cannot be
  traversed because it contains an untrusted mount point. (os error 448)"**: uv
  reaches Python through a junction (`cpython-3.14-...` -> `cpython-3.14.N-...`), and
  Windows will not let an elevated process follow a junction created by a non-elevated
  one. An administrator's SSH session is always elevated, so the privacy gate hooks
  stop working there. Re-run the `uv` recipe elevated or over SSH; a junction created
  that way works for both. It comes back when uv upgrades the patch release from a
  non-elevated shell, and the recipe warns when run non-elevated.
- **"Unable to persist credentials with the 'wincredman' credential store"**, then
  `could not read Username for 'https://github.com'`: the Git Credential Manager is
  answering, and it cannot reach Credential Manager from an SSH logon session or
  prompt without a tty. Re-run the `gh` recipe, which points the helper at gh
  instead; `git config --get-urlmatch credential https://github.com` should print
  `!gh auth git-credential`.
- **An SSH login starts in the home directory, not the dev root**: either `DEV_ROOT` is
  unset or its path is not there (`$env:DEV_ROOT`, step 2), or the profile was never
  linked because `$PROFILE` is inside OneDrive (step 4). The profile also leaves a shell
  alone deliberately when it did not start in the home directory.
- **"Permission denied (publickey)"**: the key is not in
  `administrators_authorized_keys` yet; re-run the `openssh-server` recipe elevated
  (6d). **"Too many authentication failures"**: add `IdentitiesOnly yes` (6c).
- **`wsl` output reads as `U b u n t u`**, with a space between every character:
  wsl.exe writes UTF-16LE and Windows PowerShell 5.1 reads it in the ANSI code page.
  The `wsl` recipe sets `WSL_UTF8=1` for your shells; one opened before that needs
  reopening. Nothing is wrong with the distro.
- **A tmux session is gone after a restart**: expected, since the WSL VM went with it
  (step 7). `wsl -d Ubuntu -- tmux new -A -s main` starts a fresh server and
  `prefix + Ctrl-r` restores the saved tree. A dropped SSH connection is the case that
  does leave the server running.
- **Claude in the distro says "Transcript saving is off -- inherited
  CLAUDE_CODE_CHILD_SESSION marker"**: `claude.exe` was run instead of `claude`, inside
  a tmux server whose own `wsl.exe` client was a Claude Code session. That session will
  not be resumable, so start again. Use `claude`, which exists for this reason, and to
  check a pane: `cmd.exe /c "echo [%CLAUDE_CODE_CHILD_SESSION%]"` printing the name
  back unexpanded means nothing was inherited.
- **`~/.tmux.conf` was not linked**: the distro could not read the repo under `/mnt`,
  which the recipe reports rather than guessing. Check `wsl -d Ubuntu -- ls /mnt`;
  `D:` is a ReFS Dev Drive, and whether WSL automounts it is WSL's decision, not this
  repo's.
