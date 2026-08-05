"""Edge-case tests for the tutor SSE streaming endpoint (ADR 0142).

Covers: normal ordered stream, disconnect -> provider-task cancel (no orphan
request), strict per-frame sequence (no gap/duplicate/malformed emission),
provider error/timeout mapping, retry without user-message duplication,
cleanup, and the frame-size-limit matrix.
"""

import asyncio
import json

import pytest

from app.ratelimit import RateLimiter
from app.tutor.provider_gateway import FakeProviderGateway
from app.tutor.provider_registry import ProviderRegistry
from app.tutor.router import set_service
from app.tutor.schemas import TutorTurnResponse
from app.tutor.service import TutorLimits, TutorService
from app.tutor.stream import (
    DELTA_CHUNK_CHARS,
    MAX_FRAME_BYTES,
    FrameTooLargeError,
    chunk_reply,
    encode_sse_frame,
    tutor_stream_frames,
)
from app.tutor.usage import UsageGuard

_STREAM_PATH = "/tutor/stream"


def _stream_body(**overrides):
    body = {
        "message": "Hello",
        "request_id": "req-1",
        "sequence": 0,
        "conversation_id": "conv-1",
    }
    body.update(overrides)
    return body


def _parse_sse_events(text):
    """Parse `data: {json}` SSE blocks; asserts the framing is exact."""
    events = []
    for block in text.split("\n\n"):
        block = block.strip()
        if not block:
            continue
        assert block.startswith("data: "), f"bad SSE framing: {block!r}"
        events.append(json.loads(block[len("data: ") :]))
    return events


def _collect_stream(client, headers, body):
    with client.stream("POST", _STREAM_PATH, json=body, headers=headers) as response:
        assert response.status_code == 200, response.read()
        assert response.headers["content-type"].startswith("text/event-stream")
        return _parse_sse_events("".join(response.iter_text()))


@pytest.fixture
def make_service(tutor_client, tutor_settings):
    """Swap the injected tutor service for one with a custom gateway/limits.

    The route reads the service through the module-level accessor at request
    time, so swapping it reconfigures the already-mounted app.
    """

    def _make(gateway, limits=None):
        service = TutorService(
            gateway=gateway,
            registry=ProviderRegistry(
                allowed=tutor_settings.tutor_allowed_providers,
                provider=tutor_settings.tutor_provider,
                model=tutor_settings.tutor_model,
            ),
            api_key=tutor_settings.tutor_api_key,
            usage_guard=UsageGuard(
                rate_limiter=RateLimiter(
                    max_attempts=tutor_settings.tutor_rate_limit_max,
                    window_seconds=tutor_settings.tutor_rate_limit_window,
                ),
                daily_token_limit=tutor_settings.tutor_daily_token_limit,
            ),
            limits=limits
            or TutorLimits(
                max_request_bytes=tutor_settings.tutor_max_request_bytes,
                max_history_messages=tutor_settings.tutor_max_history_messages,
                max_context_bytes=tutor_settings.tutor_max_context_bytes,
                max_output_bytes=tutor_settings.tutor_max_output_bytes,
            ),
        )
        set_service(service)
        return service

    return _make


# --- normal stream ----------------------------------------------------------


def test_normal_stream_emits_ordered_frames(tutor_client, tutor_auth_headers):
    frames = _collect_stream(
        tutor_client, tutor_auth_headers, _stream_body(message="Hi")
    )
    types = [frame["type"] for frame in frames]
    assert types[0] == "started"
    assert types[-1] == "complete"
    assert "usage" in types
    deltas = [frame for frame in frames if frame["type"] == "delta"]
    assert "".join(delta["text"] for delta in deltas) == "A" * 40
    # Shared monotonic sequence: strictly 0..n-1 across ALL frame types.
    assert [frame["seq"] for frame in frames] == list(range(len(frames)))
    # Exactly one terminal frame.
    assert sum(1 for kind in types if kind in ("complete", "failure")) == 1


def test_frames_are_well_formed_and_never_oversized(tutor_client, tutor_auth_headers):
    frames = _collect_stream(tutor_client, tutor_auth_headers, _stream_body())
    assert frames
    for frame in frames:
        assert isinstance(frame, dict)
        assert frame["type"] in {
            "started",
            "delta",
            "tool_call",
            "usage",
            "complete",
            "failure",
        }
        assert isinstance(frame["seq"], int)
        payload = json.dumps(frame, ensure_ascii=False, separators=(",", ":"))
        assert len(payload.encode("utf-8")) <= MAX_FRAME_BYTES


def test_long_reply_streams_multiple_delta_chunks(
    tutor_client, tutor_auth_headers, make_service
):
    reply = "B" * (DELTA_CHUNK_CHARS * 2 + 17)
    make_service(
        gateway=FakeProviderGateway(response=reply),
        limits=TutorLimits(
            max_request_bytes=100,
            max_history_messages=5,
            max_context_bytes=200,
            max_output_bytes=len(reply),
        ),
    )
    frames = _collect_stream(tutor_client, tutor_auth_headers, _stream_body())
    deltas = [frame for frame in frames if frame["type"] == "delta"]
    assert len(deltas) == 3
    assert "".join(delta["text"] for delta in deltas) == reply
    assert [frame["seq"] for frame in frames] == list(range(len(frames)))
    for frame in frames:
        payload = json.dumps(frame, ensure_ascii=False, separators=(",", ":"))
        assert len(payload.encode("utf-8")) <= MAX_FRAME_BYTES


def test_stream_requires_authentication(tutor_client):
    # No bearer at all -> 403 (HTTPBearer); bad token -> 401 (repo convention).
    response = tutor_client.post(_STREAM_PATH, json=_stream_body())
    assert response.status_code == 403
    response = tutor_client.post(
        _STREAM_PATH,
        json=_stream_body(),
        headers={"Authorization": "Bearer not-a-token"},
    )
    assert response.status_code == 401


# --- controlled failure frames ----------------------------------------------


def test_provider_timeout_maps_to_failure_frame(
    tutor_client, tutor_auth_headers, make_service
):
    make_service(gateway=FakeProviderGateway(should_timeout=True))
    frames = _collect_stream(tutor_client, tutor_auth_headers, _stream_body())
    assert [frame["type"] for frame in frames] == ["started", "failure"]
    assert frames[1]["code"] == "provider_timeout"
    assert [frame["seq"] for frame in frames] == [0, 1]


def test_provider_error_maps_to_failure_frame(
    tutor_client, tutor_auth_headers, make_service
):
    make_service(gateway=FakeProviderGateway(should_error=True))
    frames = _collect_stream(tutor_client, tutor_auth_headers, _stream_body())
    assert [frame["type"] for frame in frames] == ["started", "failure"]
    assert frames[1]["code"] == "provider_error"
    assert [frame["seq"] for frame in frames] == [0, 1]


def test_request_too_large_maps_to_failure_frame(tutor_client, tutor_auth_headers):
    frames = _collect_stream(
        tutor_client, tutor_auth_headers, _stream_body(message="x" * 200)
    )
    assert [frame["type"] for frame in frames] == ["started", "failure"]
    assert frames[1]["code"] == "request_too_large"


def test_rate_limit_maps_to_failure_frame(tutor_client, tutor_auth_headers):
    # conftest allows 3 turns per window; the 4th must fail inside the stream.
    for _ in range(3):
        frames = _collect_stream(tutor_client, tutor_auth_headers, _stream_body())
        assert frames[-1]["type"] == "complete"
    frames = _collect_stream(tutor_client, tutor_auth_headers, _stream_body())
    assert [frame["type"] for frame in frames] == ["started", "failure"]
    assert frames[1]["code"] == "rate_limited"


# --- request validation ------------------------------------------------------


def test_invalid_request_body_rejected(tutor_client, tutor_auth_headers):
    # Extra fields are forbidden (allowlist schema).
    response = tutor_client.post(
        _STREAM_PATH,
        json=_stream_body(bogus="field"),
        headers=tutor_auth_headers,
    )
    assert response.status_code == 422
    # Missing idempotency key.
    body = _stream_body()
    del body["request_id"]
    response = tutor_client.post(_STREAM_PATH, json=body, headers=tutor_auth_headers)
    assert response.status_code == 422
    # Negative conversation sequence.
    response = tutor_client.post(
        _STREAM_PATH,
        json=_stream_body(sequence=-1),
        headers=tutor_auth_headers,
    )
    assert response.status_code == 422


def test_control_chars_in_identifiers_rejected(tutor_client, tutor_auth_headers):
    # Log-forging guard: a `\n` in an identifier would inject a fake second
    # line into the server log; the whole C0 range + DEL must be rejected
    # (security review, MINOR).
    forged = "abc\n2026-01-01 ERROR admin: forged log line"
    for field in ("request_id", "conversation_id"):
        response = tutor_client.post(
            _STREAM_PATH,
            json=_stream_body(**{field: forged}),
            headers=tutor_auth_headers,
        )
        assert response.status_code == 422, field
    for char in ("\r", "\x00", "\x1b", "\x7f"):
        response = tutor_client.post(
            _STREAM_PATH,
            json=_stream_body(request_id=f"req{char}1"),
            headers=tutor_auth_headers,
        )
        assert response.status_code == 422, repr(char)


# --- retry idempotency (ADR 0142 D9) ------------------------------------------


def test_retry_does_not_duplicate_user_message(
    tutor_client, tutor_auth_headers, make_service
):
    gateway = FakeProviderGateway(response="A" * 40)
    make_service(gateway=gateway)
    body = _stream_body(
        message="Hello",
        history=[
            {"role": "user", "content": "Hi"},
            {"role": "assistant", "content": "Hello!"},
        ],
        request_id="req-7",
        sequence=3,
    )
    first = _collect_stream(tutor_client, tutor_auth_headers, body)
    second = _collect_stream(tutor_client, tutor_auth_headers, body)
    assert first[-1]["type"] == "complete"
    assert second[-1]["type"] == "complete"
    # Both attempts reach the provider exactly once each...
    assert len(gateway.calls) == 2
    # ...with identical message lists: the retry re-sends the same request,
    # the user message is not appended a second time and history does not grow.
    assert gateway.calls[0]["messages"] == gateway.calls[1]["messages"]
    user_messages = [
        message
        for message in gateway.calls[1]["messages"]
        if message["role"] == "user" and message["content"] == "Hello"
    ]
    assert len(user_messages) == 1


# --- disconnect -> orphan-cancel (ADR 0142 D7) ---------------------------------


async def _hang_until_cancelled():
    await asyncio.sleep(3600)
    return TutorTurnResponse(reply="unreachable")


def test_disconnect_cancels_provider_task():
    """Reviewer mutation: removing the task cancel turns this test red."""

    async def scenario():
        turn_task = asyncio.create_task(_hang_until_cancelled())
        disconnected = asyncio.Event()

        async def is_disconnected():
            return disconnected.is_set()

        generator = tutor_stream_frames(turn_task, is_disconnected, poll_seconds=0.01)
        first = await asyncio.wait_for(generator.__anext__(), timeout=2)
        first_payload = json.loads(first.removeprefix("data: ").strip())
        assert first_payload == {"type": "started", "seq": 0}

        disconnected.set()
        remaining = []

        async def drain():
            async for frame in generator:
                remaining.append(frame)

        await asyncio.wait_for(drain(), timeout=2)
        assert remaining == []
        # The provider coroutine was cancelled and awaited — no orphan request.
        assert turn_task.cancelled()

    asyncio.run(scenario())


def test_provider_task_done_after_normal_completion():
    async def scenario():
        async def quick_turn():
            return TutorTurnResponse(reply="ok")

        turn_task = asyncio.create_task(quick_turn())

        async def is_disconnected():
            return False

        frames = []
        async for frame in tutor_stream_frames(
            turn_task, is_disconnected, poll_seconds=0.01
        ):
            frames.append(frame)
        types = [
            json.loads(frame.removeprefix("data: ").strip())["type"] for frame in frames
        ]
        assert types == ["started", "delta", "usage", "complete"]
        assert turn_task.done()
        assert not turn_task.cancelled()

    asyncio.run(scenario())


# --- frame size limit matrix (ADR 0142 D8) -------------------------------------


def _delta_payload(text):
    return {"type": "delta", "seq": 1, "text": text}


def _payload_bytes(frame):
    return len(
        json.dumps(frame, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    )


def test_encode_frame_size_matrix():
    overhead = _payload_bytes(_delta_payload(""))
    exact_fill = "a" * (MAX_FRAME_BYTES - overhead)
    # Under the limit.
    below = encode_sse_frame(_delta_payload(exact_fill[:-1]))
    assert below.startswith("data: ")
    assert below.endswith("\n\n")
    assert _payload_bytes(json.loads(below.removeprefix("data: ").strip())) == (
        MAX_FRAME_BYTES - 1
    )
    # Exactly at the limit.
    exact = encode_sse_frame(_delta_payload(exact_fill))
    assert _payload_bytes(json.loads(exact.removeprefix("data: ").strip())) == (
        MAX_FRAME_BYTES
    )
    # Over the limit -> controlled error, never an oversized frame.
    with pytest.raises(FrameTooLargeError):
        encode_sse_frame(_delta_payload(exact_fill + "a"))


def test_chunk_reply_preserves_text_and_frame_limit():
    # Quotes, backslashes, control chars and multi-byte chars exercise the
    # worst-case JSON escaping (\uXXXX = 6 bytes per char).
    nasty = '"\\\u0001é中' * 900
    for reply in ("", "short", "A" * 5000, nasty):
        chunks = chunk_reply(reply)
        assert "".join(chunks) == reply
        for index, chunk in enumerate(chunks):
            encoded = encode_sse_frame(
                {"type": "delta", "seq": index + 999999, "text": chunk}
            )
            payload = encoded.removeprefix("data: ").strip()
            assert len(payload.encode("utf-8")) <= MAX_FRAME_BYTES
