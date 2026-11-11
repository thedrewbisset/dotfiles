<#
.SYNOPSIS
  Windows counterpart of bin/install.sh: runs recipes/<name>/install.ps1.

.EXAMPLE
  bin\install.ps1 all
  bin\install.ps1 git
  bin\install.ps1 -Target $env:TEMP\test-home git

.NOTES
  Windows recipes live beside the bash ones as install.ps1 / teardown.ps1, so neither
  platform's installer sees the other's files. The Windows 'all' list is its own and
  only grows when a recipe is actually needed here: parity is not a goal.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Recipe,
  # Alternate home directory, mirroring install.sh --target.
  [string]$Target = $HOME
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'bin\lib\tools.ps1')
# A shell opened before an earlier recipe changed PATH still has the old value.
Update-SessionPath

# Recipes run by 'all', in order.
$All = @('git', 'dotfiles', 'gh', 'uv', 'fnm', 'hooks', 'claude')

# Every Windows recipe, with its help text. Opt-in recipes are listed here but not in $All.
$Recipes = [ordered]@{
  git   = 'Install Git for Windows via winget (LF-safe, uses Windows OpenSSH)'
  # Needs to create symlinks: run it over SSH or from an elevated shell.
  dotfiles = 'Link the dotfiles Windows reads and make the Dev Drive the dev root'
  gh    = 'Install the GitHub CLI via winget and offer to log in'
  uv    = 'Install uv and a uv-managed Python (provides python3 for the hooks)'
  # After dotfiles, which links the profile that puts node on PATH.
  fnm   = 'Install fnm and Node, versions and npm cache on the Dev Drive'
  hooks = 'Enable the privacy gate git hooks'
  claude = 'Install the Claude Code CLI (agent config is managed elsewhere)'
  # Opt-in: creates a disk, and normally runs once before the repo moves onto it.
  devdrive = 'Create the Dev Drive (ReFS virtual disk) and its layout (run elevated)'
  # Opt-in: opens a network service, so it is never installed as a side effect of 'all'.
  'openssh-server' = 'LAN-only, key-only SSH server (run elevated)'
  # Opt-in: downloads several GB of model weights. Wants the Dev Drive to exist first.
  ollama = 'Install ollama, weights pinned to the Dev Drive, with the models this GPU can hold'
  # Opt-in: tools for a particular kind of work, not part of bootstrapping a machine.
  opencode = 'Install the OpenCode CLI, a second agentic harness for the local models'
  # After fnm: a global npm install.
  pi    = 'Install Pi and point it at the local models (the leanest prompt of the three)'
}

function Show-Usage {
  Write-Host 'Usage: bin\install.ps1 [-Target <dir>] <recipe|all>'
  Write-Host ''
  Write-Host 'Recipes:'
  Write-Host ('  {0,-16}Run all recipes in order ({1})' -f 'all', ($All -join ', '))
  foreach ($name in $Recipes.Keys) {
    $optIn = if ($All -contains $name) { '' } else { " (not in 'all')" }
    Write-Host ('  {0,-16}{1}{2}' -f $name, $Recipes[$name], $optIn)
  }
  Write-Host ''
  Write-Host 'Options:'
  Write-Host '  -Target <dir>  Install to an alternate home directory'
}

if (-not $Recipe) { Show-Usage; exit 1 }
if ($Recipe -in @('help', '-h', '--help')) { Show-Usage; exit 0 }

$run = if ($Recipe -eq 'all') { $All } else { @($Recipe) }
foreach ($name in $run) {
  if (-not $Recipes.Contains($name)) { Write-Host "Unknown recipe: $name"; exit 1 }
}

if ($Target -ne $HOME) {
  Write-Host "Installing to target: $Target"
  New-Item -ItemType Directory -Force $Target | Out-Null
}
$env:TARGET_HOME = $Target

foreach ($name in $run) {
  Write-Step "Recipe: $name"
  & (Join-Path $Root "recipes\$name\install.ps1") -Root $Root -Target $Target
}
