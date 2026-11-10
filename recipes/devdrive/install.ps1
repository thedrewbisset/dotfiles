# A Dev Drive: one ReFS volume, backed by a dynamically expanding virtual disk file,
# that holds source, caches and model weights. Opt-in (not in 'all'), run elevated.
#
# Why a Dev Drive: Microsoft Defender scans it in a lighter "performance mode", and
# tearing the whole dev environment down is one file. The performance mode is
# Defender's; a third-party antivirus attached to the volume does not provide it
# (this recipe warns when one is).
#
# This normally runs FIRST, from the unpacked repo zip, before the repo itself moves
# onto the new drive. See docs/windows.md.
#
# Defaults, each overridable with an environment variable:
#   DEVDRIVE_VHDX     C:\DevDrives\dev.vhdx
#   DEVDRIVE_SIZE_GB  64     (a cap, not an allocation; 50 is Windows' minimum)
#   DEVDRIVE_LETTER   D
#
# The file grows as it fills but never shrinks by itself, so start small: growing
# later is easy (diskpart 'expand vdisk', then extend the partition), shrinking is not.
#
# Safe to re-run: an existing disk is re-attached rather than recreated, and a
# volume that already has a filesystem is never reformatted.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')
Assert-Admin 'devdrive'

$Vhdx = if ($env:DEVDRIVE_VHDX) { $env:DEVDRIVE_VHDX } else { 'C:\DevDrives\dev.vhdx' }
$SizeGB = if ($env:DEVDRIVE_SIZE_GB) { [int]$env:DEVDRIVE_SIZE_GB } else { 64 }
$Letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
$Label = 'Dev'
# src: repositories. caches, models: for recipes that pin tool state here.
$Layout = @('src', 'caches', 'models')

# 1. Disk
if (Test-Path $Vhdx) {
  if (-not (Get-DiskImage -ImagePath $Vhdx).Attached) {
    Write-Step "Attaching existing $Vhdx"
    Mount-DiskImage -ImagePath $Vhdx | Out-Null
  }
} else {
  if ($SizeGB -lt 50) { throw "DEVDRIVE_SIZE_GB is $SizeGB; a Dev Drive must be at least 50 GB." }
  if (Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue) {
    throw "Drive ${Letter}: is already in use. Set DEVDRIVE_LETTER to a free letter."
  }
  Write-Step "Creating $Vhdx (expandable, up to $SizeGB GB) as ${Letter}:"
  New-Item -ItemType Directory -Force (Split-Path $Vhdx) | Out-Null
  $script = Join-Path $env:TEMP 'dotfiles-devdrive-diskpart.txt'
  @(
    "create vdisk file=`"$Vhdx`" maximum=$($SizeGB * 1024) type=expandable"
    "select vdisk file=`"$Vhdx`""
    'attach vdisk'
    'convert gpt'
    'create partition primary'
    "assign letter=$Letter"
  ) | Set-Content -Path $script -Encoding ascii
  diskpart /s $script
  $code = $LASTEXITCODE
  Remove-Item $script
  if ($code -ne 0) { throw "diskpart failed (exit code $code)" }
}

# 2. Filesystem
$vol = Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue
if (-not $vol) { throw "$Vhdx is attached but has no ${Letter}: volume. Check Disk Management." }
if ([string]::IsNullOrEmpty($vol.FileSystem)) {
  Write-Step "Formatting ${Letter}: as a Dev Drive"
  # -NewFileSystemLabel, not -FileSystemLabel: the latter selects a volume by its
  # current label and conflicts with -DriveLetter.
  Format-Volume -DriveLetter $Letter -DevDrive -NewFileSystemLabel $Label -Confirm:$false -Force | Out-Null
} elseif ($vol.FileSystem -ne 'ReFS') {
  throw "${Letter}: is $($vol.FileSystem), not a Dev Drive. Not touching it."
}

# 3. Layout
foreach ($dir in $Layout) { New-Item -ItemType Directory -Force "${Letter}:\$dir" | Out-Null }

# 4. Mount at boot. A virtual disk attached by diskpart or Mount-DiskImage does not
# come back after a restart on its own.
$mount = "if (-not (Get-DiskImage -ImagePath '$Vhdx').Attached) { Mount-DiskImage -ImagePath '$Vhdx' }"
# The name carries the drive letter. It used to be a single 'Mount Dev Drive', so a
# second drive at another letter silently took over the first one's boot mount -- and
# tearing that second drive down then deleted it, leaving the first unmounted after a
# restart. Migrate the old task away, but only when it is this drive's.
$legacy = Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Mount Dev Drive' -ErrorAction SilentlyContinue
if ($legacy -and $legacy.Actions[0].Arguments -like "*$Vhdx*") {
  Unregister-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Mount Dev Drive' -Confirm:$false
  Write-Host 'Replaced the old, letter-less boot task'
}
# No colon in the name: Task Scheduler rejects one with "The parameter is incorrect".
$taskName = "Mount Dev Drive ($Letter)"
Register-ScheduledTask -TaskPath '\dotfiles\' -TaskName $taskName -Force -ErrorAction Stop `
  -Description "Attach $Vhdx as ${Letter}: at boot. Managed by the dotfiles devdrive recipe." `
  -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -Command `"$mount`"") `
  -Trigger (New-ScheduledTaskTrigger -AtStartup) `
  -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest) | Out-Null
# Confirmed, not assumed: Register-ScheduledTask reports some failures without
# stopping the script, so an unregistered task would otherwise be announced as done
# and the drive would simply not come back after a restart.
if (-not (Get-ScheduledTask -TaskPath '\dotfiles\' -TaskName $taskName -ErrorAction SilentlyContinue)) {
  throw "The boot-time mount task '$taskName' was not registered, so ${Letter}: would not come back after a restart."
}
Write-Host "Boot-time mount task registered (\dotfiles\$taskName)"

# 5. Report
$vol = Get-Volume -DriveLetter $Letter
Write-Host ("{0}: {1} {2}, {3:N0} GB free of {4:N0} GB; backing file uses {5:N1} GB on {6}" -f `
  $Letter, $vol.FileSystem, $vol.FileSystemLabel, ($vol.SizeRemaining / 1GB), ($vol.Size / 1GB), `
  ((Get-Item $Vhdx).Length / 1GB), (Split-Path -Qualifier $Vhdx))
$query = (fsutil devdrv query "${Letter}:") -join "`n"
if ($query -notmatch 'trusted developer volume') {
  Write-Warning "${Letter}: is not reported as a trusted developer volume:`n$query"
}
# fsutil lists the filters scanning this volume after a "Filters currently attached"
# heading, one per line. WdFilter is Defender's own.
$lines = @($query -split "`n" | ForEach-Object { $_.Trim() })
$start = [array]::FindIndex([string[]]$lines, [Predicate[string]] { param($l) $l -like 'Filters currently attached*' })
$filters = @()
# $start + 1 has to be a real index: a heading with nothing after it makes the range
# count *down* (N..N-1), which hands back the heading itself as a filter name and warns
# about a third-party antivirus that is not there.
if ($start -ge 0 -and ($start + 1) -lt $lines.Count) {
  $filters = @($lines[($start + 1)..($lines.Count - 1)] | Where-Object { $_ -and $_ -ne 'WdFilter' })
}
if ($filters.Count) {
  Write-Warning "Third-party filter(s) attached to ${Letter}: ($($filters -join ', ')). That is usually another antivirus: Dev Drive's performance mode needs Microsoft Defender, and heuristic engines tend to quarantine scripts like these recipes."
}
