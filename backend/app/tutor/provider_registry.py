"""Config-driven provider selection (ADR 0131).

The client cannot choose arbitrary model IDs — the registry validates that
the configured provider/model is in the allowlist.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class ResolvedProvider:
    """A validated provider and model combination."""

    name: str
    model_id: str


class ProviderNotAllowedError(Exception):
    """Raised when the configured provider/model is not in the allowlist."""


class ProviderRegistry:
    """Validates and resolves the configured provider against an allowlist."""

    def __init__(
        self,
        allowed: dict[str, list[str]],
        provider: str,
        model: str,
    ) -> None:
        self._allowed = allowed
        self._provider = provider
        self._model = model

    def resolve(self) -> ResolvedProvider:
        """Return the configured provider if it's in the allowlist."""
        allowed_models = self._allowed.get(self._provider)
        if allowed_models is None:
            raise ProviderNotAllowedError(
                f"Provider '{self._provider}' not in allowlist"
            )
        if self._model not in allowed_models:
            raise ProviderNotAllowedError(
                f"Model '{self._model}' not allowed for provider '{self._provider}'"
            )
        return ResolvedProvider(name=self._provider, model_id=self._model)
