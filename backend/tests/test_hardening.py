"""Round 120 — production hardening: auth rate-limiting + prod-boot guards.

The account backend was dev-grade (documented): no brute-force throttle on
/auth/*, a fixed dev secret, and wildcard CORS. Hardened here; the prod
guards fail the BOOT, not a request — a misconfigured deploy must never
serve traffic.
"""

import pytest

from app.config import Settings
from app.main import create_app
from app.ratelimit import RateLimiter
from app.routers.auth import login_limiter


class TestRateLimiter:
    def test_allows_up_to_the_limit_then_blocks(self):
        clock = [0.0]
        rl = RateLimiter(max_attempts=3, window_seconds=60, now_fn=lambda: clock[0])
        assert [rl.allow("ip"), rl.allow("ip"), rl.allow("ip")] == [True] * 3
        assert rl.allow("ip") is False

    def test_window_expiry_frees_the_key(self):
        clock = [0.0]
        rl = RateLimiter(max_attempts=2, window_seconds=60, now_fn=lambda: clock[0])
        assert rl.allow("ip") and rl.allow("ip")
        assert rl.allow("ip") is False
        clock[0] = 61.0  # the old attempts age out of the sliding window
        assert rl.allow("ip") is True

    def test_keys_are_independent(self):
        rl = RateLimiter(max_attempts=1, window_seconds=60)
        assert rl.allow("attacker") is True
        assert rl.allow("attacker") is False
        assert rl.allow("innocent") is True


class TestAuthThrottle:
    def test_login_brute_force_gets_429_with_retry_after(self, client):
        for _ in range(login_limiter.max_attempts):
            r = client.post(
                "/auth/login",
                json={"email": "ghost@strumsight.app", "password": "wrong"},
            )
            assert r.status_code == 401
        r = client.post(
            "/auth/login",
            json={"email": "ghost@strumsight.app", "password": "wrong"},
        )
        assert r.status_code == 429
        assert "Retry-After" in r.headers

    def test_throttle_blocks_even_correct_credentials(self, client, auth_headers):
        # A brute-forcer must not learn the password by the 429 disappearing.
        for _ in range(login_limiter.max_attempts):
            client.post(
                "/auth/login",
                json={"email": "player@strumsight.app", "password": "wrong"},
            )
        r = client.post(
            "/auth/login",
            json={"email": "player@strumsight.app", "password": "sixstrings"},
        )
        assert r.status_code == 429

    def test_register_is_throttled_too(self, client):
        from app.routers.auth import register_limiter

        for i in range(register_limiter.max_attempts):
            r = client.post(
                "/auth/register",
                json={"email": f"u{i}@strumsight.app", "password": "sixstrings"},
            )
            assert r.status_code == 201
        r = client.post(
            "/auth/register",
            json={"email": "one-too-many@strumsight.app", "password": "sixstrings"},
        )
        assert r.status_code == 429


class TestProdBootGuards:
    def test_prod_with_dev_secret_refuses_to_boot(self):
        s = Settings(env="prod", cors_origins=["https://app.strumsight.app"])
        with pytest.raises(RuntimeError, match="secret"):
            create_app(s)

    def test_prod_with_wildcard_cors_refuses_to_boot(self):
        s = Settings(env="prod", secret_key="a-real-32-char-production-secret")
        with pytest.raises(RuntimeError, match="CORS"):
            create_app(s)

    def test_prod_with_real_config_boots(self):
        s = Settings(
            env="prod",
            secret_key="a-real-32-char-production-secret",
            cors_origins=["https://app.strumsight.app"],
        )
        assert create_app(s) is not None

    def test_dev_defaults_still_boot_with_zero_setup(self):
        assert create_app(Settings()) is not None
