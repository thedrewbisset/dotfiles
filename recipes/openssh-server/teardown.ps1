# Undoes recipes/openssh-server: stops and disables sshd, removes the LAN firewall
# rule, restores the original sshd_config and the default login shell. Requires an
# elevated shell.
#
# Kept: host keys (so a reinstall keeps the same fingerprint and clients don't see a
# "host key changed" warning), ~/.ssh/authorized_keys, and the network's
# Public/Private type, which this recipe never changes. Removing the Windows feature
# itself is offered, not assumed.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')
Assert-Admin 'openssh-server'

$SshDir = Join-Path $env:ProgramData 'ssh'
$Config = Join-Path $SshDir 'sshd_config'
$Backup = Join-Path $SshDir 'sshd_config.pre-dotfiles'

if (Get-Service sshd -ErrorAction SilentlyContinue) {
  Stop-Service sshd
  Set-Service sshd -StartupType Disabled
  Write-Host 'sshd stopped and disabled'
}

Remove-NetFirewallRule -Name 'dotfiles-sshd-lan' -ErrorAction SilentlyContinue
Write-Host 'Removed the LAN-only firewall rule (the built-in rule stays disabled)'

if (Test-Path $Backup) {
  Move-Item -Force $Backup $Config
  Write-Host 'Restored the original sshd_config'
}
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -eq 'Installed' -and (Confirm-Action 'Also remove the OpenSSH Server Windows feature?')) {
  Remove-WindowsCapability -Online -Name $cap.Name | Out-Null
  Write-Host 'OpenSSH Server feature removed'
}
