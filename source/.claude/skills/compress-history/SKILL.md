---
name: compress-history
description: Analyze branch commit history to identify safe fixup/squash candidates for pre-release history compression
allowed-tools: Bash, Read, Write, Agent, Workflow
argument-hint: ""
---

# Compress History

Analyzes the commit history of the current branch (from the point it diverged from `main`) and produces a side-by-side view of the original log and a proposed interactive rebase plan with squash/fixup actions.

## Task

Run the `compress-history` workflow:

```
Workflow({ name: "compress-history" })
```

The workflow will:
1. Collect all commits on this branch since diverging from `main`
2. Build a file-overlap graph between commits
3. Score each pair for squash candidacy (proximity, footprint size, overlap)
4. Present two panes: original log vs. proposed rebase plan
5. Flag any risky matches for interactive discussion before recommending them

Do not attempt to rebase or modify history — this skill is analysis only.
