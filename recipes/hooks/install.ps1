# Points this clone's git hooks at the tracked hooks/ directory (Windows counterpart
# of recipes/hooks/install). The hooks are bash; Git for Windows runs them with its
# own bash, so they are shared as-is. They need a real python3 (recipes/uv).
#
# Fails rather than warns, like scripts/install-hooks.sh: a clone silently without
# the privacy gate is the case this exists to prevent.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

git -C $Root config core.hooksPath hooks
Assert-ExitCode 'git config core.hooksPath'

# The WindowsApps python3 stub exists but only prints a Store message, so test that
# python3 actually runs instead of that it is on PATH.
# (Scoped 'Continue': under 'Stop', 5.1 turns redirected native stderr into a throw.)
$runs = & {
  $ErrorActionPreference = 'Continue'
  python3 -c "import sys" 2>$null | Out-Null
  $LASTEXITCODE -eq 0
}
if (-not $runs) {
  throw 'python3 does not run, so the hooks would refuse every commit. Run bin\install.ps1 uv first.'
}
$active = (Get-ChildItem (Join-Path $Root 'hooks') -File | Select-Object -ExpandProperty Name) -join ' '
Write-Host "core.hooksPath -> hooks/ (active: $active)"
