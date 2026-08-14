# Risk Acceptance

Reviews the **existing, already-filed** issue backlog from [issue-filing.md](issue-filing.md)
and proposes dismissing findings that are covered by a documented compensating
control. This never runs in place of filing — every new finding still gets an
issue first, unconditionally (see discovery.md / grouping.md / issue-filing.md).
Risk acceptance only operates downstream, on findings a human has already had
the chance to see as a filed issue.

**This skill never decides that a compensating control exists.** It only
checks whether a finding matches a control the user has already approved in
writing. If no approved entry matches, the finding stays open — the skill
does not infer, extrapolate, or invent a justification from reading the code.

## The Criteria Doc

Compensating controls live in `SECURITY_ACCEPTED_RISKS.md` at the repo root
(create if absent). Each entry is a discrete, human-approved fact:

```markdown
## <short id>

**Status**: approved | proposed
**Applies to**: <rule id, package name, or specific alert/CVE pattern>
**Compensating control**: <the actual fact — what mitigates this>
**Approved by**: <name>, <date>
**Review by**: <date, if time-boxed — e.g. "revisit if package X is ever exposed publicly">
```

### Two-Phase Entry Lifecycle

1. **Proposed**: the skill may draft a candidate entry when it observes something
   in the codebase that looks like it could be a compensating control (e.g. "this
   route requires `Depends(get_current_user)` on every handler"). This is written
   with `Status: proposed` and presented to the user — it is a draft, not usable
   for dismissal yet.
2. **Approved**: the user reviews and edits the entry, then changes `Status` to
   `approved` (or asks the skill to do so after explicit confirmation). Only
   `approved` entries can back a dismissal. Never treat a `proposed` entry as
   sufficient justification, even if it looks obviously correct — approval is
   the gate, not the skill's own confidence.

## Matching Findings to Criteria

For each open issue filed by `issue-filing.md`:

1. Extract its theme identifier (rule id or package name, per grouping.md)
2. Check `SECURITY_ACCEPTED_RISKS.md` for an `approved` entry whose
   `Applies to` matches
3. If matched: this is a **dismissal candidate**
4. If no match: leave the issue open, do nothing — do not propose new criteria
   here inline; drafting new criteria is a separate, explicit step (see below)

## Dry-Run Preview (Required Before Any Dismissal)

Before dismissing anything, show the user:

- Every dismissal candidate: issue link, matched criteria entry, which
  underlying alert(s) would be dismissed and with which `dismissed_reason`
- Every open issue with **no** matching criteria (so absence isn't silent —
  the user sees what stays open and why)

Nothing is dismissed until the user confirms this preview, every run — unlike
issue-filing's dry-run (which only gates the first run of a session), risk
acceptance gates **every** run, because dismissal is harder to walk back
cleanly than filing an extra issue is.

## Executing a Confirmed Dismissal

Two systems need updating, in this order:

### 1. Dismiss the underlying alert natively

**Dependabot alerts:**
```bash
gh api repos/{owner}/{repo}/dependabot/alerts/{alert_number} -X PATCH \
  -f state=dismissed \
  -f dismissed_reason=tolerable_risk \
  -f dismissed_comment="<link to SECURITY_ACCEPTED_RISKS.md entry>"
```
Valid `dismissed_reason` values (GitHub-enforced enum — do not invent others):
`fix_started`, `inaccurate`, `no_bandwidth`, `not_used`, `tolerable_risk`.
For compensating-control-based acceptance, `tolerable_risk` is the correct
reason in the overwhelming majority of cases; `inaccurate`/`not_used` apply
only if the criteria entry itself asserts the finding doesn't apply at all
(false positive), which is a different claim from "risk is acceptable."

**Code-scanning alerts:**
```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{alert_number} -X PATCH \
  -f state=dismissed \
  -f dismissed_reason="won't fix" \
  -f dismissed_comment="<link to SECURITY_ACCEPTED_RISKS.md entry>"
```
Valid `dismissed_reason` values: `false positive`, `won't fix`, `used in tests`.
Same distinction applies: `won't fix` for accepted risk, `false positive` only
if the criteria entry claims the finding doesn't actually apply, `used in
tests` only for genuine test-fixture matches (see grouping.md's secrets
exception — a "used in tests" dismissal on a real secret is still a leaked
credential; rotate it, don't just dismiss the alert).

### 2. Close the tracking issue

```bash
gh issue close {issue_number} --comment "Risk accepted per SECURITY_ACCEPTED_RISKS.md#<entry-id>. Underlying alert(s) dismissed: <links>."
```

Always dismiss the alert **before** closing the issue, not after — if the
alert dismissal call fails, the issue should still show as open and
unresolved rather than closed with a dangling alert still active.

## Re-Opening on Drift

If a dismissed alert's underlying finding changes (GitHub re-opens
auto-dismissed alerts on new severity data in some cases, or a criteria
entry's `Review by` date passes), report this explicitly rather than
re-dismissing automatically. A control that was valid six months ago may not
be valid now — time-boxed entries exist specifically so this gets re-examined
by a person, not re-approved by default.

## Reporting

After a risk-acceptance pass, report: dismissed (with criteria entry cited for
each), left open with no matching criteria, and any criteria entries proposed
this run but not yet approved (carried forward for the user to review later).
