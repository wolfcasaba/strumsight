"""Backend-side redaction boundary (E12-R22, ADR 0486).

Measures the boundary ADR 0486 D2's "the server never redacts" decision
rests on: `backend/app/routers/diagnostics.py` stores an uploaded session
verbatim (already measured by `test_diagnostics.py`'s own
`test_diagnostics_stores_session_verbatim`), so THIS file proves the other
half of the same boundary — that a secret literally present in the
verbatim-stored bytes is masked once `tool/release/build_diagnostics_
bundle.py` assembles a bundle FROM that same stored file. Together the two
files are the "redaction is the packager's job, not the server's" contract:
the server keeps the plaintext on disk, the packager is the only place it
disappears — loaded via the `importlib.util.spec_from_file_location` +
`sys.modules[spec.name] = module` pattern `test_security_release.py`
establishes, required because `build_diagnostics_bundle.py` uses `from
__future__ import annotations`.
"""

from __future__ import annotations

import gzip
import importlib.util
import json
import sys
from pathlib import Path
from types import ModuleType

_REPO_ROOT = Path(__file__).resolve().parents[2]
_BUNDLE_MODULE_PATH = _REPO_ROOT / "tool" / "release" / "build_diagnostics_bundle.py"


def _load_bundle_module() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "strumsight_build_diagnostics_bundle_e12r22", _BUNDLE_MODULE_PATH
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    # build_diagnostics_bundle.py uses `from __future__ import annotations`,
    # so any lazily-resolved annotation needs the module registered in
    # sys.modules BEFORE exec_module runs (same reasoning as
    # test_security_release.py's own loader).
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


bundle_tool = _load_bundle_module()


def _configure_diagnostics(client, data_dir, *, token="secret"):
    client.app.state.settings.diag_token = token
    client.app.state.settings.diag_dir = str(data_dir)


def _fixture_session() -> dict:
    # Deliberately synthetic — no real tester data or real token, per the
    # round brief's explicit ban on real fixtures.
    return {
        "sessionId": "s1",
        "appVersion": "1.9.0",
        "device": "Pixel 9 (Android 15)",
        "startedAt": "2026-08-01T00:00:00Z",
        "surface": "analyze",
        "diagToken": "fixture-super-secret-token-value",
        "events": [
            {
                "tSec": 1.0,
                "mlChord": "G/B",
                "note": (
                    "reported by fixture-tester@example.test, log at "
                    "/data/local/tmp/fixture/session.log"
                ),
                "deviceId": "fixture-device-id-0001",
            }
        ],
        "audioClips": [],
    }


def test_server_stores_the_secret_verbatim_but_the_bundle_redacts_it(client, tmp_path):
    _configure_diagnostics(client, tmp_path)
    payload = json.dumps(_fixture_session()).encode("utf-8")

    response = client.post(
        "/diagnostics",
        content=payload,
        headers={"X-Diag-Token": "secret", "X-Session-Id": "redaction-fixture"},
    )
    assert response.status_code == 201, response.text

    stored_files = list(tmp_path.glob("*.bin"))
    assert len(stored_files) == 1
    stored_bytes = stored_files[0].read_bytes()

    # The verbatim-storage half of the boundary: the secret is still
    # there, in the plain, in exactly what the server persisted.
    assert stored_bytes == payload
    assert b"fixture-super-secret-token-value" in stored_bytes
    assert b"fixture-tester@example.test" in stored_bytes
    assert b"/data/local/tmp/fixture/session.log" in stored_bytes
    assert b"fixture-device-id-0001" in stored_bytes

    output_path = tmp_path / "bundle.json"
    exit_code = bundle_tool.main(
        [
            "--session-file",
            str(stored_files[0]),
            "--output",
            str(output_path),
            "--consent-diagnostics",
        ]
    )
    assert exit_code == 0
    bundle_text = output_path.read_text(encoding="utf-8")

    # The redaction half: none of the four secrets survive into the bundle
    # the tester actually sends — including the one nested inside
    # events[0], proving the redaction is recursive, not top-level only.
    assert "fixture-super-secret-token-value" not in bundle_text
    assert "fixture-tester@example.test" not in bundle_text
    assert "/data/local/tmp/fixture/session.log" not in bundle_text
    assert "fixture-device-id-0001" not in bundle_text
    assert "[REDACTED:token]" in bundle_text
    assert "[REDACTED:email]" in bundle_text
    assert "[REDACTED:path]" in bundle_text
    assert "[REDACTED:device-id]" in bundle_text
    # The slash-bass chord label must survive unredacted — the path
    # pattern's two-segment floor exists exactly to protect it.
    assert "G/B" in bundle_text


def test_server_stores_a_gzip_upload_verbatim_and_the_bundle_still_redacts_it(
    client, tmp_path
):
    """The router stores whatever bytes it received, gzip or raw
    (backend/app/routers/diagnostics.py header) — the bundler must handle
    both, since the client's normal upload path IS gzip-compressed."""
    _configure_diagnostics(client, tmp_path)
    compressed = gzip.compress(json.dumps(_fixture_session()).encode("utf-8"))

    response = client.post(
        "/diagnostics",
        content=compressed,
        headers={
            "X-Diag-Token": "secret",
            "X-Session-Id": "gzip-fixture",
            "Content-Encoding": "gzip",
        },
    )
    assert response.status_code == 201, response.text

    stored_files = list(tmp_path.glob("*.bin"))
    assert len(stored_files) == 1
    assert stored_files[0].read_bytes() == compressed

    output_path = tmp_path / "bundle_gzip.json"
    exit_code = bundle_tool.main(
        [
            "--session-file",
            str(stored_files[0]),
            "--output",
            str(output_path),
            "--consent-diagnostics",
        ]
    )
    assert exit_code == 0
    bundle_text = output_path.read_text(encoding="utf-8")
    assert "fixture-super-secret-token-value" not in bundle_text
    assert "[REDACTED:token]" in bundle_text


def test_bundle_without_diagnostics_consent_writes_no_output_file(client, tmp_path):
    _configure_diagnostics(client, tmp_path)
    payload = json.dumps({"sessionId": "s2", "events": [], "audioClips": []}).encode(
        "utf-8"
    )
    response = client.post(
        "/diagnostics",
        content=payload,
        headers={"X-Diag-Token": "secret", "X-Session-Id": "no-consent-fixture"},
    )
    assert response.status_code == 201, response.text
    stored_file = next(tmp_path.glob("*.bin"))

    output_path = tmp_path / "bundle_no_consent.json"
    exit_code = bundle_tool.main(
        ["--session-file", str(stored_file), "--output", str(output_path)]
    )
    assert exit_code != 0
    assert not output_path.exists()
