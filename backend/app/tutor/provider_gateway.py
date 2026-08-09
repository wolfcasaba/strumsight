"""Abstract provider interface (ADR 0131).

The gateway hides provider-specific SDK details from the service layer.
Errors are normalized to provider-neutral exceptions — no provider details
leak into logs or responses.
"""

import httpx

_DEFAULT_BASE_URL = "https://api.openai.com/v1"
_BYTES_PER_TOKEN_ESTIMATE = 4


class ProviderError(Exception):
    """Provider-neutral error (redacted, no provider details)."""


class ProviderTimeoutError(ProviderError):
    """The provider did not respond in time."""


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
