"""Tutor turn orchestration.

The service validates request limits, checks rate/usage limits, calls the
provider gateway, and returns a redacted response. Provider errors are
normalized; usage errors propagate (not swallowed).
"""

import logging

from .provider_gateway import ProviderError, ProviderGateway, ProviderTimeoutError
from .provider_registry import ProviderRegistry
from .schemas import TutorTurnRequest, TutorTurnResponse
from .usage import UsageGuard

_logger = logging.getLogger(__name__)


class TutorLimits:
    """Request/response size limits."""

    def __init__(
        self,
        max_request_bytes: int,
        max_history_messages: int,
        max_context_bytes: int,
        max_output_bytes: int,
    ) -> None:
        self.max_request_bytes = max_request_bytes
        self.max_history_messages = max_history_messages
        self.max_context_bytes = max_context_bytes
        self.max_output_bytes = max_output_bytes


class RequestTooLargeError(Exception):
    """The request exceeds size limits."""


class TutorService:
    """Orchestrates a tutor turn: validate → limit check → provider → respond."""

    def __init__(
        self,
        gateway: ProviderGateway,
        registry: ProviderRegistry,
        api_key: str,
        usage_guard: UsageGuard,
        limits: TutorLimits,
        timeout_seconds: float = 30.0,
    ) -> None:
        self._gateway = gateway
        self._registry = registry
        self._api_key = api_key
        self._usage_guard = usage_guard
        self._limits = limits
        self._timeout = timeout_seconds

    async def turn(self, user_id: str, request: TutorTurnRequest) -> TutorTurnResponse:
        """Process a tutor turn. Raises RequestTooLargeError, RateLimitExceeded,
        UsageLimitExceeded, or ProviderError/ProviderTimeoutError."""
        # Validate request limits
        self._validate_request(request)

        # Check rate limit (propagates RateLimitExceeded)
        self._usage_guard.check_rate_limit(user_id)

        # Estimate tokens (rough: 1 token ≈ 4 chars)
        estimated_tokens = max(1, len(request.message) // 4)
        # Check usage limit (propagates UsageLimitExceeded)
        self._usage_guard.check_usage_limit(user_id, estimated_tokens)

        # Build messages for the provider
        messages = [{"role": m.role, "content": m.content} for m in request.history]
        messages.append({"role": "user", "content": request.message})
        if request.context:
            messages.append({"role": "system", "content": request.context})

        # Resolve provider (config-driven, ADR 0131)
        provider = self._registry.resolve()

        # Call provider — normalize errors (redacted, no provider details)
        try:
            reply = await self._gateway.complete(
                messages, provider.model_id, self._api_key, self._timeout
            )
        except ProviderTimeoutError:
            _logger.warning("Provider timeout for user %s", user_id)
            raise
        except ProviderError:
            _logger.warning("Provider error for user %s", user_id)
            raise

        # Truncate output if needed
        reply_bytes = reply.encode("utf-8")
        if len(reply_bytes) > self._limits.max_output_bytes:
            reply = reply_bytes[: self._limits.max_output_bytes].decode(
                "utf-8", errors="ignore"
            )

        # Record usage
        actual_tokens = max(1, len(reply) // 4)
        self._usage_guard.record_usage(user_id, estimated_tokens + actual_tokens)

        # Log metadata only — NEVER log the prompt or response content
        _logger.info(
            "Tutor turn completed for user %s (tokens: %d)",
            user_id,
            estimated_tokens + actual_tokens,
        )

        return TutorTurnResponse(reply=reply)

    def _validate_request(self, request: TutorTurnRequest) -> None:
        """Validate request size limits. Raises RequestTooLargeError."""
        if len(request.message.encode("utf-8")) > self._limits.max_request_bytes:
            raise RequestTooLargeError("Message too large")
        if len(request.history) > self._limits.max_history_messages:
            raise RequestTooLargeError("History too long")
        if len(request.context.encode("utf-8")) > self._limits.max_context_bytes:
            raise RequestTooLargeError("Context too large")
