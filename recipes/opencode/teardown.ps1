# Undoes recipes/opencode: uninstalls the OpenCode CLI.
#
# Its state is a separate, second confirmation. OpenCode keeps sessions, credentials
# and a cache of a couple of hundred MB under the home directory, and sessions are the
# part a re-install does not bring back -- so removing the tool and removing its
# history are two different decisions, as with the model weights in recipes/ollama.
#
# Nothing here touches the ollama server or its models: OpenCode only ever read them.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$installed = [bool](Get-Command opencode -ErrorAction SilentlyContinue)
# XDG-shaped, which is where OpenCode puts these on Windows too, rather than AppData.
$stateDirs = @(
  (Join-Path $HOME '.config\opencode'),
  (Join-Path $HOME '.local\share\opencode'),
  (Join-Path $HOME '.cache\opencode')
)
$present = @($stateDirs | Where-Object { Test-Path -LiteralPath $_ })

if (-not $installed -and -not $present.Count) {
  Write-Host 'opencode is not installed and has left no state; nothing to do.'
  return
}

if (-not (Confirm-Action 'Remove the OpenCode CLI?')) {
  Write-Host 'Skipped.'
  return
}

if ($installed) {
  Uninstall-WingetPackage -Id 'Anomaly.OpenCode'
} else {
  Write-Host 'opencode is not on PATH; skipping the uninstall.'
}

if (-not $present.Count) {
  Write-Host 'opencode removed.'
  return
}

# Sized first: the number is what makes this decision, and a prompt that does not show
# it is asking the question without the facts.
$bytes = 0
foreach ($dir in $present) {
  $sum = (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
  if ($sum) { $bytes += $sum }
}
Write-Host ''
Write-Host ('Sessions, credentials and cache use {0:N0} MB:' -f ($bytes / 1MB))
foreach ($dir in $present) { Write-Host "  $dir" }
if (Confirm-Action 'Delete them too?') {
  foreach ($dir in $present) {
    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Host "Removed $dir"
  }
} else {
  Write-Host 'Left alone. A later bin\install.ps1 opencode will find them again.'
}
Write-Host 'opencode removed.'
