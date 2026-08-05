"""SSE streaming transport for tutor turns (ADR 0142).

The endpoint owns the provider coroutine as an `asyncio.Task` and cancels it
on client disconnect, so no orphan provider request survives a closed stream.
Every frame is one SSE `data:` line carrying a JSON object with a shared
monotonic `seq` (0-based, +1 per frame, across ALL frame types). Once
streaming has started, errors are normalized to a terminal `failure` frame
instead of HTTP error statuses — the client parser sees one uniform protocol.

The provider gateway and the tutor service are out of this round's scope, so
the endpoint SYNTHESIZES the ordered frame sequence from the existing
non-streaming turn response (ADR 0142 D10): started -> delta* -> usage ->
complete, or started -> failure.
"""

import asyncio
import contextlib
import json
import logging
from collections.abc import AsyncIterator, Awaitable, Callable

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field

from ..deps import CurrentUser
from .provider_gateway import ProviderError, ProviderTimeoutError
from .router import get_service
from .schemas import TurnMessage, TutorTurnRequest, TutorTurnResponse
from .service import RequestTooLargeError
from .usage import RateLimitExceeded, UsageLimitExceeded

_logger = logging.getLogger(__name__)

router = APIRouter()

# --- protocol constants (ADR 0142) -------------------------------------------

#: Upper bound for one SSE `data:` JSON payload, in UTF-8 bytes (D8). The
#: server never emits a frame above it; the client rejects larger frames.
MAX_FRAME_BYTES = 8192

#: Reserved headroom for the JSON envelope (`{"type":"delta","seq":N,"text":...}`)
#: when computing the per-chunk text budget.
_FRAME_OVERHEAD_RESERVE_BYTES = 64

#: Worst-case JSON escaping expands one character to `\uXXXX` (6 bytes).
_MAX_JSON_ESCAPE_WIDTH = 6

#: Chunk size for delta frames: even with worst-case escaping every delta
#: frame stays under MAX_FRAME_BYTES by construction.
DELTA_CHUNK_CHARS = (
    MAX_FRAME_BYTES - _FRAME_OVERHEAD_RESERVE_BYTES
) // _MAX_JSON_ESCAPE_WIDTH

#: How often the generator polls for client disconnect while the provider
#: turn is still running.
_DISCONNECT_POLL_SECONDS = 0.05

#: Upper bound for client-supplied identifiers.
_MAX_ID_LENGTH = 128


class FrameTooLargeError(Exception):
    """An encoded frame would exceed MAX_FRAME_BYTES (ADR 0142 D8)."""


class TutorStreamRequest(BaseModel):
    """Stream request body: TutorTurnRequest shape + idempotency keys.

    `request_id` + `sequence` identify the request within the conversation
    (ADR 0142 D9): a retry carries the same keys, starts a fresh stream and
    never appends the user message a second time.
    """

    model_config = ConfigDict(extra="forbid")

    message: str
    history: list[TurnMessage] = []
    context: str = ""
    request_id: str = Field(min_length=1, max_length=_MAX_ID_LENGTH)
    sequence: int = Field(ge=0)
    conversation_id: str = Field(min_length=1, max_length=_MAX_ID_LENGTH)


# --- frame encoding -----------------------------------------------------------


def encode_sse_frame(frame: dict, *, max_frame_bytes: int = MAX_FRAME_BYTES) -> str:
    """Encode one frame as an SSE `data:` block.

    Raises FrameTooLargeError when the JSON payload exceeds the limit — the
    server never emits an oversized frame (ADR 0142 D8).
    """
    payload = json.dumps(frame, ensure_ascii=False, separators=(",", ":"))
    if len(payload.encode("utf-8")) > max_frame_bytes:
        raise FrameTooLargeError(
            f"frame payload exceeds {max_frame_bytes} bytes"
        )
    return f"data: {payload}\n\n"


def chunk_reply(reply: str, *, chunk_chars: int = DELTA_CHUNK_CHARS) -> list[str]:
    """Split a reply into delta texts whose frames always fit the size limit."""
    if not reply:
        return []
    return [
        reply[index : index + chunk_chars]
        for index in range(0, len(reply), chunk_chars)
    ]


def _failure_frame(seq: int, code: str, message: str) -> str:
    return encode_sse_frame(
        {"type": "failure", "seq": seq, "code": code, "message": message}
    )


# --- frame generator ----------------------------------------------------------


async def tutor_stream_frames(
    turn_task: "asyncio.Task[TutorTurnResponse]",
    is_disconnected: Callable[[], Awaitable[bool]],
    *,
    max_frame_bytes: int = MAX_FRAME_BYTES,
    delta_chunk_chars: int = DELTA_CHUNK_CHARS,
    poll_seconds: float = _DISCONNECT_POLL_SECONDS,
) -> AsyncIterator[str]:
    """Yield the ordered SSE frames for one turn.

    Frame order (ADR 0142 D3): started -> delta* -> usage -> complete, or
    started -> failure. Exactly one terminal frame ends the stream. When the
    client disconnects, the provider task is cancelled and awaited before the
    generator returns — no orphan provider request (ADR 0142 D7).
    """
    seq = 0
    try:
        yield encode_sse_frame(
            {"type": "started", "seq": seq}, max_frame_bytes=max_frame_bytes
        )
        seq += 1

        while not turn_task.done():
            if await is_disconnected():
                return
            await asyncio.wait({turn_task}, timeout=poll_seconds)

        try:
            response = turn_task.result()
        except asyncio.CancelledError:
            return
        except RequestTooLargeError:
            yield _failure_frame(seq, "request_too_large", "Request exceeds the size limits")
            return
        except RateLimitExceeded:
            yield _failure_frame(seq, "rate_limited", "Rate limit exceeded — try again shortly")
            return
        except UsageLimitExceeded:
            yield _failure_frame(seq, "usage_limited", "Daily usage limit exceeded")
            return
        except ProviderTimeoutError:
            yield _failure_frame(
                seq, "provider_timeout", "The AI service is temporarily unavailable"
            )
            return
        except ProviderError:
            yield _failure_frame(seq, "provider_error", "The AI service returned an error")
            return
        except Exception:  # noqa: BLE001 — the stream must end with a terminal frame.
            _logger.exception("Unexpected tutor stream failure (details redacted)")
            yield _failure_frame(
                seq, "internal_error", "The AI service hit an unexpected error"
            )
            return

        for chunk in chunk_reply(response.reply, chunk_chars=delta_chunk_chars):
            yield encode_sse_frame(
                {"type": "delta", "seq": seq, "text": chunk},
                max_frame_bytes=max_frame_bytes,
            )
            seq += 1

        tokens = max(1, len(response.reply) // 4)
        yield encode_sse_frame(
            {"type": "usage", "seq": seq, "tokens": tokens},
            max_frame_bytes=max_frame_bytes,
        )
        seq += 1

        yield encode_sse_frame(
            {"type": "complete", "seq": seq}, max_frame_bytes=max_frame_bytes
        )
    finally:
        if not turn_task.done():
            turn_task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await turn_task


# --- endpoint -----------------------------------------------------------------


@router.post("/stream")
async def tutor_stream(
    body: TutorStreamRequest, request: Request, current_user: CurrentUser
) -> StreamingResponse:
    """Stream a tutor turn as SSE frames (ADR 0142)."""
    service = get_service()
    user_id = str(current_user.id)
    turn_request = TutorTurnRequest(
        message=body.message, history=body.history, context=body.context
    )
    # Metadata only — never log the message content (AGENTS.md §5).
    _logger.info(
        "Tutor stream started for user %s (request %s, seq %d)",
        user_id,
        body.request_id,
        body.sequence,
    )
    turn_task = asyncio.create_task(service.turn(user_id, turn_request))
    frames = tutor_stream_frames(turn_task, request.is_disconnected)
    return StreamingResponse(
        frames,
        media_type="text/event-stream",
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )
