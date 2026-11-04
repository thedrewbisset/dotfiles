# Installs (or upgrades) Git for Windows via winget.
#
# Two installer options are chosen deliberately; both land in Git's *system* config,
# so ~/.gitconfig (symlinked from source/.gitconfig by the dotfiles recipe) stays
# identical on macOS and Windows:
#   CRLFOption=CRLFCommitAsIs  core.autocrlf=false. The installer's default (true)
#                              rewrites LF to CRLF on checkout, which breaks every bash
#                              recipe in this repo. .gitattributes enforces LF here too.
#   SSHOption=ExternalOpenSSH  Use Windows' own OpenSSH (System32) instead of the copy
#                              bundled with Git, so git shares the Windows ssh-agent
#                              service and ~/.ssh with every other tool.
# These options only apply on first install; upgrades keep the original choices.
param([string]$Root, [string]$Target)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'bin\lib\tools.ps1')

Install-WingetPackage -Id 'Git.Git' -Custom '/o:CRLFOption=CRLFCommitAsIs /o:SSHOption=ExternalOpenSSH'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'git is not on PATH after install. Open a new shell and re-run.'
}
Write-Host (git --version)

$autocrlf = git config --system --get core.autocrlf
if ($autocrlf -ne 'false') {
  Write-Warning "core.autocrlf is '$autocrlf' (expected 'false'). Git was probably installed before this recipe; LF files may be rewritten on checkout. Fix with an elevated: git config --system core.autocrlf false"
}
