"""Lab-mode diagnostics collector: store, token gate, empty/oversize reject."""

import asyncio
import gzip
import json
import stat
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from starlette.requests import ClientDisconnect, Request

from app.routers import diagnostics


def _configure_diagnostics(client, data_dir, *, token="secret"):
    client.app.state.settings.diag_token = token
    client.app.state.settings.diag_dir = str(data_dir)


def _scripted_request(receive, data_dir, *, token="secret"):
    application = SimpleNamespace(
        state=SimpleNamespace(
            settings=SimpleNamespace(
                diag_token=token,
                diag_dir=str(data_dir),
            )
        )
    )
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/diagnostics",
            "headers": [],
            "app": application,
        },
        receive,
    )


def test_diagnostics_health(client, tmp_path):
    _configure_diagnostics(client, tmp_path)
    r = client.get("/diagnostics/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_diagnostics_dev_default_token_remains_usable(client, tmp_path):
    client.app.state.settings.diag_dir = str(tmp_path)
    assert client.app.state.settings.diag_token == "strumsight-lab-dev"

    response = client.post(
        "/diagnostics",
        content=b"dev-payload",
        headers={"X-Diag-Token": "strumsight-lab-dev"},
    )

    assert response.status_code == 201
    assert len(list(tmp_path.glob("*.bin"))) == 1


def test_diagnostics_rejects_bad_token(client, tmp_path, monkeypatch):
    _configure_diagnostics(client, tmp_path, token="server-secret")
    monkeypatch.setenv("STRUMSIGHT_DIAG_TOKEN", "ignored-env-secret")
    monkeypatch.setenv("STRUMSIGHT_DIAG_DIR", str(tmp_path / "ignored-env-dir"))
    r = client.post(
        "/diagnostics", content=b"x", headers={"X-Diag-Token": "submitted-secret"}
    )
    assert r.status_code == 401
    assert "server-secret" not in r.text
    assert "submitted-secret" not in r.text
    # Nothing was written.
    assert not list(tmp_path.glob("*.bin"))


def test_diagnostics_rejects_empty(client, tmp_path):
    _configure_diagnostics(client, tmp_path)
    r = client.post("/diagnostics", content=b"", headers={"X-Diag-Token": "secret"})
    assert r.status_code == 400
    assert not list(tmp_path.glob("*.tmp"))
    assert not list(tmp_path.glob("*.bin"))


def test_diagnostics_stores_session_verbatim(
    client,
    tmp_path,
    monkeypatch,
):
    _configure_diagnostics(client, tmp_path)
    replace_calls = []
    real_replace = diagnostics.os.replace

    def record_replace(source, destination):
        replace_calls.append((Path(source), Path(destination)))
        real_replace(source, destination)

    monkeypatch.setattr(diagnostics.os, "replace", record_replace)
    payload = gzip.compress(
        json.dumps({"sessionId": "s1", "surface": "live", "events": []}).encode()
    )
    r = client.post(
        "/diagnostics",
        content=payload,
        headers={
            "X-Diag-Token": "secret",
            "X-Session-Id": "s1",
            "Content-Encoding": "gzip",
            "X-App-Version": "lab1",
        },
    )
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "stored"
    bins = list(tmp_path.glob("*.bin"))
    assert len(bins) == 1
    assert len(replace_calls) == 1
    temp_path, final_path = replace_calls[0]
    assert temp_path.parent == tmp_path
    assert temp_path.suffix == ".tmp"
    assert final_path == bins[0]
    assert not temp_path.exists()
    # Stored byte-for-byte (server is dumb on purpose).
    assert bins[0].read_bytes() == payload
    assert stat.S_IMODE(bins[0].stat().st_mode) == 0o600
    # And indexed.
    index_path = tmp_path / "index.jsonl"
    assert stat.S_IMODE(index_path.stat().st_mode) == 0o600
    idx = index_path.read_text().strip().splitlines()
    assert len(idx) == 1
    rec = json.loads(idx[0])
    assert rec["app_version"] == "lab1"
    assert rec["content_encoding"] == "gzip"


def test_diagnostics_stops_reading_when_stream_exceeds_limit(
    tmp_path,
    monkeypatch,
):
    monkeypatch.setenv("STRUMSIGHT_DIAG_MAX_BYTES", "5")
    messages = iter(
        [
            {"type": "http.request", "body": b"1234", "more_body": True},
            {"type": "http.request", "body": b"56", "more_body": True},
        ]
    )
    reads = 0

    async def receive():
        nonlocal reads
        reads += 1
        try:
            return next(messages)
        except StopIteration as error:
            raise AssertionError("oversize stream was read past the limit") from error

    request = _scripted_request(receive, tmp_path)

    with pytest.raises(HTTPException) as error:
        asyncio.run(
            diagnostics.upload_diagnostics(
                request,
                x_diag_token="secret",
                x_session_id="oversize",
            )
        )

    assert error.value.status_code == 413
    assert reads == 2
    assert not list(tmp_path.iterdir())


def test_diagnostics_oversize_endpoint_returns_413(
    client,
    tmp_path,
    monkeypatch,
):
    _configure_diagnostics(client, tmp_path)
    monkeypatch.setenv("STRUMSIGHT_DIAG_MAX_BYTES", "5")

    response = client.post(
        "/diagnostics",
        content=b"123456",
        headers={"X-Diag-Token": "secret"},
    )

    assert response.status_code == 413
    assert not list(tmp_path.glob("*.tmp"))
    assert not list(tmp_path.glob("*.bin"))


def test_diagnostics_disconnect_removes_partial_temp_file(tmp_path):
    reads = 0

    async def receive():
        nonlocal reads
        reads += 1
        if reads == 1:
            return {
                "type": "http.request",
                "body": b"partial",
                "more_body": True,
            }
        assert len(list(tmp_path.glob("*.tmp"))) == 1
        return {"type": "http.disconnect"}

    request = _scripted_request(receive, tmp_path)

    with pytest.raises(ClientDisconnect):
        asyncio.run(
            diagnostics.upload_diagnostics(
                request,
                x_diag_token="secret",
                x_session_id="disconnect",
            )
        )

    assert reads == 2
    assert not list(tmp_path.iterdir())


def test_diagnostics_collision_keeps_both_uploads(
    client,
    tmp_path,
    monkeypatch,
):
    _configure_diagnostics(client, tmp_path)
    monkeypatch.setattr(
        diagnostics.time,
        "strftime",
        lambda *args, **kwargs: "20260729-120000",
    )

    first = client.post(
        "/diagnostics",
        content=b"first",
        headers={"X-Diag-Token": "secret", "X-Session-Id": "same"},
    )
    second = client.post(
        "/diagnostics",
        content=b"second",
        headers={"X-Diag-Token": "secret", "X-Session-Id": "same"},
    )

    assert first.status_code == 201
    assert second.status_code == 201
    assert first.json()["session"] != second.json()["session"]
    bins = list(tmp_path.glob("*.bin"))
    assert len(bins) == 2
    assert {path.read_bytes() for path in bins} == {b"first", b"second"}


@pytest.mark.parametrize(
    "session_id",
    ["../escape", "/tmp/absolute", "%2e%2e%2fencoded"],
    ids=["relative", "absolute", "url-encoded"],
)
def test_diagnostics_session_id_cannot_escape_data_dir(
    client,
    tmp_path,
    session_id,
):
    data_dir = tmp_path / "data"
    _configure_diagnostics(client, data_dir)

    response = client.post(
        "/diagnostics",
        content=b"payload",
        headers={"X-Diag-Token": "secret", "X-Session-Id": session_id},
    )

    assert response.status_code == 201
    bins = list(tmp_path.rglob("*.bin"))
    assert len(bins) == 1
    assert bins[0].parent == data_dir


def test_diagnostics_index_failure_keeps_session_and_is_reported(
    client,
    tmp_path,
    monkeypatch,
):
    _configure_diagnostics(client, tmp_path)

    def fail_index(*args, **kwargs):
        raise OSError("synthetic index failure")

    monkeypatch.setattr(
        diagnostics,
        "_append_index",
        fail_index,
        raising=False,
    )

    response = client.post(
        "/diagnostics",
        content=b"payload",
        headers={"X-Diag-Token": "secret", "X-Session-Id": "index-failure"},
    )

    assert response.status_code == 201
    assert response.json()["status"] == "stored"
    assert response.json()["index_status"] == "failed"
    bins = list(tmp_path.glob("*.bin"))
    assert len(bins) == 1
    assert bins[0].read_bytes() == b"payload"
