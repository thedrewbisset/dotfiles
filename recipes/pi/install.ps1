# Pi, a third agentic coding harness, wired to the local ollama models.
#
# Opt-in (not in 'all'): a tool for a particular kind of work, and it needs Node, so
# it goes after recipes/fnm rather than beside it.
#
# Why a third harness, when recipes/opencode already added a second. Because of one
# measured number. An agentic harness resends its system prompt and the JSON schema of
# every tool it owns on every turn, and on a local model that fixed cost comes out of a
# context window measured in tens of thousands of tokens rather than hundreds of
# thousands. Asked the same trivial question against the same local model:
#
#   Claude Code   13,821 input tokens
#   Pi               699 input tokens
#
# Twenty times less, because Pi's core is four tools -- read, bash, edit, write -- and
# a short preamble. On a 32K window that is the difference between 58% of the window
# left for actual work and 98% of it. After a complete read-edit-confirm turn Pi had
# used 1,753 tokens where Claude Code used 15,061.
#
# That is not a verdict on the harnesses. Claude Code's prompt buys subagents, skills,
# MCP and a much larger tool surface, and against a hosted model with a 200K window
# the overhead is irrelevant. It is a verdict about this hardware: when the window is
# the binding constraint, the leanest harness wins, and the margin is not close.
# docs/local-llm.md has the full measurements.
#
# Defaults, each overridable with an environment variable:
#   PI_RECIPE_PACKAGE   @earendil-works/pi-coding-agent
#   PI_RECIPE_MODELS    qwen3-agent:4b@32768,qwen3:8b@16384,qwen3:4b@16384
#
# The model list is 'id@window' pairs, and the window matters as much as it does for
# Claude Code: Pi defaults an unknown model to a 128000-token context window, so
# without a real figure it would keep packing context long past what the model holds.
# Unlike Claude Code this lives in the same file as the provider, so there is no
# environment variable to forget.
#
# qwen2.5-coder:7b is deliberately absent. It declares a tools capability and does not
# honour it -- it returns the tool call as plain text that no harness can act on --
# so registering it would offer a model that cannot work here. bin\llm-probe.ps1 is
# how that was established and how to re-check after a model changes.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$Port = 11434
$Package = if ($env:PI_RECIPE_PACKAGE) { $env:PI_RECIPE_PACKAGE } else { '@earendil-works/pi-coding-agent' }
$ModelSpec = if ($env:PI_RECIPE_MODELS) { $env:PI_RECIPE_MODELS } else { 'qwen3-agent:4b@32768,qwen3-agent64:4b@65536,qwen3:8b@16384,qwen3:4b@16384' }

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

# 1. Node. recipes/fnm puts the default version's junction on the user PATH, but a
# shell opened before that ran still has the old PATH, so fall back to the junction.
Update-SessionPath
$npmCmd = (Get-Command npm -ErrorAction SilentlyContinue).Source
if (-not $npmCmd) {
  $letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
  $fnmDir = if ($env:FNM_DIR) { $env:FNM_DIR } else { "${letter}:\caches\fnm" }
  $candidate = Join-Path $fnmDir 'aliases\default\npm.cmd'
  if (Test-Path -LiteralPath $candidate) { $npmCmd = $candidate }
}
if (-not $npmCmd) {
  throw 'npm is not available. Run bin\install.ps1 fnm first (Pi needs Node 22.19 or newer).'
}

# 2. Pi. A global npm install, which under a version manager means *per Node version*:
# switching the default version with 'fnm default' leaves pi behind on the old one.
# That is a property of global installs, not a fault to work around -- re-run this
# recipe after changing the default version. --ignore-scripts is what upstream
# recommends, and it is the right default for installing someone else's package tree.
Write-Step "Installing $Package globally"
& $npmCmd install -g --ignore-scripts $Package
Assert-ExitCode "npm install -g $Package"

Update-SessionPath
$pi = (Get-Command pi -ErrorAction SilentlyContinue).Source
if (-not $pi) {
  $candidate = Join-Path (Split-Path -Parent $npmCmd) 'pi.cmd'
  if (Test-Path -LiteralPath $candidate) { $pi = $candidate }
}
if (-not $pi) { throw 'pi is not on PATH after install. Open a new shell and re-run.' }
Write-Host ("pi " + (& $pi --version))

if ($Target -ne $HOME) {
  Write-Host 'Skipping the provider configuration: it belongs to the real home directory.'
  return
}

# 3. The provider. Pi's agent directory is ~\.pi\agent -- already home-relative rather
# than under AppData, so unlike most tools on this platform there is nothing to pin.
$agentDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HOME '.pi\agent' }
New-Item -ItemType Directory -Force $agentDir | Out-Null
$modelsJson = Join-Path $agentDir 'models.json'

$entries = @()
foreach ($pair in ($ModelSpec -split ',')) {
  $pair = $pair.Trim()
  if (-not $pair) { continue }
  if ($pair -notmatch '^(.+)@(\d+)$') {
    throw "PI_RECIPE_MODELS entries must look like 'model:tag@window'; got '$pair'."
  }
  $entries += [pscustomobject]@{ Id = $Matches[1]; Window = [int]$Matches[2] }
}
if (-not $entries.Count) { throw 'PI_RECIPE_MODELS resolved to no models.' }

# Warn about anything configured that the server does not have. A warning rather than
# an error: the configuration is static and still correct, and pulling a model is a
# separate decision from wiring up the harness.
if (Test-OllamaUp) {
  $listed = @(& ollama list | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
  $absent = @($entries | Where-Object { $listed -notcontains $_.Id })
  if ($absent.Count) {
    Write-Warning ("These models are configured but the server does not have them: " +
      "$(($absent.Id) -join ', '). Run bin\install.ps1 ollama, or set PI_RECIPE_MODELS.")
  }
} else {
  Write-Host "Nothing is listening on 127.0.0.1:$Port, so the model list was not verified."
}

$modelObjects = @()
foreach ($e in $entries) {
  $modelObjects += [pscustomobject][ordered]@{
    id            = $e.Id
    reasoning     = $true
    contextWindow = $e.Window
    # Output cap, not window. Kept well under the window so a runaway generation
    # cannot eat the context a conversation needs; Pi's default here is 16384, which
    # on a 32768 window would reserve half of it.
    maxTokens     = 4096
    # Required by Pi's schema. Zero because these tokens are free, which also keeps
    # the session footer honest instead of reporting a hosted model's prices.
    cost          = [pscustomobject][ordered]@{ input = 0; output = 0; cacheRead = 0; cacheWrite = 0 }
  }
}
$provider = [pscustomobject][ordered]@{
  # /v1: this is Pi's OpenAI-compatible route, not the Anthropic one Claude Code uses.
  baseUrl = "http://127.0.0.1:$Port/v1"
  api     = 'openai-completions'
  # Required by the protocol and ignored by the server.
  apiKey  = 'ollama'
  models  = @($modelObjects)
}

# Merged rather than overwritten: models.json is where a hosted provider's proxy or a
# model override would also live, and this recipe only owns the 'ollama' key.
$config = $null
if (Test-Path -LiteralPath $modelsJson) {
  $raw = Get-Content -LiteralPath $modelsJson -Raw
  if ($raw -and $raw.Trim()) {
    try {
      $config = $raw | ConvertFrom-Json
    } catch {
      throw ("$modelsJson is not valid JSON, so it cannot be merged into. Fix or move it, then re-run.")
    }
  }
  # One backup, the first time this recipe touches an existing file, following the
  # .pre-dotfiles convention in recipes/dotfiles.
  $backup = "$modelsJson.pre-dotfiles"
  if ($config -and -not (Test-Path -LiteralPath $backup)) {
    $hadOllama = [bool]($config.PSObject.Properties['providers'] -and
      $config.providers.PSObject.Properties['ollama'])
    if (-not $hadOllama) {
      Copy-Item -LiteralPath $modelsJson -Destination $backup
      Write-Host "Backed up the existing file to $backup"
    }
  }
}
if (-not $config) { $config = New-Object psobject }
if (-not $config.PSObject.Properties['$schema']) {
  $config | Add-Member -MemberType NoteProperty -Name '$schema' -Value 'https://pi.dev/schemas/models.schema.json'
}
if (-not $config.PSObject.Properties['providers']) {
  $config | Add-Member -MemberType NoteProperty -Name 'providers' -Value (New-Object psobject)
}
$config.providers | Add-Member -MemberType NoteProperty -Name 'ollama' -Value $provider -Force

# UTF-8 without a BOM: a BOM in front of '{' is not valid JSON to most parsers, and
# PowerShell 5.1's Out-File and Set-Content both write one.
$json = $config | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($modelsJson, $json + "`n", (New-Object Text.UTF8Encoding($false)))
Write-Host "Wrote the ollama provider to $modelsJson"

# 4. Confirm from Pi rather than from the file: a provider Pi cannot parse or cannot
# authenticate is absent from this list, and that is the failure worth catching here.
# --offline so the check does not depend on reaching pi.dev for catalog updates.
$models = @(& $pi --offline --list-models 2>&1 | Where-Object { $_ -match '^\s*ollama\s' })
if (-not $models.Count) {
  throw ("Pi does not list any ollama models after writing $modelsJson. Run " +
    "'pi --offline --list-models' to see what it says.")
}

Write-Host ''
Write-Host 'Pi can see these local models:'
foreach ($m in $models) { Write-Host "  $m" }
Write-Host ''
Write-Host "Try it:   pi --model ollama/$($entries[0].Id)"
Write-Host "          pi --model ollama/$($entries[0].Id) -p ""..."""
Write-Host '          bin\llm-probe.ps1              which models can drive an agent'
