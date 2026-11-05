# Undoes recipes/uv: removes the uv-managed Python, uninstalls uv and clears the
# UV_* user variables. recipes/python/teardown (macOS) leaves uv itself in place
# because Homebrew owns it there; here this repo's recipe installed it, so this
# removes it too.
#
# Kept: ~\.local\bin on the user PATH (claude.exe lives there as well) and any
# project .venv directories, which belong to their projects.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$UvPythonVersion = '3.14'

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Write-Host 'uv is not on PATH; nothing to remove.'
  return
}
if (-not (Confirm-Action "Remove uv and its managed Python $UvPythonVersion? (the git hooks need python3)")) {
  Write-Host 'Skipped.'
  return
}

# Ask uv for the shim directory while uv is still here to answer.
$bin = (uv python dir --bin).Trim()
if ($LASTEXITCODE -ne 0) { $bin = Join-Path $HOME '.local\bin' }

# The managed Python goes first: uninstalling uv would orphan both it and the
# python / python3 shims that --default put in $bin.
# (Scoped 'Continue': under 'Stop', 5.1 turns redirected native stderr into a throw.)
$installed = & {
  $ErrorActionPreference = 'Continue'
  uv python find --managed-python $UvPythonVersion 2>$null | Out-Null
  $LASTEXITCODE -eq 0
}
if ($installed) {
  uv python uninstall $UvPythonVersion
  Assert-ExitCode "uv python uninstall $UvPythonVersion"
  Write-Host "Removed the uv-managed Python $UvPythonVersion"
} else {
  Write-Host "No uv-managed Python $UvPythonVersion; skipping."
}

Uninstall-WingetPackage -Id 'astral-sh.uv'

Remove-UserEnv 'UV_PYTHON_INSTALL_DIR'
Remove-UserEnv 'UV_TOOL_DIR'
Remove-UserEnv 'UV_CACHE_DIR'

# uv removes its own shims, but a half-finished install can leave launchers that
# point at a Python that is now gone, and those would shadow a later one.
$orphans = Get-ChildItem (Join-Path $bin 'python*.exe') -ErrorAction SilentlyContinue
if ($orphans) {
  Write-Warning "Left behind in ${bin}: $($orphans.Name -join ', '). Delete them, or they will shadow a later Python."
}
Write-Host 'uv removed. The privacy gate will refuse every commit until bin\install.ps1 uv runs again.'
