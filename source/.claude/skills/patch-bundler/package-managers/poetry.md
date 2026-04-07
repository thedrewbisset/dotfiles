# Poetry Package Manager Commands

## Lock File
- **Name**: `poetry.lock`
- **Rebase conflict resolution** (happens during `git rebase`):
  ```bash
  # During rebase when poetry.lock conflicts:
  git checkout --theirs poetry.lock
  git add poetry.lock
  cd <lambda-directory>
  poetry lock  # Regenerate to match current pyproject.toml
  cd -
  git add <lambda-directory>/poetry.lock
  git rebase --continue
  ```

**Note**: With rebase-before-merge workflow, lock file conflicts are resolved during rebase, not during merge. The merge itself will be clean.

## Manifest File
- **Name**: `pyproject.toml`
- **Conflict resolution**: Manual merge favoring higher version numbers

## Install Command
```bash
poetry install
```

**Note**: If the project uses a local poetry wrapper (check for `./poetry` script):
```bash
./poetry install
```

## Test/Validation Command
```bash
poetry run pytest
```

Or if the project uses Make:
```bash
make tests
```

## Validation Strategy

**IMPORTANT**: With rebase-before-merge workflow, lock files are already regenerated during rebase. Validation is optional and minimal.

After merge commit completes:
1. **Optional**: Run quick validation:
   - `cd <lambda-dir> && poetry install` - verify dependencies resolve
   - `make tests` (or `poetry run pytest`) - verify tests pass

**Note**: Lock file regeneration happens during rebase, NOT after merge. The merge itself should be clean with no file modifications needed.

## Common Build/Test Failures

### Import Errors
**Symptoms**: `ModuleNotFoundError`, `ImportError`
**Strategy**:
- Verify `poetry.lock` is properly resolved
- Run `poetry install` to ensure all dependencies are installed
- If persistent, may indicate version incompatibility - escalate

### Breaking API Changes
**Symptoms**: `AttributeError: 'X' object has no attribute 'Y'`, `TypeError: unexpected keyword argument`
**Strategy**:
- Review error output for affected files
- If errors are in 1-2 files with clear fixes (method renamed, parameter changed), attempt fix
- If errors span multiple files or are ambiguous, escalate

### Type Annotation Errors (mypy/pyright)
**Symptoms**: Type checking errors if project uses static type checking
**Strategy**:
- If type errors only (tests still pass), may be acceptable
- If blocking tests, review and fix clear issues
- If complex type issues, escalate

### Dependency Version Conflicts
**Symptoms**: `SolverProblemError`, `poetry.lock` conflicts
**Strategy**:
- Poetry lock file conflicts are complex - accept theirs and reinstall
- If `poetry install` fails after accepting theirs, escalate
- Don't attempt to manually resolve Poetry's dependency resolution

### Test Failures
**Symptoms**: Tests that passed before now fail
**Strategy**:
- Review test output to determine if failure is from dependency change
- If 1-2 clear test failures related to API changes, may attempt fix
- If widespread test failures or unclear cause, escalate

## Poetry-Specific Edge Cases

### Python Version Constraints
If `pyproject.toml` has strict Python version requirements:
- Ensure local Python version matches project requirements
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
✅ `poetry install` exits with code 0
✅ `poetry run pytest` (or `make tests`) exits with code 0
✅ No import errors or module not found errors
✅ Test suite passes (warnings acceptable)

## Lock File Resolution Best Practice

**With Rebase-Before-Merge Workflow:**

Lock file conflicts are resolved during `git rebase`, not during `git merge`:

```bash
# During rebase when poetry.lock conflicts occur:

# Step 1: Accept their lock file
git checkout --theirs poetry.lock
git add poetry.lock

# Step 2: CRITICAL - Regenerate lock file to match current pyproject.toml
cd <lambda-directory>
poetry lock  # Regenerates lock to match accumulating branch's pyproject.toml
cd -

# Step 3: Stage regenerated lock and continue rebase
git add <lambda-directory>/poetry.lock
git rebase --continue
```

**Why regenerate during rebase:**
- Dependabot branch started from old commit (stale)
- Your accumulating branch has newer pyproject.toml from previous merges
- Regenerating updates lock file to match current constraints
- When rebase completes, lock file is consistent
- **Merge is then CLEAN (no conflicts!)** because lock files are already compatible

**What happens without regeneration:**
1. ❌ Lock file has boto3 1.42.23 (from old dependabot branch)
2. ❌ pyproject.toml requires boto3 ^1.42.45 (from accumulating branch)
3. ❌ Inconsistent state causes merge conflicts or runtime errors
4. 💥 Each subsequent rebase/merge repeats the same conflicts

**With rebase-first approach:**
1. ✅ Rebase updates dependabot branch to current state
2. ✅ Lock regeneration happens once during rebase
3. ✅ Merge is clean (fast-forward with --no-ff)
4. ✅ Future rebases through this history are clean

## Build Command Alternative
Some FastAPI projects don't have a traditional "build" step. Validation strategies:
1. **Run tests**: `make tests` or `poetry run pytest`
2. **Type checking**: `poetry run mypy app/` (if configured)
3. **Linting**: `poetry run ruff check .` (if configured)

For the patch-bundler skill, **running tests is the recommended validation** for Poetry projects.
