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
# Trimmed, and the move itself is guarded: Test-Path accepts a path with a trailing
# space (Windows trims it) where Set-Location -LiteralPath does not, so a stray space
# in the variable would otherwise put a Set-Location error in front of every login --
# including the one-shot SSH commands this file is supposed to stay out of the way of.
$devRoot = if ($env:DEV_ROOT) { $env:DEV_ROOT.Trim() } else { $null }
if ($devRoot -and (Test-Path -LiteralPath $devRoot)) {
  $here = (Get-Location).ProviderPath
  if ($here -and $home -and $here.TrimEnd('\') -ieq $home.TrimEnd('\')) {
    # A convenience, never a reason for a shell to fail or print anything.
    try { Set-Location -LiteralPath $devRoot -ErrorAction Stop } catch { }
  }
}

# Node, via fnm (recipes/fnm). This block is only for *switching* versions per
# directory -- the default version is already on PATH, because the recipe puts fnm's
# aliases\default junction there, so node works in cmd, in Git Bash and in anything
# that does not read this file.
#
# --use-on-cd is what makes .nvmrc and .node-version work without thinking about it.
# Worth knowing what it does rather than discovering it: on PowerShell it does not
# hook the prompt, it aliases `cd` to a wrapper that calls `fnm use
# --silent-if-unchanged` when the directory holds .nvmrc, .node-version or
# package.json. About 14 ms when it fires, and nothing when it does not.
#
# Three guards, in order of cost, because evaluating 'fnm env' is a process spawn and
# costs about 40 ms of every shell start -- including the one-shot SSH commands this
# file is supposed to stay out of the way of. So it only runs when it will do
# something:
#   FNM_DIR set. The recipe writes it as a user variable, since it has to be in the
#   environment before fnm reads it and so cannot be set here.
#   A default alias on disk. Without this, 'fnm env' still succeeds and still aliases
#   cd, but activates nothing -- a shell with a cd hook and no node, which is a worse
#   state to debug than no integration at all.
#   fnm on PATH. Last because it scans PATH, where the two above are a variable read
#   and one Test-Path.
$fnmDir = if ($env:FNM_DIR) { $env:FNM_DIR.Trim() } else { $null }
if ($fnmDir -and (Test-Path -LiteralPath (Join-Path $fnmDir 'aliases\default'))) {
  if (Get-Command fnm -ErrorAction SilentlyContinue) {
    # Same contract as the Set-Location above: a convenience, never a reason for a
    # shell to fail or print anything. An Invoke-Expression of broken input would
    # otherwise put errors in front of every login.
    try {
      fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    } catch { }
  }
}
