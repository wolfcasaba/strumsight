"""Signed playback-URL service (E09-R19, ADR 0412).

Application-level HMAC-SHA256 signed tokens for media playback
URLs. The token shape is independent of the bucket — the
Kör 18 ``ObjectStore`` ABC has only PUT-signing (no GET /
download-signing), and adding GET-signing is a future round's
job (ADR 0412 §D6, HANDOFF §6 nyitott horog).

**What this service does today:**

* Issues a short-lived (default 5 minutes, capped at 30
  minutes) HMAC-SHA256 signed token tied to a media row's
  ``public_id``.
* Verifies the token integrity + expiry.
* Re-uses the project-wide :class:`CommunityAccessPolicy`
  (read-only import from
  :mod:`community.policies.access_policy`) for audience
  authorization — a blocked viewer never gets a token, an
  unfollowed viewer never gets a token for ``FOLLOWERS``
  audience media (ADR 0412 §D7).
* Combines audience + integrity + state checks into a single
  ``issue_playback_token`` /
  ``verify_playback_token`` pair that downstream routers /
  the Flutter player will call.

**What this service does NOT do today:**

* It does NOT hit the bucket. The signed token is a
  *gate* the future HTTP route will check before signing a
  real GET URL via the (future) bucket-GET-signing adapter.
* It does NOT auto-transition ``processing_state='ready'``
  onto ``ready``-machines; that is the human-review gate's
  job (:mod:`community.moderation.media_moderation`).
* It does NOT replace the existing ``ObjectStore`` for the
  upload path — the upload pipeline keeps using the Kör 18
  presigned PUT URLs.

The HMAC-SHA256 family matches the project-wide cursor
signing in :mod:`community.feed.following_feed` /
:mod:`community.repositories.profile_search_repository`
(ADR 0410 D4).
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Final

from sqlalchemy.orm import Session

from ..models.media import (
    PROCESSING_STATE_READY,
    CommunityMedia,
)
from ..policies.access_policy import (
    CommunityAccessPolicy,
    CommunityAudience,
    RelationshipContext,
)
from ..tasks.media_processing import (
    make_signed_playback_token,
    parse_signed_playback_token,
)

# ---------------------------------------------------------------------------
# Token TTLs.
# ---------------------------------------------------------------------------

#: Default playback-URL TTL. 5 minutes — enough for a single
#: mobile playback session, short enough that a leaked token
#: cannot outlive the viewer's tab. A future round tunes this
#: per the product's measured session length.
DEFAULT_PLAYBACK_TTL: Final[timedelta] = timedelta(minutes=5)

#: Absolute cap the service enforces. A caller-supplied
#: ``ttl`` longer than this is clamped down — defense-in-depth
#: against a future config bug that asks for a 24-hour token.
MAX_PLAYBACK_TTL: Final[timedelta] = timedelta(minutes=30)


# ---------------------------------------------------------------------------
# Errors.
# ---------------------------------------------------------------------------


class MediaPlaybackError(Exception):
    """Base class for the playback-URL service."""


class MediaNotPlayable(MediaPlaybackError):
    """The row's ``processing_state`` is not ``ready``."""


class MediaAudienceDenied(MediaPlaybackError):
    """The viewer is not authorized to see this media (A4)."""


class MediaTokenInvalid(MediaPlaybackError):
    """The token's HMAC verification failed (A5 / forgery)."""


class MediaTokenExpired(MediaPlaybackError):
    """The token's TTL has elapsed (A5 / clock)."""


# ---------------------------------------------------------------------------
# Public dataclasses.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class PlaybackToken:
    """The issued playback token + the expiry the client must respect."""

    token: str
    media_public_id: uuid.UUID
    expires_at: datetime


# ---------------------------------------------------------------------------
# Audience-aware policy plumbing.
# ---------------------------------------------------------------------------


def _resolve_audience(row: CommunityMedia) -> CommunityAudience:
    """Map the row's ``audience`` literal to the policy enum.

    The ``CommunityMedia`` model does not carry an ``audience``
    column in this round (the post does, in
    :class:`CommunityPost.audience`); the playback URL service
    uses a community-default audience of ``PUBLIC`` until the
    future post-attachment round wires a real mapping. The
    function is the seam a future round updates when the
    post-media attachment lands.
    """
    # Kör 19 scope: every media is community-default-PUBLIC
    # until the post-attachment round gives it a per-post
    # audience. The default keeps the audience-policy
    # evaluation order intact while the future column is
    # absent.
    return CommunityAudience.PUBLIC


# ---------------------------------------------------------------------------
# Token issuance / verification.
# ---------------------------------------------------------------------------


def issue_playback_token(
    db: Session,
    row: CommunityMedia,
    *,
    viewer_relationship: RelationshipContext,
    secret: str,
    now: datetime | None = None,
    ttl: timedelta | None = None,
    access_policy: CommunityAccessPolicy | None = None,
) -> PlaybackToken:
    """Issue an audience-checked, signed playback token for ``row``.

    Raises:

    * :class:`MediaNotPlayable` — the row is not in
      ``processing_state='ready'`` (A2/A3 invariant — the
      player never plays non-ready media).
    * :class:`MediaAudienceDenied` — the audience policy
      rejects the viewer (A4 — blocked / non-follower
      against FOLLOWERS audience).

    On success, returns a :class:`PlaybackToken` the caller
    forwards to the player; the player renders a ``<video>``
    or ``<audio>`` element with the token as the URL's
    ``token=`` query param. The token is a single
    application-level gate the future HTTP route cross-checks
    before signing the real GET URL.
    """
    when = now or datetime.now(timezone.utc)
    if row.processing_state != PROCESSING_STATE_READY:
        raise MediaNotPlayable(row.processing_state)
    audience = _resolve_audience(row)
    policy = access_policy or CommunityAccessPolicy()
    if not policy.evaluate_content_access(audience, viewer_relationship):
        raise MediaAudienceDenied(
            f"audience={audience.value} viewer-blocked-or-non-follower"
        )
    effective_ttl = ttl or DEFAULT_PLAYBACK_TTL
    if effective_ttl > MAX_PLAYBACK_TTL:
        effective_ttl = MAX_PLAYBACK_TTL
    expires_at = when + effective_ttl
    token = make_signed_playback_token(
        media_public_id=row.public_id,
        expires_at=expires_at,
        secret=secret,
    )
    return PlaybackToken(
        token=token,
        media_public_id=row.public_id,
        expires_at=expires_at,
    )


def verify_playback_token(
    *,
    token: str,
    row: CommunityMedia,
    secret: str,
    viewer_relationship: RelationshipContext,
    now: datetime | None = None,
    access_policy: CommunityAccessPolicy | None = None,
) -> datetime:
    """Verify a token and return its expiry.

    Raises:

    * :class:`MediaNotPlayable` — the row is not ``ready``.
    * :class:`MediaAudienceDenied` — the viewer is not
      authorized (A4 — re-runs the policy at verify time, so
      a viewer that was unblocked-then-blocked between issue
      and verify is correctly rejected).
    * :class:`MediaTokenInvalid` — the HMAC does not verify
      (A5 / forgery).
    * :class:`MediaTokenExpired` — the token's TTL elapsed.

    The verify side re-runs the audience check on purpose —
    the audience state may have changed between issue and
    verify, and the A4 cell is about *every* gate, not just
    the issue-time check.
    """
    when = now or datetime.now(timezone.utc)
    if row.processing_state != PROCESSING_STATE_READY:
        raise MediaNotPlayable(row.processing_state)
    audience = _resolve_audience(row)
    policy = access_policy or CommunityAccessPolicy()
    if not policy.evaluate_content_access(audience, viewer_relationship):
        raise MediaAudienceDenied(
            f"audience={audience.value} viewer-blocked-or-non-follower"
        )
    expires_at = parse_signed_playback_token(
        token=token,
        expected_media_public_id=row.public_id,
        secret=secret,
        now=when,
        audience_passed=True,
    )
    if expires_at is None:
        # The parse helper returns ``None`` for BOTH the
        # signature-mismatch and the clock-expired branches
        # (it cannot tell them apart without a separate
        # ``expires_at`` re-read). The verify function
        # re-decides via the well-known test below: parse
        # the timestamp out of the token and compare to now.
        _raise_for_token_failure(token, row, secret, when)
        # ``_raise_for_token_failure`` always raises — the
        # unreachable return below makes the type-checker
        # happy.
        raise MediaTokenInvalid(token)  # pragma: no cover
    return expires_at


def _raise_for_token_failure(
    token: str,
    row: CommunityMedia,
    secret: str,
    now: datetime,
) -> None:
    """Inspect the token, decide between INVALID and EXPIRED, raise.

    Used by :func:`verify_playback_token` when
    :func:`parse_signed_playback_token` returned ``None`` —
    the parse helper collapses the two failure modes; this
    helper re-opens the gap so the caller's exception
    matches the actual cause.

    The payload uses the integer Unix timestamp (NOT
    ``isoformat()``) so the bytes match what was signed —
    ``isoformat()`` carries microsecond noise that breaks the
    HMAC verification.
    """
    if "." not in token:
        raise MediaTokenInvalid(token)
    expires_raw, signature_b64 = token.rsplit(".", 1)
    try:
        expires_at_unix = int(expires_raw)
        expires_at = datetime.fromtimestamp(expires_at_unix, tz=timezone.utc)
    except (ValueError, TypeError, OverflowError):
        raise MediaTokenInvalid(token)
    payload = f"{row.public_id}|{expires_at_unix}".encode("utf-8")
    expected = hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).digest()
    try:
        signature = base64.urlsafe_b64decode(signature_b64.encode("ascii"))
    except (ValueError, TypeError):
        raise MediaTokenInvalid(token)
    if not hmac.compare_digest(signature, expected):
        raise MediaTokenInvalid(token)
    if expires_at <= now:
        raise MediaTokenExpired(token)
    # Unknown failure — be conservative.
    raise MediaTokenInvalid(token)  # pragma: no cover


__all__ = [
    "DEFAULT_PLAYBACK_TTL",
    "MAX_PLAYBACK_TTL",
    "MediaAudienceDenied",
    "MediaNotPlayable",
    "MediaPlaybackError",
    "MediaTokenExpired",
    "MediaTokenInvalid",
    "PlaybackToken",
    "issue_playback_token",
    "verify_playback_token",
]
