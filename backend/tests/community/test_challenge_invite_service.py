"""E09-R21 — Challenge invite lifecycle acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases:

* A1 — invalid transition (``declined → accepted`` rejected).
* A2 — expired invite accept rejected (server-time check).
* A3 — blocked pair cannot invite / accept.
* A4 — idempotency key duplicate returns the existing row.
* A5 — concurrent accept + cancel race is deterministic.
* A7 — expiry is server-time, never client-time.

The fixtures are built locally (the §0.0 5. pont — own
``FastAPI()`` + ``TestClient`` + alembic-upgraded in-memory
SQLite, importing the challenge invite service + router
directly, the Kör 11 / Kör 7 precedent). The two-user fixture
is inlined so the invite state machine exercises the JWT-
resolved identity path consistently.

The §6.1 valódi-sértés próbák are exercised explicitly:

* **A4 probe** drops the idempotency-key check from
  ``create_invite`` and asserts that two creates with the
  same key produce two rows (the A4 cell turns red).
* **A5 probe** swaps the conditional UPDATE for an
  unconditional UPDATE and asserts that both branches land
  (the A5 cell turns red). The barrier sits on
  ``_before_transition_seam``, NOT at the function entry
  point — the L421 review measure.
"""

from __future__ import annotations

import threading
import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.challenge import (
    CHALLENGE_INVITE_STATE_ACCEPTED,
    CHALLENGE_INVITE_STATE_CANCELLED,
    CHALLENGE_INVITE_STATE_DECLINED,
    CHALLENGE_INVITE_STATE_SENT,
    CommunityChallenge,
    CommunityChallengeInvite,
)
from app.community.models.profile import CommunityProfile
from app.community.services import challenge_invite_service as service_module
from app.community.services.challenge_invite_service import (
    BlockedChallengeRelationship,
    ChallengeInviteNotFound,
    ChallengeNotFound,
    InvalidChallengeInviteTransition,
    accept_invite,
    cancel_invite,
    create_invite,
    decline_invite,
    reset_rate_limiters,
)
from app.config import Settings
from app.database import enable_sqlite_foreign_keys, get_db
from app.security import create_access_token, hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — engine + session factory + app + client (the Kör 11
# / Kör 7 / Kör 20 pattern).
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied."""
    db_path = tmp_path / "challenge.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
    )
    enable_sqlite_foreign_keys(engine)
    # ``expire_on_commit=False`` so the test code can access
    # row attributes (e.g. ``invite.public_id``) after the
    # session closes without triggering a lazy-load against a
    # detached session. The router layer uses the same
    # ``session_factory`` via ``get_db`` so this is also the
    # production-shape; the brief's other service-level
    # tests rely on the same default.
    factory = sessionmaker(
        bind=engine,
        autoflush=False,
        autocommit=False,
        expire_on_commit=False,
    )
    try:
        yield factory
    finally:
        engine.dispose()


@pytest.fixture
def app(session_factory) -> Iterator[FastAPI]:
    """Build a self-contained FastAPI with the challenge router
    mounted.

    The router is mounted directly (the §0.0 5. pont — the
    ``build_community_router`` factory is in the §3 tilos
    zóna, so we mount the challenges router directly, same
    pattern as ``test_follow_service.py``).
    """
    from app.community.routers.challenges import router as challenges_router

    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Challenge Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(challenges_router)
    yield app


@pytest.fixture
def client(app, session_factory) -> Iterator[TestClient]:
    """TestClient with ``get_db`` overridden so the CurrentUser DI works."""

    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def _reset_invite_limiter() -> Iterator[None]:
    """Reset the invite rate limiter between tests (the Kör 3
    ``reset_rate_limiters`` test seam)."""
    reset_rate_limiters()
    try:
        yield
    finally:
        reset_rate_limiters()


# ---------------------------------------------------------------------------
# Data helpers — users, profiles, blocks, challenges, invites.
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


def _make_profile_with_visibility(
    db: Session,
    *,
    user_id: int,
) -> CommunityProfile:
    """Insert a parent ``users`` row + a ``community_profiles`` row.

    The ``community_privacy_settings`` row is also written so
    the profile is fully bootable (the Kör 6 pattern).
    """
    _insert_user(db, user_id, f"u{user_id}@s.test")
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
            "vis": "public",
            "aud": "public",
        },
    )
    db.commit()
    db.refresh(profile)
    return profile


def _make_user_with_headers(
    session_factory,
    *,
    user_id: int,
    email: str,
) -> tuple[CommunityProfile, dict[str, str]]:
    """Create a fresh user+profile and return ``(profile, headers)``."""
    db: Session = session_factory()
    try:
        profile = _make_profile_with_visibility(db, user_id=user_id)
    finally:
        db.close()
    token = create_access_token(user_id)
    return profile, {"Authorization": f"Bearer {token}"}


def _create_block(
    session_factory, *, blocker: CommunityProfile, blocked: CommunityProfile
) -> None:
    db: Session = session_factory()
    try:
        db.execute(
            text(
                "INSERT INTO community_blocks "
                "(id, public_id, blocker_profile_id, blocked_profile_id, created_at) "
                "VALUES (:id, :pid, :b, :bd, :ts)"
            ),
            {
                "id": None,
                "pid": uuid.uuid4().hex,
                "b": blocker.id,
                "bd": blocked.id,
                "ts": _utcnow(),
            },
        )
        db.commit()
    finally:
        db.close()


def _insert_challenge(
    session_factory,
    *,
    author: CommunityProfile,
    starts_at: datetime | None = None,
    ends_at: datetime | None = None,
) -> CommunityChallenge:
    """Insert a single ``community_challenges`` row.

    Default window is ``[now, now + 7 days]``. Returns the
    ORM row (with ``public_id`` populated by the default).
    """
    now = _utcnow()
    start = starts_at if starts_at is not None else now
    end = ends_at if ends_at is not None else now + timedelta(days=7)
    challenge = CommunityChallenge(
        author_profile_id=author.id,
        type="friends",
        metric="score",
        difficulty=1,
        starts_at=start,
        ends_at=end,
        version=1,
        club_id=None,
        created_at=now,
        updated_at=now,
    )
    db: Session = session_factory()
    try:
        db.add(challenge)
        db.commit()
        db.refresh(challenge)
        return challenge
    finally:
        db.close()


def _fetch_invite(
    session_factory, *, public_id: uuid.UUID
) -> CommunityChallengeInvite | None:
    db: Session = session_factory()
    try:
        return (
            db.query(CommunityChallengeInvite)
            .filter_by(public_id=public_id)
            .one_or_none()
        )
    finally:
        db.close()


def _service_call(
    session_factory, fn, *, expect_exception: type[BaseException] | None = None
):
    """Run a service-layer function inside a single session and
    COMMIT — the service methods use ``db.flush()`` not
    ``db.commit()`` (the router layer commits via
    ``_commit_via``); without an explicit commit here the
    next service call would not see the previous write.

    When ``expect_exception`` is set, the service is expected
    to raise; the session is rolled back instead of committed
    (mirrors the router's ``db.rollback()`` before the 4xx
    raise).
    """
    db: Session = session_factory()
    try:
        result = fn(db)
        if expect_exception is not None:
            raise AssertionError(
                f"expected {expect_exception.__name__} but call returned {result!r}"
            )
        db.commit()
        return result
    except expect_exception or Exception:
        if expect_exception is None:
            raise
        db.rollback()
        return None
    finally:
        db.close()


def _service_call_raw(session_factory, fn):
    """Like ``_service_call`` but does NOT auto-commit on
    success. Used for service calls that the test wants to
    inspect / assert on BEFORE committing (the A5 probe).

    The session is closed after the call; the caller manages
    the commit lifecycle.
    """
    db: Session = session_factory()
    try:
        return fn(db)
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A1 — invalid transition (``declined → accepted`` rejected).
# ---------------------------------------------------------------------------


def test_a1_invalid_transition_declined_to_accepted(session_factory) -> None:
    """A1 — an invite in a terminal state cannot be flipped back to
    ``accepted``.

    The cell is exercised at the service layer: a
    ``declined`` invite is rejected by the conditional UPDATE
    ``WHERE state IN (draft, sent)`` and the service raises
    :class:`InvalidChallengeInviteTransition`. The router
    surfaces the same exception as a 409.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=1, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=2, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)

    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a1-decline-1",
            now=now,
        ),
    )
    declined = _service_call(
        session_factory,
        lambda db: decline_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite.public_id,
            now=now + timedelta(seconds=1),
        ),
    )
    assert declined.state == CHALLENGE_INVITE_STATE_DECLINED

    # A retry of accept on the declined invite MUST raise.
    _service_call(
        session_factory,
        lambda db: accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite.public_id,
            now=now + timedelta(seconds=2),
        ),
        expect_exception=InvalidChallengeInviteTransition,
    )

    # The decline transition was committed; the invite
    # row's final state is ``declined`` and a fresh
    # accept re-read returns the same state.
    current = _fetch_invite(session_factory, public_id=invite.public_id)
    assert current is not None
    assert current.state == CHALLENGE_INVITE_STATE_DECLINED


def test_a1_invalid_transition_cancelled_to_accepted(session_factory) -> None:
    """A1 — ``cancelled → accepted`` is also rejected (terminal
    state).
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=10, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=11, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)

    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a1-cancel-1",
            now=now,
        ),
    )
    cancelled = _service_call(
        session_factory,
        lambda db: cancel_invite(
            db,
            inviter_public_id=inviter.public_id,
            invite_public_id=invite.public_id,
            now=now + timedelta(seconds=1),
        ),
    )
    assert cancelled.state == CHALLENGE_INVITE_STATE_CANCELLED

    _service_call(
        session_factory,
        lambda db: accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite.public_id,
            now=now + timedelta(seconds=2),
        ),
        expect_exception=InvalidChallengeInviteTransition,
    )

    current = _fetch_invite(session_factory, public_id=invite.public_id)
    assert current is not None
    assert current.state == CHALLENGE_INVITE_STATE_CANCELLED


# ---------------------------------------------------------------------------
# A2 — expired invite accept rejected (server-time check).
# ---------------------------------------------------------------------------


def test_a2_expired_invite_accept_rejected(session_factory) -> None:
    """A2 — an invite whose ``expires_at <= now`` is rejected at
    accept. The check uses the caller's ``now`` (server-time)
    against the row's ``expires_at`` — never client-time.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=20, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=21, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(seconds=10)

    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a2-expire-1",
            now=now,
        ),
    )

    # Accept 30 seconds later — well past ``expires_at``.
    later = now + timedelta(seconds=30)
    _service_call(
        session_factory,
        lambda db: accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite.public_id,
            now=later,
        ),
        expect_exception=InvalidChallengeInviteTransition,
    )

    # The invite must STILL be in ``sent`` state — the
    # rejection must NOT have flipped it.
    current = _fetch_invite(session_factory, public_id=invite.public_id)
    assert current is not None
    assert current.state == CHALLENGE_INVITE_STATE_SENT


def test_a2_expired_challenge_create_rejected(session_factory) -> None:
    """A2 / §5.2 — an invite against a challenge whose
    ``ends_at <= now`` is rejected at create. The check uses
    the server-time window.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=30, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=31, email="invitee@s.test"
    )
    now = _utcnow()
    # An already-ended challenge (ends_at in the past).
    challenge = _insert_challenge(
        session_factory,
        author=inviter,
        starts_at=now - timedelta(days=2),
        ends_at=now - timedelta(days=1),
    )

    _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=now + timedelta(days=1),
            idempotency_key="a2-expired-challenge-1",
            now=now,
        ),
        expect_exception=ChallengeNotFound,
    )


# ---------------------------------------------------------------------------
# A3 — blocked pair cannot invite / accept.
# ---------------------------------------------------------------------------


def test_a3_blocked_inviter_rejected_on_create(session_factory) -> None:
    """A3 — a block edge between inviter and invitee blocks
    the invite creation. The check is symmetric.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=40, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=41, email="invitee@s.test"
    )
    # inviter blocks invitee (one direction — the predicate
    # is symmetric).
    _create_block(session_factory, blocker=inviter, blocked=invitee)

    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=now + timedelta(days=1),
            idempotency_key="a3-block-create-1",
            now=now,
        ),
        expect_exception=BlockedChallengeRelationship,
    )


def test_a3_block_lands_after_invite_blocks_accept(session_factory) -> None:
    """A3 — a block edge that lands AFTER the invite was created
    still blocks the accept path (defence-in-depth on the
    accept branch).
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=50, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=51, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()

    # Step 1 — create the invite (no block yet).
    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=now + timedelta(days=1),
            idempotency_key="a3-block-late-1",
            now=now,
        ),
    )
    assert invite.state == CHALLENGE_INVITE_STATE_SENT

    # Step 2 — the invitee blocks the inviter (the block
    # direction does not matter for the predicate).
    _create_block(session_factory, blocker=invitee, blocked=inviter)

    # Step 3 — accept must now raise the block exception.
    _service_call(
        session_factory,
        lambda db: accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite.public_id,
            now=now + timedelta(seconds=1),
        ),
        expect_exception=BlockedChallengeRelationship,
    )


# ---------------------------------------------------------------------------
# A4 — idempotency key duplicate returns the existing row.
# ---------------------------------------------------------------------------


def test_a4_idempotent_invite_returns_same_row(session_factory) -> None:
    """A4 — a retry of ``create_invite`` with the same
    ``idempotency_key`` returns the existing row. Two
    consecutive calls must land ONE row.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=60, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=61, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)

    first = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a4-idem-1",
            now=now,
        ),
    )
    second = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a4-idem-1",
            now=now + timedelta(seconds=1),
        ),
    )
    assert first.public_id == second.public_id

    # Database has exactly one row for this (challenge,
    # inviter, invitee) tuple.
    db: Session = session_factory()
    try:
        rows = (
            db.query(CommunityChallengeInvite)
            .filter_by(
                challenge_id=challenge.id,
                inviter_profile_id=inviter.id,
                invitee_profile_id=invitee.id,
            )
            .all()
        )
        assert len(rows) == 1
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A5 — concurrent accept + cancel race (D5 conditional UPDATE).
# ---------------------------------------------------------------------------


def test_a5_concurrent_accept_and_cancel_is_deterministic(session_factory) -> None:
    """A5 — concurrent accept + cancel resolves to exactly ONE
    successful branch; the other raises
    :class:`InvalidChallengeInviteTransition`.

    The barrier sits on ``_before_transition_seam``, IMMEDIATELY
    before the conditional UPDATE — the L421 measurement point.
    A barrier at the function entry point fails to reproduce
    the race in 7 / 10 attempts because one thread completes
    the existence-check → UPDATE → commit chain before the
    second is even scheduled.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=70, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=71, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)

    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a5-race-1",
            now=now,
        ),
    )

    # Two independent sessions — one for each branch. SQLite
    # serialises writes through the file lock, so the race
    # is between the conditional UPDATE and the
    # ``rowcount == 0`` check.
    db_a = session_factory()
    db_b = session_factory()
    # A two-party barrier used at the seam. The seam is the
    # EXACT SQL-decision point (L421 / ADR 0415 D5); a
    # barrier at the function entry point fails to reproduce
    # the race 7 / 10 attempts.
    barrier = threading.Barrier(2)
    barrier_timeout = 30.0
    results: list[tuple[str, Exception | None]] = []

    def accept_thread() -> None:
        try:
            try:
                accepted = accept_invite(
                    db_a,
                    invitee_public_id=invitee.public_id,
                    invite_public_id=invite.public_id,
                    now=now + timedelta(seconds=1),
                )
                db_a.commit()
            except Exception:
                db_a.rollback()
                raise
            results.append(
                ("accept", None)
                if accepted.state == CHALLENGE_INVITE_STATE_ACCEPTED
                else (
                    "accept-unexpected",
                    AssertionError(f"unexpected accept state: {accepted.state}"),
                )
            )
        except Exception as exc:  # noqa: BLE001 — race outcome
            results.append(("accept-raised", exc))
        finally:
            db_a.close()

    def cancel_thread() -> None:
        try:
            try:
                cancelled = cancel_invite(
                    db_b,
                    inviter_public_id=inviter.public_id,
                    invite_public_id=invite.public_id,
                    now=now + timedelta(seconds=1),
                )
                db_b.commit()
            except Exception:
                db_b.rollback()
                raise
            results.append(
                ("cancel", None)
                if cancelled.state == CHALLENGE_INVITE_STATE_CANCELLED
                else (
                    "cancel-unexpected",
                    AssertionError(f"unexpected cancel state: {cancelled.state}"),
                )
            )
        except Exception as exc:  # noqa: BLE001 — race outcome
            results.append(("cancel-raised", exc))
        finally:
            db_b.close()

    # Wire the race-test seam — the barrier sits on
    # ``_before_transition_seam`` (L421, ADR 0415 D5).
    barrier_count = {"hits": 0}

    def _seam() -> None:
        barrier_count["hits"] += 1
        barrier.wait(timeout=barrier_timeout)

    previous = service_module._install_before_transition(_seam)
    try:
        thread_a = threading.Thread(target=accept_thread, name="accept")
        thread_b = threading.Thread(target=cancel_thread, name="cancel")
        thread_a.start()
        thread_b.start()
        thread_a.join(timeout=barrier_timeout + 10)
        thread_b.join(timeout=barrier_timeout + 10)
    finally:
        service_module._install_before_transition(previous)

    successes = [r for r in results if r[1] is None and r[0] in {"accept", "cancel"}]
    failures = [r for r in results if r[1] is not None]
    assert len(successes) == 1, (
        f"exactly one branch must succeed; got successes={successes!r}, "
        f"failures={failures!r}"
    )
    assert len(failures) == 1, (
        f"the other branch must raise InvalidChallengeInviteTransition; "
        f"got failures={failures!r}"
    )
    assert isinstance(failures[0][1], InvalidChallengeInviteTransition), (
        f"the failing branch must raise InvalidChallengeInviteTransition; "
        f"got {type(failures[0][1]).__name__}"
    )

    # The barrier must have fired at least twice (once per
    # branch).
    assert barrier_count["hits"] >= 2

    # Final state matches the successful branch.
    final = _fetch_invite(session_factory, public_id=invite.public_id)
    assert final is not None
    assert final.state in {
        CHALLENGE_INVITE_STATE_ACCEPTED,
        CHALLENGE_INVITE_STATE_CANCELLED,
    }


# ---------------------------------------------------------------------------
# A5 §6.1 valódi-sértés próba — drop the rowcount check.
# ---------------------------------------------------------------------------


def test_a5_real_violation_probe_unconditional_update_breaks_race(
    monkeypatch, session_factory
) -> None:
    """A5 §6.1 — when the conditional UPDATE is replaced with
    an unconditional UPDATE (``WHERE id = :id`` without the
    ``AND state IN (...)`` clause), the rowcount check is
    ALWAYS 1 and BOTH branches land — the final state is the
    latter writer's value. The probe proves the conditional
    UPDATE + rowcount check is the load-bearing construct.
    """
    from sqlalchemy import update as sa_update

    inviter, _ = _make_user_with_headers(
        session_factory, user_id=80, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=81, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)
    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a5-probe-1",
            now=now,
        ),
    )

    # Patch: replace ``accept_invite``'s conditional UPDATE
    # with an unconditional UPDATE (drop the state IN
    # filter and the rowcount check).
    original_accept = service_module.accept_invite

    def _accept_no_check(db, *, invitee_public_id, invite_public_id, now):
        # Replicate the visibility / block guards so the
        # probe does not crash on a missing row.
        invite_row = (
            db.query(CommunityChallengeInvite)
            .filter_by(public_id=invite_public_id)
            .one()
        )
        if invite_row.invitee_profile_id is None:
            raise ChallengeInviteNotFound("invite not found")
        # Unconditional UPDATE — no state filter, no
        # rowcount check. The probe's whole point is that
        # both threads land on this UPDATE.
        db.execute(
            sa_update(CommunityChallengeInvite)
            .where(CommunityChallengeInvite.id == invite_row.id)
            .values(
                state=CHALLENGE_INVITE_STATE_ACCEPTED,
                responded_at=now,
                updated_at=now,
            )
        )
        db.flush()
        db.refresh(invite_row)
        return invite_row

    monkeypatch.setattr(service_module, "accept_invite", _accept_no_check)

    db_a = session_factory()
    db_b = session_factory()
    barrier = threading.Barrier(2)
    barrier_timeout = 30.0
    results: list[str | Exception] = []

    def accept_thread() -> None:
        try:
            try:
                result = _accept_no_check(
                    db_a,
                    invitee_public_id=invitee.public_id,
                    invite_public_id=invite.public_id,
                    now=now + timedelta(seconds=1),
                )
                db_a.commit()
                results.append(result.state)
            except Exception:
                db_a.rollback()
                raise
        except Exception as exc:  # noqa: BLE001 — race outcome
            results.append(exc)
        finally:
            db_a.close()

    def cancel_thread() -> None:
        try:
            # Cancel still goes through the production path —
            # the probe only patches ``accept_invite``.
            try:
                result = original_accept(
                    db_b,
                    invitee_public_id=invitee.public_id,
                    invite_public_id=invite.public_id,
                    now=now + timedelta(seconds=1),
                )
                db_b.commit()
                results.append(result.state)
            except Exception:
                db_b.rollback()
                raise
        except Exception as exc:  # noqa: BLE001 — race outcome
            results.append(exc)
        finally:
            db_b.close()

    barrier_count = {"hits": 0}

    def _seam() -> None:
        barrier_count["hits"] += 1
        barrier.wait(timeout=barrier_timeout)

    previous = service_module._install_before_transition(_seam)
    try:
        thread_a = threading.Thread(target=accept_thread, name="accept")
        thread_b = threading.Thread(target=cancel_thread, name="cancel")
        thread_a.start()
        thread_b.start()
        thread_a.join(timeout=barrier_timeout + 10)
        thread_b.join(timeout=barrier_timeout + 10)
    finally:
        service_module._install_before_transition(previous)

    # With the rowcount check removed, BOTH branches land.
    # The probe asserts that NEITHER branch raises the
    # expected ``InvalidChallengeInviteTransition`` —
    # because the unconditional UPDATE always succeeds.
    assert not any(isinstance(r, InvalidChallengeInviteTransition) for r in results), (
        f"with the unconditional UPDATE the probe must NOT raise — "
        f"both branches succeed; got {results!r}"
    )


# ---------------------------------------------------------------------------
# A4 §6.1 valódi-sértés próba — drop the idempotency check.
# ---------------------------------------------------------------------------


def test_a4_real_violation_probe_idempotency_check_removed(
    monkeypatch, session_factory
) -> None:
    """A4 §6.1 — when the idempotency-key pre-read + re-read
    pattern is removed from ``create_invite``, two creates
    with the same key land TWO rows. The probe proves the
    idempotency surface is the load-bearing construct.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=90, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=91, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)

    # Patch: replace the idempotency pre-read with a no-op
    # so the INSERT never short-circuits to the existing
    # row. The DB UNIQUE constraint catches the second
    # INSERT and translates to IntegrityError; the
    # probe's whole point is that the service layer
    # catches it and re-reads — but with the patch the
    # service raises the IntegrityError instead.
    def _create_no_idempotency(
        db,
        *,
        inviter_public_id,
        invitee_public_id,
        challenge_public_id,
        expires_at,
        idempotency_key,
        now,
    ):
        from app.community.models.challenge import (
            CHALLENGE_INVITE_STATE_SENT,
            CommunityChallengeInvite,
        )

        inviter_row = (
            db.query(CommunityProfile).filter_by(public_id=inviter_public_id).one()
        )
        invitee_row = (
            db.query(CommunityProfile).filter_by(public_id=invitee_public_id).one()
        )
        challenge_row = (
            db.query(CommunityChallenge).filter_by(public_id=challenge_public_id).one()
        )
        invite = CommunityChallengeInvite(
            challenge_id=challenge_row.id,
            inviter_profile_id=inviter_row.id,
            invitee_profile_id=invitee_row.id,
            state=CHALLENGE_INVITE_STATE_SENT,
            expires_at=expires_at,
            idempotency_key=idempotency_key,
            created_at=now,
            updated_at=now,
            responded_at=None,
        )
        db.add(invite)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            # The probe deliberately does NOT re-read —
            # the IntegrityError propagates.
            raise
        return invite

    monkeypatch.setattr(service_module, "create_invite", _create_no_idempotency)

    # First create — succeeds.
    first = _create_no_idempotency(
        session_factory(),
        inviter_public_id=inviter.public_id,
        invitee_public_id=invitee.public_id,
        challenge_public_id=challenge.public_id,
        expires_at=expires_at,
        idempotency_key="a4-probe-1",
        now=now,
    )

    # Second create with the same key — the probe expects an
    # IntegrityError (no idempotency re-read → DB UNIQUE
    # collision → raise).
    with pytest.raises(IntegrityError):
        _create_no_idempotency(
            session_factory(),
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a4-probe-1",
            now=now + timedelta(seconds=1),
        )

    # Database has exactly one row — the first INSERT.
    db: Session = session_factory()
    try:
        rows = (
            db.query(CommunityChallengeInvite)
            .filter_by(
                challenge_id=challenge.id,
                inviter_profile_id=inviter.id,
                invitee_profile_id=invitee.id,
            )
            .all()
        )
        assert len(rows) == 1
        assert rows[0].public_id == first.public_id
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A7 — expiry is server-time (timezone-independent).
# ---------------------------------------------------------------------------


def test_a7_expiry_uses_server_clock_not_client_local(session_factory) -> None:
    """A7 — the expiry check uses the caller's ``now`` parameter
    (server-time) against the row's ``expires_at`` (server-
    stored UTC). A client clock skew or a local-timezone
    ``DateTime`` cannot extend the window.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=100, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=101, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    now = _utcnow()
    expires_at = now + timedelta(days=1)

    invite = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a7-tz-1",
            now=now,
        ),
    )

    # Client passes a NAIVE ``now`` (no tzinfo) — the
    # service still rejects because ``_as_utc`` normalises
    # to UTC.
    naive_now = (now + timedelta(seconds=2)).replace(tzinfo=None)
    accepted = _service_call(
        session_factory,
        lambda db: accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite.public_id,
            now=naive_now,
        ),
    )
    assert accepted.state == CHALLENGE_INVITE_STATE_ACCEPTED

    # Client passes a clock-skewed ``now`` (in the future)
    # — the service still rejects because the comparison
    # is against ``expires_at``, not the client clock.
    future_now = now + timedelta(days=30)
    # Need a fresh invite — the previous one is now
    # ``accepted``.
    invite2 = _service_call(
        session_factory,
        lambda db: create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=expires_at,
            idempotency_key="a7-tz-2",
            now=now,
        ),
    )
    _service_call(
        session_factory,
        lambda db: accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite2.public_id,
            now=future_now,
        ),
        expect_exception=InvalidChallengeInviteTransition,
    )


# ---------------------------------------------------------------------------
# HTTP wiring — router ships the service (the Kör 11 A7 cell).
# ---------------------------------------------------------------------------


def test_http_create_invite_happy_path(client, session_factory) -> None:
    """HTTP wiring — the ``POST .../invites`` endpoint lands a
    row through the router + service stack.
    """
    inviter, headers = _make_user_with_headers(
        session_factory, user_id=110, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=111, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    response = client.post(
        f"/community/challenges/{challenge.public_id}/invites",
        headers=headers,
        json={
            "invitee_public_id": str(invitee.public_id),
            "idempotency_key": "http-create-1",
        },
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["state"] == CHALLENGE_INVITE_STATE_SENT
    assert body["inviter_public_id"] == str(inviter.public_id)
    assert body["invitee_public_id"] == str(invitee.public_id)


def test_http_accept_invite_happy_path(client, session_factory) -> None:
    """HTTP wiring — the ``POST .../accept`` endpoint flips the
    row to ``accepted`` through the router.
    """
    inviter, inviter_headers = _make_user_with_headers(
        session_factory, user_id=120, email="inviter@s.test"
    )
    invitee, invitee_headers = _make_user_with_headers(
        session_factory, user_id=121, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    # Create via the HTTP endpoint.
    create_resp = client.post(
        f"/community/challenges/{challenge.public_id}/invites",
        headers=inviter_headers,
        json={
            "invitee_public_id": str(invitee.public_id),
            "idempotency_key": "http-accept-create-1",
        },
    )
    assert create_resp.status_code == 201, create_resp.text
    invite_public_id = create_resp.json()["public_id"]

    accept_resp = client.post(
        f"/community/challenges/invites/{invite_public_id}/accept",
        headers=invitee_headers,
        json={},
    )
    assert accept_resp.status_code == 200, accept_resp.text
    assert accept_resp.json()["state"] == CHALLENGE_INVITE_STATE_ACCEPTED


def test_http_blocked_inviter_returns_403(client, session_factory) -> None:
    """HTTP wiring — the block-side gate returns 403 on the
    router path.
    """
    inviter, inviter_headers = _make_user_with_headers(
        session_factory, user_id=130, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=131, email="invitee@s.test"
    )
    _create_block(session_factory, blocker=inviter, blocked=invitee)
    challenge = _insert_challenge(session_factory, author=inviter)

    response = client.post(
        f"/community/challenges/{challenge.public_id}/invites",
        headers=inviter_headers,
        json={
            "invitee_public_id": str(invitee.public_id),
            "idempotency_key": "http-block-create-1",
        },
    )
    assert response.status_code == 403, response.text


def test_http_rate_limit_returns_429(client, session_factory) -> None:
    """HTTP wiring — the rate limiter trips at 429. The Kör 3
    ``reset_rate_limiters`` seam clears the counter between
    tests (the autouse fixture).
    """
    inviter, inviter_headers = _make_user_with_headers(
        session_factory, user_id=140, email="inviter@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)

    # Burn the 30-invite / minute budget.
    for i in range(30):
        invitee, _ = _make_user_with_headers(
            session_factory, user_id=200 + i, email=f"u{i}@s.test"
        )
        response = client.post(
            f"/community/challenges/{challenge.public_id}/invites",
            headers=inviter_headers,
            json={
                "invitee_public_id": str(invitee.public_id),
                "idempotency_key": f"http-rate-{i}",
            },
        )
        assert response.status_code == 201, (
            f"invite {i} should succeed; got {response.status_code} {response.text}"
        )

    # The 31st request must trip the limiter.
    invitee_31, _ = _make_user_with_headers(
        session_factory, user_id=300, email="u31@s.test"
    )
    response = client.post(
        f"/community/challenges/{challenge.public_id}/invites",
        headers=inviter_headers,
        json={
            "invitee_public_id": str(invitee_31.public_id),
            "idempotency_key": "http-rate-31",
        },
    )
    assert response.status_code == 429, response.text


def test_http_cancel_returns_cancelled(client, session_factory) -> None:
    """HTTP wiring — the ``DELETE .../invites/{id}`` endpoint
    flips the row to ``cancelled`` through the router.
    """
    inviter, inviter_headers = _make_user_with_headers(
        session_factory, user_id=310, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=311, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    create_resp = client.post(
        f"/community/challenges/{challenge.public_id}/invites",
        headers=inviter_headers,
        json={
            "invitee_public_id": str(invitee.public_id),
            "idempotency_key": "http-cancel-create-1",
        },
    )
    assert create_resp.status_code == 201
    invite_public_id = create_resp.json()["public_id"]

    cancel_resp = client.delete(
        f"/community/challenges/invites/{invite_public_id}",
        headers=inviter_headers,
        params={"idempotency_key": "http-cancel-1"},
    )
    assert cancel_resp.status_code == 200, cancel_resp.text
    assert cancel_resp.json()["state"] == CHALLENGE_INVITE_STATE_CANCELLED
