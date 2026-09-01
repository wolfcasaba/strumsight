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
alone — they name no email/path/token/device-id pattern. Object KEYS go
through the same email/path text redaction as values do (D2.1), after the
token/device-id key classification above has already decided the value —
two distinct keys colliding onto the same redacted key is a hard error
(D4 forbids a disambiguating salt/hash/suffix).

D2.1 (added after the round's review, 2026-09-01): opaque binary payload
fields (`wavBase64`) are NOT run through string redaction — the base64
alphabet contains "/", which the absolute-path pattern would otherwise
mistake for path separators and silently mangle a consented audio clip.
Instead, the raw-audio path is protected by content-based discovery (D3.1)
plus an explicit integrity check: the packaged clip must still decode to
the exact byte length it had on input, or the run is a hard error.

The raw-audio size cap (D3) is the MEASURED
`DiagnosticsUploader.maxWavBytes` (lib/features/diagnostics/data/
diagnostics_uploader.dart:40) = 5 * 1024 * 1024 = 5,242,880 bytes,
INCLUSIVE — exactly that many decoded bytes is still accepted. Going over
is a hard, non-zero-exit rejection with NO output file, never a silent
truncation: this tool is producing diagnostic evidence, where quietly
cutting the clip short would misrepresent what was actually recorded (the
opposite of the client uploader, which decimates on purpose).

D3.1 (added after the round's review): the raw-audio gate and the size cap
are CONTENT-based, not tied to the top-level `audioClips` key name — the
tool recursively finds every `wavBase64` field at any nesting depth,
removes all of them when `--consent-raw-audio` is absent, and sums all of
them (wherever they live) against the cap when it is present. Gzip
decompression of the stored session is bounded for the same reason: the
router stores an upload's bytes verbatim, so this tool's input is untrusted
by construction.

Output is canonical JSON (object keys sorted ascending at every nesting
level, UTF-8, a single trailing newline) — the same contract ADR 0447 D1
states for the release manifest — and carries no generation timestamp,
hostname or absolute filesystem path of its own. The output file is
written 0600, refusing to follow a symlink at `--output` (N2) — a bundle
carries consented tester data, and in the raw-audio case, recorded audio.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import gzip
import io
import json
import os
import re
import sys
from pathlib import Path

# Measured, not invented — lib/features/diagnostics/data/diagnostics_uploader.dart:40.
MAX_RAW_AUDIO_BYTES = 5 * 1024 * 1024

# Measured client upload budget (ADR 0486 D3.1): the raw-audio cap above,
# base64-encoded, is ceil(5,242,880 / 3) * 4 = 6,990,508 characters. This is
# the decompressed-session bound: that base64 payload plus a generous
# allowance for the surrounding JSON (event list, session/device metadata,
# quoting/braces) that a legitimate upload never needs to exceed — rounded
# up to a clean 8 MiB, comfortably above the base64 payload alone. Also used
# as the raw (possibly gzip-compressed) input FILE size bound: a session
# file bigger than the decompressed cap was never going to fit the upload
# contract either way. Anything past this is treated as hostile/malformed
# input, not a legitimate diagnostics session (the server stores whatever
# bytes it received verbatim, so this tool's input is untrusted).
MAX_SESSION_INPUT_BYTES = 8 * 1024 * 1024

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

# Closed list of opaque binary payload field names (ADR 0486 D2.1) — these
# carry base64-encoded audio, not free text, so they are excluded from
# string redaction and instead get a decode/byte-length integrity check.
_RAW_AUDIO_KEYS = frozenset({"wavBase64"})

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
    """A consent, input-shape, or size-cap failure — always fail-closed.

    NEVER include raw input content in a BundleError message (secrets,
    e-mail addresses, paths, device ids) — index/key-level identification
    only. The whole point of this tool is that the redacted bundle is the
    only place tester data goes; an error message is a channel too.
    """


def _redact_string(value: str) -> str:
    value = _EMAIL_PATTERN.sub(REDACTED_EMAIL, value)
    value = _WINDOWS_PATH_PATTERN.sub(REDACTED_PATH, value)
    value = _POSIX_PATH_PATTERN.sub(REDACTED_PATH, value)
    return value


def redact(value):
    """Recursively redacts [value] (ADR 0486 D2/D2.1) — every dict key/value
    pair at every nesting level, and every string value wherever it lives (a
    top-level field or nested inside a list of events). Opaque binary
    payload fields (`_RAW_AUDIO_KEYS`) are passed through unredacted — see
    the module docstring and D2.1."""
    if isinstance(value, dict):
        result = {}
        for key, sub_value in value.items():
            if _TOKEN_KEY_PATTERN.search(key):
                new_value = REDACTED_TOKEN
            elif key in _DEVICE_ID_KEYS:
                new_value = REDACTED_DEVICE_ID
            elif key in _RAW_AUDIO_KEYS:
                new_value = sub_value
            else:
                new_value = redact(sub_value)
            new_key = _redact_string(key)
            if new_key in result:
                raise BundleError(
                    "two distinct session keys collide onto the same "
                    f'redacted key "{new_key}"'
                )
            result[new_key] = new_value
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


def _strip_raw_audio_fields(value):
    """Recursively drops every `_RAW_AUDIO_KEYS` field at any nesting depth
    (ADR 0486 D3.1) — the raw-audio gate is content-based, not tied to the
    top-level `audioClips` key alone."""
    if isinstance(value, dict):
        return {
            key: _strip_raw_audio_fields(sub_value)
            for key, sub_value in value.items()
            if key not in _RAW_AUDIO_KEYS
        }
    if isinstance(value, list):
        return [_strip_raw_audio_fields(item) for item in value]
    return value


def _iter_raw_audio_fields(value, path: str):
    """Yields `(path, wavBase64_value)` for every opaque binary payload
    field found at any nesting depth in [value] — the content-based
    discovery ADR 0486 D3.1 requires. `path` is index/key-level only, never
    the field's own content, so it is always safe to put in an error
    message."""
    if isinstance(value, dict):
        for key, sub_value in value.items():
            sub_path = f"{path}.{key}"
            if key in _RAW_AUDIO_KEYS:
                yield (sub_path, sub_value)
            else:
                yield from _iter_raw_audio_fields(sub_value, sub_path)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _iter_raw_audio_fields(item, f"{path}[{index}]")


def _decode_raw_audio_field(path: str, value) -> bytes:
    if not isinstance(value, str):
        raise BundleError(f"malformed audio payload at {path}: expected a base64 string")
    try:
        return base64.b64decode(value, validate=True)
    except (TypeError, binascii.Error) as error:
        raise BundleError(f"malformed audio payload base64 at {path}: {error}") from error


def _validate_audio_clips_shape(session: dict) -> None:
    """Validates the documented top-level `audioClips` array shape — a list
    of dicts each carrying `wavBase64`. Index-only identity in the error
    (B1): never the clip's own content."""
    audio_clips = session.get("audioClips", [])
    if not isinstance(audio_clips, list):
        raise BundleError('session "audioClips" must be a list')
    for index, clip in enumerate(audio_clips):
        if not isinstance(clip, dict) or "wavBase64" not in clip:
            raise BundleError(
                f'malformed audio clip at audioClips[{index}]: missing "wavBase64"'
            )


def _total_raw_audio_bytes(session: dict) -> int:
    total = 0
    for path, value in _iter_raw_audio_fields(session, "session"):
        total += len(_decode_raw_audio_field(path, value))
    return total


def _verify_raw_audio_integrity(original_session: dict, redacted_session: dict) -> None:
    """ADR 0486 D2.1: the packaged clip(s) must still decode to the exact
    byte length they had on input — proof that redaction did not silently
    mangle a consented audio clip (the M1 failure mode)."""
    original_fields = list(_iter_raw_audio_fields(original_session, "session"))
    redacted_fields = list(_iter_raw_audio_fields(redacted_session, "session"))
    if len(original_fields) != len(redacted_fields):
        raise BundleError(
            "raw audio field count changed during redaction: "
            f"{len(original_fields)} -> {len(redacted_fields)}"
        )
    for (path, original_value), (_, redacted_value) in zip(
        original_fields, redacted_fields
    ):
        original_length = len(_decode_raw_audio_field(path, original_value))
        redacted_length = len(_decode_raw_audio_field(path, redacted_value))
        if redacted_length != original_length:
            raise BundleError(
                f"raw audio payload at {path} changed size during redaction: "
                f"{original_length} -> {redacted_length} bytes"
            )


def _read_bounded_file(path: Path, limit: int) -> bytes:
    try:
        with path.open("rb") as handle:
            data = handle.read(limit + 1)
    except OSError as error:
        raise BundleError(f"cannot read session file: {error}") from error
    if len(data) > limit:
        raise BundleError(f"session file exceeds the {limit}-byte input cap")
    return data


def _decompress_bounded(raw: bytes, limit: int) -> bytes:
    """Incremental, chunk-bounded gzip decompression — never allocates more
    than `limit` (plus one chunk) of decompressed data, regardless of how
    large the compressed input claims to expand to (ADR 0486 D3.1 —
    protects against a decompression bomb on untrusted, verbatim-stored
    upload bytes)."""
    chunks = []
    total = 0
    chunk_size = 64 * 1024
    try:
        with gzip.GzipFile(fileobj=io.BytesIO(raw)) as gz:
            while True:
                chunk = gz.read(chunk_size)
                if not chunk:
                    break
                total += len(chunk)
                if total > limit:
                    raise BundleError(
                        f"decompressed session payload exceeds the {limit}-byte cap"
                    )
                chunks.append(chunk)
    except OSError as error:
        raise BundleError(f"session file is not valid gzip: {error}") from error
    return b"".join(chunks)


def _load_session(session_path: Path) -> dict:
    raw = _read_bounded_file(session_path, MAX_SESSION_INPUT_BYTES)

    if raw[:2] == b"\x1f\x8b":
        raw = _decompress_bounded(raw, MAX_SESSION_INPUT_BYTES)

    try:
        session = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise BundleError(f"session payload is not valid JSON: {error}") from error

    if not isinstance(session, dict):
        raise BundleError("session payload must be a JSON object")
    return session


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
        redacted_session = _strip_raw_audio_fields(redacted_session)
    return {
        "schemaVersion": DIAGNOSTICS_BUNDLE_SCHEMA_VERSION,
        "session": redacted_session,
    }


def _write_output_file(path: Path, data: bytes) -> None:
    """Writes [data] to [path] mode 0600, refusing to follow a symlink
    (N2) — the bundle carries consented tester data (and, under
    --consent-raw-audio, recorded audio)."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as error:
        raise BundleError(f"cannot write output file: {error}") from error
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
    except OSError as error:
        raise BundleError(f"cannot write output file: {error}") from error


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
            _validate_audio_clips_shape(session)
            total_audio_bytes = _total_raw_audio_bytes(session)
            if total_audio_bytes > MAX_RAW_AUDIO_BYTES:
                raise BundleError(
                    f"raw audio attachment is {total_audio_bytes} bytes, "
                    f"exceeding the {MAX_RAW_AUDIO_BYTES}-byte cap — "
                    "rejected, not truncated"
                )

        bundle = build_bundle(session, include_raw_audio=include_raw_audio)
        if include_raw_audio:
            _verify_raw_audio_integrity(session, bundle["session"])
        output_bytes = canonical_json_bytes(bundle)
        _write_output_file(Path(args.output), output_bytes)
    except BundleError as error:
        print(f"build_diagnostics_bundle: {error}", file=sys.stderr)
        return 1
    except Exception:
        # NT1: any exception this tool did not anticipate (RecursionError,
        # MemoryError, ...) still fails closed, without leaking a raw
        # traceback (which can quote input content) to stderr.
        print(
            "build_diagnostics_bundle: internal error while building the "
            "bundle",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
