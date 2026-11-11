# Ollama, with its weights pinned to the Dev Drive and the models this machine can
# actually keep resident in VRAM.
#
# Opt-in (not in 'all'): it downloads several GB of model weights, which is not a
# thing to do as a side effect of bootstrapping a machine.
#
# Defaults, each overridable with an environment variable:
#   OLLAMA_MODELS          <DEVDRIVE_LETTER>:\models\ollama
#   OLLAMA_RECIPE_MODELS   qwen3:8b,qwen2.5-coder:7b,qwen3:4b,qwen2.5vl:7b  (comma separated)
#   OLLAMA_KEEP_ALIVE      30m
#   OLLAMA_CONTEXT_LENGTH  16384
#   OLLAMA_RECIPE_AGENT    qwen3-agent:4b=qwen3:4b@32768   (name=base@window; '' to skip)
#
# Why these four. The default set is sized for an 8 GB-class CUDA card, where
# roughly 7.2 GiB of the 8 is usable for weights plus KV cache once the CUDA context
# and compute buffers are accounted for. Pull sizes, 17.1 GB in total:
#
#   qwen3:8b           4.87 GB  the interactive default
#   qwen2.5-coder:7b   4.36 GB  has the fill-in-middle tokens editor completion
#                               needs; no Qwen3 coder is small enough (30B-A3B is)
#   qwen3:4b           2.33 GB  fast enough for autocomplete and classification
#   qwen2.5vl:7b       5.56 GB  image input -- every other model here is text-only
#
# Each stays GPU-resident with room for a useful context window, and since
# OLLAMA_MAX_LOADED_MODELS is 1 a fourth model costs disk rather than VRAM: they
# swap, they do not compete. gemma3:12b (7.60 GB) and qwen3:14b (8.64 GB) are left
# out because they exceed the budget, and a partially offloaded model loses more
# speed than the extra parameters give back. Set OLLAMA_RECIPE_MODELS for a card
# with a different budget; docs/llm-cluster.md has the sizing method.
#
# On the vision choice: fidelity on dense text and documents is set by the vision
# encoder's input resolution, not by parameter count, so the lever is architecture
# rather than size. Qwen2.5-VL's native dynamic-resolution ViT feeds far more visual
# tokens per page than Gemma 3's fixed 896x896 SigLIP with pan-and-scan, which is
# why it wins at the same parameter count; gemma3:4b (3.12 GB) is the cheaper, faster
# alternative if images only ever need a glance. The VRAM cost of vision is those
# visual tokens landing in the KV cache, so on 8 GB the practical limit is image size
# and count per prompt, not whether the model loads.
#
# The recipe also derives one extra model, qwen3-agent:4b, for driving an agentic
# coding harness. That is a different job from interactive chat and it sizes
# differently: a harness sends its system prompt and the JSON schema of every tool it
# owns on every turn, which measures about 14K tokens before the conversation starts.
# A 16K window leaves nothing, so the window matters more than the parameter count,
# and the model that wins is the one holding the biggest window on the GPU -- a 4B at
# 32768 stays 100% GPU where an 8B at 32768 spills. The window has to be baked into a
# derived model because OLLAMA_CONTEXT_LENGTH is server-wide and neither the OpenAI
# nor the Anthropic surface has anywhere to put a per-request num_ctx; raising the
# server default to 32768 would spill the 8B that chat uses. Derived models share the
# parent's weight blobs, so this costs a manifest and no measurable disk.
# See docs/local-llm.md, and bin\claude-local.ps1 for the harness side.
#
# Weights go in a subdirectory of the Dev Drive's models/ rather than its root, so a
# second runtime's raw GGUFs (llama.cpp, should the cluster plan ever get there) can
# live beside them without the two interleaving.
#
# The tuning variables below are read by the ollama *server*, not the CLI, so this
# restarts it after writing them. A server still running from before would keep its
# old values and quietly ignore the pinned model directory.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$Port = 11434
# Set from measured peak, not from apparent size. Pulling the 17.1 GB default set
# consumed 29.5 GB of an ReFS Dev Drive: the weights account for 17.1 GB of live
# files and the rest is deleted download temporaries that ReFS reclaims lazily rather
# than at once. A floor of 30 covers that peak and still lets a re-run pass, since a
# re-run with every model already present downloads nothing.
$MinFreeGB = 30

# The letter follows the devdrive recipe's DEVDRIVE_LETTER so the two cannot disagree.
$letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
# An OLLAMA_MODELS already set by an earlier run of this recipe is the default, which
# is what keeps a re-run idempotent rather than relocating the weights.
$ModelRoot = if ($env:OLLAMA_MODELS) { $env:OLLAMA_MODELS } else { "${letter}:\models\ollama" }
$KeepAlive = if ($env:OLLAMA_KEEP_ALIVE) { $env:OLLAMA_KEEP_ALIVE } else { '30m' }

$Models = if ($env:OLLAMA_RECIPE_MODELS) {
  @($env:OLLAMA_RECIPE_MODELS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
} else {
  @('qwen3:8b', 'qwen2.5-coder:7b', 'qwen3:4b', 'qwen2.5vl:7b')
}

# The derived harness models, as a comma-separated list of 'name=base@window'. Set
# OLLAMA_RECIPE_AGENT to 'none' to skip them, or to different triples on a card with
# another budget. 'none' rather than the empty string because assigning '' to $env: on
# Windows removes the variable, which is indistinguishable from never having set it.
#
# Two of them, because the right window is per *harness*, not per machine, and the
# difference is not a preference:
#   @32768  free -- 100% GPU at full speed. Enough for a harness with a small prompt.
#   @65536  spills to system RAM and costs about 45% of throughput, and is the
#           smallest window a harness with a ~14K prompt can do multi-file work in.
#           Measured, Claude Code at 32768 aborts a three-file task with "autocompact
#           is thrashing"; at 65536 the same task completes.
$AgentSpec = if ($env:OLLAMA_RECIPE_AGENT) { $env:OLLAMA_RECIPE_AGENT } else { 'qwen3-agent:4b=qwen3:4b@32768,qwen3-agent64:4b=qwen3:4b@65536' }
if ($AgentSpec -eq 'none') { $AgentSpec = '' }
$Agents = @()
foreach ($spec in ($AgentSpec -split ',')) {
  $spec = $spec.Trim()
  if (-not $spec) { continue }
  if ($spec -notmatch '^([^=]+)=([^@]+)@(\d+)$') {
    throw "OLLAMA_RECIPE_AGENT entries must look like 'name=base@window'; got '$spec'."
  }
  $Agents += [pscustomobject]@{ Name = $Matches[1]; Base = $Matches[2]; Window = [int]$Matches[3] }
}

# 'ollama app' is the tray application that owns the server process; 'ollama' is both
# the CLI and, with 'serve', the server itself. Stopping the app alone can leave the
# server behind, so both go.
function Stop-Ollama {
  $procs = @(Get-Process -Name 'ollama app', 'ollama' -ErrorAction SilentlyContinue)
  if (-not $procs.Count) { return $false }
  $procs | Stop-Process -Force
  # Give the port time to come free, so a Start-Ollama straight after cannot find the
  # old server still holding it and conclude it is the new one.
  for ($i = 0; $i -lt 20; $i++) {
    if (-not (Test-OllamaUp $Port)) { break }
    Start-Sleep -Milliseconds 250
  }
  return $true
}

function Start-Ollama {
  if (Test-OllamaUp $Port) { return }
  # 'ollama serve', deliberately not 'ollama app.exe'.
  #
  # The tray app is what a normal login starts. But it is a GUI program: it needs an
  # interactive window station to place its tray icon, which neither an SSH logon nor
  # a backgrounded shell has. Started from one it exits without ever binding the port,
  # which is indistinguishable from a slow start and times out below. 'serve' is a
  # console program and comes up in any session, so the recipe uses it for its own
  # pulls, and step 4b registers the same command as a logon task.
  #
  # A note on "the installer registers the tray app for login", which this comment used
  # to claim: it does not, or at least a winget install does not. Checked -- no Run
  # key entry, no Startup shortcut, no service, no task. The tray app appears to write
  # its own Run entry when it first runs, and it never runs here. Hence step 4b.
  $ollama = Get-OllamaExe
  Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-OllamaUp $Port) {
      Write-Host "ollama server is up on 127.0.0.1:$Port"
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw ("The ollama server did not come up on 127.0.0.1:$Port within 30s. Run " +
    "'ollama serve' by hand to see why it refused to start, then re-run this recipe.")
}

# 0. Where this shell thinks %LOCALAPPDATA% is.
#
# ollama's installer is per-user and puts the program -- plus the bundled CUDA
# libraries, which are not small -- under %LOCALAPPDATA%\Programs\Ollama. A packaged
# (MSIX) app, the Claude desktop app among them, redirects AppData writes made by
# processes it launches into private per-app storage, so an install started from such
# a terminal lands where no other shell can see it, and the tray app this recipe
# starts is then not where it looks. The weights are pinned out of AppData below, but
# the program's own location belongs to the installer, so this can only refuse.
$expectedLocalAppData = Join-Path $HOME 'AppData\Local'
if ($env:LOCALAPPDATA -and $env:LOCALAPPDATA -notlike "$expectedLocalAppData*") {
  throw ("LOCALAPPDATA is '$env:LOCALAPPDATA', which is not under '$expectedLocalAppData'. " +
    'This shell looks like it was launched by a packaged (MSIX) app, which redirects ' +
    'AppData writes, and ollama installs itself there. Run this recipe from a plain ' +
    'terminal or over SSH.')
}

# 1. Somewhere to put the weights, checked before anything is downloaded.
$qualifier = Split-Path -Qualifier $ModelRoot -ErrorAction SilentlyContinue
if (-not $qualifier) { throw "OLLAMA_MODELS must be an absolute path with a drive letter; got '$ModelRoot'." }
$vol = Get-Volume -DriveLetter $qualifier.TrimEnd(':') -ErrorAction SilentlyContinue
if (-not $vol) {
  throw ("Drive $qualifier is not attached, so there is nowhere to put the weights. " +
    "Create the Dev Drive with an elevated: bin\install.ps1 devdrive")
}
$freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
Write-Host ("$qualifier has {0:N1} GB free" -f $freeGB)
if ($freeGB -lt $MinFreeGB) {
  # A Dev Drive is a fixed-size virtual disk, so filling it is a real risk rather
  # than a theoretical one, and a part-written pull is the worst place to find out.
  Write-Warning ("Less than $MinFreeGB GB free on $qualifier. The default models need about 17.1 GB. " +
    "Grow the Dev Drive (diskpart 'expand vdisk', then extend the partition), or set OLLAMA_MODELS elsewhere.")
  if (-not (Confirm-Action 'Continue anyway?')) {
    Write-Host 'Skipped.'
    return
  }
}

# 2. The pinned paths and the tuning, written before the install so the server the
# installer starts reads them on its first run.
#
# A user environment variable is machine-wide, with no per-target equivalent, so a
# -Target run reports rather than writes, as the dotfiles recipe does for DEV_ROOT.
$settings = [ordered]@{
  # Keeps the weights off C: and out of %LOCALAPPDATA%, ollama's default.
  OLLAMA_MODELS            = $ModelRoot
  # FlashAttention-2, supported on any NVIDIA card of compute capability 8.0 or
  # later. Required for the KV cache quantisation below, and it lowers prefill cost
  # on long prompts either way.
  OLLAMA_FLASH_ATTENTION   = '1'
  # Halves the per-token KV cost, which is what makes the context below affordable.
  # The accuracy cost is small, but it is not zero -- drop this variable to compare.
  OLLAMA_KV_CACHE_TYPE     = 'q8_0'
  # ollama defaults to 4096, which is short for coding and long-document work, and
  # without this the KV setting above buys nothing because nothing asks for a bigger
  # window. 16384 is the measured ceiling for an 8B model on 8 GB: 'ollama ps' reports
  # 6.3 GB and 100% GPU at 16384 with no throughput cost against 4096, while 32768
  # reaches 8.2 GB, spills to 22%/78% CPU/GPU, and loses about 40% of its speed. Raise
  # it on a larger card, and check 'ollama ps' still says 100% GPU afterwards.
  OLLAMA_CONTEXT_LENGTH    = '16384'
  # Two resident models would not fit in 8 GB together, and the loser gets offloaded
  # to system RAM, where it runs several times slower for no gain.
  OLLAMA_MAX_LOADED_MODELS = '1'
  # Reloading several GB of weights from disk on every prompt dominates short
  # interactive turns. Free on a machine whose display is not drawn by this GPU;
  # lower it if the card also has to render a desktop.
  OLLAMA_KEEP_ALIVE        = $KeepAlive
}
if ($Target -eq $HOME) {
  foreach ($name in $settings.Keys) { Set-UserEnv $name $settings[$name] }
} else {
  foreach ($name in $settings.Keys) { Write-Host "Would set $name=$($settings[$name])" }
  Write-Host 'Skipped: -Target run, and the user environment is machine-wide.'
}

New-Item -ItemType Directory -Force $ModelRoot | Out-Null

# 3. Ollama itself.
Install-WingetPackage -Id 'Ollama.Ollama'
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
  throw 'ollama is not on PATH after install. Open a new shell and re-run.'
}
Write-Host (ollama --version)

# 4. Restart the server onto the new settings. Unconditional: a server already
# running was started before the variables above existed, and the environment of a
# process that is already up cannot be read to check.
if (Stop-Ollama) { Write-Host 'Stopped the running ollama server to pick up the new settings' }
Start-Ollama

# 4b. Make the server come back after a restart.
#
# Checked rather than assumed, and the assumption was wrong: after a winget install
# there is no Ollama entry under either Run key, nothing in the Startup folder, no
# service and no scheduled task. The tray app writes its own Run entry when it first
# runs, and it never does here, because it is a GUI program with no window station to
# start in (see Start-Ollama). So without this, the server lives exactly as long as
# the shell that started it, and every harness breaks after the next reboot with a
# connection refused that looks like a configuration problem.
#
# A logon task running 'ollama serve' rather than a Run entry for the tray app: the
# same reasoning as Start-Ollama, plus a Run entry would flash a console window. At
# logon rather than at startup, and as this user rather than SYSTEM, because the
# OLLAMA_* settings above are *user* environment variables -- a SYSTEM task would not
# read them and would quietly serve 4096-token contexts out of the default model
# directory.
#
# What this trigger does *not* cover: an OpenSSH logon arrives as logon type 3,
# Network, and a Task Scheduler logon trigger fires on interactive logons only --
# console, RDP, unlock. So a machine that reboots and is then reached only over SSH
# finds this task Ready and nothing listening. source/windows/profile.ps1 closes that
# gap from the other side, probing the port when SSH_CONNECTION is set and starting
# this task if it is closed. Covering it here instead would mean an S4U principal and
# an at-startup trigger, which needs an elevation nothing else in this recipe does --
# see docs/verify-local-llm.md for the command, kept as a deliberate choice.
if ($Target -eq $HOME) {
  $taskName = 'Serve ollama'
  $action = New-ScheduledTaskAction -Execute (Get-OllamaExe) -Argument 'serve'
  # The account name comes from the token, not from "$env:USERDOMAIN\$env:USERNAME".
  # On a machine that is not domain-joined USERDOMAIN can be the literal 'WORKGROUP',
  # and 'WORKGROUP\<user>' has no SID to map to -- Register-ScheduledTask fails with
  # "No mapping between account names and security IDs was done". WindowsIdentity
  # returns what the OS actually calls the account, '<machine>\<user>', which resolves.
  $account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  Register-ScheduledTask -TaskPath '\dotfiles\' -TaskName $taskName -Force -ErrorAction Stop `
    -Description 'Start the ollama server at logon. Managed by the dotfiles ollama recipe.' `
    -Action $action `
    -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $account) `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)) `
    -Principal (New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive) | Out-Null
  # Confirmed, not assumed: Register-ScheduledTask reports some failures without
  # stopping the script, and an unregistered task would be announced as done.
  if (-not (Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName $taskName -ErrorAction SilentlyContinue)) {
    throw "The logon task '$taskName' was not registered, so the server would not come back after a restart."
  }
  Write-Host "Logon task registered (\dotfiles\$taskName), so the server survives a reboot"
}

if ($Target -ne $HOME) {
  Write-Host 'Skipping the model pulls: a -Target run has no pinned model directory to put them in.'
  return
}

# 5. The models. 'ollama pull' is idempotent -- an unchanged manifest is a no-op --
# so a re-run of this recipe only fetches what has actually changed upstream.
foreach ($model in $Models) {
  Write-Step "Pulling $model"
  ollama pull $model
  Assert-ExitCode "ollama pull $model"
}

# 6. The derived harness models. Skipped rather than failed when a base is not in the
# model set, since a custom OLLAMA_RECIPE_MODELS is a deliberate choice and these are
# an extra rather than a requirement.
$expected = @($Models)
$created = @()
foreach ($agent in $Agents) {
  if ($Models -notcontains $agent.Base) {
    Write-Host "Skipping $($agent.Name): its base model $($agent.Base) is not in this run's model set."
    continue
  }
  Write-Step "Creating $($agent.Name) ($($agent.Base) at a $($agent.Window)-token window)"
  $modelfile = Join-Path $env:TEMP "dotfiles-$($agent.Name -replace '[^\w.-]', '_').Modelfile"
  # ASCII and no BOM: ollama parses this as bytes, and PowerShell 5.1's redirection
  # defaults would hand it UTF-16.
  $lines = @("FROM $($agent.Base)", "PARAMETER num_ctx $($agent.Window)")
  [IO.File]::WriteAllLines($modelfile, $lines, (New-Object Text.ASCIIEncoding))
  try {
    ollama create $agent.Name -f $modelfile
    Assert-ExitCode "ollama create $($agent.Name)"
  } finally {
    Remove-Item -LiteralPath $modelfile -Force -ErrorAction SilentlyContinue
  }
  $expected += $agent.Name
  $created += $agent
}

# 7. Report. Confirmed from the server rather than assumed from the pulls: a model
# whose manifest resolved but whose layers did not land would otherwise be announced
# as ready and fail on first use.
$listed = @(ollama list | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
Assert-ExitCode 'ollama list'
$missing = @($expected | Where-Object { $listed -notcontains $_ })
if ($missing.Count) { throw "The server does not list these models after pulling: $($missing -join ', ')" }

Write-Host ''
ollama list
$vol = Get-Volume -DriveLetter $qualifier.TrimEnd(':')
Write-Host ''
Write-Host ("Models are in $ModelRoot ({0:N1} GB free on $qualifier)" -f ($vol.SizeRemaining / 1GB))
Write-Host ''
Write-Host "Try it:   ollama run $($Models[0])"
Write-Host '          bin\llm-probe.ps1              which models can drive an agent'
if ($created.Count) {
  Write-Host '          bin\claude-local.ps1           Claude Code on the widest window'
  Write-Host ''
  Write-Host 'Derived for agentic harnesses:'
  foreach ($agent in $created) {
    Write-Host ("  {0,-18} {1} tokens" -f $agent.Name, $agent.Window)
  }
}
