# Collects this machine's hardware inventory as JSON on stdout.
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\inventory.ps1
#
# Counterpart of scripts/inventory.sh, which emits the same schema on macOS and
# Linux. scripts/fleet-inventory.sh pipes whichever one fits each host over SSH and
# collects the results. See docs/llm-cluster.md for what the numbers are used for.
#
# Read-only: installs nothing and changes no state, so it is safe on a machine you
# are only surveying. The output names the host and its LAN address, so a collected
# set is local-only and never belongs in this repo.
#
# Targets Windows PowerShell 5.1 and stays ASCII, like the recipes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# Runs a native command without letting 5.1 turn its stderr into a terminating
# error, and without the caller having to redirect. Returns stdout lines.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
  $ErrorActionPreference = 'Continue'
  $out = & $Exe @Arguments 2>$null
  return @($out | ForEach-Object { "$_" })
}

function Get-GpuInventory {
  $gpus = @()
  # nvidia-smi is authoritative for VRAM. Win32_VideoController.AdapterRAM is a
  # 32-bit field, so it reports 4 GB for anything larger -- this machine's 8 GB
  # card shows as 4.
  $smi = @(
    'nvidia-smi',
    (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'),
    (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')
  ) | ForEach-Object { (Get-Command $_ -ErrorAction SilentlyContinue).Source } |
      Where-Object { $_ } | Select-Object -First 1

  if ($smi) {
    $rows = Invoke-Native $smi @(
      '--query-gpu=name,memory.total,driver_version,compute_cap',
      '--format=csv,noheader,nounits'
    )
    foreach ($row in $rows) {
      if (-not $row.Trim()) { continue }
      $f = $row -split '\s*,\s*'
      if ($f.Count -lt 4) { continue }
      $gpus += [ordered]@{
        vendor      = 'nvidia'
        name        = $f[0].Trim()
        vram_mib    = [int]$f[1]
        driver      = $f[2].Trim()
        compute_cap = $f[3].Trim()
      }
    }
  }

  # Everything else (integrated, AMD, virtual) from WMI, skipping cards nvidia-smi
  # already described properly.
  $known = @($gpus | ForEach-Object { $_.name })
  foreach ($v in @(Get-CimInstance Win32_VideoController)) {
    if ($known -contains $v.Name) { continue }
    $vram = $null
    if ($v.AdapterRAM) { $vram = [int][math]::Round($v.AdapterRAM / 1MB) }
    $gpus += [ordered]@{
      vendor      = 'other'
      name        = $v.Name
      vram_mib    = $vram
      driver      = $v.DriverVersion
      compute_cap = $null
    }
  }
  return $gpus
}

function Get-RuntimeInventory {
  $found = [ordered]@{}
  foreach ($name in @('ollama', 'lms', 'llama-server', 'llama-cli', 'rpc-server', 'python3', 'uv')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $found[$name] = $cmd.Source } else { $found[$name] = $null }
  }
  return $found
}

$cs   = Get-CimInstance Win32_ComputerSystem
$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = @(Get-CimInstance Win32_Processor)[0]
$dimms = @(Get-CimInstance Win32_PhysicalMemory)

$modules = @()
foreach ($d in $dimms) {
  $modules += [ordered]@{
    gb              = [math]::Round($d.Capacity / 1GB, 1)
    configured_mts  = $d.ConfiguredClockSpeed
    rated_mts       = $d.Speed
    slot            = $d.DeviceLocator
  }
}

$volumes = @()
foreach ($v in @(Get-Volume | Where-Object { $_.DriveLetter })) {
  $volumes += [ordered]@{
    mount    = "$($v.DriveLetter):"
    fs       = $v.FileSystem
    label    = $v.FileSystemLabel
    size_gb  = [math]::Round($v.Size / 1GB, 1)
    free_gb  = [math]::Round($v.SizeRemaining / 1GB, 1)
  }
}

$nics = @()
foreach ($n in @(Get-NetAdapter)) {
  $nics += [ordered]@{
    name        = $n.Name
    description = $n.InterfaceDescription
    status      = "$($n.Status)"
    link_speed  = $n.LinkSpeed
    media       = "$($n.MediaType)"
  }
}

$active = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1

$inventory = [ordered]@{
  schema       = 1
  collected_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  host         = $env:COMPUTERNAME
  platform     = 'windows'
  os           = [ordered]@{
    name  = $os.Caption
    build = "$([Environment]::OSVersion.Version.Build)"
  }
  cpu          = [ordered]@{
    model            = $cpu.Name.Trim()
    cores            = $cpu.NumberOfCores
    threads          = $cpu.NumberOfLogicalProcessors
    max_mhz          = $cpu.MaxClockSpeed
    virtualization   = [bool]$cpu.VirtualizationFirmwareEnabled
  }
  memory       = [ordered]@{
    total_gb          = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    free_gb           = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    modules_populated = $modules.Count
    modules           = $modules
  }
  gpus         = Get-GpuInventory
  storage      = $volumes
  network      = [ordered]@{
    adapters = $nics
    active   = [ordered]@{
      interface = if ($active) { $active.InterfaceAlias } else { $null }
      ipv4      = if ($active) { $active.IPv4Address.IPAddress } else { $null }
      gateway   = if ($active) { $active.IPv4DefaultGateway.NextHop } else { $null }
    }
  }
  runtimes     = Get-RuntimeInventory
}

# 5.1 defaults to -Depth 2, which would flatten the nested arrays into type names.
$inventory | ConvertTo-Json -Depth 8
