#!/usr/bin/env python3
"""Feature-freeze policy verifier (E12-R30).

Three checks in one tool, all fail-closed (L566 / L571 / L573 / L575 — a
hand-written line parser defaults to fail-OPEN; what does not match the
expected shape must be an error, never a silently-dropped row):

  * **Freeze classification (A1, A6).** Every path changed since
    `docs/release/feature-freeze.md`'s `freeze_base_sha` (or listed in an
    explicit `--changes-file`, for git-fixture-free testing) must fall into
    one of the THREE closed change classes that same document declares —
    `documentation` (`docs/**`, `CHANGELOG.md`), `release-tooling`
    (`tool/release/**`, `test/tooling/**`), or `blocker-fix` (any path, but
    ONLY if the commit that touches it names a `P0`/`P1`/`P2` blocker id
    that exists in `docs/release/blockers.md`). A path matching none of the
    three is a finding naming the path.
  * **Known-issues honesty (A2, A3).** Every row in
    `docs/release/known-issues.md`'s marker-delimited table must carry a
    non-empty title, impact and workaround (an explicit "no workaround" is a
    non-empty cell — an EMPTY cell is the failure, not the wording), and
    every `P0`/`P1` row's id must exist in `docs/release/blockers.md` with
    the same severity — no P0/P1 known issue may hide outside the blocker
    registry.
  * **CHANGELOG determinism (A4).** `CHANGELOG.md`'s marker-delimited
    release-header block carries exactly `version`, `build` and
    `schema_version` — no fourth line, so a generation timestamp cannot be
    smuggled in (ADR 0447 D1) — and the three values must equal the
    MEASURED `pubspec.yaml` version/build and the `releaseManifestSchemaVersion`
    constant in `tool/generate_release_manifest.dart`.

Two independently-disciplined table/block parsers per document, on purpose,
following the `tool/release/verify_ga_scope.py` precedent: every non-header,
non-separator line inside a marker block is a REQUIRED data row, and a line
that does not fully match its table's row shape is a `VerifyError` naming
the line — never a silently-skipped row. A marker block that is missing or
empty is itself a `VerifyError` (A7).

Exit codes (frozen, `docs/release/contract-freeze.md` — the same three
codes `verify_ga_scope.py` / `verify_beta_profile.py` use; no fourth code):
  0  every check passed
  1  a validation rule failed: an unclassified freeze-era change (A1), an
     empty known-issues title/impact/workaround cell or an unknown severity
     value (A2), a P0/P1 known-issues row with no matching (or
     severity-mismatched) `blockers.md` id (A3), or a CHANGELOG header field
     that disagrees with the measured `pubspec.yaml`/manifest-generator
     source (A4)
  2  usage or format error: a missing/malformed file, a missing or empty
     marker block, a table/block row that does not match the expected
     shape, an invalid `--since` git revision, or `--since` and
     `--changes-file` given together
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_FEATURE_FREEZE_PATH = Path("docs/release/feature-freeze.md")
DEFAULT_KNOWN_ISSUES_PATH = Path("docs/release/known-issues.md")
DEFAULT_BLOCKERS_PATH = Path("docs/release/blockers.md")
DEFAULT_CHANGELOG_PATH = Path("CHANGELOG.md")
DEFAULT_PUBSPEC_PATH = Path("pubspec.yaml")
DEFAULT_MANIFEST_GENERATOR_PATH = Path("tool/generate_release_manifest.dart")

_KNOWN_SEVERITIES = {"P0", "P1", "P2", "P3"}
_BLOCKER_FIX_REQUIRING_SEVERITIES = {"P0", "P1", "P2"}


class VerifyError(Exception):
    """A usage/format error (exit 2) — parsing could not even determine
    what to check, as opposed to a validation finding (exit 1)."""


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError as error:
        raise VerifyError(f"file not found: {path}") from error


# ---------------------------------------------------------------------------
# Generic marker-block helpers (precedent: verify_ga_scope.py)
# ---------------------------------------------------------------------------


def _extract_block_lines(
    text: str, *, begin_marker: str, end_marker: str, path: Path
) -> list[tuple[int, str]]:
    """Every line between the markers, UNFILTERED (blank lines included) —
    used for fixed-shape key:value blocks where a stray blank line is
    itself a shape violation."""
    lines = text.splitlines()
    begin_index = end_index = None
    for index, line in enumerate(lines):
        if begin_marker in line:
            begin_index = index
        elif end_marker in line and begin_index is not None:
            end_index = index
            break
    if begin_index is None or end_index is None:
        raise VerifyError(
            f"{path}: markers {begin_marker!r}/{end_marker!r} not found or out of order"
        )
    return [
        (line_number, line)
        for line_number, line in enumerate(
            lines[begin_index + 1 : end_index], start=begin_index + 2
        )
    ]


def _extract_table(
    text: str, *, begin_marker: str, end_marker: str, path: Path
) -> list[tuple[int, str]]:
    """Every `|`-starting line between the markers — prose/headings between
    tables in the same block are not candidate rows at all, matching the
    `verify_ga_scope.py` capability/core-path table extractor."""
    lines = text.splitlines()
    begin_index = end_index = None
    for index, line in enumerate(lines):
        if begin_marker in line:
            begin_index = index
        elif end_marker in line and begin_index is not None:
            end_index = index
            break
    if begin_index is None or end_index is None:
        raise VerifyError(
            f"{path}: markers {begin_marker!r}/{end_marker!r} not found or out of order"
        )
    return [
        (line_number, line)
        for line_number, line in enumerate(
            lines[begin_index + 1 : end_index], start=begin_index + 2
        )
        if line.strip().startswith("|")
    ]


def _parse_table(
    rows: list[tuple[int, str]],
    *,
    row_pattern: re.Pattern,
    path: Path,
    header_prefixes: tuple[str, ...],
) -> list[tuple[int, re.Match]]:
    """Every non-header, non-separator `|`-row is a REQUIRED data row — a
    row that does not fully match `row_pattern` is a `VerifyError` naming
    the line, never a silently-dropped row (L566/L571/L573/L575)."""
    parsed: list[tuple[int, re.Match]] = []
    for line_number, line in rows:
        stripped = line.strip()
        if stripped.startswith(header_prefixes) or set(
            stripped.replace("|", "").strip()
        ) <= {"-", " "}:
            continue
        match = row_pattern.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: table row does not match the expected "
                f"shape — {line!r}"
            )
        parsed.append((line_number, match))
    return parsed


# ---------------------------------------------------------------------------
# docs/release/feature-freeze.md
# ---------------------------------------------------------------------------

_FREEZE_BASE_SHA_LINE = re.compile(r"^freeze_base_sha:\s*(?P<sha>[0-9a-f]{7,40})$")
_APPROVER_ROLE_LINE = re.compile(r"^approver_role:\s*(?P<role>\S.*)$")


def load_freeze_base(path: Path) -> dict:
    text = _read(path)
    rows = _extract_block_lines(
        text,
        begin_marker="<!-- freeze-base:begin -->",
        end_marker="<!-- freeze-base:end -->",
        path=path,
    )
    if not rows:
        raise VerifyError(f"{path}: freeze-base marker block is empty")
    if len(rows) != 2:
        raise VerifyError(
            f"{path}: freeze-base marker block must contain exactly 2 lines "
            f"(freeze_base_sha, approver_role), found {len(rows)}"
        )
    (sha_line_no, sha_line), (role_line_no, role_line) = rows
    sha_match = _FREEZE_BASE_SHA_LINE.match(sha_line.strip())
    if sha_match is None:
        raise VerifyError(
            f'{path}:{sha_line_no}: expected "freeze_base_sha: <sha>" — {sha_line!r}'
        )
    role_match = _APPROVER_ROLE_LINE.match(role_line.strip())
    if role_match is None:
        raise VerifyError(
            f'{path}:{role_line_no}: expected "approver_role: <text>" — {role_line!r}'
        )
    return {
        "freeze_base_sha": sha_match.group("sha"),
        "approver_role": role_match.group("role"),
    }


_FREEZE_CLASS_ROW = re.compile(
    r"^\|\s*`(?P<cls>[a-zA-Z_-]+)`\s*\|\s*(?P<paths>.+?)\s*\|\s*"
    r"`(?P<requires>yes|no)`\s*\|$"
)
_PATH_TOKEN = re.compile(r"`([^`]+)`")


def load_freeze_classes(path: Path) -> dict[str, dict]:
    text = _read(path)
    rows = _extract_table(
        text,
        begin_marker="<!-- freeze-classes:begin -->",
        end_marker="<!-- freeze-classes:end -->",
        path=path,
    )
    if not rows:
        raise VerifyError(f"{path}: freeze-classes marker block is empty")
    parsed = _parse_table(
        rows, row_pattern=_FREEZE_CLASS_ROW, path=path, header_prefixes=("| class",)
    )
    if not parsed:
        raise VerifyError(f"{path}: freeze-classes table has no data rows")

    classes: dict[str, dict] = {}
    for line_number, match in parsed:
        cls = match.group("cls")
        if cls in classes:
            raise VerifyError(
                f"{path}:{line_number}: freeze class {cls!r} listed more than once"
            )
        tokens = _PATH_TOKEN.findall(match.group("paths"))
        if not tokens:
            raise VerifyError(
                f"{path}:{line_number}: freeze class {cls!r} has no "
                "backtick-quoted path token(s)"
            )
        classes[cls] = {
            "paths": set(tokens),
            "requires_blocker_id": match.group("requires") == "yes",
        }
    return classes


# ---------------------------------------------------------------------------
# docs/release/blockers.md — id -> severity, fail-closed row shape
# (precedent: verify_ga_scope.py's load_open_blockers, widened to keep
# every severity, not only P0/P1 — a `blocker-fix` may also cite a P2)
# ---------------------------------------------------------------------------

_BLOCKER_ID_START = re.compile(r"^\|\s*R-[A-Z0-9-]+\s*\|")
_BLOCKER_ROW = re.compile(r"^\|\s*(?P<id>R-[A-Z0-9-]+)\s*\|\s*(?P<severity>P[0-4])\s*\|")


def load_blocker_ids(path: Path) -> dict[str, str]:
    text = _read(path)
    ids: dict[str, str] = {}
    for line_number, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not _BLOCKER_ID_START.match(stripped):
            continue
        match = _BLOCKER_ROW.match(stripped)
        if match is None:
            raise VerifyError(
                f"{path}:{line_number}: blocker row does not match the expected "
                f"shape — {line!r}"
            )
        ids[match.group("id")] = match.group("severity")
    return ids


# ---------------------------------------------------------------------------
# docs/release/known-issues.md
# ---------------------------------------------------------------------------

_KNOWN_ISSUE_ROW = re.compile(
    r"^\|\s*`(?P<id>[^`]+)`\s*\|\s*`(?P<severity>[^`]+)`\s*\|\s*"
    r"(?P<title>[^|]*?)\s*\|\s*(?P<impact>[^|]*?)\s*\|\s*(?P<workaround>[^|]*?)\s*\|$"
)


def load_known_issues(path: Path) -> list[tuple[int, re.Match]]:
    text = _read(path)
    rows = _extract_table(
        text,
        begin_marker="<!-- known-issues:begin -->",
        end_marker="<!-- known-issues:end -->",
        path=path,
    )
    if not rows:
        raise VerifyError(f"{path}: known-issues marker block is empty")
    parsed = _parse_table(
        rows, row_pattern=_KNOWN_ISSUE_ROW, path=path, header_prefixes=("| id",)
    )
    if not parsed:
        raise VerifyError(f"{path}: known-issues table has no data rows")
    return parsed


def validate_known_issues(
    rows: list[tuple[int, re.Match]], blocker_ids: dict[str, str]
) -> list[str]:
    findings: list[str] = []
    seen_ids: dict[str, int] = {}
    for line_number, match in rows:
        issue_id = match.group("id")
        severity = match.group("severity")
        title = match.group("title").strip()
        impact = match.group("impact").strip()
        workaround = match.group("workaround").strip()

        if issue_id in seen_ids:
            findings.append(
                f"known-issues.md:{line_number}: id {issue_id!r} listed more than "
                f"once (also line {seen_ids[issue_id]})"
            )
        seen_ids[issue_id] = line_number

        if severity not in _KNOWN_SEVERITIES:
            findings.append(
                f"known-issues.md:{line_number}: id {issue_id!r} has unknown "
                f"severity {severity!r} — must be one of {sorted(_KNOWN_SEVERITIES)}"
            )
        if not title:
            findings.append(
                f"known-issues.md:{line_number}: id {issue_id!r} has an empty title (A2)"
            )
        if not impact:
            findings.append(
                f"known-issues.md:{line_number}: id {issue_id!r} has an empty "
                "impact cell (A2)"
            )
        if not workaround:
            findings.append(
                f"known-issues.md:{line_number}: id {issue_id!r} has an empty "
                "workaround cell — state 'no workaround' explicitly instead of "
                "leaving it blank (A2, §5.2)"
            )

        if severity in {"P0", "P1"}:
            blocker_severity = blocker_ids.get(issue_id)
            if blocker_severity is None:
                findings.append(
                    f"known-issues.md:{line_number}: id {issue_id!r} is severity "
                    f"{severity!r} but has no matching row in blockers.md (A3) — "
                    "no P0/P1 known issue may hide outside the blocker registry"
                )
            elif blocker_severity != severity:
                findings.append(
                    f"known-issues.md:{line_number}: id {issue_id!r} is severity "
                    f"{severity!r} here but {blocker_severity!r} in blockers.md (A3)"
                )
    return findings


# ---------------------------------------------------------------------------
# CHANGELOG.md — release-header marker block
# ---------------------------------------------------------------------------

_CHANGELOG_VERSION_LINE = re.compile(r"^version:\s*(?P<version>\d+\.\d+\.\d+)$")
_CHANGELOG_BUILD_LINE = re.compile(r"^build:\s*(?P<build>\d+)$")
_CHANGELOG_SCHEMA_VERSION_LINE = re.compile(r"^schema_version:\s*(?P<schema_version>\d+)$")


def load_changelog_header(path: Path) -> dict:
    text = _read(path)
    rows = _extract_block_lines(
        text,
        begin_marker="<!-- release-header:begin -->",
        end_marker="<!-- release-header:end -->",
        path=path,
    )
    if not rows:
        raise VerifyError(f"{path}: release-header marker block is empty")
    if len(rows) != 3:
        raise VerifyError(
            f"{path}: release-header marker block must contain exactly 3 lines "
            f"(version, build, schema_version) — a 4th line (e.g. a generation "
            f"timestamp) is forbidden by ADR 0447 D1; found {len(rows)}"
        )
    (v_no, v_line), (b_no, b_line), (s_no, s_line) = rows
    v_match = _CHANGELOG_VERSION_LINE.match(v_line.strip())
    if v_match is None:
        raise VerifyError(f'{path}:{v_no}: expected "version: X.Y.Z" — {v_line!r}')
    b_match = _CHANGELOG_BUILD_LINE.match(b_line.strip())
    if b_match is None:
        raise VerifyError(f'{path}:{b_no}: expected "build: <int>" — {b_line!r}')
    s_match = _CHANGELOG_SCHEMA_VERSION_LINE.match(s_line.strip())
    if s_match is None:
        raise VerifyError(
            f'{path}:{s_no}: expected "schema_version: <int>" — {s_line!r}'
        )
    return {
        "version": v_match.group("version"),
        "build": int(b_match.group("build")),
        "schema_version": int(s_match.group("schema_version")),
    }


def validate_changelog(header: dict, *, pubspec_version: str, pubspec_build: int, schema_version: int) -> list[str]:
    findings: list[str] = []
    if header["version"] != pubspec_version:
        findings.append(
            f"CHANGELOG.md: release-header version {header['version']!r} does not "
            f"match the measured pubspec.yaml version {pubspec_version!r} (A4)"
        )
    if header["build"] != pubspec_build:
        findings.append(
            f"CHANGELOG.md: release-header build {header['build']!r} does not "
            f"match the measured pubspec.yaml build {pubspec_build!r} (A4)"
        )
    if header["schema_version"] != schema_version:
        findings.append(
            f"CHANGELOG.md: release-header schema_version "
            f"{header['schema_version']!r} does not match the measured "
            f"releaseManifestSchemaVersion constant {schema_version!r} (A4)"
        )
    return findings


# ---------------------------------------------------------------------------
# pubspec.yaml / tool/generate_release_manifest.dart — MEASURED sources
# ---------------------------------------------------------------------------

_PUBSPEC_VERSION_LINE = re.compile(r"^version:\s*(?P<full>\S+)\s*$", re.MULTILINE)
_MANIFEST_SCHEMA_VERSION_CONST = re.compile(
    r"const int releaseManifestSchemaVersion = (?P<n>\d+);"
)


def load_pubspec_version(path: Path) -> tuple[str, int]:
    text = _read(path)
    match = _PUBSPEC_VERSION_LINE.search(text)
    if match is None:
        raise VerifyError(f'{path}: no top-level "version:" line found')
    full = match.group("full")
    if "+" not in full:
        raise VerifyError(f'{path}: version {full!r} has no "+<build>" suffix')
    version, build = full.split("+", 1)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not re.fullmatch(r"\d+", build):
        raise VerifyError(f'{path}: version {full!r} is not in "X.Y.Z+N" shape')
    return version, int(build)


def load_manifest_schema_version(path: Path) -> int:
    text = _read(path)
    match = _MANIFEST_SCHEMA_VERSION_CONST.search(text)
    if match is None:
        raise VerifyError(
            f'{path}: "const int releaseManifestSchemaVersion = <n>;" not found'
        )
    return int(match.group("n"))


# ---------------------------------------------------------------------------
# Freeze-era change list: real git (--since) or an explicit, fail-closed
# --changes-file (git-fixture-free testing)
# ---------------------------------------------------------------------------


def get_changes_from_git(since_sha: str) -> list[tuple[str, str]]:
    try:
        subprocess.run(
            ["git", "rev-parse", "--verify", since_sha],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, OSError) as error:
        raise VerifyError(
            f"--since {since_sha!r} is not a valid git revision: {error}"
        ) from error

    try:
        rev_list_result = subprocess.run(
            ["git", "rev-list", "--reverse", f"{since_sha}..HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        raise VerifyError(
            f"git rev-list failed for --since {since_sha!r}: {error.stderr}"
        ) from error

    changes: list[tuple[str, str]] = []
    for commit_sha in rev_list_result.stdout.split():
        message = subprocess.run(
            ["git", "log", "-1", "--format=%B", commit_sha],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        files = subprocess.run(
            ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", commit_sha],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.splitlines()
        for changed_path in files:
            if changed_path:
                changes.append((changed_path, message))
    return changes


def load_changes_file(path: Path) -> list[tuple[str, str]]:
    """Each non-blank, non-`#`-comment line is `<path>\\t<commit message>` —
    a line with no tab, or an empty path, is a `VerifyError` (fail-closed;
    lets A1's negative fixtures be deterministic without a real git repo)."""
    text = _read(path)
    changes: list[tuple[str, str]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.startswith("#"):
            continue
        if "\t" not in line:
            raise VerifyError(
                f'{path}:{line_number}: expected "<path>\\t<commit message>", no '
                f"tab found — {line!r}"
            )
        changed_path, message = line.split("\t", 1)
        if not changed_path:
            raise VerifyError(f"{path}:{line_number}: empty path — {line!r}")
        changes.append((changed_path, message))
    return changes


_BLOCKER_ID_TOKEN = re.compile(r"\bR-[A-Z0-9-]+\b")


def _message_names_valid_blocker_fix(message: str, blocker_ids: dict[str, str]) -> bool:
    for token in _BLOCKER_ID_TOKEN.findall(message):
        if blocker_ids.get(token) in _BLOCKER_FIX_REQUIRING_SEVERITIES:
            return True
    return False


def classify_changes(
    changes: list[tuple[str, str]],
    classes: dict[str, dict],
    blocker_ids: dict[str, str],
) -> list[str]:
    findings: list[str] = []
    prefix_classes = {
        name: cls for name, cls in classes.items() if cls["paths"] != {"*"}
    }
    wildcard_classes = {
        name: cls for name, cls in classes.items() if cls["paths"] == {"*"}
    }

    for changed_path, message in changes:
        matched_class = None
        for name, cls in prefix_classes.items():
            if any(changed_path.startswith(prefix) for prefix in cls["paths"]):
                matched_class = name
                break

        if matched_class is None:
            for name, cls in wildcard_classes.items():
                if not cls["requires_blocker_id"]:
                    matched_class = name
                    break
                if _message_names_valid_blocker_fix(message, blocker_ids):
                    matched_class = name
                    break

        if matched_class is None:
            findings.append(
                f"{changed_path}: not classified under any freeze change class "
                "(no documentation/release-tooling path prefix matched, and the "
                "commit names no P0/P1/P2 blockers.md id) — commit message: "
                f"{message!r} (A1)"
            )
    return findings


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feature-freeze", type=Path, default=DEFAULT_FEATURE_FREEZE_PATH)
    parser.add_argument("--known-issues", type=Path, default=DEFAULT_KNOWN_ISSUES_PATH)
    parser.add_argument("--blockers", type=Path, default=DEFAULT_BLOCKERS_PATH)
    parser.add_argument("--changelog", type=Path, default=DEFAULT_CHANGELOG_PATH)
    parser.add_argument("--pubspec", type=Path, default=DEFAULT_PUBSPEC_PATH)
    parser.add_argument(
        "--manifest-generator", type=Path, default=DEFAULT_MANIFEST_GENERATOR_PATH
    )
    parser.add_argument(
        "--since",
        metavar="SHA",
        help="Base git SHA — classify every path changed since this commit on "
        "the real git history (mutually exclusive with --changes-file).",
    )
    parser.add_argument(
        "--changes-file",
        type=Path,
        help="Explicit, fail-closed <path>\\t<commit message> list — classify "
        "this instead of reading real git history (testing).",
    )
    args = parser.parse_args(argv)

    if args.since is not None and args.changes_file is not None:
        print(
            "verify_freeze: --since and --changes-file are mutually exclusive",
            file=sys.stderr,
        )
        return 2

    try:
        classes = load_freeze_classes(args.feature_freeze)
        load_freeze_base(args.feature_freeze)  # validated for its own shape
        blocker_ids = load_blocker_ids(args.blockers)
        known_issues_rows = load_known_issues(args.known_issues)
        changelog_header = load_changelog_header(args.changelog)
        pubspec_version, pubspec_build = load_pubspec_version(args.pubspec)
        schema_version = load_manifest_schema_version(args.manifest_generator)

        changes: list[tuple[str, str]] | None = None
        if args.since is not None:
            changes = get_changes_from_git(args.since)
        elif args.changes_file is not None:
            changes = load_changes_file(args.changes_file)
    except VerifyError as error:
        print(f"verify_freeze: {error}", file=sys.stderr)
        return 2

    findings: list[str] = []
    if changes is not None:
        findings += classify_changes(changes, classes, blocker_ids)
    findings += validate_known_issues(known_issues_rows, blocker_ids)
    findings += validate_changelog(
        changelog_header,
        pubspec_version=pubspec_version,
        pubspec_build=pubspec_build,
        schema_version=schema_version,
    )

    if findings:
        print(f"verify_freeze: {len(findings)} finding(s):", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return 1

    summary = f"verify_freeze: ok — {len(known_issues_rows)} known-issue row(s)"
    if changes is not None:
        summary += f", {len(changes)} changed path(s) classified"
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
