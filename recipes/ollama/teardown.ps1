# Undoes recipes/ollama: stops the server, uninstalls ollama, and clears the OLLAMA_*
# user variables the install recipe set.
#
# The weights are a separate, second confirmation. They are the expensive part -- tens
# of GB and a long download -- and they are the one thing here that is not recreated
# by re-running the install recipe in a few seconds, so removing the tool and removing
# its models are deliberately two different decisions.
#
# Kept: the Dev Drive's models\ directory itself, which belongs to the drive's layout
# (see recipes/devdrive), not to this recipe.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$Port = 11434

function Test-OllamaUp {
  $client = New-Object Net.Sockets.TcpClient
  try {
    $client.Connect('127.0.0.1', $Port)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

# Read where the install recipe pinned the weights before Remove-UserEnv clears the
# variable that says so. The fallback is that recipe's default.
$letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
$ModelRoot = if ($env:OLLAMA_MODELS) { $env:OLLAMA_MODELS } else { "${letter}:\models\ollama" }

$installed = [bool](Get-Command ollama -ErrorAction SilentlyContinue)
$vars = @('OLLAMA_MODELS', 'OLLAMA_FLASH_ATTENTION', 'OLLAMA_KV_CACHE_TYPE',
  'OLLAMA_MAX_LOADED_MODELS', 'OLLAMA_KEEP_ALIVE', 'OLLAMA_CONTEXT_LENGTH')
$setVars = @($vars | Where-Object { $null -ne [Environment]::GetEnvironmentVariable($_, 'User') })

if (-not $installed -and -not $setVars.Count -and -not (Test-Path -LiteralPath $ModelRoot)) {
  Write-Host 'ollama is not installed, no OLLAMA_* variables are set, and there are no weights; nothing to do.'
  return
}

if (-not (Confirm-Action 'Remove ollama and clear its settings?')) {
  Write-Host 'Skipped.'
  return
}

# The server holds open handles under the model directory, so it goes first whether or
# not the weights are being deleted: winget cannot replace files a running process owns.
$procs = @(Get-Process -Name 'ollama app', 'ollama' -ErrorAction SilentlyContinue)
if ($procs.Count) {
  $procs | Stop-Process -Force
  for ($i = 0; $i -lt 20; $i++) {
    if (-not (Test-OllamaUp)) { break }
    Start-Sleep -Milliseconds 250
  }
  Write-Host 'Stopped the ollama server'
}

if ($installed) {
  Uninstall-WingetPackage -Id 'Ollama.Ollama'
} else {
  Write-Host 'ollama is not on PATH; skipping the uninstall.'
}

foreach ($name in $vars) { Remove-UserEnv $name }

# The weights. Sized first, because "35 GB" is the number that makes this decision,
# and a prompt that does not say so is asking the question without the facts.
if (-not (Test-Path -LiteralPath $ModelRoot)) {
  Write-Host "No weights at $ModelRoot."
  Write-Host 'ollama removed.'
  return
}

$size = (Get-ChildItem -LiteralPath $ModelRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
  Measure-Object -Property Length -Sum).Sum
Write-Host ("Model weights at {0} use {1:N1} GB" -f $ModelRoot, ($size / 1GB))
if (Confirm-Action 'Delete them too? (re-downloading takes a while)') {
  Remove-Item -LiteralPath $ModelRoot -Recurse -Force
  Write-Host "Removed $ModelRoot"
} else {
  Write-Host "Left alone: $ModelRoot"
  Write-Host 'A later bin\install.ps1 ollama will find them and re-pull nothing.'
}
Write-Host 'ollama removed.'
