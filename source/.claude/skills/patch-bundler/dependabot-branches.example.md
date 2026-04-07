# Dependabot Security Update Branches

This file tracks the status of dependabot branches being merged onto the consolidated security updates branch.

**Target Branch**: chore/security-updates (or your branch name)

## Status Values
- **PENDING**: Not yet processed
- **COMPLETED**: Successfully merged and validated
- **ESCALATED**: Requires manual review and resolution

---

## Single Repository Format

Use this format for standard repositories with one package.json/pyproject.toml at the root:

```markdown
## Branches

- dependabot/npm_and_yarn/typescript-5.0.0: PENDING
- dependabot/npm_and_yarn/react-18.2.0: PENDING
- dependabot/npm_and_yarn/eslint-8.40.0: PENDING
```

---

## Monorepo Format

Use this format for monorepos where dependabot creates branches with directory prefixes:

**Branch naming pattern:** `dependabot/pip/{directory-name}/{package-version}`

### How to Structure for Monorepos

Group branches by directory using section headers (## Directory Name):

```markdown
## lambda-1
- dependabot/pip/lambda-1/boto3-1.42.39: PENDING
- dependabot/pip/lambda-1/pydantic-2.9.2: PENDING

## lambda-2
- dependabot/pip/lambda-2/boto3-1.42.39: PENDING
- dependabot/pip/lambda-2/requests-2.32.5: PENDING

## shared-utils
- dependabot/pip/shared-utils/pytest-8.0.0: PENDING
```

### Monorepo Workflow

1. **Create root manifest** (this file) at repository root with all branches grouped by directory
2. **Agent distributes**: Claude will parse sections and create per-directory tracking files
3. **Agent processes**: Runs patch-bundler in each directory independently
4. **Agent consolidates**: Updates root manifest with results

### Why Section Headers?

- **Clarity**: Easy to see which branches affect which directories
- **Organization**: Natural grouping matches your repo structure
- **Automation**: Agent can parse and distribute automatically
- **Audit trail**: Clear record of what was processed per directory

---

## Finding Branches to Include

### From GitHub UI (Recommended)
Check open dependabot PRs - only include branches with active PRs to avoid stale branches.

### From Git (All Branches)
```bash
# List all dependabot branches
git branch -r | grep dependabot

# For monorepos, group by directory
git branch -r | grep "dependabot/pip" | sort

# For npm projects
git branch -r | grep "dependabot/npm_and_yarn" | sort
```

### Using GitHub CLI (Cleanest)
```bash
# List only branches with OPEN PRs
gh pr list --label dependencies --json headRefName --jq '.[].headRefName'
```

**Tip**: Only include branches with open PRs to avoid processing stale branches that were never cleaned up.

---

## Example: Complete Single Repo

```markdown
# Dependabot Security Update Branches

## Branches

- dependabot/npm_and_yarn/security-updates-160c87e243: PENDING
- dependabot/npm_and_yarn/typescript-5.0.0: PENDING
- dependabot/npm_and_yarn/react-18.2.0: PENDING
- dependabot/github_actions/actions/checkout-6.0.2: PENDING
```

---

## Example: Complete Monorepo

```markdown
# Dependabot Security Update Branches - Lambda Functions Monorepo

## summarize-lambda
- dependabot/pip/summarize-lambda/boto3-1.42.39: PENDING
- dependabot/pip/summarize-lambda/pydantic-2.9.2: PENDING
- dependabot/pip/summarize-lambda/numpy-2.3.5: PENDING

## mdm-scoring-lambda
- dependabot/pip/mdm-scoring-lambda/boto3-1.42.39: PENDING
- dependabot/pip/mdm-scoring-lambda/requests-2.32.5: PENDING

## deepgram-transcription-lambda
- dependabot/pip/deepgram-transcription-lambda/deepgram-sdk-5.3.2: PENDING
- dependabot/pip/deepgram-transcription-lambda/boto3-1.42.39: PENDING

## GitHub Actions (applies to all)
- dependabot/github_actions/actions/checkout-6.0.2: PENDING
```

**Note**: GitHub Actions branches affect the repository globally, not specific directories.
