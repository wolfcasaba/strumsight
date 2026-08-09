"""Contract tests for the OpenAI tutor provider adapter."""

import asyncio
import json
import logging
from collections.abc import Callable
from typing import Any

import httpx
import pytest

from app.tutor.provider_gateway import (
    OpenAiProviderGateway,
    ProviderError,
    ProviderTimeoutError,
)

_API_KEY = "sk-SENTINEL-KEY"
_BASE_URL = "https://provider.example/v1"
_MESSAGES = [{"role": "user", "content": "PROMPT-SENTINEL"}]
_MODEL = "configured-model"
_MAX_OUTPUT_BYTES = 2000


def _gateway(
    handler: Callable[[httpx.Request], httpx.Response],
) -> OpenAiProviderGateway:
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return OpenAiProviderGateway(
        client=client,
        base_url=_BASE_URL,
        max_output_bytes=_MAX_OUTPUT_BYTES,
    )


async def _complete(
    handler: Callable[[httpx.Request], httpx.Response],
    timeout_seconds: float = 5.0,
) -> str:
    gateway = _gateway(handler)
    try:
        return await gateway.complete(
            messages=_MESSAGES,
            model=_MODEL,
            api_key=_API_KEY,
            timeout_seconds=timeout_seconds,
        )
    finally:
        await gateway.aclose()


def test_complete_posts_configured_model_and_messages() -> None:
    """The adapter sends the Chat Completions contract and returns content."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["method"] = request.method
        captured["url"] = str(request.url)
        captured["authorization"] = request.headers["authorization"]
        captured["content_type"] = request.headers["content-type"]
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": "hello"}}]},
        )

    assert asyncio.run(_complete(handler)) == "hello"
    assert captured == {
        "method": "POST",
        "url": "https://provider.example/v1/chat/completions",
        "authorization": f"Bearer {_API_KEY}",
        "content_type": "application/json",
        "body": {
            "model": _MODEL,
            "messages": _MESSAGES,
            "max_tokens": 500,
        },
    }


@pytest.mark.parametrize(
    ("handler", "expected_exception"),
    [
        (
            lambda request: (_ for _ in ()).throw(
                httpx.ReadTimeout("SENTINEL-BODY", request=request)
            ),
            ProviderTimeoutError,
        ),
        (
            lambda request: httpx.Response(401, text="SENTINEL-BODY", request=request),
            ProviderError,
        ),
        (
            lambda request: httpx.Response(500, text="SENTINEL-BODY", request=request),
            ProviderError,
        ),
        (
            lambda request: (_ for _ in ()).throw(
                httpx.ConnectError("SENTINEL-BODY", request=request)
            ),
            ProviderError,
        ),
        (
            lambda request: httpx.Response(200, text="SENTINEL-BODY", request=request),
            ProviderError,
        ),
        (
            lambda request: httpx.Response(
                200,
                json={"choices": [{"message": {}}]},
                request=request,
            ),
            ProviderError,
        ),
        (
            lambda request: httpx.Response(
                200,
                json={"choices": [{"message": {"content": 123}}]},
                request=request,
            ),
            ProviderError,
        ),
    ],
    ids=[
        "timeout",
        "http_4xx",
        "http_5xx",
        "connect_error",
        "invalid_json",
        "missing_content",
        "non_string_content",
    ],
)
def test_complete_normalizes_failures_without_leaking_details(
    handler: Callable[[httpx.Request], httpx.Response],
    expected_exception: type[Exception],
) -> None:
    """All provider failures are redacted provider-neutral exceptions."""
    with pytest.raises(expected_exception) as raised:
        asyncio.run(_complete(handler))

    message = str(raised.value).lower()
    assert _API_KEY.lower() not in message
    assert "provider.example" not in message
    assert "openai" not in message
    assert "sentinel-body" not in message


@pytest.mark.parametrize("timeout_seconds", [0.5, 5.0, 30.0])
def test_complete_passes_timeout_to_http_client(timeout_seconds: float) -> None:
    """The requested timeout is forwarded without local adjustment."""
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["timeout"] = request.extensions["timeout"]
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": "hello"}}]},
            request=request,
        )

    assert asyncio.run(_complete(handler, timeout_seconds)) == "hello"
    assert set(captured["timeout"].values()) == {timeout_seconds}


@pytest.mark.parametrize(
    "handler",
    [
        lambda request: httpx.Response(
            200,
            json={"choices": [{"message": {"content": "hello"}}]},
            request=request,
        ),
        lambda request: httpx.Response(500, text="SENTINEL-BODY", request=request),
    ],
    ids=["success", "error"],
)
def test_complete_never_logs_prompt_or_api_key(
    handler: Callable[[httpx.Request], httpx.Response], caplog: pytest.LogCaptureFixture
) -> None:
    """Neither successful nor failed calls log secrets or prompt content."""
    with caplog.at_level(logging.DEBUG):
        try:
            asyncio.run(_complete(handler))
        except ProviderError:
            pass

    assert _MESSAGES[0]["content"] not in caplog.text
    assert _API_KEY not in caplog.text
