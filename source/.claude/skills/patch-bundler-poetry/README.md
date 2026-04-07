# Patch Bundler Skill - Poetry Variant

Bundles multiple dependabot security update branches into a single consolidated branch using git merge --no-ff, with comprehensive validation including **lock file regeneration**, tests, type checking, and linting.

## Purpose

When managing security updates across many dependencies in a Poetry project, this skill:
- Consolidates multiple dependabot PRs into a single branch using merge --no-ff
- Creates explicit merge commits for clear audit trail
- Preserves commit SHAs so GitHub auto-closes dependabot PRs on merge
- **🔥 NEW: Regenerates poetry.lock** with `poetry lock --no-update` (prevents CI failures!)
- **Runs comprehensive validation**: tests, type checking, and linting
- **Uses conda for Python version management** if needed
- Makes it easy to see all bundled updates in git log
- Tracks progress and escalates complex cases
- Enables incremental work without blocking on hard cases

## Why Merge --no-ff?

The merge --no-ff approach offers the best visibility:
- **GitHub Integration**: Preserves commit SHAs → auto-closes dependabot PRs
- **Clear Audit Trail**: Merge commits explicitly show what was bundled
- **Easy Review**: `git log --oneline --graph` clearly shows all security updates
- **Verbose but Informative**: Each branch integration is a distinct, visible event

## Comprehensive Validation

Unlike simpler bundlers, this skill runs **comprehensive validation** after merging:

### ✅ Required Checks (must pass)
1. **Python Version**: Matches `pyproject.toml` (uses conda if needed)
2. **Dependencies**: `poetry install` succeeds
3. **Tests**: `make tests` or `poetry run pytest` passes

### ⚠️ Recommended Checks (log warnings)
4. **Type Checking**: `make mypy` or `poetry run mypy app/`
5. **Linting**: `make format` or `poetry run ruff check .`
6. **Lock File**: `poetry lock --check`

**Why this approach?**
- **Tests are critical**: If tests fail, something is broken
- **Types are informational**: Type errors are often pre-existing
- **Formatting is fixable**: Can be auto-corrected, not blocking

## Quick Start

1. **Prepare target branch**: Checkout your consolidated security updates branch
   ```bash
   cd ../api-security-updates  # Your FastAPI backend worktree
   git checkout -b chore/security-updates
   ```

2. **Create tracking file**: List dependabot branches to process
   ```bash
   # Example: dependabot-branches.md
   - dependabot/pip/fastapi-0.121.0: PENDING
   - dependabot/pip/uvicorn-0.35.0: PENDING
   - dependabot/pip/pydantic-2.12.3: PENDING
   ```

3. **Run the skill**:
   ```bash
   /patch-bundler-poetry dependabot-branches.md
   ```

4. **Review results**: 
   - Check `git log --oneline --graph` to see merge commits
   - Review validation output (tests, type checking, linting)
   - Check tracking file for any ESCALATED items

## Tracking File Format

The tracking file uses markdown with status annotations:

```markdown
# Dependabot Branches to Merge

- dependabot/pip/package-a-1.2.3: PENDING
- dependabot/pip/package-b-4.5.6: COMPLETED
- dependabot/pip/package-c-7.8.9: ESCALATED
  - Exception Files: pyproject.toml, app/api/routes.py
  - Log Output:
    ```
    ModuleNotFoundError: No module named 'old_package_name'
    tests/test_api.py::test_endpoint FAILED
    ```
```

## Workflow Overview

For each branch:
1. Save current commit SHA (rollback point)
2. Merge remote branch with `git merge --no-ff origin/<branch-name>`
3. Handle conflicts if they occur:
   - **poetry.lock**: Auto-accept theirs, mark for later validation
   - **pyproject.toml**: Smart merge favoring latest versions
   - **Source code**: Escalate (too risky)
4. Continue to next branch (no validation yet)

After ALL merges:
5. **Validate Python version**: Check pyproject.toml, use conda if needed
6. **Regenerate lock file**: `poetry lock --no-update` (prevents CI failures)
7. **Install dependencies**: `poetry install`
8. **Run tests** (required): `make tests` or `poetry run pytest`
9. **Type checking** (recommended): `make mypy` - log warnings
10. **Linting** (recommended): `make format` - log warnings
11. **Summarize**: Report what passed/failed/warned

## Validation Output Example

```
=== Comprehensive Validation ===

✅ Python version: 3.10 (matches requirement ^3.10)
✅ Lock file regenerated: poetry lock --no-update succeeded
✅ Dependencies installed: poetry install succeeded
✅ Tests passed: 127 passed in 4.23s

⚠️  Type checking: Found 3 type errors (non-blocking)
    app/models.py:45: error: Incompatible return type
    app/utils.py:12: error: Missing type annotation

⚠️  Linting: Found formatting issues (auto-fixable)
    app/main.py: Line too long (E501)

📊 Validation Summary:
   Required checks: ✅ ALL PASSED
   Optional checks: ⚠️  2 warnings (non-blocking)
   
🎉 Core validation successful - safe to merge!
```

## Merge Commit Output

After bundling, `git log --oneline --graph` will show:

```
* Merge dependabot/pip/pydantic-2.12.3
|\
| * build(deps): bump pydantic from 2.10.0 to 2.12.3
|/
* Merge dependabot/pip/uvicorn-0.35.0
|\
| * build(deps): bump uvicorn from 0.30.0 to 0.35.0
|/
* Previous commits...
```

## Conflict Resolution Strategy

### Automatic Resolution
- **poetry.lock**: Accept theirs - Poetry's lock file is complex, don't manually merge
- **pyproject.toml version conflicts**: Favor higher version, validate compatibility

### Smart Resolution (2-3 attempts)
- Analyze test failures
- Try installing with resolved versions
- Fix straightforward breaking changes

### Escalation Triggers
- Source code conflicts
- 3 failed resolution attempts
- Tests fail after validation
- Import errors after poetry install

## Python Version Management with Conda

The agent automatically handles Python version requirements:

1. **Check required version**:
   ```bash
   grep 'python = ' pyproject.toml
   # Example: python = "^3.10"
   ```

2. **If mismatch and conda available**:
   ```bash
   conda create -n patch-bundler-validation python=3.10 -y
   conda activate patch-bundler-validation
   ```

3. **Install and validate**:
   ```bash
   poetry install
   make tests
   ```

**Benefits of conda**:
- Isolates Python version from system Python
- Creates clean environment for validation
- Ensures consistent results across machines

## Best Practices

1. **Start small**: Test with 2-3 branches first
2. **Clean state**: Ensure `git status` is clean before starting
3. **Review validation output**: Check test results, type errors, lint warnings
4. **Review escalations**: Manually review all ESCALATED branches
5. **Review merge commits**: Run `git log --oneline --graph` to see what was bundled
6. **Resume capability**: Re-run skill to continue if interrupted (skips COMPLETED)
7. **poetry.lock conflicts**: Always accept theirs, never manually merge

## Troubleshooting

### "Python version mismatch"
- Agent will use conda to create environment with correct version
- Or manually: `conda create -n myenv python=3.10`
- Or: `poetry env use python3.10`

### "poetry install fails"
- May indicate incompatible dependency versions
- Check if poetry.lock was properly resolved
- Consider escalating the problematic branch

### "Tests pass individually but fail together"
- May indicate conflicting dependency versions
- Review which branches were merged
- Consider bisecting to find problematic merge

### "Type checking fails"
- Type errors are logged but don't block validation
- Review output to see if errors are new or pre-existing
- Fix if simple, otherwise note for later

### "Linting fails"
- Formatting issues are logged but don't block validation
- Often auto-fixable with `make format` or `poetry run black .`
- Can be addressed in follow-up PR

## Differences from Yarn Variant

| Aspect | Yarn Variant | Poetry Variant |
|--------|--------------|----------------|
| **Validation timing** | After each merge | After all merges |
| **Validation scope** | Build only | Tests + Type + Lint |
| **Python version** | N/A | Conda management |
| **Lock file** | yarn.lock | poetry.lock |
| **Required check** | `yarn build` | `make tests` |
| **Optional checks** | None | mypy, ruff, pre-commit |

## Files

```
~/.claude/skills/patch-bundler-poetry/
├── SKILL.md                       # Main skill entry point
├── base-merge-logic.md            # Core workflow (shared)
├── package-managers/
│   ├── poetry.md                  # Poetry validation strategy
│   └── yarn.md                    # (reference)
└── README.md                      # This file
```

## Version Control

This skill is designed for personal use across repositories:
- Lives in `~/.claude/skills/` (not in project `.git`)
- Available across all your projects
- Can be synced via dotfiles repo

## Example Session

```bash
$ cd ../api-security-updates
$ /patch-bundler-poetry dependabot-branches.md

Merging 7 branches...
✅ Merged dependabot/pip/fastapi-0.121.0
✅ Merged dependabot/pip/uvicorn-0.35.0
... (5 more)

Running comprehensive validation...
✅ Python 3.10 (matches ^3.10)
✅ poetry install succeeded
✅ Tests: 127 passed in 4.23s
⚠️  mypy: 3 type errors (non-blocking)
⚠️  ruff: 2 formatting issues (non-blocking)

🎉 All 7 branches bundled successfully!
   Required checks: ✅ PASSED
   Optional checks: ⚠️  5 warnings
```
