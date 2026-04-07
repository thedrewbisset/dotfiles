# Patch Bundler Skill - Multi-Platform

Bundles multiple dependabot security update branches into a single consolidated branch using git merge --no-ff, creating explicit merge commits that show what was integrated and enabling GitHub to auto-close dependabot PRs.

**Supports Multiple Package Managers**:
- ✅ JavaScript/TypeScript (Yarn)
- ✅ Android (Gradle)
- ✅ iOS (CocoaPods)
- ✅ GitHub Actions
- ✅ Python (Poetry)

Perfect for **React Native projects** where dependencies span JavaScript, Android native, and iOS native layers.

## Purpose

When managing security updates across many dependencies and platforms, this skill:
- Consolidates multiple dependabot PRs into a single branch using merge --no-ff
- Creates explicit merge commits for clear audit trail
- Preserves commit SHAs so GitHub auto-closes dependabot PRs on merge
- Makes it easy to see all bundled updates in git log
- Automatically detects platform from branch names
- Validates dependency resolution locally (minimal, fast)
- Pushes to CI for comprehensive validation (builds, tests)
- Tracks progress and escalates complex cases
- Enables incremental work without blocking on hard cases

## Why Merge --no-ff?

The merge --no-ff approach offers the best visibility:
- **GitHub Integration**: Preserves commit SHAs → auto-closes dependabot PRs
- **Clear Audit Trail**: Merge commits explicitly show what was bundled
- **Easy Review**: `git log --oneline --graph` clearly shows all security updates
- **Verbose but Informative**: Each branch integration is a distinct, visible event

Alternatives:
- **Rebase**: Linear history but security commits buried chronologically, hard to see what was bundled
- **Cherry-pick**: Groups all security commits at top, but requires manual PR closing

## Quick Start

1. **Prepare target branch**: Checkout your consolidated security updates branch
   ```bash
   git checkout -b chore/security-updates
   ```

2. **Create tracking file**: List dependabot branches to process (supports multiple platforms)
   ```bash
   # Example: dependabot-branches.md
   - dependabot/npm_and_yarn/typescript-5.0.0: PENDING
   - dependabot/gradle/android/com.google.firebase-firebase-crashlytics-gradle-3.0.6: PENDING
   - dependabot/cocoapods/Firebase-10.5.0: PENDING
   - dependabot/github_actions/actions/checkout-5: PENDING
   ```

3. **Run the skill**:
   ```bash
   /patch-bundler dependabot-branches.md
   ```

4. **Review results**: Check tracking file for status

5. **CI Validation**: After merges, push branch and create PR targeting `codeql-build-verification`:
   ```bash
   git push origin <your-branch>
   gh pr create --base codeql-build-verification --head <your-branch>
   ```

6. **After CI passes**: Close validation PR, then create PR to main for actual merge

## Tracking File Format

The tracking file uses markdown with status annotations:

```markdown
# Dependabot Branches to Merge

- dependabot/npm_and_yarn/package-a-1.2.3: COMPLETED
- dependabot/gradle/android/com.google.firebase-firebase-crashlytics-gradle-3.0.6: COMPLETED
- dependabot/cocoapods/Firebase-10.5.0: ESCALATED
  - Exception Files: ios/Podfile
  - Log Output:
    ```
    [!] CocoaPods could not find compatible versions for pod "Firebase/Core"
    ```
- dependabot/github_actions/actions/checkout-5: COMPLETED
```

## Workflow Overview

For each branch:
1. **Detect platform** from branch name (yarn/gradle/cocoapods/github-actions)
2. **Save current commit SHA** (rollback point)
3. **Merge remote branch** with `git merge --no-ff origin/<branch-name>`
4. **Handle conflicts** if they occur:
   - **Lock files**: Auto-accept theirs, reinstall
   - **Manifest files**: ONLY auto-resolve trivial single-version conflicts. When in doubt, ESCALATE.
   - **Source code**: Always ESCALATE
5. **Run minimal validation** (platform-specific):
   - **Yarn**: `yarn install --frozen-lockfile`
   - **Gradle**: `yarn install --frozen-lockfile` (verify JS layer still works)
   - **CocoaPods**: `yarn install --frozen-lockfile && cd ios && pod install`
   - **GitHub Actions**: No validation needed
6. **On success**: Mark COMPLETED in tracking file **locally** (merge commit already created by git)
7. **On failure**: Rollback to saved SHA and mark ESCALATED
8. Continue to next branch

**IMPORTANT**: The tracking file is NEVER committed. Only merge commits are created.

After ALL branches processed:
9. **Push branch**: `git push origin <branch-name>`
10. **Create validation PR**: Create PR targeting `codeql-build-verification` as base branch
11. **Monitor CI validation**: CI runs on the PR (yarn test, gradle build, xcodebuild)
12. **Close validation PR**: After CI passes, close the PR (don't merge)
13. **Report summary**: COMPLETED branches, ESCALATED branches, CI instructions

## Merge Commit Output

After bundling, `git log --oneline --graph` will show:

```
* Merge dependabot/npm_and_yarn/eslint-8.40.0
|\
| * build(deps-dev): bump eslint from 8.39.0 to 8.40.0
|/
* Merge dependabot/npm_and_yarn/react-18.2.0
|\
| * build(deps): bump react from 18.1.0 to 18.2.0
|/
* Previous commits...
```

This makes it immediately clear what security updates were bundled!

## Conflict Resolution Strategy

### Automatic Resolution (Platform-Specific)

**Yarn**:
- `yarn.lock`: Accept theirs, run `yarn install --frozen-lockfile`
- `package.json` version conflicts: Favor higher version

**Gradle**:
- No lock file (Gradle resolves dynamically)
- `build.gradle` version conflicts: Accept higher version for minor/patch, escalate for major

**CocoaPods**:
- `Podfile.lock`: Accept theirs, run `pod install`
- `Podfile` version conflicts: Favor higher version for same major version

**GitHub Actions**:
- Workflow files: Accept theirs (action version updates)

### Smart Resolution (Limited Attempts)
- For manifest conflicts: Try higher version first
- For lock file conflicts: Always accept theirs and regenerate
- Max 2-3 attempts before escalation

### Escalation Triggers
- Source code conflicts (any platform)
- Major version updates (X.0.0 → Y.0.0)
- Kotlin version changes
- Platform version changes (iOS deployment target)
- Complex build.gradle conflicts
- Local validation failures after 2 retries
- CI validation failures

## Package Manager Support

**Currently Supported** (auto-detected from branch names):
- ✅ **Yarn** (`dependabot/npm_and_yarn/*`)
- ✅ **Gradle** (`dependabot/gradle/*`)
- ✅ **CocoaPods** (`dependabot/cocoapods/*`)
- ✅ **GitHub Actions** (`dependabot/github_actions/*`)
- ✅ **Poetry** (`dependabot/pip/*`)

**Detection**: See [platform-detector.md](platform-detector.md)

**Configuration Files**:
```
package-managers/
├── yarn.md           # JavaScript/TypeScript via Yarn
├── gradle.md         # Android dependencies via Gradle
├── cocoapods.md      # iOS dependencies via CocoaPods
├── github-actions.md # GitHub Actions workflow dependencies
└── poetry.md         # Python dependencies via Poetry
```

## Adding New Package Managers

To add support for a new package manager:

1. **Create config file**: `package-managers/<manager>.md`
2. **Define**:
   - Lock file name and auto-resolve strategy
   - Manifest file name and conflict resolution rules
   - Install command
   - Validation strategy (local minimal + CI comprehensive)
   - Success criteria
   - Escalation triggers
3. **Update platform-detector.md**: Add branch naming pattern
4. **Test**: Run with branches from that package manager

## Safety Features

- **Rollback on failure**: Uses `git reset --hard` to saved commit SHA
- **Incremental progress**: Updates tracking file after each branch
- **Non-blocking**: Escalations don't block other branches
- **Retry limits**: Max 2-3 attempts before giving up
- **Minimal local validation**: Fast dependency checks, no expensive builds
- **Comprehensive CI validation**: Full builds and tests in CI after all merges
- **Merge commit visibility**: Easy to see all bundled updates in git log
- **Platform isolation**: Each branch validated with platform-specific rules
- **CI as source of truth**: Final validation matches production (push to main)

## Best Practices

1. **Start small**: Test with 2-3 branches first
2. **Clean state**: Ensure `git status` is clean before starting
3. **Tracking file**: Keep `dependabot-branches.md` untracked (add to .gitignore if desired)
4. **Review escalations**: Manually review all ESCALATED branches
5. **Review merge commits**: Run `git log --oneline --graph` to see what was bundled
6. **Resume capability**: Re-run skill to continue if interrupted (skips COMPLETED)
7. **Use origin prefix**: Always merge with `origin/<branch-name>` to use remote branches
8. **Conservative approach**: The skill escalates by default - only trivial conflicts are auto-resolved

## Troubleshooting

### "Repository is not clean"
- Commit or stash changes before running skill
- Check `git status`

### "Branch not found"
- Run `git fetch origin` to update remote branches
- Verify branch names in tracking file
- Ensure you use the correct branch name (without `origin/` prefix in tracking file)

### Too many escalations
- Consider breaking into smaller batches
- Review first escalation to identify patterns
- May need manual resolution for complex updates

### Build failures persist
- Check if base branch builds cleanly
- Verify dependencies are compatible
- May need to update build configuration

### Want to see what was bundled?
- Run `git log --oneline --graph` to see merge commits
- Each merge commit shows exactly which dependabot branch was integrated

## Files

```
~/.claude/skills/patch-bundler/
├── SKILL.md                       # Main skill entry point
├── README.md                      # This file
├── base-merge-logic.md            # Core workflow (package-agnostic)
├── platform-detector.md           # Platform detection from branch names
├── dependabot-branches.example.md # Example tracking file format
└── package-managers/
    ├── yarn.md                    # JavaScript/TypeScript (Yarn)
    ├── gradle.md                  # Android (Gradle)
    ├── cocoapods.md               # iOS (CocoaPods)
    ├── github-actions.md          # GitHub Actions
    └── poetry.md                  # Python (Poetry)
```

## Version Control

This skill is designed for personal use across repositories:
- Lives in `~/.claude/skills/` (not in project `.git`)
- Available across all your projects
- Can be synced via dotfiles repo

To share with a team:
- Create a Claude Code plugin
- Or symlink into project `.claude/skills/` and commit

## Future Enhancements

- [x] ~~Multi-platform support~~ (✅ Implemented: Yarn, Gradle, CocoaPods, GitHub Actions, Poetry)
- [x] ~~CI validation integration~~ (✅ Implemented: pushes to codeql-build-verification)
- [ ] Support for monorepos with multiple package.json files
- [ ] Parallel processing of independent branches (same platform)
- [ ] Interactive mode for escalation decisions
- [ ] Metrics tracking (success rate, common failure patterns per platform)
- [ ] Support for Swift Package Manager (iOS)
- [ ] Support for NPM (as alternative to Yarn)
- [x] ~~GitHub API integration to close dependabot PRs~~ (merge preserves SHAs, auto-closes)
