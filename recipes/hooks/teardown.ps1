# Undoes recipes/hooks: points this clone's git hooks back at git's default
# .git/hooks, so nothing in hooks/ runs any more. Only this clone is touched, and
# only its local config.
#
# Kept: the deny-list. It lives outside the repo
# (~\.config\exponential\denylist.txt) and is shared by every clone and worktree,
# so deleting it here would disarm the gate everywhere else too.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

# --local, because a hooksPath set globally is not this recipe's to unset.
# (Scoped 'Continue': --get exits 1 when the key is unset, and under 'Stop' 5.1
# turns redirected native stderr into a throw.)
$current = & {
  $ErrorActionPreference = 'Continue'
  git -C $Root config --local --get core.hooksPath 2>$null
}
if (-not $current) {
  Write-Host 'core.hooksPath is not set in this clone; nothing to do.'
  return
}

Write-Host "This clone runs the hooks in $current, including the privacy gate that"
Write-Host 'checks every commit against the deny-list.'
if (-not (Confirm-Action 'Disable them for this clone?')) {
  Write-Host 'Skipped.'
  return
}

git -C $Root config --local --unset core.hooksPath
Assert-ExitCode 'git config --unset core.hooksPath'
Write-Host 'core.hooksPath unset: commits in this clone are no longer gated.'
