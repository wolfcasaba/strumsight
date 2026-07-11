"""A small in-memory sliding-window rate limiter (round 120).

Deliberately stdlib-only: this backend targets a single small instance, so a
process-local limiter is honest protection against credential brute-force
without a Redis dependency. If the service ever scales past one process, swap
the storage — the interface stays.
"""

import time
from collections import deque
from typing import Callable


class RateLimiter:
    """Allow up to [max_attempts] events per [key] per sliding window."""

    def __init__(
        self,
        max_attempts: int,
        window_seconds: float,
        now_fn: Callable[[], float] = time.monotonic,
    ) -> None:
        self.max_attempts = max_attempts
        self.window_seconds = window_seconds
        self._now = now_fn
        self._hits: dict[str, deque[float]] = {}

    def allow(self, key: str) -> bool:
        """Record an attempt for [key]; False once the window is full."""
        now = self._now()
        q = self._hits.get(key)
        if q is None:
            q = self._hits[key] = deque()
        while q and now - q[0] >= self.window_seconds:
            q.popleft()
        if len(q) >= self.max_attempts:
            return False
        q.append(now)
        # Opportunistic cleanup keeps the dict from accumulating dead keys
        # (attackers rotate IPs). AFTER the append, so the current key is
        # never dead — pruning it earlier silently un-throttled everyone.
        if len(self._hits) > 1024:
            self._prune(now)
        return True

    def _prune(self, now: float) -> None:
        dead = [
            k
            for k, q in self._hits.items()
            if not q or now - q[-1] >= self.window_seconds
        ]
        for k in dead:
            del self._hits[k]

    def reset(self) -> None:
        """Forget everything (test isolation)."""
        self._hits.clear()
