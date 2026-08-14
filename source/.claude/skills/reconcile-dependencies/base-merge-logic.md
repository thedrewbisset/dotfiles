# Base Merge Logic (Package Manager Agnostic)

This document defines the core workflow for bundling security update branches using git merge --no-ff. Package-manager-specific commands are injected from the relevant variant file.

## Merge Approach Rationale

This workflow uses `git merge --no-ff` because it:
- Preserves commit SHAs → GitHub auto-closes dependabot PRs when merged to main
- Creates explicit merge commits showing what was integrated
- Provides clear audit trail - each security update integration is a visible event
- Makes it easy to see all bundled updates in git log

**Important**: Always merge with `origin/<branch-name>` and use `--no-ff` to force creation of merge commits even for fast-forward merges.

## Prerequisites Check

1. **Verify target branch**: Confirm current branch matches expected target (e.g., `chore/security-updates`)
2. **Verify clean state**: Ensure `git status` is clean before starting (no uncommitted changes)
3. **Run discovery**: Follow [discovery.md](discovery.md) to generate the tracking manifest — do not ask the user to hand-author it
4. **Validate tracking format**: Ensure the generated file format is correct markdown

**IMPORTANT**: The tracking file is for local progress tracking only. NEVER commit it — it should remain untracked or be added to .gitignore. The ONLY commits this skill creates are the merge commits from `git merge --no-ff`.

## Per-Branch Merge Loop - Rebase Before Merge Strategy

For each branch listed in the tracking file that is not already marked COMPLETED:

**Core Principle**: Rebase each dependabot branch onto the accumulating branch BEFORE merging. This ensures lock files are up-to-date and merges are clean.

### Phase 1: Create Rebased Branch
1. **Save rollback point**: `ROLLBACK_SHA=$(git rev-parse HEAD)`
2. **Create local rebased branch**:
   ```bash
   TEMP_BRANCH="temp/$(basename origin/<branch-name>)-rebased"
   git checkout -b $TEMP_BRANCH origin/<branch-name>
   ```
3. **Rebase onto accumulating branch**:
   ```bash
   git rebase <target-branch>
   ```
   This brings the dependabot branch up-to-date with all previous merges.

### Phase 2: Resolve Rebase Conflicts
If rebase reports conflicts, resolve them according to file type:

#### Lock File Conflicts (auto-resolve with regeneration)
- **Detection**: Conflicts in `yarn.lock`, `poetry.lock`, `package-lock.json`, `Podfile.lock`, etc.
- **Resolution Strategy**:
  1. **Accept OURS, not theirs**: `git checkout --ours <lock-file>`
  2. Stage: `git add <lock-file>`
  3. **CRITICAL**: Regenerate lock file using the package manager command from `package-managers/<platform>.md`
  4. Stage regenerated lock file: `git add <lock-file>`
  5. **Verify no other package regressed** — see "Mandatory Post-Regeneration Verification" below. Do not skip this step even when the regeneration command exits 0.
  6. Continue rebase: `git rebase --continue`

**Why `--ours`, not `--theirs`:**
- During a rebase, `--theirs` refers to the commit being replayed (the stale
  dependabot branch's own lock file, frozen at whatever old commit it forked
  from) — `--ours` refers to the branch being rebased onto (the accumulating
  target branch, which already has every prior merge's fixes applied).
- **`--theirs` is backwards here and will silently reintroduce old versions.**
  A prior real incident: rebasing a `python-dotenv` bump used `--theirs`,
  which pulled in the dependabot branch's stale lock; the subsequent
  `poetry lock` call then partially preserved that staleness because of a
  local package-manager cache that hadn't refreshed since an earlier run —
  it kept `aiohttp` pinned to a version already fixed three commits earlier
  (`3.14.1` → `3.13.5`, reopening three CVEs with open Dependabot alerts) and
  silently touched previously-merged versions of `redis`, `cryptography`,
  and `python-multipart` too. Each of the prior three merges had genuinely
  fixed its target package, but by the fourth merge every one of those fixes
  had been silently clobbered — because every rebase in the chain used
  `--theirs` and each one dragged the lock backward toward its own stale
  starting point.
- Starting from `--ours` means the regeneration only has to account for the
  one manifest change this branch introduces, on top of an already-correct
  base — not reconcile an entire stale snapshot against the current state.

**Why regenerate at all, then?**
- The manifest (`pyproject.toml`/`package.json`) merge itself may still need
  the lock file's hash/content updated even when `--ours` is correct,
  because the incoming branch's manifest edit (e.g. a version constraint
  bump) still needs to be resolved into the lock.
- Regenerating ensures the lock file matches the current (merged) manifest
  state without regressing anything the base branch already fixed.

### Mandatory Post-Regeneration Verification

After every lock file regeneration during a rebase — not just on conflict,
every time the lock file changes — diff the regenerated lock against the
**pre-rebase HEAD of the accumulating branch** (not against the dependabot
branch), and check specifically for downgrades:

```bash
# Compare the package this branch is bumping, plus any package touched by
# a PRIOR merge in this run, against the accumulating branch's last commit
git diff <accumulating-branch-pre-rebase-sha> -- <lock-file> | \
  grep -E '^[+-]version = ' 
```

For every package whose version changed, confirm the new version is `>=`
the version on the accumulating branch, not just compatible with the
manifest constraint. A regeneration that satisfies the manifest but
downgrades a package fixed by an earlier merge in the same run is exactly
the failure mode above — it will not raise an error, `poetry check --lock`
will pass, and the merge will look clean. This check is the only thing that
catches it.

**If a downgrade is detected**: do not continue the rebase. Treat it the
same as an unresolvable lock conflict — abort, escalate, and note which
package regressed and from which prior merge. Do not attempt to hand-fix the
lock file inline; a local package-manager cache may be stale (see the
incident above) and needs to be cleared before re-attempting, not patched
around.

#### Manifest Conflicts (escalate — too risky by default)
- **Detection**: Conflicts in `package.json`, `pyproject.toml`, `build.gradle`, `Podfile`, etc.
- **Action**:
  1. Abort rebase: `git rebase --abort`
  2. Delete temp branch: `git branch -D $TEMP_BRANCH`
  3. Mark as ESCALATED with reason: "Manifest file conflicts require manual review"
  4. Continue to next branch

Package-manager files in `package-managers/` define narrow exceptions (e.g. a
single trivial minor-version bump) where auto-resolution is acceptable — treat
those as the exception, not the default.

#### Source Code Conflicts (always escalate)
- **Detection**: Conflicts in source files (`.ts`, `.tsx`, `.py`, `.rs`, etc.)
- **Action**: Same as manifest conflicts — abort, delete temp branch, escalate

### Phase 3: Merge Rebased Branch (Clean!)
After rebase succeeds:

1. **Switch back to the target branch**:
   ```bash
   git checkout <target-branch>
   ```
2. **Merge the rebased branch with --no-ff**:
   ```bash
   git merge --no-ff $TEMP_BRANCH -m "Merge dependabot/<original-branch-name>"
   ```
3. **Delete temporary branch**:
   ```bash
   git branch -D $TEMP_BRANCH
   ```

### Phase 4: Local Validation (Optional — Minimal)
Run the platform's minimal local validation command from `package-managers/<platform>.md`. Full validation happens in CI (see below) — local validation here is a fast sanity check, not the source of truth.

### Phase 5: Finalization
1. **Update tracking file**: Mark branch as COMPLETED (include risk tier from discovery Step 3 — e.g. `COMPLETED (major)` — so the final summary can call out majors without re-deriving them)
2. **Verify clean state**: `git status` should show no uncommitted changes besides the untracked tracking file
3. **Log progress**: Output which branch was processed

### Error Recovery

**If rebase fails after 3 attempts**:
1. Abort rebase: `git rebase --abort`
2. Delete temp branch: `git branch -D $TEMP_BRANCH`
3. Rollback: `git reset --hard $ROLLBACK_SHA`
4. Mark branch as ESCALATED with error details
5. Continue to next branch

**If merge fails (shouldn't happen if rebase succeeded)**:
1. Abort merge: `git merge --abort`
2. Delete temp branch: `git branch -D $TEMP_BRANCH`
3. Rollback: `git reset --hard $ROLLBACK_SHA`
4. Mark as ESCALATED
5. Continue to next branch

## Why This Approach Works

- **Clean merges**: No conflicts during merge because rebase already resolved them
- **Stable commits**: Each merge commit has consistent lock files
- **Easy to rebase later**: No "magic" conflict resolution that can't be replayed
- **Preserves SHAs**: GitHub auto-closes dependabot PRs
- **Atomic updates**: Each dependency update is a clean, reviewable merge commit
