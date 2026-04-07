---
name: patch-bundler
description: Bundle multiple dependabot branches into a consolidated branch using git merge --no-ff (supports Yarn, Gradle, CocoaPods, GitHub Actions, Poetry)
allowed-tools: Read, Grep, Bash, Edit
disable-model-invocation: true
argument-hint: "[path-to-branches.md]"
---

# Patch Bundler Agent - Multi-Platform

This skill bundles multiple dependabot security update branches into a single consolidated branch using git merge --no-ff, creating clear merge commits that show what was integrated and enabling GitHub to auto-close dependabot PRs.

**Supported Platforms**:
- JavaScript/TypeScript (Yarn)
- Android (Gradle)
- iOS (CocoaPods)
- GitHub Actions
- Python (Poetry)

Perfect for **React Native projects** with dependencies across multiple layers (JS, Android, iOS).

## Task

Bundle dependabot branches listed in: ${1:-dependabot-branches.md}

Target branch: Current checked-out branch (should be `chore/security-updates`, `fix/security-updates-YYYYMMDD`, or similar)

## Workflow: Rebase-Before-Merge Strategy

**Key Innovation**: Uses **rebase-before-merge** to ensure clean, conflict-free merges:

For each dependabot branch:
1. **Create local rebased branch**: `git checkout -b temp/dep-rebased origin/dependabot-branch`
2. **Rebase onto accumulating branch**: `git rebase security-updates`
   - Lock file conflicts resolved during rebase
   - Lock files regenerated to match current manifest state
3. **Merge rebased branch**: `git merge --no-ff temp/dep-rebased` (clean merge!)
4. **Delete temp branch**: `git branch -D temp/dep-rebased`

Then:
5. **Detect platform** using [platform-detector.md](platform-detector.md)
6. **Load package manager config** from `package-managers/<platform>.md`
7. **Follow rebase-merge logic** in [base-merge-logic.md](base-merge-logic.md)
8. **Push to CI** for validation after all merges complete

## Core Principles

1. **Rebase First**: Rebase each dependabot branch onto accumulating branch BEFORE merging
2. **Clean Merges**: Conflicts resolved during rebase, merges are clean (no conflicts!)
3. **Safety First**: Save commit SHA before each operation for rollback capability
4. **Incremental Progress**: Update tracking file locally after each branch (COMPLETED or ESCALATED)
5. **Stable Commits**: Each merge commit is buildable (lock files already regenerated)
6. **Easy to Rebase Later**: Clean history without "magic" conflict resolution
7. **Platform-Aware**: Automatically detects platform from branch name
8. **Conservative**: When in doubt, ESCALATE - only auto-resolve lock file conflicts

## Why Rebase-Before-Merge Works

**The Problem with Direct Merging:**
- Dependabot branches are stale (based on old commits)
- Their lock files don't know about previous dependency updates
- Every merge creates lock file conflicts
- Conflict resolution is manual and doesn't replay during future rebases

**How Rebase-Before-Merge Solves It:**
- ✅ Rebasing updates dependabot branch with all previous merges
- ✅ Lock file regenerated once during rebase
- ✅ Merge is clean (no conflicts!) because files are compatible
- ✅ **Future rebases through this history are also clean!**
- ✅ Preserves commit SHAs → GitHub auto-closes dependabot PRs
- ✅ Clear audit trail with explicit merge commits

## Output Format

Update the tracking file with status and exception details:

```
- dependabot/npm_and_yarn/package-name-1.2.3: COMPLETED
- dependabot/gradle/android/com.google.firebase-firebase-crashlytics-gradle-3.0.6: COMPLETED
- dependabot/cocoapods/Firebase-10.5.0: ESCALATED
  - Exception Files: ios/Podfile
  - Log Output:
    ```
    [!] CocoaPods could not find compatible versions for pod "Firebase/Core"
    ```
- dependabot/github_actions/actions/checkout-5: COMPLETED
```

## Important Notes

- This skill should only be invoked manually with `/patch-bundler [branches-file]`
- The target branch must be checked out before running
- The branches file will be updated in place with progress **but NEVER committed**
- All ESCALATED branches will be summarized at the end for manual review
- Use `origin/<branch-name>` when merging to ensure remote branches are used
- Merge commits will show exactly what security updates were bundled
- **CRITICAL**: Only create merge commits - never commit the tracking file or any other files
- **CRITICAL**: After all merges, push branch and create PR targeting `codeql-build-verification` for CI validation
- The validation PR is ONLY for CI - close it after CI passes, don't merge it
- Local validation is minimal - CI is the authoritative validation
- For React Native projects: handles Yarn, Gradle, and CocoaPods dependencies automatically
- **Conservative approach**: When in doubt about conflict resolution, ESCALATE
