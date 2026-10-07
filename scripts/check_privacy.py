#!/usr/bin/env python3
"""Privacy gate for this repository.

This repo is public, and so is its history. What is already published cannot be
unpublished, so this scans **the diff**, not the past. Findings nobody can act on make a check
unsatisfiable, and an unsatisfiable check is one people learn to bypass with
--no-verify, which costs the protection it was meant to add.

    scripts/check_privacy.py                          # working tree
    scripts/check_privacy.py --range="HEAD --not --remotes"   # + unpushed commits

Exit 0 when clean, 1 on a blocking finding. Warnings never affect the exit code.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import privacy_gate as pg  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent


def main(argv: list[str]) -> int:
    flags = {a for a in argv[1:] if a.startswith("--")}
    rev_args = None
    for f in list(flags):
        if f.startswith("--range="):
            rev_args = f[len("--range="):].split()
            flags.discard(f)
    allow_missing = "--allow-missing-denylist" in flags
    flags.discard("--allow-missing-denylist")
    if flags:
        print(f"unknown option(s): {' '.join(sorted(flags))}", file=sys.stderr)
        return 2

    findings, notices = pg.check_privacy(REPO_ROOT, allow_missing_denylist=allow_missing)
    if rev_args:
        hist, hnotes = pg.check_history(REPO_ROOT, rev_args)
        findings += hist
        notices += hnotes

    for n in notices:
        print(f"NOTICE: {n}", file=sys.stderr)
    for line in pg.render_warnings(pg.check_identity(REPO_ROOT), REPO_ROOT):
        print(line, file=sys.stderr)

    if findings:
        print(f"\n{len(findings)} blocking finding(s):", file=sys.stderr)
        for f in findings:
            print(f"  {f}", file=sys.stderr)
        print("\ncheck_privacy: FAILED", file=sys.stderr)
        return 1

    print("check_privacy: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
