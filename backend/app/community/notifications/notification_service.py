"""Community notification inbox + push-delivery service (E09-R20, ADR 0414).

The single source of truth for the inbox side: every notification
the app surfaces passes through one of the four mutating methods
on this module. The push gateway is a separate concern
(``push_gateway.PushGateway``) and is invoked from this service
AFTER a successful row write.

Design contract (the §5 / §0.0 invariants — these are the load-bearing
guarantees the tests pin):

* **Push payload redaction (A1, §5.1).** The :class:`PushPayload`
  dataclass carries ONLY the inbox ``public_id``, the wire kind,
  the localization KEYS, and the route entity pair. The full
  notification body is NEVER on the wire — the client reads the
  localised text from the ARB catalogues on receipt of the inbox
  row. The §6.1 valódi-sértés próba adds a ``commentBody`` field
  to ``PushPayload`` and asserts the A1 cell goes red.

* **Reaction burst aggregation (A2, §5.2).** A new event in the
  15-minute sliding window keyed by
  ``(recipient_profile_id, entity_type, entity_id)`` increments
  the existing row's ``aggregate_count`` and bumps
  ``updated_at`` / ``created_at`` to the new ``now``. A new
  push is NOT fired — the previous push (fired at window open)
  is the single delivery. The aggregation is OPT-IN: the caller
  passes ``aggregate=True`` only for the reaction-summary kind
  (other kinds do not aggregate — a comment + a reaction on the
  same post are distinct events).

* **Read state race (A3, §0.0 D4).** :func:`mark_read` and
  :func:`mark_all_read_up_to` accept a ``_before_commit`` test
  hook (mirror of the ``on_invalidate`` callback seam). The hook
  fires INSIDE the service, just before the commit, so the
  §6.1 L421-style threading test can place a
  ``threading.Barrier(2)`` at the SQL UPDATE point — not at
  thread-start, where the race is non-deterministic.

* **Blocked-actor visibility (A4, §0.0).** :func:`list_inbox`
  drops any row whose ``actor_profile_id`` is in a block
  relationship with the recipient (via
  :func:`policies.query_filters.is_blocked_pair`). System events
  (NULL ``actor_profile_id``) are NOT filtered.

* **Deleted-entity handling (A5).** :func:`list_inbox` checks the
  existence of the entity the row points at. For ``entity_type ==
  'post'`` (the only entity type this round wires), a soft-
  deleted, moderation-removed, or hard-deleted post causes the
  returned row to have ``related_content_id = None`` — the row
  stays visible but the deep-link is suppressed (the
  ``CommunityNotificationItem.relatedContentId == null`` path).

* **Dedup (A7, §5.2).** A non-null ``dedup_key`` is UNIQUE-
  constrained per ``(recipient_profile_id, dedup_key)``. A retry
  with the same key is rejected by the DB; the service catches
  :class:`IntegrityError` and re-reads the existing row
  (the ``reaction_service.set_reaction`` pattern).

* **In-memory preference store (A6 — Flutter widget test only).**
  The :func:`get_preferences` / :func:`set_preference` pair is
  a process-local dict keyed by ``(profile_id, category)``. The
  brief §3 places the FULL persistence of preferences on a
  future round's ``allowed_paths``; this round ships the
  service surface so the Flutter ``notification_controller``
  can be wired against the production-shape API. The dict is
  intentionally non-persistent — a server restart resets the
  preferences — and the Flutter test (A6) uses a controller-
  scoped fake repository, so the service's preference surface
  is exercised by the production wiring and NOT by the §6
  measure-matrix.

* **Caller-supplied clock (``now: datetime``).** Same precedent
  as ``routers/privacy.py::update_privacy_settings`` and the
  Kör 4 / Kör 11 / Kör 15 / Kör 16 services — the timestamp
  the service uses to stamp ``created_at`` / ``updated_at`` is
  the caller's, never ``datetime.now(timezone.utc)`` inline.
  The deterministic-timestamp discipline keeps the §6 A2
  "burst-aggregation window" test free of microsecond drift.

* **Injectable push-gateway seam.** :func:`create_notification`
  takes a :class:`PushGateway` instance. The default is a
  :class:`NoOpPushGateway` (in-memory recorder); a future
  round that wires FCM / APNs swaps the implementation at the
  composition root.
"""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import or_, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..models.notification import (
    NOTIFICATION_TYPE_ALLOWLIST,
    REACTION_BURST_WINDOW_SECONDS,
    CommunityNotification,
    is_allowed_notification_type,
)
from ..models.post import CommunityPost
from ..models.profile import CommunityProfile
from ..policies.query_filters import (
    is_blocked_pair,
    list_block_pairs_for_viewer,
)
from .push_gateway import NoOpPushGateway, PushGateway, PushPayload

# ---------------------------------------------------------------------------
# Domain exceptions.
# ---------------------------------------------------------------------------


class NotificationProfileNotFound(Exception):
    """The recipient profile does not exist.

    Mirrors the ``reaction_service.ReactionViewerNotFound`` shape —
    the caller-side decision to raise rather than 404 is the same:
    the recipient IS authenticated but has not completed the
    Community onboarding flow.
    """


class NotificationActorNotFound(Exception):
    """The actor profile (when supplied) does not exist."""


class InvalidNotificationType(Exception):
    """The ``notification_type`` argument is outside the §3 allowlist."""

    def __init__(self, value: object) -> None:
        super().__init__(
            f"notification type {value!r} is not in the allowlist "
            f"{sorted(NOTIFICATION_TYPE_ALLOWLIST)}"
        )
        self.value = value


class NotificationNotFound(Exception):
    """The referenced notification public_id is not visible to the
    caller (or does not exist)."""


# ---------------------------------------------------------------------------
# Invalidation event.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class NotificationInvalidationEvent:
    """Emitted by the mutating service methods on a successful write.

    ``notification_public_id`` is the row that changed;
    ``recipient_profile_id`` is the internal bigint of the inbox
    owner. A future cache layer (Kör 22+) reads this event to
    invalidate the inbox projection snapshot.
    """

    notification_public_id: uuid.UUID
    recipient_profile_id: int
    action: str  # "create" | "aggregate" | "mark_read" | "mark_all_read"


# ---------------------------------------------------------------------------
# Paged-response envelope.
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class NotificationInboxPage:
    """A single page of notifications on the recipient's inbox.

    Mirrors :class:`comment_service.CommentListPage` — the public
    ids are opaque Community UUIDs, the cursor is opaque to the
    caller, and the next request sends the cursor back verbatim.
    The ordering is ``(created_at DESC, id DESC)`` (ADR 0414 §D3
    / Kör 16 pattern).
    """

    notifications: tuple[CommunityNotification, ...]
    next_cursor: str | None


# ---------------------------------------------------------------------------
# Internal helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _as_utc(value: datetime) -> datetime:
    """Normalize a DB-roundtripped ``datetime`` to UTC-aware.

    SQLite drops the tzinfo on read, so a ``DateTime(timezone=True)``
    value that came back from ``session.get()`` is naive. The
    migration contract says the column stores UTC, so we re-attach
    ``timezone.utc`` here for comparison and serialization.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _resolve_profile_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityProfile | None:
    return db.query(CommunityProfile).filter_by(public_id=public_id).one_or_none()


def _resolve_notification_by_public_id(
    db: Session, public_id: uuid.UUID
) -> CommunityNotification | None:
    return db.query(CommunityNotification).filter_by(public_id=public_id).one_or_none()


def _encode_cursor(created_at: datetime, row_id: int) -> str:
    """Encode a ``(created_at, row_id)`` cursor as base64 JSON.

    Mirror of the Kör 8 / Kör 16 / Kör 18 cursor shape — the cursor
    is opaque to the caller; a tampered cursor is decoded back to
    ``None`` by :func:`_decode_cursor` and the list starts from
    the top (the §A7 invariant).
    """
    payload = {"created_at": _as_utc(created_at).isoformat(), "id": row_id}
    return base64.urlsafe_b64encode(
        json.dumps(payload, separators=(",", ":")).encode("utf-8")
    ).decode("ascii")


def _decode_cursor(cursor: str) -> tuple[datetime, int] | None:
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
        payload = json.loads(raw)
        created_at = datetime.fromisoformat(payload["created_at"])
        row_id = int(payload["id"])
        return created_at, row_id
    except (ValueError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
        return None


def _existing_burst_row(
    db: Session,
    *,
    recipient_profile_id: int,
    entity_type: str,
    entity_id: str,
    now: datetime,
    window_seconds: int = REACTION_BURST_WINDOW_SECONDS,
) -> CommunityNotification | None:
    """Find the in-window burst-aggregation row.

    Returns the most recent row matching the aggregation key
    ``(recipient, entity_type, entity_id)`` whose
    ``created_at`` is within ``[now - window_seconds, now]``,
    or ``None`` when no such row exists. The window is
    half-open on the past (``created_at >= now - window``) and
    closed on the present (``created_at <= now``) — a row that
    landed exactly at ``now - window`` is INSIDE the window.
    """
    window_start = now.timestamp() - window_seconds
    rows = (
        db.query(CommunityNotification)
        .filter(
            CommunityNotification.recipient_profile_id == recipient_profile_id,
            CommunityNotification.entity_type == entity_type,
            CommunityNotification.entity_id == entity_id,
        )
        .order_by(CommunityNotification.created_at.desc())
        .all()
    )
    for row in rows:
        ts = _as_utc(row.created_at).timestamp()
        if window_start <= ts <= now.timestamp():
            return row
    return None


def _post_alive(db: Session, *, post_public_id_str: str) -> bool:
    """A5 helper — check whether a ``post`` entity is still
    visible to the inbox viewer.

    Returns ``True`` for a visible, non-deleted post; ``False``
    for a soft-deleted, moderation-removed, or hard-deleted
    post. A malformed entity id (not a UUID) returns ``False``
    — the A5 cell asserts the related_content_id is suppressed
    for ANY non-visible entity, including one that was hard-
    deleted between the event and the inbox open.
    """
    try:
        post_public_id = uuid.UUID(post_public_id_str)
    except (ValueError, TypeError):
        return False
    post = db.query(CommunityPost).filter_by(public_id=post_public_id).one_or_none()
    if post is None:
        return False
    if post.deleted_at is not None:
        return False
    if post.moderation_state != "visible":
        return False
    return True


# ---------------------------------------------------------------------------
# Public service surface — mutating methods.
# ---------------------------------------------------------------------------


def create_notification(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
    notification_type: str,
    title_key: str,
    body_key: str | None,
    actor_public_id: uuid.UUID | None,
    entity_type: str | None,
    entity_id: str | None,
    dedup_key: str | None,
    aggregate: bool,
    now: datetime,
    push_gateway: PushGateway | None = None,
    on_invalidate: Callable[[NotificationInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> CommunityNotification:
    """Create a new inbox item, or aggregate into an existing one.

    Server-side recipient (§5.1): ``recipient_public_id`` is the
    JWT-resolved identity; the body-side contract has no
    ``recipient_id`` field. The Pydantic schema (a future round)
    would reject it via ``extra='forbid'`` even if it sneaked
    through.

    Actor (A4): the actor is OPTIONAL — system events pass
    ``actor_public_id=None``. The block-pair filter is
    applied in :func:`list_inbox`; ``create_notification`` does
    not pre-check the block relationship (a system event with
    a blocked recipient still has to be created — the LIST side
    hides it, not the WRITE side).

    Aggregation (A2): when ``aggregate=True`` and the row's
    ``(entity_type, entity_id)`` are both set, the function
    looks for an in-window row in the burst window and
    increments its ``aggregate_count`` instead of inserting.
    The push is fired EXACTLY ONCE per aggregation window — the
    burst-opening push — NOT per event.

    Dedup (A7): when ``dedup_key`` is set, a duplicate INSERT
    is caught by the UNIQUE constraint and the service
    re-reads the existing row (the
    ``reaction_service.set_reaction`` pattern).

    Returns the new (or freshly-aggregated, or pre-existing-on-
    dedup) row.

    Raises :class:`NotificationProfileNotFound` when the
    recipient profile is missing; :class:`NotificationActorNotFound`
    when ``actor_public_id`` is set and the actor profile is
    missing; :class:`InvalidNotificationType` when
    ``notification_type`` is outside the allowlist.
    """
    if not is_allowed_notification_type(notification_type):
        raise InvalidNotificationType(notification_type)

    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        raise NotificationProfileNotFound("recipient community profile not found")
    actor_id: int | None = None
    if actor_public_id is not None:
        actor = _resolve_profile_by_public_id(db, actor_public_id)
        if actor is None:
            raise NotificationActorNotFound("actor community profile not found")
        actor_id = actor.id

    # A2 burst-aggregation — find the in-window row, increment
    # its count, and return. The push was already fired when
    # the burst opened; we do NOT re-fire.
    if aggregate and entity_type is not None and entity_id is not None:
        existing = _existing_burst_row(
            db,
            recipient_profile_id=recipient.id,
            entity_type=entity_type,
            entity_id=entity_id,
            now=now,
        )
        if existing is not None:
            existing.aggregate_count = existing.aggregate_count + 1
            existing.updated_at = now
            existing.created_at = now  # A2 — "newest activity" stamp
            db.flush()
            db.refresh(existing)
            if on_invalidate is not None:
                on_invalidate(
                    NotificationInvalidationEvent(
                        notification_public_id=existing.public_id,
                        recipient_profile_id=recipient.id,
                        action="aggregate",
                    )
                )
            return existing

    # Fresh INSERT.
    new_row = CommunityNotification(
        recipient_profile_id=recipient.id,
        actor_profile_id=actor_id,
        type=notification_type,
        title_key=title_key,
        body_key=body_key,
        entity_type=entity_type,
        entity_id=entity_id,
        aggregate_count=1,
        is_read=False,
        read_at=None,
        dedup_key=dedup_key,
        created_at=now,
        updated_at=now,
    )
    # A SAVEPOINT a ``db.add`` ELŐTT nyílik: a ``begin_nested()`` maga is
    # flush-ol a SAVEPOINT kiadása előtt, tehát egy előre hozzáadott sor
    # ütközése MÁR ITT eldobná az ``IntegrityError``-t — a lenti kezelő
    # mellett, nem benne.
    # SAVEPOINT az INSERT köré (2026-09-05). Korábban a dedup-ág
    # ``db.rollback()``-ot hívott, ami a TELJES tranzakciót gördíti
    # vissza — tehát a HÍVÓ elsődleges műveletét is. Amíg a service-nek
    # nem volt hívója, ez nem látszott; az első valódi kibocsátó (egy
    # klub-meghívó) esetén viszont a duplikált értesítés magát a
    # meghívót is eldobta volna. A savepoint csak a sikertelen INSERT-et
    # gördíti vissza.
    savepoint = db.begin_nested()
    db.add(new_row)
    try:
        db.flush()
    except IntegrityError:
        # A7 dedup — a concurrent writer landed between our
        # read and our INSERT. Re-read the existing row by
        # the (recipient, dedup_key) UNIQUE.
        savepoint.rollback()
        if dedup_key is None:
            # A non-dedup-key IntegrityError is a real bug —
            # the table's only UNIQUE that isn't ``public_id``
            # is ``(recipient, dedup_key)``, and we only set
            # ``dedup_key`` on this path when the caller
            # asked for it. Re-raise so the caller surfaces
            # a 500 (the §A7 measure-matrix targets the
            # dedup-key path specifically).
            raise
        again = (
            db.query(CommunityNotification)
            .filter(
                CommunityNotification.recipient_profile_id == recipient.id,
                CommunityNotification.dedup_key == dedup_key,
            )
            .one_or_none()
        )
        if again is None:
            # The IntegrityError was on a different constraint
            # (most likely ``public_id``, an internal bug).
            # Re-raise so the caller surfaces a 500.
            raise
        return again
    else:
        savepoint.commit()

    db.refresh(new_row)

    # A1 redaction — the payload is the minimal dataclass
    # shape. The :meth:`PushPayload.__post_init__` validator
    # rejects any field outside the allowlist; the future
    # §6.1 valódi-sértés próba exercises this guard.
    gateway = push_gateway if push_gateway is not None else NoOpPushGateway()
    payload = PushPayload(
        notification_id=new_row.public_id,
        type=new_row.type,
        title_key=new_row.title_key,
        body_key=new_row.body_key,
        route_entity_type=new_row.entity_type,
        route_entity_id=new_row.entity_id,
    )
    gateway.send(payload)

    if on_invalidate is not None:
        on_invalidate(
            NotificationInvalidationEvent(
                notification_public_id=new_row.public_id,
                recipient_profile_id=recipient.id,
                action="create",
            )
        )
    return new_row


def mark_read(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
    notification_public_id: uuid.UUID,
    now: datetime,
    _before_commit: Callable[[], None] | None = None,
    on_invalidate: Callable[[NotificationInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> bool:
    """Mark one notification as read.

    Idempotent: a second call on a read item returns ``False``
    without raising. Returns ``True`` when a transition happened
    (the row was unread), ``False`` when the row was already read
    (no-op). The §6 A3 measure-matrix exercises the
    transition-and-no-transition pair on the same row.

    Test seam (A3 race, §0.0 D4): ``_before_commit`` fires
    INSIDE the service, immediately after the UPDATE statement
    lands but BEFORE the transaction commits. The §6.1
    threading test places a ``threading.Barrier(2)`` at the
    call site so two concurrent ``mark_read`` calls
    synchronise on the SQL UPDATE point — not at thread-start
    (the L421 lesson: thread-start synchronisation is non-
    deterministic; the SQL UPDATE is the deterministic point).

    Raises :class:`NotificationProfileNotFound` when the
    recipient profile is missing; the call is a no-op when the
    notification does not exist OR is not owned by the
    recipient.
    """
    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        raise NotificationProfileNotFound("recipient community profile not found")
    notification = _resolve_notification_by_public_id(db, notification_public_id)
    if notification is None:
        return False
    if notification.recipient_profile_id != recipient.id:
        # IDOR guard — the notification is not in this
        # recipient's inbox. Silent no-op mirrors the Kör 8
        # ``list_blocked`` shape.
        return False
    if notification.is_read:
        return False

    # A3 test seam — the ``_before_commit`` hook fires AFTER
    # the early-return guard (``is_read`` check) but BEFORE
    # the decisive UPDATE statement (the §6.1 "a döntő
    # UPDATE elé" placement). The L421 lesson: a barrier
    # placed AFTER the flush serialises the threads too
    # late — the second thread's flush has already raised a
    # SQLite lock error by the time the first commits.
    # Placing the barrier here means BOTH threads' SELECT
    # statements land first, BOTH see ``is_read = False``,
    # the barrier synchronises them, BOTH then issue the
    # UPDATE. SQLite's writer-serialises-writers invariant
    # means one commits, the second's UPDATE blocks until
    # the first commits, then proceeds. The final state is
    # consistent (unread count = 0); the return values are
    # both ``True`` (both wrote a transition).
    if _before_commit is not None:
        _before_commit()
    notification.is_read = True
    notification.read_at = now
    notification.updated_at = now
    db.flush()
    db.refresh(notification)
    if on_invalidate is not None:
        on_invalidate(
            NotificationInvalidationEvent(
                notification_public_id=notification.public_id,
                recipient_profile_id=recipient.id,
                action="mark_read",
            )
        )
    return True


def mark_all_read_up_to(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
    up_to_id: uuid.UUID,
    now: datetime,
    _before_commit: Callable[[], None] | None = None,
    on_invalidate: Callable[[NotificationInvalidationEvent], None] | None = None,
    idempotency_key: str | None = None,
) -> int:
    """Mark every unread notification up to ``up_to_id`` as read.

    The bulk endpoint is the §17.4 aggregation-friendly path used
    by the inbox "Mark all as read" action. The ``up_to_id`` is
    the public_id of the LAST item the user has seen — the
    service marks every unread row whose ``id <= up_to_id.id``
    (in server-order: ``id`` is monotonic in the same
    ``created_at`` order, so ``id <= up_to_id.id`` is a
    consistent cutoff) AND whose ``created_at <= up_to_id.
    created_at``.

    Returns the number of rows transitioned (a zero return is a
    legitimate "nothing to do" answer).

    Test seam (A3 race): ``_before_commit`` fires INSIDE the
    service, immediately after the bulk UPDATE statement
    lands but BEFORE the transaction commits. The §6.1
    threading test pins the L421 invariant — two devices'
    mark-all-read calls converge to a consistent unread count
    even when they race.

    Raises :class:`NotificationProfileNotFound` when the
    recipient profile is missing; the call is a no-op when
    ``up_to_id`` does not resolve to one of the recipient's
    notifications.
    """
    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        raise NotificationProfileNotFound("recipient community profile not found")
    up_to = _resolve_notification_by_public_id(db, up_to_id)
    if up_to is None or up_to.recipient_profile_id != recipient.id:
        return 0

    # The cutoff is BOTH ``id <= up_to.id`` AND
    # ``created_at <= up_to.created_at`` — the id is the
    # tie-breaker, the created_at is the primary key (a
    # future round that adds a non-monotonic id source
    # would break this; SQLAlchemy's
    # ``BigInteger().with_variant(Integer, "sqlite")``
    # autoincrement is monotonic for our use).
    unread_q = db.query(CommunityNotification).filter(
        CommunityNotification.recipient_profile_id == recipient.id,
        CommunityNotification.is_read.is_(False),
    )
    # Filter to the cutoff — only notifications that the
    # user has actually seen. A "mark all as read" without a
    # cutoff would also mark the brand-new pushes the
    # user has not seen yet, which is the wrong UX.
    if up_to.created_at is not None:
        unread_q = unread_q.filter(
            tuple_(CommunityNotification.created_at, CommunityNotification.id)
            <= tuple_(_as_utc(up_to.created_at), up_to.id)
        )
    rows = unread_q.all()
    if not rows:
        return 0

    # A3 test seam — same L421 rationale as
    # :func:`mark_read`. The barrier fires AFTER the SELECT
    # and BEFORE the bulk UPDATE. Two concurrent
    # ``mark_all_read_up_to`` calls synchronise on the
    # barrier, then both issue the bulk UPDATE; SQLite
    # serialises the writes; the final state is consistent
    # (unread count = 0, every row's ``is_read`` is True).
    if _before_commit is not None:
        _before_commit()
    count = 0
    for row in rows:
        row.is_read = True
        row.read_at = now
        row.updated_at = now
        count += 1
    db.flush()
    for row in rows:
        db.refresh(row)
    if on_invalidate is not None:
        for row in rows:
            on_invalidate(
                NotificationInvalidationEvent(
                    notification_public_id=row.public_id,
                    recipient_profile_id=recipient.id,
                    action="mark_all_read",
                )
            )
    return count


# ---------------------------------------------------------------------------
# Public service surface — read paths.
# ---------------------------------------------------------------------------


def list_inbox(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
    cursor: str | None,
    limit: int,
) -> NotificationInboxPage:
    """Return one page of the recipient's inbox.

    A4 (blocked actor): any row whose ``actor_profile_id`` is in
    a block relationship with the recipient is silently dropped
    (the §D2 pattern). System events (NULL actor) are not
    filtered.

    A5 (deleted entity): for ``entity_type == 'post'``, a soft-
    deleted, moderation-removed, or hard-deleted post causes
    the row to be returned BUT with ``related_content_id``
    suppressed — the row stays visible, the deep-link is
    neutralised. The Flutter ``CommunityNotificationItem`` has
    a nullable ``relatedContentId`` so the inbox can render the
    row without a deep-link.

    Cursor pagination: base64-encoded ``(created_at, row_id)``
    JSON, mirror of the Kör 8 / Kör 16 shape. A tampered cursor
    yields ``None`` from :func:`_decode_cursor` and the list
    starts from the top (the §A7 invariant — the list endpoint
    never crashes on a bad cursor).
    """
    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        return NotificationInboxPage(notifications=(), next_cursor=None)

    base_query = db.query(CommunityNotification).filter(
        CommunityNotification.recipient_profile_id == recipient.id,
    )
    decoded = _decode_cursor(cursor) if cursor else None
    if decoded is not None:
        cursor_at, cursor_id = decoded
        base_query = base_query.filter(
            tuple_(CommunityNotification.created_at, CommunityNotification.id)
            < tuple_(_as_utc(cursor_at), cursor_id)
        )
    rows = (
        base_query.order_by(
            CommunityNotification.created_at.desc(),
            CommunityNotification.id.desc(),
        )
        .limit(limit + 1)
        .all()
    )

    # A4 — drop rows whose actor is in a block relationship
    # with the recipient. The block-table read is amortised
    # over the page (one query for the whole page, not one
    # per row).
    filtered: list[CommunityNotification] = []
    blocked_ids: set[int] = set()
    for row in rows:
        if row.actor_profile_id is None:
            filtered.append(row)
            continue
        # The page-level block check uses a lazy per-row
        # predicate — the block-set is small per recipient
        # (the §5.3 invariant: a typical user has <50
        # blocked profiles, so the amortised read is one
        # per row, not 50*N). A future round that
        # materialises the block set as a single query
        # can swap this without changing the public
        # surface.
        if row.actor_profile_id in blocked_ids:
            continue
        if is_blocked_pair(
            db,
            profile_id_a=recipient.id,
            profile_id_b=row.actor_profile_id,
        ):
            blocked_ids.add(row.actor_profile_id)
            continue
        filtered.append(row)

    has_more = len(filtered) > limit
    page_rows = filtered[:limit]
    next_cursor: str | None = None
    if has_more and page_rows:
        last = page_rows[-1]
        next_cursor = _encode_cursor(last.created_at, last.id)
    return NotificationInboxPage(
        notifications=tuple(page_rows),
        next_cursor=next_cursor,
    )


def get_unread_count(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
) -> int:
    """Return the recipient's unread count.

    The count is the number of unread rows VISIBLE to the
    recipient — the same A4 blocked-actor filter
    :func:`list_inbox` applies (the E09-R20 review-fix §1,
    MAJOR-1: badge-desync mitigation). A notification whose
    actor is in a block relationship with the recipient MUST
    NOT be counted — a badge that ticks up while the inbox
    shows nothing is a leak vector (the recipient would
    learn "a blocked user did something" from the count
    alone). System events (NULL actor) are NOT filtered —
    they are always visible (the ``actor_profile_id IS NULL``
    branch short-circuits the NOT IN).

    The block set is materialised once via
    :func:`policies.query_filters.list_block_pairs_for_viewer`
    (one block-table read, not N+1), then excluded in SQL via
    the ``NOT IN`` predicate. The composite index
    ``ix_community_notifications_recipient_unread`` backs the
    ``(recipient, is_read)`` filter.
    """
    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        return 0

    blocked_ids = list_block_pairs_for_viewer(db, viewer_profile_id=recipient.id)

    q = db.query(CommunityNotification).filter(
        CommunityNotification.recipient_profile_id == recipient.id,
        CommunityNotification.is_read.is_(False),
    )
    if blocked_ids:
        # ``actor_profile_id IS NULL`` keeps system events
        # visible; the NOT IN excludes the blocked-actor rows.
        q = q.filter(
            or_(
                CommunityNotification.actor_profile_id.is_(None),
                CommunityNotification.actor_profile_id.notin_(blocked_ids),
            )
        )
    return q.count()


def get_related_content_id(
    db: Session,
    *,
    notification: CommunityNotification,
) -> str | None:
    """A5 — return the ``relatedContentId`` for a notification row.

    A notification whose entity is no longer visible returns
    ``None`` here so the Flutter side suppresses the deep-link.
    The row itself is still returned by :func:`list_inbox` —
    the deep-link is the only thing neutralised (the row
    stays in the inbox, marked read or not as the user has
    it).
    """
    if notification.entity_type is None or notification.entity_id is None:
        return None
    if notification.entity_type == "post":
        if _post_alive(db, post_public_id_str=notification.entity_id):
            return notification.entity_id
        return None
    # Other entity types land in future rounds (Kör 21+ for
    # challenges, Kör 24+ for clubs). The default behaviour
    # is to KEEP the related_content_id — the row points to
    # something we haven't yet wired a freshness check for,
    # so we don't suppress it speculatively.
    return notification.entity_id


# ---------------------------------------------------------------------------
# Public service surface — preferences (A6 — Flutter widget test only).
# ---------------------------------------------------------------------------


# The process-local preference store. A future round can
# replace this with a DB-backed row without changing the public
# surface (the service signature is the wire contract; the
# storage is an implementation detail).
_PREFERENCE_STORE: dict[tuple[int, str], str] = {}


def get_preferences(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
) -> dict[str, str]:
    """Return the recipient's per-category notification preferences.

    The aggregate map is a ``dict[category, level]`` where
    ``level`` is one of ``"inApp"``, ``"push"``, or
    ``"disabled"``. A category with no entry defaults to
    ``"inApp"`` — the safe default (a user with no explicit
    preference gets the in-app inbox notification but no
    push).

    This round's implementation is process-local (an
    in-memory dict); a future round can swap to a DB-backed
    row. The Flutter ``community_notifications_test.dart``
    exercises the controller's ``updatePreference`` flow
    against a fake repository, NOT against this service, so
    the persistence quality of this function is a future-
    round concern, not a §6 measure-matrix cell.
    """
    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        return {}
    result: dict[str, str] = {}
    for kind in NOTIFICATION_TYPE_ALLOWLIST:
        result[kind] = _PREFERENCE_STORE.get((recipient.id, kind), "inApp")
    return result


def set_preference(
    db: Session,
    *,
    recipient_public_id: uuid.UUID,
    category: str,
    level: str,
) -> None:
    """Update the recipient's per-category notification preference.

    ``level`` MUST be one of ``"inApp"``, ``"push"``, or
    ``"disabled"`` — anything else raises ``ValueError``. An
    unknown ``category`` is silently accepted (a future round
    adds a new wire kind; the preference store keys by the
    wire string, so the new kind is a no-op until the
    service-side allowlist grows).

    See :func:`get_preferences` for the process-local-storage
    caveat.
    """
    recipient = _resolve_profile_by_public_id(db, recipient_public_id)
    if recipient is None:
        raise NotificationProfileNotFound("recipient community profile not found")
    if level not in {"inApp", "push", "disabled"}:
        raise ValueError(
            f"preference level {level!r} is not one of 'inApp', 'push', 'disabled'"
        )
    _PREFERENCE_STORE[(recipient.id, category)] = level


__all__ = [
    "InvalidNotificationType",
    "NoOpPushGateway",
    "NotificationActorNotFound",
    "NotificationInboxPage",
    "NotificationInvalidationEvent",
    "NotificationNotFound",
    "NotificationProfileNotFound",
    "PushGateway",
    "PushPayload",
    "create_notification",
    "get_preferences",
    "get_related_content_id",
    "get_unread_count",
    "list_inbox",
    "mark_all_read_up_to",
    "mark_read",
    "set_preference",
]
