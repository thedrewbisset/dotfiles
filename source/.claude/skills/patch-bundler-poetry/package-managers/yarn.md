# Yarn Package Manager Commands

## Lock File
- **Name**: `yarn.lock`
- **Auto-resolve command**: `git checkout --theirs yarn.lock`

## Manifest File
- **Name**: `package.json`
- **Conflict resolution**: Manual merge favoring higher version numbers

## Install Command
```bash
yarn install
```

## Build Command
```bash
yarn build
```

## Validation Strategy
After resolving conflicts and installing dependencies:
1. Run `yarn build` to catch:
   - Type errors (TypeScript)
   - Breaking API changes
   - Missing dependencies
   - Compilation failures

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

## Success Criteria
✅ `yarn build` exits with code 0
✅ No error messages in output (warnings acceptable)
✅ Build artifacts generated in expected locations
