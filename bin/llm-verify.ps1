# Runs the checks in docs\verify-local-llm.md and prints what it found.
#
# The runbook came first and is still the explanation; this is the same ground without
# the typing. Pasting thirty commands into an SSH session is its own source of errors
# -- a truncated paste, a variable left over from an earlier step -- and none of those
# errors tell you anything about the thing being verified.
#
# It prints evidence, not verdicts. Every check reports the value it actually read,
# because "PASS" from a script is just another claim to take on faith, and the numbers
# are what make a wrong one obvious. Lines that start with '!!' are the exceptions: a
# check that read something it can argue is wrong says so, and the exit code is the
# count of those.
#
# Default run is the fast set, about 45s measured, and changes nothing. Most of that
# is the 'windows' check, which loads three models in turn to read back the context
# window each one came up with. The three slow or destructive checks are opt-in:
#   -Tools     loads every installed model in turn to test tool-call compliance (2-4m)
#   -Runs      one real turn through each of Pi, OpenCode and Claude Code (3-5m)
#   -Restart   kills the server and brings it back through the logon task
#   -All       all three
[CmdletBinding(PositionalBinding = $false)]
param(
  # Named checks to run instead of the default set: server, env, surfaces, windows,
  # tools, harnesses, runs, node, restart.
  [string[]]$Only,
  [switch]$Tools,
  [switch]$Runs,
  [switch]$Restart,
  [switch]$All,
  # The model the API and harness checks talk to. The default is the derived 32768
  # one, which is the only configuration that stays entirely on the GPU here.
  [string]$Model = 'qwen3-agent:4b',
  # Models whose context window to read back, in the 'windows' check.
  [string[]]$Models = @('qwen3:8b', 'qwen3-agent:4b', 'qwen3-agent64:4b'),
  [int]$Port = 11434
)

$ErrorActionPreference = 'Stop'
# Invoke-RestMethod draws a progress bar over the output otherwise, and it survives
# the call in a non-interactive host.
$ProgressPreference = 'SilentlyContinue'

$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'bin\lib\tools.ps1')

$script:Problems = New-Object Collections.ArrayList
$script:Base = "http://127.0.0.1:$Port"

function Write-Head([string]$Name, [string]$What) {
  Write-Host ''
  Write-Host "== $Name == $What"
}

function Write-Fact([string]$Label, $Value) {
  Write-Host ("   {0,-25} {1}" -f $Label, $Value)
}

function Write-Note([string]$Text) {
  Write-Host "   -- $Text"
}

function Add-Problem([string]$Text) {
  [void]$script:Problems.Add($Text)
  Write-Host "   !! $Text" -ForegroundColor Yellow
}

# One place that knows how to POST JSON, so a check reads as what it is asking rather
# than as plumbing. Returns $null and records the problem on failure, so one dead
# surface does not abort the rest of the run.
function Invoke-Json([string]$Path, [hashtable]$Body, [hashtable]$Headers, [string]$What) {
  $json = $Body | ConvertTo-Json -Depth 6
  try {
    if ($Headers) {
      return Invoke-RestMethod -Uri "$script:Base$Path" -Method Post -ContentType 'application/json' -Headers $Headers -Body $json
    }
    return Invoke-RestMethod -Uri "$script:Base$Path" -Method Post -ContentType 'application/json' -Body $json
  } catch {
    # The server's own error body says far more than the WebException wrapping it.
    $detail = $_.Exception.Message
    $resp = $_.Exception.Response
    if ($resp) {
      try {
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd()
        if ($body) { $detail = $body }
      } catch { }
    }
    Add-Problem "$What failed: $detail"
    return $null
  }
}

# Native commands here are run for their output, with stderr merged in, and that
# combination is a trap under $ErrorActionPreference = 'Stop': PowerShell 5.1 wraps
# each native stderr line in a NativeCommandError, and with Stop in force the first
# one *terminates*. OpenCode writes a bare ANSI reset to stderr, so a check that reads
# its output died on a colour code. Preference is dropped to Continue for the duration
# of the call only, so a real failure is still visible in the exit code and the output.
function Invoke-Native([scriptblock]$Command) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    return @(& $Command 2>&1)
  } finally {
    $ErrorActionPreference = $previous
  }
}

function Get-OllamaRows([string]$Subcommand) {
  $out = Invoke-Native { & $script:Ollama $Subcommand }
  if ($LASTEXITCODE -ne 0) {
    Add-Problem "'ollama $Subcommand' exited $LASTEXITCODE"
    return @()
  }
  $rows = @()
  foreach ($line in ($out | Select-Object -Skip 1)) {
    if (-not "$line".Trim()) { continue }
    $f = @("$line" -split '\s{2,}' | Where-Object { $_ })
    if ($f.Count -ge 4) { $rows += , $f }
  }
  return $rows
}

# ---------------------------------------------------------------- checks

function Test-Server {
  Write-Head 'server' 'is it listening, and what started it'

  $up = Test-OllamaUp $Port
  Write-Fact 'port' ("127.0.0.1:{0} {1}" -f $Port, $(if ($up) { 'open' } else { 'CLOSED' }))
  if (-not $up) {
    Add-Problem "nothing on 127.0.0.1:$Port -- Start-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama'"
  } else {
    try {
      $v = Invoke-RestMethod -Uri "$script:Base/api/version"
      Write-Fact 'version' $v.version
    } catch {
      Add-Problem "the port is open but /api/version did not answer: $($_.Exception.Message)"
    }
  }

  $proc = @(Get-Process -Name 'ollama' -ErrorAction SilentlyContinue)
  if ($proc.Count) {
    Write-Fact 'process' ("PID {0}, started {1}" -f $proc[0].Id, $proc[0].StartTime)
  }

  # Which mechanism got the server here is worth knowing even when it is up, because
  # the two fail in different circumstances and only one of them survives a reboot
  # that nobody logs into at the console.
  $task = Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama' -ErrorAction SilentlyContinue
  if (-not $task) {
    Add-Problem "no \dotfiles\Serve ollama task -- the server will not come back after a reboot. Run: bin\install.ps1 ollama"
  } else {
    $info = $task | Get-ScheduledTaskInfo
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    Write-Fact 'task' ("{0}, last run {1}" -f $task.State, $info.LastRunTime)
    Write-Fact 'last boot' $boot
    # Decoded, because two of the three codes this task produces are healthy and read
    # as failures: a scheduled task that is doing its job reports "still running", and
    # one asked to start when it already has reports that as an error.
    $meaning = switch ($info.LastTaskResult) {
      0 { 'completed' }
      267009 { 'currently running' }
      267011 { 'has not run yet' }
      2147946720 { 'a start was refused because an instance was already running' }
      default { 'unrecognised -- look it up before worrying about it' }
    }
    Write-Fact 'last result' ("{0} (0x{1:X}) {2}" -f $info.LastTaskResult, $info.LastTaskResult, $meaning)
    if ($info.LastRunTime -and $info.LastRunTime -gt $boot) {
      Write-Note 'started by the logon task: last run is after the last boot'
    } else {
      Write-Note 'the logon task has not run since boot -- an SSH logon is type 3 (Network) and does not fire it'
      Write-Note 'so this server was started by hand, or by the SSH block in source/windows/profile.ps1'
    }
  }
  if ($env:SSH_CONNECTION) { Write-Note 'this shell is an SSH session' }
}

function Test-Env {
  Write-Head 'env' 'the settings the server was started with'

  $expected = @{
    OLLAMA_MODELS            = $null
    OLLAMA_CONTEXT_LENGTH    = $null
    OLLAMA_FLASH_ATTENTION   = '1'
    OLLAMA_KV_CACHE_TYPE     = 'q8_0'
    OLLAMA_MAX_LOADED_MODELS = '1'
    OLLAMA_KEEP_ALIVE        = $null
  }
  foreach ($name in @('OLLAMA_MODELS', 'OLLAMA_CONTEXT_LENGTH', 'OLLAMA_FLASH_ATTENTION',
      'OLLAMA_KV_CACHE_TYPE', 'OLLAMA_MAX_LOADED_MODELS', 'OLLAMA_KEEP_ALIVE')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'User')
    if (-not $value) {
      Add-Problem "$name is not set as a user variable -- run bin\install.ps1 ollama"
      continue
    }
    Write-Fact $name $value
    $want = $expected[$name]
    if ($want -and $value -ne $want) { Add-Problem "$name is '$value', expected '$want'" }
  }

  # The server's own view, which is the one that matters: if OLLAMA_MODELS had not
  # reached it, it would be looking in %LOCALAPPDATA% and reporting nothing at all
  # while looking perfectly healthy.
  $rows = Get-OllamaRows 'list'
  Write-Fact 'models on disk' ("{0}: {1}" -f $rows.Count, (($rows | ForEach-Object { $_[0] }) -join ', '))
  if (-not $rows.Count) {
    Add-Problem 'the server reports no models -- OLLAMA_MODELS probably did not reach it'
  }
}

function Test-Surfaces {
  Write-Head 'surfaces' "all three API shapes on port $Port, model $Model"

  $prompt = 'Reply with exactly: READY'

  # Ollama's own API: the only surface that takes num_ctx per request. think=$true is
  # deliberate -- these models reason whether or not you ask, and with it off the
  # server stops parsing the reasoning out and raw <think> tags land in content.
  $r = Invoke-Json '/api/chat' @{ model = $Model; stream = $false; think = $true
    options = @{ num_ctx = 8192 }; messages = @(@{ role = 'user'; content = $prompt })
  } $null 'POST /api/chat'
  if ($r) {
    Write-Fact 'native /api/chat' ("content=[{0}] thinking={1} chars in={2} out={3}" -f
      "$($r.message.content)".Trim(), "$($r.message.thinking)".Length, $r.prompt_eval_count, $r.eval_count)
    if ("$($r.message.content)" -notmatch 'READY') { Add-Problem "native surface did not answer READY" }
    if ("$($r.message.content)" -match '<think>') { Add-Problem 'raw <think> tags in content -- thinking is not being parsed out' }
  }

  # OpenAI-compatible: what Pi and most editor plugins speak.
  $r = Invoke-Json '/v1/chat/completions' @{ model = $Model; max_tokens = 512
    messages = @(@{ role = 'user'; content = $prompt })
  } @{ Authorization = 'Bearer ollama' } 'POST /v1/chat/completions'
  if ($r) {
    Write-Fact 'openai /v1/chat' ("finish={0} in={1} out={2} content=[{3}]" -f
      $r.choices[0].finish_reason, $r.usage.prompt_tokens, $r.usage.completion_tokens,
      "$($r.choices[0].message.content)".Trim())
    if ("$($r.choices[0].message.content)" -notmatch 'READY') { Add-Problem 'openai surface did not answer READY' }
  }

  # Anthropic Messages: what Claude Code speaks. max_tokens is the one field this
  # surface refuses to default, and 1024 is room for the reasoning to finish -- too
  # small and the only block that comes back is 'thinking', with stop=max_tokens.
  $r = Invoke-Json '/v1/messages' @{ model = $Model; max_tokens = 1024
    messages = @(@{ role = 'user'; content = $prompt })
  } @{ 'x-api-key' = 'ollama'; 'anthropic-version' = '2023-06-01' } 'POST /v1/messages'
  if ($r) {
    $blocks = ($r.content | ForEach-Object { $_.type }) -join '+'
    $text = @($r.content | Where-Object { $_.type -eq 'text' })
    Write-Fact 'anthropic /v1/msg' ("blocks={0} stop={1} in={2} out={3} text=[{4}]" -f
      $blocks, $r.stop_reason, $r.usage.input_tokens, $r.usage.output_tokens,
      $(if ($text.Count) { "$($text[0].text)".Trim() } else { '' }))
    if ($blocks -notmatch 'text') { Add-Problem "no text block: blocks=$blocks stop=$($r.stop_reason) -- raise max_tokens" }
  }
}

function Test-Windows {
  Write-Head 'windows' 'the context window each model actually loads with'

  $installed = @(Get-OllamaRows 'list' | ForEach-Object { $_[0] })
  $serverDefault = [Environment]::GetEnvironmentVariable('OLLAMA_CONTEXT_LENGTH', 'User')

  foreach ($m in $Models) {
    if ($installed -notcontains $m) {
      Write-Fact $m 'not installed; skipped'
      continue
    }
    # One token of work is enough to make the server load it; the point is ollama ps.
    $null = Invoke-Json '/api/chat' @{ model = $m; stream = $false
      messages = @(@{ role = 'user'; content = 'hi' }) } $null "loading $m"
    $row = @(Get-OllamaRows 'ps' | Where-Object { $_[0] -eq $m })
    if (-not $row.Count) {
      Add-Problem "$m did not appear in 'ollama ps' after a request"
      continue
    }
    $f = $row[0]
    Write-Fact $m ("context={0} size={1} processor={2}" -f $f[4], $f[2], $f[3])
    # A derived model whose window matches the server default means the baked
    # num_ctx did not take, which is invisible until a harness runs out of room.
    if ($m -ne 'qwen3:8b' -and $serverDefault -and "$($f[4])" -eq "$serverDefault") {
      Add-Problem "$m loaded at the server default ($serverDefault) -- its baked num_ctx is not being honoured"
    }
  }
  Write-Note 'OLLAMA_MAX_LOADED_MODELS=1, so each line above cost an evict and a reload'
}

function Test-ToolCalls {
  Write-Head 'tools' 'which models emit tool calls rather than describing them'
  $probe = Join-Path $Root 'bin\llm-probe.ps1'
  Invoke-Native { & powershell -NoProfile -ExecutionPolicy Bypass -File $probe -Port $Port } | ForEach-Object { Write-Host "   $_" }
  if ($LASTEXITCODE -ne 0) { Add-Problem "llm-probe.ps1 exited $LASTEXITCODE" }
}

function Test-Harnesses {
  Write-Head 'harnesses' 'installed, and pointed at this server'

  foreach ($name in @('pi', 'opencode', 'claude', 'node', 'npm')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { Write-Fact $name $cmd.Source } else { Write-Fact $name 'not on PATH' }
  }

  if (Get-Command pi -ErrorAction SilentlyContinue) {
    $rows = @(Invoke-Native { & pi --offline --list-models } | Select-String -Pattern '^\s*ollama\s' | ForEach-Object { $_.Line.Trim() })
    Write-Fact 'pi models' ("{0} registered" -f $rows.Count)
    foreach ($r in $rows) { Write-Host "      $r" }
    if (-not $rows.Count) { Add-Problem 'pi has no ollama provider -- run bin\install.ps1 pi' }
  }

  if (Get-Command opencode -ErrorAction SilentlyContinue) {
    $rows = @(Invoke-Native { & opencode models } | Select-String -Pattern '^ollama/' | ForEach-Object { $_.Line.Trim() })
    Write-Fact 'opencode models' ("{0} discovered" -f $rows.Count)
    if (-not $rows.Count) { Add-Problem 'opencode discovered no ollama models -- is the server up?' }
    # OpenCode enumerates whatever the server has, including models that cannot drive
    # an agent, and the non-compliant one sorts first alphabetically.
    if ($rows -contains 'ollama/qwen2.5-coder:7b') {
      Write-Note 'ollama/qwen2.5-coder:7b is listed and sorts first -- it declares tools and does not emit them'
    }
  }
}

function Test-Runs {
  Write-Head 'runs' 'one real turn through each harness'

  $prompt = 'Reply with exactly: READY'

  if (Get-Command pi -ErrorAction SilentlyContinue) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = Invoke-Native { & pi --offline --no-session -p --mode text --model "ollama/$Model" $prompt }
    $sw.Stop()
    $ok = ($out -join ' ') -match 'READY'
    Write-Fact 'pi' ("{0:N0}s  {1}" -f $sw.Elapsed.TotalSeconds, $(if ($ok) { 'READY' } else { 'no READY in output' }))
    if (-not $ok) { Add-Problem "pi did not answer READY: $(($out | Select-Object -Last 3) -join ' / ')" }
  }

  if (Get-Command opencode -ErrorAction SilentlyContinue) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = Invoke-Native { & opencode run -m "ollama/$Model" --archived $prompt }
    $sw.Stop()
    $ok = ($out -join ' ') -match 'READY'
    Write-Fact 'opencode' ("{0:N0}s  {1}" -f $sw.Elapsed.TotalSeconds, $(if ($ok) { 'READY' } else { 'no READY in output' }))
    if (-not $ok) { Add-Problem "opencode did not answer READY: $(($out | Select-Object -Last 3) -join ' / ')" }
  }

  if (Get-Command claude -ErrorAction SilentlyContinue) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $wrapper = Join-Path $Root 'bin\claude-local.ps1'
    $out = Invoke-Native { & powershell -NoProfile -ExecutionPolicy Bypass -File $wrapper -Prompt $prompt }
    $sw.Stop()
    $ok = ($out -join ' ') -match 'READY'
    Write-Fact 'claude code' ("{0:N0}s  {1}" -f $sw.Elapsed.TotalSeconds, $(if ($ok) { 'READY' } else { 'no READY in output' }))
    Write-Note 'that run used the 65536 window, which spills about a quarter onto the CPU'
    if (-not $ok) { Add-Problem "claude-local.ps1 did not answer READY: $(($out | Select-Object -Last 3) -join ' / ')" }
  }
}

function Test-Node {
  Write-Head 'node' 'the toolchain the harnesses were installed with'

  foreach ($pair in @(@('node', 'node -v'), @('npm', 'npm -v'))) {
    $exe = $pair[0]
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
      Add-Problem "$exe is not on PATH -- run bin\install.ps1 fnm"
      continue
    }
    Write-Fact $exe (Invoke-Native { & $exe -v })
  }
  if (Get-Command npm -ErrorAction SilentlyContinue) {
    $cache = (Invoke-Native { & npm config get cache }) -join ''
    Write-Fact 'npm cache' $cache
    if ($cache -notmatch '^[A-Za-z]:\\caches\\npm') { Add-Problem "npm cache is '$cache', expected <drive>:\caches\npm" }
  }
  Write-Fact 'FNM_DIR' $(if ($env:FNM_DIR) { $env:FNM_DIR } else { 'not set' })
  $node = Get-Command node -ErrorAction SilentlyContinue
  if ($node) {
    Write-Fact 'node resolves to' $node.Source
    # Either answer is correct and they mean different things: the multishell path is
    # the profile's fnm block active in this shell, the aliases junction is the PATH
    # entry that makes node work in cmd and Git Bash.
    if ($node.Source -match 'fnm_multishells') { Write-Note "via fnm's per-shell junction, so the profile block is active here" }
    elseif ($node.Source -match 'aliases\\default') { Write-Note 'via the PATH junction, so this shell did not load the profile' }
  }

  $letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
  $devdrv = (Invoke-Native { & fsutil devdrv query "${letter}:" }) -join ' '
  Write-Fact "${letter}: dev drive" $devdrv
  if ($devdrv -notmatch 'trusted') { Add-Problem "${letter}: is not reported as a trusted developer volume" }
}

function Test-TaskRestart {
  Write-Head 'restart' 'kill the server and bring it back through the logon task'

  $task = Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama' -ErrorAction SilentlyContinue
  if (-not $task) {
    Add-Problem 'no \dotfiles\Serve ollama task to test'
    return
  }

  @(Get-Process -Name 'ollama' -ErrorAction SilentlyContinue) | Stop-Process -Force
  for ($i = 0; $i -lt 20; $i++) {
    if (-not (Test-OllamaUp $Port)) { break }
    Start-Sleep -Milliseconds 250
  }
  Write-Fact 'after kill' ("port {0}" -f $(if (Test-OllamaUp $Port) { 'STILL OPEN' } else { 'closed' }))
  if (Test-OllamaUp $Port) { Add-Problem 'could not stop the server, so the restart proves nothing' ; return }

  # The scheduler goes on calling the task Running after the process it started is
  # gone, and refuses to start what it thinks is already there.
  if ((Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama').State -eq 'Running') {
    Stop-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama'
  }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  Start-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Serve ollama'
  $up = $false
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-OllamaUp $Port) { $up = $true; break }
    Start-Sleep -Milliseconds 250
  }
  $sw.Stop()
  if ($up) {
    $proc = @(Get-Process -Name 'ollama' -ErrorAction SilentlyContinue)
    Write-Fact 'after task' ("up in {0:N1}s, PID {1}" -f $sw.Elapsed.TotalSeconds, $proc[0].Id)
  } else {
    Add-Problem 'the task did not bring the server back within 15s'
  }
}

# ---------------------------------------------------------------- run

$script:Ollama = Get-OllamaExe

$checks = [ordered]@{
  server    = ${function:Test-Server}
  env       = ${function:Test-Env}
  surfaces  = ${function:Test-Surfaces}
  windows   = ${function:Test-Windows}
  tools     = ${function:Test-ToolCalls}
  harnesses = ${function:Test-Harnesses}
  runs      = ${function:Test-Runs}
  node      = ${function:Test-Node}
  restart   = ${function:Test-TaskRestart}
}

if ($Only) {
  # Run through powershell.exe -File, '-Only server,env' arrives as one string rather
  # than as two elements -- -File parses a command line, it does not bind PowerShell
  # types. Splitting here means both spellings work from either kind of invocation.
  $Only = @($Only -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $unknown = @($Only | Where-Object { $checks.Keys -notcontains $_ })
  if ($unknown.Count) {
    throw "Unknown check(s): $($unknown -join ', '). Known: $($checks.Keys -join ', ')."
  }
  $selected = @($Only)
} else {
  $selected = @('server', 'env', 'surfaces', 'windows', 'harnesses', 'node')
  if ($Tools -or $All) { $selected += 'tools' }
  if ($Runs -or $All) { $selected += 'runs' }
  if ($Restart -or $All) { $selected += 'restart' }
  # Keep the declared order whatever the switches were, so restart stays last.
  $selected = @($checks.Keys | Where-Object { $selected -contains $_ })
}

$total = [Diagnostics.Stopwatch]::StartNew()
Write-Host ("llm-verify: {0} on {1}" -f ($selected -join ', '), $script:Base)
foreach ($name in $selected) {
  try {
    & $checks[$name]
  } catch {
    # One check throwing is a finding, not a reason to abandon the other eight.
    Add-Problem "the '$name' check threw: $($_.Exception.Message)"
  }
}
$total.Stop()

Write-Host ''
if ($script:Problems.Count) {
  Write-Host ("{0} problem(s) in {1:N0}s:" -f $script:Problems.Count, $total.Elapsed.TotalSeconds)
  foreach ($p in $script:Problems) { Write-Host "   !! $p" -ForegroundColor Yellow }
  Write-Host ''
  Write-Host 'docs\verify-local-llm.md has the by-hand version of each check and what the output means.'
  exit $script:Problems.Count
}
Write-Host ("no problems found in {0:N0}s. Checks run: {1}" -f $total.Elapsed.TotalSeconds, ($selected -join ', '))
Write-Host 'The numbers above are the evidence; docs\verify-local-llm.md says what each one means.'
