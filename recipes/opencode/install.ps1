# OpenCode: a second agentic coding harness, for driving the local models.
#
# Opt-in (not in 'all'): it is a tool for a particular kind of work, not part of
# bootstrapping a machine, and it pulls down a runtime of its own.
#
# Why a second harness at all. Claude Code and OpenCode speak to the same Ollama
# server over different surfaces -- Anthropic Messages against :11434 for one, the
# OpenAI-compatible route for the other -- so having both is a cheap way to tell a
# harness problem from a model problem. The contrast is also instructive: Claude Code
# needs four environment variables and the model's real context window declared by
# hand (bin\claude-local.ps1 does that), where OpenCode discovers a running server on
# the default port and enumerates its models, derived ones included, with nothing
# written to a config file.
#
# There is no step here that configures the local provider, and that is not an
# omission. The hand-written provider.ollama block that older guides describe -- an
# @ai-sdk/openai-compatible entry pointing at http://localhost:11434/v1 -- is only
# needed for a server on a non-default host or port.
#
# Nothing is pinned out of AppData either, which is the usual job on this platform:
# OpenCode already keeps XDG-shaped state under the home directory (~\.config,
# ~\.local\share, ~\.cache). The cache is the big one, a couple of hundred MB on C:.
#
# 'ollama launch opencode' would also wire this up, and is deliberately not used: it
# requires an interactive terminal and refuses to run headless even when given
# --model and --yes, so it cannot be part of a recipe. Same lesson as the tray app
# needing a window station. See docs/local-llm.md.
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

# 1. The CLI. 'Anomaly.OpenCode' is the command-line package; 'Anomaly.OpenCode.Desktop'
# is a separate GUI application and not what this wants.
Install-WingetPackage -Id 'Anomaly.OpenCode'
Update-SessionPath
if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
  throw 'opencode is not on PATH after install. Open a new shell and re-run.'
}
Write-Host (opencode --version)

# 2. Show what it can see, which is the whole of the local configuration. Reported
# rather than asserted: OpenCode is useful against hosted providers too, so an empty
# list here is a note, not a failure.
if (-not (Test-OllamaUp)) {
  Write-Host ''
  Write-Host "Nothing is listening on 127.0.0.1:$Port, so no local models were discovered."
  Write-Host 'Run bin\install.ps1 ollama for the server and a default set of models.'
  return
}

$models = @(opencode models 2>$null | Where-Object { $_ -like 'ollama/*' })
if (-not $models.Count) {
  Write-Host ''
  Write-Host 'The server is up but OpenCode listed no ollama/* models. Check: ollama list'
  return
}

Write-Host ''
Write-Host 'Local models OpenCode discovered:'
foreach ($m in $models) { Write-Host "  $m" }
Write-Host ''
# Deliberately not naming one of them here. The list is alphabetical, and on an
# 8 GB-class card the models that sort first are the ones that cannot drive an agent
# at all: a vision model with no tools section, and, if it has been pulled, a
# completion model that declares a tools capability it does not honour and would print
# a JSON object instead of calling the tool. Which of these can drive an agent is a
# question with a measured answer, so point at the measurement.
Write-Host 'Which of them can drive an agent:  bin\llm-probe.ps1'
Write-Host 'Then:                              opencode run --model ollama/<model> "..."'
Write-Host '                                   opencode          (interactive)'
