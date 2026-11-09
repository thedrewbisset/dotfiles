# Claude Code CLI installation only (Windows counterpart of recipes/claude/install).
#
# Agent configuration lives in its own repository with its own installer, as on
# macOS. ~/.claude must stay a real directory: it is Claude Code's live home and
# holds runtime state that must never enter a repository.
#
# Uses Anthropic's native installer, like the macOS recipe, so both platforms
# update the same way (the CLI updates itself). On Windows the CLI's Bash tool runs
# through Git Bash, which recipes/git provides.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

$claudeHome = Join-Path $Target '.claude'
$item = Get-Item $claudeHome -Force -ErrorAction SilentlyContinue
if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
  throw "$claudeHome is a symlink or junction. It must be a real directory so Claude's runtime state stays out of any repo."
}

if (Get-Command claude -ErrorAction SilentlyContinue) {
  Write-Host "Claude Code CLI already installed ($(claude --version))"
} elseif (Confirm-Action "Install Claude Code CLI? (Anthropic's native installer)") {
  Write-Step 'Installing Claude Code CLI'
  # In a child shell so the installer's own error handling can't end this run.
  powershell -NoProfile -ExecutionPolicy Bypass -Command 'irm https://claude.ai/install.ps1 | iex'
  Assert-ExitCode 'Claude Code installer'
  Update-SessionPath
  if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "Installed $(claude --version)"
  } else {
    Write-Warning 'Installed, but claude is not on PATH in this shell yet. Open a new shell (or reconnect over SSH).'
  }
} else {
  Write-Host 'Skipping Claude Code CLI installation.'
}

Write-Host 'Agent configuration is managed outside this repo; nothing linked here.'
