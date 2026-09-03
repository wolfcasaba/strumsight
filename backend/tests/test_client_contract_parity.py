"""E15-R12 -- client<->backend endpoint contract parity (ADR 0497 D5).

A5 (round brief §6): every endpoint the Flutter client actually calls
(measured by grep across ``lib/**``, not a wishlist — brief §0.0 R6) must
exist in the live app's OpenAPI schema. Drift ("the screen stays empty")
is a red test cell here, not a runtime symptom a user discovers.

``docs/contracts/client-backend-endpoints.json`` is the measured artifact.
Two statuses:

* ``"mounted"``   -- asserted PRESENT in ``app.openapi()["paths"]``. This
  is the A5 cell.
* ``"known_gap"`` -- the client calls it, but no backend route exists yet
  (a pre-existing drift outside this round's ``allowed_paths`` — see the
  entry's ``note``). Asserted ABSENT as a canary: if a future round
  implements the route, this assertion breaks and forces the contract
  file to be updated to ``"mounted"`` instead of silently going stale.
"""

from __future__ import annotations

import json
from pathlib import Path

from app.config import Settings
from app.main import create_app

_REPO_ROOT = Path(__file__).resolve().parents[2]
_CONTRACT_PATH = _REPO_ROOT / "docs" / "contracts" / "client-backend-endpoints.json"

_VALID_METHODS = frozenset({"GET", "POST", "PUT", "PATCH", "DELETE"})
_VALID_STATUSES = frozenset({"mounted", "known_gap"})


def _load_contract() -> dict:
    return json.loads(_CONTRACT_PATH.read_text())


def _fully_mounted_settings() -> Settings:
    """Every optional surface ON so the OpenAPI schema carries every route
    the contract could reference. A5 measures presence, not the flag
    gating itself (that is ``test_community_mounting.py``'s job)."""
    return Settings(
        _env_file=None,
        database_url="sqlite://",
        tutor_enabled=True,
        community_enabled=True,
        community_writes_enabled=True,
        community_media_enabled=True,
        community_leaderboard_enabled=True,
        community_clubs_enabled=True,
    )


def _openapi_paths() -> dict:
    app = create_app(_fully_mounted_settings())
    return app.openapi()["paths"]


def _missing_mounted_entries(paths: dict, entries: list[dict]) -> list[dict]:
    """The ``"mounted"`` entries whose method+path are NOT present."""
    missing = []
    for entry in entries:
        if entry["status"] != "mounted":
            continue
        operations = paths.get(entry["path"], {})
        if entry["method"].lower() not in operations:
            missing.append(entry)
    return missing


def _present_known_gap_entries(paths: dict, entries: list[dict]) -> list[dict]:
    """The ``"known_gap"`` entries that now DO exist — the canary."""
    present = []
    for entry in entries:
        if entry["status"] != "known_gap":
            continue
        operations = paths.get(entry["path"], {})
        if entry["method"].lower() in operations:
            present.append(entry)
    return present


def test_contract_file_is_well_formed():
    contract = _load_contract()
    entries = contract["endpoints"]
    assert entries, "contract must list at least one measured endpoint"
    seen = set()
    for entry in entries:
        assert entry["status"] in _VALID_STATUSES, entry
        assert entry["method"] in _VALID_METHODS, entry
        assert entry["path"].startswith("/"), entry
        assert entry["source"], entry
        if entry["status"] == "known_gap":
            assert entry.get("note"), f"known_gap entry needs a note: {entry}"
        key = (entry["method"], entry["path"])
        assert key not in seen, f"duplicate contract entry: {key}"
        seen.add(key)


def test_a5_every_mounted_client_call_exists_in_openapi():
    contract = _load_contract()
    paths = _openapi_paths()
    missing = _missing_mounted_entries(paths, contract["endpoints"])
    assert not missing, (
        "client-backend-endpoints.json lists these as 'mounted' but they "
        f"are absent from the live OpenAPI schema (client<->server drift): {missing}"
    )


def test_known_gap_entries_stay_unimplemented_or_the_contract_is_stale():
    """Canary: a 'known_gap' entry that now exists server-side means this
    contract file is lying about its status — flip it to 'mounted'."""
    contract = _load_contract()
    paths = _openapi_paths()
    present = _present_known_gap_entries(paths, contract["endpoints"])
    assert not present, (
        "these entries are marked 'known_gap' but now exist in the OpenAPI "
        f"schema — update their status to 'mounted': {present}"
    )


def test_a5_real_violation_probe_missing_route_is_caught():
    """§6.1 valódi-sértés próba: simulate a server-side route rename by
    deleting one 'mounted' entry's path from a COPY of the OpenAPI paths
    dict, and assert the same checker A5 uses reports it as missing. Never
    touches the real app or any router file — proves the parity check is
    falsifiable, not vacuous.
    """
    contract = _load_contract()
    entries = contract["endpoints"]
    target = next(e for e in entries if e["status"] == "mounted")

    paths = dict(_openapi_paths())
    paths.pop(target["path"], None)

    missing = _missing_mounted_entries(paths, entries)
    assert target in missing
