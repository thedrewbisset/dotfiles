# Installs uv via winget and a uv-managed Python (Windows counterpart of recipes/uv/install).
#
# --default also installs python.exe / python3.exe into uv's bin directory
# (~\.local\bin), which is what the bash git hooks call as `python3`. That directory
# goes to the front of the user PATH: by default WindowsApps holds python/python3
# stubs that only open the Microsoft Store, and they would win otherwise.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$UvPythonVersion = '3.14'

# uv's Windows defaults live under AppData; pin them to the paths uv uses on macOS
# instead (see Set-UserEnv for why AppData is avoided). The bin dir already defaults
# to ~\.local\bin on both platforms.
Set-UserEnv 'UV_PYTHON_INSTALL_DIR' (Join-Path $HOME '.local\share\uv\python')
Set-UserEnv 'UV_TOOL_DIR' (Join-Path $HOME '.local\share\uv\tools')
Set-UserEnv 'UV_CACHE_DIR' (Join-Path $HOME '.cache\uv')

Install-WingetPackage -Id 'astral-sh.uv'
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  throw 'uv is not on PATH after install. Open a new shell and re-run.'
}
Write-Host (uv --version)

# --default is a uv preview feature; opting in explicitly acknowledges that it may change.
# --force replaces launchers uv no longer recognises as its own, which happens after a
# failed run (see the os error 448 check below); without it uv only warns and skips them.
uv python install --managed-python --default --preview-features python-install-default --force $UvPythonVersion
Assert-ExitCode "uv python install $UvPythonVersion"

$bin = (uv python dir --bin).Trim()
Assert-ExitCode 'uv python dir --bin'
Add-UserPathEntry $bin

$found = (Get-Command python3 -ErrorAction SilentlyContinue).Source
Write-Host "uv setup complete (python3 -> $found)"
if ($found -notlike "$bin*") {
  Write-Warning "python3 still resolves outside $bin. Turn off the python aliases in Settings > Apps > Advanced app settings > App execution aliases."
}

# uv reaches the install through a junction (cpython-3.14-... -> cpython-3.14.N-...).
# Windows refuses to let an elevated process follow a junction that a non-elevated one
# created ("untrusted mount point", os error 448), and an administrator's SSH session is
# always elevated. A junction created elevated is trusted by both, so run this recipe
# elevated (or over SSH) on a machine that is used that way.
#
# $found is invoked rather than the bare name: PATH in this shell may not yet hold $bin,
# and a name that does not resolve leaves $LASTEXITCODE untouched from the command
# before it, which would read as a pass.
if (-not $found) {
  Write-Warning "python3 is not on PATH in this shell, so the os error 448 check was skipped. Open a new shell and re-run to check it."
}
else {
  # 'Stop' turns a native command's redirected stderr into a terminating error in 5.1.
  $ErrorActionPreference = 'Continue'
  $check = (& $found -c 'print(1)' 2>&1 | ForEach-Object { "$_" }) -join ' '
  $pythonExit = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($pythonExit -ne 0) {
    Write-Warning "python3 does not run: $check"
  } elseif (-not (Test-Admin)) {
    Write-Warning ('This shell is not elevated, so elevated shells and administrator SSH ' +
      'sessions will fail to run python3 with "untrusted mount point (os error 448)". ' +
      'If the machine is used that way, re-run this recipe elevated or over SSH.')
  }
}
