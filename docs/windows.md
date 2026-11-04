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

Skip this step to use a plain folder instead (e.g. `~\dev`); nothing else depends on
the Dev Drive.

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

## 4. GitHub CLI, Python and the privacy gate (recipes + manual)

```powershell
powershell -ExecutionPolicy Bypass -File bin\install.ps1 gh
powershell -ExecutionPolicy Bypass -File bin\install.ps1 uv
powershell -ExecutionPolicy Bypass -File bin\install.ps1 hooks
```

(`bin\install.ps1 all` runs these and `claude` in order.)

- **gh login (manual).** The `gh` recipe offers it; answer the browser or device-code
  prompt yourself. Shells opened before the recipe ran do not have `GH_CONFIG_DIR`
  yet and report "not logged in" -- open a new one.
- **Deny-list (manual).** The gate blocks every commit until it exists, and the
  `hooks` recipe warns if it is missing. Copy `scripts\denylist.local.txt.example` to
  `~\.config\exponential\denylist.txt` and list the names this public repo must never
  contain.
- **Commit identity (manual, per clone).** The `dotfiles` recipe that links
  `.gitconfig` and the identity files has no Windows version yet, so set it on the clone:

  ```powershell
  git config user.name <name>
  git config user.email <email>
  ```

- **Pushing over HTTPS** with gh's login, without writing a credential helper into
  `~/.gitconfig` (on macOS that file is the repo's `source/.gitconfig`):

  ```powershell
  git -c credential.helper= -c 'credential.https://github.com.helper=!gh auth git-credential' push
  ```

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

## Verify

```powershell
Get-MpComputerStatus | Select AMRunningMode, RealTimeProtectionEnabled       # Normal, True
Get-Volume D | Select FileSystem, FileSystemLabel                            # ReFS, Dev
git config --system core.autocrlf                                            # false
git config core.hooksPath                                                    # hooks
python3 -c "import sys; print(sys.executable)"                               # under ~\.local\share\uv
gh auth status
Get-Service sshd | Select Status, StartType                                  # Running, Automatic
Get-NetFirewallRule -Name dotfiles-sshd-lan | Get-NetFirewallAddressFilter   # RemoteAddress LocalSubnet
Get-NetConnectionProfile | Select Name, NetworkCategory                      # Private at home
```

## Where things live

| What | Where | Set by |
|---|---|---|
| Dev Drive | `D:` from `C:\DevDrives\dev.vhdx`, task `\dotfiles\Mount Dev Drive` | `devdrive` |
| Repos | `D:\src\` | you |
| Git for Windows, GitHub CLI | Program Files | `git`, `gh` (winget) |
| uv, Python 3.14 | winget's folder; `~\.local\share\uv\python`, launchers in `~\.local\bin` | `uv` |
| uv cache, tools | `~\.cache\uv`, `~\.local\share\uv\tools` | `uv` (`UV_*` user variables) |
| gh config | `~\.config\gh`; token in Windows Credential Manager | `gh` (`GH_CONFIG_DIR`) |
| Claude Code | `~\.local\bin\claude.exe`, state in `~\.claude` | `claude` |
| Deny-list | `~\.config\exponential\denylist.txt` | you |
| sshd config, keys | `C:\ProgramData\ssh\` | `openssh-server` |

## Teardown

Reverse order. Each one stands alone:

```powershell
bin\teardown.ps1 openssh-server   # elevated; restores the original sshd_config
bin\teardown.ps1 gh
bin\teardown.ps1 git              # last thing needing git
bin\teardown.ps1 devdrive         # elevated, from a copy of the repo NOT on D:
```

`devdrive`'s teardown detaches the drive and deletes the backing file only if you type
`DELETE`. `uv`, `hooks` and `claude` have no teardown, as on macOS. The manual steps
(Defender, network type, router) are left as they are.

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
- **"Permission denied (publickey)"**: the key is not in
  `administrators_authorized_keys` yet; re-run the `openssh-server` recipe elevated
  (6d). **"Too many authentication failures"**: add `IdentitiesOnly yes` (6c).
