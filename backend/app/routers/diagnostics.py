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

import hmac
import json
import logging
import os
import tempfile
import time

from fastapi import APIRouter, Header, HTTPException, Request, status

router = APIRouter(prefix="/diagnostics", tags=["diagnostics"])
_FILE_MODE = 0o600
_logger = logging.getLogger(__name__)


def _data_dir(request: Request) -> str:
    """Return the explicitly configured diagnostics storage directory."""
    return request.app.state.settings.diag_dir


def _token(request: Request) -> str:
    """Return the configured spam-gate token without exposing it."""
    return request.app.state.settings.diag_token


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


def _unique_session_path(data_dir: str, base_session_id: str) -> tuple[str, str]:
    """Choose a suffix without yielding, so one async process cannot overwrite."""
    session_id = base_session_id
    suffix = 1
    path = os.path.join(data_dir, f"{session_id}.bin")
    while os.path.exists(path):
        session_id = f"{base_session_id}-{suffix}"
        suffix += 1
        path = os.path.join(data_dir, f"{session_id}.bin")
    return session_id, path


def _append_index(
    data_dir: str,
    session_id: str,
    byte_count: int,
    request: Request,
) -> None:
    record = {
        "session": session_id,
        "bytes": byte_count,
        "content_encoding": request.headers.get("content-encoding"),
        "app_version": request.headers.get("x-app-version"),
        "device": request.headers.get("x-device"),
        "at": time.time(),
    }
    index_path = os.path.join(data_dir, "index.jsonl")
    descriptor = os.open(
        index_path,
        os.O_APPEND | os.O_CREAT | os.O_WRONLY,
        _FILE_MODE,
    )
    try:
        os.fchmod(descriptor, _FILE_MODE)
        with os.fdopen(
            descriptor,
            "a",
            encoding="utf-8",
            closefd=False,
        ) as index_file:
            index_file.write(json.dumps(record) + "\n")
    finally:
        os.close(descriptor)


@router.get("/health")
def diagnostics_health(request: Request) -> dict[str, object]:
    d = _data_dir(request)
    exists = os.path.isdir(d)
    n = len(os.listdir(d)) if exists else 0
    return {"status": "ok", "sessions": n}


@router.post("", status_code=status.HTTP_201_CREATED)
async def upload_diagnostics(
    request: Request,
    x_diag_token: str | None = Header(default=None),
    x_session_id: str | None = Header(default=None),
) -> dict[str, object]:
    expected_token = _token(request)
    provided_token = x_diag_token or ""
    if not expected_token or not hmac.compare_digest(
        provided_token.encode("utf-8"),
        expected_token.encode("utf-8"),
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="bad or missing X-Diag-Token",
        )

    max_bytes = _max_bytes()
    data_dir = _data_dir(request)
    os.makedirs(data_dir, mode=0o700, exist_ok=True)
    base_session_id = _safe_id(x_session_id)
    descriptor, temp_path = tempfile.mkstemp(
        dir=data_dir,
        prefix=f".{base_session_id}-",
        suffix=".tmp",
    )
    byte_count = 0
    try:
        os.fchmod(descriptor, _FILE_MODE)
        temp_file = os.fdopen(descriptor, "wb")
        descriptor = -1
        with temp_file:
            async for chunk in request.stream():
                if not chunk:
                    continue
                next_byte_count = byte_count + len(chunk)
                if next_byte_count > max_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"body > {max_bytes} bytes",
                    )
                temp_file.write(chunk)
                byte_count = next_byte_count

        if byte_count == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="empty body",
            )

        session_id, final_path = _unique_session_path(
            data_dir,
            base_session_id,
        )
        os.replace(temp_path, final_path)
        temp_path = ""
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temp_path:
            try:
                os.unlink(temp_path)
            except FileNotFoundError:
                pass

    response: dict[str, object] = {
        "status": "stored",
        "session": session_id,
        "bytes": byte_count,
    }
    try:
        _append_index(data_dir, session_id, byte_count, request)
    except OSError:
        _logger.exception(
            "Diagnostics index append failed for session %s",
            session_id,
        )
        response["index_status"] = "failed"
    return response
