# Claude launchers: identity limits and roles

Scope: `chartpro-isolation` (`~/scopes/chartpro-isolation.json`). The full plan, facts and
proof steps live in the Claude config repo's branch `add/chartpro-isolation`, at
`.agent/plans/identity-and-role-limits.md`. This branch carries only the launcher half:
step 4 there, and it starts after that plan's proof (step 3) passes.

This branch is stacked on PR #41 (`chore/claude-lge-model`), which edits the same lines.
Rebase onto `main` once #41 merges.

## What changes here

- `claude-lge [--role review|admin]` adds the identity file plus the role file with
  `--settings`, refuses to start if either is missing, calls `command claude`, and logs a
  reason for each `admin` launch.
- `alias claude='claude-lge'`: plain `claude` runs with the default role.
- `claude-chartpro` calls `command claude` (the alias would otherwise recurse).
- README: document the launchers, the roles and the escalation log.

No protected path is named in this public repo; the files that name them are installed from
the config repo into `~/.claude/`.
