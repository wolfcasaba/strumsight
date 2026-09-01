#!/usr/bin/env python3
"""Redacted, layered-consent Lab-mode diagnostics bundle (ADR 0486).

Takes ONE stored diagnostics session payload exactly as
`backend/app/routers/diagnostics.py` persists it — gzipped JSON (the
client's normal `Content-Encoding: gzip` upload) OR raw JSON bytes, since
the router stores whatever bytes it received verbatim — and produces a
redacted, deterministic bundle file for a beta tester's feedback report.

Two independent consent gates (D1), neither a substitute for the other:

  --consent-diagnostics   required for ANY bundle at all. Missing it is a
                           non-zero exit and NO output file is written.
  --consent-raw-audio     required, ON TOP of --consent-diagnostics, for the
                           bundle to carry the session's recorded audio
                           clips. Given alone (without --consent-diagnostics)
                           it grants nothing — still a non-zero exit.

The redaction (D2) runs BEFORE anything is written, recursively over the
whole parsed session structure, at both key and string-value level, across
four classes: token (key contains "token", case-insensitive), e-mail (a
match anywhere in any string value), absolute filesystem path (POSIX or
Windows, anywhere in any string value), and device identifier (an EXACT
`deviceId`/`device_id`/`androidId`/`installId`/`udid` key). The replacement
is always the same constant string per class — no salt, no hash, no
sequence number, because two runs on the same input must be byte-identical
(D4). `appVersion`/`device` (the platform-correlation strings the data
inventory calls `device_metadata`) are ordinary keys here and are left
alone — they name no email/path/token/device-id pattern.

The raw-audio size cap (D3) is the MEASURED
`DiagnosticsUploader.maxWavBytes` (lib/features/diagnostics/data/
diagnostics_uploader.dart:40) = 5 * 1024 * 1024 = 5,242,880 bytes,
INCLUSIVE — exactly that many decoded bytes is still accepted. Going over
is a hard, non-zero-exit rejection with NO output file, never a silent
truncation: this tool is producing diagnostic evidence, where quietly
cutting the clip short would misrepresent what was actually recorded (the
opposite of the client uploader, which decimates on purpose).

Output is canonical JSON (object keys sorted ascending at every nesting
level, UTF-8, a single trailing newline) — the same contract ADR 0447 D1
states for the release manifest — and carries no generation timestamp,
hostname or absolute filesystem path of its own.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import gzip
import json
import re
import sys
from pathlib import Path

# Measured, not invented — lib/features/diagnostics/data/diagnostics_uploader.dart:40.
MAX_RAW_AUDIO_BYTES = 5 * 1024 * 1024

DIAGNOSTICS_BUNDLE_SCHEMA_VERSION = 1

REDACTED_TOKEN = "[REDACTED:token]"
REDACTED_EMAIL = "[REDACTED:email]"
REDACTED_PATH = "[REDACTED:path]"
REDACTED_DEVICE_ID = "[REDACTED:device-id]"

_TOKEN_KEY_PATTERN = re.compile("token", re.IGNORECASE)

# Exact spellings only (ADR 0486 D2) — this is a closed list, not a
# substring/case-insensitive heuristic like the token class.
_DEVICE_ID_KEYS = frozenset(
    {"deviceId", "device_id", "androidId", "installId", "udid"}
)

# Bounded quantifiers (local part <=64, domain <=253 — the RFC 5321 caps)
# are deliberate, not cosmetic: an UNBOUNDED `+` before a literal `@` that
# never appears degrades to O(n^2) backtracking over a long run of
# matching characters — exactly what a multi-megabyte base64 `wavBase64`
# string is. The bound keeps every class linear in the input length
# regardless of what the string actually contains.
_EMAIL_PATTERN = re.compile(
    r"[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9.\-]{1,253}\.[A-Za-z]{2,24}"
)

# An absolute POSIX path: a leading "/" followed by TWO OR MORE
# slash-separated segments, none containing whitespace or a quote (which
# would signal the match ran past the intended token into surrounding
# prose). The two-segment floor is deliberate: this app's own domain data
# includes slash-bass chord labels ("C/E", "Am7/G"), which are exactly a
# single "/segment" and must never be mistaken for an absolute path. Each
# segment is length-bounded (see the email pattern above for why) — real
# path segments are at most a filesystem's NAME_MAX (255 on every target
# platform here), and an unbounded segment risks O(n^2) backtracking over
# a long slash-bearing string such as base64 audio data.
_POSIX_PATH_PATTERN = re.compile(r'(?:/[^\s"\'/]{1,255}){2,}/?')

# An absolute Windows path: a drive letter, colon, backslash, then
# backslash-separated segments (same length bound as the POSIX pattern).
_WINDOWS_PATH_PATTERN = re.compile(
    r'[A-Za-z]:\\(?:[^\\\s"\']{1,255}\\)*[^\\\s"\']{0,255}'
)


class BundleError(Exception):
    """A consent, input-shape, or size-cap failure — always fail-closed."""


def _redact_string(value: str) -> str:
    value = _EMAIL_PATTERN.sub(REDACTED_EMAIL, value)
    value = _WINDOWS_PATH_PATTERN.sub(REDACTED_PATH, value)
    value = _POSIX_PATH_PATTERN.sub(REDACTED_PATH, value)
    return value


def redact(value):
    """Recursively redacts [value] (ADR 0486 D2) — every dict key/value pair
    at every nesting level, and every string value wherever it lives (a
    top-level field or nested inside a list of events)."""
    if isinstance(value, dict):
        result = {}
        for key, sub_value in value.items():
            if _TOKEN_KEY_PATTERN.search(key):
                result[key] = REDACTED_TOKEN
            elif key in _DEVICE_ID_KEYS:
                result[key] = REDACTED_DEVICE_ID
            else:
                result[key] = redact(sub_value)
        return result
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, str):
        return _redact_string(value)
    return value


def _should_include_raw_audio(consent_raw_audio: bool) -> bool:
    # ADR 0486 D1: the raw-audio layer is opt-in on top of diagnostics
    # consent, never default-on just because Lab mode itself is opt-in.
    return consent_raw_audio


def _load_session(session_path: Path) -> dict:
    try:
        raw = session_path.read_bytes()
    except OSError as error:
        raise BundleError(f"cannot read session file: {error}") from error

    if raw[:2] == b"\x1f\x8b":
        try:
            raw = gzip.decompress(raw)
        except OSError as error:
            raise BundleError(f"session file is not valid gzip: {error}") from error

    try:
        session = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BundleError(f"session payload is not valid JSON: {error}") from error

    if not isinstance(session, dict):
        raise BundleError("session payload must be a JSON object")
    return session


def _raw_audio_byte_count(session: dict) -> int:
    audio_clips = session.get("audioClips", [])
    if not isinstance(audio_clips, list):
        raise BundleError('session "audioClips" must be a list')
    total = 0
    for clip in audio_clips:
        if not isinstance(clip, dict) or "wavBase64" not in clip:
            raise BundleError(f"malformed audio clip: {clip!r}")
        try:
            total += len(base64.b64decode(clip["wavBase64"], validate=True))
        except (TypeError, binascii.Error) as error:
            raise BundleError(f"malformed audio clip base64: {error}") from error
    return total


def canonical_json_bytes(value) -> bytes:
    """ADR 0447 D1 / ADR 0486 D4: object keys sorted ascending at every
    nesting level (`sort_keys=True` applies recursively), UTF-8, a single
    trailing newline — no timestamp, no non-determinism."""
    text = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return (text + "\n").encode("utf-8")


def build_bundle(session: dict, *, include_raw_audio: bool) -> dict:
    redacted_session = redact(session)
    if not include_raw_audio:
        redacted_session.pop("audioClips", None)
    return {
        "schemaVersion": DIAGNOSTICS_BUNDLE_SCHEMA_VERSION,
        "session": redacted_session,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--session-file", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--consent-diagnostics",
        action="store_true",
        help="Required for any bundle at all (ADR 0486 D1).",
    )
    parser.add_argument(
        "--consent-raw-audio",
        action="store_true",
        help="Required, on top of --consent-diagnostics, to include audio.",
    )
    args = parser.parse_args(argv)

    try:
        if not args.consent_diagnostics:
            raise BundleError(
                "--consent-diagnostics is required to build any bundle "
                "(a --consent-raw-audio flag alone grants nothing)"
            )

        session = _load_session(Path(args.session_file))
        include_raw_audio = _should_include_raw_audio(args.consent_raw_audio)

        if include_raw_audio:
            total_audio_bytes = _raw_audio_byte_count(session)
            if total_audio_bytes > MAX_RAW_AUDIO_BYTES:
                raise BundleError(
                    f"raw audio attachment is {total_audio_bytes} bytes, "
                    f"exceeding the {MAX_RAW_AUDIO_BYTES}-byte cap — "
                    "rejected, not truncated"
                )

        bundle = build_bundle(session, include_raw_audio=include_raw_audio)
        output_bytes = canonical_json_bytes(bundle)
    except BundleError as error:
        print(f"build_diagnostics_bundle: {error}", file=sys.stderr)
        return 1

    Path(args.output).write_bytes(output_bytes)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
