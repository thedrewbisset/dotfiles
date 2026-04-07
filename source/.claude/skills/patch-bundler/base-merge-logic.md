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
3. **Load tracking file**: Read the dependabot branches manifest file
4. **Validate tracking format**: Ensure file format is correct markdown

**IMPORTANT**: The tracking file is for local progress tracking only. NEVER commit the tracking file - it should remain untracked or be added to .gitignore. The ONLY commits this skill creates are the merge commits from `git merge --no-ff`.

## Per-Branch Merge Loop - Rebase Before Merge Strategy

For each branch listed in the tracking file that is not already marked COMPLETED:

**Core Principle**: Rebase each dependabot branch onto the accumulating security updates branch BEFORE merging. This ensures lock files are up-to-date and merges are clean.

### Phase 1: Create Rebased Branch
1. **Save rollback point**: `ROLLBACK_SHA=$(git rev-parse HEAD)`
2. **Create local rebased branch**:
   ```bash
   TEMP_BRANCH="temp/$(basename origin/<branch-name>)-rebased"
   git checkout -b $TEMP_BRANCH origin/<branch-name>
   ```
3. **Rebase onto accumulating branch**:
   ```bash
   git rebase <security-updates-branch>
   ```
   This brings the dependabot branch up-to-date with all previous merges.

### Phase 2: Resolve Rebase Conflicts
If rebase reports conflicts, resolve them according to file type:

#### Lock File Conflicts (auto-resolve with regeneration)
- **Detection**: Conflicts in `yarn.lock`, `poetry.lock`, `package-lock.json`, `Podfile.lock`, etc.
- **Resolution Strategy**:
  1. Accept theirs: `git checkout --theirs <lock-file>`
  2. Stage: `git add <lock-file>`
  3. **CRITICAL**: Regenerate lock file using package manager command:
     - **Poetry**: `cd <lambda-dir> && poetry lock && cd -`
     - **Yarn**: `yarn install`
     - **CocoaPods**: `cd ios && pod install && cd ..`
  4. Stage regenerated lock file: `git add <lock-file>`
  5. Continue rebase: `git rebase --continue`

**Why regenerate during rebase?**
- Dependabot branch started from old commit with outdated constraints
- Our accumulating branch has newer `pyproject.toml`/`package.json` from previous merges
- Regenerating ensures lock file matches current manifest state
- When rebase completes, lock file is already consistent - no merge conflicts!

#### Manifest Conflicts (escalate - too risky)
- **Detection**: Conflicts in `package.json`, `pyproject.toml`, `build.gradle`, `Podfile`, etc.
- **Action**:
  1. Abort rebase: `git rebase --abort`
  2. Delete temp branch: `git branch -D $TEMP_BRANCH`
  3. Mark as ESCALATED with reason: "Manifest file conflicts require manual review"
  4. Continue to next branch

**Why escalate manifest conflicts?**
- Manifest conflicts mean competing version constraints
- Could indicate incompatible dependency updates
- Better to handle manually than risk breaking builds
- Lock file conflicts are expected; manifest conflicts are not

#### Source Code Conflicts (escalate)
- **Detection**: Conflicts in source files (`.ts`, `.tsx`, `.py`, `.rs`, etc.)
- **Action**: Same as manifest conflicts - abort, delete temp branch, escalate

### Phase 3: Merge Rebased Branch (Clean!)
After rebase succeeds:

1. **Switch back to security updates branch**:
   ```bash
   git checkout <security-updates-branch>
   ```

2. **Merge the rebased branch with --no-ff**:
   ```bash
   git merge --no-ff $TEMP_BRANCH -m "Merge dependabot/<original-branch-name>"
   ```
   - This merge will be **CLEAN** (no conflicts!) because rebase already resolved them
   - The `--no-ff` creates an explicit merge commit for audit trail
   - Commit SHAs from dependabot branch are preserved (GitHub auto-closes PRs)

3. **Delete temporary branch**:
   ```bash
   git branch -D $TEMP_BRANCH
   ```

### Phase 4: Validation (Optional - Minimal)
After merge completes, optionally run quick validation:

- **Poetry**: `cd <lambda-dir> && poetry install` (verify dependencies resolve)
- **Yarn**: `yarn install --frozen-lockfile`
- **GitHub Actions**: No validation needed

**Note**: Full validation happens in CI. Local validation is optional and minimal.

### Phase 5: Finalization
1. **Update tracking file**: Mark branch as COMPLETED
2. **Verify clean state**: `git status` should show no uncommitted changes (tracking file is untracked)
3. **Log progress**: Output which branch was processed

### Error Recovery

**If rebase fails after 3 attempts**:
1. Abort rebase: `git rebase --abort`
2. Delete temp branch: `git branch -D $TEMP_BRANCH`
3. Rollback security updates branch: `git reset --hard $ROLLBACK_SHA`
4. Mark branch as ESCALATED with error details
5. Continue to next branch

**If merge fails (shouldn't happen if rebase succeeded)**:
1. Abort merge: `git merge --abort`
2. Delete temp branch: `git branch -D $TEMP_BRANCH`
3. Rollback: `git reset --hard $ROLLBACK_SHA`
4. Mark as ESCALATED
5. Continue to next branch

## Why This Approach Works

**Key Benefits:**
- ✅ **Clean merges**: No conflicts during merge because rebase already resolved them
- ✅ **Stable commits**: Each merge commit has consistent lock files
- ✅ **Easy to rebase later**: No "magic" conflict resolution that can't be replayed
- ✅ **Preserves SHAs**: GitHub auto-closes dependabot PRs
- ✅ **Atomic updates**: Each dependency update is a clean, reviewable merge commit

**How it solves the lock file problem:**
- Dependabot branches are stale (based on old main)
- Rebasing updates them to know about previous merges
- Lock file regeneration happens during rebase (one-time)
- Merge is then trivial (fast-forward with --no-ff)
- Result: Clean commit history that's easy to work with

---

## Post-Merge CI Validation

After ALL branches have been processed (merged or escalated), push the consolidated branch to CI for full validation:

### Phase 5: CI Validation (After All Merges)

**Purpose**: Run comprehensive builds and tests in CI to validate all merged changes together.

**Steps**:

1. **Verify clean state**:
   ```bash
   git status
   ```
   Ensure no uncommitted changes remain (tracking file should be untracked, but nothing else should be modified).

   **If tracking file shows as modified**: This is expected - it's being updated locally but NOT committed.
   **If anything else is modified**: ERROR - something went wrong, do not push to CI.

2. **Push consolidated branch to origin**:
   ```bash
   git push origin HEAD
   ```

   Or if the branch already exists remotely:
   ```bash
   git push --force-with-lease origin HEAD
   ```

3. **Create PR targeting codeql-build-verification**:

   **Using GitHub CLI** (recommended):
   ```bash
   gh pr create --base codeql-build-verification --head <current-branch-name> --title "Security updates validation" --body "Automated security updates bundle for CI validation"
   ```

   **Or manually**:
   - Navigate to GitHub repository
   - Create PR with:
     - **Base branch**: `codeql-build-verification`
     - **Head branch**: Your consolidated branch (e.g., `fix/security-updates-20260401`)

   This triggers the `codeql.yml` workflow which runs:
   - `analyze-javascript`: `yarn install` + `yarn test`
   - `analyze-kotlin`: `yarn install` + `cd android && ./gradlew assembleDevDebug`
   - `analyze-swift`: `yarn install` + `cd ios && pod install` + xcodebuild

4. **Monitor CI results**:
   - Report the PR URL and GitHub Actions URL to the user
   - User should monitor the PR checks
   - Report which jobs need to pass

5. **If CI passes**:
   - All merges validated successfully
   - Close the validation PR (don't merge it)
   - Branch is ready to merge to main
   - Report success summary to user

6. **If CI fails**:
   - Identify which job(s) failed:
     - `analyze-javascript`: Yarn/JS/TS issue
     - `analyze-kotlin`: Android/Gradle issue
     - `analyze-swift`: iOS/CocoaPods issue
   - Review failed job logs for specific errors
   - Escalate branches that likely caused the failure
   - User may need to:
     - Cherry-pick successful merges to a new branch
     - Manually fix failing branches
     - Re-run patch-bundler with subset of branches

**Why CI Validation?**
- ✅ Matches production validation (same workflow that runs on push to main)
- ✅ Runs expensive builds (xcodebuild, gradle) without local overhead
- ✅ Tests all platforms together (catches cross-platform issues)
- ✅ Authoritative source of truth - if CI passes, changes are safe
- ✅ Creates audit trail in GitHub Actions
- ✅ Isolated validation branch prevents polluting main branch with failed builds

**Important Notes**:
- The PR to `codeql-build-verification` is ONLY for validation - do NOT merge it
- After CI passes, close the validation PR
- Then create a new PR from your consolidated branch to `main` for actual merge
- The validation PR can be deleted after use

**CI Failure Strategy**:
- Do NOT attempt to auto-fix CI failures
- Report failures clearly to user with links to logs
- Recommend manual review of specific failed jobs
- User should decide: rollback specific merges or fix issues

---

## Error Handling

### Rollback Scenarios
- Build failures after all merges complete
- Unrecoverable conflicts after 3 attempts
- Unexpected git errors during merge

**Rollback command**: `git reset --hard $ROLLBACK_SHA`

### Abort Scenarios
- User interruption
- Critical git repository corruption
- Tracking file becomes invalid

**Abort command**: `git merge --abort` (if mid-merge), then report partial progress

## Escalation Format

When marking a branch as ESCALATED, include:

\`\`\`markdown
- <branch-name>: ESCALATED
  - Exception Files: <comma-separated list of conflict files or files mentioned in build errors>
  - Log Output:
    \`\`\`
    <relevant error messages from git or build output>
    \`\`\`
\`\`\`

## Final Summary Report

After processing all branches, generate a summary with CI validation instructions:

\`\`\`markdown
## Patch Bundler Summary

**Total Branches**: X
**Completed**: Y
**Escalated**: Z

### Merge Results
All branches COMPLETED successfully with clear merge commits, or:

### Escalated Branches (require manual review)
<list of all escalated branches with their exception details>

### CI Validation Instructions

**Step 1**: Push your consolidated branch:
\`\`\`bash
git push origin <your-branch-name>
\`\`\`

**Step 2**: Create PR targeting `codeql-build-verification` for validation:
\`\`\`bash
gh pr create --base codeql-build-verification --head <your-branch-name> --title "Security updates validation" --body "Automated security updates bundle for CI validation"
\`\`\`

Or create manually in GitHub:
- Base: `codeql-build-verification`
- Head: `<your-branch-name>`

**Step 3**: Monitor CI validation (3 jobs must pass):
- ✅ analyze-javascript: yarn test
- ✅ analyze-kotlin: gradle assembleDevDebug
- ✅ analyze-swift: xcodebuild

### Next Steps

**If CI passes**:
- ✅ All changes validated successfully
- Close the validation PR (do NOT merge it)
- Review merge commits: `git log --oneline --graph`
- Create PR from your branch to `main` for actual merge
- GitHub will auto-close dependabot PRs when merged to main

**If CI fails**:
- ⚠️ Review failed job logs to identify issues
- Consider reverting problematic merges: `git revert <commit-sha>`
- Or manually fix issues and force-push
- Re-run validation PR checks

**If escalations occurred**:
- Review escalated branches manually
- Determine if they can be resolved or need further investigation
- Consider processing them separately after main bundle is merged
\`\`\`

## Attempt Counter Logic

Each branch maintains a retry counter for conflict/build resolution:
- **Counter scope**: Per-phase (separate for conflict resolution vs build validation)
- **Max attempts**: 3
- **Reset**: Counter resets when moving to a new branch
- **Escalation trigger**: Counter reaches 3 without success

## State Preservation

To enable resume capability, the tracking file is the source of truth:
- Update immediately after each branch (success or failure)
- Never batch updates (disk write after each iteration)
- If agent is interrupted, re-running will skip COMPLETED branches

## Merge Commit Visibility

The merge commits created by this workflow will look like:
\`\`\`
* Merge dependabot/npm_and_yarn/prettier-3.6.2
|\
| * build(deps-dev): bump prettier from 3.3.3 to 3.6.2
|/
* Merge dependabot/npm_and_yarn/dayjs-1.11.18
|\
| * build(deps): bump dayjs from 1.11.13 to 1.11.18
|/
* Previous commit
\`\`\`

This makes it very clear in `git log` what was bundled and when.

**No extra commits should appear between merge commits** - conflict resolutions are part of the merge commit itself.
