# Undoes recipes/dotfiles: removes the links it created and unsets DEV_ROOT.
#
# Only links pointing inside this repo are removed, so a file someone wrote by hand,
# or a link to somewhere else, is reported and left alone. Where the install recipe
# kept a <name>.pre-dotfiles copy, it is moved back.
#
# Kept: ~\.ssh itself and everything in it except the config link (private keys,
# authorized_keys, config.local), and ~\.gitconfig-identities, which is yours and
# gitignored. The Dev Drive is the devdrive recipe's to remove.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$profileLink = if ($Target -eq $HOME) {
  $PROFILE.CurrentUserAllHosts
} else {
  Join-Path $Target 'Documents\WindowsPowerShell\profile.ps1'
}

foreach ($path in @(
    (Join-Path $Target '.gitconfig'),
    (Join-Path $Target '.git-excludes-file'),
    (Join-Path $Target '.ssh\config'),
    $profileLink)) {
  Remove-RepoLink $path $Root
}

# Machine-wide, so a -Target run leaves it alone, as the install recipe does.
if ($Target -eq $HOME) {
  Remove-UserEnv 'DEV_ROOT'
  Write-Host 'New shells start in the home directory again.'
} else {
  Write-Host 'Left DEV_ROOT alone (-Target run, and the user environment is machine-wide)'
}
