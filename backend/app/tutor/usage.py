"""Usage and rate-limit guard for the tutor proxy.

Errors are NOT swallowed — they propagate to the router, which converts
them to HTTP 429. This avoids the silent-no-op trap (round 17).
"""

import time
from collections import defaultdict

from ..ratelimit import RateLimiter


class RateLimitExceeded(Exception):
    """The user has exceeded the rate limit."""


class UsageLimitExceeded(Exception):
    """The user has exceeded the daily usage limit."""


class UsageGuard:
    """Enforces rate limits and daily token quotas per user."""

    def __init__(
        self,
        rate_limiter: RateLimiter,
        daily_token_limit: int,
        now_fn: callable = time.monotonic,
    ) -> None:
        self._rate_limiter = rate_limiter
        self._daily_token_limit = daily_token_limit
        self._usage: dict[str, int] = defaultdict(int)
        self._now = now_fn
        self._day_start: float = now_fn()

    def check_rate_limit(self, user_id: str) -> None:
        """Raise RateLimitExceeded if the user has exceeded the rate limit."""
        if not self._rate_limiter.allow(user_id):
            raise RateLimitExceeded("Rate limit exceeded")

    def check_usage_limit(self, user_id: str, estimated_tokens: int) -> None:
        """Raise UsageLimitExceeded if the user would exceed the daily limit."""
        self._maybe_reset_daily()
        used = self._usage[user_id]
        if used + estimated_tokens > self._daily_token_limit:
            raise UsageLimitExceeded("Daily usage limit exceeded")

    def record_usage(self, user_id: str, tokens: int) -> None:
        """Record token usage for the user."""
        self._maybe_reset_daily()
        self._usage[user_id] += tokens

    def _maybe_reset_daily(self) -> None:
        """Reset usage counters if a new day has started."""
        now = self._now()
        if now - self._day_start >= 86400:
            self._usage.clear()
            self._day_start = now
