"""Tests for tutor usage and rate-limit guard."""

import pytest

from app.ratelimit import RateLimiter
from app.tutor.usage import RateLimitExceeded, UsageGuard, UsageLimitExceeded


@pytest.fixture
def rate_limiter():
    """A fresh rate limiter for each test."""
    return RateLimiter(max_attempts=3, window_seconds=60)


@pytest.fixture
def usage_guard(rate_limiter):
    """A usage guard with a daily limit of 100 tokens."""
    return UsageGuard(
        rate_limiter=rate_limiter,
        daily_token_limit=100,
    )


class TestRateLimit:
    """Rate limit enforcement."""

    def test_rate_limit_below(self, usage_guard):
        """Below threshold: calls are allowed."""
        # Make 2 calls (max_attempts - 1)
        usage_guard.check_rate_limit("user1")
        usage_guard.check_rate_limit("user1")
        # Third call should still be allowed (at the boundary)
        usage_guard.check_rate_limit("user1")

    def test_rate_limit_at(self, usage_guard):
        """At threshold: the limit is reached, next call is rejected."""
        # Make max_attempts calls (all allowed)
        usage_guard.check_rate_limit("user1")
        usage_guard.check_rate_limit("user1")
        usage_guard.check_rate_limit("user1")
        # Next call should be rejected
        with pytest.raises(RateLimitExceeded):
            usage_guard.check_rate_limit("user1")

    def test_rate_limit_above(self, usage_guard):
        """Above threshold: calls are rejected."""
        # Make max_attempts calls
        for _ in range(3):
            usage_guard.check_rate_limit("user1")
        # Next calls should be rejected
        with pytest.raises(RateLimitExceeded):
            usage_guard.check_rate_limit("user1")
        with pytest.raises(RateLimitExceeded):
            usage_guard.check_rate_limit("user1")


class TestUsageLimit:
    """Daily usage limit enforcement."""

    def test_usage_limit_below(self, usage_guard):
        """Below threshold: usage is allowed."""
        # Use 50 tokens (below 100 limit)
        usage_guard.check_usage_limit("user1", 50)
        usage_guard.record_usage("user1", 50)
        # Should still be able to use more
        usage_guard.check_usage_limit("user1", 30)

    def test_usage_limit_at(self, usage_guard):
        """At threshold: exactly at the limit is allowed."""
        # Use 70 tokens
        usage_guard.record_usage("user1", 70)
        # Try to use 30 more (exactly at 100 limit)
        usage_guard.check_usage_limit("user1", 30)
        usage_guard.record_usage("user1", 30)

    def test_usage_limit_above(self, usage_guard):
        """Above threshold: usage is rejected."""
        # Use 80 tokens
        usage_guard.record_usage("user1", 80)
        # Try to use 30 more (would exceed 100 limit)
        with pytest.raises(UsageLimitExceeded):
            usage_guard.check_usage_limit("user1", 30)


class TestDailyReset:
    """Daily usage counter reset."""

    def test_daily_reset(self):
        """Usage counters reset after a day."""
        fake_time = [0.0]

        def now_fn():
            return fake_time[0]

        limiter = RateLimiter(max_attempts=1000, window_seconds=60)
        guard = UsageGuard(
            rate_limiter=limiter,
            daily_token_limit=100,
            now_fn=now_fn,
        )

        # Use 80 tokens
        guard.record_usage("user1", 80)

        # Try to use 30 more (would exceed limit)
        with pytest.raises(UsageLimitExceeded):
            guard.check_usage_limit("user1", 30)

        # Advance time by 1 day
        fake_time[0] = 86401.0

        # Now usage should be allowed (counters reset)
        guard.check_usage_limit("user1", 30)


class TestUsageErrorPropagation:
    """Usage errors propagate (not swallowed)."""

    def test_usage_error_not_swallowed(self, tutor_client, tutor_auth_headers):
        """Usage limit errors propagate to the client as HTTP 429."""
        # Configure a low daily limit
        # Override the service with a low-limit usage guard
        from app.tutor.provider_gateway import FakeProviderGateway
        from app.tutor.provider_registry import ProviderRegistry
        from app.tutor.router import set_service
        from app.tutor.service import TutorLimits, TutorService
        from app.tutor.usage import UsageGuard

        registry = ProviderRegistry(
            allowed={"fake": ["fake-model"]},
            provider="fake",
            model="fake-model",
        )
        gateway = FakeProviderGateway()
        usage_guard = UsageGuard(
            rate_limiter=RateLimiter(max_attempts=100, window_seconds=60),
            daily_token_limit=40,
        )
        limits = TutorLimits(
            max_request_bytes=1000,
            max_history_messages=20,
            max_context_bytes=1000,
            max_output_bytes=1000,
        )
        service = TutorService(
            gateway=gateway,
            registry=registry,
            api_key="test-key",
            usage_guard=usage_guard,
            limits=limits,
        )
        set_service(service)

        # Make requests until the usage limit is exceeded
        # Each request uses ~25 tokens (100 chars / 4)
        resp1 = tutor_client.post(
            "/tutor/turn",
            json={"message": "x" * 100, "history": [], "context": ""},
            headers=tutor_auth_headers,
        )
        assert resp1.status_code == 200

        # Second request should exceed the limit
        resp2 = tutor_client.post(
            "/tutor/turn",
            json={"message": "x" * 100, "history": [], "context": ""},
            headers=tutor_auth_headers,
        )
        assert resp2.status_code == 429
        assert "usage limit" in resp2.json()["detail"].lower()
