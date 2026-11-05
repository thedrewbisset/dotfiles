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
  return ($LASTEXITCODE -eq 0)
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
