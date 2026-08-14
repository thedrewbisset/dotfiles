# Reconcile Dependencies

Bundles open Dependabot PRs into a single consolidated branch using
`git merge --no-ff`, discovering the branch list automatically via `gh`
instead of a hand-maintained manifest.

This is a reboot of the earlier `patch-bundler`/`patch-bundler-poetry` skills.
Same rebase-before-merge mechanics; the manifest is now generated, not
authored, and CI validation adapts to whatever this repo's actual pipeline
does instead of assuming a specific validation-branch convention.

## Scope

**In scope**: any `dependabot/*` branch with a currently open PR
(`gh pr list --label dependencies`).

**Out of scope** (routes to `reconcile-vulnerabilities` instead):
- Open Dependabot alerts with no corresponding PR (Dependabot couldn't
  auto-generate a fix)
- Code-scanning findings (Semgrep, CodeQL, etc.) — these aren't dependency
  bumps and need a code change, not a merge

## Quick Start

1. **Prepare target branch**:
   ```bash
   git checkout -b chore/dependency-updates
   ```
2. **Run the skill**:
   ```bash
   /reconcile-dependencies
   ```
   No manifest to prepare — the skill queries `gh pr list --label dependencies`
   itself and generates its own tracking file.
3. **Review the summary**: COMPLETED branches (tagged patch/minor/major),
   ESCALATED branches, and any alerts with no auto-fix PR.
4. **CI validation**: the skill detects whether this repo needs a dedicated
   validation branch or can validate directly on a PR to the real target —
   see [ci-validation.md](ci-validation.md).

## Why Merge --no-ff

- Preserves commit SHAs → GitHub auto-closes Dependabot PRs on merge
- Explicit merge commits show exactly what was bundled
- `git log --oneline --graph` gives a clear audit trail

## Files

```
reconcile-dependencies/
├── SKILL.md                       # Entry point
├── README.md                      # This file
├── discovery.md                   # gh-cli branch discovery + alert cross-check
├── base-merge-logic.md            # Core rebase-before-merge workflow
├── ci-validation.md               # Repo-adaptive CI push/validation
├── platform-detector.md           # Platform detection from branch names
├── dependabot-branches.example.md # What the generated manifest looks like
└── package-managers/
    ├── yarn.md
    ├── gradle.md
    ├── cocoapods.md
    ├── github-actions.md
    └── poetry.md
```

## Version Control

Personal skill, lives in `~/.claude/skills/` via symlink to this dotfiles
repo — available across all projects, not tied to any single repo's `.git`.
