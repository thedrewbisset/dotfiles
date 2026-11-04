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
uv python install --managed-python --default --preview-features python-install-default $UvPythonVersion
Assert-ExitCode "uv python install $UvPythonVersion"

$bin = (uv python dir --bin).Trim()
Assert-ExitCode 'uv python dir --bin'
Add-UserPathEntry $bin

$found = (Get-Command python3 -ErrorAction SilentlyContinue).Source
Write-Host "uv setup complete (python3 -> $found)"
if ($found -notlike "$bin*") {
  Write-Warning "python3 still resolves outside $bin. Turn off the python aliases in Settings > Apps > Advanced app settings > App execution aliases."
}
