"""Lab-mode diagnostics collector: store, token gate, empty/oversize reject."""

import gzip
import json


def test_diagnostics_health(client):
    r = client.get("/diagnostics/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_diagnostics_rejects_bad_token(client, tmp_path, monkeypatch):
    monkeypatch.setenv("STRUMSIGHT_DIAG_TOKEN", "secret")
    monkeypatch.setenv("STRUMSIGHT_DIAG_DIR", str(tmp_path))
    r = client.post("/diagnostics", content=b"x",
                    headers={"X-Diag-Token": "wrong"})
    assert r.status_code == 401
    # Nothing was written.
    assert not list(tmp_path.glob("*.bin"))


def test_diagnostics_rejects_empty(client, tmp_path, monkeypatch):
    monkeypatch.setenv("STRUMSIGHT_DIAG_TOKEN", "secret")
    monkeypatch.setenv("STRUMSIGHT_DIAG_DIR", str(tmp_path))
    r = client.post("/diagnostics", content=b"",
                    headers={"X-Diag-Token": "secret"})
    assert r.status_code == 400


def test_diagnostics_stores_session_verbatim(client, tmp_path, monkeypatch):
    monkeypatch.setenv("STRUMSIGHT_DIAG_TOKEN", "secret")
    monkeypatch.setenv("STRUMSIGHT_DIAG_DIR", str(tmp_path))
    payload = gzip.compress(
        json.dumps({"sessionId": "s1", "surface": "live", "events": []}).encode())
    r = client.post(
        "/diagnostics", content=payload,
        headers={"X-Diag-Token": "secret", "X-Session-Id": "s1",
                 "Content-Encoding": "gzip", "X-App-Version": "lab1"})
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "stored"
    bins = list(tmp_path.glob("*.bin"))
    assert len(bins) == 1
    # Stored byte-for-byte (server is dumb on purpose).
    assert bins[0].read_bytes() == payload
    # And indexed.
    idx = (tmp_path / "index.jsonl").read_text().strip().splitlines()
    assert len(idx) == 1
    rec = json.loads(idx[0])
    assert rec["app_version"] == "lab1"
    assert rec["content_encoding"] == "gzip"
