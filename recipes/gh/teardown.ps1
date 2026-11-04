# Uninstalls the GitHub CLI. Logins (in Windows Credential Manager), ~\.config\gh and
# the GH_CONFIG_DIR user variable are kept, so a reinstall picks up where it left off.
# Run `gh auth logout` first to remove a login as well.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

if (-not (Confirm-Action 'Uninstall the GitHub CLI?')) {
  Write-Host 'Skipped.'
  return
}
Uninstall-WingetPackage -Id 'GitHub.cli'
