# Platform Detection from Branch Names

This document defines how to detect which package manager/platform a dependabot branch targets based on its naming pattern.

## Branch Naming Patterns

Dependabot uses consistent naming patterns that encode the package manager:

### JavaScript/TypeScript (Yarn)
**Pattern**: `dependabot/npm_and_yarn/*`
**Examples**:
- `dependabot/npm_and_yarn/typescript-5.0.0`
- `dependabot/npm_and_yarn/@types/react-18.2.0`

**Package Manager**: `yarn`
**Config File**: `package-managers/yarn.md`

---

### Android (Gradle)
**Pattern**: `dependabot/gradle/android/*`
**Examples**:
- `dependabot/gradle/android/com.google.firebase-firebase-crashlytics-gradle-3.0.6`
- `dependabot/gradle/android/com.android.tools.build-gradle-8.13.2`

**Package Manager**: `gradle`
**Config File**: `package-managers/gradle.md`

---

### iOS (CocoaPods)
**Pattern**: `dependabot/cocoapods/*`
**Examples**:
- `dependabot/cocoapods/Firebase-10.0.0`
- `dependabot/cocoapods/Alamofire-5.8.0`

**Package Manager**: `cocoapods`
**Config File**: `package-managers/cocoapods.md`

---

### Python (Poetry)
**Pattern**: `dependabot/pip/*`
**Examples**:
- `dependabot/pip/lambda-name/boto3-1.42.79`
- `dependabot/pip/lambda-name/pyyaml-6.0.3`
- `dependabot/pip/some-service/requests-2.32.5`

**Package Manager**: `poetry`
**Config File**: `package-managers/poetry.md`

---

### GitHub Actions
**Pattern**: `dependabot/github_actions/*`
**Examples**:
- `dependabot/github_actions/actions/checkout-5`
- `dependabot/github_actions/github/codeql-action-4`

**Package Manager**: `github-actions`
**Config File**: `package-managers/github-actions.md`

---

## Detection Logic

For each branch in the tracking file:

1. **Extract branch name** (without `origin/` prefix if present)
2. **Match against patterns** in order:
   - If contains `/npm_and_yarn/` → yarn
   - If contains `/gradle/` → gradle
   - If contains `/cocoapods/` → cocoapods
   - If contains `/pip/` → poetry
   - If contains `/github_actions/` → github-actions
   - Else → ESCALATE (unknown platform)

3. **Load corresponding package manager config** from `package-managers/<manager>.md`

4. **Use config for**:
   - Lock file name and resolution strategy
   - Manifest file name and resolution strategy
   - Install commands
   - Validation commands
   - Platform-specific conflict handling

## Multi-Platform Support

Modern projects often have dependencies across multiple platforms:

**React Native projects:**
- **JS/TS layer**: React Native framework, npm packages (Yarn)
- **Android layer**: Gradle plugins, Android libraries
- **iOS layer**: CocoaPods, Swift packages
- **CI/CD layer**: GitHub Actions versions

**Python monorepos (Lambda functions, microservices):**
- **Python layer**: Lambda functions, services (Poetry)
- **CI/CD layer**: GitHub Actions versions

**Full-stack applications:**
- May combine any of the above platforms

The patch-bundler skill must handle all of these in a single run, detecting the platform for each branch and applying the appropriate merge strategy.

## Unknown Platforms

If a branch doesn't match any known pattern:
- Mark as ESCALATED immediately
- Log: "Unknown platform - cannot determine package manager"
- Continue to next branch
