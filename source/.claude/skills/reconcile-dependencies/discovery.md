# Branch Discovery (GitHub CLI)

Replaces the hand-authored `dependabot-branches.md` manifest. The agent discovers
in-scope branches itself, then generates the manifest as a progress-tracking
artifact — never as something the user types up.

## Step 1: Discover Open Dependabot PRs

```bash
gh pr list --label dependencies --json number,headRefName,title --limit 100
```

- Only branches with an **open PR** are in scope. Stale `dependabot/*` branches
  with no PR (closed, superseded, or manually abandoned) are excluded —
  don't fall back to `git branch -r | grep dependabot`.
- If `gh pr list` returns branches that don't match any pattern in
  [platform-detector.md](platform-detector.md), ESCALATE those specifically —
  do not guess a package manager.

## Step 2: Cross-Check Against Open Dependabot Alerts

```bash
gh api repos/{owner}/{repo}/dependabot/alerts --paginate -f state=open -f per_page=100 \
  --jq '.[] | [.number, .security_advisory.severity, .dependency.package.ecosystem, .dependency.package.name] | @tsv'
```

Some open alerts have **no corresponding open PR** — this happens when Dependabot
can't auto-generate a fix (transitive dependency, no compatible version, alert
grouped/superseded). These are explicitly **out of scope for this skill**.

- Do not attempt to hand-fix these.
- Report them in the final summary as "Alerts with no auto-fix PR — route to
  `reconcile-vulnerabilities`" so they aren't silently dropped.
- Match by package name (case-insensitive) against the PR titles from Step 1 to
  determine which alerts already have a PR in flight.

## Step 3: Classify by Risk Tier

For each discovered PR, classify using the PR title (Dependabot encodes the
version bump in the title, e.g. "bump X from 1.2.3 to 1.2.4"):

- **Patch/minor bump, single dependency, no alert severity above medium** →
  standard tier, process normally.
- **Major version bump** (X.0.0 → Y.0.0) → still process, but flag for closer
  review in the summary; do not silently treat like a patch bump.
- **Grouped PR** (title says "bump the X group across N directories/manifests
  with M updates") → treat as one unit; if any member of the group is a major
  bump, flag the whole group.

This classification does not change the merge mechanics (still rebase-before-merge,
see [base-merge-logic.md](base-merge-logic.md)) — it only changes what gets
called out in the summary so majors don't get rubber-stamped alongside patches.

## Step 4: Generate the Tracking Manifest

Write a manifest (e.g. `dependabot-branches.md`, untracked, matching
[dependabot-branches.example.md](dependabot-branches.example.md) format) from
the discovered branches, seeded as `PENDING`. This file is:

- Generated fresh each run (or resumed if it already exists with progress from
  an interrupted run — see State Preservation in base-merge-logic.md)
- Never committed
- The only source of truth for what's left to process

## Why Discovery Instead of a Manual List

- The manual manifest required the user to run `git branch -r | grep dependabot`
  or check the GitHub UI and hand-transcribe branch names — pure toil for
  information `gh` already exposes structurally.
- Cross-checking alerts against PRs surfaces gaps (alerts with no fix available)
  that a manually authored branch list would never reveal, since the user only
  sees what they thought to list.
