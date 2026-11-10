# Links the dotfiles Windows actually reads, and makes the Dev Drive the dev root
# (Windows counterpart of recipes/dotfiles/install).
#
# Only three of the files in source/ apply here:
#   .gitconfig           aliases, excludesfile, identity routing: all platform-neutral
#   .git-excludes-file   referenced by .gitconfig's core.excludesfile
#   .ssh/config          host aliases, shared with Windows' own OpenSSH
# Everything else belongs to a tool this side does not have -- zsh, oh-my-zsh, tmux,
# ruby, psql, bats, paperclip, vim -- and parity with macOS is not a goal (CLAUDE.md).
# .claude is skipped for the same reason as on macOS: it is Claude Code's live home,
# holding runtime state, not config to link.
#
# Plus one Windows-only file with no macOS counterpart: source/windows/profile.ps1,
# linked to the PowerShell profile. It is what makes an SSH login land in the dev
# root, since sshd has no working-directory option and drops you in %USERPROFILE%.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

# 1. Can this session create links at all? Checked before anything is written, so a
# shell without the privilege cannot leave half the files linked.
if (-not (Test-CanSymlink $Target (Join-Path $Root 'README.md'))) {
  throw ('Cannot create symlinks as this user. Creating one needs ' +
    'SeCreateSymbolicLinkPrivilege, which only Administrators hold, and UAC strips it ' +
    'from a local interactive shell. Run this over SSH, whose logon keeps it, or from ' +
    'an elevated PowerShell (Run as administrator).')
}

# 2. The dotfiles themselves.
$Links = [ordered]@{
  '.gitconfig'         = 'source\.gitconfig'
  '.git-excludes-file' = 'source\.git-excludes-file'
}
foreach ($name in $Links.Keys) {
  Set-Link (Join-Path $Root $Links[$name]) (Join-Path $Target $name)
}

# ~/.ssh holds private keys, so this never overwrites a real config: a machine that
# already has one keeps it, exactly as the macOS recipe does. An existing link is
# still re-pointed, so the recipe stays idempotent.
$sshDir = Join-Path $Target '.ssh'
if (-not (Test-Path $sshDir)) {
  New-Item -ItemType Directory -Force $sshDir | Out-Null
  Write-Host "Created $sshDir"
}
$sshConfig = Join-Path $sshDir 'config'
if ((Test-Path -LiteralPath $sshConfig) -and -not (Get-LinkTarget $sshConfig)) {
  Write-Host 'SSH config already exists, skipping to preserve existing setup'
} else {
  Set-Link (Join-Path $Root 'source\.ssh\config') $sshConfig
}

# 2b. Keys the SSH config names but this machine does not have.
#
# Every host entry pins a key with IdentitiesOnly, so a missing key does not fall back
# to whatever the agent holds: the clone just fails with "Permission denied (publickey)"
# much later, with nothing pointing back here. Keys are generated per machine and never
# committed (README, SSH key setup), so this warns rather than fails.
if (Test-Path -LiteralPath $sshConfig) {
  $missingKeys = [ordered]@{}
  foreach ($line in Get-Content -LiteralPath $sshConfig) {
    if ($line -notmatch '^\s*IdentityFile\s+(.+?)\s*$') { continue }
    $ref = $Matches[1].Trim('"')
    # -replace rather than TrimStart(char[]): one regex, no character-literal quoting.
    $keyPath = if ($ref.StartsWith('~')) { Join-Path $Target ($ref.Substring(1) -replace '^[\\/]+', '') } else { $ref }
    if (-not (Test-Path -LiteralPath $keyPath)) { $missingKeys[$ref] = $keyPath }
  }
  if ($missingKeys.Count) {
    Write-Host ''
    Write-Warning 'SSH keys named by .ssh/config are not on this machine. A git remote that uses one fails with "Permission denied (publickey)", and IdentitiesOnly means ssh will not try another key from the agent instead.'
    foreach ($ref in $missingKeys.Keys) { Write-Host "  $ref" }
    Write-Host '    Fix: ssh-keygen -t ed25519 -f <path> -C "<comment>", then add the .pub file to the matching GitHub account (README, SSH key setup).'
    Write-Host '    HTTPS remotes are unaffected: they authenticate through gh.'
    Write-Host ''
  }
}

# 3. The dev root, in order of precedence:
#   DEV_ROOT         an explicit choice, and the only way to say "no Dev Drive on this
#                    machine": a box that keeps its repos in a plain folder sets this
#                    once and the recipe keeps it, re-runs included.
#   DEVDRIVE_LETTER  follows the devdrive recipe, so the drive and the dev root cannot
#                    disagree about the letter.
#   D:\src           the default both recipes assume.
$letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
$fromLetter = "${letter}:\src"
$devRoot = $fromLetter
$rootSource = if ($env:DEVDRIVE_LETTER) { 'DEVDRIVE_LETTER' } else { 'the default' }
if ($env:DEV_ROOT) {
  # Trimmed: Set-Location -LiteralPath rejects a trailing space where Test-Path accepts
  # it, so a stray one in the variable would put an error in front of every login. The
  # length guard keeps a drive root ("D:\") whole while dropping "D:\src\" to "D:\src".
  $devRoot = $env:DEV_ROOT.Trim()
  if ($devRoot.Length -gt 3) { $devRoot = $devRoot.TrimEnd('\', '/') }
  $rootSource = 'DEV_ROOT'
  if ($devRoot -ne $fromLetter) {
    Write-Host "Dev root: $devRoot (from DEV_ROOT; DEVDRIVE_LETTER would give $fromLetter)"
  }
}
# A user environment variable is machine-wide, with no per-target equivalent, so a
# -Target run reports it rather than writing it -- the same reason the gh recipe uses
# `git config --file` over `--global`.
if ($Target -eq $HOME) {
  Set-UserEnv 'DEV_ROOT' $devRoot
} else {
  Write-Host "Would set DEV_ROOT=$devRoot (skipped: -Target run, and the user environment is machine-wide)"
}
if (-not (Test-Path -LiteralPath $devRoot)) {
  Write-Warning "The dev root $devRoot (from $rootSource) does not exist, so the profile skips its cd until it does. Either create the Dev Drive with an elevated: bin\install.ps1 devdrive -- or, to keep repos in a plain folder instead, set DEV_ROOT to that folder (setx DEV_ROOT <path>, then a new shell) and re-run this recipe."
}

# 4. The PowerShell profile.
#
# $PROFILE rather than a path built by hand: Documents is often redirected into
# OneDrive, and only PowerShell knows where it ended up. Under -Target that lookup
# would point at the real home directory, so a test run uses the layout instead.
# CurrentUserAllHosts (profile.ps1) is the one every host loads, SSH logins included.
$profileLink = if ($Target -eq $HOME) {
  $PROFILE.CurrentUserAllHosts
} else {
  Join-Path $Target 'Documents\WindowsPowerShell\profile.ps1'
}
# Nothing from this repo goes into a OneDrive-backed folder. With Known Folder Move on
# for Documents, $PROFILE lands inside OneDrive, and a link there is either skipped with
# a sync error or followed -- uploading the file and handing every other machine on the
# account a stale real copy of it. Where Documents points is not this recipe's to
# change, so it reports the problem and links nothing; the rest is already done.
$oneDriveRoots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ }
$inOneDrive = @($oneDriveRoots | Where-Object { $profileLink -like (Join-Path $_ '*') }).Count -gt 0
if (-not $inOneDrive) { $inOneDrive = $profileLink -like '*\OneDrive\*' }
if ($inOneDrive) {
  Write-Host ''
  Write-Warning "The PowerShell profile path is inside OneDrive ($profileLink), so it was NOT linked. OneDrive either skips a symlink with a sync error or follows it and uploads the file, which hands every other machine on the account a stale copy."
  Write-Host '    Fix: in OneDrive, Settings > Sync and backup > Manage backup, turn Documents off; move what you want to keep back to %USERPROFILE%\Documents; then re-run this recipe.'
  Write-Host '    Until then an SSH login starts in the home directory rather than the dev root.'
  Write-Host ''
} else {
  New-Item -ItemType Directory -Force (Split-Path -Parent $profileLink) | Out-Null
  Set-Link (Join-Path $Root 'source\windows\profile.ps1') $profileLink
}
# PowerShell 7 reads Documents\PowerShell\profile.ps1 instead. Nothing installs it
# here, and sshd launches Windows PowerShell, so only 5.1's profile is linked.

# 5. Identity routing. git ignores a missing include silently: no warning, nothing in
# `git config` output, and the first symptom is a commit under the wrong name or a
# push as the wrong account. Same check as check_git_includes in bin/lib/tools.
$gitconfig = Join-Path $Target '.gitconfig'
$missing = @()
$scan = @($gitconfig)
# Two levels: .gitconfig, then the routing file it names. Identity files include
# nothing further.
foreach ($level in 1, 2) {
  $nested = @()
  foreach ($file in $scan) {
    if (-not (Test-Path -LiteralPath $file)) { continue }
    foreach ($line in Get-Content -LiteralPath $file) {
      if ($line -notmatch '^\s*path\s*=\s*(.+?)\s*$') { continue }
      $path = $Matches[1]
      if ($path.StartsWith('~')) { $path = Join-Path $Target $path.Substring(1).TrimStart('/', '\') }
      if (Test-Path -LiteralPath $path) { $nested += $path }
      elseif ($missing -notcontains $path) { $missing += $path }
    }
  }
  if (-not $nested) { break }
  $scan = $nested
}
if ($missing.Count) {
  Write-Host ''
  Write-Warning 'git identity files referenced by .gitconfig are missing. Git ignores these includes silently: commits in the directories they cover use the DEFAULT identity, and pushes may authenticate as the wrong account.'
  foreach ($m in $missing) {
    Write-Host "  $m"
    $base = Split-Path -Leaf $m
    $template = Join-Path $Root "source\$base.example"
    if (-not (Test-Path -LiteralPath $template) -and $base -like '.gitconfig-*') {
      $template = Join-Path $Root 'source\.gitconfig-identity.example'
    }
    if (Test-Path -LiteralPath $template) {
      # To the home path, not into source\: the macOS recipe links everything in
      # source/, so a copy left there becomes ~/<name>, but this one links a fixed list
      # and never links identity files. Git reads the copy as soon as it exists, so
      # there is nothing to re-run either.
      Write-Host "    Fix: copy source\$(Split-Path -Leaf $template) to $m and fill it in."
    } else {
      Write-Host "    Fix: create $m with the identity it should supply."
    }
  }
  # On this side the routed directories are on the Dev Drive, so an includeIf copied
  # from the macOS machine needs Windows paths: gitdir:D:/src/... , forward slashes.
  Write-Host '    Note: includeIf gitdir: patterns need this machine''s paths, e.g. gitdir:D:/src/work/.'
  Write-Host ''
}
