# Uninstalls Git for Windows. Repositories and ~/.gitconfig are left alone.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

if (-not (Confirm-Action 'Uninstall Git for Windows? (this repo will need it to pull again)')) {
  Write-Host 'Skipped.'
  return
}
Uninstall-WingetPackage -Id 'Git.Git'
