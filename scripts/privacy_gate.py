#!/usr/bin/env python3
"""Shared privacy gate.

CANONICAL COPY: the `exponential-claude-config` repository, at
scripts/privacy_gate.py. That repo's scripts/mirror-privacy-gate mirrors it
byte-for-byte, one way only, into every other repository that uses it. If
this is not that repo, this file is a mirrored copy -- never edit it
directly. An edit made on this side is silently discarded by the next mirror
run and has no __version__ to tell you so.

It cannot be a shared dependency: one of the repositories using it is public
and must not reference the other, so importing it across them would create
the exact linkage the gate exists to prevent. __version__ and
scripts/privacy_gate.sha256, both maintained in the canonical copy, exist so
a change to this file is a diff, not a surprise: that repo's
scripts/mirror-privacy-gate --check reports drift without touching anything.

Two tiers, split by why a match matters:

  FORMAT   -- secret by shape. `ghp_` plus 36 characters is a token, always.
              Unambiguous, so it BLOCKS, and nothing switches it off: a credential
              inside a vendored dependency is a live credential regardless of who
              committed it.

  IDENTITY -- sensitive by ownership. An email, a repository link, a hostname. No
              shape distinguishes yours from a third party's copyright header, so
              precise matching is impossible and loose matching produces false
              positives at any scale. These WARN against an allowlist.
"""

from __future__ import annotations

import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

# Bump on every change to this file, and refresh scripts/privacy_gate.sha256 to
# match (see test_privacy_gate_checksum_matches_version). The mirror script
# refuses to copy a file whose version it has already copied, so a stale bump
# is a silent no-op mirror rather than a loud test failure -- the checksum test
# is what actually catches "changed the file, forgot to bump".
__version__ = "1.1.2"

SKIP_DIRS = {".git", "__pycache__", ".pytest_cache"}

SKIP_SUFFIXES = {".pyc", ".png", ".jpg", ".gif", ".ico", ".zip"}

# The two carve-outs are deliberately NOT the same set, because the two layers fail
# differently.
#
# Structural patterns match a *shape*, so synthetic test fixtures trip them by
# construction -- the gate cannot be tested without identifier-shaped strings. Tests
# are therefore exempt from structural patterns only.
#
# The deny-list matches real names. A real name in a test file is still published, so
# tests are NOT exempt from it. Only the deny-list file itself is, since its entire
# content is deny-listed terms and scanning it would report one finding per term on
# every run.
# Belt and braces for the deny-list file. Gitignored paths are already skipped (see
# ignored_paths), which covers it in any real clone; this keeps it skipped when git
# is unavailable or the tree is not a repository, since its entire content is
# deny-listed terms by design.

# The two list files are never scanned. Their entire content is identity-shaped
# strings by design -- the deny-list holds names to block, the allowlist holds names
# already cleared -- so scanning them reports one finding per entry, forever. Both
# are also unpublishable or trivial: the deny-list is gitignored, and the allowlist
# holds only things already known to be somebody else's.
PRIVACY_SKIP = ("scripts/denylist.local.txt", "scripts/allowlist.txt")

# Tests are exempt from STRUCTURAL patterns only, never from the deny-list.

STRUCTURAL_EXCLUDE = ("scripts/test_*.py",)

EMAIL_OK = re.compile(r"@(example\.(com|org|net)|noreply\b)", re.I)
# Home directories belonging to a role rather than a person. A container or CI
# path like /home/dev identifies no one, and flagging it trains people to ignore
# the check -- which is how a real finding gets waved through.

NON_IDENTIFYING_HOMES = {"dev", "root", "runner", "node", "ubuntu", "agent", "app"}

# Patterns split by WHY the match is sensitive.
#
# FORMAT patterns match things that are secret by shape -- `ghp_` plus 36 chars is a
# token, always, regardless of who wrote it. They are unambiguous, so they BLOCK, and
# nothing switches them off: a credential shipped inside a vendored dependency is a
# live credential in a public repo whether or not you typed it.
#
# IDENTITY patterns match things that are sensitive by ownership -- an email, a
# repository reference, a hostname. There is no shape that distinguishes yours from a
# third party's copyright header, so matching them at all produces false positives at
# any scale. They WARN, and an allowlist silences the ones already known to be
# somebody else's.

FORMAT_PATTERNS = [
    (
        "absolute-home-path",
        re.compile(r"/(?:Users|home)/([A-Za-z][A-Za-z0-9._-]*)"),
        "absolute home path identifies a machine and its user; write ~/ instead",
    ),
    (
        "aws-account-id",
        re.compile(r"(?<![\w.-])\d{12}(?![\w.-])"),
        "12-digit sequence looks like an AWS account ID",
    ),
    ("aws-arn", re.compile(r"arn:aws[a-z-]*:"), "AWS ARN"),
    (
        "private-ip",
        re.compile(
            r"(?<![\d.])(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))"
            r"\.\d{1,3}\.\d{1,3}(?![\d.])"
        ),
        "private IP address",
    ),
    (
        "aws-access-key",
        re.compile(r"(?<![A-Z0-9])(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA|ANVA)[0-9A-Z]{16}(?![A-Z0-9])"),
        "AWS access key id",
    ),
    (
        "github-token",
        re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
        "GitHub token",
    ),
    (
        "slack-token",
        re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
        "Slack token",
    ),
    (
        "private-key-block",
        re.compile(r"-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----"),
        "private key block",
    ),
    (
        "jwt",
        re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\."),
        "JSON web token",
    ),
    (
        "credentials-in-url",
        re.compile(r"\b[a-z][a-z0-9+.-]*://[^/@\s:]+:[^/@\s]+@"),
        "credentials embedded in a URL",
    ),
    (
        "generic-secret-assignment",
        re.compile(
            r"(?i)\b(?:api[_-]?key|secret[_-]?key|access[_-]?token|client[_-]?secret|"
            r"password|passwd)\s*[:=]\s*['\"]([^'\"\s]{12,})['\"]"
        ),
        "a secret-looking value assigned to a secret-looking name",
    ),
]

IDENTITY_PATTERNS = [
    (
        "email-address",
        re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
        "email address",
    ),
    (
        "github-owner-repo",
        re.compile(r"github\.com[:/]([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)"),
        "GitHub repository reference",
    ),
    (
        "internal-hostname",
        re.compile(
            r"\b[a-z0-9][a-z0-9-]*\.(?:internal|local|corp|intranet)(?!\.\w)", re.I
        ),
        "internal hostname",
    ),
]

@dataclass
class Finding:
    check: str
    path: str
    line: int
    message: str

    def __str__(self) -> str:
        where = f"{self.path}:{self.line}" if self.line else self.path
        return f"  [{self.check}] {where}: {self.message}"

def ignored_paths(root: Path) -> set[str]:
    """Repo-relative paths git will never publish.

    A finding in a gitignored file can never be acted on -- the file cannot be
    committed -- so the check becomes unsatisfiable, and an unsatisfiable gate is
    one people learn to bypass. `containers/.env` holds an auth token by design;
    flagging it would block every commit forever.

    History is deliberately NOT filtered this way: a file ignored today may still
    have been committed yesterday, and that is exactly what needs finding.
    """
    try:
        r = subprocess.run(
            ("git", "-C", str(root), "ls-files", "-oi",
             "--exclude-standard", "--directory"),
            capture_output=True, text=True, timeout=60,
        )
    except (OSError, subprocess.SubprocessError):
        return set()
    if r.returncode != 0:
        return set()
    return {line.rstrip("/") for line in r.stdout.splitlines() if line.strip()}

def is_ignored(rel: str, ignored: set[str]) -> bool:
    """True if rel is ignored, or sits under an ignored directory."""
    if rel in ignored:
        return True
    parts = rel.split("/")
    return any("/".join(parts[:i]) in ignored for i in range(1, len(parts)))

def iter_files(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix in SKIP_SUFFIXES:
            continue
        yield path

def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return None

def load_allowlist(root: Path) -> tuple[set[str], list[str]]:
    """Identity strings and paths already known to belong to somebody else.

    Committed, unlike the deny-list: it holds third-party repository links, upstream
    copyright addresses and config keys -- nothing sensitive, and a fresh clone should
    inherit the baseline rather than re-derive it.

    It silences WARNINGS only. Nothing here ever suppresses a format match: a
    credential inside a vendored dependency is a live credential regardless of who
    committed it.

    Lines are either a literal value, or `path: <prefix>` to cover a vendored tree.
    """
    text = read_text(root / "scripts" / "allowlist.txt")
    if text is None:
        return set(), []
    values: set[str] = set()
    paths: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("path:"):
            p = line[len("path:"):].strip().rstrip("/")
            if p:
                paths.append(p)
        else:
            values.add(line.lower())
    return values, paths

def path_allowlisted(rel: str, paths: list[str]) -> bool:
    return any(rel == p or rel.startswith(p + "/") for p in paths)

CONFIG_DIR_NAME = "exponential"

def shared_denylist_path() -> Path:
    """The deny-list location shared by every repo this gate is mirrored into.

    One file per machine rather than one per repo, so a name added for one
    repo protects the other without being copied by hand. XDG_CONFIG_HOME
    wins when set and non-empty, matching shell `${VAR:-default}` semantics.
    """
    xdg = os.environ.get("XDG_CONFIG_HOME")
    config_home = Path(xdg) if xdg else Path.home() / ".config"
    return config_home / CONFIG_DIR_NAME / "denylist.txt"

def local_denylist(root: Path) -> list[str]:
    """The shared, cross-repo deny-list, falling back to the in-repo one.

    The fallback exists so a machine that has not yet created the shared file
    keeps working exactly as before -- moving to the shared location is
    opt-in by creating the file, not a breaking change on the day it ships.
    """
    shared = shared_denylist_path()
    path = shared if shared.is_file() else root / "scripts" / "denylist.local.txt"
    text = read_text(path)
    if text is None:
        return []
    terms = []
    for raw in text.splitlines():
        term = raw.strip()
        if term and not term.startswith("#"):
            terms.append(term.lower())
    return terms

def check_privacy(root: Path, allow_missing_denylist: bool = False) -> tuple[list[Finding], list[str]]:
    """The contribution rule, enforced.

    Two layers. Structural patterns are safe to commit because they describe a
    *shape* of identifier. Employer, client and project names are not -- naming
    them here would publish exactly what the rule exists to withhold -- so they
    live in a gitignored local file.
    """
    findings: list[Finding] = []
    notices: list[str] = []


    terms = local_denylist(root)
    if not terms:
        if allow_missing_denylist:
            notices.append(
                "no deny-list found (checked "
                "${XDG_CONFIG_HOME:-$HOME/.config}/" + CONFIG_DIR_NAME + "/denylist.txt "
                "and scripts/denylist.local.txt) -- employer/client/project names are "
                "NOT being checked, and --allow-missing-denylist was passed. Structural "
                "patterns still ran."
            )
        else:
            findings.append(
                Finding("privacy", "scripts/denylist.local.txt", 0,
                        "missing -- checked "
                        "${XDG_CONFIG_HOME:-$HOME/.config}/" + CONFIG_DIR_NAME + "/denylist.txt "
                        "and scripts/denylist.local.txt, found neither. employer/client/"
                        "project names are unchecked. Copy denylist.local.txt.example to "
                        "one of those paths and fill it in, or pass "
                        "--allow-missing-denylist to accept structural checks only")
            )

    ignored = ignored_paths(root)
    for path in iter_files(root):
        rel = path.relative_to(root).as_posix()
        text = read_text(path)
        if text is None:
            continue
        if is_ignored(rel, ignored):
            continue
        if any(path.match(p) for p in PRIVACY_SKIP):
            continue
        scan_structural = not any(path.match(p) for p in STRUCTURAL_EXCLUDE)

        for lineno, line in enumerate(text.splitlines(), start=1):
            lowered = line.lower()
            for term in terms:
                if term in lowered:
                    findings.append(
                        Finding("privacy", rel, lineno, "deny-listed term present")
                    )
            if not scan_structural:
                continue
            for name, pattern, why in FORMAT_PATTERNS:
                for match in pattern.finditer(line):
                    if name == "absolute-home-path":
                        if match.group(1).lower() in NON_IDENTIFYING_HOMES:
                            continue
                    findings.append(
                        Finding("privacy", rel, lineno, f"{why}: {match.group(0)!r}")
                    )
    return findings, notices

def check_identity(root: Path) -> list[Finding]:
    """Identity-shaped strings not yet known to be somebody else's.

    Returned as warnings by the caller, never as blocking findings -- see the note on
    IDENTITY_PATTERNS for why these cannot be matched precisely.
    """
    values, paths = load_allowlist(root)
    ignored = ignored_paths(root)
    warnings: list[Finding] = []

    for path in iter_files(root):
        rel = path.relative_to(root).as_posix()
        if is_ignored(rel, ignored) or path_allowlisted(rel, paths):
            continue
        if any(path.match(p) for p in PRIVACY_SKIP + STRUCTURAL_EXCLUDE):
            continue
        text = read_text(path)
        if text is None:
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            for name, pattern, why in IDENTITY_PATTERNS:
                for match in pattern.finditer(line):
                    hit = match.group(0)
                    if hit.lower() in values:
                        continue
                    if name == "email-address" and EMAIL_OK.search(hit):
                        continue
                    warnings.append(Finding(name, rel, lineno, hit))
    return warnings

def check_history(root: Path, rev_args: list[str] | None = None
                  ) -> tuple[list[Finding], list[str]]:
    """Scan committed blobs, not just the working tree.

    A secret committed and then deleted stays reachable in a public repository
    forever, and the working-tree checks cannot see it.

    `rev_args` selects which commits to walk. The default (`--all`) is right for a
    repository that started clean and stayed that way. Pass a range -- typically
    `[<sha>, "--not", "--remotes"]` -- for one whose past is already published and
    immutable: scanning it produces findings nobody can act on, and an unsatisfiable
    check is one people learn to bypass.
    """
    def git(*args):
        try:
            r = subprocess.run(("git", "-C", str(root)) + args,
                               capture_output=True, text=True, timeout=120)
        except (OSError, subprocess.SubprocessError):
            return None
        return r.stdout if r.returncode == 0 else None

    if git("rev-parse", "--git-dir") is None:
        return [], ["history scan skipped: not a git repository"]
    listing = git("rev-list", "--objects", *(rev_args or ["--all"]))
    if listing is None:
        return [], ["history scan skipped: could not list objects"]

    blobs = {}
    for line in listing.splitlines():
        sha, _, path = line.partition(" ")
        if path:
            blobs[sha] = path
    if not blobs:
        return [], ["history scan: no committed objects yet"]

    terms = local_denylist(root)
    findings = []
    try:
        batch = subprocess.run(("git", "-C", str(root), "cat-file", "--batch"),
                               input=("\n".join(blobs) + "\n").encode(),
                               capture_output=True, timeout=300)
    except (OSError, subprocess.SubprocessError):
        return [], ["history scan skipped: git cat-file failed"]
    if batch.returncode != 0:
        return [], ["history scan skipped: git cat-file failed"]

    data, pos, scanned = batch.stdout, 0, 0
    while pos < len(data):
        nl = data.find(b"\n", pos)
        if nl == -1:
            break
        header = data[pos:nl].decode("utf-8", "replace").split()
        pos = nl + 1
        if len(header) < 3 or header[1] != "blob":
            continue
        sha, size = header[0], int(header[2])
        body, pos = data[pos:pos + size], pos + size + 1
        path = blobs.get(sha, "?")
        p = Path(path)
        if p.suffix in SKIP_SUFFIXES or any(p.match(x) for x in PRIVACY_SKIP):
            continue
        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError:
            continue
        scanned += 1
        structural = not any(p.match(x) for x in STRUCTURAL_EXCLUDE)
        for lineno, line in enumerate(text.splitlines(), start=1):
            lowered = line.lower()
            for term in terms:
                if term in lowered:
                    findings.append(Finding("history", f"{path}@{sha[:8]}", lineno,
                                            "deny-listed term present in history"))
            if not structural:
                continue
            for name, pattern, why in FORMAT_PATTERNS:
                for match in pattern.finditer(line):
                    if (name == "absolute-home-path"
                            and match.group(1).lower() in NON_IDENTIFYING_HOMES):
                        continue
                    findings.append(Finding("history", f"{path}@{sha[:8]}", lineno,
                                            f"{why}: {match.group(0)!r}"))
    return findings, [f"history scan: {scanned} committed blob(s) examined"]

WARN_LIST_LIMIT = 10

def render_warnings(warnings: list[Finding], root: Path, limit: int = WARN_LIST_LIMIT) -> list[str]:
    """Aggregate warnings so a large change does not produce a wall of text.

    A wall of text is not read, and a warning that is not read protects nothing. Four
    reductions, in order of how much they buy: deduplicate by value (one file can
    reference the same repository thirty times), collapse a dominating path (vendoring
    a library should cost one line, not forty), group by pattern, then cap the listing
    and spill the rest to a file.
    """
    if not warnings:
        return []

    seen: dict[tuple[str, str], list] = {}
    for w in warnings:
        key = (w.check, w.message)
        if key in seen:
            seen[key][0] += 1
        else:
            seen[key] = [1, f"{w.path}:{w.line}"]

    by_path: dict[str, set] = {}
    for w in warnings:
        by_path.setdefault(w.path, set()).add((w.check, w.message))

    out = [f"{len(seen)} identity-shaped string(s) not in the allowlist"]

    dominant = max(by_path.items(), key=lambda kv: len(kv[1]), default=(None, set()))
    if dominant[0] and len(dominant[1]) >= 5 and len(dominant[1]) > len(seen) / 2:
        out += [
            "",
            f"  {dominant[0]} accounts for {len(dominant[1])} of them.",
            "  If it is vendored, allowlist the path rather than each value:",
            f"    path: {dominant[0]}",
        ]
        for key in dominant[1]:
            seen.pop(key, None)
        if not seen:
            return out
        out.append("")

    grouped: dict[str, list] = {}
    for (check, value), (count, where) in seen.items():
        grouped.setdefault(check, []).append((value, count, where))

    shown = 0
    overflow: list[str] = []
    for check in sorted(grouped):
        rows = sorted(grouped[check], key=lambda r: -r[1])
        out += ["", f"  {check} ({len(rows)})"]
        for value, count, where in rows:
            if shown >= limit:
                overflow.append(f"{check}\t{value}\t{where}")
                continue
            extra = f"   (+{count - 1})" if count > 1 else ""
            out.append(f"    {value:<44} {where}{extra}")
            shown += 1

    if overflow:
        spill = root / ".git" / "gate-warnings.txt"
        try:
            spill.parent.mkdir(parents=True, exist_ok=True)
            spill.write_text("\n".join(overflow) + "\n")
            out += ["", f"  ...and {len(overflow)} more, listed in {spill}"]
        except OSError:
            out += ["", f"  ...and {len(overflow)} more (could not write the overflow file)"]

    out += ["", "  Allowlist what is not yours by adding it to scripts/allowlist.txt"]
    return out
