# Linked to $PROFILE.CurrentUserAllHosts by recipes/dotfiles/install.ps1.
#
# profile.ps1 (all hosts) rather than Microsoft.PowerShell_profile.ps1, so an SSH
# login shell loads it too -- which is the whole point of the Set-Location below.
#
# Keep this ASCII and 5.1-compatible: sshd launches Windows PowerShell.
# Keep it fast and quiet, too. It runs before every prompt, interactive or not, and
# anything written here is output a remote one-shot command has to step around.

# The Dev Drive is this machine's development root. sshd has no working-directory
# option and drops a login in %USERPROFILE%, so the profile moves there instead.
# DEV_ROOT is set by recipes/dotfiles/install.ps1, following DEVDRIVE_LETTER.
#
# Two guards:
#   Only from the home directory, so a deliberate location always wins -- a terminal
#   opened inside a project stays there, and an explicit `cd` in an SSH command runs
#   after this file and overrides it.
#   Only when the drive is attached. The devdrive recipe mounts it from a boot task
#   that can be slower than the first login, and a Set-Location into a drive that is
#   not there yet would fail the whole profile.
if ($env:DEV_ROOT -and (Test-Path -LiteralPath $env:DEV_ROOT)) {
  $here = (Get-Location).ProviderPath
  if ($here -and $home -and $here.TrimEnd('\') -ieq $home.TrimEnd('\')) {
    Set-Location -LiteralPath $env:DEV_ROOT
  }
}
