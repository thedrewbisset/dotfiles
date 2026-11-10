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
# The default set is 17.1 GB, so this leaves real slack rather than just clearing it.
$MinFreeGB = 24

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

# True when something is listening on the ollama API port.
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
    if (-not (Test-OllamaUp)) { break }
    Start-Sleep -Milliseconds 250
  }
  return $true
}

function Start-Ollama {
  if (Test-OllamaUp) { return }
  # The tray app is preferred: it is what a normal login starts, so using it here
  # means this recipe exercises the same path the machine will use every day.
  $app = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
  if (Test-Path -LiteralPath $app) {
    Start-Process -FilePath $app | Out-Null
  } else {
    $ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
    if (-not $ollama) { throw 'ollama is not on PATH, so the server cannot be started.' }
    Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
  }
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-OllamaUp) {
      Write-Host "ollama server is up on 127.0.0.1:$Port"
      return
    }
    Start-Sleep -Milliseconds 500
  }
  throw "The ollama server did not come up on 127.0.0.1:$Port within 30s."
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
  # The highest-value setting on an 8 GB card: a q8_0 KV cache halves the per-token
  # cost, which is what turns a 16K context on an 8B model into a 32K one. The
  # accuracy cost is small, but it is not zero -- drop this variable to compare.
  OLLAMA_KV_CACHE_TYPE     = 'q8_0'
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

# 6. Report. Confirmed from the server rather than assumed from the pulls: a model
# whose manifest resolved but whose layers did not land would otherwise be announced
# as ready and fail on first use.
$listed = @(ollama list | Select-Object -Skip 1 | ForEach-Object { ($_ -split '\s+')[0] } | Where-Object { $_ })
Assert-ExitCode 'ollama list'
$missing = @($Models | Where-Object { $listed -notcontains $_ })
if ($missing.Count) { throw "The server does not list these models after pulling: $($missing -join ', ')" }

Write-Host ''
ollama list
$vol = Get-Volume -DriveLetter $qualifier.TrimEnd(':')
Write-Host ''
Write-Host ("Models are in $ModelRoot ({0:N1} GB free on $qualifier)" -f ($vol.SizeRemaining / 1GB))
Write-Host "Try it: ollama run $($Models[0])"
