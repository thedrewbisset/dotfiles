# Undoes recipes/claude: removes the Claude Code CLI that Anthropic's installer put
# in ~\.local\bin, along with the builds and install locks it keeps beside it.
# macOS has no counterpart (bin/teardown.sh says so for claude): there the CLI is
# all the recipe installs, and the same is true here, but on Windows there is no
# package manager to hand the uninstall to.
#
# Never touched: ~\.claude and ~\.claude.json, which are Claude Code's live state
# (sessions, project history, settings), and agent configuration, which lives in
# its own repository with its own installer. ~\.local\bin stays on the PATH because
# the uv shims live there too.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$exe = Join-Path $Target '.local\bin\claude.exe'
$builds = Join-Path $Target '.local\share\claude'
$locks = Join-Path $Target '.local\state\claude'

if (-not (Test-Path $exe) -and -not (Test-Path $builds)) {
  Write-Host 'The Claude Code CLI is not installed here; nothing to do.'
  return
}

# Windows locks a running .exe, so a session running from this binary -- including
# one this teardown was started from -- would make the delete fail halfway.
$running = Get-Process claude -ErrorAction SilentlyContinue
if ($running) {
  throw "Claude Code is running (PID $($running.Id -join ', ')). Windows locks a running .exe: close every session, including any this shell is inside, and run this from a plain PowerShell."
}

Write-Host "Removes $exe and its builds. Your sessions, settings and project"
Write-Host "history in $(Join-Path $Target '.claude') are kept."
if (-not (Confirm-Action 'Remove the Claude Code CLI?')) {
  Write-Host 'Skipped.'
  return
}

foreach ($path in @($exe, $builds, $locks)) {
  if (Test-Path $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
    Write-Host "Removed $path"
  }
}
Update-SessionPath
Write-Host 'Claude Code CLI removed. Reinstall any time with: bin\install.ps1 claude'
