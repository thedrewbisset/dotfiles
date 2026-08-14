# Reconcile Vulnerabilities

Works down the full backlog of security findings a repo's scanning tools have
already caught — not just what Dependabot could generate an auto-fix PR for.
Groups findings by theme and files tracking issues. Separately, reviews the
existing issue backlog for findings covered by an approved compensating
control and proposes dismissing them. Never writes remediation code, and
never dismisses anything the user hasn't explicitly approved a justification
for.

## Why This Exists

`reconcile-dependencies` bundles Dependabot PRs, but that only covers findings
Dependabot could mechanically patch. Two gaps remain:

- **Dependabot alerts with no PR** — transitive dependencies, no compatible
  version yet, grouped/superseded alerts
- **Code-scanning findings** (Semgrep, CodeQL, etc.) — SQL injection, missing
  Dockerfile hardening, secrets in test fixtures, mutable Action tags — none
  of these are dependency bumps, so Dependabot never touches them

This skill exists so those aren't invisible just because they can't be
merged.

## Scope Boundary

| | reconcile-dependencies | reconcile-vulnerabilities |
|---|---|---|
| Input | Open Dependabot PRs | Alerts w/o PR + code-scanning alerts |
| Action | Merges branches | Files grouped issues |
| Writes code | Yes (lockfile regen, merge commits) | No |
| Output | Consolidated branch + CI validation | GitHub issues |

Run `reconcile-dependencies` first if you also want the mergeable PRs bundled
in the same pass — the two are independent and can run in either order.

## Quick Start

```bash
/reconcile-vulnerabilities
```

1. Reports raw counts (alerts without PR by severity; code-scanning alerts by
   severity and tool) before doing anything else.
2. Groups findings by theme (see [grouping.md](grouping.md)).
3. Shows a dry-run preview of every issue it intends to file — nothing is
   filed until you confirm, since a repo's first run can surface dozens of
   pre-existing findings.
4. Files issues, skipping anything already tracked by an open issue.

## Risk Acceptance (`--risk-review`)

```bash
/reconcile-vulnerabilities --risk-review
```

Separate mode. Reviews the *existing* open-issue backlog against
`SECURITY_ACCEPTED_RISKS.md` and proposes dismissing findings covered by an
**approved** compensating control. Never runs in place of filing — a finding
is always filed first (default mode), and only becomes a dismissal candidate
later, once a human has had the chance to see it as an issue.

The skill may draft candidate criteria entries (`Status: proposed`) when it
notices something in the code that looks like a compensating control, but a
`proposed` entry can never back a dismissal — only entries you've reviewed and
flipped to `Status: approved` count. See [risk-acceptance.md](risk-acceptance.md)
for the full criteria-doc format and the native GitHub dismissal mechanics
(`dismissed_reason` on Dependabot/code-scanning alerts) this uses instead of
just closing the tracking issue.

Dry-run preview gates *every* `--risk-review` run, not just the first —
dismissal is harder to walk back than an extra filed issue.

## Files

```
reconcile-vulnerabilities/
├── SKILL.md             # Entry point
├── README.md            # This file
├── discovery.md         # gh-cli queries for alerts + code-scanning findings
├── grouping.md          # Theme-based grouping rules
├── issue-filing.md      # Dedup, dry-run preview, gh issue create
└── risk-acceptance.md   # Criteria doc format, dismissal matching, native GH dismissal
```

## Version Control

Personal skill, lives in `~/.claude/skills/` via symlink to this dotfiles
repo — available across all projects.
