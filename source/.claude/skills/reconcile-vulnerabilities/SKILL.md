---
name: reconcile-vulnerabilities
description: Discover Dependabot alerts with no auto-fix PR and code-scanning findings via GitHub CLI, group them by theme, file tracking issues, and separately review the backlog for risk-acceptance dismissals (never auto-fixes code)
allowed-tools: Read, Grep, Bash
disable-model-invocation: true
argument-hint: "[--risk-review]"
---

# Reconcile Vulnerabilities

Works down the full list of open security findings available through this
repo's scanning tools — not just what Dependabot could auto-generate a PR
for. Complements `reconcile-dependencies`: that skill merges branches with a
live PR; this skill surfaces everything else (alerts with no PR, and all
code-scanning findings) as filed, trackable issues.

**This skill never writes remediation code, and never dismisses a finding on
its own judgment.** Its default output is issues, not commits or PRs. Its
optional risk-review mode only dismisses findings that match a criteria entry
the user has explicitly approved beforehand — it never infers that a
compensating control exists.

## Task

Run against the current repo.

- **Default (no args)**: discover → group → file. Covers new findings only.
- **`--risk-review`**: review the *existing* open-issue backlog for dismissal
  candidates against approved criteria. Does not discover or file anything
  new — run the default mode first if you also want new findings surfaced.

These two modes are independent and safe to run in either order or on
different schedules — risk-review only ever touches issues/alerts that
already exist.

## Workflow: Default Mode

1. **Discover findings**: follow [discovery.md](discovery.md) — pulls open
   Dependabot alerts with no matching PR, and all open code-scanning alerts
   (tool-agnostic: Semgrep, CodeQL, or whatever's configured), plus a
   secret-scanning check if enabled. Reports raw counts before proceeding.
2. **Group by theme**: follow [grouping.md](grouping.md) — code-scanning
   grouped by `rule.id`, Dependabot alerts grouped by package name, secrets
   never grouped (always filed individually).
3. **Dedup and file**: follow [issue-filing.md](issue-filing.md) — checks
   existing open/closed issues first, shows a dry-run preview before the
   first `gh issue create` call in a session, then files.
4. **Report**: filed (new), skipped (already tracked, with links), and any
   closed-issue/still-open mismatches.

## Workflow: `--risk-review` Mode

1. **Load criteria**: read `SECURITY_ACCEPTED_RISKS.md` at repo root (create a
   stub if absent, with no entries — never seed it with invented entries)
2. **Match backlog to criteria**: follow [risk-acceptance.md](risk-acceptance.md)
   — only `approved` entries can back a dismissal; `proposed` entries are
   drafts awaiting the user, never usable yet
3. **Dry-run preview**: show every dismissal candidate, its matched entry, and
   every open issue with no match — required before every risk-review run,
   not just the first
4. **Dismiss on confirmation**: native alert dismissal first (see
   risk-acceptance.md's `dismissed_reason` enum tables for Dependabot vs.
   code-scanning), then close the tracking issue — in that order
5. **Report**: dismissed (with citation), left open, and any criteria entries
   proposed but not yet approved

## Core Principles

1. **Surface, don't fix**: every default-mode action ends at "an issue
   exists," never at a code change
2. **Theme over volume**: one issue per rule/package, not per finding —
   except secrets, which are always individual
3. **No silent counts**: raw findings are reported before grouping, so the
   user sees scale before any filing happens
4. **Dedup first**: never file a duplicate of an existing open issue; flag
   (don't silently reopen) closed issues whose findings are still open
5. **Confirm before first batch**: dry-run preview required before the first
   `gh issue create` of a session, since a repo's first run can surface dozens
   of pre-existing findings at once
6. **Risk acceptance is never inferred**: the skill only dismisses a finding
   if it matches a criteria entry the user already approved in writing —
   approval is the gate, not the skill's confidence in a pattern it noticed
7. **Filing and dismissal never trade off against each other**: a finding
   always gets filed first; dismissal only ever happens later, on the
   already-filed issue, never in place of filing it

## Important Notes

- Should only be invoked manually
- Requires `gh` authenticated with access to Dependabot alerts and
  code-scanning alerts (`security_events` scope for private repos), plus
  write access for `--risk-review`'s dismissal calls
- Tool-agnostic by design — don't hardcode "Semgrep" or "CodeQL" in logic,
  read `.tool.name` per finding
- Secret values are never included in issue bodies, only location and type
- Complements, does not replace, `reconcile-dependencies` — run that first if
  you also want the mergeable PRs bundled
- `--risk-review` dry-run gates *every* run, not just the first — dismissal is
  harder to walk back than an extra filed issue
