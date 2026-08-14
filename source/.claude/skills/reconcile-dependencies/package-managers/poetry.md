# Poetry Package Manager Commands

## Lock File
- **Name**: `poetry.lock`
- **Rebase conflict resolution** (happens during `git rebase`):
  ```bash
  # During rebase when poetry.lock conflicts:
  git checkout --ours poetry.lock   # NOT --theirs — see base-merge-logic.md
  git add poetry.lock
  cd <lambda-directory>
  poetry lock  # Regenerate to match current pyproject.toml
  cd -
  git add <lambda-directory>/poetry.lock
  # Verify no package regressed vs. the pre-rebase accumulating-branch HEAD
  # (see "Mandatory Post-Regeneration Verification" in base-merge-logic.md)
  # before continuing:
  git rebase --continue
  ```

**`--ours`, not `--theirs`**: during a rebase, `--theirs` means the
dependabot branch's own commit — its lock file, frozen at whatever old
commit that branch forked from. `--ours` means the accumulating branch being
rebased onto, which already carries every prior merge's fixes. Using
`--theirs` here silently drags the lock file back toward the dependabot
branch's stale baseline; a real incident on this repo saw three prior
merges' package bumps (`aiohttp`, `redis`, `python-multipart`,
`cryptography`) each get clobbered by the very next rebase in the chain,
because every one used `--theirs`.

**Cache staleness compounds this**: if the local Poetry package cache hasn't
refreshed recently, `poetry lock` after `--ours` may still resolve to an
older version than PyPI currently offers, even when the manifest constraint
permits newer. If a regenerated version looks older than expected, run
`poetry cache clear PyPI --all -n` before assuming the constraint itself is
the problem.

**Plain `poetry lock` won't force an upgrade the branch intends**: when a
dependabot branch only *widens* a version range (e.g. `^7.4.0` →
`>=7.4,<9.0`) rather than bumping a pin, `poetry lock` keeps whatever's
already locked if it still satisfies the new range — it does not walk
forward to what the branch is actually trying to achieve. Don't treat this
the same as the "constraint already satisfied, no bump needed" case (see
python-multipart example above) — check whether the branch's target version
falls inside an open Dependabot alert's still-vulnerable range before
concluding a no-op is fine. If the branch genuinely needs the version to
move (alert still open at the old version, or the PR title names a specific
target), force it precisely:
```bash
poetry add "<package>@<exact-version>" --lock
```
This pins the manifest to an exact version as a side effect — **immediately
correct that back** to the range the dependabot branch's `pyproject.toml`
diff specifies (the exact pin is a `poetry add` artifact, not something
dependabot asked for), then re-run `poetry lock` once the manifest is
correct. Re-verify with the same pre-rebase diff check afterward — `poetry
add` re-resolves more than just the target package and needs the same
regression check as any other regeneration.

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
- Poetry lock file conflicts are complex — accept **ours** (the accumulating
  branch's lock, not the dependabot branch's) and regenerate
- Verify the regenerated lock doesn't downgrade any package a prior merge in
  this run already fixed (see Mandatory Post-Regeneration Verification in
  base-merge-logic.md) — a stale local cache can cause this silently
- If `poetry install` fails after regenerating, escalate
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

# Step 1: Accept OUR lock file (the accumulating branch's — NOT --theirs,
# which would be the stale dependabot branch's own lock)
git checkout --ours poetry.lock
git add poetry.lock

# Step 2: CRITICAL - Regenerate lock file to match current pyproject.toml
cd <lambda-directory>
poetry lock  # Regenerates lock to match accumulating branch's pyproject.toml
cd -

# Step 3: Verify no regression before continuing — diff against the
# accumulating branch's pre-rebase HEAD and confirm every changed package
# version is >= what was there before (see base-merge-logic.md's Mandatory
# Post-Regeneration Verification). A stale local package-manager cache can
# make `poetry lock` silently resolve to an older version than what's
# actually available, even when starting from --ours.
git diff <accumulating-branch-pre-rebase-sha> -- <lambda-directory>/poetry.lock

# Step 4: Stage regenerated lock and continue rebase
git add <lambda-directory>/poetry.lock
git rebase --continue
```

**Why `--ours`, not `--theirs`:**
- `--theirs` in a rebase is the dependabot branch's own stale lock file.
  `--ours` is the accumulating branch, which already has every prior
  merge's fixes baked in.
- Starting from `--theirs` and regenerating does not reliably recover the
  accumulating branch's prior fixes — `poetry lock` will happily keep any
  version from the stale starting point that still satisfies the merged
  manifest, even if a newer version was already locked in on a previous
  commit. This is exactly what caused a real regression: three consecutive
  merges each had their target package's fix silently reverted by the next
  rebase in the chain, because each one started from `--theirs`.

**What happens if you use `--theirs` anyway:**
1. ❌ Lock file starts from the dependabot branch's old snapshot (e.g. boto3
   pinned to whatever it was when that branch forked from main weeks ago)
2. ❌ `poetry lock` resolves against the merged `pyproject.toml`, but a
   stale local cache or a permissive constraint range means it can settle
   on that old snapshot's version instead of the newer one a prior merge on
   the accumulating branch already locked in
3. ❌ The merge commit looks clean and `poetry check --lock` passes, but a
   previously-fixed package has silently regressed
4. 💥 Each subsequent rebase repeats this, compounding — by the Nth merge,
   several earlier fixes can all be simultaneously reverted with no error
   at any step

**With `--ours` first:**
1. ✅ Rebase starts from the accumulating branch's already-correct lock
2. ✅ Regeneration only has to resolve the one manifest change this branch
   introduces, on top of a correct base
3. ✅ Post-regeneration diff against the pre-rebase HEAD confirms nothing
   regressed before the rebase is allowed to continue
4. ✅ Merge is clean, and — unlike the `--theirs` path — actually stays
   correct across the whole chain of merges

## Build Command Alternative
Some FastAPI projects don't have a traditional "build" step. Validation strategies:
1. **Run tests**: `make tests` or `poetry run pytest`
2. **Type checking**: `poetry run mypy app/` (if configured)
3. **Linting**: `poetry run ruff check .` (if configured)

For the patch-bundler skill, **running tests is the recommended validation** for Poetry projects.
