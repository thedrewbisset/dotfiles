<#
.SYNOPSIS
  Windows counterpart of bin/teardown.sh: runs recipes/<name>/teardown.ps1.

.EXAMPLE
  bin\teardown.ps1 git
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Recipe,
  [string]$Target = $HOME
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'bin\lib\tools.ps1')

# Reverse install order. Recipes whose teardown is destructive enough to want
# deliberate, one-at-a-time use are left out of 'all'.
$All = @()

$Recipes = @('claude', 'hooks', 'uv', 'gh', 'dotfiles', 'git', 'wsl', 'devdrive', 'openssh-server')

if (-not $Recipe) { Write-Host 'Usage: bin\teardown.ps1 [-Target <dir>] <recipe|all>'; exit 1 }

$run = if ($Recipe -eq 'all') { $All } else { @($Recipe) }
foreach ($name in $run) {
  if ($Recipes -notcontains $name) { Write-Host "Unknown recipe: $name"; exit 1 }
}
if ($Recipe -eq 'all' -and $All.Count -eq 0) {
  Write-Host "Nothing in teardown 'all' yet. Tear down recipes individually: $($Recipes -join ', ')"
}

$env:TARGET_HOME = $Target
foreach ($name in $run) {
  Write-Step "Teardown: $name"
  & (Join-Path $Root "recipes\$name\teardown.ps1") -Root $Root -Target $Target
}
