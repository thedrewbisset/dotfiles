# Node, through fnm (Fast Node Manager), with its versions and npm's cache on the
# Dev Drive.
#
# Why fnm and not a port of recipes/nvm. That recipe installs nvm-sh, which is not a
# program but a few thousand lines of POSIX shell function sourced into bash or zsh.
# There is nothing to port: the thing itself is the shell. fnm is a single Rust binary
# that runs on both platforms, reads the same .nvmrc and .node-version files, and is
# in winget -- so the Windows side gets a version manager without inventing a second
# set of habits, and macOS could later move onto the same tool for free.
#
# Why not nvm-windows, the obvious name-match: despite the name it is an unrelated
# program with its own CLI, it switches versions by replacing a *symlink*, and
# creating one needs SeCreateSymbolicLinkPrivilege, which only Administrators hold.
# fnm uses directory junctions instead -- verified, both %LOCALAPPDATA%\fnm_multishells
# \<pid> and <FNM_DIR>\aliases\default are junctions -- and a junction needs no
# privilege at all. So fnm installs and switches from an ordinary shell where
# nvm-windows wants elevation for routine work. Volta is the other serious option and
# shims instead of hooking the shell, which is tidier, but it pins versions in
# package.json rather than reading .nvmrc, so it would not share version files with
# the macOS side.
#
# Why the Dev Drive. This is the workload Dev Drives exist for: node_modules is
# hundreds of thousands of small files, and the volume is ReFS with Defender in
# performance mode. Everything that gets written a lot goes there --
#   <drive>:\caches\fnm    node versions themselves, and the default alias
#   <drive>:\caches\npm    npm's cache
# -- and 'npm config get prefix' then resolves *through* the alias junction, so global
# installs land on the Dev Drive too without setting a prefix. Setting one would be a
# mistake: a fixed prefix is shared across every Node version, which is the conflict
# recipes/nvm deletes a leftover prefix to avoid.
#
# Defaults, each overridable with an environment variable:
#   FNM_DIR            <DEVDRIVE_LETTER>:\caches\fnm   (falls back under $HOME)
#   FNM_RECIPE_NODE    24                              (major, or a full version)
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$NodeVersion = if ($env:FNM_RECIPE_NODE) { $env:FNM_RECIPE_NODE } else { '24' }

# 1. Where the versions and the cache go. The Dev Drive when it is attached, and
# home-relative XDG paths when it is not, the way recipes/uv pins uv -- so this recipe
# is safe in 'all' on a machine that never ran recipes/devdrive.
$letter = if ($env:DEVDRIVE_LETTER) { $env:DEVDRIVE_LETTER } else { 'D' }
$cacheRoot = "${letter}:\caches"
if (-not (Test-Path -LiteralPath "${letter}:\")) {
  Write-Warning ("Drive ${letter}: is not attached, so Node is going under your home directory " +
    'instead of the Dev Drive. Run an elevated bin\install.ps1 devdrive first to get the ' +
    'ReFS and Defender-performance-mode win on node_modules, then re-run this recipe.')
  $FnmDir = Join-Path $HOME '.local\share\fnm'
  $NpmCache = Join-Path $HOME '.cache\npm'
  $CorepackHome = Join-Path $HOME '.cache\corepack'
} else {
  # An FNM_DIR already set by an earlier run is the default, so a re-run does not
  # relocate the versions out from under a shell that is using them.
  $FnmDir = if ($env:FNM_DIR) { $env:FNM_DIR } else { Join-Path $cacheRoot 'fnm' }
  $NpmCache = Join-Path $cacheRoot 'npm'
  $CorepackHome = Join-Path $cacheRoot 'corepack'
}

$settings = [ordered]@{
  # Read by fnm itself. Must be set before 'fnm env' runs in a shell, which is why it
  # is a user variable rather than something the profile exports.
  FNM_DIR          = $FnmDir
  # npm reads npm_config_<key> for any config key. Its default is
  # %LOCALAPPDATA%\npm-cache, which is both off the Dev Drive and inside the AppData a
  # packaged (MSIX) app redirects for its child processes.
  npm_config_cache = $NpmCache
  # Same reasoning for corepack, which is how yarn and pnpm arrive if they ever do.
  # Harmless when unused; fnm leaves corepack off unless --corepack-enabled is given.
  COREPACK_HOME    = $CorepackHome
}
if ($Target -eq $HOME) {
  foreach ($name in $settings.Keys) { Set-UserEnv $name $settings[$name] }
} else {
  foreach ($name in $settings.Keys) { Write-Host "Would set $name=$($settings[$name])" }
  Write-Host 'Skipped: -Target run, and the user environment is machine-wide.'
}
foreach ($dir in @($FnmDir, $NpmCache)) { New-Item -ItemType Directory -Force $dir | Out-Null }

# 2. fnm itself.
Install-WingetPackage -Id 'Schniz.fnm'
Update-SessionPath
if (-not (Get-Command fnm -ErrorAction SilentlyContinue)) {
  throw 'fnm is not on PATH after install. Open a new shell and re-run.'
}
Write-Host (fnm --version)

# 3. Node. Set FNM_DIR for this process too: Set-UserEnv writes the registry, which
# the *next* shell reads, so without this the install would land in fnm's default
# %APPDATA%\fnm and nothing afterwards would find it.
$env:FNM_DIR = $FnmDir
Write-Step "Installing Node $NodeVersion into $FnmDir"
# Idempotent: an already-installed version warns on stderr and exits 0.
fnm install $NodeVersion
Assert-ExitCode "fnm install $NodeVersion"
fnm default $NodeVersion
Assert-ExitCode "fnm default $NodeVersion"

# 4. Verify by running the real binaries rather than by trusting the exit codes above.
# Resolved through the default alias, not through the shell, because the shell
# integration lands in the profile and does not apply to this process. 'fnm exec' is
# not used for npm: npm is a .cmd shim rather than an executable, and fnm cannot spawn
# it ("program not found").
$defaultDir = Join-Path $FnmDir 'aliases\default'
$nodeExe = Join-Path $defaultDir 'node.exe'
$npmCmd = Join-Path $defaultDir 'npm.cmd'
foreach ($exe in @($nodeExe, $npmCmd)) {
  if (-not (Test-Path -LiteralPath $exe)) { throw "fnm reported success but $exe is missing." }
}
$nodeReported = (& $nodeExe --version)
Assert-ExitCode 'node --version'
$npmReported = (& $npmCmd --version)
Assert-ExitCode 'npm --version'

# The pinned cache is worth confirming rather than assuming: it is an env var npm may
# or may not have picked up, and a cache quietly back on C: defeats the point.
$env:npm_config_cache = $NpmCache
$cacheReported = (& $npmCmd config get cache)
Assert-ExitCode 'npm config get cache'

# 5. Put the default version on PATH directly.
#
# fnm's own integration works by giving each shell a private junction and prepending
# it, which means node exists only in a shell that has evaluated 'fnm env' -- not in
# cmd, not in Git Bash, not in a tool that spawns a shell of its own. aliases\default
# is a stable junction that fnm repoints when 'fnm default' changes, so putting it on
# PATH makes node work everywhere without a per-shell process spawn.
#
# This does not fight the shell integration: 'fnm env' rebuilds PATH with its
# per-shell directory in front, so a version switched in a shell still wins there and
# this entry is the fallback.
if ($Target -eq $HOME) {
  Add-UserPathEntry $defaultDir
} else {
  Write-Host "Would add $defaultDir to the user PATH."
}

Write-Host ''
Write-Host "node $nodeReported, npm $npmReported"
Write-Host "versions:  $FnmDir"
Write-Host "npm cache: $cacheReported"
Write-Host ''
Write-Host 'The default version is on the user PATH, so node works in any new shell --'
Write-Host 'not in this one, since PATH and the variables above are read at startup.'
Write-Host 'Per-directory switching on .nvmrc, .node-version or package.json comes from the'
Write-Host 'fnm block in source/windows/profile.ps1, which the dotfiles recipe links; it'
Write-Host 'aliases cd to do the switch, costing about 14 ms when it fires.'
Write-Host ''
Write-Host 'Try it in a new shell:  node --version'
Write-Host '                        fnm list'
