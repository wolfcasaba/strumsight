"""Abstract provider interface (ADR 0131).

The gateway hides provider-specific SDK details from the service layer.
Errors are normalized to provider-neutral exceptions — no provider details
leak into logs or responses.
"""


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
