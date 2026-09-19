"""Abstract provider interface (ADR 0131).

The gateway hides provider-specific SDK details from the service layer.
Errors are normalized to provider-neutral exceptions — no provider details
leak into responses. The server log gets a classification plus, at most, the
HTTP status (`_log_provider_failure`): never the key, the prompt, the reply
or the provider's response body.
"""

import json
import logging
from dataclasses import dataclass

import httpx

_DEFAULT_BASE_URL = "https://api.openai.com/v1"
_ANTHROPIC_BASE_URL = "https://api.anthropic.com/v1"
#: MiniMax serves an ANTHROPIC-COMPATIBLE Messages API — the same request
#: body, the same SSE frame types, the same `anthropic-version` header — at
#: `https://api.minimax.io/anthropic`, with the Messages path `/v1/messages`
#: under it. Measured from this repository's own MiniMax tooling
#: (`tools/mm-round.sh`), which points Claude Code at that base URL. The
#: constant therefore ends in `/v1`, so the adapter's `{base}/messages` join
#: produces `https://api.minimax.io/anthropic/v1/messages`.
_MINIMAX_BASE_URL = "https://api.minimax.io/anthropic/v1"
#: The Anthropic Messages API is versioned by header, not by URL path.
ANTHROPIC_API_VERSION = "2023-06-01"
_BYTES_PER_TOKEN_ESTIMATE = 4

_logger = logging.getLogger(__name__)


class ProviderError(Exception):
    """Provider-neutral error (redacted, no provider details)."""


class ProviderTimeoutError(ProviderError):
    """The provider did not respond in time."""


class ProviderConfigurationError(ProviderError):
    """The provider refused the credentials or the addressed resource.

    An operator problem (bad/revoked key, wrong model id, wrong base URL), not
    a user problem — retrying the same request cannot fix it.
    """


class ProviderBusyError(ProviderError):
    """The provider is rate-limited or overloaded.

    Retryable: the SAME request may succeed later.
    """


class ProviderInvalidRequestError(ProviderError):
    """The provider rejected the request shape or size."""


# Every subclass above is a `ProviderError`, so the client-facing contract is
# unchanged: `router.py` still answers 502 (504 for the timeout) and
# `stream.py` still emits `provider_error` / `provider_timeout`. The
# distinction exists for the SERVER log, where an operator has to tell "my key
# is wrong" from "Anthropic is overloaded" without ever seeing a provider body.


class ProviderGateway:
    """Abstract base for provider adapters."""

    async def complete(
        self,
        messages: list[dict[str, str]],
        model: str,
        api_key: str,
        timeout_seconds: float,
    ) -> str:
        """Call the provider and return the response text."""
        raise NotImplementedError

    async def aclose(self) -> None:
        """Release provider resources at application shutdown.

        The base implementation is a no-op so the composition root can close
        every gateway uniformly (`main.py` lifespan) without knowing which
        adapter is configured.
        """
        return None


class FakeProviderGateway(ProviderGateway):
    """Test double that returns a predictable response.

    Intentionally does NOT log messages or API keys — the fake is used in
    tests that verify the no-prompt-log invariant.
    """

    def __init__(
        self,
        response: str = "fake-tutor-response",
        should_timeout: bool = False,
        should_error: bool = False,
    ) -> None:
        self._response = response
        self._should_timeout = should_timeout
        self._should_error = should_error
        self.calls: list[dict] = []

    async def complete(
        self,
        messages: list[dict[str, str]],
        model: str,
        api_key: str,
        timeout_seconds: float,
    ) -> str:
        self.calls.append({"messages": messages, "model": model})
        if self._should_timeout:
            raise ProviderTimeoutError("Provider timed out")
        if self._should_error:
            raise ProviderError("Provider error")
        return self._response


class OpenAiProviderGateway(ProviderGateway):
    """Chat Completions adapter with provider-neutral failure handling."""

    def __init__(
        self,
        max_output_bytes: int,
        client: httpx.AsyncClient | None = None,
        base_url: str = _DEFAULT_BASE_URL,
    ) -> None:
        if max_output_bytes <= 0:
            raise ValueError("max_output_bytes must be positive")

        self._client = client or httpx.AsyncClient()
        self._base_url = base_url.rstrip("/")
        self._max_tokens = max(1, max_output_bytes // _BYTES_PER_TOKEN_ESTIMATE)

    async def complete(
        self,
        messages: list[dict[str, str]],
        model: str,
        api_key: str,
        timeout_seconds: float,
    ) -> str:
        """Return response text while normalizing transport and schema failures."""
        try:
            response = await self._client.post(
                f"{self._base_url}/chat/completions",
                headers={
                    "Authorization": f"Bearer {api_key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model,
                    "messages": messages,
                    "max_tokens": self._max_tokens,
                },
                timeout=timeout_seconds,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
        except httpx.TimeoutException:
            raise ProviderTimeoutError("Provider request timed out") from None
        except (httpx.HTTPError, ValueError, KeyError, TypeError, IndexError):
            raise ProviderError("Provider request failed") from None

        if not isinstance(content, str):
            raise ProviderError("Provider response was invalid")
        return content

    async def aclose(self) -> None:
        """Release the owned or injected HTTP client after its final use."""
        await self._client.aclose()


# --- Anthropic Messages API adapter ------------------------------------------

#: Roles the Anthropic Messages API accepts inside `messages`. Anything else
#: (the tutor service appends the assembled context as a `system` turn) is
#: carried out of band in the top-level `system` field.
_ANTHROPIC_CHAT_ROLES = ("user", "assistant")

#: HTTP status -> provider-neutral failure class. The status code itself is
#: NOT a secret and never carries prompt content, so it is the one provider
#: detail this adapter is allowed to log. Anything unlisted stays the generic
#: `ProviderError`; 5xx is retryable as a class, so it lands on "busy" with
#: 529 (Anthropic's overloaded status) rather than being singled out.
_ANTHROPIC_STATUS_ERRORS: dict[int, tuple[type[ProviderError], str, str]] = {
    400: (
        ProviderInvalidRequestError,
        "invalid_request",
        "Provider request was invalid",
    ),
    401: (
        ProviderConfigurationError,
        "configuration",
        "Provider rejected the credentials",
    ),
    403: (
        ProviderConfigurationError,
        "configuration",
        "Provider rejected the credentials",
    ),
    404: (
        ProviderConfigurationError,
        "configuration",
        "Provider resource is unavailable",
    ),
    413: (
        ProviderInvalidRequestError,
        "invalid_request",
        "Provider request was invalid",
    ),
    422: (
        ProviderInvalidRequestError,
        "invalid_request",
        "Provider request was invalid",
    ),
    429: (ProviderBusyError, "busy", "Provider is busy — retry shortly"),
}

#: `error` SSE frame `error.type` -> the same classification. The type is a
#: closed provider enum (never free text and never prompt-derived), so it is
#: safe to branch on; the provider's `message` is NOT read.
_ANTHROPIC_ERROR_TYPES: dict[str, tuple[type[ProviderError], str, str]] = {
    "authentication_error": (
        ProviderConfigurationError,
        "configuration",
        "Provider rejected the credentials",
    ),
    "permission_error": (
        ProviderConfigurationError,
        "configuration",
        "Provider rejected the credentials",
    ),
    "not_found_error": (
        ProviderConfigurationError,
        "configuration",
        "Provider resource is unavailable",
    ),
    "billing_error": (
        ProviderConfigurationError,
        "configuration",
        "Provider resource is unavailable",
    ),
    "invalid_request_error": (
        ProviderInvalidRequestError,
        "invalid_request",
        "Provider request was invalid",
    ),
    "request_too_large": (
        ProviderInvalidRequestError,
        "invalid_request",
        "Provider request was invalid",
    ),
    "rate_limit_error": (ProviderBusyError, "busy", "Provider is busy — retry shortly"),
    "overloaded_error": (ProviderBusyError, "busy", "Provider is busy — retry shortly"),
    "api_error": (ProviderBusyError, "busy", "Provider is busy — retry shortly"),
    "timeout_error": (
        ProviderTimeoutError,
        "timeout",
        "Provider request timed out",
    ),
}


def _log_provider_failure(classification: str, status: int | None = None) -> None:
    """Log a REDACTED failure summary.

    The classification and (when there is one) the HTTP status are the whole
    payload: never the API key, the prompt, the reply, or the provider's
    response body — a 400 body echoes the request back (AGENTS.md §5).
    """
    _logger.warning(
        "Tutor provider call failed (classification=%s, http_status=%s)",
        classification,
        status,
    )


def _anthropic_status_error(status: int) -> ProviderError:
    """Map an HTTP status onto a redacted, provider-neutral exception."""
    entry = _ANTHROPIC_STATUS_ERRORS.get(status)
    if entry is None:
        entry = (
            (ProviderBusyError, "busy", "Provider is busy — retry shortly")
            if status >= 500
            else (ProviderError, "provider_error", "Provider request failed")
        )
    error_type, classification, message = entry
    _log_provider_failure(classification, status)
    return error_type(message)


def split_anthropic_messages(
    messages: list[dict[str, str]],
) -> tuple[str, list[dict[str, str]]]:
    """Split the tutor's flat message list into Anthropic's request shape.

    The tutor service (`service.py::turn`) builds one flat list: the history,
    the student's message, then the assembled context as a `system` entry.
    The Anthropic Messages API instead takes the system prompt out of band and
    requires `messages` to start with `user` and to alternate roles, so this
    function:

    * moves every non-chat role into the top-level `system` text,
    * merges consecutive same-role turns (the API rejects repeats),
    * drops a leading `assistant` turn (the API requires a `user` first).

    Normalizing here rather than at the call site keeps the provider-neutral
    `ProviderGateway.complete` contract unchanged.
    """
    system_parts: list[str] = []
    chat: list[dict[str, str]] = []
    for message in messages:
        role = message.get("role")
        content = message.get("content")
        if not isinstance(role, str) or not isinstance(content, str):
            raise ProviderInvalidRequestError("Provider request was invalid")
        if role not in _ANTHROPIC_CHAT_ROLES:
            if content:
                system_parts.append(content)
            continue
        if chat and chat[-1]["role"] == role:
            chat[-1]["content"] = f"{chat[-1]['content']}\n\n{content}"
            continue
        if not chat and role == "assistant":
            continue
        chat.append({"role": role, "content": content})
    return "\n\n".join(system_parts), chat


def _anthropic_stream_error(event: dict) -> ProviderError:
    """Classify an `error` SSE frame without reading its message text."""
    error = event.get("error")
    error_type = error.get("type") if isinstance(error, dict) else None
    entry = (
        _ANTHROPIC_ERROR_TYPES.get(error_type) if isinstance(error_type, str) else None
    )
    if entry is None:
        entry = (ProviderError, "provider_error", "Provider returned an error")
    exception_type, classification, message = entry
    _log_provider_failure(classification)
    return exception_type(message)


async def _read_anthropic_stream(
    response: httpx.Response,
) -> tuple[str, int | None]:
    """Fold an Anthropic SSE stream into the reply text and the output tokens.

    Event mapping (Messages API streaming contract):
    `content_block_delta`/`text_delta` -> reply text, `message_delta` -> usage,
    `message_stop` -> end of stream, `error` -> the classified, redacted
    exception from `_ANTHROPIC_ERROR_TYPES`. Anything else (`message_start`,
    `content_block_start`/`_stop`, `ping`, comment lines) is ignored. A stream
    that ends without `message_stop` is a truncated response, not a short
    answer — it fails closed.
    """
    parts: list[str] = []
    output_tokens: int | None = None
    completed = False

    async for line in response.aiter_lines():
        stripped = line.strip()
        if not stripped or stripped.startswith((":", "event:", "id:", "retry:")):
            continue
        if not stripped.startswith("data:"):
            _log_provider_failure("malformed_response")
            raise ProviderError("Provider response was invalid")
        raw = stripped[len("data:") :].strip()
        if not raw:
            continue
        try:
            event = json.loads(raw)
        except ValueError:
            _log_provider_failure("malformed_response")
            raise ProviderError("Provider response was invalid") from None
        if not isinstance(event, dict):
            _log_provider_failure("malformed_response")
            raise ProviderError("Provider response was invalid")

        event_type = event.get("type")
        if event_type == "content_block_delta":
            delta = event.get("delta")
            if isinstance(delta, dict) and delta.get("type") == "text_delta":
                text = delta.get("text")
                if not isinstance(text, str):
                    _log_provider_failure("malformed_response")
                    raise ProviderError("Provider response was invalid")
                parts.append(text)
        elif event_type == "message_delta":
            usage = event.get("usage")
            if isinstance(usage, dict):
                tokens = usage.get("output_tokens")
                if isinstance(tokens, int) and not isinstance(tokens, bool):
                    output_tokens = tokens
        elif event_type == "error":
            raise _anthropic_stream_error(event)
        elif event_type == "message_stop":
            completed = True
            break

    if not completed:
        _log_provider_failure("incomplete_response")
        raise ProviderError("Provider response was incomplete")
    return "".join(parts), output_tokens


@dataclass(frozen=True)
class AnthropicCompatibleProfile:
    """The per-vendor wire details of ONE Anthropic-compatible endpoint.

    Everything the Messages API contract leaves to the vendor lives here —
    the base URL and how the key is presented — so a second provider is a
    PROFILE, not a second adapter: the request body, the SSE folding and the
    entire error classification below stay literally the same code, and a
    bug fixed there is fixed for every provider at once.
    """

    name: str
    base_url: str
    auth_header: str
    auth_prefix: str = ""

    def auth_headers(self, api_key: str) -> dict[str, str]:
        """Render the single authentication header this vendor expects."""
        return {self.auth_header: f"{self.auth_prefix}{api_key}"}


#: Anthropic's own Messages API: the key rides the `x-api-key` header.
ANTHROPIC_PROFILE = AnthropicCompatibleProfile(
    name="anthropic",
    base_url=_ANTHROPIC_BASE_URL,
    auth_header="x-api-key",
)

#: MiniMax M3 (the tutor's provider). MEASURED from this repository's own
#: MiniMax tooling (`tools/mm-round.sh`), which drives the same endpoint by
#: exporting `ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic` plus
#: `ANTHROPIC_AUTH_TOKEN` — i.e. the key is presented as
#: `Authorization: Bearer <key>`, not as `x-api-key`. Whether MiniMax ALSO
#: accepts `x-api-key` is not measured anywhere in this repository, so the
#: adapter sends the one header that is: exactly one credential leaves the
#: process per request, never a speculative second copy of the secret.
MINIMAX_PROFILE = AnthropicCompatibleProfile(
    name="minimax",
    base_url=_MINIMAX_BASE_URL,
    auth_header="Authorization",
    auth_prefix="Bearer ",
)

#: Profile per provider name, for the composition root's lookup.
ANTHROPIC_COMPATIBLE_PROFILES: dict[str, AnthropicCompatibleProfile] = {
    ANTHROPIC_PROFILE.name: ANTHROPIC_PROFILE,
    MINIMAX_PROFILE.name: MINIMAX_PROFILE,
}


class AnthropicProviderGateway(ProviderGateway):
    """Anthropic Messages API adapter with provider-neutral failure handling.

    Streaming (`"stream": true`) is used even though `complete()` returns the
    whole reply: it is the shape that survives a long answer without tripping
    a request timeout, and the tutor's own SSE transport (`stream.py`) chunks
    the finished reply into `delta` frames from there (ADR 0142 D10).

    It serves EVERY Anthropic-compatible endpoint, selected by `profile`:
    Anthropic itself and MiniMax M3 differ only in the base URL and in how
    the key is presented (`AnthropicCompatibleProfile`). `base_url` stays an
    explicit override for a proxy in front of either vendor; left at `None`
    the profile's own URL is used.
    """

    def __init__(
        self,
        max_output_bytes: int,
        client: httpx.AsyncClient | None = None,
        base_url: str | None = None,
        api_version: str = ANTHROPIC_API_VERSION,
        profile: AnthropicCompatibleProfile = ANTHROPIC_PROFILE,
    ) -> None:
        if max_output_bytes <= 0:
            raise ValueError("max_output_bytes must be positive")

        self._client = client or httpx.AsyncClient()
        self._profile = profile
        self._base_url = (base_url or profile.base_url).rstrip("/")
        self._api_version = api_version
        # Shared with the OpenAI adapter: the service truncates the reply to
        # `max_output_bytes` anyway, so asking for more would only burn tokens.
        self._max_tokens = max(1, max_output_bytes // _BYTES_PER_TOKEN_ESTIMATE)

    @property
    def profile(self) -> AnthropicCompatibleProfile:
        """The vendor profile this adapter was composed with.

        Read-only, and free of the key: it exists so a composition test can
        assert WHICH provider a configuration actually built without reaching
        into private attributes.
        """
        return self._profile

    @property
    def base_url(self) -> str:
        """The resolved endpoint root (profile default or operator override)."""
        return self._base_url

    async def complete(
        self,
        messages: list[dict[str, str]],
        model: str,
        api_key: str,
        timeout_seconds: float,
    ) -> str:
        """Return the reply text while normalizing transport and schema failures."""
        # Pre-flight validation: no provider call happened, so it produces no
        # `_log_provider_failure` line — that log describes CALL outcomes only.
        system_prompt, chat = split_anthropic_messages(messages)
        if not chat:
            raise ProviderInvalidRequestError("Provider request was invalid")

        payload: dict[str, object] = {
            "model": model,
            "max_tokens": self._max_tokens,
            "messages": chat,
            "stream": True,
        }
        if system_prompt:
            payload["system"] = system_prompt

        try:
            async with self._client.stream(
                "POST",
                f"{self._base_url}/messages",
                headers={
                    # The vendor-specific credential header comes from the
                    # profile; everything below is the Messages API contract
                    # and is identical for every compatible provider.
                    **self._profile.auth_headers(api_key),
                    "anthropic-version": self._api_version,
                    "content-type": "application/json",
                    "accept": "text/event-stream",
                },
                json=payload,
                timeout=timeout_seconds,
            ) as response:
                if response.status_code >= 400:
                    # The body may echo the prompt back — never read or log it;
                    # only the status crosses into the log.
                    raise _anthropic_status_error(response.status_code)
                reply, output_tokens = await _read_anthropic_stream(response)
        except httpx.TimeoutException:
            _log_provider_failure("timeout")
            raise ProviderTimeoutError("Provider request timed out") from None
        except httpx.HTTPError:
            # Connect/read/protocol failure: the exception text can carry the
            # target URL, so it is dropped rather than logged.
            _log_provider_failure("transport")
            raise ProviderError("Provider request failed") from None

        # Metadata only — never the prompt, the reply or the key (AGENTS.md §5).
        # The profile NAME is configuration, not a secret, and it is what an
        # operator needs to tell two configured providers apart in one log.
        _logger.info(
            "Tutor provider stream completed (provider=%s, output_tokens=%s)",
            self._profile.name,
            output_tokens,
        )
        return reply

    async def aclose(self) -> None:
        """Release the owned or injected HTTP client after its final use."""
        await self._client.aclose()
