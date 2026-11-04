# Installs (or upgrades) the GitHub CLI via winget and offers to log in
# (Windows counterpart of the `gh` entry in recipes/homebrews/install).
#
# gh's Windows default config dir is %APPDATA%\GitHub CLI; it is pinned to
# ~\.config\gh, the path gh uses on macOS (see Set-UserEnv for why AppData is
# avoided). The auth token itself goes to Windows Credential Manager, not that dir.
#
# Not done here: `gh auth setup-git`. It writes a credential helper into
# ~/.gitconfig, which on macOS is a symlink to source/.gitconfig (whose helper path
# is Homebrew's). Clones use the SSH host aliases from source/.ssh/config, and Git
# for Windows ships its own credential manager for any HTTPS remotes.
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
