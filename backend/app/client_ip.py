"""Trusted-proxy-aware client identity for the auth throttles (R14).

MEASURED problem (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.4):
`routers/auth.py` keyed its login (10/min) and register (5/min) sliding
windows on `request.client.host`. On the live deploy Caddy terminates TLS
and proxies to the container, so EVERY caller arrives from the same
docker-bridge address — one shared budget for all users, and the resulting
`429` surfaces in the app as a generic network error
(`authErrorNetwork`). That looks exactly like "login is broken".

The fix is deliberately narrow and fail-closed. `X-Forwarded-For` is
caller-supplied, so trusting it unconditionally hands every caller a free
rate-limit bypass — measured precedent in this codebase: E09-R03 review F1,
60/60 requests slipped past a 30/min limit by rotating the header (see the
`_client_key` docstrings in `app/community/routers/handles.py` and
`search.py`, which for that reason still key on the socket peer). Here the
header is read ONLY when the direct socket peer is one of the explicitly
configured `Settings.trusted_proxy_ips`, and the DEFAULT is an empty list,
so a deployment that has not measured its proxy hop keeps the exact
pre-R14 behaviour.

DEPLOYMENT REQUIREMENT (the first hop must be the real client). Caddy's
`reverse_proxy` APPENDS the peer address to any `X-Forwarded-For` the
caller already sent, so with a stock config a caller can prepend a
value of its own and pick its own throttle bucket. The reverse proxy must
therefore OVERWRITE the header — for Caddy:

    reverse_proxy 127.0.0.1:8010 {
        header_up X-Forwarded-For {remote_host}
    }

`docs/operations/backend-live-deploy.md` §7 carries this as part of the
runbook. Without that line, list no proxy here at all: the shared-bucket
throttle is a smaller problem than a throttle anyone can dodge.
"""

from __future__ import annotations

from fastapi import Request

from .config import Settings

UNKNOWN_CLIENT = "unknown"


def client_ip_for_throttle(request: Request, settings: Settings) -> str:
    """The rate-limit bucket key for `request`.

    The direct socket peer, EXCEPT when that peer is a configured trusted
    proxy and it forwarded an `X-Forwarded-For` — then the first (client)
    hop of that header. Never raises; an unknown peer collapses to a single
    shared `"unknown"` bucket, which throttles more, never less.
    """
    peer = request.client.host if request.client is not None else None
    if not peer:
        return UNKNOWN_CLIENT
    if peer not in settings.trusted_proxy_ips:
        return peer
    forwarded = request.headers.get("x-forwarded-for")
    if not forwarded:
        return peer
    first_hop = forwarded.split(",")[0].strip()
    return first_hop or peer
