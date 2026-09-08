#!/usr/bin/env python3
"""Live device-backend bring-up smoke (E16-R04, ADR 0503).

A companion to `tool/release/production_smoke.py` (E12-R31), NOT a
replacement (ADR 0503 D3 — the difference table is in the ADR). Where
`production_smoke.py` measures a production/internal-cohort deploy's health
with independent, read-mostly checks, this tool walks the ONE chain a fresh
phone actually needs before its Community screens work: reachability ->
register -> login -> `/auth/me` -> settings read/write -> community profile
create/read/update -> community safety-list read. It targets a dev/lab
instance reachable over plain LAN `http://`, not a `https://` production
endpoint, and it REGISTERS a fresh throwaway account every run instead of
logging into an existing one.

The set of endpoints this tool is responsible for covering comes from
`docs/contracts/client-backend-endpoints.json` (E15-R12, ADR 0497 D5) —
`classify_contract()` below reads that artifact and assigns each of its
entries one of three buckets (ADR 0503 D1):

  exercised       the bring-up chain calls it directly (`_EXERCISED_ORDER`).
  not_exercised   documented reason it is out of scope for a SINGLE-account
                   bring-up run (`_NOT_EXERCISED`) — e.g. it needs a second
                   account, or belongs to an unrelated subsystem (tutor,
                   diagnostics).
  known_gap       the contract itself marks it `known_gap` (a client call
                   site with no backend route yet) — the chain expects a
                   `404` and reports the path's PRESENCE as the failure.

An entry that lands in none of the three buckets is `unclassified`, and
`main()` fails closed on that (exit 2) BEFORE any network call — a new
client-called endpoint landing in the contract without an explicit
classification here must break this tool, not slip through silently
(ADR 0503 D1, round brief §6.1 "smoke kihagyja a community felületet").

**D2 — the chain stops at the first divergence.** Unlike
`production_smoke.py`'s independent checks, `run_chain()` below is a single
ordered sequence: a step's failure means every later step is skipped, and
`main()` reports exactly where the chain broke (expected vs measured
status/path) instead of a partial "N/M passed" summary.

**D4 — duck-typed client.** `UrllibClient` below exposes the same
`.get(path, headers=)` / `.post(path, json=, headers=)` / `.put(path,
json=, headers=)` shape as `production_smoke.py`'s `UrllibClient`, so
`run_chain()` runs unmodified against a real deploy (this class) and, in
`backend/tests/test_live_smoke_contract.py`, against an in-process
`fastapi.testclient.TestClient` with no network at all.

Standard library only (`urllib.request`) — this tool has to run standalone
against a real LAN target, where a third-party package is not guaranteed to
be installed (same precedent as `production_smoke.py`).

Exit codes:
  0  the full chain passed and every contract entry was classified
  1  the chain diverged from the expected shape at some step (a real
     bring-up finding — see the printed diff)
  2  usage error, OR the contract has an unclassified entry (a tool-
     completeness problem, not a deploy problem)
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

_REPO_ROOT = Path(__file__).resolve().parents[2]
_DEFAULT_CONTRACT_PATH = (
    _REPO_ROOT / "docs" / "contracts" / "client-backend-endpoints.json"
)

# No route in `backend/app/community/routers/challenges.py` matches ANY id
# shape for the three known_gap paths (there is no GET route registered at
# all) — a fixed placeholder is enough to prove the path 404s.
_KNOWN_GAP_PLACEHOLDER_ID = "00000000-0000-0000-0000-000000000000"


class _HttpError(Exception):
    """A request could not even reach the server — distinct from an HTTP
    response with a bad status, which is a normal (if failing) `Response`.
    Mirrors `production_smoke.py`'s `_HttpError`."""


@dataclass(frozen=True)
class Response:
    status_code: int
    body: bytes

    def json(self) -> Any:
        return json.loads(self.body.decode("utf-8"))


def _dumps(payload: dict) -> bytes:
    return json.dumps(payload).encode("utf-8")


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Blocks redirect-following — same rationale as `production_smoke.py`:
    a 3xx from `--base-url` must not silently hand the bearer token (or a
    POST body containing the password) to a different host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirectHandler)


class UrllibClient:
    """The same `.get(path, headers=)` / `.post(path, json=, headers=)` /
    `.put(path, json=, headers=)` -> `Response(status_code, .json())` shape
    as `production_smoke.py`'s `UrllibClient` (ADR 0503 D3/D4), plus `.put`
    for the settings/profile writes this chain needs. `run_chain()` works
    unmodified against a real deploy (this class) and against an in-process
    app in tests (`backend/tests/test_live_smoke_contract.py` passes a real
    `TestClient` instance directly)."""

    def __init__(self, base_url: str, *, timeout: float = 10.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

    def get(self, path: str, *, headers: dict | None = None) -> Response:
        return self._request("GET", path, headers=headers)

    def post(
        self, path: str, *, json: dict | None = None, headers: dict | None = None
    ) -> Response:
        return self._request("POST", path, headers=headers, json_body=json)

    def put(
        self, path: str, *, json: dict | None = None, headers: dict | None = None
    ) -> Response:
        return self._request("PUT", path, headers=headers, json_body=json)

    def _request(
        self,
        method: str,
        path: str,
        *,
        headers: dict | None = None,
        json_body: dict | None = None,
    ) -> Response:
        url = f"{self.base_url}{path}"
        request_headers = dict(headers or {})
        data = None
        if json_body is not None:
            data = _dumps(json_body)
            request_headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            url, data=data, headers=request_headers, method=method
        )
        try:
            with _NO_REDIRECT_OPENER.open(request, timeout=self.timeout) as resp:
                return Response(resp.status, resp.read())
        except urllib.error.HTTPError as error:
            return Response(error.code, error.read())
        except (urllib.error.URLError, OSError, TimeoutError) as error:
            raise _HttpError(str(error)) from error


def _traffic_gate_reason(resp: Response) -> str | None:
    """If `resp` is the ADR 0449 D1 traffic-gate 503 shape, return a
    dedicated reason string; otherwise None."""
    if resp.status_code != 503:
        return None
    try:
        body = resp.json()
    except (ValueError, UnicodeDecodeError):
        return None
    if isinstance(body, dict) and body.get("status") == "not_ready":
        return f"traffic gate active (not_ready): {body.get('reason', '<no reason>')}"
    return None


# ---------------------------------------------------------------------------
# Contract-driven classification (ADR 0503 D1)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class ContractEndpoint:
    method: str
    path: str
    status: str  # the CONTRACT's own field: "mounted" | "known_gap"


def load_contract(path: Path) -> list[ContractEndpoint]:
    data = json.loads(path.read_text(encoding="utf-8"))
    endpoints = data.get("endpoints")
    if not isinstance(endpoints, list) or not endpoints:
        raise ValueError(f"{path}: no non-empty 'endpoints' array")
    return [
        ContractEndpoint(
            method=entry["method"], path=entry["path"], status=entry["status"]
        )
        for entry in endpoints
    ]


# The bring-up chain's exercised endpoints, in call order (D2). This is NOT
# a copy of the endpoint catalogue (D1's forbidden weakening) — it is the
# subset `run_chain()` below actually calls; `classify_contract()` fails
# closed on any contract entry that is in neither this set nor
# `_NOT_EXERCISED`.
_EXERCISED_ORDER: tuple[tuple[str, str], ...] = (
    ("POST", "/auth/register"),
    ("POST", "/auth/login"),
    ("GET", "/auth/me"),
    ("GET", "/settings"),
    ("PUT", "/settings"),
    ("POST", "/community/profiles/me"),
    ("GET", "/community/profiles/me"),
    ("PUT", "/community/profiles/me"),
    ("GET", "/community/blocked"),
    ("GET", "/community/muted"),
)

# Every other `mounted` contract entry, with the documented reason it is out
# of scope for a single-account bring-up chain (ADR 0503 D1 "kimondott
# indokkal"). A future round that seeds a second account, or wires the
# tutor/diagnostics subsystems into this chain, moves entries out of here
# and into `_EXERCISED_ORDER`.
_NOT_EXERCISED: dict[tuple[str, str], str] = {
    ("POST", "/diagnostics"): (
        "diagnostics upload posts a distinct on-device telemetry envelope, "
        "gated by its own STRUMSIGHT_DIAG_TOKEN — unrelated to the "
        "account/settings/community bring-up chain this tool proves"
    ),
    ("GET", "/tutor/capability"): (
        "belongs to the AI tutor/model-gateway subsystem, independent of "
        "the account/community chain; exercising it needs a tutor-specific "
        "provider configuration this device profile does not carry"
    ),
    ("POST", "/tutor/stream"): (
        "a server-sent streaming response — the duck-typed request/response "
        "client this tool shares with production_smoke.py has no streaming "
        "support, and the check belongs to the tutor subsystem, not the "
        "account/community chain"
    ),
    ("GET", "/community/profiles/search"): (
        "meaningful only against a second profile's handle; GET "
        "/community/profiles/me already proves this device's authenticated "
        "community read access"
    ),
    ("GET", "/community/profiles/{public_id}/following"): (
        "requires a second account's follow edge for a non-degenerate "
        "result; GET /community/blocked and GET /community/muted already "
        "prove the authenticated list-read shape"
    ),
    ("GET", "/community/profiles/{public_id}/followers"): (
        "requires a second account's follow edge for a non-degenerate "
        "result; GET /community/blocked and GET /community/muted already "
        "prove the authenticated list-read shape"
    ),
    ("POST", "/community/profiles/{public_id}/follow"): (
        "requires a second account to follow — a self-follow is explicitly "
        "rejected by the backend (SelfFollowNotAllowed), so it cannot stand "
        "in for a real exercise"
    ),
    ("DELETE", "/community/profiles/{public_id}/follow"): (
        "requires an existing follow edge from a second account, which "
        "itself requires the follow endpoint above; out of scope for a "
        "single-account bring-up chain"
    ),
    ("DELETE", "/community/profiles/{public_id}/followers/{follower_id}"): (
        "requires a second account's follower edge to remove; the "
        "single-account chain has none"
    ),
    ("POST", "/community/follow-requests/{request_id}/accept"): (
        "requires a pending follow request from a second account, which "
        "itself requires the follow endpoint above"
    ),
    ("POST", "/community/follow-requests/{request_id}/decline"): (
        "requires a pending follow request from a second account, which "
        "itself requires the follow endpoint above"
    ),
    ("POST", "/community/profiles/{public_id}/block"): (
        "a self-block is explicitly rejected (SelfBlockNotAllowed); a real "
        "exercise needs a second account"
    ),
    ("DELETE", "/community/profiles/{public_id}/block"): (
        "requires an existing block from a second account; see the block "
        "endpoint above"
    ),
    ("POST", "/community/profiles/{public_id}/mute"): (
        "a self-mute is rejected the same way a self-block is; needs a "
        "second account"
    ),
    ("DELETE", "/community/profiles/{public_id}/mute"): (
        "requires an existing mute from a second account; see the mute "
        "endpoint above"
    ),
    ("POST", "/community/challenges/{challenge_public_id}/invites"): (
        "needs an existing challenge and a second account to invite; no "
        "challenge-creation endpoint is mounted to seed one from a single "
        "account"
    ),
    ("POST", "/community/challenges/invites/{invite_public_id}/accept"): (
        "requires a pending invite from the endpoint above"
    ),
    ("POST", "/community/challenges/invites/{invite_public_id}/decline"): (
        "requires a pending invite from the endpoint above"
    ),
    ("DELETE", "/community/challenges/invites/{invite_public_id}"): (
        "requires a pending invite from the endpoint above"
    ),
    ("POST", "/community/challenges/{challenge_public_id}/results"): (
        "requires an existing challenge id this single-account chain has no "
        "way to create — no challenge-creation endpoint is mounted"
    ),
    ("GET", "/community/leaderboards/{challenge_public_id}"): (
        "requires an existing challenge id; see the results endpoint above"
    ),
    # Javító sáv 2026-09-06 R5 — the three client call sites wired that
    # round (`docs/ui/apk-functionality-audit-2026-09-06.md` §5).
    ("GET", "/community/bookmarks"): (
        "a fresh account has nothing bookmarked, and no post to bookmark "
        "exists without a second account's content; GET /community/blocked "
        "and GET /community/muted already prove the authenticated list-read "
        "shape"
    ),
    ("GET", "/community/clubs/{public_id}/members"): (
        "requires an existing club id; no club-creation step is part of the "
        "single-account bring-up chain"
    ),
    ("GET", "/community/profiles/{public_id}"): (
        "the by-id read is the followers/following list's row lookup for a "
        "SECOND account's profile; GET /community/profiles/me already proves "
        "this device's authenticated profile read"
    ),
    # Javító sáv 2026-09-06 R11 — the two client call sites wired that round
    # (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.2: club posts and
    # the profilePosts endpoint).
    ("POST", "/community/posts"): (
        "publishing a post writes durable, user-visible content into the "
        "target deploy's community feed; a bring-up probe must not leave "
        "content behind, and this chain has no delete-back step to undo it"
    ),
    ("GET", "/community/profiles/{public_id}/posts"): (
        "meaningful only against a SECOND account's profile (the caller's "
        "own posts are read through the same route with the owner "
        "short-circuit, and a fresh account has none); GET "
        "/community/profiles/me already proves this device's authenticated "
        "community read access"
    ),
    # Javito sav 2026-09-06 R14 — the club feed/pinned call sites measured by
    # R11 (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.2), missing from
    # the contract until this round.
    ("GET", "/community/clubs/{public_id}/pinned"): (
        "requires an existing club id; no club-creation step is part of the "
        "single-account bring-up chain (same reason as GET "
        "/community/clubs/{public_id}/members)"
    ),
    ("GET", "/community/clubs/{public_id}/feed"): (
        "requires an existing club id; no club-creation step is part of the "
        "single-account bring-up chain (same reason as GET "
        "/community/clubs/{public_id}/members)"
    ),
    # Javito sav 2026-09-08 R27 — the community media surface. All three
    # are `mounted` in the contract (the parity test builds the app with
    # every optional flag on), but none can join a bring-up chain:
    ("POST", "/community/media"): (
        "the only multipart request in the tree, and it WRITES durable user "
        "content the chain has no delete-back step for (the POST "
        "/community/posts rule); it is also the one endpoint whose success "
        "depends on infrastructure OUTSIDE the app — with the fail-closed "
        "default STRUMSIGHT_MEDIA_SCANNER=disabled every upload is answered "
        "201 `rejected`, so a chain step here would be red on a healthy "
        "target that simply has not stood up clamd"
    ),
    ("GET", "/community/media/{public_id}"): (
        "requires a media public_id this single-account chain has no way to "
        "create (see POST /community/media), and its success body is bytes "
        "rather than JSON — the duck-typed request/response client this tool "
        "shares with production_smoke.py has no byte-body support"
    ),
    ("DELETE", "/community/media/{public_id}"): (
        "requires a media public_id this single-account chain has no way to "
        "create (see POST /community/media)"
    ),
    # Javito sav 2026-09-07 R16 — the 26 measured client call sites R14
    # reported as still missing from the contract. Re-measured against `lib/**`
    # that round; every one of them is present in the live OpenAPI schema, so
    # each needs a classification here or `classify_contract()` fails closed.
    #
    # Three reason families cover all 26:
    #   (a) the clubs surface is flag-gated (STRUMSIGHT_COMMUNITY_CLUBS_ENABLED)
    #       and may legitimately be unmounted on a target whose account chain is
    #       healthy — a flag-dependent step cannot be allowed to halt the chain
    #       (ADR 0503 D2);
    #   (b) the endpoint needs an id (club, post, comment, notification) this
    #       single-account chain has no way to create;
    #   (c) the endpoint WRITES durable, user-visible content and the chain has
    #       no delete-back step to undo it (the POST /community/posts rule).
    ("GET", "/community/feed"): (
        "the following-feed of a fresh account with no follow edges is "
        "degenerate (an empty page); a non-degenerate result needs a second "
        "account's posts, and GET /community/blocked and GET /community/muted "
        "already prove the authenticated list-read shape"
    ),
    ("GET", "/community/clubs"): (
        "the clubs surface is gated by STRUMSIGHT_COMMUNITY_CLUBS_ENABLED and "
        "may legitimately be unmounted (404) on a deploy whose account and "
        "profile chain is healthy; a flag-dependent step must not halt the "
        "chain (ADR 0503 D2)"
    ),
    ("POST", "/community/clubs"): (
        "creating a club writes durable, user-visible state into the target "
        "deploy's community surface and this chain has no delete-back step to "
        "undo it (same rule as POST /community/posts); the clubs surface is "
        "flag-gated on top of that"
    ),
    ("GET", "/community/clubs/{public_id}"): (
        "requires an existing club id; no club-creation step is part of the "
        "single-account bring-up chain (same reason as GET "
        "/community/clubs/{public_id}/members)"
    ),
    ("PATCH", "/community/clubs/{public_id}"): (
        "requires an existing club id AND mutates another owner's club "
        "metadata; a bring-up probe must not edit content it did not create"
    ),
    ("POST", "/community/clubs/{public_id}/join"): (
        "requires an existing club id, and a join request leaves durable "
        "membership state (or a pending request an owner has to triage) behind "
        "on the target deploy"
    ),
    ("POST", "/community/clubs/{public_id}/leave"): (
        "requires an existing membership, which itself requires the join "
        "endpoint above"
    ),
    ("POST", "/community/clubs/{public_id}/invites"): (
        "requires an existing club the caller may administer AND a second "
        "account to invite; the single-account chain has neither"
    ),
    ("POST", "/community/clubs/{public_id}/owner"): (
        "transfers ownership to a SECOND account — irreversible from the "
        "caller's side and impossible with one account"
    ),
    ("DELETE", "/community/clubs/{public_id}/members/{target_public_id}"): (
        "requires an existing club with a second account as a member to "
        "remove; the single-account chain has none"
    ),
    ("GET", "/community/posts/{public_id}"): (
        "requires an existing post id; the chain publishes none (POST "
        "/community/posts is itself out of scope precisely so the probe leaves "
        "no content behind)"
    ),
    ("PATCH", "/community/posts/{public_id}"): (
        "requires a post the caller authored; see GET "
        "/community/posts/{public_id} — this chain creates none"
    ),
    ("DELETE", "/community/posts/{public_id}"): (
        "requires a post the caller authored; see GET "
        "/community/posts/{public_id} — this chain creates none"
    ),
    ("PUT", "/community/posts/{post_public_id}/reaction"): (
        "requires an existing, visible post id; a fresh single account can see "
        "none, and reacting writes durable state onto another author's content"
    ),
    ("DELETE", "/community/posts/{post_public_id}/reaction"): (
        "requires an existing reaction from the endpoint above"
    ),
    ("GET", "/community/posts/{post_public_id}/comments"): (
        "requires an existing, visible post id; see PUT "
        "/community/posts/{post_public_id}/reaction"
    ),
    ("POST", "/community/posts/{post_public_id}/comments"): (
        "requires an existing, visible post id, and publishing a comment "
        "writes durable, user-visible content this chain has no delete-back "
        "step to undo"
    ),
    ("PATCH", "/community/comments/{public_id}"): (
        "requires a comment the caller authored, which requires the comment "
        "creation endpoint above"
    ),
    ("DELETE", "/community/comments/{public_id}"): (
        "requires a comment the caller authored, which requires the comment "
        "creation endpoint above"
    ),
    ("POST", "/community/bookmarks/{post_public_id}"): (
        "requires an existing, visible post id to bookmark; a fresh "
        "single-account deploy has none reachable"
    ),
    ("DELETE", "/community/bookmarks/{post_public_id}"): (
        "requires an existing bookmark from the endpoint above"
    ),
    ("GET", "/community/notifications"): (
        "a fresh account's inbox is empty — every notification in this "
        "backend is raised by a SECOND account's action (follow, comment, "
        "reaction, invite); GET /community/blocked and GET /community/muted "
        "already prove the authenticated list-read shape"
    ),
    ("POST", "/community/notifications/{public_id}/read"): (
        "requires an existing notification id, which requires a second "
        "account's action to raise"
    ),
    ("POST", "/community/notifications/{public_id}/read-up-to"): (
        "requires an existing notification id, which requires a second "
        "account's action to raise"
    ),
    ("GET", "/community/notifications/preferences"): (
        "the preference map of a freshly created profile carries defaults "
        "only, so the read is degenerate; GET /community/profiles/me already "
        "proves this device's authenticated community read access"
    ),
    ("PUT", "/community/notifications/preferences"): (
        "writes durable per-profile delivery preferences, and the wire shape "
        "needs a category/level pair the tool would have to hardcode against a "
        "server-side enum that can drift; PUT /settings already proves the "
        "authenticated write path"
    ),
    # Javito sav 2026-09-08 R36 — R33's content-report call site
    # (`HttpCommunityPostRepository.submitReport`). `mounted`: the reports
    # router is registered into the community aggregate unconditionally.
    ("POST", "/community/reports"): (
        "filing a report writes durable moderation state (a row a human "
        "moderator has to triage) against a post or comment the "
        "single-account bring-up chain never creates, and the chain has no "
        "delete-back step to withdraw it (the POST /community/posts rule); "
        "a target_id the chain could invent answers 404, which would make "
        "the step red on a healthy deploy"
    ),
}


@dataclass(frozen=True)
class EndpointClassification:
    method: str
    path: str
    kind: str  # "exercised" | "not_exercised" | "known_gap" | "unclassified"
    reason: str


def classify_contract(
    entries: list[ContractEndpoint],
) -> list[EndpointClassification]:
    """Classify every contract entry. Fail CLOSED (D1): an entry that is
    neither the chain's own exercised set, the documented not_exercised
    table, nor the contract's own `known_gap` status comes back
    "unclassified" so the caller can fail loudly instead of silently
    under-covering the client's network surface."""
    exercised = set(_EXERCISED_ORDER)
    out: list[EndpointClassification] = []
    for entry in entries:
        key = (entry.method, entry.path)
        if entry.status == "known_gap":
            out.append(
                EndpointClassification(
                    entry.method,
                    entry.path,
                    "known_gap",
                    "contract declares this a known_gap (ADR 0497 D5) — the "
                    "chain expects 404 and reports its presence as a break",
                )
            )
        elif key in exercised:
            out.append(
                EndpointClassification(
                    entry.method,
                    entry.path,
                    "exercised",
                    "called directly by the bring-up chain",
                )
            )
        elif key in _NOT_EXERCISED:
            out.append(
                EndpointClassification(
                    entry.method, entry.path, "not_exercised", _NOT_EXERCISED[key]
                )
            )
        else:
            out.append(
                EndpointClassification(
                    entry.method,
                    entry.path,
                    "unclassified",
                    "no classification on file for this contract entry — add "
                    "one to _EXERCISED_ORDER or _NOT_EXERCISED in "
                    "tool/release/live_backend_smoke.py",
                )
            )
    return out


# ---------------------------------------------------------------------------
# The bring-up chain (ADR 0503 D2 — stops at the first divergence)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class StepResult:
    name: str
    method: str
    path: str
    ok: bool
    detail: str


def _record(
    steps: list[StepResult],
    *,
    name: str,
    method: str,
    path: str,
    resp: Response,
    expected_status: int,
) -> bool:
    """Append a `StepResult` for `resp` against `expected_status`, honoring
    the ADR 0449 D1 traffic-gate 503 shape. Returns True if the chain may
    continue, False if the caller must halt (D2)."""
    reason = _traffic_gate_reason(resp)
    if reason is not None:
        steps.append(StepResult(name, method, path, False, reason))
        return False
    if resp.status_code != expected_status:
        # Never prints the response body (production_smoke.py's own rule):
        # an authenticated response body can carry account data, and this
        # detail string is meant for a human-readable diagnosis, not a data
        # dump. Status codes and paths are never secret.
        steps.append(
            StepResult(
                name,
                method,
                path,
                False,
                f"expected {method} {path} -> {expected_status}, got "
                f"{resp.status_code}",
            )
        )
        return False
    steps.append(
        StepResult(name, method, path, True, f"{resp.status_code} as expected")
    )
    return True


def _record_expected_absent(
    steps: list[StepResult], *, name: str, method: str, path: str, resp: Response
) -> bool:
    """The known_gap counterpart to `_record`: a `404` is the PASS outcome —
    anything else means the contract is stale (a future round implemented
    the route without flipping its `status` to `mounted`)."""
    if resp.status_code == 404:
        steps.append(
            StepResult(name, method, path, True, "404 as expected (known_gap)")
        )
        return True
    steps.append(
        StepResult(
            name,
            method,
            path,
            False,
            f"expected {method} {path} -> 404 (known_gap), got "
            f"{resp.status_code} — the contract may be stale: a route that "
            "now exists must flip this entry to 'mounted' and get a real "
            "classification",
        )
    )
    return False


def run_chain(client, *, email: str, password: str) -> list[StepResult]:
    """Runs the bring-up chain against `client` (a real `UrllibClient` or,
    in tests, an in-process `TestClient`). Stops at the FIRST failing step
    (D2) — every later step is simply never called, so a caller inspecting
    call counts on a spy client can prove the halt."""
    steps: list[StepResult] = []

    try:
        resp = client.get("/health/ready")
    except _HttpError as error:
        steps.append(
            StepResult("readiness", "GET", "/health/ready", False, f"request failed: {error}")
        )
        return steps
    if not _record(
        steps,
        name="readiness",
        method="GET",
        path="/health/ready",
        resp=resp,
        expected_status=200,
    ):
        return steps
    ready_body = resp.json()
    if ready_body.get("status") != "ready":
        steps[-1] = StepResult(
            "readiness",
            "GET",
            "/health/ready",
            False,
            f"HTTP 200 but unexpected body: {ready_body!r}",
        )
        return steps

    try:
        resp = client.post(
            "/auth/register", json={"email": email, "password": password}
        )
    except _HttpError as error:
        steps.append(
            StepResult(
                "register", "POST", "/auth/register", False, f"request failed: {error}"
            )
        )
        return steps
    if not _record(
        steps,
        name="register",
        method="POST",
        path="/auth/register",
        resp=resp,
        expected_status=201,
    ):
        return steps

    try:
        resp = client.post("/auth/login", json={"email": email, "password": password})
    except _HttpError as error:
        steps.append(
            StepResult("login", "POST", "/auth/login", False, f"request failed: {error}")
        )
        return steps
    if not _record(
        steps, name="login", method="POST", path="/auth/login", resp=resp, expected_status=200
    ):
        return steps
    try:
        login_body = resp.json()
    except (ValueError, UnicodeDecodeError):
        steps[-1] = StepResult(
            "login", "POST", "/auth/login", False, "HTTP 200 but body is not valid JSON"
        )
        return steps
    token = login_body.get("access_token") if isinstance(login_body, dict) else None
    if not token:
        steps[-1] = StepResult(
            "login", "POST", "/auth/login", False, "HTTP 200 but no access_token in body"
        )
        return steps
    auth_headers = {"Authorization": f"Bearer {token}"}

    try:
        resp = client.get("/auth/me", headers=auth_headers)
    except _HttpError as error:
        steps.append(
            StepResult("auth_me", "GET", "/auth/me", False, f"request failed: {error}")
        )
        return steps
    if not _record(
        steps, name="auth_me", method="GET", path="/auth/me", resp=resp, expected_status=200
    ):
        return steps

    try:
        resp = client.get("/settings", headers=auth_headers)
    except _HttpError as error:
        steps.append(
            StepResult("settings_read", "GET", "/settings", False, f"request failed: {error}")
        )
        return steps
    if not _record(
        steps,
        name="settings_read",
        method="GET",
        path="/settings",
        resp=resp,
        expected_status=200,
    ):
        return steps

    try:
        resp = client.put(
            "/settings", json={"theme_mode": "dark"}, headers=auth_headers
        )
    except _HttpError as error:
        steps.append(
            StepResult("settings_write", "PUT", "/settings", False, f"request failed: {error}")
        )
        return steps
    if not _record(
        steps,
        name="settings_write",
        method="PUT",
        path="/settings",
        resp=resp,
        expected_status=200,
    ):
        return steps

    handle = f"livesmoke{uuid.uuid4().hex[:12]}"
    try:
        resp = client.post(
            "/community/profiles/me",
            json={
                "handle": handle,
                "display_name": "Live Smoke",
                "visibility": "public",
                "audience_default": "public",
            },
            headers=auth_headers,
        )
    except _HttpError as error:
        steps.append(
            StepResult(
                "community_profile_create",
                "POST",
                "/community/profiles/me",
                False,
                f"request failed: {error}",
            )
        )
        return steps
    if not _record(
        steps,
        name="community_profile_create",
        method="POST",
        path="/community/profiles/me",
        resp=resp,
        expected_status=201,
    ):
        return steps

    try:
        resp = client.get("/community/profiles/me", headers=auth_headers)
    except _HttpError as error:
        steps.append(
            StepResult(
                "community_profile_read",
                "GET",
                "/community/profiles/me",
                False,
                f"request failed: {error}",
            )
        )
        return steps
    if not _record(
        steps,
        name="community_profile_read",
        method="GET",
        path="/community/profiles/me",
        resp=resp,
        expected_status=200,
    ):
        return steps

    try:
        resp = client.put(
            "/community/profiles/me",
            json={"display_name": "Live Smoke Updated"},
            headers=auth_headers,
        )
    except _HttpError as error:
        steps.append(
            StepResult(
                "community_profile_update",
                "PUT",
                "/community/profiles/me",
                False,
                f"request failed: {error}",
            )
        )
        return steps
    if not _record(
        steps,
        name="community_profile_update",
        method="PUT",
        path="/community/profiles/me",
        resp=resp,
        expected_status=200,
    ):
        return steps

    try:
        resp = client.get("/community/blocked", headers=auth_headers)
    except _HttpError as error:
        steps.append(
            StepResult(
                "community_blocked", "GET", "/community/blocked", False, f"request failed: {error}"
            )
        )
        return steps
    if not _record(
        steps,
        name="community_blocked",
        method="GET",
        path="/community/blocked",
        resp=resp,
        expected_status=200,
    ):
        return steps

    try:
        resp = client.get("/community/muted", headers=auth_headers)
    except _HttpError as error:
        steps.append(
            StepResult(
                "community_muted", "GET", "/community/muted", False, f"request failed: {error}"
            )
        )
        return steps
    if not _record(
        steps,
        name="community_muted",
        method="GET",
        path="/community/muted",
        resp=resp,
        expected_status=200,
    ):
        return steps

    # known_gap probes (ADR 0503 D1 "Következmények") — the SAME chain, same
    # halt-on-divergence discipline, proving the three challenges-listing
    # paths are still absent on this deploy.
    known_gap_paths = (
        ("known_gap_challenges", "GET", "/community/challenges"),
        (
            "known_gap_challenge_detail",
            "GET",
            f"/community/challenges/{_KNOWN_GAP_PLACEHOLDER_ID}",
        ),
        (
            "known_gap_challenge_me",
            "GET",
            f"/community/challenges/{_KNOWN_GAP_PLACEHOLDER_ID}/me",
        ),
    )
    for name, method, path in known_gap_paths:
        try:
            resp = client.get(path, headers=auth_headers)
        except _HttpError as error:
            steps.append(StepResult(name, method, path, False, f"request failed: {error}"))
            return steps
        if not _record_expected_absent(steps, name=name, method=method, path=path, resp=resp):
            return steps

    return steps


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--base-url", required=True, help="e.g. http://192.168.1.42:8000"
    )
    parser.add_argument(
        "--contract",
        type=Path,
        default=_DEFAULT_CONTRACT_PATH,
        help=(
            "Path to docs/contracts/client-backend-endpoints.json (default: "
            "the repo copy next to this tool)."
        ),
    )
    parser.add_argument("--timeout", type=float, default=10.0, help="HTTP timeout in seconds.")
    return parser


def _scheme_error(base_url: str) -> str | None:
    """Unlike `production_smoke.py`, plain `http://` is an accepted target
    here (ADR 0503 D3 — a LAN/tunnel dev-lab instance, not a production
    endpoint reachable only over `https://`). Only a missing/other scheme is
    rejected."""
    scheme = urlsplit(base_url).scheme
    if scheme in ("http", "https"):
        return None
    return (
        f"live_backend_smoke: --base-url {base_url!r} must use http:// or "
        f"https:// (got scheme {scheme or '<none>'!r})"
    )


def main(argv: list[str]) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    scheme_error = _scheme_error(args.base_url)
    if scheme_error is not None:
        print(scheme_error, file=sys.stderr)
        return 2

    try:
        entries = load_contract(args.contract)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"live_backend_smoke: could not read --contract: {error}", file=sys.stderr)
        return 2

    classifications = classify_contract(entries)
    unclassified = [c for c in classifications if c.kind == "unclassified"]
    for classification in classifications:
        print(
            f"[{classification.kind}] {classification.method} {classification.path}: "
            f"{classification.reason}"
        )
    if unclassified:
        print(
            f"live_backend_smoke: {len(unclassified)} contract entr"
            f"{'y' if len(unclassified) == 1 else 'ies'} unclassified — the "
            "smoke tool is out of date with the contract (see above)",
            file=sys.stderr,
        )
        return 2

    email = f"live-smoke-{uuid.uuid4().hex[:12]}@strumsight.app"
    password = f"live-smoke-{uuid.uuid4().hex}"
    client = UrllibClient(args.base_url, timeout=args.timeout)
    steps = run_chain(client, email=email, password=password)

    for step in steps:
        status = "PASS" if step.ok else "FAIL"
        print(f"[{status}] {step.name} ({step.method} {step.path}): {step.detail}")

    if not steps or not steps[-1].ok:
        halted_at = steps[-1].name if steps else "readiness"
        print(
            f"live_backend_smoke: chain halted at {halted_at!r} — later steps "
            "did not run (ADR 0503 D2)",
            file=sys.stderr,
        )
        return 1

    print(
        f"live_backend_smoke: ok — {len(steps)} chain step(s) passed against "
        f"{args.base_url}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
