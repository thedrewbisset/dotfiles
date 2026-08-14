# Issue Filing

This skill only files issues — it never attempts the remediation itself. A
raw-SQL-injection finding or a missing Dockerfile `USER` directive requires
judgment a skill shouldn't apply unsupervised; the deliverable is a
well-described issue a person (or a future, explicitly-scoped task) can act
on.

## Step 1: Dedup Against Existing Issues

Before filing anything, search for issues already covering this theme:

```bash
gh issue list --search "in:title <rule-id-or-package>" --state all --json number,title,state
```

- If an **open** issue already matches, don't file a duplicate — instead
  report it and, if the group has grown (more findings than the issue
  currently lists), note that as a suggested update rather than a new issue.
- If a **closed** issue matches and the findings are still open per the
  scanner, that means the fix didn't fully land or regressed — flag this
  explicitly to the user rather than silently reopening or refiling.
- Match on the theme identifier from grouping.md (rule id or package name),
  not on exact title string, since titles include a count that changes run
  to run.

## Step 2: Dry-Run Preview (Required Before First Filing)

Given a repo can have dozens of pre-existing findings, the first run against
any repo produces a real, visible batch of new issues. Before calling `gh
issue create` for the first time in a session:

1. Print every group that would become an issue: title, severity, finding
   count, whether it's new or would update an existing issue
2. Ask the user to confirm before proceeding — do not file automatically on
   first run
3. On subsequent runs (same session, already confirmed), continue filing new
   groups without re-asking, unless the group set changed significantly
   (e.g. a new severity tier of finding appeared that wasn't in the preview)

This mirrors the "check with the user before actions with real blast radius"
principle — issues are visible to the whole team and persist, so a batch of
20 shouldn't appear without the user having seen the list first.

## Step 3: File the Issue

```bash
gh issue create --title "<theme title from grouping.md>" --label security --body "$(cat <<'EOF'
## Findings

<one line per finding: file/path, severity, rule id or advisory link>

## Source

<Semgrep / CodeQL / Dependabot, whichever produced these>

## Scope

This issue tracks remediation only — no fix is proposed here. <Add any
cross-references, e.g. related packages sharing a root cause per
grouping.md.>
EOF
)"
```

- Use a `security` label (create it via `gh label create` if it doesn't
  exist) so these are filterable separately from `dependencies`,
  `enhancement`, etc.
- Include direct advisory links (`security_advisory.references` for
  Dependabot) and the exact rule id for code-scanning, so whoever picks up
  the issue doesn't need to re-run discovery themselves.
- For per-finding issues (secrets — see grouping.md "What Doesn't Get
  Grouped"), title as `Secret detected: <type> in <file>` and flag as
  higher urgency in the body — do not include the actual secret value in the
  issue body, only its location and type.

## Step 4: Report

After filing, report: how many issues filed (new), how many groups matched
existing open issues (skipped, with links), and any closed-issue mismatches
flagged in Step 1. This is the same "no silent truncation" principle as
elsewhere — every discovered finding should be accounted for in the summary,
either as filed, already-tracked, or explicitly deferred.
