# Undoes recipes/uv: removes the uv-managed Python, uninstalls uv, clears the UV_*
# user variables and deletes the directories those variables pinned.
# recipes/python/teardown (macOS) leaves uv itself in place because Homebrew owns it
# there; here this repo's recipe installed it, so this removes it too.
#
# Kept: ~\.local\bin on the user PATH (claude.exe lives there as well), any project
# .venv directories, which belong to their projects, and UV_TOOL_DIR when it still
# holds tools -- `uv tool install` state is the user's, not this recipe's.
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

# Read where the install recipe pinned uv's state before Remove-UserEnv clears the
# variables that say so. The fallbacks are that recipe's defaults.
$pythonDir = if ($env:UV_PYTHON_INSTALL_DIR) { $env:UV_PYTHON_INSTALL_DIR } else { Join-Path $HOME '.local\share\uv\python' }
$toolDir = if ($env:UV_TOOL_DIR) { $env:UV_TOOL_DIR } else { Join-Path $HOME '.local\share\uv\tools' }
$cacheDir = if ($env:UV_CACHE_DIR) { $env:UV_CACHE_DIR } else { Join-Path $HOME '.cache\uv' }

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

# The cache is derived data and can reach gigabytes, so it goes with uv rather than
# being left behind for a tool that is no longer installed to find.
if (Test-Path -LiteralPath $cacheDir) {
  $size = (Get-ChildItem -LiteralPath $cacheDir -Recurse -File -Force -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum).Sum
  Remove-Item -LiteralPath $cacheDir -Recurse -Force
  Write-Host ("Removed the uv cache {0} ({1:N0} MB)" -f $cacheDir, ($size / 1MB))
}

# The pinned directories, but only when uv's own bookkeeping is all that is left in
# them: an interpreter or a tool still in there is content, and deleting it silently
# would be a surprise.
foreach ($dir in @($pythonDir, $toolDir)) {
  if (-not (Test-Path -LiteralPath $dir)) { continue }
  $content = @(Get-ChildItem -LiteralPath $dir -Force |
    Where-Object { $_.Name -notin @('.gitignore', '.lock', '.temp') })
  if ($content.Count) {
    Write-Host "Left alone (not empty): $dir -- holds $($content.Name -join ', ')"
  } else {
    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Host "Removed $dir"
  }
}
# ...and the directory that held both, once it is empty.
$share = Split-Path $pythonDir
if ((Split-Path $share -Leaf) -eq 'uv' -and (Test-Path -LiteralPath $share) -and
    -not @(Get-ChildItem -LiteralPath $share -Force).Count) {
  Remove-Item -LiteralPath $share -Force
  Write-Host "Removed $share"
}

# uv removes its own shims, but a half-finished install can leave launchers that
# point at a Python that is now gone, and those would shadow a later one.
$orphans = Get-ChildItem (Join-Path $bin 'python*.exe') -ErrorAction SilentlyContinue
if ($orphans) {
  Write-Warning "Left behind in ${bin}: $($orphans.Name -join ', '). Delete them, or they will shadow a later Python."
}
Write-Host 'uv removed. The privacy gate will refuse every commit until bin\install.ps1 uv runs again.'
