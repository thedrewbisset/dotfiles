# Undoes recipes/pi: uninstalls the global npm package and removes the ollama provider
# it added to Pi's models.json.
#
# The provider is removed surgically rather than by deleting the file, because
# models.json is shared: a hosted provider's proxy or a model override can live in it,
# and this recipe only ever owned the 'ollama' key. The file goes only when removing
# that key leaves nothing behind.
#
# Sessions and credentials are a separate, second confirmation, as the weights are in
# recipes/ollama: a re-install brings the tool and its provider back in seconds and
# cannot bring a session history back at all.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$Package = if ($env:PI_RECIPE_PACKAGE) { $env:PI_RECIPE_PACKAGE } else { '@earendil-works/pi-coding-agent' }
$agentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HOME '.pi\agent' }
$modelsJson = Join-Path $agentDir 'models.json'

# Resolved the same way the install recipe resolves them, and for the same reason: a
# shell opened before recipes/fnm ran has neither npm nor pi on PATH, and concluding
# "not installed" from that would silently leave the package behind.
Update-SessionPath
$npmCmd = (Get-Command npm -ErrorAction SilentlyContinue).Source
$binDir = $null
if ($npmCmd) {
  $binDir = Split-Path -Parent $npmCmd
} else {
  $letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
  $fnmDir = if ($env:FNM_DIR) { $env:FNM_DIR } else { "${letter}:\caches\fnm" }
  $candidate = Join-Path $fnmDir 'aliases\default'
  if (Test-Path -LiteralPath (Join-Path $candidate 'npm.cmd')) {
    $binDir = $candidate
    $npmCmd = Join-Path $candidate 'npm.cmd'
  }
}
$installed = [bool](Get-Command pi -ErrorAction SilentlyContinue)
if (-not $installed -and $binDir) {
  $installed = Test-Path -LiteralPath (Join-Path $binDir 'pi.cmd')
}

$haveConfig = Test-Path -LiteralPath $modelsJson
$piRoot = Split-Path -Parent $agentDir

if (-not $installed -and -not $haveConfig -and -not (Test-Path -LiteralPath $piRoot)) {
  Write-Host 'pi is not installed and has left nothing behind; nothing to do.'
  return
}

if (-not (Confirm-Action 'Remove pi and its ollama provider?')) {
  Write-Host 'Skipped.'
  return
}

if (-not $installed) {
  Write-Host 'The pi package is not installed; skipping the uninstall.'
} elseif (-not $npmCmd) {
  Write-Host 'npm is not available, so the package could not be uninstalled. Run bin\install.ps1 fnm, then re-run.'
} else {
  & $npmCmd uninstall -g $Package
  Assert-ExitCode "npm uninstall -g $Package"
}

# The provider. Reading and rewriting rather than deleting, for the reason in the
# header -- and a file this recipe cannot parse is left strictly alone, since guessing
# at it would be worse than leaving one stale key.
if ($haveConfig) {
  $config = $null
  $raw = Get-Content -LiteralPath $modelsJson -Raw
  if ($raw -and $raw.Trim()) {
    try {
      $config = $raw | ConvertFrom-Json
    } catch {
      Write-Warning "$modelsJson is not valid JSON; leaving it untouched."
    }
  }
  if ($config -and $config.PSObject.Properties['providers'] -and
    $config.providers.PSObject.Properties['ollama']) {
    $config.providers.PSObject.Properties.Remove('ollama')
    $otherProviders = @($config.providers.PSObject.Properties).Count
    $otherKeys = @($config.PSObject.Properties | Where-Object { $_.Name -ne '$schema' -and $_.Name -ne 'providers' }).Count
    if ($otherProviders -eq 0 -and $otherKeys -eq 0) {
      Remove-Item -LiteralPath $modelsJson -Force
      Write-Host "Removed $modelsJson (it held nothing but the ollama provider)"
    } else {
      $json = $config | ConvertTo-Json -Depth 10
      [IO.File]::WriteAllText($modelsJson, $json + "`n", (New-Object Text.UTF8Encoding($false)))
      Write-Host "Removed the ollama provider from $modelsJson, left the rest"
    }
    # The backup the install recipe made is only meaningful while the key it was taken
    # for is in place, so it goes with it.
    $backup = "$modelsJson.pre-dotfiles"
    if (Test-Path -LiteralPath $backup) {
      Remove-Item -LiteralPath $backup -Force
      Write-Host "Removed $backup"
    }
  }
}

if (-not (Test-Path -LiteralPath $piRoot)) {
  Write-Host 'pi removed.'
  return
}

# Sized first: the number is what makes this decision, and a prompt that does not show
# it is asking the question without the facts.
$sum = (Get-ChildItem -LiteralPath $piRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
  Measure-Object -Property Length -Sum).Sum
if (-not $sum) { $sum = 0 }
Write-Host ''
Write-Host ('Sessions, settings and credentials in {0} use {1:N1} MB' -f $piRoot, ($sum / 1MB))
if (Confirm-Action 'Delete them too?') {
  Remove-Item -LiteralPath $piRoot -Recurse -Force
  Write-Host "Removed $piRoot"
} else {
  Write-Host "Left alone: $piRoot"
}
Write-Host 'pi removed.'
