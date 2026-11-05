# Installs (or upgrades) the GitHub CLI via winget and offers to log in
# (Windows counterpart of the `gh` entry in recipes/homebrews/install).
#
# gh's Windows default config dir is %APPDATA%\GitHub CLI; it is pinned to
# ~\.config\gh, the path gh uses on macOS (see Set-UserEnv for why AppData is
# avoided). The auth token itself goes to Windows Credential Manager, not that dir.
#
# Clones use the SSH host aliases from source/.ssh/config. The credential helper
# written at the end is for HTTPS remotes, which is what a clone made before those
# aliases exist ends up with -- including this repo's own, on a fresh machine.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

Set-UserEnv 'GH_CONFIG_DIR' (Join-Path $HOME '.config\gh')

Install-WingetPackage -Id 'GitHub.cli'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw 'gh is not on PATH after install. Open a new shell and re-run.'
}
Write-Host ((gh --version) | Select-Object -First 1)

# Exit code 1 means not logged in (or a stored token is no longer valid).
gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -eq 0) {
  Write-Host 'gh is already authenticated to github.com:'
  gh auth status --hostname github.com
} elseif (Confirm-Action 'Log gh in to github.com now? (opens a browser / device code)') {
  # SSH protocol to match the SSH remotes; gh may offer to upload a public key.
  gh auth login --hostname github.com --git-protocol ssh --web
  Assert-ExitCode 'gh auth login'
} else {
  Write-Host 'Skipping login. Run later: gh auth login --hostname github.com --git-protocol ssh --web'
}

# HTTPS credentials come from gh, not the Git Credential Manager.
#
# A key-based SSH logon session cannot reach Windows Credential Manager, so GCM fails
# with "Unable to persist credentials with the 'wincredman' credential store" and git
# has no tty to fall back to prompting on: a push just dies with "could not read
# Username". gh holds its own token, so it can answer where GCM cannot.
#
# The empty helper first resets the list, which drops the system gitconfig's `manager`
# for these hosts only -- every other host keeps GCM. That mirrors the block
# `gh auth setup-git` leaves at the end of source/.gitconfig on macOS, except the
# helper is a bare `gh`: setup-git hardcodes an absolute path (the macOS copy still
# names Homebrew's), and a winget install path moves on upgrade.
#
# --file rather than --global so -Target stays honoured; `git config --global` would
# write the real home directory during a test run.
#
# The reset value is '""' and not '': PowerShell 5.1 drops an empty-string argument to
# a native command altogether, so git would see two arguments instead of three and
# fail with "wrong number of arguments". '""' reaches git as the empty value.
$gitconfig = Join-Path $Target '.gitconfig'
$existing = Get-Item -LiteralPath $gitconfig -Force -ErrorAction SilentlyContinue
if ($existing -and $existing.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
  # A Windows `dotfiles` recipe would link this to source/.gitconfig, as on macOS.
  # That file is tracked in a public repo, and this is machine-local configuration.
  Write-Warning ("$gitconfig is a link, so the gh credential helper was not written. " +
    'It points at a tracked file (source/.gitconfig on macOS) and this is ' +
    "machine-local configuration, so set it per clone instead: git config " +
    "credential.https://github.com.helper '!gh auth git-credential'")
}
else {
  foreach ($hostUrl in 'https://github.com', 'https://gist.github.com') {
    git config --file $gitconfig --replace-all "credential.$hostUrl.helper" '""'
    Assert-ExitCode "git config credential.$hostUrl.helper"
    git config --file $gitconfig --add "credential.$hostUrl.helper" '!gh auth git-credential'
    Assert-ExitCode "git config --add credential.$hostUrl.helper"
  }
  Write-Host "git will use gh for HTTPS credentials on github.com ($gitconfig)."
  Write-Host 'Other hosts keep the Git Credential Manager.'
}
