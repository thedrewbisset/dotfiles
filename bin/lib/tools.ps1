# Shared helpers for the Windows recipes (the PowerShell counterpart of bin/lib/tools).
# Dot-sourced by bin/install.ps1 and bin/teardown.ps1; targets Windows PowerShell 5.1,
# which ships with every Windows install, so bootstrapping needs nothing preinstalled.
# Keep this file ASCII: 5.1 reads BOM-less scripts in the ANSI code page.

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

# Native commands don't throw on failure, even with $ErrorActionPreference = 'Stop'.
function Assert-ExitCode([string]$What, [int[]]$Allowed = @(0)) {
  if ($Allowed -notcontains $LASTEXITCODE) {
    throw "$What failed (exit code $LASTEXITCODE)"
  }
}

# Re-read PATH from the registry so tools installed earlier in this run are found
# without opening a new shell.
function Update-SessionPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

# Sets a user environment variable persistently and in this session.
#
# Recipes use this to pin tool state outside %APPDATA% / %LOCALAPPDATA%. Packaged
# (MSIX) apps such as the Claude desktop app silently redirect AppData writes made
# by the processes they launch into their own private storage, so a tool run from
# one of them would install somewhere your own shells never see. Registry writes
# are not redirected, which is why pinning via environment variables works.
function Set-UserEnv([string]$Name, [string]$Value) {
  if ([Environment]::GetEnvironmentVariable($Name, 'User') -ne $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Write-Host "Set user env $Name=$Value"
  }
  Set-Item -Path "env:$Name" -Value $Value
}

# Removes a user environment variable, in the registry and in this session. The
# teardown counterpart of Set-UserEnv; a variable it never set is left alone.
function Remove-UserEnv([string]$Name) {
  if ($null -ne [Environment]::GetEnvironmentVariable($Name, 'User')) {
    [Environment]::SetEnvironmentVariable($Name, $null, 'User')
    Write-Host "Removed user env $Name"
  }
  Remove-Item -Path "env:$Name" -ErrorAction SilentlyContinue
}

# Puts $Dir at the front of the *user* PATH (persisted), ahead of WindowsApps, whose
# python/python3 "App execution alias" stubs would otherwise shadow real installs.
function Add-UserPathEntry([string]$Dir) {
  $entries = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })
  if ($entries.Count -gt 0 -and $entries[0] -ieq $Dir) { return }
  $rest = $entries | Where-Object { $_ -ine $Dir }
  [Environment]::SetEnvironmentVariable('Path', ((@($Dir) + $rest) -join ';'), 'User')
  Write-Host "Moved $Dir to the front of the user PATH."
  Update-SessionPath
}

# True when a symlink can actually be created in $Dir.
#
# Creating one needs SeCreateSymbolicLinkPrivilege, which only Administrators hold:
# UAC strips it from an interactive logon's filtered token, while an SSH logon keeps
# it (sshd's logon is not filtered), and Developer Mode changes the rules again. None
# of that is inferred here -- this creates one throwaway link with the same call the
# caller will use, so the answer cannot disagree with what happens next.
function Test-CanSymlink([string]$Dir, [string]$ProbeTarget) {
  $probe = Join-Path $Dir ('.dotfiles-link-probe-' + [guid]::NewGuid().ToString('N'))
  try {
    New-Item -ItemType SymbolicLink -Path $probe -Target $ProbeTarget -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  } finally {
    # Deletes the link, never what it points at.
    if (Get-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue) {
      Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
  }
}

# Returns the path a link points at, or $null for anything that is not a link.
# 5.1 reports .Target as a collection, so take the first entry.
function Get-LinkTarget([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if (-not $item) { return $null }
  if (-not $item.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) { return $null }
  return @($item.Target)[0]
}

# Links $TargetPath -> $SourcePath: the counterpart of set_link in bin/lib/tools.
#
# A link already pointing at $SourcePath is left alone, so recipes stay idempotent.
# Anything else in the way is a conflict and the caller decides, as on macOS; an
# overwritten real file is kept as <name>.pre-dotfiles, the same convention the
# openssh-server recipe uses for sshd_config.
function Set-Link([string]$SourcePath, [string]$TargetPath) {
  if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Nothing to link: $SourcePath does not exist."
  }
  $source = (Resolve-Path -LiteralPath $SourcePath).ProviderPath
  $existing = Get-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue

  if ($existing) {
    $current = Get-LinkTarget $TargetPath
    if ($current -and ([IO.Path]::GetFullPath($current) -ieq $source)) {
      Write-Host "Already linked: $TargetPath -> $source"
      return
    }
    Write-Host "Found conflicting file: $TargetPath"
    if ($current) { Write-Host "  (a link to $current)" }
    if (-not (Confirm-Action 'Overwrite it?')) {
      Write-Host "Skipping $TargetPath"
      return
    }
    # Only a real file is worth keeping; a link holds no content of its own.
    if (-not $current) {
      $backup = "$TargetPath.pre-dotfiles"
      Move-Item -LiteralPath $TargetPath -Destination $backup -Force
      Write-Host "  kept the original as $backup"
    } else {
      Remove-Item -LiteralPath $TargetPath -Force -Recurse
    }
  }

  New-Item -ItemType SymbolicLink -Path $TargetPath -Target $source -ErrorAction Stop | Out-Null
  Write-Host "Linked $TargetPath -> $source"
}

# Removes $TargetPath only if it is a link pointing inside $Root, so a teardown can
# never delete a real file someone wrote by hand, or a link to somewhere else.
function Remove-RepoLink([string]$TargetPath, [string]$Root) {
  $current = Get-LinkTarget $TargetPath
  if (-not $current) {
    if (Test-Path -LiteralPath $TargetPath) { Write-Host "Left alone (not a link): $TargetPath" }
    return
  }
  $full = [IO.Path]::GetFullPath($current)
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  if (-not ($full -like "$rootFull\*")) {
    Write-Host "Left alone (links outside this repo): $TargetPath -> $current"
    return
  }
  Remove-Item -LiteralPath $TargetPath -Force -Recurse
  Write-Host "Removed link: $TargetPath"
  $backup = "$TargetPath.pre-dotfiles"
  if (Test-Path -LiteralPath $backup) {
    Move-Item -LiteralPath $backup -Destination $TargetPath -Force
    Write-Host "Restored the original from $backup"
  }
}

function Assert-Winget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
  }
}

# Only the community 'winget' source is used, never 'msstore', so runs are
# reproducible and never stop at the Store's terms prompt.
$script:WingetCommon = @('--exact', '--source', 'winget', '--disable-interactivity')

function Test-WingetPackage([string]$Id) {
  winget list --id $Id @script:WingetCommon | Out-Null
  $found = ($LASTEXITCODE -eq 0)
  # "No installed package found" (exit 20) is an answer, not a failure. Left alone it
  # becomes the exit code of a teardown that correctly found nothing to remove.
  $global:LASTEXITCODE = 0
  return $found
}

# Installs a package, or upgrades it if already present. $Custom is appended to the
# installer's own arguments (winget --custom), e.g. Inno Setup /o: options.
function Install-WingetPackage([string]$Id, [string]$Custom) {
  Assert-Winget
  $agree = @('--silent', '--accept-package-agreements')
  if (Test-WingetPackage $Id) {
    Write-Step "$Id is installed; checking for upgrades"
    winget upgrade --id $Id @script:WingetCommon @agree
    # 0x8A15002B: no applicable upgrade (already current).
    Assert-ExitCode "winget upgrade $Id" @(0, -1978335189)
  } else {
    Write-Step "Installing $Id"
    $extra = @()
    if ($Custom) { $extra = @('--custom', $Custom) }
    winget install --id $Id @script:WingetCommon @agree @extra
    Assert-ExitCode "winget install $Id"
  }
  Update-SessionPath
}

function Uninstall-WingetPackage([string]$Id) {
  Assert-Winget
  if (-not (Test-WingetPackage $Id)) {
    Write-Host "$Id is not installed; nothing to do."
    return
  }
  Write-Step "Uninstalling $Id"
  winget uninstall --id $Id @script:WingetCommon --silent
  Assert-ExitCode "winget uninstall $Id"
  Update-SessionPath
}

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin([string]$Recipe) {
  if (-not (Test-Admin)) {
    throw "The $Recipe recipe changes machine-wide settings. Run it from an elevated PowerShell (Run as administrator)."
  }
}

function Confirm-Action([string]$Question) {
  $answer = Read-Host "$Question [y/N]"
  return ($answer -match '^(y|yes)$')
}

# Where ollama is, and whether it is answering. Both live here because four callers
# needed them -- the two bin wrappers, the ollama recipe and its teardown -- and four
# copies of a socket probe is four places to fix when one of them is wrong.
function Get-OllamaExe {
  $cmd = Get-Command ollama -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  # PATH in this shell can predate the install; the per-user installer puts it here.
  $fallback = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
  if (Test-Path -LiteralPath $fallback) { return $fallback }
  throw "Cannot find ollama.exe (checked PATH and $fallback). Run: bin\install.ps1 ollama"
}

# A bounded wait rather than Connect(), which is the whole reason this is a function.
# Measured on Windows: a *closed* loopback port costs about 2,050 ms of SYN retries,
# against 155 ms for a bounded wait that gives up -- so a plain Connect() turns every
# "is it up?" into a two-second pause on exactly the path that is already failing.
function Test-OllamaUp([int]$Port = 11434, [int]$TimeoutMs = 500) {
  $client = New-Object Net.Sockets.TcpClient
  try {
    $connect = $client.ConnectAsync('127.0.0.1', $Port)
    if (-not $connect.Wait($TimeoutMs)) { return $false }
    return $client.Connected
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}
