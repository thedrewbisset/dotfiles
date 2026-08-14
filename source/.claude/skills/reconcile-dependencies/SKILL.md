---
name: reconcile-dependencies
description: Discover open Dependabot PRs via GitHub CLI and bundle them into a consolidated branch using git merge --no-ff (supports Yarn, Gradle, CocoaPods, GitHub Actions, Poetry)
allowed-tools: Read, Grep, Bash, Edit
disable-model-invocation: true
argument-hint: "[target-branch]"
---

# Reconcile Dependencies

Discovers open Dependabot PRs for the current repo via `gh`, bundles them into
a single consolidated branch using `git merge --no-ff`, and pushes for CI
validation. This is the mechanical path: only branches with a live Dependabot
PR are in scope. Alerts with no auto-fix PR, and non-dependency security
findings, are out of scope — those route to `reconcile-vulnerabilities`.

**Supported Platforms**: JavaScript/TypeScript (Yarn), Android (Gradle), iOS
(CocoaPods), GitHub Actions, Python (Poetry).

## Task

Target branch: ${1:-current checked-out branch} (e.g. `chore/dependency-updates`,
`fix/dependency-updates-YYYYMMDD`)

## Workflow

1. **Prerequisites check**: confirm target branch, confirm clean `git status`
2. **Discover branches**: follow [discovery.md](discovery.md) — queries `gh pr
   list --label dependencies` and cross-checks against `gh api
   .../dependabot/alerts` for alerts with no matching PR. Generates the
   tracking manifest; the user never hand-authors one.
3. **Classify risk tier** per branch (discovery.md Step 3): patch/minor vs.
   major vs. grouped — this doesn't change merge mechanics, only what gets
   flagged in the final summary.
4. **Detect platform** per branch using [platform-detector.md](platform-detector.md)
5. **Load package manager config** from `package-managers/<platform>.md`
6. **Follow rebase-merge logic** in [base-merge-logic.md](base-merge-logic.md)
   for every branch not already COMPLETED
7. **Push for CI validation** using [ci-validation.md](ci-validation.md) —
   detects whether this repo needs a dedicated validation branch or can run
   CI directly on the real target PR
8. **Report summary**: COMPLETED (by tier), ESCALATED, and alerts with no
   auto-fix PR (hand off to `reconcile-vulnerabilities`)

## Core Principles

1. **Discover, don't transcribe**: branch list comes from `gh`, not a
   hand-maintained file
2. **Rebase first**: rebase each branch onto the accumulating branch before
   merging — conflicts resolved during rebase, merges are clean
3. **Safety first**: save commit SHA before each operation for rollback
4. **Incremental progress**: update tracking file after each branch
5. **Conservative on conflicts**: only auto-resolve lock file conflicts;
   escalate manifest and source conflicts by default
6. **Lock conflicts resolve from `--ours`, never `--theirs`**: `--theirs` in a
   rebase is the stale dependabot branch's own lock file; starting from it
   silently drags previously-merged package versions backward. Always accept
   `--ours` (the accumulating branch) before regenerating — see
   base-merge-logic.md.
7. **Every regeneration gets verified, not trusted**: after every lock file
   regeneration, diff against the pre-rebase accumulating-branch HEAD and
   confirm no package regressed. A regeneration can exit 0 and pass
   `poetry check --lock` / equivalent while still silently downgrading a
   package a prior merge in the same run already fixed — this check is the
   only thing that catches that failure mode.
8. **Flag majors, don't gate on them**: major-version bumps still get bundled,
   but are called out distinctly in the summary rather than merged silently
   alongside patches
9. **CI-adaptive**: don't assume a specific validation branch convention —
   detect what this repo actually does

## Output Format

```
- dependabot/pip/redis-8.0.0: COMPLETED (major)
- dependabot/github_actions/actions/checkout-7: COMPLETED (patch)
- dependabot/pip/cryptography-...: ESCALATED
  - Exception Files: pyproject.toml
  - Log Output:
    ```
    SolverProblemError: ...
    ```

## Alerts With No Auto-Fix PR (route to reconcile-vulnerabilities)
- #95 cryptography (medium): wildcard DNS name verification bypass
```

## Important Notes

- Should only be invoked manually
- Target branch must be checked out before running
- Tracking file is generated, untracked, and NEVER committed
- Use `origin/<branch-name>` when merging to ensure remote branches are used
- **CRITICAL**: only merge commits are created — never commit the tracking file
- Local validation is minimal; CI is authoritative (see ci-validation.md)
- Conservative by default: when in doubt about conflict resolution, ESCALATE
