# Uninstalls the GitHub CLI. Logins (in Windows Credential Manager), ~\.config\gh and
# the GH_CONFIG_DIR user variable are kept, so a reinstall picks up where it left off.
# Run `gh auth logout` first to remove a login as well.
#
# The credential helper the install recipe wrote IS removed: it shells out to gh, so
# leaving it behind would break every HTTPS push once gh is gone, and the failure
# would come back as a credential prompt rather than anything naming gh.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

if (-not (Confirm-Action 'Uninstall the GitHub CLI?')) {
  Write-Host 'Skipped.'
  return
}
Uninstall-WingetPackage -Id 'GitHub.cli'

# Probed before removing: --remove-section is a fatal error when the section is not
# there, and that is the normal state on a machine that never ran the install recipe.
# --get-all just exits non-zero. ('Stop' would turn a native command's redirected
# stderr into a terminating error, so neither call merges it into the output stream.)
#
# Never through a link: `git config --file` follows one and rewrites the file at the
# other end, leaving the link in place, so once recipes/dotfiles has linked
# ~/.gitconfig this would quietly edit the tracked source/.gitconfig instead.
$gitconfig = Join-Path $Target '.gitconfig'
$linked = Get-LinkTarget $gitconfig
if ($linked) {
  Write-Host "$gitconfig is a link to $linked, so its credential helper was left as it is."
  Write-Host 'That file is tracked; change it there if you mean to.'
}
elseif (Test-Path -LiteralPath $gitconfig) {
  $removed = $false
  foreach ($hostUrl in 'https://github.com', 'https://gist.github.com') {
    git config --file $gitconfig --get-all "credential.$hostUrl.helper" *> $null
    if ($LASTEXITCODE -ne 0) { continue }
    git config --file $gitconfig --remove-section "credential.$hostUrl"
    Assert-ExitCode "git config --remove-section credential.$hostUrl"
    $removed = $true
  }
  if ($removed) { Write-Host "Removed the gh credential helper from $gitconfig." }
  # A missing section is the expected case, so the probe's non-zero code is not a
  # failure of this recipe and should not leak into the caller's shell.
  $global:LASTEXITCODE = 0
}
