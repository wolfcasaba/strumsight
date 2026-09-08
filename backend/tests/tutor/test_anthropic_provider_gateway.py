"""Contract tests for the Anthropic tutor provider adapter.

Every call goes through `httpx.MockTransport` — the suite never reaches the
real Messages API and never needs a key.
"""

import asyncio
import json
import logging
from collections.abc import Callable
from typing import Any

import httpx
import pytest

from app.tutor.provider_gateway import (
    AnthropicProviderGateway,
    ProviderBusyError,
    ProviderConfigurationError,
    ProviderError,
    ProviderInvalidRequestError,
    ProviderTimeoutError,
    split_anthropic_messages,
)

_API_KEY = "sk-ant-SENTINEL-KEY"
_BASE_URL = "https://provider.example/v1"
_MESSAGES = [{"role": "user", "content": "PROMPT-SENTINEL"}]
_MODEL = "configured-model"
_MAX_OUTPUT_BYTES = 2000
_EXPECTED_MAX_TOKENS = _MAX_OUTPUT_BYTES // 4


def _sse(*frames: dict[str, Any]) -> bytes:
    """Render frames the way the Messages API streams them."""
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
        "delta": {"type": "text_delta", "text": "Hello"},
    },
    {
        "type": "content_block_delta",
        "index": 0,
        "delta": {"type": "text_delta", "text": ", G major"},
    },
    {"type": "content_block_stop", "index": 0},
    {
        "type": "message_delta",
        "delta": {"stop_reason": "end_turn"},
        "usage": {"output_tokens": 12},
    },
    {"type": "message_stop"},
)


def _ok(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, content=_TEXT_STREAM, request=request)


def _gateway(
    handler: Callable[[httpx.Request], httpx.Response],
) -> AnthropicProviderGateway:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return AnthropicProviderGateway(
        client=client,
        base_url=_BASE_URL,
        max_output_bytes=_MAX_OUTPUT_BYTES,
    )


async def _run(
    handler: Callable[[httpx.Request], httpx.Response],
    messages: list[dict[str, str]] | None = None,
    timeout_seconds: float = 5.0,
) -> str:
    gateway = _gateway(handler)
    try:
        return await gateway.complete(
            messages=_MESSAGES if messages is None else messages,
            model=_MODEL,
            api_key=_API_KEY,
            timeout_seconds=timeout_seconds,
        )
    finally:
        await gateway.aclose()


def _complete(
    handler: Callable[[httpx.Request], httpx.Response],
    messages: list[dict[str, str]] | None = None,
    timeout_seconds: float = 5.0,
) -> str:
    return asyncio.run(_run(handler, messages, timeout_seconds))


# --- happy path ---------------------------------------------------------------


def test_complete_sends_the_messages_contract_and_folds_text_deltas() -> None:
    """The adapter posts the streaming Messages contract and joins the deltas."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["method"] = request.method
        captured["url"] = str(request.url)
        captured["api_key"] = request.headers["x-api-key"]
        captured["version"] = request.headers["anthropic-version"]
        captured["content_type"] = request.headers["content-type"]
        captured["body"] = json.loads(request.content)
        return _ok(request)

    assert _complete(handler) == "Hello, G major"
    assert captured == {
        "method": "POST",
        "url": "https://provider.example/v1/messages",
        "api_key": _API_KEY,
        "version": "2023-06-01",
        "content_type": "application/json",
        "body": {
            "model": _MODEL,
            "max_tokens": _EXPECTED_MAX_TOKENS,
            "messages": _MESSAGES,
            "stream": True,
        },
    }


def test_complete_hoists_the_context_turn_into_the_system_field() -> None:
    """The tutor's `system` turn is carried out of band, not inside messages."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        return _ok(request)

    _complete(
        handler,
        messages=[
            {"role": "user", "content": "how do I play G?"},
            {"role": "system", "content": "CONTEXT-SNAPSHOT"},
        ],
    )
    assert captured["body"]["system"] == "CONTEXT-SNAPSHOT"
    assert captured["body"]["messages"] == [
        {"role": "user", "content": "how do I play G?"}
    ]


def test_complete_omits_the_system_field_when_there_is_no_context() -> None:
    """No context turn ⇒ no empty `system` string in the request body."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["body"] = json.loads(request.content)
        return _ok(request)

    _complete(handler)
    assert "system" not in captured["body"]


@pytest.mark.parametrize(
    ("messages", "expected"),
    [
        (
            [
                {"role": "user", "content": "first"},
                {"role": "user", "content": "second"},
            ],
            [{"role": "user", "content": "first\n\nsecond"}],
        ),
        (
            [
                {"role": "assistant", "content": "dangling"},
                {"role": "user", "content": "question"},
            ],
            [{"role": "user", "content": "question"}],
        ),
        (
            [
                {"role": "user", "content": "a"},
                {"role": "assistant", "content": "b"},
                {"role": "user", "content": "c"},
            ],
            [
                {"role": "user", "content": "a"},
                {"role": "assistant", "content": "b"},
                {"role": "user", "content": "c"},
            ],
        ),
    ],
    ids=["merges_repeated_roles", "drops_leading_assistant", "keeps_alternating"],
)
def test_split_anthropic_messages_normalizes_the_chat_turns(
    messages: list[dict[str, str]], expected: list[dict[str, str]]
) -> None:
    """The API rejects repeated roles and a non-user first turn — normalize first."""
    system_prompt, chat = split_anthropic_messages(messages)
    assert system_prompt == ""
    assert chat == expected


def test_complete_records_the_provider_usage_without_content(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """`message_delta` usage is logged as a bare number — the only usage capture."""
    with caplog.at_level(logging.INFO):
        assert _complete(_ok) == "Hello, G major"

    assert "output_tokens=12" in caplog.text
    assert "Hello, G major" not in caplog.text
    assert _MESSAGES[0]["content"] not in caplog.text


@pytest.mark.parametrize("timeout_seconds", [0.5, 5.0, 30.0])
def test_complete_passes_timeout_to_http_client(timeout_seconds: float) -> None:
    """The requested timeout is forwarded without local adjustment."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["timeout"] = request.extensions["timeout"]
        return _ok(request)

    assert _complete(handler, timeout_seconds=timeout_seconds) == "Hello, G major"
    assert set(captured["timeout"].values()) == {timeout_seconds}


# --- failure normalization ----------------------------------------------------


def _raise(exception: Exception) -> Callable[[httpx.Request], httpx.Response]:
    def handler(request: httpx.Request) -> httpx.Response:
        raise exception

    return handler


def _body(payload: bytes, status: int = 200) -> Callable[..., httpx.Response]:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(status, content=payload, request=request)

    return handler


@pytest.mark.parametrize(
    ("handler", "expected_exception"),
    [
        (_raise(httpx.ReadTimeout("SENTINEL-BODY")), ProviderTimeoutError),
        (_raise(httpx.ConnectTimeout("SENTINEL-BODY")), ProviderTimeoutError),
        (_raise(httpx.ConnectError("SENTINEL-BODY")), ProviderError),
        (_body(b'{"error":{"message":"SENTINEL-BODY"}}', 401), ProviderError),
        (_body(b'{"error":{"message":"SENTINEL-BODY"}}', 500), ProviderError),
        (_body(b"SENTINEL-BODY\n"), ProviderError),
        (_body(b"data: {SENTINEL-BODY\n\n"), ProviderError),
        (_body(b"data: [1,2,3]\n\n"), ProviderError),
        (
            _body(
                _sse(
                    {
                        "type": "error",
                        "error": {
                            "type": "overloaded_error",
                            "message": "SENTINEL-BODY",
                        },
                    }
                )
            ),
            ProviderError,
        ),
        (
            _body(
                _sse(
                    {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": "partial"},
                    }
                )
            ),
            ProviderError,
        ),
        (
            _body(
                _sse(
                    {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": 123},
                    },
                    {"type": "message_stop"},
                )
            ),
            ProviderError,
        ),
    ],
    ids=[
        "read_timeout",
        "connect_timeout",
        "connect_error",
        "http_4xx",
        "http_5xx",
        "not_an_sse_line",
        "malformed_json_frame",
        "frame_is_not_an_object",
        "provider_error_event",
        "stream_without_message_stop",
        "non_string_text_delta",
    ],
)
def test_complete_normalizes_failures_without_leaking_details(
    handler: Callable[[httpx.Request], httpx.Response],
    expected_exception: type[Exception],
) -> None:
    """Every provider failure is a redacted, provider-neutral exception."""
    with pytest.raises(expected_exception) as raised:
        _complete(handler)

    message = str(raised.value).lower()
    assert _API_KEY.lower() not in message
    assert "provider.example" not in message
    assert "anthropic" not in message
    assert "claude" not in message
    assert "sentinel-body" not in message


def test_complete_rejects_a_request_with_no_chat_turn() -> None:
    """A context-only turn cannot become a Messages request — fail closed."""

    def handler(request: httpx.Request) -> httpx.Response:  # pragma: no cover
        raise AssertionError("the adapter must not call the provider")

    with pytest.raises(ProviderError):
        _complete(handler, messages=[{"role": "system", "content": "context only"}])


@pytest.mark.parametrize(
    "messages",
    [
        [{"role": 7, "content": "x"}],
        [{"role": "user", "content": None}],
    ],
    ids=["non_string_role", "non_string_content"],
)
def test_complete_rejects_non_string_turns(messages: list[dict[str, Any]]) -> None:
    """A malformed turn is a provider-neutral error, not a TypeError at the wire."""
    with pytest.raises(ProviderError):
        split_anthropic_messages(messages)


@pytest.mark.parametrize(
    "handler",
    [_ok, _body(b'{"error":{"message":"SENTINEL-BODY"}}', 500)],
    ids=["success", "error"],
)
def test_complete_never_logs_prompt_or_api_key(
    handler: Callable[[httpx.Request], httpx.Response],
    caplog: pytest.LogCaptureFixture,
) -> None:
    """Neither successful nor failed calls log secrets or prompt content."""
    with caplog.at_level(logging.DEBUG):
        try:
            _complete(handler)
        except ProviderError:
            pass

    assert _MESSAGES[0]["content"] not in caplog.text
    assert _API_KEY not in caplog.text


def test_max_output_bytes_must_be_positive() -> None:
    """A non-positive budget is a configuration error, not a silent 1-token cap."""
    with pytest.raises(ValueError, match="max_output_bytes"):
        AnthropicProviderGateway(max_output_bytes=0)


# --- failure CLASSIFICATION ---------------------------------------------------
#
# Every class below is a `ProviderError` subclass, so the client-facing
# contract is untouched (502, or 504 for the timeout). The classification
# exists for the operator reading the server log: "my key is wrong" and
# "Anthropic is overloaded" must not look the same.


@pytest.mark.parametrize(
    ("status", "expected_exception", "expected_classification"),
    [
        (400, ProviderInvalidRequestError, "invalid_request"),
        (401, ProviderConfigurationError, "configuration"),
        (403, ProviderConfigurationError, "configuration"),
        (404, ProviderConfigurationError, "configuration"),
        (413, ProviderInvalidRequestError, "invalid_request"),
        (422, ProviderInvalidRequestError, "invalid_request"),
        (429, ProviderBusyError, "busy"),
        (500, ProviderBusyError, "busy"),
        (529, ProviderBusyError, "busy"),
        (418, ProviderError, "provider_error"),
    ],
)
def test_http_status_maps_to_a_classified_error_and_a_redacted_log(
    status: int,
    expected_exception: type[ProviderError],
    expected_classification: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """The status is the ONLY provider detail allowed into the log."""
    with caplog.at_level(logging.WARNING):
        with pytest.raises(expected_exception):
            _complete(_body(b'{"error":{"message":"SENTINEL-BODY"}}', status))

    assert f"classification={expected_classification}" in caplog.text
    assert f"http_status={status}" in caplog.text
    assert "SENTINEL-BODY" not in caplog.text
    assert _API_KEY not in caplog.text
    assert _MESSAGES[0]["content"] not in caplog.text


@pytest.mark.parametrize(
    ("error_type", "expected_exception", "expected_classification"),
    [
        ("authentication_error", ProviderConfigurationError, "configuration"),
        ("permission_error", ProviderConfigurationError, "configuration"),
        ("not_found_error", ProviderConfigurationError, "configuration"),
        ("billing_error", ProviderConfigurationError, "configuration"),
        ("invalid_request_error", ProviderInvalidRequestError, "invalid_request"),
        ("request_too_large", ProviderInvalidRequestError, "invalid_request"),
        ("rate_limit_error", ProviderBusyError, "busy"),
        ("overloaded_error", ProviderBusyError, "busy"),
        ("api_error", ProviderBusyError, "busy"),
        ("timeout_error", ProviderTimeoutError, "timeout"),
        ("something_new", ProviderError, "provider_error"),
    ],
)
def test_error_frame_type_maps_to_a_classified_error(
    error_type: str,
    expected_exception: type[ProviderError],
    expected_classification: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A mid-stream `error` frame is classified by its closed `type` enum."""
    frame = _sse(
        {"type": "error", "error": {"type": error_type, "message": "SENTINEL-BODY"}}
    )
    with caplog.at_level(logging.WARNING):
        with pytest.raises(expected_exception):
            _complete(_body(frame))

    assert f"classification={expected_classification}" in caplog.text
    assert "SENTINEL-BODY" not in caplog.text


@pytest.mark.parametrize(
    ("handler", "expected_classification"),
    [
        (_raise(httpx.ReadTimeout("SENTINEL-BODY")), "timeout"),
        (_raise(httpx.ConnectError("SENTINEL-BODY")), "transport"),
        (_body(b"SENTINEL-BODY\n"), "malformed_response"),
        (
            _body(
                _sse(
                    {
                        "type": "content_block_delta",
                        "index": 0,
                        "delta": {"type": "text_delta", "text": "partial"},
                    }
                )
            ),
            "incomplete_response",
        ),
    ],
    ids=["timeout", "transport", "malformed_response", "incomplete_response"],
)
def test_transport_and_schema_failures_are_logged_with_a_classification(
    handler: Callable[[httpx.Request], httpx.Response],
    expected_classification: str,
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A failure with no HTTP status still names its class — `http_status=None`."""
    with caplog.at_level(logging.WARNING):
        with pytest.raises(ProviderError):
            _complete(handler)

    assert f"classification={expected_classification}" in caplog.text
    assert "SENTINEL-BODY" not in caplog.text
    assert _API_KEY not in caplog.text


def test_a_malformed_turn_is_an_invalid_request_error() -> None:
    """A shape error is classified too, so the log distinguishes it from a 5xx."""
    with pytest.raises(ProviderInvalidRequestError):
        split_anthropic_messages([{"role": "user", "content": None}])


def test_a_successful_call_logs_no_failure_line(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """The failure log must not fire on the happy path (no false alarms)."""
    with caplog.at_level(logging.WARNING):
        assert _complete(_ok) == "Hello, G major"

    assert "Tutor provider call failed" not in caplog.text
