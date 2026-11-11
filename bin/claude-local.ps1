<#
.SYNOPSIS
  Run Claude Code against the local Ollama server instead of the Anthropic API.

.DESCRIPTION
  Ollama answers the Anthropic Messages API directly (v0.14.0 and later), so no
  translation proxy is involved: Claude Code only needs to be pointed at the port and
  told the truth about the model's context window.

  The environment is set for this one child process and nothing else. Persisting
  ANTHROPIC_BASE_URL as a user variable would silently redirect every Claude Code
  session on the machine, including the ones meant for the real API, so this script
  exists instead of a recipe that writes those variables.

.EXAMPLE
  bin\claude-local.ps1
  bin\claude-local.ps1 -Model qwen3-agent:4b -Context 32768   # faster, single-file only
  bin\claude-local.ps1 -Prompt "Summarise README.md"
  bin\claude-local.ps1 --permission-mode acceptEdits

.NOTES
  Expect a local model to be slower and less capable than the hosted one; a
  single-file edit lands in tens of seconds rather than seconds. docs/local-llm.md has
  the measurements, the context arithmetic, and why a 4B model at a 32K window beats
  an 8B at 16K for this.
#>
# PositionalBinding is off so that a stray argument meant for claude cannot land in
# -Model or -Context by position.
[CmdletBinding(PositionalBinding = $false)]
param(
  # The model to drive. The default is the *wider* of the two models the ollama recipe
  # derives, and the width is the point.
  #
  # Claude Code spends about 13,800 tokens on its system prompt and tool schemas before
  # the conversation starts. At a 32768 window that is 42% of the budget, and measured
  # on a three-file task it does not merely feel tight -- it fails, aborting with
  # "autocompact is thrashing: the context refilled to the limit within 3 turns of the
  # previous compact, 3 times in a row". The same task at 65536 completes in five
  # turns. So this defaults to the window the harness can actually work in, and pays
  # for it: 65536 spills past 8 GB of VRAM into system RAM and gives up about 45% of
  # throughput. A faster, narrower run is -Model qwen3-agent:4b -Context 32768, which
  # is fine for single-file work and nothing larger.
  [string]$Model = 'qwen3-agent64:4b',
  # The model's real context window, in tokens. Claude Code cannot discover the window
  # of an ID it does not recognise -- it assumes 200K, keeps packing context past what
  # the model can hold, and never compacts because by its reckoning there is room.
  # Must match the model: see 'ollama show <model>' and any baked-in num_ctx.
  [int]$Context = 65536,
  [int]$Port = 11434,
  # One-shot, non-interactive: becomes 'claude --print <prompt>'. Here as a parameter
  # of its own because PowerShell binds '-p' against this script's own parameter names
  # before claude ever sees it, so 'claude -p ...' cannot be passed through.
  [string]$Prompt,
  # Anything else goes to claude untouched. Use claude's long flags: a short one such
  # as -p or -c is parsed as a parameter of this script and silently swallowed.
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$ClaudeArgs
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'bin\lib\tools.ps1')

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { throw 'claude is not on PATH. Run: bin\install.ps1 claude' }
$ollama = Get-OllamaExe

# 1. A server to talk to. 'ollama serve' rather than the tray app, which is a GUI
# program and exits without binding the port when there is no interactive window
# station -- an SSH logon or a backgrounded shell. Same reason as in the recipe.
if (-not (Test-OllamaUp $Port)) {
  Write-Host "Nothing on 127.0.0.1:$Port; starting 'ollama serve'"
  Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-OllamaUp $Port) { break }
    Start-Sleep -Milliseconds 500
  }
  if (-not (Test-OllamaUp $Port)) {
    throw ("The ollama server did not come up on 127.0.0.1:$Port within 30s. Run " +
      "'ollama serve' by hand to see why.")
  }
}

# 2. A model that is actually there. Cheap to check, and the alternative is a failure
# part way into the first turn.
$listed = @(& $ollama list | Select-Object -Skip 1 |
  ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
Assert-ExitCode 'ollama list'
if ($listed -notcontains $Model) {
  throw ("The server does not have '$Model'. It has: $($listed -join ', '). " +
    "Run 'bin\install.ps1 ollama' for the default set, or 'ollama pull $Model'.")
}

$env2 = [ordered]@{
  # No /v1 -- the client appends the path. '.../v1' is the OpenAI surface, and a client
  # expecting Anthropic semantics there gets a 404 that reads like a dead server.
  ANTHROPIC_BASE_URL              = "http://127.0.0.1:$Port"
  # Required by the protocol, ignored by the server. There is no authentication on
  # this port, which is why it stays bound to localhost.
  ANTHROPIC_AUTH_TOKEN            = 'ollama'
  # The real window. CLAUDE_CODE_AUTO_COMPACT_WINDOW is not the knob for this: it
  # accepts 100K to 1M and clamps anything smaller to the 100K floor.
  CLAUDE_CODE_MAX_CONTEXT_TOKENS  = "$Context"
  # Background work (conversation titles and the like) goes to whatever 'haiku'
  # resolves to, which behind a local base URL is a model the server does not have.
  # Pointing it at a *second* local model is worse than leaving it: with
  # OLLAMA_MAX_LOADED_MODELS=1 every background call evicts the main model and
  # reloads it, which measured 94s against 38s on the same single-edit task. So it
  # gets the same model, and the swap never happens.
  ANTHROPIC_DEFAULT_HAIKU_MODEL   = $Model
  ANTHROPIC_MODEL                 = $Model
  # An unset ANTHROPIC_API_KEY alongside ANTHROPIC_AUTH_TOKEN is deliberate: the two
  # are alternatives, and setting both earns a warning about which one wins.
}

Write-Host ''
Write-Host "model:   $Model"
Write-Host "server:  $($env2.ANTHROPIC_BASE_URL)"
Write-Host "context: $Context tokens (about 13,800 of it goes to the system prompt and tool schemas)"
# A window this harness is known to thrash in is worth saying out loud rather than
# leaving to be discovered three compactions into a task.
if ($Context -lt 65536) {
  Write-Host ''
  Write-Warning ("At $Context tokens this is a single-file configuration. Measured, a " +
    'three-file task aborts here with "autocompact is thrashing". Drop -Context and ' +
    '-Model to use the 65536 window instead.')
}
Write-Host ''

# Save and restore, so a dot-sourced run cannot leave the caller's shell pointed at
# the local server.
$saved = @{}
foreach ($name in $env2.Keys) {
  $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
  foreach ($name in $env2.Keys) {
    [Environment]::SetEnvironmentVariable($name, $env2[$name], 'Process')
  }
  $argv = @()
  if ($Prompt) { $argv += @('--print', $Prompt) }
  if ($ClaudeArgs) { $argv += $ClaudeArgs }
  & $claude.Source @argv
  exit $LASTEXITCODE
} finally {
  foreach ($name in $saved.Keys) {
    [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
  }
}
