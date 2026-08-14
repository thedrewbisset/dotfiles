# Finding Discovery (GitHub CLI)

This skill covers security findings that `reconcile-dependencies` explicitly
does **not** handle: Dependabot alerts with no auto-fix PR, and code-scanning
findings of any kind. Nothing here is a dependency bump — every finding
surfaced by this step requires either a manual code change or a policy
decision, so the skill's job is to surface and organize, never to auto-fix.

## Step 1: Open Dependabot Alerts With No Matching PR

```bash
gh api repos/{owner}/{repo}/dependabot/alerts --paginate -f state=open -f per_page=100 \
  --jq '.[] | [.number, .security_advisory.severity, .dependency.package.ecosystem, .dependency.package.name, .security_advisory.summary] | @tsv'
```

Cross-check against open PRs:

```bash
gh pr list --label dependencies --json headRefName,title
```

An alert is "no auto-fix PR" if no open PR title references its package name
(case-insensitive substring match against the PR title's package segment).
This mirrors the check in `reconcile-dependencies/discovery.md` — if that
skill already ran and reported this list in its summary, reuse it rather than
re-querying.

**Why these have no PR**: usually a transitive dependency Dependabot can't
patch directly, no compatible version exists yet, or the alert was
grouped/superseded. Don't assume malice or neglect — just surface it.

## Step 2: Open Code-Scanning Alerts

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts --paginate -f state=open -f per_page=100 \
  --jq '.[] | [.number, .rule.severity, .rule.id, .most_recent_instance.location.path, .tool.name] | @tsv'
```

**Tool-agnostic**: the same endpoint returns findings from whichever scanners
are configured — Semgrep OSS, CodeQL, or others. Read `.tool.name` per finding
rather than assuming which tool produced it; a repo may run more than one
scanner, or switch scanners over time. Don't hardcode a specific tool name in
downstream logic (grouping, filing) — group by `rule.id` and severity, which
are tool-independent.

## Step 3: Secret Scanning (If Enabled)

```bash
gh api repos/{owner}/{repo}/secret-scanning/alerts -f state=open 2>&1
```

If this returns `404 Secret scanning is disabled on this repository`, that's
expected on repos without the feature enabled — report it as "not enabled",
not as "zero findings" (those mean different things: one is an unmonitored
gap, the other is a clean scan).

## Step 4: Snapshot Counts

Before grouping, report raw counts to the user: total alerts-without-PR by
severity, total code-scanning alerts by severity and by tool. This matters
because a repo can easily have dozens of pre-existing findings on first run —
the user should see the scale before the skill proposes how to group and file
them, not be surprised by a batch of new issues appearing.
