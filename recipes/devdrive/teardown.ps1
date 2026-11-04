# Undoes recipes/devdrive: removes the boot-time mount task and detaches the Dev
# Drive. Deleting the backing file -- and with it everything on the drive -- is a
# separate, typed confirmation. Run elevated, from a copy of this repo that is NOT
# on the Dev Drive (a script cannot detach the disk it is running from).
#
# Uses the same DEVDRIVE_VHDX / DEVDRIVE_LETTER overrides as the install recipe.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')
Assert-Admin 'devdrive'

$Vhdx = if ($env:DEVDRIVE_VHDX) { $env:DEVDRIVE_VHDX } else { 'C:\DevDrives\dev.vhdx' }
$Letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }

if ($Root -like "${Letter}:\*") {
  throw "This repo is on ${Letter}:, the drive being removed. Copy the repo elsewhere (e.g. to Downloads) and run the teardown from there."
}

Unregister-ScheduledTask -TaskPath '\dotfiles\' -TaskName 'Mount Dev Drive' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host 'Removed the boot-time mount task'

if (-not (Test-Path $Vhdx)) {
  Write-Host "$Vhdx does not exist; nothing else to do."
  return
}
if ((Get-DiskImage -ImagePath $Vhdx).Attached) {
  Dismount-DiskImage -ImagePath $Vhdx | Out-Null
  Write-Host "Detached ${Letter}: ($Vhdx kept)"
}

Write-Host ''
Write-Host "Deleting $Vhdx permanently destroys everything that was on ${Letter}:."
$answer = Read-Host 'Type DELETE to delete it, or press Enter to keep it'
if ($answer -ceq 'DELETE') {
  Remove-Item -LiteralPath $Vhdx
  Write-Host "Deleted $Vhdx"
} else {
  Write-Host "Kept $Vhdx. Re-attach any time with: bin\install.ps1 devdrive"
}
