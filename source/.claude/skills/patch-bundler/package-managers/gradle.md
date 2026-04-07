# Gradle Package Manager Commands (Android)

## Platform Context
- **Files Modified**: `android/build.gradle`, `android/app/build.gradle`
- **Working Directory**: Project root (gradle commands run from `android/` subdirectory)
- **Dependency Resolution**: On-the-fly (no lock file)

## Lock File
- **Name**: None (Gradle resolves dependencies dynamically)
- **Auto-resolve command**: N/A

## Manifest Files
- **Primary**: `android/build.gradle` (project-level, buildscript dependencies)
- **Secondary**: `android/app/build.gradle` (app-level dependencies)
- **Conflict resolution**: ESCALATE by default, only auto-resolve if:
  - Conflict is ONLY a single version number difference
  - Version change is minor/patch (not major)
  - No other changes in the conflicted section

**ESCALATE immediately for**:
  - Major version updates (X.0.0 → Y.0.0)
  - Multiple dependencies conflicted
  - Plugin versions in buildscript.dependencies
  - Kotlin version changes
  - Any structural changes beyond version numbers

## Install Command
```bash
cd android && ./gradlew --refresh-dependencies && cd ..
```

**Note**: This refreshes the dependency cache but doesn't build anything.

## Validation Strategy

### Local Validation (Minimal)
For gradle branches, run minimal validation during merge:

```bash
yarn install --frozen-lockfile
```

This ensures the React Native JavaScript layer still works with gradle changes. **Do NOT run gradle builds locally** - they're expensive and should happen in CI.

### CI Validation (Required)
After all branches are merged, create a PR targeting `codeql-build-verification` for full CI validation:

```bash
# Push your branch
git push origin <branch-name>

# Create validation PR
gh pr create --base codeql-build-verification --head <branch-name> \
  --title "Security updates validation" \
  --body "Automated security updates bundle for CI validation"
```

The CI workflow will run on the PR:
- `yarn install --frozen-lockfile`
- `cd android && ./gradlew assembleDevDebug --no-daemon --stacktrace`

This is the authoritative validation - if CI passes, the gradle changes are safe.

## Common Gradle Conflict Scenarios

### Buildscript Dependency Conflicts
**Location**: `android/build.gradle` in `buildscript.dependencies` block
**Example**:
```groovy
classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.2")  // Current
classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.6")  // Incoming
```

**Strategy**:
- If same major version (3.x → 3.y): Accept higher version, mark COMPLETED
- If different major version (2.x → 3.x): ESCALATE (likely breaking changes)

### Plugin Version Conflicts
**Location**: `ext { kotlinVersion = "..." }` in `android/build.gradle`
**Example**:
```groovy
kotlinVersion = "2.0.21"  // Current
kotlinVersion = "2.3.0"   // Incoming
```

**Strategy**:
- ESCALATE all Kotlin version conflicts (high risk of compilation issues)
- Kotlin version must match React Native compatibility

### App Dependency Conflicts
**Location**: `android/app/build.gradle` in `dependencies` block
**Strategy**:
- Review carefully - these affect the app directly
- If minor/patch update: Accept higher version
- If major update: ESCALATE

## Edge Cases

### Multiple Gradle Files Modified
If dependabot modifies both `android/build.gradle` AND `android/app/build.gradle`:
- Merge each file separately
- If conflicts in both: ESCALATE (complex dependency change)

### Gradle Wrapper Updates
If dependabot updates `android/gradle/wrapper/gradle-wrapper.properties`:
- Accept theirs (wrapper version updates are usually safe)
- Ensure `./gradlew --version` works after merge

### React Native Version Compatibility
Some gradle dependencies have React Native version requirements:
- If gradle change requires RN upgrade: ESCALATE
- Check package.json to verify RN version compatibility

## Escalation Triggers
- Conflicts in buildscript dependencies
- Kotlin version changes
- Major version updates (X.0.0 → Y.0.0)
- Multiple gradle files with conflicts
- Any build.gradle conflicts in source code (not just version numbers)

## Success Criteria (Local)
✅ `yarn install --frozen-lockfile` exits with code 0
✅ No merge conflicts remain
✅ Gradle files are syntactically valid (no merge markers)

## Success Criteria (CI - Required)
✅ CI workflow `codeql.yml` passes on `codeql-build-verification` branch
✅ `analyze-kotlin` job succeeds
✅ `./gradlew assembleDevDebug` builds successfully

## Important Notes
- **Never run gradle builds locally during merge** - too expensive and time-consuming
- **Always push to codeql-build-verification for validation** - this is the source of truth
- **CI failure = immediate escalation** - don't attempt local fixes without understanding root cause
- **Gradle changes are high-risk** - err on side of escalation for complex conflicts
