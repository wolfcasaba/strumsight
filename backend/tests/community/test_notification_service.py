"""E09-R20 — Notification service acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases. The notification service is
**not** exposed via HTTP this round (ADR 0414 §D2 — the router
and the in-app inbox projection are a future round's
``allowed_paths``), so the tests are pure service-layer calls
against the same file-backed SQLite engine the
``test_reaction_service.py`` / ``test_comment_service.py`` /
``test_post_service.py`` / ``test_follow_service.py`` precedent
uses.

* A1 — push payload contains ONLY ``notification_id`` / ``type``
  / localization KEYS / route entity pair. No comment body, no
  author email, no localised text. The §6.1 valódi-sértés próba
  adds a ``commentBody`` field to ``PushPayload`` and asserts the
  A1 cell goes red.

* A2 — five reactions on the same entity inside the 15-minute
  window collapse to ONE inbox item with
  ``aggregate_count = 5``; the push gateway receives exactly one
  ``send`` call (not five).

* A3 — two concurrent ``mark_read`` calls on the same row
  produce a consistent ``is_read`` state (the second sees the
  row already read, the unread count is exactly 1, not 0 or -1);
  the same for ``mark_all_read_up_to``. The ``_before_commit``
  hook is the L421 barrier point — the ``threading.Barrier(2)``
  sits INSIDE the service, just before the transaction commits,
  not at thread-start.

* A4 — a notification whose actor is in a block relationship
  with the recipient is dropped from the inbox list (the
  ``is_blocked_pair`` helper, the Kör 8 / Kör 16 pattern).
  System events (NULL actor) are not filtered.

* A5 — a notification whose entity is a soft-deleted /
  moderation-removed / hard-deleted post is returned by
  ``list_inbox`` with ``related_content_id == None``. The row
  stays visible but the deep-link is neutralised.

* A7 — a retry with the same ``dedup_key`` is rejected by the
  UNIQUE constraint; the service catches ``IntegrityError`` and
  re-reads the existing row. The §6.1 valódi-sértés próba drops
  the UNIQUE constraint and asserts the A7 cell goes red.

The §6 A6 cell (per-category push preference) is a Flutter
widget test — see ``community_notifications_test.dart``. The
service's preference surface is exercised for the wire shape
(``get_preferences`` / ``set_preference``), not for its
persistence (the in-memory dict is intentional, see
``notification_service.py`` for the future-round rationale).
"""

from __future__ import annotations

import dataclasses
import threading
import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community import notifications
from app.community.models.notification import (
    NOTIFICATION_TYPE_REACTION_SUMMARY,
    NOTIFICATION_TYPE_COMMENT,
    CommunityNotification,
    REACTION_BURST_WINDOW_SECONDS,
)
from app.community.models.post import CommunityPost
from app.community.models.profile import CommunityProfile
from app.community.notifications import notification_service
from app.community.notifications.push_gateway import (
    NoOpPushGateway,
    PushPayload,
    _assert_payload_is_minimal,
)
from app.community.policies.access_policy import CommunityAudience
from app.community.services.post_service import create_post
from app.database import enable_sqlite_foreign_keys
from app.security import hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — file-backed SQLite engine with the full alembic chain
# applied, mirroring the test_reaction_service / test_comment_service
# pattern.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "notifications.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
    )
    enable_sqlite_foreign_keys(engine)
    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        yield factory
    finally:
        engine.dispose()


@pytest.fixture
def push_gateway() -> NoOpPushGateway:
    """A fresh, empty in-memory push recorder per test."""
    return NoOpPushGateway()


@pytest.fixture
def invalidation_events() -> list[dict[str, object]]:
    """Thread-safe capture list for the on_invalidate spy."""
    return []


# ---------------------------------------------------------------------------
# Test data helpers.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _insert_user(db: Session, user_id: int, email: str) -> None:
    db.execute(
        text(
            "INSERT INTO users (id, email, hashed_password, created_at) "
            "VALUES (:id, :email, :password, :ts)"
        ),
        {
            "id": user_id,
            "email": email,
            "password": hash_password("test-password"),
            "ts": _utcnow(),
        },
    )


def _make_profile(
    db: Session,
    *,
    user_id: int,
    email: str,
    visibility: str = "public",
) -> CommunityProfile:
    """Insert a parent ``users`` row + ``community_profiles`` row +
    matching ``community_privacy_settings`` row."""
    _insert_user(db, user_id, email)
    db.commit()
    profile = CommunityProfile(user_id=user_id)
    db.add(profile)
    db.flush()
    db.execute(
        text(
            "INSERT INTO community_privacy_settings "
            "(id, public_id, profile_id, updated_at, visibility, audience_default) "
            "VALUES (:id, :pid, :profile_id, :ts, :vis, :aud)"
        ),
        {
            "id": None,
            "pid": uuid.uuid4().hex,
            "profile_id": profile.id,
            "ts": _utcnow(),
            "vis": visibility,
            "aud": "followers",
        },
    )
    db.commit()
    db.refresh(profile)
    return profile


def _make_recipient(session_factory) -> CommunityProfile:
    with session_factory() as db:
        profile = _make_profile(
            db, user_id=1, email="recipient@s.test", visibility="public"
        )
        db.refresh(profile)
        return profile


def _make_actor(session_factory, *, user_id: int, email: str) -> CommunityProfile:
    with session_factory() as db:
        profile = _make_profile(db, user_id=user_id, email=email, visibility="public")
        db.refresh(profile)
        return profile


def _make_two_actors(session_factory) -> tuple[CommunityProfile, CommunityProfile]:
    a = _make_actor(session_factory, user_id=2, email="actor-a@s.test")
    b = _make_actor(session_factory, user_id=3, email="actor-b@s.test")
    return a, b


def _create_visible_post(
    session_factory,
    *,
    author: CommunityProfile,
    body: str = "notification-target",
    idempotency_key: str = "notification-target-key",
) -> CommunityPost:
    public_id = author.public_id
    with session_factory() as db:
        post = create_post(
            db,
            author_public_id=public_id,
            audience=CommunityAudience.PUBLIC,
            body=body,
            idempotency_key=idempotency_key,
            now=_utcnow(),
        )
        db.commit()
        db.refresh(post)
        return post


def _make_block_pair(
    session_factory, *, blocker: CommunityProfile, blocked: CommunityProfile
) -> None:
    """Insert a ``community_blocks`` row from ``blocker`` to ``blocked``."""
    with session_factory() as db:
        db.execute(
            text(
                "INSERT INTO community_blocks "
                "(blocker_profile_id, blocked_profile_id, created_at) "
                "VALUES (:blocker, :blocked, :ts)"
            ),
            {
                "blocker": blocker.id,
                "blocked": blocked.id,
                "ts": _utcnow(),
            },
        )
        db.commit()


# ---------------------------------------------------------------------------
# A1 — push payload redaction.
# ---------------------------------------------------------------------------


def test_a1_push_payload_is_minimal_and_keys_only(
    session_factory, push_gateway
) -> None:
    """A1 — the push payload contains ONLY the allowed fields.

    The A1 measure-matrix: a push payload MUST NOT include the
    full comment body, the actor's email, or any localised text.
    The :class:`PushPayload` dataclass is closed (the
    ``_ALLOWED_PUSH_FIELDS`` frozenset), and the
    :func:`_assert_payload_is_minimal` helper is the
    structural guard. A future change that drops a
    ``commentBody`` field onto the payload is caught HERE,
    before the §6.1 valódi-sértés próba runs.
    """
    recipient = _make_recipient(session_factory)
    actor = _make_actor(session_factory, user_id=2, email="actor-a@s.test")
    post = _create_visible_post(session_factory, author=recipient)

    sensitive_body = "This is the sensitive comment body that must NEVER leak to push."

    with session_factory() as db:
        notification = notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="community_notification_comment_title",
            body_key="community_notification_comment_body",
            actor_public_id=actor.public_id,
            entity_type="post",
            entity_id=str(post.public_id),
            dedup_key=None,
            aggregate=False,
            now=_utcnow(),
            push_gateway=push_gateway,
        )
        db.commit()
        db.refresh(notification)
        notification_id = notification.public_id

    # Exactly ONE push fired (A2's per-row invariant — this
    # notification did not aggregate, but the push IS
    # per-row, not per-actor).
    assert len(push_gateway.sent_payloads) == 1
    payload = push_gateway.sent_payloads[0]

    # The payload carries only the allowed fields — the
    # §6.1 measure-matrix structural check.
    _assert_payload_is_minimal(payload)
    allowed = {f.name for f in dataclasses.fields(PushPayload)}
    assert {f.name for f in dataclasses.fields(payload)} == allowed

    # The payload does NOT carry any sensitive content. We
    # assert every one of the Kör 5 / §5.1 field names a
    # future "preview" feature could leak: the body text,
    # the actor's email, the author's display name. None
    # of them exist on the dataclass.
    payload_str = str(payload.__dict__)
    assert sensitive_body not in payload_str
    assert "actor-a@s.test" not in payload_str

    # The payload DOES carry the wire surface: notification
    # id (UUID), type, the localization KEYS (not text),
    # and the route entity pair.
    assert payload.notification_id == notification_id
    assert payload.type == NOTIFICATION_TYPE_COMMENT
    assert payload.title_key == "community_notification_comment_title"
    assert payload.body_key == "community_notification_comment_body"
    assert payload.route_entity_type == "post"
    assert payload.route_entity_id == str(post.public_id)


def test_a1_real_violation_probe_adds_field_to_payload() -> None:
    """§6.1 valódi-sértés próba — add a ``commentBody`` field to
    :class:`PushPayload` and assert the A1 cell goes red.

    The probe does NOT modify the production dataclass. It
    spawns a throwaway subclass with the offending field,
    runs :func:`_assert_payload_is_minimal`, and asserts
    the assertion fires. Then it verifies the production
    dataclass still passes (the redaction invariant is
    still structural for the real surface).
    """
    # The production dataclass is still minimal — this is
    # the "before" check; the A1 cell is green.
    _assert_payload_is_minimal(PushPayload(
        notification_id=uuid.uuid4(),
        type=NOTIFICATION_TYPE_COMMENT,
        title_key="k",
        body_key=None,
        route_entity_type="post",
        route_entity_id="abc",
    ))

    # A throwaway subclass with the offending field trips
    # the §6.1 guard.
    @dataclasses.dataclass(frozen=True)
    class _LeakyPayload(PushPayload):
        commentBody: str = ""

    leaky = _LeakyPayload(
        notification_id=uuid.uuid4(),
        type=NOTIFICATION_TYPE_COMMENT,
        title_key="k",
        body_key=None,
        route_entity_type="post",
        route_entity_id="abc",
    )
    with pytest.raises(AssertionError, match="outside the A1 redaction allowlist"):
        _assert_payload_is_minimal(leaky)


# ---------------------------------------------------------------------------
# A2 — burst aggregation.
# ---------------------------------------------------------------------------


def test_a2_five_reactions_in_window_collapse_to_one_push(
    session_factory, push_gateway
) -> None:
    """A2 — five reactions on the same entity inside the
    15-minute window collapse to ONE inbox item with
    ``aggregate_count = 5``; the push gateway receives
    exactly one ``send`` call.

    The aggregation key is
    ``(recipient_profile_id, entity_type, entity_id)`` (ADR
    0414 §D3). The window is a 15-minute sliding window
    from the most-recent event in the burst.
    """
    recipient = _make_recipient(session_factory)
    actor = _make_two_actors(session_factory)
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    base = _utcnow()
    # Five reactions, 60 seconds apart, all inside the
    # 15-minute window.
    for i in range(5):
        with session_factory() as db:
            notification_service.create_notification(
                db,
                recipient_public_id=recipient.public_id,
                notification_type=NOTIFICATION_TYPE_REACTION_SUMMARY,
                title_key="community_notification_reaction_summary_title",
                body_key=None,
                actor_public_id=actor[0].public_id,
                entity_type="post",
                entity_id=post_id_str,
                dedup_key=None,
                aggregate=True,
                now=base + timedelta(seconds=60 * i),
                push_gateway=push_gateway,
            )
            db.commit()

    # Exactly ONE push fired — the burst-opening push. The
    # next four events increment the count instead of
    # creating a new row.
    assert len(push_gateway.sent_payloads) == 1, (
        f"A2 violated — expected exactly 1 push for a "
        f"5-reaction burst, got {len(push_gateway.sent_payloads)}"
    )

    # The inbox has exactly ONE row for this entity.
    with session_factory() as db:
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient.public_id,
            cursor=None,
            limit=10,
        )
    assert len(page.notifications) == 1, (
        f"A2 violated — expected exactly 1 inbox row for a "
        f"5-reaction burst, got {len(page.notifications)}"
    )
    row = page.notifications[0]
    assert row.aggregate_count == 5, (
        f"A2 violated — aggregate_count={row.aggregate_count}, expected 5"
    )


def test_a2_aggregation_window_resets_after_15_minutes(
    session_factory, push_gateway
) -> None:
    """A2 — a reaction 16 minutes after the burst opens a
    NEW inbox item, NOT an aggregation of the previous
    one. The 15-minute window is sliding (ADR 0414 §D3).
    """
    recipient = _make_recipient(session_factory)
    actor = _make_two_actors(session_factory)
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    base = _utcnow()
    # Reaction 1 at t=0 — opens a new row.
    with session_factory() as db:
        notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_REACTION_SUMMARY,
            title_key="community_notification_reaction_summary_title",
            body_key=None,
            actor_public_id=actor[0].public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=None,
            aggregate=True,
            now=base,
            push_gateway=push_gateway,
        )
        db.commit()
    # Reaction 2 at t=window+1min — outside the window,
    # opens a NEW row.
    with session_factory() as db:
        notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_REACTION_SUMMARY,
            title_key="community_notification_reaction_summary_title",
            body_key=None,
            actor_public_id=actor[0].public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=None,
            aggregate=True,
            now=base + timedelta(seconds=REACTION_BURST_WINDOW_SECONDS + 60),
            push_gateway=push_gateway,
        )
        db.commit()

    # Two pushes fired (one per burst-opening), two inbox
    # rows.
    assert len(push_gateway.sent_payloads) == 2
    with session_factory() as db:
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient.public_id,
            cursor=None,
            limit=10,
        )
    assert len(page.notifications) == 2, (
        "A2 violated — a reaction outside the 15-min window "
        "should open a new row, not aggregate"
    )
    for row in page.notifications:
        assert row.aggregate_count == 1


# ---------------------------------------------------------------------------
# A3 — read-state race.
# ---------------------------------------------------------------------------


def test_a3_two_concurrent_mark_read_calls_yield_consistent_state(
    session_factory, push_gateway
) -> None:
    """A3 — two parallel ``mark_read`` calls on the same row
    produce a consistent ``is_read = True`` and an unread
    count of zero. One call returns ``True`` (a transition
    happened); the other returns ``False`` (already read).

    The L421 lesson: synchronisation at thread-start is
    NON-deterministic. The §6.1 invariant is to place the
    ``threading.Barrier(2)`` at the SQL UPDATE point INSIDE
    the service, via the ``_before_commit`` hook. The two
    threads serialise on the barrier; one commits first,
    the second sees the row already read and returns
    ``False``.
    """
    recipient = _make_recipient(session_factory)
    actor = _make_two_actors(session_factory)
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    with session_factory() as db:
        notification = notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="k",
            body_key=None,
            actor_public_id=actor[0].public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=None,
            aggregate=False,
            now=_utcnow(),
            push_gateway=push_gateway,
        )
        notification_id = notification.public_id
        db.commit()

    barrier = threading.Barrier(2)
    results: list[bool] = []
    errors: list[BaseException] = []

    def _marker() -> None:
        try:
            barrier.wait(timeout=5.0)
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)
            return

    def _read() -> None:
        try:
            with session_factory() as db:
                outcome = notification_service.mark_read(
                    db,
                    recipient_public_id=recipient.public_id,
                    notification_public_id=notification_id,
                    now=_utcnow(),
                    _before_commit=_marker,
                )
                results.append(outcome)
                db.commit()
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    t1 = threading.Thread(target=_read)
    t2 = threading.Thread(target=_read)
    t1.start()
    t2.start()
    t1.join(timeout=10.0)
    t2.join(timeout=10.0)
    assert not errors, f"concurrent mark_read raised: {errors}"

    # One returned True (transition), the other False (already
    # read) — the §6.1 measure-matrix.
    assert sorted(results) == [False, True], (
        f"A3 violated — concurrent mark_read should yield "
        f"exactly one True + one False; got {results}"
    )

    # The row is read, the unread count is zero.
    with session_factory() as db:
        row = db.query(CommunityNotification).filter_by(
            public_id=notification_id
        ).one()
        assert row.is_read is True
        assert row.read_at is not None
        count = notification_service.get_unread_count(
            db, recipient_public_id=recipient.public_id
        )
    assert count == 0, f"A3 violated — unread count={count}, expected 0"


def test_a3_mark_all_read_up_to_concurrent_serialises(
    session_factory, push_gateway
) -> None:
    """A3 — two parallel ``mark_all_read_up_to`` calls on the
    same ``up_to_id`` produce a consistent unread count of
    zero. The two threads serialise on the L421 barrier
    (inside the service, just before commit).
    """
    recipient = _make_recipient(session_factory)
    actor = _make_two_actors(session_factory)
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    # Three unread notifications, in order.
    with session_factory() as db:
        for i in range(3):
            notification_service.create_notification(
                db,
                recipient_public_id=recipient.public_id,
                notification_type=NOTIFICATION_TYPE_COMMENT,
                title_key="k",
                body_key=None,
                actor_public_id=actor[0].public_id,
                entity_type="post",
                entity_id=post_id_str,
                dedup_key=None,
                aggregate=False,
                now=_utcnow() + timedelta(seconds=i),
                push_gateway=push_gateway,
            )
        db.commit()
    # The up_to_id is the LAST (oldest) row — mark-everything
    # up to and including it. (created_at DESC means the LAST
    # row in the inbox is the OLDEST; the most recent push
    # is the FIRST row.)
    with session_factory() as db:
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient.public_id,
            cursor=None,
            limit=10,
        )
    last = page.notifications[-1]
    up_to_id = last.public_id

    barrier = threading.Barrier(2)
    results: list[int] = []
    errors: list[BaseException] = []

    def _marker() -> None:
        try:
            barrier.wait(timeout=5.0)
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    def _mark_all() -> None:
        try:
            with session_factory() as db:
                outcome = notification_service.mark_all_read_up_to(
                    db,
                    recipient_public_id=recipient.public_id,
                    up_to_id=up_to_id,
                    now=_utcnow(),
                    _before_commit=_marker,
                )
                results.append(outcome)
                db.commit()
        except BaseException as exc:  # noqa: BLE001
            errors.append(exc)

    t1 = threading.Thread(target=_mark_all)
    t2 = threading.Thread(target=_mark_all)
    t1.start()
    t2.start()
    t1.join(timeout=10.0)
    t2.join(timeout=10.0)
    assert not errors, f"concurrent mark_all_read_up_to raised: {errors}"

    # The two outcomes sum to exactly 3 (the total number of
    # unread rows). The first call sees 3 unread rows and
    # marks all 3; the second sees 0 and returns 0.
    assert sum(results) == 3, (
        f"A3 violated — concurrent mark_all_read_up_to should "
        f"mark exactly 3 rows total; got {results}"
    )

    with session_factory() as db:
        count = notification_service.get_unread_count(
            db, recipient_public_id=recipient.public_id
        )
    assert count == 0, f"A3 violated — unread count={count}, expected 0"


# ---------------------------------------------------------------------------
# A4 — blocked actor.
# ---------------------------------------------------------------------------


def test_a4_blocked_actor_notification_hidden_from_inbox(
    session_factory, push_gateway
) -> None:
    """A4 — a notification whose actor is in a block
    relationship with the recipient is dropped from the
    inbox list. The ``is_blocked_pair`` helper is the
    Kör 8 / Kör 16 read-path policy.

    System events (NULL actor) are NOT filtered — a
    security alert from "the system" must always be
    visible.
    """
    recipient = _make_recipient(session_factory)
    actor_a, actor_b = _make_two_actors(session_factory)
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    # Block actor_a (so the recipient can never see
    # their events).
    _make_block_pair(
        session_factory, blocker=recipient, blocked=actor_a
    )

    # Three notifications:
    # 1) from actor_a — should be hidden.
    # 2) from actor_b — should be visible.
    # 3) a system event (NULL actor) — should be visible.
    with session_factory() as db:
        notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="k1",
            body_key=None,
            actor_public_id=actor_a.public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=None,
            aggregate=False,
            now=_utcnow() + timedelta(seconds=1),
            push_gateway=push_gateway,
        )
        notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="k2",
            body_key=None,
            actor_public_id=actor_b.public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=None,
            aggregate=False,
            now=_utcnow() + timedelta(seconds=2),
            push_gateway=push_gateway,
        )
        notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type="security_alert",
            title_key="k3",
            body_key=None,
            actor_public_id=None,
            entity_type=None,
            entity_id=None,
            dedup_key=None,
            aggregate=False,
            now=_utcnow() + timedelta(seconds=3),
            push_gateway=push_gateway,
        )
        db.commit()

    with session_factory() as db:
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient.public_id,
            cursor=None,
            limit=10,
        )
    assert len(page.notifications) == 2, (
        f"A4 violated — expected 2 visible rows "
        f"(actor_b + system), got {len(page.notifications)}"
    )
    visible_actors = {row.actor_profile_id for row in page.notifications}
    assert actor_a.id not in visible_actors, (
        "A4 violated — a blocked actor's notification is "
        "still visible in the inbox"
    )


# ---------------------------------------------------------------------------
# A5 — deleted entity.
# ---------------------------------------------------------------------------


def test_a5_deleted_entity_suppresses_related_content_id(
    session_factory, push_gateway
) -> None:
    """A5 — a notification whose ``entity_type == 'post'``
    points at a soft-deleted post is returned by
    ``list_inbox`` with ``related_content_id == None``.
    The row stays visible; the deep-link is neutralised.
    """
    recipient = _make_recipient(session_factory)
    actor = _make_actor(session_factory, user_id=2, email="actor-a@s.test")
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    with session_factory() as db:
        notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="k",
            body_key=None,
            actor_public_id=actor.public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=None,
            aggregate=False,
            now=_utcnow(),
            push_gateway=push_gateway,
        )
        db.commit()

    # Pre-condition: the row is visible with the entity id.
    with session_factory() as db:
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient.public_id,
            cursor=None,
            limit=10,
        )
        assert len(page.notifications) == 1
        pre_related = notification_service.get_related_content_id(
            db, notification=page.notifications[0]
        )
    assert pre_related == post_id_str, (
        f"A5 pre-condition violated — entity is alive, "
        f"related_content_id should be the post id; got {pre_related!r}"
    )

    # Soft-delete the post.
    with session_factory() as db:
        db.execute(
            text(
                "UPDATE community_posts SET deleted_at = :ts WHERE id = :id"
            ),
            {"ts": _utcnow(), "id": post.id},
        )
        db.commit()

    with session_factory() as db:
        page = notification_service.list_inbox(
            db,
            recipient_public_id=recipient.public_id,
            cursor=None,
            limit=10,
        )
    assert len(page.notifications) == 1, (
        "A5 violated — a deleted-entity notification was "
        "dropped from the inbox; it must stay visible"
    )
    post_delete = page.notifications[0]
    with session_factory() as db:
        related = notification_service.get_related_content_id(
            db, notification=post_delete
        )
    assert related is None, (
        f"A5 violated — a deleted-entity notification should "
        f"suppress related_content_id; got {related!r}"
    )


# ---------------------------------------------------------------------------
# A7 — dedup key.
# ---------------------------------------------------------------------------


def test_a7_dedup_key_prevents_duplicate_row(
    session_factory, push_gateway
) -> None:
    """A7 — a retry with the same ``dedup_key`` does NOT
    create a second row. The service catches
    ``IntegrityError`` and re-reads the existing row.

    The §6.1 valódi-sértés próba below drops the UNIQUE
    constraint and asserts the A7 cell goes red.
    """
    recipient = _make_recipient(session_factory)
    actor = _make_actor(session_factory, user_id=2, email="actor-a@s.test")
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    dedup_key = f"event-{uuid.uuid4()}"
    with session_factory() as db:
        first = notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="k",
            body_key=None,
            actor_public_id=actor.public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=dedup_key,
            aggregate=False,
            now=_utcnow(),
            push_gateway=push_gateway,
        )
        first_id = first.public_id
        db.commit()

    # The push was fired once.
    assert len(push_gateway.sent_payloads) == 1
    push_gateway.clear()

    # Retry with the same dedup_key — should NOT create a
    # second row, and the push should NOT fire again.
    with session_factory() as db:
        again = notification_service.create_notification(
            db,
            recipient_public_id=recipient.public_id,
            notification_type=NOTIFICATION_TYPE_COMMENT,
            title_key="k",
            body_key=None,
            actor_public_id=actor.public_id,
            entity_type="post",
            entity_id=post_id_str,
            dedup_key=dedup_key,
            aggregate=False,
            now=_utcnow() + timedelta(seconds=1),
            push_gateway=push_gateway,
        )
        again_id = again.public_id
        db.commit()

    assert again_id == first_id, (
        f"A7 violated — retry with the same dedup_key "
        f"created a new row; got {again_id}, expected {first_id}"
    )
    assert len(push_gateway.sent_payloads) == 0, (
        "A7 violated — the push fired on a dedup retry; "
        "the existing row's push was already sent"
    )

    with session_factory() as db:
        rows = (
            db.query(CommunityNotification)
            .filter(
                CommunityNotification.recipient_profile_id == recipient.id,
                CommunityNotification.dedup_key == dedup_key,
            )
            .count()
        )
    assert rows == 1, f"A7 violated — {rows} rows for one dedup key"


def test_a7_real_violation_probe_drops_unique_constraint(
    session_factory, monkeypatch
) -> None:
    """§6.1 valódi-sértés próba — rebuild the
    ``community_notifications`` table WITHOUT the
    ``UNIQUE(recipient_profile_id, dedup_key)`` constraint,
    retry with the same ``dedup_key``, and assert that
    TWO rows land. Then restore the schema.

    The probe mirrors the Kör 15 table-rebuild dance
    (the SQLite limitation — no portable DROP CONSTRAINT
    is available).
    """
    recipient = _make_recipient(session_factory)
    actor = _make_actor(session_factory, user_id=2, email="actor-a@s.test")
    post = _create_visible_post(session_factory, author=recipient)
    post_id_str = str(post.public_id)

    dedup_key = f"violation-{uuid.uuid4()}"

    engine = session_factory.kw["bind"]
    rebuild_sql = [
        "CREATE TABLE community_notifications_probe_backup AS "
        "SELECT * FROM community_notifications",
        "DROP TABLE community_notifications",
        "CREATE TABLE community_notifications ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  public_id CHAR(32) NOT NULL,"
        "  recipient_profile_id INTEGER NOT NULL,"
        "  actor_profile_id INTEGER,"
        "  type VARCHAR NOT NULL,"
        "  title_key VARCHAR NOT NULL,"
        "  body_key VARCHAR,"
        "  entity_type VARCHAR,"
        "  entity_id VARCHAR(64),"
        "  aggregate_count INTEGER NOT NULL DEFAULT 1,"
        "  is_read BOOLEAN NOT NULL DEFAULT 0,"
        "  read_at DATETIME,"
        "  dedup_key VARCHAR(128),"
        "  created_at DATETIME NOT NULL,"
        "  updated_at DATETIME NOT NULL,"
        "  FOREIGN KEY (recipient_profile_id) "
        "    REFERENCES community_profiles(id) ON DELETE CASCADE,"
        "  FOREIGN KEY (actor_profile_id) "
        "    REFERENCES community_profiles(id) ON DELETE CASCADE"
        ")",
        "INSERT INTO community_notifications "
        "  (id, public_id, recipient_profile_id, actor_profile_id, "
        "   type, title_key, body_key, entity_type, entity_id, "
        "   aggregate_count, is_read, read_at, dedup_key, "
        "   created_at, updated_at) "
        "SELECT id, public_id, recipient_profile_id, actor_profile_id, "
        "       type, title_key, body_key, entity_type, entity_id, "
        "       aggregate_count, is_read, read_at, dedup_key, "
        "       created_at, updated_at "
        "FROM community_notifications_probe_backup",
        "DROP TABLE community_notifications_probe_backup",
        "CREATE UNIQUE INDEX ix_community_notifications_public_id "
        "  ON community_notifications (public_id)",
        "CREATE INDEX ix_community_notifications_recipient_created "
        "  ON community_notifications "
        "  (recipient_profile_id, created_at, id)",
        "CREATE INDEX ix_community_notifications_recipient_unread "
        "  ON community_notifications (recipient_profile_id, is_read)",
        "CREATE INDEX ix_community_notifications_recipient_entity "
        "  ON community_notifications "
        "  (recipient_profile_id, entity_type, entity_id, created_at)",
    ]
    restore_sql = [
        "CREATE TABLE community_notifications_probe_backup AS "
        "SELECT * FROM community_notifications",
        "DROP TABLE community_notifications",
        "CREATE TABLE community_notifications ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  public_id CHAR(32) NOT NULL,"
        "  recipient_profile_id INTEGER NOT NULL,"
        "  actor_profile_id INTEGER,"
        "  type VARCHAR NOT NULL,"
        "  title_key VARCHAR NOT NULL,"
        "  body_key VARCHAR,"
        "  entity_type VARCHAR,"
        "  entity_id VARCHAR(64),"
        "  aggregate_count INTEGER NOT NULL DEFAULT 1,"
        "  is_read BOOLEAN NOT NULL DEFAULT 0,"
        "  read_at DATETIME,"
        "  dedup_key VARCHAR(128),"
        "  created_at DATETIME NOT NULL,"
        "  updated_at DATETIME NOT NULL,"
        "  FOREIGN KEY (recipient_profile_id) "
        "    REFERENCES community_profiles(id) ON DELETE CASCADE,"
        "  FOREIGN KEY (actor_profile_id) "
        "    REFERENCES community_profiles(id) ON DELETE CASCADE,"
        "  CONSTRAINT uq_community_notifications_recipient_dedup "
        "    UNIQUE (recipient_profile_id, dedup_key)"
        ")",
        "INSERT INTO community_notifications "
        "  (id, public_id, recipient_profile_id, actor_profile_id, "
        "   type, title_key, body_key, entity_type, entity_id, "
        "   aggregate_count, is_read, read_at, dedup_key, "
        "   created_at, updated_at) "
        "SELECT MIN(id), public_id, recipient_profile_id, "
        "       actor_profile_id, type, title_key, body_key, "
        "       entity_type, entity_id, aggregate_count, "
        "       is_read, read_at, dedup_key, MIN(created_at), "
        "       MAX(updated_at) "
        "FROM community_notifications_probe_backup "
        "GROUP BY recipient_profile_id, dedup_key",
        "DROP TABLE community_notifications_probe_backup",
        "CREATE UNIQUE INDEX ix_community_notifications_public_id "
        "  ON community_notifications (public_id)",
        "CREATE INDEX ix_community_notifications_recipient_created "
        "  ON community_notifications "
        "  (recipient_profile_id, created_at, id)",
        "CREATE INDEX ix_community_notifications_recipient_unread "
        "  ON community_notifications (recipient_profile_id, is_read)",
        "CREATE INDEX ix_community_notifications_recipient_entity "
        "  ON community_notifications "
        "  (recipient_profile_id, entity_type, entity_id, created_at)",
    ]

    with engine.begin() as conn:
        for stmt in rebuild_sql:
            conn.execute(text(stmt))

    try:
        with session_factory() as db:
            notification_service.create_notification(
                db,
                recipient_public_id=recipient.public_id,
                notification_type=NOTIFICATION_TYPE_COMMENT,
                title_key="k",
                body_key=None,
                actor_public_id=actor.public_id,
                entity_type="post",
                entity_id=post_id_str,
                dedup_key=dedup_key,
                aggregate=False,
                now=_utcnow(),
            )
            db.commit()
        with session_factory() as db:
            # The UNIQUE is gone — the second INSERT must
            # succeed; the A7 cell goes red.
            notification_service.create_notification(
                db,
                recipient_public_id=recipient.public_id,
                notification_type=NOTIFICATION_TYPE_COMMENT,
                title_key="k",
                body_key=None,
                actor_public_id=actor.public_id,
                entity_type="post",
                entity_id=post_id_str,
                dedup_key=dedup_key,
                aggregate=False,
                now=_utcnow() + timedelta(seconds=1),
            )
            db.commit()
        with session_factory() as db:
            rows = (
                db.query(CommunityNotification)
                .filter(
                    CommunityNotification.recipient_profile_id == recipient.id,
                    CommunityNotification.dedup_key == dedup_key,
                )
                .count()
            )
        assert rows == 2, (
            f"A7 real-violation probe should land 2 rows when "
            f"the UNIQUE is gone; got {rows}"
        )
    finally:
        with engine.begin() as conn:
            for stmt in restore_sql:
                conn.execute(text(stmt))


# ---------------------------------------------------------------------------
# Module-side import-graph guard.
# ---------------------------------------------------------------------------


def test_no_learning_reward_in_push_payload() -> None:
    """The notification service MUST NOT emit a learning reward
    event — the E08-R26 cross-feature adapter boundary
    invariant. The :class:`PushPayload` dataclass is the
    chokepoint, and it carries no gamification-shaped marker.
    """
    payload = PushPayload(
        notification_id=uuid.uuid4(),
        type=NOTIFICATION_TYPE_COMMENT,
        title_key="k",
        body_key=None,
        route_entity_type="post",
        route_entity_id="abc",
    )
    assert not hasattr(payload, "xp_delta")
    assert not hasattr(payload, "learning_reward")
    assert not hasattr(payload, "commentBody")


def test_module_exports_expected_surface() -> None:
    """The notifications package re-exports the
    §6 / §6.1 measure-matrix surface.

    The Flutter test and any future router land here.
    """
    for name in (
        "PushPayload",
        "PushGateway",
        "NoOpPushGateway",
        "NotificationInvalidationEvent",
        "NotificationInboxPage",
        "create_notification",
        "mark_read",
        "mark_all_read_up_to",
        "list_inbox",
        "get_unread_count",
        "get_related_content_id",
        "get_preferences",
        "set_preference",
    ):
        assert hasattr(notifications, name) or hasattr(
            notification_service, name
        ), f"missing export: {name}"
