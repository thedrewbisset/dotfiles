---
name: patch-bundler-poetry
description: Bundle multiple dependabot branches with comprehensive validation (Poetry package manager)
allowed-tools: Read, Grep, Bash, Edit
disable-model-invocation: true
argument-hint: "[path-to-branches.md]"
---

# Patch Bundler Agent - Poetry Variant

This skill bundles multiple dependabot security update branches into a single consolidated branch using git merge --no-ff, creating clear merge commits that show what was integrated and enabling GitHub to auto-close dependabot PRs.

## Task

Bundle dependabot branches listed in: ${1:-dependabot-branches.md}

Target branch: Current checked-out branch (should be `chore/security-updates` or similar)

## Workflow

Follow the base merge logic defined in [base-merge-logic.md](base-merge-logic.md) using Poetry-specific commands from [package-managers/poetry.md](package-managers/poetry.md).

## Core Principles

1. **Safety First**: Save commit SHA before each merge for rollback capability
2. **Incremental Progress**: Update tracking file after each branch (COMPLETED or ESCALATED)
3. **Lock File Regeneration**: ALWAYS run `poetry lock --no-update` after all merges
4. **Comprehensive Validation**: Run tests, type checking, and linting after lock regeneration
5. **Clear Audit Trail**: Merge commits explicitly show what was integrated and when
6. **Non-Blocking**: Continue to next branch on escalation

## Why Merge --no-ff vs Rebase or Cherry-pick?

**Merge --no-ff** is the recommended approach because it:
- ✅ Preserves commit SHAs → GitHub auto-closes dependabot PRs when merged
- ✅ Creates explicit merge commits showing what was bundled
- ✅ Clear audit trail - easy to see all security updates in git log
- ✅ Each branch integration is a distinct, visible event
- ⚠️ More verbose history with merge commits (but that's the benefit!)

Alternative approaches and trade-offs:
- **Rebase**: Linear history but security commits buried chronologically
- **Cherry-pick**: Cleanest (all security commits at top) but requires manual PR closing

## Comprehensive Validation

After all merges complete, the agent will run comprehensive validation:

### Step 0: Regenerate Lock File (CRITICAL!)
**REQUIRED**: Run `poetry lock --no-update` to regenerate poetry.lock

**Why this is critical:**
- Accepting "theirs" during conflicts may leave lock file inconsistent
- Manual edits to `pyproject.toml` require lock regeneration
- Multiple merges may accumulate inconsistencies
- Ensures lock file is in sync with `pyproject.toml`
- Prevents CI failures from inconsistent dependencies

**This step is NEW and addresses the CI failure you experienced!**

### Step 1-5: Standard Validation

#### Required (must pass)
1. **Lock File Regenerated**: `poetry lock --no-update` succeeded (step 0)
2. **Python Version Check**: Ensure Python version matches `pyproject.toml` (use conda if needed)
3. **Install Dependencies**: `poetry install` or `./poetry install`
4. **Run Tests**: `make tests` or `poetry run pytest`

If any required check fails, validation fails and the issue is escalated.

#### Recommended (log but don't fail)
5. **Type Checking**: `make mypy` or `poetry run mypy app/`
6. **Linting/Formatting**: `make format` or `poetry run ruff check .`
7. **Lock File Check**: `poetry lock --check`

Recommended checks log warnings but don't fail validation. This is because:
- Type errors are often pre-existing
- Formatting issues can be auto-fixed
- Lock file was already regenerated in step 0

### Validation Strategy

The agent will:
1. **Regenerate lock file FIRST** (prevents CI failures!)
2. Check which tools are available (Makefile targets, poetry commands)
3. Use Makefile targets when available (e.g., `make tests`, `make mypy`)
4. Fall back to direct poetry commands if Makefile doesn't exist
5. Run minimum validation (lock + tests) if advanced tools aren't configured
6. Provide clear summary of what passed/failed/warned

## Python Version Management with Conda

If the project requires a specific Python version and conda is available:

```bash
# Extract version from pyproject.toml
# Create conda environment
conda create -n patch-bundler-validation python=3.10 -y
conda activate patch-bundler-validation
poetry lock --no-update
poetry install
```

The agent will automatically detect Python version mismatches and use conda if available.

## Output Format

Update the tracking file with status and exception details:

```
- dependabot/pip/package-name-1.2.3: COMPLETED
- dependabot/pip/another-package-4.5.6: ESCALATED
  - Exception Files: pyproject.toml, app/main.py
  - Log Output:
    ```
    SolverProblemError: Cannot resolve dependencies
    ModuleNotFoundError: No module named 'old_package'
    ```
```

## Important Notes

- This skill should only be invoked manually with `/patch-bundler-poetry [branches-file]`
- The target branch must be checked out before running
- The branches file will be updated in place with progress
- All ESCALATED branches will be summarized at the end for manual review
- Use `origin/<branch-name>` when merging to ensure remote branches are used
- Merge commits will show exactly what security updates were bundled
- **CRITICAL**: `poetry lock --no-update` runs after all merges (prevents CI failures!)
- **poetry.lock conflicts**: Always accept theirs, then regenerate with `poetry lock --no-update`
- **Conda**: Used for Python version management if available
- **Tests are required**: Validation fails if tests fail
- **Type checking is optional**: Type errors logged but don't fail validation
