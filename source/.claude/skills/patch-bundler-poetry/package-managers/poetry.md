# Poetry Package Manager Commands

## Lock File
- **Name**: `poetry.lock`
- **Auto-resolve command**: `git checkout --theirs poetry.lock`

## Manifest File
- **Name**: `pyproject.toml`
- **Conflict resolution**: Manual merge favoring higher version numbers

## Python Version Management

Check Python version requirement from pyproject.toml:
```bash
grep 'python = ' pyproject.toml
```

If conda is available and Python version doesn't match, create/use conda environment:
```bash
# Extract required version (e.g., "^3.10" or ">=3.10,<3.13")
conda create -n patch-bundler-validation python=3.10 -y
conda activate patch-bundler-validation
```

Or use the project's existing conda/venv if present.

## Install Command
```bash
poetry install
```

**Note**: If the project uses a local poetry wrapper (check for `./poetry` script):
```bash
./poetry install
```

## Critical: Lock File Regeneration

**IMPORTANT**: After all merges complete and before validation, ALWAYS run:

```bash
poetry lock --no-update
# OR if project uses local poetry:
./poetry lock --no-update
```

**Why this is critical:**
- Accepting "theirs" during conflicts may leave lock file inconsistent
- Manual edits to `pyproject.toml` require lock file regeneration
- Multiple merges may accumulate inconsistencies
- `poetry lock --no-update` regenerates lock file without upgrading packages
- This ensures lock file is in sync with `pyproject.toml`

**When to run:**
- After ALL merges complete (not after each merge)
- Before running `poetry install`
- After any manual conflict resolution in `pyproject.toml`

## Comprehensive Validation Strategy

After EACH merge completes (immediately after merge commit), run validation in this order:

### 0. Regenerate Lock File (REQUIRED - NEW!)
```bash
poetry lock --no-update
# OR
./poetry lock --no-update
```
**Exit on failure**: Yes - if lock file can't be generated, dependencies are incompatible

### 1. Dependency Installation (Required)
```bash
poetry install  # or ./poetry install
```
**Exit on failure**: Yes - if dependencies can't install, everything else will fail

### 2. Run Tests (Required)

**Preferred (if Makefile exists with tests target):**
```bash
make tests
```

**Fallback (if no Makefile or no tests target):**
```bash
poetry run pytest
# OR for local poetry installations:
./poetry run pytest
```

**Detection logic:**
```bash
if [ -f Makefile ] && grep -q "^tests:" Makefile; then
    make tests
else
    poetry run pytest || ./poetry run pytest
fi
```

**Exit on failure**: Yes - tests must pass

### 3. Type Checking (Recommended)
```bash
make mypy
# OR
poetry run mypy app/
```
**Exit on failure**: No - log warnings but continue. Type errors are often pre-existing.

### 4. Linting/Formatting (Recommended)
```bash
make format
# OR
poetry run pre-commit run --all-files
# OR
poetry run ruff check .
```
**Exit on failure**: No - formatting issues are often pre-existing or auto-fixable

### 5. Lock File Validation (Optional)
```bash
make check-lockfile
# OR
poetry lock --check
```
**Exit on failure**: No - informational only (already regenerated in step 0)

## Validation Command Strategy

The agent should attempt validation in this priority order:

1. **Regenerate lock file FIRST** (critical):
   ```bash
   poetry lock --no-update || ./poetry lock --no-update
   ```

2. **Try Makefile targets** (most projects have these configured):
   ```bash
   make tests && make mypy && make format
   ```

3. **Fall back to direct poetry commands**:
   ```bash
   poetry run pytest && poetry run mypy app/ && poetry run ruff check .
   ```

4. **Minimal validation** (if above tools not configured):
   ```bash
   poetry run pytest  # At minimum, tests must run
   ```

## Intelligent Validation

The agent should:
1. **Regenerate lock file** (required, new step 0)
2. Check which tools are available before running them
3. Run tests (required) - validation fails if tests fail
4. Run type checking (recommended) - log output but don't fail on type errors
5. Run linting (recommended) - log output but don't fail on lint errors
6. Summarize all validation results at the end

**Example validation flow**:
```bash
# Step 0 - Regenerate lock file (CRITICAL!)
poetry lock --no-update || exit 1

# Required - must pass
poetry install || exit 1
make tests || exit 1

# Recommended - log but continue
make mypy || echo "⚠️  Type checking found issues (non-blocking)"
make format || echo "⚠️  Formatting issues found (non-blocking)"

# Success if we got here
echo "✅ Core validation passed (tests green)"
```

## Common Build/Test Failures

### Lock File Generation Failures
**Symptoms**: `SolverProblemError`, `poetry.lock` generation fails
**Strategy**:
- This indicates incompatible dependency versions from merges
- Review the error output to identify conflicting packages
- May need to manually adjust version constraints in `pyproject.toml`
- Escalate if unable to resolve after 2 attempts

### Import Errors
**Symptoms**: `ModuleNotFoundError`, `ImportError`
**Strategy**:
- Verify `poetry.lock` was regenerated successfully
- Run `poetry install` to ensure all dependencies are installed
- If persistent after lock regeneration, may indicate version incompatibility - escalate

### Breaking API Changes
**Symptoms**: `AttributeError: 'X' object has no attribute 'Y'`, `TypeError: unexpected keyword argument`
**Strategy**:
- Review error output for affected files
- If errors are in 1-2 files with clear fixes (method renamed, parameter changed), attempt fix
- If errors span multiple files or are ambiguous, escalate

### Type Annotation Errors (mypy/pyright)
**Symptoms**: Type checking errors if project uses static type checking
**Strategy**:
- Type errors are often pre-existing and non-blocking
- Log them for informational purposes
- Only escalate if tests also fail

### Dependency Version Conflicts
**Symptoms**: `SolverProblemError` during `poetry lock`
**Strategy**:
- Review which packages have conflicting constraints
- Check if you can adjust version ranges in `pyproject.toml`
- May need to revert specific merges that introduce conflicts
- Escalate if no clear resolution after 2 attempts

### Test Failures
**Symptoms**: Tests that passed before now fail
**Strategy**:
- Review test output to determine if failure is from dependency change
- If 1-2 clear test failures related to API changes, may attempt fix
- If widespread test failures or unclear cause, escalate

## Poetry-Specific Edge Cases

### Python Version Constraints
If `pyproject.toml` has strict Python version requirements:
- Use conda to create environment with matching Python version
- Or ensure local Python version matches project requirements
- May need to use `poetry env use python3.X` to set correct version
- If version mismatch blocks install, escalate

### Extra Dependencies Groups
If conflict involves optional dependency groups:
```toml
[tool.poetry.group.dev.dependencies]
```
- Dev dependencies don't affect production code
- Safe to accept conflicts in dev groups if tests pass
- Be cautious with conflicts in main `[tool.poetry.dependencies]`

### Local Poetry Installation
Some projects install Poetry locally (e.g., `./poetry` script):
- Check for `./poetry` script in project root
- Use `./poetry` instead of `poetry` if it exists
- This ensures consistent Poetry version across team

## Success Criteria

### Required (must pass)
✅ `poetry lock --no-update` exits with code 0 (NEW!)
✅ `poetry install` exits with code 0
✅ `make tests` (or `poetry run pytest`) exits with code 0
✅ No import errors or module not found errors
✅ Test suite passes

### Recommended (log but don't fail)
⚠️  `make mypy` - type checking passes
⚠️  `make format` - linting/formatting passes
⚠️  `poetry lock --check` - lock file is consistent

## Lock File Resolution Best Practice

**Always prefer accepting theirs for poetry.lock conflicts:**
```bash
git checkout --theirs poetry.lock
git add poetry.lock
git commit --no-edit
```

Then **AFTER ALL MERGES**, regenerate the lock file:
```bash
poetry lock --no-update
```

This ensures the lock file is consistent and properly reflects all dependency changes.

## Why `--no-update` Flag?

`poetry lock --no-update` regenerates the lock file **without upgrading packages beyond what's in pyproject.toml**:
- Maintains the versions specified in your merges
- Resolves the dependency graph cleanly
- Doesn't introduce surprise upgrades
- Ensures reproducible builds

Without `--no-update`, Poetry might upgrade packages to their latest versions, which defeats the purpose of bundling specific security updates.

## Example Validation Script

```bash
#!/bin/bash
set -e  # Exit on first error for required checks

echo "=== Regenerating lock file (CRITICAL) ==="
if [ -x "./poetry" ]; then
    ./poetry lock --no-update
else
    poetry lock --no-update
fi

echo "=== Installing dependencies ==="
poetry install || ./poetry install

echo "=== Running tests (REQUIRED) ==="
if command -v make &> /dev/null && grep -q "^tests:" Makefile; then
    make tests
else
    poetry run pytest
fi

echo "=== Type checking (RECOMMENDED) ==="
if command -v make &> /dev/null && grep -q "^mypy:" Makefile; then
    make mypy || echo "⚠️  Type checking issues found (non-blocking)"
else
    poetry run mypy app/ 2>/dev/null || echo "⚠️  mypy not configured or found issues"
fi

echo "=== Linting (RECOMMENDED) ==="
if command -v make &> /dev/null && grep -q "^format:" Makefile; then
    make format || echo "⚠️  Formatting issues found (non-blocking)"
else
    poetry run ruff check . 2>/dev/null || echo "⚠️  ruff not configured"
fi

echo "✅ Validation complete - all required checks passed!"
```
