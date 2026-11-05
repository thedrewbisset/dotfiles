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

# 3. The dev root. The letter follows the devdrive recipe's DEVDRIVE_LETTER so the
# two cannot disagree.
$letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
$devRoot = "${letter}:\src"
# A user environment variable is machine-wide, with no per-target equivalent, so a
# -Target run reports it rather than writing it -- the same reason the gh recipe uses
# `git config --file` over `--global`.
if ($Target -eq $HOME) {
  Set-UserEnv 'DEV_ROOT' $devRoot
} else {
  Write-Host "Would set DEV_ROOT=$devRoot (skipped: -Target run, and the user environment is machine-wide)"
}
if (-not (Test-Path -LiteralPath $devRoot)) {
  Write-Warning "DEV_ROOT is $devRoot, which does not exist yet. Create the Dev Drive with an elevated: bin\install.ps1 devdrive. The profile skips the cd until it is there."
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
New-Item -ItemType Directory -Force (Split-Path -Parent $profileLink) | Out-Null
Set-Link (Join-Path $Root 'source\windows\profile.ps1') $profileLink
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
      Write-Host "    Fix: copy source\$(Split-Path -Leaf $template) to source\$base, fill it in, then re-run this recipe."
    } else {
      Write-Host "    Fix: create $m with the identity it should supply."
    }
  }
  # On this side the routed directories are on the Dev Drive, so an includeIf copied
  # from the macOS machine needs Windows paths: gitdir:D:/src/... , forward slashes.
  Write-Host '    Note: includeIf gitdir: patterns need this machine''s paths, e.g. gitdir:D:/src/work/.'
  Write-Host ''
}
