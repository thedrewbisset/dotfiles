# GitHub Actions Package Manager Commands

## Platform Context
- **Files Modified**: `.github/workflows/*.yml`, `.github/workflows/*.yaml`
- **Working Directory**: Project root
- **Dependency Resolution**: N/A (YAML files, not dependencies)

## Lock File
- **Name**: None
- **Auto-resolve command**: N/A

## Manifest Files
- **Pattern**: `.github/workflows/*.yml`
- **Conflict resolution**: Accept theirs (GitHub Actions version updates are typically safe)

**Example Change**:
```yaml
# Current
- uses: actions/checkout@v4

# Incoming
- uses: actions/checkout@v5
```

## Install Command
None - GitHub Actions YAML files don't require installation.

## Validation Strategy

### Local Validation (Minimal)
For GitHub Actions branches, no local validation is needed during merge:
- YAML syntax is validated by GitHub when workflows run
- No build or test commands needed locally

Simply merge and mark COMPLETED.

### CI Validation (Optional but Recommended)
After all branches are merged, pushing to `origin/codeql-build-verification` will validate:
- YAML syntax is correct
- Workflows can be parsed
- Updated action versions exist and work

However, GitHub Actions changes are lower risk than code dependencies.

## Common GitHub Actions Scenarios

### Action Version Updates
**Pattern**: `dependabot/github_actions/actions/checkout-5`
**Change**: Bumps action version in workflow files

**Strategy**: Auto-accept (these are almost always safe)

**Example**:
```yaml
- uses: actions/checkout@v4  →  - uses: actions/checkout@v5
- uses: actions/setup-node@v4  →  - uses: actions/setup-node@v6
```

### Conflicts in Workflow Files
If merge conflicts occur in `.github/workflows/*.yml`:

**Strategy**:
- If conflict is only in action version: Accept theirs (higher version)
- If conflict involves workflow logic/steps: ESCALATE (too risky to auto-resolve)

**Example - Safe to Auto-resolve**:
```yaml
<<<<<<< HEAD
- uses: actions/checkout@v4
=======
- uses: actions/checkout@v5
>>>>>>> dependabot/github_actions/actions/checkout-5
```
Resolution: Accept v5 (theirs)

**Example - Escalate**:
```yaml
<<<<<<< HEAD
- name: Run tests
  run: npm test
=======
- name: Run tests
  run: yarn test
>>>>>>> some-branch
```
Resolution: ESCALATE (workflow logic changed, not just versions)

## Edge Cases

### Multiple Workflow Files Modified
If dependabot updates the same action across multiple workflow files:
- Merge each file independently
- If any file has conflicts beyond version updates: ESCALATE

### New Action Parameters
If the updated action version introduces new parameters or deprecates old ones:
- Accept the change (GitHub will show warnings if parameters are invalid)
- CI validation will catch any issues

### Breaking Changes in Actions
Major version updates (v3 → v4) may have breaking changes:
- Dependabot usually handles these correctly in the PR
- If merge is clean: Accept
- If conflicts arise: ESCALATE

## Escalation Triggers
- Conflicts in workflow logic (steps, jobs, conditions)
- Conflicts in workflow triggers (on: push/pull_request)
- Multiple workflow files with complex conflicts
- YAML syntax errors after merge (use `yamllint` if available)

## Success Criteria (Local)
✅ No merge conflicts remain
✅ YAML files are syntactically valid (no merge markers)
✅ Workflow files exist in `.github/workflows/`

## Success Criteria (CI - Optional)
✅ GitHub can parse the workflow files (no syntax errors)
✅ Updated actions exist and are accessible
✅ Workflows run successfully (if triggered)

## Important Notes
- **GitHub Actions updates are low-risk** - they don't affect build/runtime
- **Auto-accept version-only changes** - these are almost always safe
- **YAML syntax matters** - ensure no merge markers remain
- **CI will validate** - GitHub shows workflow errors in the Actions tab
- **Breaking changes are rare** - dependabot usually handles them correctly
