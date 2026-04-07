# CocoaPods Package Manager Commands (iOS)

## Platform Context
- **Files Modified**: `ios/Podfile`, `ios/Podfile.lock`
- **Working Directory**: Project root (pod commands run from `ios/` subdirectory)
- **Dependency Resolution**: Lock file based

## Lock File
- **Name**: `ios/Podfile.lock`
- **Auto-resolve command**: `git checkout --theirs ios/Podfile.lock`

**Strategy**: Always accept theirs for lock file conflicts, then run `pod install` to regenerate if needed.

## Manifest File
- **Name**: `ios/Podfile`
- **Conflict resolution**: ESCALATE by default, only auto-resolve for trivial version bumps

**Conflict Patterns**:
```ruby
# Current
pod 'Firebase/Analytics', '~> 10.0'

# Incoming
pod 'Firebase/Analytics', '~> 10.5'
```

**Strategy**:
- If same major version AND single pod conflict: Accept higher version
- If different major version: ESCALATE (breaking changes likely)
- If multiple pods conflicted: ESCALATE (complex change)
- If anything besides version number differs: ESCALATE

## Install Command
```bash
cd ios && pod install && cd ..
```

**Note**: This resolves dependencies and generates/updates the `.xcworkspace` file.

## Validation Strategy

### Local Validation (Minimal)
For CocoaPods branches, run minimal validation during merge:

```bash
yarn install --frozen-lockfile
cd ios && pod install && cd ..
```

This ensures:
- JavaScript dependencies are consistent
- CocoaPods can resolve dependencies
- Workspace is properly generated

**Do NOT run xcodebuild locally** - it's extremely expensive (can take 10+ minutes) and should happen in CI.

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
- `cd ios && pod install`
- Full xcodebuild with ChartproDev scheme

This is the authoritative validation - if CI passes, the CocoaPods changes are safe.

## Common CocoaPods Conflict Scenarios

### Podfile Version Conflicts
**Example**:
```ruby
<<<<<<< HEAD
pod 'Firebase/Crashlytics', '~> 10.0.0'
=======
pod 'Firebase/Crashlytics', '~> 10.5.0'
>>>>>>> dependabot/cocoapods/Firebase-10.5.0
```

**Strategy**:
- Same major version (10.x → 10.y): Accept higher version
- Different major version (9.x → 10.x): ESCALATE

### Podfile.lock Conflicts
**Strategy**: Always auto-resolve
```bash
git checkout --theirs ios/Podfile.lock
git add ios/Podfile.lock
cd ios && pod install && cd ..
```

The `pod install` will regenerate the lock file correctly based on the merged Podfile.

### Platform Version Conflicts
**Example**:
```ruby
platform :ios, '15.0'  # Current
platform :ios, '16.0'  # Incoming
```

**Strategy**: ESCALATE immediately (affects minimum iOS version, requires team decision)

## Pod Install Failures

### Common Errors

**Missing Ruby Dependencies**:
```
[!] You must run `gem install cocoapods` to use CocoaPods
```
**Action**: ESCALATE (environment issue, not dependency issue)

**Pod Not Found**:
```
[!] Unable to find a specification for `PodName`
```
**Action**:
- Try `pod repo update` once to refresh specs
- If still fails: ESCALATE (pod may not exist at that version)

**Version Conflicts**:
```
[!] CocoaPods could not find compatible versions for pod "Firebase/Core"
```
**Action**: ESCALATE (complex dependency resolution needed)

### Success Signals
✅ `pod install` exits with code 0
✅ Output shows "Pod installation complete!"
✅ `ios/Pods/` directory exists
✅ `ios/ChartPro.xcworkspace` exists

## React Native Integration

CocoaPods changes may affect React Native integration:
- React Native itself is installed via CocoaPods
- Changes to `react-native` pod version: ESCALATE (must match package.json)
- Changes to RN-related pods (e.g., Hermes, Flipper): Review carefully

**Check for Consistency**:
```bash
# React Native version in package.json
grep '"react-native"' package.json

# React Native version in Podfile.lock
grep 'React-Core' ios/Podfile.lock
```

If versions don't align: ESCALATE

## Escalation Triggers
- Conflicts in `platform :ios` declaration
- Major version updates in core pods (Firebase, React Native)
- `pod install` failures after 1 retry with `pod repo update`
- React Native version mismatches between package.json and Podfile.lock
- Conflicts in native module integration (e.g., `use_native_modules!`)
- Multiple Podfile conflicts beyond simple version numbers

## Success Criteria (Local)
✅ `yarn install --frozen-lockfile` exits with code 0
✅ `pod install` exits with code 0
✅ No merge conflicts remain
✅ `ios/ChartPro.xcworkspace` exists and is valid
✅ Podfile is syntactically valid (Ruby syntax)

## Success Criteria (CI - Required)
✅ CI workflow `codeql.yml` passes on `codeql-build-verification` branch
✅ `analyze-swift` job succeeds
✅ xcodebuild completes successfully

## Important Notes
- **Never run xcodebuild locally during merge** - extremely time-consuming
- **Always push to codeql-build-verification for validation** - this is the source of truth
- **pod install is cheap, xcodebuild is expensive** - run pod install locally, xcodebuild in CI
- **CI failure = immediate escalation** - don't attempt local fixes without understanding root cause
- **CocoaPods changes can affect React Native** - verify RN version consistency
