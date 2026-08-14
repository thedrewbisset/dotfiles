# Theme-Based Grouping

Per-finding issues don't scale — a repo can have dozens of code-scanning
alerts that are really one systemic problem (e.g. every workflow file using a
mutable action tag). File **one issue per theme**, not one per alert.

## Grouping Key: Code-Scanning Alerts

Group by `rule.id` (tool-independent; stable across Semgrep/CodeQL/etc.).

- All alerts sharing a `rule.id` → one group, one issue
- Within the issue, list every affected file/line as a checklist so the
  group's completeness is trackable (e.g. "12 of 15 files fixed")
- If a single `rule.id` spans wildly different severities in practice (rare,
  but possible if the tool changed scoring over time), keep them in one group
  anyway — the rule is the theme, not the score

**Example**: 15 open alerts with `rule.id: yaml.github-actions.security.github-actions-mutable-action-tag`
across `.github/workflows/*.yml` → **one issue**: "Pin GitHub Actions to
immutable SHA refs across workflows", with all 15 files listed.

## Grouping Key: Dependabot Alerts With No PR

Group by **package name**, not by individual advisory ID — a single package
can have several open advisories (this repo's `cryptography` package has 5
right now, across 3 distinct CVEs). One issue per package, listing every
advisory affecting it, is far more actionable than 5 separate issues that all
resolve the same way (bump the package).

**Exception**: if two different *packages* are both blocked on the same root
cause (e.g. both pinned by a shared parent dependency), note the relationship
in each issue body but still file separately — don't merge across packages
just because the fix might be related.

## What Doesn't Get Grouped

- **Secrets detected in code** (`detected-jwt-token`, `detected-aws-access-key-id-value`,
  etc.): file individually, one issue per finding. These are not a "theme" to
  batch — each one is a distinct potential exposure that needs its own
  triage and remediation owner, and batching risks one slipping through as
  "already covered" when it wasn't.
- **Findings with only one occurrence**: a group of one is just an issue;
  don't create an empty wrapper.

## Naming a Group

Issue title format: `<action-oriented summary> (<rule-id or package>, N findings)`

Examples:
- "Pin GitHub Actions to immutable SHA refs (github-actions-mutable-action-tag, 15 findings)"
- "Resolve cryptography advisories (5 open, includes 2 high-severity)"

This makes the theme and scale legible from the issue list view without
opening each one.

## Severity Roll-Up

When a group spans multiple severities, the issue's overall severity label is
the **highest** severity present in the group — don't average or default to
the most common. A group with 14 warnings and 1 error is an error-priority
issue; burying the one error inside a warning-labeled batch defeats the point
of surfacing it.
