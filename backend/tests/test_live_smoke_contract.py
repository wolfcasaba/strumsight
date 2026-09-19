"""E16-R04 — live_backend_smoke.py contract cells (round brief §6, §7,
ADR 0503).

`tool/release/live_backend_smoke.py`'s `run_chain()` accepts any client
exposing `.get(path, headers=)` / `.post(path, json=, headers=)` /
`.put(path, json=, headers=)` — this file passes it a REAL
`fastapi.testclient.TestClient` around a fully migrated, lab-profile,
Community-enabled `create_app()` app, so the same functions the CLI calls
against a live LAN deploy are exercised here, in process, with no network
(ADR 0503 D4).

Acceptance-map:
  A1  test_classify_contract_covers_the_real_contract_with_no_unclassified_entries
      test_classify_contract_fails_closed_on_an_uncovered_mounted_entry
      test_main_exits_2_on_an_unclassified_contract_without_touching_the_network
  A2  test_full_chain_passes_against_a_freshly_migrated_lab_app
      test_chain_halts_at_the_first_divergence_and_later_steps_never_run
      test_challenge_listing_divergence_turns_the_chain_red_without_running_later_steps
  A5  every cell in this file drives an in-process TestClient — no socket is
      ever opened (offline gate, ADR 0503 D4).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from alembic.config import Config
from fastapi.testclient import TestClient

from alembic import command
from app.config import Settings
from app.main import create_app

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_REPO_ROOT = _BACKEND_ROOT.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tool.release import live_backend_smoke as smoke  # noqa: E402

_REAL_CONTRACT_PATH = (
    _REPO_ROOT / "docs" / "contracts" / "client-backend-endpoints.json"
)


def _alembic_config() -> Config:
    config = Config(str(_BACKEND_ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    return config


def _migrated_lab_settings(tmp_path: Path, monkeypatch, **overrides) -> Settings:
    """A migrated-to-head, lab-profile, Community-enabled `Settings` — the
    ADR 0449 D1 traffic gate does not even apply outside staging/prod
    (`main.py::_TRAFFIC_GATE_ENVIRONMENTS`), matching ADR 0503 D3's "a
    dev/lab instance, not a production deploy" framing."""
    database_url = f"sqlite:///{tmp_path / 'live-smoke-contract.db'}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", database_url)
    command.upgrade(_alembic_config(), "head")
    defaults = dict(
        env="lab",
        database_url=database_url,
        community_enabled=True,
    )
    defaults.update(overrides)
    return Settings(**defaults)


class _CountingClient:
    """Wraps a real `TestClient` and counts every `.get`/`.post`/`.put`
    call — the A2 "later steps never run" proof (D2) needs a way to show
    the chain did not merely stop REPORTING after a divergence but
    actually stopped CALLING."""

    def __init__(self, inner) -> None:
        self._inner = inner
        self.call_count = 0

    def get(self, path, *, headers=None):
        self.call_count += 1
        return self._inner.get(path, headers=headers)

    def post(self, path, *, json=None, headers=None):
        self.call_count += 1
        return self._inner.post(path, json=json, headers=headers)

    def put(self, path, *, json=None, headers=None):
        self.call_count += 1
        return self._inner.put(path, json=json, headers=headers)


# ---------------------------------------------------------------------------
# A1 — every contract entry gets a classification, fail-closed on gaps
# ---------------------------------------------------------------------------


def test_classify_contract_covers_the_real_contract_with_no_unclassified_entries():
    entries = smoke.load_contract(_REAL_CONTRACT_PATH)
    assert len(entries) == 39

    classifications = smoke.classify_contract(entries)
    by_kind: dict[str, int] = {}
    for classification in classifications:
        by_kind[classification.kind] = by_kind.get(classification.kind, 0) + 1
        assert classification.reason.strip(), classification

    assert by_kind.get("unclassified", 0) == 0, [
        c for c in classifications if c.kind == "unclassified"
    ]
    assert by_kind == {"exercised": 13, "not_exercised": 26}


def test_classify_contract_fails_closed_on_an_uncovered_mounted_entry():
    """§6.1 mátrix — a new client-called endpoint added to the contract
    without a matching entry in `_EXERCISED_ORDER`/`_NOT_EXERCISED` must
    come back "unclassified", not silently disappear."""
    entries = [
        smoke.ContractEndpoint(
            method="GET", path="/community/never-classified", status="mounted"
        )
    ]
    classifications = smoke.classify_contract(entries)
    assert len(classifications) == 1
    assert classifications[0].kind == "unclassified"


def test_main_exits_2_on_an_unclassified_contract_without_touching_the_network(
    tmp_path, capsys
):
    """`main()` must refuse to even attempt the network chain when the
    contract carries an uncovered entry (D1) — proven here by pointing
    `--base-url` at a port nothing listens on and confirming the exit code
    is the usage/config code (2), not a network-failure code."""
    contract_path = tmp_path / "stale-contract.json"
    contract_path.write_text(
        json.dumps(
            {
                "endpoints": [
                    {
                        "method": "GET",
                        "path": "/community/never-classified",
                        "status": "mounted",
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    exit_code = smoke.main(
        ["--base-url", "http://127.0.0.1:1", "--contract", str(contract_path)]
    )

    assert exit_code == 2
    captured = capsys.readouterr()
    assert "unclassified" in captured.err


# ---------------------------------------------------------------------------
# A2 — the chain runs the full contract-derived bring-up sequence, and
# stops dead at the first divergence
# ---------------------------------------------------------------------------


def test_full_chain_passes_against_a_freshly_migrated_lab_app(tmp_path, monkeypatch):
    settings = _migrated_lab_settings(tmp_path, monkeypatch)
    app = create_app(settings)

    with TestClient(app) as client:
        steps = smoke.run_chain(
            client,
            email="live-smoke-full-chain@strumsight.app",
            password="live-smoke-fake-correct-horse",
        )

    assert [step.name for step in steps] == [
        "readiness",
        "register",
        "login",
        "auth_me",
        "settings_read",
        "settings_write",
        "community_profile_create",
        "community_profile_read",
        "community_profile_update",
        "community_blocked",
        "community_muted",
        "community_challenges",
        "community_notifications",
        "community_notification_preferences",
    ]
    for step in steps:
        assert step.ok, f"{step.name} unexpectedly failed: {step.detail}"


def test_chain_halts_at_the_first_divergence_and_later_steps_never_run(
    tmp_path, monkeypatch
):
    """ADR 0503 D2. Pre-registering the email OUTSIDE the chain forces the
    chain's OWN `register` call to 409 — the first possible divergence
    point — and proves every later step (login, auth_me, settings,
    community, challenges) is never even called, not merely unreported."""
    settings = _migrated_lab_settings(tmp_path, monkeypatch)
    app = create_app(settings)
    email = "live-smoke-halts@strumsight.app"

    with TestClient(app) as raw_client:
        pre_register = raw_client.post(
            "/auth/register", json={"email": email, "password": "fake-already-here"}
        )
        assert pre_register.status_code == 201, pre_register.text

        counting_client = _CountingClient(raw_client)
        steps = smoke.run_chain(
            counting_client, email=email, password="fake-a-different-password"
        )

    assert [step.name for step in steps] == ["readiness", "register"]
    assert steps[0].ok is True
    assert steps[1].ok is False
    assert "expected POST /auth/register -> 201, got 409" in steps[1].detail
    # readiness (1) + register (1) = 2 calls through the chain itself. The
    # pre-registration call above used `raw_client` directly, not the
    # counting wrapper, so it does not inflate this count.
    assert counting_client.call_count == 2


class _DivertingClient(_CountingClient):
    """`_CountingClient` that answers ONE `GET` path with a canned
    response instead of forwarding it — the duck-typed client contract
    (`.get`/`.post`/`.put` returning something with `.status_code` and
    `.json()`) is exactly what the CLI's `UrllibClient` offers, so a
    diverted step is indistinguishable from a live deploy answering that
    status."""

    def __init__(self, inner, *, divert_path: str, response) -> None:
        super().__init__(inner)
        self._divert_path = divert_path
        self._response = response

    def get(self, path, *, headers=None):
        if path == self._divert_path:
            self.call_count += 1
            return self._response
        return super().get(path, headers=headers)


def test_challenge_listing_divergence_turns_the_chain_red_without_running_later_steps(
    tmp_path, monkeypatch
):
    """§6.1 mátrix, D2 on the LAST step: the challenge listing used to be
    a known_gap probe (404 expected); now that the route is mounted the
    chain expects 200 there, and a deploy that still answers 404 (an
    older backend behind a newer contract) must turn the chain RED at
    exactly that step — with the whole earlier chain intact and nothing
    after it called."""
    settings = _migrated_lab_settings(tmp_path, monkeypatch)
    app = create_app(settings)

    with TestClient(app) as client:
        diverting_client = _DivertingClient(
            client,
            divert_path="/community/challenges",
            response=smoke.Response(status_code=404, body=b'{"detail": "Not Found"}'),
        )
        steps = smoke.run_chain(
            diverting_client,
            email="live-smoke-stale-deploy@strumsight.app",
            password="live-smoke-fake-correct-horse",
        )

    assert steps[-1].name == "community_challenges"
    assert "community_notifications" not in [s.name for s in steps]
    assert steps[-1].ok is False
    assert "expected GET /community/challenges -> 200, got 404" in steps[-1].detail
    assert all(step.ok for step in steps[:-1]), [s.name for s in steps if not s.ok]
    # readiness + register + login + auth_me + settings ×2 + profile ×3 +
    # blocked + muted + challenges = 12 calls, and not one more.
    assert diverting_client.call_count == 12
