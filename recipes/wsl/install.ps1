# WSL 2 plus tmux: a detachable session that survives a dropped SSH connection.
# Opt-in (not in 'all'), run elevated, and it needs one restart partway through.
#
# Why this recipe rather than a Windows-native equivalent. sshd puts every login
# session in a job object marked JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE and holds the
# handle itself, so when the session ends Windows kills everything still in the job.
# A child process inherits that membership and Start-Process cannot ask to break
# away, so the POSIX habit of backgrounding a long job does not survive a disconnect
# here -- measured on this machine: LimitFlags 0x2800, every process from conhost
# down inside the job, sshd outside it holding the handle.
# Linux processes under WSL are not Windows processes and are in no Windows job: they
# run inside the WSL VM, which wslservice.exe keeps alive. So a tmux server started
# through wsl.exe outlives both the client that started it and the SSH session that
# client belonged to, and it is reattachable from any terminal over plain ssh.
#
# What it does, in order. Each step is skipped when already done, so re-running is
# safe -- and re-running is also how you resume after the restart in step 1.
#   1. Enables the two Windows features WSL 2 needs, then stops for a restart. The run
#      after the restart installs the WSL package itself (winget, Microsoft.WSL).
#   2. Registers the distro WITHOUT launching it, so its first-run account prompt
#      cannot block a non-interactive run.
#   3. Creates the login user, gives it passwordless sudo (see the note in the script)
#      and makes it the distro's default user.
#   4. Installs tmux, and the git tpm needs, inside the distro.
#   5. Links the distro's ~/.tmux.conf to this repo's source/.tmux.conf, so the config
#      has exactly one copy and editing it on the Windows side is enough.
#   6. Clones tpm and installs the plugins .tmux.conf declares: the same
#      non-interactive half of tpm that recipes/tmux does on macOS.
#   7. Installs a 'claude' shim in the distro. Claude Code itself stays on the Windows
#      side -- one install, one auth, one session history -- and the shim both puts
#      the name you would type on the PATH and strips the session markers interop
#      would otherwise hand it. The script carries the full explanation; the short
#      version is that an inherited CLAUDE_CODE_CHILD_SESSION silently turns off
#      transcript saving, which would cost exactly the resumability this recipe is for.
#
# Defaults, each overridable with an environment variable:
#   WSL_DISTRO   Ubuntu    any name 'wsl --list --online' offers
#   WSL_USER     the Windows user name, lowercased and stripped to a legal Linux name
#
# Attach with:  wsl -d Ubuntu -- tmux new -A -s main
# Then, inside it, 'claude' is the Windows binary with a clean environment.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')
Assert-Admin 'wsl'

# wsl.exe writes UTF-16LE, which Windows PowerShell 5.1 reads in the ANSI code page:
# every listing comes back as "U b u n t u" with a null between each character, and no
# amount of trimming parses it. WSL_UTF8 makes wsl.exe emit UTF-8 instead. Set here
# before the first call, and persisted at the end for your own shells.
#
# The pre-install stub ignores it, so step 1 on a machine with no WSL prints garbled
# text whatever this says. Everything this recipe parses runs against the real wsl.exe,
# which honours it.
$env:WSL_UTF8 = '1'

$Distro = if ($env:WSL_DISTRO) { $env:WSL_DISTRO } else { 'Ubuntu' }

# A Linux login name starts with a lowercase letter and holds only lowercase letters,
# digits, hyphens and underscores; a Windows account name can hold a space, a dot or a
# capital. Validated rather than trusted, because it is interpolated into the shell
# script below.
$User = if ($env:WSL_USER) { $env:WSL_USER } else { ($env:USERNAME -replace '[^A-Za-z0-9_-]', '').ToLower() }
if ($User -notmatch '^[a-z][a-z0-9_-]{0,31}$') {
  throw "Cannot use '$User' as the distro's login name. Set WSL_USER to a name starting with a lowercase letter."
}

if ($Target -ne $HOME) {
  Write-Host "Note: -Target does not reach inside the distro. Its home directory lives in $Distro, not under $Target."
}

# Runs a bash script inside the distro.
#
# Piped in as base64 rather than passed as arguments: a shell script carries quotes,
# dollars, backslashes and newlines, and anything passed the other way has to survive
# PowerShell's parser, the single Win32 command-line string wsl.exe is handed, and
# bash's own quoting -- three chances to mangle it. Base64 is one argument of
# [A-Za-z0-9+/=] that none of the three can misread. Newlines are normalised to LF for
# the same reason .gitattributes forces LF on this repo: bash reads a CRLF script as
# commands with a stray carriage return attached to each one.
function Invoke-InDistro([string]$Script, [string]$AsUser, [string]$What) {
  $lf = $Script -replace "`r`n", "`n"
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($lf))
  wsl.exe --distribution $Distro --user $AsUser -- bash -c "echo $b64 | base64 --decode | bash"
  Assert-ExitCode $What
}

# True when a command inside the distro succeeds. For questions, not actions, so a
# non-zero exit is an answer -- and must not leak into the next Assert-ExitCode.
function Test-InDistro([string]$Command, [string]$AsUser) {
  wsl.exe --distribution $Distro --user $AsUser -- bash -c $Command | Out-Null
  $ok = ($LASTEXITCODE -eq 0)
  $global:LASTEXITCODE = 0
  return $ok
}

# 1. The platform. WSL 2 runs a real Linux kernel in a light VM, so it needs the
# virtual machine platform as well as the subsystem itself.
#
# Hardware virtualization is checked first because it cannot be fixed from here: it is
# a firmware setting, the same console trip as Secure Boot in
# docs/windows-disk-encryption.md. Only an explicit $false counts -- the property is
# $null on hardware that does not report it, and a hypervisor already running is proof
# enough by itself.
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
if ($cpu.VirtualizationFirmwareEnabled -eq $false -and -not (Get-CimInstance Win32_ComputerSystem).HypervisorPresent) {
  throw 'Hardware virtualization (AMD SVM / Intel VT-x) is off in firmware, and WSL 2 cannot start without it. Turn it on in UEFI setup at the console, then re-run this recipe.'
}

$Features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
function Get-FeatureStates {
  $states = [ordered]@{}
  foreach ($name in $Features) {
    $states[$name] = (Get-WindowsOptionalFeature -Online -FeatureName $name).State
  }
  return $states
}

$states = Get-FeatureStates
if (@($states.Values | Where-Object { $_ -ne 'Enabled' }).Count) {
  Write-Step 'Enabling the WSL platform features'
  foreach ($name in $Features) { Write-Host ('  {0,-36} {1}' -f $name, $states[$name]) }
  # Enabled through DISM rather than "wsl --install", which is all that command does
  # underneath. Until WSL is installed, the wsl.exe in System32 is a stub that accepts
  # only --install, --update, --status and --help: it has no --no-distribution, and it
  # refuses an unknown flag by printing "The Windows Subsystem for Linux is not
  # installed" and exiting 1 -- a message that says nothing about the flag it actually
  # objected to. Its bare --install would bring the default distribution along with the
  # features and launch it, which is the console account prompt this recipe exists to
  # avoid. DISM takes neither liberty.
  foreach ($name in $Features) {
    if ($states[$name] -eq 'Enabled') { continue }
    Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart | Out-Null
    Write-Host "  enabled $name"
  }
  $states = Get-FeatureStates
}
if (@($states.Values | Where-Object { $_ -ne 'Enabled' }).Count) {
  foreach ($name in $Features) { Write-Host ('  {0,-36} {1}' -f $name, $states[$name]) }
  Write-Host ''
  Write-Warning 'The WSL platform needs a restart before it can run. Nothing inside a distro was changed.'
  Write-Host '    Restart, reconnect, and run this recipe again: bin\install.ps1 wsl'
  Write-Host '    A restart drops the SSH session; the Dev Drive remounts itself from its boot task.'
  Write-Host ''
  return
}

# Enabled features are not proof WSL can run. The kernel, and the wsl.exe that
# understands anything beyond the stub's four arguments, ship as a package separate
# from the features -- installed here the same way every other recipe on this side
# installs a tool, rather than by letting the stub's --install choose for us.
wsl.exe --status | Out-Null
if ($LASTEXITCODE -ne 0) {
  $global:LASTEXITCODE = 0
  Install-WingetPackage 'Microsoft.WSL'
  wsl.exe --status | Out-Null
  if ($LASTEXITCODE -ne 0) {
    $global:LASTEXITCODE = 0
    Write-Host ''
    Write-Warning 'The features are enabled and the WSL package is installed, but "wsl --status" still fails, which almost always means the restart has not happened yet.'
    Write-Host '    Restart, reconnect, and run this recipe again: bin\install.ps1 wsl'
    Write-Host ''
    return
  }
}

# 2. The distro.
$listed = @(wsl.exe --list --quiet)
# "no installed distributions" is an answer, not a failure.
$global:LASTEXITCODE = 0
$registered = @($listed | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($registered -notcontains $Distro) {
  Write-Step "Registering $Distro"
  # --no-launch: a distro's first run otherwise asks for a UNIX account name and
  # password on the console. Step 3 creates the user instead, unattended.
  wsl.exe --install --distribution $Distro --no-launch
  Assert-ExitCode "wsl --install --distribution $Distro"
} else {
  Write-Host "$Distro is already registered"
}

# 3 and 4. The user, sudo and tmux. One script, run as root, idempotent throughout.
$provision = @'
set -eu

# The login user, created with no password -- which is only reasonable because of the
# sudoers note below.
if ! id -u __USER__ >/dev/null 2>&1; then
  adduser --quiet --disabled-password --gecos '' __USER__
  usermod -aG sudo __USER__
  echo "created user __USER__"
fi

# Passwordless sudo. WSL draws no privilege boundary between the Windows account and
# root inside the distro: "wsl --user root" needs no password and never will. A sudo
# password here therefore guards nothing that cannot be walked around, while making
# every run of this recipe interactive. Prefer a password? Set one and drop the file:
#   wsl -d <distro> -u root passwd __USER__
#   wsl -d <distro> -u root rm /etc/sudoers.d/90-dotfiles-wsl
sudoers=/etc/sudoers.d/90-dotfiles-wsl
if [ ! -f "$sudoers" ]; then
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' __USER__ > "$sudoers.new"
  chmod 0440 "$sudoers.new"
  # A drop-in sudo cannot parse breaks every later sudo, so it is validated before it
  # moves into place rather than after.
  if visudo -cqf "$sudoers.new"; then
    mv "$sudoers.new" "$sudoers"
    echo "installed $sudoers"
  else
    rm -f "$sudoers.new"
    echo 'refused to install an unparseable sudoers drop-in' >&2
    exit 1
  fi
fi

# The default user for a bare "wsl" command. Read when the distro starts, which is why
# the last step restarts the distro -- but only when this has not taken effect yet,
# since a restart would kill any tmux server running inside.
if [ ! -f /etc/wsl.conf ] || ! grep -q '^\[user\]' /etc/wsl.conf; then
  printf '[user]\ndefault=%s\n' __USER__ >> /etc/wsl.conf
  echo 'set the default user in /etc/wsl.conf'
fi

# tmux, and the git tpm clones plugins with. ca-certificates so that clone can verify
# github.com on a freshly registered distro.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq tmux git ca-certificates
'@ -replace '__USER__', $User

Write-Step "Provisioning ${Distro}: user $User, sudo, tmux"
Invoke-InDistro $provision 'root' "provisioning $Distro"

# 5 and 6. The tmux config and its plugins.
#
# Linked, not copied, so the config has one copy and an edit on the Windows side is
# live inside the distro at the next tmux start. The repo sits on a Windows drive,
# which the distro sees under /mnt -- but that mount is not this recipe's to
# guarantee: D: is ReFS, and which volumes automount is WSL's call. So it is tested
# from inside the distro first, and when the repo is not reachable the recipe links
# nothing and says why, rather than leaving a dangling link behind.
if ($Root -notmatch '^[A-Za-z]:\\') {
  Write-Host ''
  Write-Warning "The repo is at $Root, which has no drive letter, so the distro has no /mnt path for it. Skipped linking ~/.tmux.conf; tmux still runs with its own defaults."
  Write-Host ''
} else {
  $repoInDistro = '/mnt/' + $Root.Substring(0, 1).ToLower() + ($Root.Substring(2) -replace '\\', '/')
  $confInDistro = "$repoInDistro/source/.tmux.conf"
  if (-not (Test-InDistro "test -r '$confInDistro'" $User)) {
    Write-Host ''
    Write-Warning "$Distro cannot read $confInDistro, so ~/.tmux.conf was NOT linked. tmux still runs, with its own defaults."
    Write-Host "    See what is mounted:  wsl -d $Distro -- ls /mnt"
    Write-Host '    A Dev Drive is ReFS. If its letter is missing, try mounting it by hand:'
    Write-Host "      wsl -d $Distro -u root -- mount -t drvfs D: /mnt/d"
    Write-Host '    Failing that, keep a clone inside the distro and link ~/.tmux.conf from there.'
    Write-Host ''
  } else {
    $configure = @'
set -eu
conf="__CONF__"

# An existing real file is kept rather than clobbered, the same .pre-dotfiles
# convention Set-Link uses on the Windows side. An existing link is just re-pointed.
if [ -e "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
  mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.pre-dotfiles"
  echo 'kept the existing ~/.tmux.conf as ~/.tmux.conf.pre-dotfiles'
fi
ln -sfn "$conf" "$HOME/.tmux.conf"
echo "linked ~/.tmux.conf -> $conf"

# tpm and the plugins .tmux.conf declares. The config clones tpm itself, but only
# installs plugins when a human presses prefix + I inside a running server; this is
# the non-interactive half, exactly as recipes/tmux does on macOS. Failures here are
# warnings, not errors: tmux runs fine without its plugins and the next run retries.
tpm="$HOME/.tmux/plugins/tpm"
if [ ! -d "$tpm/.git" ]; then
  mkdir -p "$HOME/.tmux/plugins"
  git clone --quiet https://github.com/tmux-plugins/tpm "$tpm" || echo 'warning: failed to clone tpm'
else
  git -C "$tpm" pull --rebase --quiet || echo 'warning: failed to update tpm; keeping the installed copy'
fi
if [ -x "$tpm/bin/install_plugins" ]; then
  "$tpm/bin/install_plugins" >/dev/null || echo 'warning: some tmux plugins failed to install'
  "$tpm/bin/update_plugins" all >/dev/null || echo 'warning: some tmux plugins failed to update'
fi
'@ -replace '__CONF__', $confInDistro

    Write-Step 'Linking the tmux config and installing its plugins'
    Invoke-InDistro $configure $User 'linking the tmux config'
  }
}

# 7. The claude shim.
#
# Written into the distro rather than linked back to the repo, for the reason step 5
# spells out: /mnt reachability is not this recipe's to guarantee, and a dangling PATH
# entry named "claude" is worse than a copy. The sudoers drop-in and /etc/wsl.conf are
# handled the same way, and like the sudoers file it is syntax-checked before it moves
# into place.
$shim = @'
set -eu
dest=/usr/local/bin/claude
cat > "$dest.new" <<'EOS'
#!/bin/sh
# claude -- run the Windows Claude Code binary from inside this distro with the
# markers of a launching Claude Code session stripped. Installed by recipes/wsl.
#
# Interop resolves Windows executables by extension only, so the command inside the
# distro is claude.exe and a plain "claude" is not found. That much would be a
# symlink. The reason this is a script instead:
#
# WSL does not build an interop process's environment from the Linux one. It restores
# the environment captured from the wsl.exe client that started this distro session.
# When that client is itself a Claude Code tool call -- which it is whenever an agent
# starts the tmux server on your behalf -- every claude.exe launched here inherits
# CLAUDE_CODE_CHILD_SESSION, reads itself as a subprocess, and turns transcript saving
# off. That session cannot then be resumed, which is the one property a detached tmux
# session exists to provide, and the only warning is a single line at startup.
#
# Measured on this machine: the Linux side is clean either way -- pane, shell and tmux
# server all carry nothing -- and only the interop side has them, eleven variables of
# it. WSLENV is the single lever that reaches that side. It takes no wildcard, so the
# names are listed; exporting each empty AND naming it in WSLENV removes it from the
# child outright rather than passing it through blank.
set -eu

MARKERS='CLAUDECODE:CLAUDE_CODE_BRIDGE_SESSION_ID:CLAUDE_CODE_CHILD_SESSION'
MARKERS="$MARKERS:CLAUDE_CODE_ENTRYPOINT:CLAUDE_CODE_EXECPATH"
MARKERS="$MARKERS:CLAUDE_CODE_MESSAGING_SOCKET:CLAUDE_CODE_MESSAGING_TOKEN"
MARKERS="$MARKERS:CLAUDE_CODE_SESSION_ATTENDED:CLAUDE_CODE_SESSION_ID"
MARKERS="$MARKERS:CLAUDE_EFFORT:CLAUDE_PID"

IFS=':'
for v in $MARKERS; do export "$v="; done
unset IFS
# Appended rather than assigned: an existing WSLENV may be carrying something wanted.
export WSLENV="${WSLENV:+$WSLENV:}$MARKERS"

# Resolved at run time rather than baked in, so a Windows install that moves, or
# arrives later, needs no reinstall of this file.
if ! command -v claude.exe >/dev/null 2>&1; then
  echo 'claude: claude.exe is not on PATH inside this distro.' >&2
  echo '  Claude Code runs from the Windows side here. Check that it is installed' >&2
  echo '  there, and that interop is on ([interop] enabled=true in /etc/wsl.conf).' >&2
  exit 127
fi

exec claude.exe "$@"
EOS
chmod 0755 "$dest.new"
if sh -n "$dest.new"; then
  mv "$dest.new" "$dest"
  echo "installed $dest"
else
  rm -f "$dest.new"
  echo 'refused to install an unparseable claude shim' >&2
  exit 1
fi
'@

Write-Step 'Installing the claude shim'
Invoke-InDistro $shim 'root' 'installing the claude shim'

# Check what a fresh wsl call actually gets rather than assuming the steps above added
# up -- and restart the distro only if it needs it.
#
# /etc/wsl.conf is read when the distro starts, so the default user set in step 3 does
# not apply until it restarts: a first run has to. A re-run almost never does, and
# terminating is not free -- it kills every process inside the distro, which means any
# tmux server and the sessions it is holding, the one thing this recipe exists to keep
# alive. Re-running is also the documented way to resume after step 1's restart, so it
# has to be safe to do while you have work open. Hence: ask first, restart only when
# the answer is wrong.
Write-Step "Verifying $Distro"
# Captured into an array, never piped into Select-Object -First. That stops the
# upstream pipeline as soon as it has its one object, which kills the native command
# mid-flight: wsl.exe then reports exit -1 even though it did exactly what was asked,
# and Assert-ExitCode fails the whole recipe on a successful call. Measured both ways
# on this machine -- piped: exit -1, captured: exit 0, same output either way.
$whoLines = @(wsl.exe --distribution $Distro -- whoami)
Assert-ExitCode "wsl -d $Distro -- whoami"
$who = if ($whoLines.Count) { "$($whoLines[0])".Trim() } else { '' }
if ($who -ne $User) {
  Write-Host "  a bare 'wsl -d $Distro' lands as '$who'; restarting so /etc/wsl.conf applies"
  wsl.exe --terminate $Distro | Out-Null
  $global:LASTEXITCODE = 0
  $whoLines = @(wsl.exe --distribution $Distro -- whoami)
  Assert-ExitCode "wsl -d $Distro -- whoami"
  $who = if ($whoLines.Count) { "$($whoLines[0])".Trim() } else { '' }
} else {
  Write-Host '  the default user is already live, so the distro was left running'
}
$versionLines = @(wsl.exe --distribution $Distro -- tmux -V)
Assert-ExitCode "wsl -d $Distro -- tmux -V"
$version = if ($versionLines.Count) { "$($versionLines[0])".Trim() } else { '' }
Write-Host "  default user: $who"
Write-Host "  tmux:         $version"
if ($who -ne $User) {
  Write-Warning "A bare 'wsl -d $Distro' still lands as '$who', not '$User', after a restart. Check the [user] section of /etc/wsl.conf."
}

# See the note at the top of this file: wsl.exe's UTF-16LE output is unreadable in
# Windows PowerShell 5.1, so pin the variable for your own shells too, the same way
# other recipes pin tool state with Set-UserEnv. A user environment variable is
# machine-wide with no per-target equivalent, so a -Target run reports it instead.
if ($Target -eq $HOME) {
  Set-UserEnv 'WSL_UTF8' '1'
} else {
  Write-Host 'Would set WSL_UTF8=1 (skipped: -Target run, and the user environment is machine-wide)'
}

Write-Host ''
Write-Step 'tmux over SSH'
Write-Host "  Attach, creating it if needed:  wsl -d $Distro -- tmux new -A -s main"
Write-Host "  List what is running:           wsl -d $Distro -- tmux ls"
Write-Host "  Inside the session:             claude"
Write-Host ''
Write-Host '  The server runs in the WSL VM rather than in the SSH session, so a dropped'
Write-Host '  connection leaves it alone: reconnect and run the same command to reattach.'
Write-Host '  It does not survive a restart or "wsl --shutdown" -- after either, start a'
Write-Host '  session and restore the saved tree with prefix + Ctrl-r (tmux-resurrect).'
Write-Host ''
Write-Host "  Run 'claude', not 'claude.exe'. Both reach the same Windows binary, but only"
Write-Host '  the shim clears the session markers interop hands it. Called directly, a'
Write-Host '  session started inside a tmux server that an agent created reports'
Write-Host '  "Transcript saving is off" at startup and cannot afterwards be resumed.'
Write-Host ''
