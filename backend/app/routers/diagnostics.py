"""Lab-mode field diagnostics collector.

The app's opt-in "Lab mode" uploads real-guitar detection sessions here so we
can see what to improve (ML-vs-DSP chord disagreement, confidence, short audio
for offline ground-truth). Detection still stays on-device by default — this
endpoint only ever receives data while the user has explicitly turned Lab mode
ON on their own device.

Wire contract (client = the Flutter uploader):
    POST /diagnostics
      header  X-Diag-Token: <shared build-time secret>   (blocks random spam)
      header  X-Session-Id: <client session uuid>          (optional; else derived)
      body    the session payload — a **gzipped JSON** blob:
              {sessionId, appVersion, device, startedAt, surface,
               events:[{tSec, mlChord, dspChord, agree, mlConf, dspConf,
                        strumDir, bpm, inputLevel}],
               features:[...], audioClips:[{tSec, wavBase64}]}
              Content-Encoding: gzip (or a raw body — we store bytes verbatim).

We store the raw upload verbatim (one file per session) + append an index line,
and parse offline. Keeping the server dumb (store-bytes) makes it robust to
client-format iteration and needs no multipart dependency.
"""

from __future__ import annotations

import json
import os
import time

from fastapi import APIRouter, Header, HTTPException, Request, status

router = APIRouter(prefix="/diagnostics", tags=["diagnostics"])


def _data_dir() -> str:
    """Where uploaded sessions land on the box (STRUMSIGHT_DIAG_DIR).

    Read per-request (not import-time) so tests and a redeployed box can
    override it without a re-import."""
    return os.environ.get(
        "STRUMSIGHT_DIAG_DIR",
        os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__)))), "diagnostics_data"),
    )


def _token() -> str:
    """Shared build-time secret the APK sends; a spam gate, not real auth. The
    default is a dev value — set STRUMSIGHT_DIAG_TOKEN in the box environment."""
    return os.environ.get("STRUMSIGHT_DIAG_TOKEN", "strumsight-lab-dev")


def _max_bytes() -> int:
    """Reject absurd uploads (short clips → a few MB is plenty)."""
    return int(os.environ.get("STRUMSIGHT_DIAG_MAX_BYTES", str(32 * 1024 * 1024)))


def _safe_id(raw: str | None) -> str:
    """A filesystem-safe session id (client-supplied or time-derived)."""
    ts = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
    if raw:
        cleaned = "".join(c for c in raw if c.isalnum() or c in "-_")[:48]
        if cleaned:
            return f"{ts}_{cleaned}"
    return f"{ts}_{os.urandom(4).hex()}"


@router.get("/health")
def diagnostics_health() -> dict[str, object]:
    d = _data_dir()
    exists = os.path.isdir(d)
    n = len(os.listdir(d)) if exists else 0
    return {"status": "ok", "sessions": n}


@router.post("", status_code=status.HTTP_201_CREATED)
async def upload_diagnostics(
    request: Request,
    x_diag_token: str | None = Header(default=None),
    x_session_id: str | None = Header(default=None),
) -> dict[str, object]:
    if x_diag_token != _token():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail="bad or missing X-Diag-Token")
    body = await request.body()
    if not body:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="empty body")
    max_bytes = _max_bytes()
    if len(body) > max_bytes:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                            detail=f"body > {max_bytes} bytes")

    data_dir = _data_dir()
    os.makedirs(data_dir, exist_ok=True)
    sid = _safe_id(x_session_id)
    # Store the raw upload verbatim (gzipped-json or whatever the client sent).
    path = os.path.join(data_dir, f"{sid}.bin")
    with open(path, "wb") as f:
        f.write(body)
    # Append a one-line index for a quick at-a-glance list.
    with open(os.path.join(data_dir, "index.jsonl"), "a") as ix:
        ix.write(json.dumps({
            "session": sid,
            "bytes": len(body),
            "content_encoding": request.headers.get("content-encoding"),
            "app_version": request.headers.get("x-app-version"),
            "device": request.headers.get("x-device"),
            "at": time.time(),
        }) + "\n")
    return {"status": "stored", "session": sid, "bytes": len(body)}
