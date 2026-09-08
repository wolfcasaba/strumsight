# strumsight:allow-secret-file — every credential in this file is an invented
# sentinel (`mm-SENTINEL-KEY`); the suite talks to `httpx.MockTransport` only
# and its PURPOSE is to prove the real key never reaches the log, and that it
# rides exactly ONE header.
"""Contract tests for the MiniMax tutor provider PROFILE (R29b).

MiniMax M3 serves an Anthropic-compatible Messages API, so R29b added a
`AnthropicCompatibleProfile` instead of a second adapter: the request body,
the SSE folding and the error classification are the code
`test_anthropic_provider_gateway.py` already pins. What is NEW — and what
this suite measures — is everything the profile decides: the base URL the
request lands on, and WHICH header carries the key.

Every call goes through `httpx.MockTransport` — the suite never reaches
`api.minimax.io` and never needs a key.
"""

import asyncio
import json
import logging
from collections.abc import Callable
from typing import Any

import httpx
import pytest

from app.tutor.provider_gateway import (
    ANTHROPIC_COMPATIBLE_PROFILES,
    ANTHROPIC_PROFILE,
    MINIMAX_PROFILE,
    AnthropicCompatibleProfile,
    AnthropicProviderGateway,
    ProviderBusyError,
    ProviderConfigurationError,
    ProviderError,
    ProviderInvalidRequestError,
    ProviderTimeoutError,
)

_API_KEY = "mm-SENTINEL-KEY"
_MESSAGES = [{"role": "user", "content": "PROMPT-SENTINEL"}]
_MODEL = "MiniMax-M3"
_MAX_OUTPUT_BYTES = 2000
_EXPECTED_MAX_TOKENS = _MAX_OUTPUT_BYTES // 4

#: The URL the MiniMax profile must produce with no override — the whole
#: point of the `/v1` suffix on `_MINIMAX_BASE_URL`. Measured from this
#: repository's own MiniMax tooling (`tools/mm-round.sh`:
#: `ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic`), plus the Messages
#: API's own `/v1/messages` path under it.
_MINIMAX_MESSAGES_URL = "https://api.minimax.io/anthropic/v1/messages"
_ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages"


def _sse(*frames: dict[str, Any]) -> bytes:
    """Render frames the way an Anthropic-compatible endpoint streams them."""
    blocks = [
        f"event: {frame['type']}\ndata: {json.dumps(frame, separators=(',', ':'))}\n"
        for frame in frames
    ]
    return ("\n".join(blocks) + "\n").encode("utf-8")


_TEXT_STREAM = _sse(
    {"type": "message_start", "message": {"id": "msg_1", "type": "message"}},
    {"type": "content_block_start", "index": 0, "content_block": {"type": "text"}},
    {
        "type": "content_block_delta",
        "index": 0,
        "delta": {"type": "text_delta", "text": "Barre"},
    },
    {
        "type": "content_block_delta",
        "index": 0,
        "delta": {"type": "text_delta", "text": " chords"},
    },
    {"type": "content_block_stop", "index": 0},
    {
        "type": "message_delta",
        "delta": {"stop_reason": "end_turn"},
        "usage": {"output_tokens": 9},
    },
    {"type": "message_stop"},
)


def _ok(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, content=_TEXT_STREAM, request=request)


def _gateway(
    handler: Callable[[httpx.Request], httpx.Response],
    profile: AnthropicCompatibleProfile = MINIMAX_PROFILE,
) -> AnthropicProviderGateway:
    """Build the adapter on its PROFILE default — no `base_url` override."""
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return AnthropicProviderGateway(
        client=client,
        max_output_bytes=_MAX_OUTPUT_BYTES,
        profile=profile,
    )


async def _run(
    handler: Callable[[httpx.Request], httpx.Response],
    profile: AnthropicCompatibleProfile = MINIMAX_PROFILE,
) -> str:
    gateway = _gateway(handler, profile)
    try:
        return await gateway.complete(
            messages=_MESSAGES,
            model=_MODEL,
            api_key=_API_KEY,
            timeout_seconds=5.0,
        )
    finally:
        await gateway.aclose()


def _complete(
    handler: Callable[[httpx.Request], httpx.Response],
    profile: AnthropicCompatibleProfile = MINIMAX_PROFILE,
) -> str:
    return asyncio.run(_run(handler, profile))


# --- the profile table --------------------------------------------------------


@pytest.mark.parametrize(
    ("profile", "expected_url", "expected_header", "forbidden_header"),
    [
        (MINIMAX_PROFILE, _MINIMAX_MESSAGES_URL, "authorization", "x-api-key"),
        (ANTHROPIC_PROFILE, _ANTHROPIC_MESSAGES_URL, "x-api-key", "authorization"),
    ],
    ids=["minimax", "anthropic"],
)
def test_each_profile_addresses_its_own_endpoint_with_its_own_auth_header(
    profile: AnthropicCompatibleProfile,
    expected_url: str,
    expected_header: str,
    forbidden_header: str,
) -> None:
    """The profile decides the URL and the ONE header that carries the key.

    The forbidden-header half matters as much as the positive one: sending
    the secret twice "just in case the vendor accepts both" would double the
    surface the key crosses per request.
    """
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = request.headers
        return _ok(request)

    assert _complete(handler, profile) == "Barre chords"
    assert captured["url"] == expected_url
    assert captured["headers"][expected_header] == (f"{profile.auth_prefix}{_API_KEY}")
    assert forbidden_header not in captured["headers"]


def test_the_minimax_profile_presents_the_key_as_a_bearer_token() -> None:
    """`Authorization: Bearer <key>` — measured from `tools/mm-round.sh`."""
    assert MINIMAX_PROFILE.auth_headers(_API_KEY) == {
        "Authorization": f"Bearer {_API_KEY}"
    }
    assert ANTHROPIC_PROFILE.auth_headers(_API_KEY) == {"x-api-key": _API_KEY}


def test_the_registry_resolves_both_provider_names() -> None:
    """The composition root looks a profile up by the configured name."""
    assert ANTHROPIC_COMPATIBLE_PROFILES == {
        "anthropic": ANTHROPIC_PROFILE,
        "minimax": MINIMAX_PROFILE,
    }


def test_an_explicit_base_url_still_overrides_the_profile() -> None:
    """A proxy in front of MiniMax stays configurable per deployment."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        return _ok(request)

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    gateway = AnthropicProviderGateway(
        client=client,
        max_output_bytes=_MAX_OUTPUT_BYTES,
        base_url="https://gateway.internal/mm/v1/",
        profile=MINIMAX_PROFILE,
    )

    async def _call() -> str:
        try:
            return await gateway.complete(
                messages=_MESSAGES,
                model=_MODEL,
                api_key=_API_KEY,
                timeout_seconds=5.0,
            )
        finally:
            await gateway.aclose()

    assert asyncio.run(_call()) == "Barre chords"
    assert captured["url"] == "https://gateway.internal/mm/v1/messages"


# --- the wire request ---------------------------------------------------------


def test_complete_sends_the_messages_contract_to_minimax() -> None:
    """The exact request MiniMax receives — URL, headers and body."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["method"] = request.method
        captured["url"] = str(request.url)
        captured["authorization"] = request.headers["authorization"]
        captured["version"] = request.headers["anthropic-version"]
        captured["content_type"] = request.headers["content-type"]
        captured["accept"] = request.headers["accept"]
        captured["body"] = json.loads(request.content)
        return _ok(request)

    assert _complete(handler) == "Barre chords"
    assert captured == {
        "method": "POST",
        "url": _MINIMAX_MESSAGES_URL,
        "authorization": f"Bearer {_API_KEY}",
        # MiniMax mirrors Anthropic's header-based versioning, so the same
        # constant is sent unchanged.
        "version": "2023-06-01",
        "content_type": "application/json",
        "accept": "text/event-stream",
        "body": {
            "model": _MODEL,
            "max_tokens": _EXPECTED_MAX_TOKENS,
            "messages": _MESSAGES,
            "stream": True,
        },
    }


def test_the_context_turn_is_hoisted_into_the_system_field_for_minimax() -> None:
    """The compatible endpoint takes the system prompt out of band too."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        return _ok(request)

    gateway = _gateway(handler)

    async def _call() -> str:
        try:
            return await gateway.complete(
                messages=[
                    {"role": "user", "content": "how do I play F?"},
                    {"role": "system", "content": "CONTEXT-SNAPSHOT"},
                ],
                model=_MODEL,
                api_key=_API_KEY,
                timeout_seconds=5.0,
            )
        finally:
            await gateway.aclose()

    assert asyncio.run(_call()) == "Barre chords"
    assert captured["body"]["system"] == "CONTEXT-SNAPSHOT"
    assert captured["body"]["messages"] == [
        {"role": "user", "content": "how do I play F?"}
    ]


# --- failure classification, reused ------------------------------------------


def _body(payload: bytes, status: int = 200) -> Callable[..., httpx.Response]:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(status, content=payload, request=request)

    return handler


def _error_frame(error_type: str) -> Callable[..., httpx.Response]:
    return _body(
        _sse({"type": "error", "error": {"type": error_type, "message": "SENTINEL"}})
    )


@pytest.mark.parametrize(
    ("handler", "expected_exception", "expected_classification"),
    [
        (_body(b"", 401), ProviderConfigurationError, "configuration"),
        (_body(b"", 404), ProviderConfigurationError, "configuration"),
        (_body(b"", 429), ProviderBusyError, "busy"),
        (_body(b"", 400), ProviderInvalidRequestError, "invalid_request"),
        (_body(b"", 503), ProviderBusyError, "busy"),
        (_error_frame("rate_limit_error"), ProviderBusyError, "busy"),
        (
            _error_frame("authentication_error"),
            ProviderConfigurationError,
            "configuration",
        ),
        (_error_frame("timeout_error"), ProviderTimeoutError, "timeout"),
    ],
    ids=[
        "http_401",
        "http_404",
        "http_429",
        "http_400",
        "http_503",
        "frame_rate_limit",
        "frame_authentication",
        "frame_timeout",
    ],
)
def test_minimax_failures_classify_exactly_as_anthropic_failures_do(
    handler: Callable[[httpx.Request], httpx.Response],
    expected_exception: type[Exception],
    expected_classification: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """One classification table serves both providers — no per-vendor fork."""
    with caplog.at_level(logging.WARNING):
        with pytest.raises(expected_exception):
            _complete(handler)

    assert f"classification={expected_classification}" in caplog.text
    assert _API_KEY not in caplog.text


@pytest.mark.parametrize(
    "error_type",
    [
        "minimax_internal_error",
        "insufficient_balance",
        "",
        "42",
    ],
    ids=["vendor_specific", "vendor_billing_wording", "empty", "numeric_string"],
)
def test_an_error_TYPE_this_repository_has_never_seen_still_fails_closed(
    error_type: str, caplog: pytest.LogCaptureFixture
) -> None:
    """A vendor-specific `error.type` must degrade, not crash.

    MiniMax's error enum is not documented in this repository, so the
    adapter cannot claim to know it. An unlisted type therefore lands on the
    generic, redacted `ProviderError` (`classification=provider_error`) — the
    client-facing answer an operator already knows how to read — instead of
    raising a `KeyError` out of the streaming loop.
    """
    with caplog.at_level(logging.WARNING):
        with pytest.raises(ProviderError) as raised:
            _complete(_error_frame(error_type))

    assert type(raised.value) is ProviderError
    assert "classification=provider_error" in caplog.text
    # The vendor's own type string is never echoed back to the caller (the
    # empty case has nothing to echo, hence the guard).
    assert not error_type or error_type not in str(raised.value)
    assert "SENTINEL" not in caplog.text


@pytest.mark.parametrize(
    "payload",
    [
        b'{"error":{"type":"authentication_error"}}',
        b"data: not-json\n\n",
        b"<html>upstream proxy</html>\n",
        b'data: {"type":"error","error":"a bare string"}\n\n',
    ],
    ids=[
        "json_not_sse",
        "malformed_frame",
        "html_error_page",
        "error_is_not_an_object",
    ],
)
def test_a_non_conforming_minimax_response_is_a_redacted_provider_error(
    payload: bytes,
) -> None:
    """An endpoint that answers 200 with something else fails closed."""
    with pytest.raises(ProviderError) as raised:
        _complete(_body(payload))

    message = str(raised.value).lower()
    assert _API_KEY.lower() not in message
    assert "minimax" not in message
    assert "api.minimax.io" not in message


def test_a_stream_without_message_stop_is_incomplete_not_a_short_answer() -> None:
    """A truncated MiniMax stream must not be presented as the tutor's reply."""
    truncated = _sse(
        {
            "type": "content_block_delta",
            "index": 0,
            "delta": {"type": "text_delta", "text": "half an ans"},
        }
    )
    with pytest.raises(ProviderError):
        _complete(_body(truncated))


# --- the log ------------------------------------------------------------------


def test_a_successful_minimax_turn_logs_metadata_only(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Provider name and token count — never the key, the prompt or the reply."""
    with caplog.at_level(logging.DEBUG):
        assert _complete(_ok) == "Barre chords"

    assert "provider=minimax" in caplog.text
    assert "output_tokens=9" in caplog.text
    assert _API_KEY not in caplog.text
    assert _MESSAGES[0]["content"] not in caplog.text
    assert "Barre chords" not in caplog.text


def test_a_failed_minimax_turn_logs_no_secret_and_no_url(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """The transport exception text can carry the target URL — it is dropped."""

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError(f"failed to connect to {_MINIMAX_MESSAGES_URL}")

    with caplog.at_level(logging.DEBUG):
        with pytest.raises(ProviderError):
            _complete(handler)

    assert "classification=transport" in caplog.text
    assert "api.minimax.io" not in caplog.text
    assert _API_KEY not in caplog.text
