# Undoes recipes/fnm: uninstalls fnm and clears the variables that pinned it.
#
# The installed Node versions and npm's cache are a separate, second confirmation, for
# the same reason as the model weights in recipes/ollama: they are the part that costs
# time to get back, and a re-run of the install recipe recreates everything else in
# seconds. Globally installed npm packages live inside a Node version, so deleting the
# versions takes those with it.
#
# Kept: the Dev Drive's caches\ directory itself, which belongs to the drive's layout
# (see recipes/devdrive), not to this recipe. The fnm block in profile.ps1 is also
# left alone -- it is guarded on fnm being present, so it goes quiet by itself, and the
# file belongs to recipes/dotfiles.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

# Read the pinned locations before Remove-UserEnv clears the variables that name them.
$letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
$FnmDir = if ($env:FNM_DIR) { $env:FNM_DIR } else { "${letter}:\caches\fnm" }
$NpmCache = if ($env:npm_config_cache) { $env:npm_config_cache } else { "${letter}:\caches\npm" }

$installed = [bool](Get-Command fnm -ErrorAction SilentlyContinue)
$vars = @('FNM_DIR', 'npm_config_cache', 'COREPACK_HOME')
$setVars = @($vars | Where-Object { $null -ne [Environment]::GetEnvironmentVariable($_, 'User') })
$dirs = @($FnmDir, $NpmCache) | Where-Object { Test-Path -LiteralPath $_ }

if (-not $installed -and -not $setVars.Count -and -not $dirs.Count) {
  Write-Host 'fnm is not installed, no variables are set, and there is nothing on disk; nothing to do.'
  return
}

if (-not (Confirm-Action 'Remove fnm and clear its settings?')) {
  Write-Host 'Skipped.'
  return
}

if ($installed) {
  Uninstall-WingetPackage -Id 'Schniz.fnm'
} else {
  Write-Host 'fnm is not on PATH; skipping the uninstall.'
}

foreach ($name in $vars) { Remove-UserEnv $name }

# The per-shell junction directories fnm creates on every shell start. Not under
# FNM_DIR -- fnm puts them in %LOCALAPPDATA% regardless -- and dead as soon as the
# shell that made one exits, so they go unconditionally rather than on a prompt.
$multishells = Join-Path $env:LOCALAPPDATA 'fnm_multishells'
if (Test-Path -LiteralPath $multishells) {
  Remove-Item -LiteralPath $multishells -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "Removed $multishells"
}

if (-not $dirs.Count) {
  Write-Host 'fnm removed.'
  return
}

# Sized first: the number is what makes this decision, and a prompt that does not show
# it is asking the question without the facts.
Write-Host ''
foreach ($dir in $dirs) {
  $sum = (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
  if (-not $sum) { $sum = 0 }
  Write-Host ('{0,-40} {1,8:N0} MB' -f $dir, ($sum / 1MB))
}
if (Confirm-Action 'Delete the Node versions and npm cache too? (re-downloading takes a while)') {
  foreach ($dir in $dirs) {
    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Host "Removed $dir"
  }
} else {
  Write-Host 'Left alone. A later bin\install.ps1 fnm will find them and re-download nothing.'
}
Write-Host 'fnm removed.'
