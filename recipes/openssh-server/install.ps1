# OpenSSH Server, reachable only from the local network, keys only.
#
# Opt-in (not in 'all'): it opens a network service. Requires an elevated shell.
#
#   1. Installs the built-in Windows optional feature (Microsoft's own OpenSSH port).
#   2. Writes sshd_config from the template beside this file (original backed up once).
#   3. Copies ~/.ssh/authorized_keys into administrators_authorized_keys, because
#      Windows sshd reads only that file for admin accounts, and locks down its ACL.
#   4. Replaces the feature's own firewall rule (every profile, any address) with one
#      for the Private profile from the local subnet only. Nothing is ever forwarded
#      on the router, so traffic cannot arrive from the WAN.
#   5. Makes PowerShell the login shell and starts sshd automatically at boot.
#
# It never changes the network's Public/Private type: whether a network is trusted
# is your decision. On a Public network sshd runs but the firewall blocks it.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')
Assert-Admin 'openssh-server'

$SshDir = Join-Path $env:ProgramData 'ssh'
$Config = Join-Path $SshDir 'sshd_config'
$Backup = Join-Path $SshDir 'sshd_config.pre-dotfiles'
$AdminKeys = Join-Path $SshDir 'administrators_authorized_keys'
$Sshd = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
$RuleName = 'dotfiles-sshd-lan'
# SIDs rather than names, so the ACL works on non-English Windows.
$Administrators = '*S-1-5-32-544'
$System = '*S-1-5-18'

# 1. Feature
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') {
  Write-Step "Installing $($cap.Name) (downloads from Windows Update; can take a few minutes)"
  Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}
if (-not (Test-Path $Sshd)) { throw "sshd.exe not found at $Sshd after install." }

# sshd generates its host keys on first start; sshd -t needs them to validate.
if (-not (Test-Path (Join-Path $SshDir 'ssh_host_ed25519_key'))) {
  Start-Service sshd
  Stop-Service sshd
}

# 2. Config
if ((Test-Path $Config) -and -not (Test-Path $Backup)) {
  Copy-Item $Config $Backup
  Write-Host "Backed up the original config to $Backup"
}
$user = $env:USERNAME.ToLowerInvariant()
$template = Get-Content -Raw (Join-Path $PSScriptRoot 'sshd_config')
$rendered = $template.Replace('__ALLOW_USER__', $user)
$candidate = "$Config.dotfiles-new"
[IO.File]::WriteAllText($candidate, $rendered, (New-Object Text.UTF8Encoding $false))
& $Sshd -t -f $candidate
if ($LASTEXITCODE -ne 0) {
  Remove-Item $candidate
  throw 'The rendered sshd_config failed validation (sshd -t); the live config was not changed.'
}
Move-Item -Force $candidate $Config
Write-Host "sshd_config written (AllowUsers $user, keys only)"

# 3. Keys
$userKeys = Join-Path $HOME '.ssh\authorized_keys'
if (-not (Test-Path $userKeys)) {
  New-Item -ItemType Directory -Force (Split-Path $userKeys) | Out-Null
  New-Item -ItemType File $userKeys | Out-Null
}
$keys = @(Get-Content $userKeys | Where-Object { $_ -match '^\s*(ssh-|ecdsa-|sk-)' })
if (Test-Admin) {
  # The admin key file must be writable only by Administrators and SYSTEM, or sshd
  # silently ignores it.
  [IO.File]::WriteAllLines($AdminKeys, [string[]]$keys, (New-Object Text.UTF8Encoding $false))
  icacls $AdminKeys /inheritance:r /grant "${Administrators}:F" /grant "${System}:F" | Out-Null
  Assert-ExitCode 'icacls administrators_authorized_keys'
}
if ($keys.Count -eq 0) {
  Write-Warning "No public keys in $userKeys, so no one can log in yet. Add your other computer's public key (one line, e.g. from ~/.ssh/id_ed25519.pub) to that file and re-run this recipe."
} else {
  Write-Host "$($keys.Count) authorized key(s) installed"
}

# 4. Firewall
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue |
  Where-Object { $_.Enabled -eq 'True' } |
  Disable-NetFirewallRule
Write-Host 'Disabled the built-in OpenSSH rule (it allows every network and address)'
Remove-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
New-NetFirewallRule -Name $RuleName -DisplayName 'OpenSSH Server (LAN only, dotfiles)' `
  -Description 'Managed by the dotfiles openssh-server recipe.' `
  -Direction Inbound -Action Allow -Protocol TCP -LocalPort 22 -Program $Sshd `
  -Profile Private -RemoteAddress LocalSubnet | Out-Null
Write-Host 'Firewall: TCP 22 allowed from the local subnet on Private networks only'

# 5. Shell and service
$shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $shell -PropertyType String -Force | Out-Null
Set-Service sshd -StartupType Automatic
Restart-Service sshd
Write-Host "sshd: $((Get-Service sshd).Status), starts automatically"

# Report
$profiles = @(Get-NetConnectionProfile | Where-Object { $_.IPv4Connectivity -ne 'Disconnected' })
foreach ($p in $profiles) {
  if ($p.NetworkCategory -ne 'Private') {
    Write-Warning "Network '$($p.Name)' ($($p.InterfaceAlias)) is $($p.NetworkCategory), so the firewall blocks SSH on it. If you trust this network, set it to Private: Settings > Network & internet > $($p.InterfaceAlias) > Network profile type."
  }
}
$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -in 'Dhcp', 'Manual' } | Select-Object -ExpandProperty IPAddress
foreach ($ip in $ips) { Write-Host "Connect from the LAN with: ssh $user@$ip" }
$fp = & (Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe') -lf (Join-Path $SshDir 'ssh_host_ed25519_key.pub')
Write-Host "Host key (check it matches on first connect): $fp"
