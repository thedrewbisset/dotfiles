<#
.SYNOPSIS
  Report whether a local Ollama model actually emits structured tool calls.

.DESCRIPTION
  'ollama show' reports a 'tools' capability whenever the model's chat template has a
  tools section. That says the plumbing exists; it does not say the model uses it. The
  template instructs the model to wrap each call in <tool_call> tags, and Ollama's
  parser turns those tags into a structured tool_use block. A model that ignores the
  convention and prints bare JSON returns a valid-looking text response that no
  agentic harness can act on -- the agent prints an object at you and the file it was
  asked to edit is untouched.

  This sends one tool schema over the Anthropic Messages surface and reports which of
  the two happened, so the mismatch is found in a second rather than mid-task.

.EXAMPLE
  bin\llm-probe.ps1
  bin\llm-probe.ps1 qwen3:8b
  bin\llm-probe.ps1 -Port 11434 qwen3:4b qwen2.5-coder:7b

.NOTES
  docs/local-llm.md has the measured results and what they mean for harness choice.
#>
[CmdletBinding()]
param(
  # Models to probe. Default: every model the server lists.
  [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Models,
  [int]$Port = 11434
)
$ErrorActionPreference = 'Stop'
# Invoke-RestMethod in PowerShell 5.1 draws a progress bar that costs more than the
# request on a local server.
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'bin\lib\tools.ps1')

$ollama = Get-OllamaExe
if (-not (Test-OllamaUp $Port)) {
  throw ("Nothing is listening on 127.0.0.1:$Port. Start the server with 'ollama serve', " +
    'or log out and back in to let the tray app start it.')
}

if (-not $Models -or -not $Models.Count) {
  $Models = @(& $ollama list | Select-Object -Skip 1 |
    ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
  Assert-ExitCode 'ollama list'
}
if (-not $Models.Count) { throw 'The server lists no models. Run: bin\install.ps1 ollama' }

# One tool, one unambiguous request for it. Deliberately trivial: the question is
# whether the model can produce the *format*, not whether it can reason.
$body = @{
  max_tokens = 300
  tools      = @(@{
      name         = 'get_weather'
      description  = 'Get the current weather in a given city'
      input_schema = @{
        type       = 'object'
        properties = @{ city = @{ type = 'string'; description = 'City name' } }
        required   = @('city')
      }
    })
  messages   = @(@{ role = 'user'; content = 'What is the weather in Paris?' })
}
$headers = @{
  'x-api-key'         = 'ollama'
  'anthropic-version' = '2023-06-01'
}

$results = @()
foreach ($model in $Models) {
  Write-Step "Probing $model"

  # What the model claims, so the claim and the behaviour can be read side by side.
  $declared = 'no'
  $shown = & $ollama show $model 2>&1
  if ($LASTEXITCODE -eq 0 -and ($shown | Select-String -Pattern '^\s+tools\s*$' -Quiet)) {
    $declared = 'yes'
  }

  $body['model'] = $model
  $json = $body | ConvertTo-Json -Depth 10 -Compress
  $verdict = 'error'
  $stop = '-'
  $detail = ''
  if ($declared -eq 'no') {
    # No tools section in the template at all, so the server rejects the request with a
    # 400. Reported as what it is rather than as a failed probe: a vision or embedding
    # model is not a broken agent model, it is a different kind of model.
    $results += [pscustomobject]@{
      Model    = $model
      Declares = 'no'
      Returned = 'n/a'
      Stop     = '-'
      Detail   = 'no tools section in the template; not an agent model'
    }
    continue
  }
  try {
    $resp = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$Port/v1/messages" `
      -Headers $headers -ContentType 'application/json' -Body $json
    $stop = $resp.stop_reason
    $blocks = @($resp.content | ForEach-Object { $_.type })
    if ($blocks -contains 'tool_use') {
      $verdict = 'tool_use'
      $call = @($resp.content | Where-Object { $_.type -eq 'tool_use' })[0]
      $detail = "$($call.name)($($call.input | ConvertTo-Json -Compress))"
    } elseif ($blocks -contains 'text') {
      $verdict = 'text only'
      $text = @($resp.content | Where-Object { $_.type -eq 'text' })[0].text
      $detail = ($text -replace '\s+', ' ')
      if ($detail.Length -gt 70) { $detail = $detail.Substring(0, 70) + '...' }
    } else {
      $detail = "blocks: $($blocks -join ', ')"
    }
  } catch {
    $detail = $_.Exception.Message
  }

  $results += [pscustomobject]@{
    Model    = $model
    Declares = $declared
    Returned = $verdict
    Stop     = $stop
    Detail   = $detail
  }
}

Write-Host ''
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

$usable = @($results | Where-Object { $_.Returned -eq 'tool_use' })
$broken = @($results | Where-Object { $_.Returned -eq 'text only' })
# 'if' is a statement in PowerShell, so it needs $() to be read as a value here.
$usableNames = 'none'
if ($usable.Count) { $usableNames = ($usable.Model -join ', ') }
Write-Host "Can drive an agentic harness: $usableNames"
if ($broken.Count) {
  Write-Host ''
  Write-Host ("Declared tools but returned plain text: {0}" -f ($broken.Model -join ', '))
  Write-Host 'Those will print a JSON object instead of calling the tool. Use them for'
  Write-Host 'completion, not for an agent. See docs/local-llm.md.'
}
