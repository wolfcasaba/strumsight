#!/usr/bin/env python3
"""Static production signing-policy audit (ADR 0448 D2/D5/D6).

Standard library only (see `tool/release/generate_sbom.py`'s module
docstring for why: the CI runner image does not guarantee any third-party
Python package).

There is no Android SDK on this box (E12-R07 brief §0.0.1.a), so this tool
does NOT run Gradle — it statically audits the TEXT of
`android/app/build.gradle.kts` and `.github/workflows/release-apk.yml`
against a small set of named rules. Both file paths are parameters
(`--gradle` / `--workflow`) precisely so the gate test can point them at a
synthetic fixture instead of the real tree (ADR 0448 D6): the cell must
measure BOTH a real-file exit 0 AND a broken-fixture non-zero exit, never
only the former (the `test/tooling/check_secrets_test.dart` L220 failure
class this repo already guards against elsewhere).

Rules on the Gradle file (ADR 0448 D2/D3):

  - debug-keystore-rejected: production-required signing (gated on the
    `releaseSigningRequired` toggle) throws when the keystore file name is
    "debug.keystore" (case-insensitive) or the keystore path is the default
    `~/.android/debug.keystore`.
  - debug-alias-rejected: same gate, throws when the key alias is
    "androiddebugkey" (case-insensitive).
  - lab-fallback-preserved: the release buildType can still resolve to the
    debug signing config when production signing is not required — the
    Lab/dev build path (no signing env at all) must not regress (ADR 0448
    D3).

Rules on the workflow file (ADR 0448 D5, R3 — a regression guard over
already-fail-closed behaviour, not new functionality):

  - secrets-checked-before-build: the release-apk job declares
    `needs: signing-prerequisites`.
  - keystore-not-echoed: no step echoes/prints/cats a signing password —
    either as a plain shell reference (`$NAME` / `${NAME}`) or as a GitHub
    Actions interpolation (`${{ secrets.NAME }}` / `${{ env.NAME }}`) — and
    no `set -x`-shaped line exists (which would echo every later command,
    including secret arguments). The one exception is the exact
    `echo "::add-mask::$NAME"` masking idiom ADR 0448 D5 requires before a
    secret is used — that whole line, and nothing wider, is not a leak.
  - keystore-cleanup-present: an `if: always()` step removes the
    materialized keystore file.

`--strict` turns any violation into a non-zero exit; every rule still runs
and prints its verdict without it, but the process always exits 0 (a plain
human dry run). The round gate always passes `--strict`.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


class PolicyViolation:
    def __init__(self, rule: str, message: str) -> None:
        self.rule = rule
        self.message = message

    def __str__(self) -> str:
        return f"{self.rule}: {self.message}"


# Lookback for the enclosing releaseSigningRequired guard and lookahead for
# the resulting throw. Measured against the real gradle file: the keystore
# and alias comparisons sit ~220 and ~600 characters after the enclosing
# `if (releaseSigningRequired && ...)` respectively, so the gate window is
# wider than the throw window.
_GATE_WINDOW = 900
_THROW_WINDOW = 400

_DEBUG_KEYSTORE_NAME_COMPARISON = re.compile(
    r'"debug\.keystore"\s*,\s*ignoreCase\s*=\s*true', re.IGNORECASE
)
_DEBUG_KEYSTORE_DEFAULT_PATH = re.compile(r"\.android/debug\.keystore", re.IGNORECASE)
_DEBUG_ALIAS_COMPARISON = re.compile(
    r'"androiddebugkey"\s*,\s*ignoreCase\s*=\s*true', re.IGNORECASE
)
_THROW_GRADLE_EXCEPTION = re.compile(r"throw\s+GradleException\s*\(")
_WARN_ONLY = re.compile(r"\b(println|logger\.warn)\s*\(")
_RELEASE_SIGNING_REQUIRED_TOKEN = "releaseSigningRequired"
_DEBUG_SIGNING_CONFIG_ASSIGNMENT = re.compile(r'signingConfigs\.getByName\(\s*"debug"\s*\)')


def _closest_gate_and_throw(text: str, comparison: re.Pattern[str]) -> tuple[bool, bool, bool]:
    """For every regex match of a debug-credential comparison, checks whether
    it is gated by `releaseSigningRequired` shortly before it and followed
    by a `throw GradleException(` shortly after it. Returns
    (found_any_match, gated, rejected) for the first match that satisfies
    both, or the diagnostics of the last match if none do.
    """
    matches = list(comparison.finditer(text))
    if not matches:
        return False, False, False
    last_gated = False
    last_rejected = False
    for match in matches:
        before = text[max(0, match.start() - _GATE_WINDOW) : match.start()]
        after = text[match.end() : match.end() + _THROW_WINDOW]
        gated = _RELEASE_SIGNING_REQUIRED_TOKEN in before
        rejected = _THROW_GRADLE_EXCEPTION.search(after) is not None
        if gated and rejected:
            return True, True, True
        last_gated, last_rejected = gated, rejected
    return True, last_gated, last_rejected


def _debug_credential_rule(
    text: str,
    *,
    rule: str,
    comparison: re.Pattern[str],
    missing_message: str,
    ungated_message: str,
) -> list[PolicyViolation]:
    found, gated, rejected = _closest_gate_and_throw(text, comparison)
    if not found:
        return [PolicyViolation(rule, missing_message)]
    if not gated:
        return [PolicyViolation(rule, ungated_message)]
    if not rejected:
        if _WARN_ONLY.search(text):
            return [
                PolicyViolation(
                    rule,
                    "the check only warns (println/logger.warn) instead of "
                    "throwing GradleException",
                )
            ]
        return [
            PolicyViolation(
                rule,
                "the comparison is not followed by a throw GradleException(...)",
            )
        ]
    return []


def check_gradle(text: str) -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []

    keystore_violations = _debug_credential_rule(
        text,
        rule="debug-keystore-rejected",
        comparison=_DEBUG_KEYSTORE_NAME_COMPARISON,
        missing_message=(
            'no case-insensitive comparison against "debug.keystore" found — '
            "the production signing branch does not reject the debug "
            "keystore filename"
        ),
        ungated_message=(
            f'the "debug.keystore" comparison is not gated by '
            f"{_RELEASE_SIGNING_REQUIRED_TOKEN} — it may apply globally and "
            f"break the Lab build"
        ),
    )
    violations.extend(keystore_violations)
    if not keystore_violations and not _DEBUG_KEYSTORE_DEFAULT_PATH.search(text):
        violations.append(
            PolicyViolation(
                "debug-keystore-rejected",
                "no check against the default ~/.android/debug.keystore path "
                "found (ADR 0448 D2 requires both the filename AND the "
                "default-path form)",
            )
        )

    violations.extend(
        _debug_credential_rule(
            text,
            rule="debug-alias-rejected",
            comparison=_DEBUG_ALIAS_COMPARISON,
            missing_message=(
                'no case-insensitive comparison against "androiddebugkey" found'
            ),
            ungated_message=(
                f'the "androiddebugkey" comparison is not gated by '
                f"{_RELEASE_SIGNING_REQUIRED_TOKEN}"
            ),
        )
    )

    if not _DEBUG_SIGNING_CONFIG_ASSIGNMENT.search(text):
        violations.append(
            PolicyViolation(
                "lab-fallback-preserved",
                'signingConfigs.getByName("debug") is unreachable for the '
                "release buildType — the Lab/dev build (no production "
                "signing env) would fail to build (ADR 0448 D3)",
            )
        )

    return violations


# Only names carrying an actual signing PASSWORD — never the alias (not
# secret) and never the base64 keystore blob, which is legitimately
# `printf`'d into a `base64 --decode` pipe by the real workflow's
# "Materialize production keystore" step (that pipes binary bytes into a
# file, never a human-readable log line).
_SECRET_ENV_NAMES = (
    "ANDROID_STORE_PASSWORD",
    "ANDROID_KEY_PASSWORD",
    "STRUMSIGHT_RELEASE_STORE_PASSWORD",
    "STRUMSIGHT_RELEASE_KEY_PASSWORD",
)
_SECRET_NAME_GROUP = "|".join(_SECRET_ENV_NAMES)

# The one masking idiom ADR 0448 D5 REQUIRES before a secret is used
# (`echo "::add-mask::$NAME"`) is not itself a leak — it is GitHub Actions'
# own masking directive, and a *whole line* consisting of nothing else. The
# match is intentionally narrow (anchored start-to-end) so it excludes only
# that exact idiom: a same-line `echo "::add-mask::$NAME and then $NAME"`
# would NOT match this pattern and would still trip the rule below.
_MASK_DIRECTIVE_OF_SECRET_ONLY = re.compile(
    r'^\s*echo\s+"::add-mask::\$\{?(?:' + _SECRET_NAME_GROUP + r')\}?"\s*$'
)
_ECHO_LIKE_COMMAND = re.compile(r"\b(echo|printf|cat)\b")
# Plain shell reference: $NAME or ${NAME}.
_SECRET_SHELL_VAR_REFERENCE = re.compile(r"\$\{?(?:" + _SECRET_NAME_GROUP + r")\}?\b")
# GitHub Actions interpolation: ${{ secrets.NAME }} / ${{ env.NAME }} — the
# `$` and the name are separated by `{{ secrets.`/`{{ env.`, so the plain
# shell pattern above never matches it; this is a distinct leak shape.
_SECRET_ACTIONS_INTERPOLATION = re.compile(
    r"\$\{\{\s*(?:secrets|env)\.(?:" + _SECRET_NAME_GROUP + r")\s*\}\}"
)
_SET_X = re.compile(r"\bset\s+-\w*x\w*\b")


def _line_echoes_secret(line: str) -> bool:
    if _MASK_DIRECTIVE_OF_SECRET_ONLY.match(line):
        return False
    if not _ECHO_LIKE_COMMAND.search(line):
        return False
    return bool(
        _SECRET_SHELL_VAR_REFERENCE.search(line)
        or _SECRET_ACTIONS_INTERPOLATION.search(line)
    )


def _echoes_secret(text: str) -> bool:
    return any(_line_echoes_secret(line) for line in text.split("\n"))


def check_workflow(text: str) -> list[PolicyViolation]:
    violations: list[PolicyViolation] = []

    if "needs: signing-prerequisites" not in text:
        violations.append(
            PolicyViolation(
                "secrets-checked-before-build",
                "the release-apk job does not declare "
                '"needs: signing-prerequisites" — the build could run '
                "before the required secrets are verified",
            )
        )

    if _echoes_secret(text):
        violations.append(
            PolicyViolation(
                "keystore-not-echoed",
                "a signing password env var appears to be echoed/printed/catted",
            )
        )
    if _SET_X.search(text):
        violations.append(
            PolicyViolation(
                "keystore-not-echoed",
                'a "set -x"-shaped line was found — this echoes every '
                "subsequent command, including any secret arguments",
            )
        )

    if not re.search(r"if:\s*always\(\)", text):
        violations.append(
            PolicyViolation(
                "keystore-cleanup-present",
                'no "if: always()" step found — a failed build could leave '
                "the materialized keystore on the runner disk",
            )
        )
    elif "rm -f" not in text:
        violations.append(
            PolicyViolation(
                "keystore-cleanup-present",
                'an "if: always()" step exists but no "rm -f" cleanup of the '
                "keystore was found",
            )
        )

    return violations


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gradle", default="android/app/build.gradle.kts")
    parser.add_argument("--workflow", default=".github/workflows/release-apk.yml")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args(argv)

    gradle_path = Path(args.gradle)
    workflow_path = Path(args.workflow)

    try:
        gradle_text = gradle_path.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"verify_signing_policy: gradle file not found: {gradle_path}", file=sys.stderr)
        return 1
    try:
        workflow_text = workflow_path.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"verify_signing_policy: workflow file not found: {workflow_path}", file=sys.stderr)
        return 1

    violations = check_gradle(gradle_text) + check_workflow(workflow_text)

    if violations:
        for violation in violations:
            print(f"VIOLATION {violation}")
    else:
        print("signing policy: all rules satisfied")
        print(f"  gradle: {gradle_path}")
        print(f"  workflow: {workflow_path}")

    if violations and args.strict:
        for violation in violations:
            print(f"verify_signing_policy: {violation}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
