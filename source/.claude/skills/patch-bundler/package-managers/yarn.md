# Yarn Package Manager Commands

## Lock File
- **Name**: `yarn.lock`
- **Auto-resolve command**: `git checkout --theirs yarn.lock`

## Manifest File
- **Name**: `package.json`
- **Conflict resolution**: ESCALATE by default
  - Only auto-resolve if conflict is a single dependency version number
  - Must be minor/patch version change (not major)
  - No other changes in the conflicted section
  - Otherwise: ESCALATE

## Install Command
```bash
yarn install
```

## Validation Strategy

### Local Validation (Minimal)
For yarn branches, run minimal validation during merge:

```bash
yarn install --frozen-lockfile
```

This ensures dependencies resolve correctly. **Do NOT run `yarn test` locally** - tests should run in CI for proper validation.

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
- `yarn test` (full test suite)

This is the authoritative validation - if CI passes, the yarn changes are safe.

## Common Build Failures

### TypeScript Breaking Changes
**Symptoms**: `error TS2339`, `error TS2345`, `error TS2741`
**Strategy**:
- Review error output for affected files
- If errors are in 1-2 files with clear fixes (method renamed, property changed), attempt fix
- If errors span multiple files or are ambiguous, escalate

### Missing Peer Dependencies
**Symptoms**: `warning "package@version" has unmet peer dependency "peer@version"`
**Strategy**:
- If warnings only (not errors), proceed
- If peer dependency errors block build, escalate

### Version Incompatibilities
**Symptoms**: `error package@version requires dependency@^X.Y.Z but found @A.B.C`
**Strategy**:
- Check if adjusting version ranges resolves it
- Max 2 attempts to find compatible versions
- If no resolution, escalate

## Yarn-Specific Edge Cases

### Workspace Projects
If `package.json` contains `"workspaces"`:
- Build command may need to be `yarn workspaces run build`
- Lock file conflicts may be more complex
- Consider escalating if workspace-specific conflicts arise

### Yarn Berry (v2+)
If `.yarnrc.yml` exists:
- Lock file format is different
- Cache handling differs
- Commands are the same (`yarn install`, `yarn build`)

## Success Criteria (Local)
✅ `yarn install --frozen-lockfile` exits with code 0
✅ No merge conflicts remain
✅ package.json and yarn.lock are syntactically valid

## Success Criteria (CI - Required)
✅ CI workflow `codeql.yml` passes on `codeql-build-verification` branch
✅ `analyze-javascript` job succeeds
✅ `yarn test` passes (full test suite)
