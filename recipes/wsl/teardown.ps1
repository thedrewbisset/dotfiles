# Undoes recipes/wsl: stops the distro and, on a typed confirmation, unregisters it.
#
# Unregistering deletes the distro's entire filesystem, its home directory included,
# so that half is deliberate and typed -- the same treatment the Dev Drive's backing
# file gets. The two Windows features are left enabled: disabling them is a
# machine-wide change needing another restart, and nothing is improved by having them
# off. The last lines print the commands if you want them gone anyway.
#
# Uses the same WSL_DISTRO override as the install recipe.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')
Assert-Admin 'wsl'

# Set before the first wsl call for the reason the install recipe explains: 5.1 cannot
# read wsl.exe's default UTF-16LE output, so a listing would be unparseable.
$env:WSL_UTF8 = '1'
$Distro = if ($env:WSL_DISTRO) { $env:WSL_DISTRO } else { 'Ubuntu' }

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  Write-Host 'wsl.exe is not present; nothing to do.'
  return
}

$listed = @(wsl.exe --list --quiet)
# No distros at all is an answer, not a failure.
$global:LASTEXITCODE = 0
$registered = @($listed | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($registered -notcontains $Distro) {
  Write-Host "$Distro is not registered; nothing to stop or remove."
} else {
  wsl.exe --terminate $Distro | Out-Null
  $global:LASTEXITCODE = 0
  Write-Host "Stopped $Distro. Any tmux server that was running inside it is gone."

  Write-Host ''
  Write-Host "Unregistering $Distro permanently deletes its filesystem: its home directory,"
  Write-Host 'shell history, any tmux-resurrect saves, and anything else not kept on a Windows'
  Write-Host 'drive. The linked ~/.tmux.conf is only a link -- source/.tmux.conf in this repo is'
  Write-Host 'untouched either way.'
  $answer = Read-Host "Type DELETE to unregister $Distro, or press Enter to keep it"
  if ($answer -ceq 'DELETE') {
    wsl.exe --unregister $Distro
    Assert-ExitCode "wsl --unregister $Distro"
    Write-Host "Unregistered $Distro"
  } else {
    Write-Host "Kept $Distro. Start it again any time with: wsl -d $Distro"
  }
}

# Only after the listing above, which needs it.
if ($Target -eq $HOME) {
  Remove-UserEnv 'WSL_UTF8'
} else {
  Write-Host 'Left WSL_UTF8 alone (-Target run, and the user environment is machine-wide)'
}

Write-Host ''
Write-Host 'Left the WSL platform installed. To remove it as well -- machine-wide, and it'
Write-Host 'needs a restart -- from an elevated shell:'
Write-Host '  dism /online /disable-feature /featurename:VirtualMachinePlatform /norestart'
Write-Host '  dism /online /disable-feature /featurename:Microsoft-Windows-Subsystem-Linux /norestart'
