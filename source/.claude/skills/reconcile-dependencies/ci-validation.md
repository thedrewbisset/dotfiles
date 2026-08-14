# Post-Merge CI Validation (Repo-Adaptive)

The original patch-bundler hardcoded a `codeql-build-verification` base branch,
which was specific to one repo's CI setup (a dedicated validation branch that
triggered `codeql.yml`). That convention doesn't generalize — most repos run
their real CI directly on `pull_request`, so a separate validation branch is
unnecessary indirection. This skill detects what a given repo actually does
instead of assuming a specific branch name.

## Step 1: Detect the Validation Path

Before pushing, check how this repo's CI is triggered:

```bash
gh workflow list
grep -rl "pull_request" .github/workflows/*.yml
```

Two cases:

**A. CI runs on `pull_request` to the real target branch (main/dev/etc.)** —
the common case. No separate validation branch needed: open the PR directly
against the intended target and let CI run there.

**B. Repo has a dedicated validation/staging branch that CI treats specially**
(e.g. a `*-build-verification` branch, a required-checks branch distinct from
the merge target) — ask the user to confirm the branch name once; don't guess
or hardcode a specific one. Record it in the tracking file header for the
remainder of the run.

If genuinely unsure which case applies, ask rather than assume — pushing to
the wrong branch or opening a throwaway PR against the wrong base creates
noise on a shared system.

## Step 2: Push and Open the Validation PR

```bash
git push origin HEAD
gh pr create --base <detected-target> --head <branch-name> \
  --title "Dependency updates validation" \
  --body "Automated dependency update bundle for CI validation"
```

If Step 1 found case A, `<detected-target>` is the real merge target and this
PR **is** the real PR — no closing/discarding step follows. If case B, this PR
is throwaway-by-design (see Step 4).

## Step 3: Monitor CI

```bash
gh pr checks <pr-number> --watch
```

Report which jobs are running/required and their status. Do not attempt to
auto-fix CI failures — report failures with links to logs and let the user
decide whether to roll back specific merges or fix forward.

## Step 4: Resolve Based on Case

**Case A (CI ran on the real target PR)**: If CI passes, the PR is ready to
merge as the actual dependency update PR — report it as such. No extra PR to
close.

**Case B (dedicated validation branch)**: If CI passes, close the validation
PR (don't merge it) and open a second PR from the same branch to the real
target. This mirrors the original two-PR flow but only when the repo actually
requires it.

## Reporting

Always state explicitly in the summary which case applied and why, so the
user isn't left guessing whether an open PR is the real one or a disposable
validation artifact.
