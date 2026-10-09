# Claude launchers: identity isolation

Scope: `chartpro-isolation` (`~/scopes/chartpro-isolation.json`). The plan, evidence and proof
live in the Claude config repo's branch `add/chartpro-isolation`, at
`.agent/plans/identity-and-role-limits.md`. Roles were cut; this branch carries only the
launcher.

This branch is stacked on PR #41 (`chore/claude-lge-model`), which edits the same lines.
Rebase onto `main` once #41 merges.

## Done

- `claude-lge` passes `--settings ~/.claude/settings.lge-identity.json`, refuses to start
  without it, and calls `command claude`; `alias claude='claude-lge'`;
  `claude-chartpro` calls `command claude`. README documents them. Checked with a stubbed
  `claude` binary in zsh.

## Merge order

The config PR merges and its `install.sh` runs first: until the identity file is in
`~/.claude/`, plain `claude` refuses to start.

No protected path is named in this public repo.
