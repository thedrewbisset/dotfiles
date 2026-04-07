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
2. **Verify clean state**: Ensure `git status` is clean before starting
3. **Load tracking file**: Read the dependabot branches manifest file
4. **Validate tracking format**: Ensure file format is correct markdown

## Per-Branch Merge Loop

For each branch listed in the tracking file that is not already marked COMPLETED:

### Phase 1: Setup
1. **Save rollback point**: `ROLLBACK_SHA=$(git rev-parse HEAD)`
2. **Start merge**: `git merge --no-ff origin/<branch-name> -m "Merge dependabot/<branch-name>"`
   - The `--no-ff` flag forces creation of a merge commit even if fast-forward is possible
   - The `origin/` prefix ensures we use the remote branch, not local

### Phase 2: Conflict Resolution
If merge reports conflicts:

#### Lock File Conflicts (auto-resolve)
- **Detection**: Check if only lock files have conflicts (e.g., `yarn.lock`, `package-lock.json`)
- **Resolution**:
  1. Accept theirs: `git checkout --theirs <lock-file>`
  2. Stage the resolution: `git add <lock-file>`
  3. Complete the merge: `git commit --no-edit`
  4. **CRITICAL**: Do NOT run install/build yet - save validation for after all merges complete, OR accept that working directory will be dirty for next merge

**Note**: Running `yarn install` after resolving a yarn.lock conflict may modify yarn.lock again, creating a dirty working directory. It's better to validate builds AFTER all merges are complete.

#### Manifest Conflicts (smart-resolve)
- **Detection**: Conflicts in `package.json`, `requirements.txt`, `Cargo.toml`, etc.
- **Resolution Strategy**:
  1. Read both versions of the conflicted sections
  2. **For version conflicts**: Favor the higher version number
  3. Manually edit the file to resolve conflicts
  4. Stage the resolution: `git add <manifest-file>`
  5. Complete the merge: `git commit --no-edit`
  6. **Validation**: Can optionally install + build to validate, but don't commit those changes

#### Source Code Conflicts (escalate)
- **Detection**: Conflicts in source files (`.ts`, `.tsx`, `.py`, `.rs`, etc.)
- **Action**: Immediately `git merge --abort`, mark ESCALATED (too risky to auto-resolve)

### Phase 3: Validation (Post-Merge)
After merge completes (merge commit created), validate immediately:

1. **Install dependencies**: Run package manager install command
   - Yarn: `yarn install`
   - Poetry: `poetry install` or `./poetry install`

2. **Run tests**: Execute test command specific to package manager
   - Yarn: `yarn test`
   - Poetry: `make tests` (if Makefile exists), else `poetry run pytest`

3. **If tests pass**:
   - Mark COMPLETED in tracking file
   - Continue to next merge

4. **If tests fail**:
   - Capture error output
   - Rollback: `git reset --hard $ROLLBACK_SHA`
   - Mark ESCALATED with test failure details
   - Continue to next merge

**Why validate after each merge?**
- Identifies which specific merge caused test failures
- Allows rollback of problematic merge while keeping successful ones
- Provides immediate feedback on compatibility issues
- Prevents cascading failures from accumulating

### Phase 4: Finalization
1. **Update tracking file**: Write status (COMPLETED or ESCALATED) with details
2. **Clean up state**: Ensure repository is in a committable state before next iteration
3. **Log progress**: Output which branch was processed and outcome

## Final Build Validation

After ALL branches are merged:
1. Run `yarn install` to ensure all dependencies are properly installed
2. Run `yarn build` to validate the final state
3. If build fails, identify which merge caused the issue and mark it ESCALATED

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

After processing all branches, generate a summary:

\`\`\`markdown
## Patch Bundler Summary

**Total Branches**: X
**Completed**: Y
**Escalated**: Z

### Results
All branches COMPLETED successfully with clear merge commits, or:

### Escalated Branches (require manual review)
<list of all escalated branches with their exception details>

### Next Steps
- Review consolidated changes and merge commits in git log
- Push to remote when ready
- Create PR to merge into main (GitHub will auto-close dependabot PRs)
- Merge commits provide clear audit trail of all bundled updates
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
