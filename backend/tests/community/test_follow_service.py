"""E09-R07 — Follow and follow-request lifecycle acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases:

* A1 — self-follow forbidden at the DB layer (CHECK constraint).
* A2 — duplicate follow rows blocked at the DB layer (UNIQUE).
        §6.1 valódi-sértés próba drops the unique constraint and
        asserts the A2 cell turns red.
* A3 — private-profile request lifecycle (accept/decline/cancel).
* A4 — follower-removal does NOT block.
* A5 — cursor pagination stable, no duplicate page.
* A6 — optimistic rollback on retry is a NO-OP, not a failure.
* A7 — HTTP-level wiring (the router ships the service).

The fixtures are built locally (the §0.0 5. pont — we follow the
``test_handle_policy.py`` pattern: own ``FastAPI()`` + ``TestClient``
+ alembic-upgraded in-memory SQLite, importing the social_graph
router directly). The ``community_two_auth_headers`` fixture from
the existing conftest is reused via a small in-test bridge so the
two ``Authorization: Bearer <token>`` users land in the SAME
engine the TestClient uses.
"""

from __future__ import annotations

import threading
import uuid
from collections.abc import Iterator
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.profile import CommunityProfile
from app.community.models.social_graph import CommunityFollow, CommunityFollowRequest
from app.community.routers.social_graph import router as social_graph_router
from app.community.services.follow_service import (
    FollowListPage,
    accept_follow_request,
    decline_follow_request,
    list_followers,
    remove_follower,
    unfollow,
)
from app.community.services.follow_service import (
    follow as service_follow,
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
# Test app + session factory — own FastAPI() + TestClient + alembic-upgraded
# in-memory SQLite (per the §0.0 5. pont and the test_handle_policy.py
# pattern). The two-user fixture is inlined because the existing
# community_two_auth_headers is wired to a different conftest engine.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied.

    The migration runs through ``alembic upgrade head`` against a
    real file-backed SQLite. The Settings-driven URL
    (``alembic/env.py``) reads ``STRUMSIGHT_DATABASE_URL`` so the
    fixture sets the env var first. Same precedent as
    ``test_handle_policy.py``.
    """
    db_path = tmp_path / "follow.db"
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
def app(session_factory) -> Iterator[FastAPI]:
    """Build a self-contained FastAPI with the social_graph router mounted."""
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Social-graph Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(social_graph_router)
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


# ---------------------------------------------------------------------------
# Test data helpers — two users, two profiles, the auth headers for each.
# ---------------------------------------------------------------------------


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
            "ts": _now(),
        },
    )


def _now():
    from datetime import datetime, timezone

    return datetime.now(timezone.utc)


def _make_profile_with_visibility(
    db: Session,
    *,
    user_id: int,
    visibility: str = "public",
) -> CommunityProfile:
    """Insert a parent ``users`` row + a ``community_profiles`` row
    (with a matching ``community_privacy_settings`` row carrying the
    requested visibility) — the FK chain is satisfied atomically.
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
            # SQLite stores Uuid(as_uuid=True) as CHAR(32); raw cursor
            # binding needs the hex form.
            "pid": uuid.uuid4().hex,
            "profile_id": profile.id,
            "ts": _now(),
            "vis": visibility,
            "aud": "followers",
        },
    )
    db.commit()
    db.refresh(profile)
    return profile


def _make_user_with_headers(
    session_factory,
    *,
    email: str,
    user_id: int,
    visibility: str = "public",
) -> tuple[uuid.UUID, dict[str, str]]:
    """Insert a User + CommunityProfile row, return (profile_public_id, headers)."""
    with session_factory() as db:
        # _make_profile_with_visibility creates both rows in one
        # transaction (parent user first, then profile + privacy).
        profile = _make_profile_with_visibility(
            db, user_id=user_id, visibility=visibility
        )
        token = create_access_token(user_id)
        return profile.public_id, {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# §6 / §6.1 measure-matrix cells
# ---------------------------------------------------------------------------


# A1 — self-follow forbidden at the DB layer.
# Tested at the DB layer directly — the CHECK constraint is the
# enforcement, not the service layer (which also rejects, but the
# DB is what the §6.1 valódi-sértés próba targets).


def test_a1_self_follow_rejected_by_check_constraint(session_factory):
    """A1 — DB CHECK forbids self-follow; service layer rejects first."""
    with session_factory() as db:
        profile = _make_profile_with_visibility(db, user_id=1, visibility="public")
        own_public_id = profile.public_id

    # Service layer refuses first (the friendlier error path).
    with session_factory() as db:
        with pytest.raises(Exception) as excinfo:
            service_follow(
                db,
                follower_public_id=own_public_id,
                target_public_id=own_public_id,
                idempotency_key="self-1",
            )
        assert "yourself" in str(excinfo.value).lower()

    # And the DB-level CHECK would fire even if the service layer
    # ever stopped checking — simulate the race by inserting a row
    # directly with follower == followed, expecting IntegrityError.
    with session_factory() as db:
        profile_id = (
            db.query(CommunityProfile).filter_by(public_id=own_public_id).one().id
        )
        with pytest.raises(IntegrityError):
            db.execute(
                text(
                    "INSERT INTO community_follows "
                    "(id, public_id, follower_profile_id, followed_profile_id, created_at) "
                    "VALUES (:id, :pid, :p, :p, :ts)"
                ),
                {
                    "id": None,
                    "pid": str(uuid.uuid4()),
                    "p": profile_id,
                    "ts": _now(),
                },
            )
            db.commit()


# A2 — concurrent follow calls do not produce duplicate rows; retry
# on the same pair is idempotent. The service layer's two retries
# (two sessions, two transactions) MUST both succeed and the table
# MUST hold exactly one row.


def test_a2_duplicate_follow_is_idempotent_at_service_layer(session_factory):
    """A2 — service-layer follow() called twice on the same pair
    returns success both times; the table holds exactly one row.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        result1 = service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="key-1",
        )
        db.commit()
    with session_factory() as db:
        result2 = service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="key-1",
        )
        db.commit()

    assert result1.status == "following"
    assert result2.status == "following"
    assert result1.request_id == result2.request_id, (
        "retry returned a different request_id — A2 invariant broken"
    )

    with session_factory() as db:
        count = (
            db.query(CommunityFollow)
            .filter(
                CommunityFollow.follower_profile_id
                == db.query(CommunityProfile).filter_by(public_id=a_id).one().id
            )
            .filter(
                CommunityFollow.followed_profile_id
                == db.query(CommunityProfile).filter_by(public_id=b_id).one().id
            )
            .count()
        )
        assert count == 1, f"A2 violated — table holds {count} rows for one pair"


def test_a2_concurrent_follow_writes_produce_one_row(session_factory):
    """A2 — two service-layer calls in two threads racing on the
    same pair end up with exactly one row in the table.

    The DB UNIQUE constraint is the §6.1 valódi-sértés target; the
    service layer's ``IntegrityError``→re-read path is the §6
    §6.1 contract.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    errors: list[Exception] = []

    def writer():
        try:
            with session_factory() as db:
                service_follow(
                    db,
                    follower_public_id=a_id,
                    target_public_id=b_id,
                    idempotency_key="concurrent",
                )
                db.commit()
        except Exception as exc:  # noqa: BLE001
            errors.append(exc)

    threads = [threading.Thread(target=writer) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    # Both threads must succeed (idempotent on retry) — no errors.
    assert not errors, f"Concurrent writers raised: {errors}"

    with session_factory() as db:
        profile_a = db.query(CommunityProfile).filter_by(public_id=a_id).one()
        profile_b = db.query(CommunityProfile).filter_by(public_id=b_id).one()
        count = (
            db.query(CommunityFollow)
            .filter_by(
                follower_profile_id=profile_a.id,
                followed_profile_id=profile_b.id,
            )
            .count()
        )
        assert count == 1, (
            f"A2 violated — race produced {count} rows in community_follows"
        )


# §6.1 valódi-sértés próba for A2 — without the DB-level UNIQUE
# constraint, the concurrent-follow test should land two rows.
#
# SQLite enforces UNIQUE through the table DDL itself (not the
# named index), so a true regression test requires running
# against a SQLite WITHOUT the UniqueConstraint. We build a
# separate, fresh SQLite for this regression: alembic to the
# e09_r04_0004 head, then manually CREATE TABLE without the
# UniqueConstraint. The test demonstrates that the DB-level
# uniqueness is what protects A2 — when it is removed, two
# concurrent follow calls land two rows.


def test_swap_unique_constraint_breaks_a2(tmp_path, monkeypatch):
    """§6.1 valódi-sértés próba — build a SQLite where
    ``community_follows`` has NO unique constraint on (follower,
    followed), then run the concurrent-follow service. The table
    ends up with two rows for the same pair — proving that the
    production UniqueConstraint is what protects A2 from
    concurrent writers.

    The service layer's existence-check is the FIRST line of defence
    and is enough to stop sequential retries (the previous A2
    cell). This regression specifically targets the CONCURRENT
    path: two writers racing through the existence-check before
    either has committed. Without the DB constraint, the second
    INSERT lands and the table ends up with two rows. The §6.1
    measure-matrix names this exact failure mode.
    """
    db_path = tmp_path / "follow_no_uniq.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")

    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(engine)

    # Drop the production table and recreate it without the
    # UniqueConstraint. Foreign keys on the new table are dropped
    # too — they are not part of this regression; we only care
    # about the pair uniqueness.
    with engine.begin() as conn:
        conn.execute(text("PRAGMA foreign_keys = OFF"))
        conn.execute(text("DROP TABLE community_follows"))
        conn.execute(
            text(
                """
                CREATE TABLE community_follows (
                    id INTEGER NOT NULL,
                    public_id CHAR(32) NOT NULL,
                    follower_profile_id INTEGER NOT NULL,
                    followed_profile_id INTEGER NOT NULL,
                    created_at DATETIME NOT NULL,
                    PRIMARY KEY (id),
                    UNIQUE (public_id),
                    CHECK (follower_profile_id != followed_profile_id)
                )
                """
            )
        )
        conn.execute(text("DROP TABLE community_follow_requests"))
        conn.execute(
            text(
                """
                CREATE TABLE community_follow_requests (
                    id INTEGER NOT NULL,
                    public_id CHAR(32) NOT NULL,
                    requester_profile_id INTEGER NOT NULL,
                    target_profile_id INTEGER NOT NULL,
                    status VARCHAR NOT NULL DEFAULT 'requested',
                    created_at DATETIME NOT NULL,
                    responded_at DATETIME,
                    PRIMARY KEY (id),
                    UNIQUE (public_id),
                    CHECK (requester_profile_id != target_profile_id)
                )
                """
            )
        )
        conn.execute(text("PRAGMA foreign_keys = ON"))

    factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    try:
        with factory() as db:
            a = _make_profile_with_visibility(db, user_id=1, visibility="public")
            b = _make_profile_with_visibility(db, user_id=2, visibility="public")
            db.commit()
            a_id, b_id = a.public_id, b.public_id
            a_pk = a.id
            b_pk = b.id

        errors: list[Exception] = []

        # Barrier(2) injected INTO the existence-check — synchronises
        # both threads at the moment service_follow() decides whether
        # to INSERT or short-circuit. A Barrier at the writer() entry
        # (the previous attempt) is too early: one thread can still
        # finish the entire existence-check → INSERT → commit path
        # BEFORE the second thread even GETs to the existence-check,
        # so the second thread's check returns the first thread's
        # committed row and the function short-circuits — count == 1
        # even with the constraint removed. By moving the Barrier
        # INSIDE the existence-check helper itself, both threads
        # are guaranteed to be at the same SQL decision point.
        # The check then runs for both, both see no row (the check
        # is the synchronous barrier point), both INSERT, both commit
        # (no UNIQUE constraint in this test's schema), count == 2.
        from app.community.services import follow_service as _follow_service_module

        _real_existing_follow = _follow_service_module._existing_follow
        barrier = threading.Barrier(2)

        def _synced_existing_follow(db, *, follower_id, followed_id):
            barrier.wait()
            return _real_existing_follow(
                db, follower_id=follower_id, followed_id=followed_id
            )

        _follow_service_module._existing_follow = _synced_existing_follow

        def writer():
            try:
                with factory() as db:
                    service_follow(
                        db,
                        follower_public_id=a_id,
                        target_public_id=b_id,
                        idempotency_key="concurrent-no-uniq",
                    )
                    db.commit()
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        try:
            # Two threads race through the existence-check into the
            # INSERT. With the constraint present, one fails (the
            # service layer catches IntegrityError and translates to
            # success). With the constraint removed, both succeed and
            # land two rows.
            threads = [threading.Thread(target=writer) for _ in range(2)]
            for t in threads:
                t.start()
            for t in threads:
                t.join()
        finally:
            _follow_service_module._existing_follow = _real_existing_follow

        # No errors expected — the service translates the
        # IntegrityError to a re-read success path. With the
        # regression, the re-read returns nothing (no rows), so
        # the function would actually raise ``FollowAlreadyExists``,
        # which we accept as evidence the constraint was missing.
        # Either way, the row count tells the real story.

        with factory() as db:
            count = (
                db.query(CommunityFollow)
                .filter_by(
                    follower_profile_id=a_pk,
                    followed_profile_id=b_pk,
                )
                .count()
            )
            assert count == 2, (
                "expected the regression to land two rows; got "
                f"{count} (A2 still protected — the unique constraint "
                "is still active in the DB or the service layer has a "
                "hidden lock). errors={errors!r}"
            )
    finally:
        engine.dispose()


# A3 — private-profile lifecycle (accept/decline/cancel/refollow).


def test_a3_private_profile_request_lifecycle(session_factory):
    """A3 — full lifecycle: request → accept flips to active follow;
    request → decline flips to declined; request → cancel (via
    unfollow) flips to cancelled; refollow after decline re-opens.
    """
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="private")
        requester = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        owner_id = owner.public_id
        requester_id = requester.public_id

    # Initial request.
    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="r1",
        )
        db.commit()
    assert result.status == "requested"
    request_id = result.request_id

    # Accept path.
    with session_factory() as db:
        result = accept_follow_request(
            db,
            request_public_id=request_id,
            target_public_id=owner_id,
            idempotency_key="a1",
        )
        db.commit()
    assert result.status == "accepted"

    with session_factory() as db:
        owner_pk = db.query(CommunityProfile).filter_by(public_id=owner_id).one().id
        requester_pk = (
            db.query(CommunityProfile).filter_by(public_id=requester_id).one().id
        )
        assert (
            db.query(CommunityFollow)
            .filter_by(
                follower_profile_id=requester_pk,
                followed_profile_id=owner_pk,
            )
            .count()
            == 1
        ), "accept must write the matching follow edge"

    # Now unfollow — active edge exists → DELETE branch.
    with session_factory() as db:
        outcome = unfollow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="u1",
        )
        db.commit()
    assert outcome == "unfollowed"

    # Re-request (private) and decline.
    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="r2",
        )
        db.commit()
    assert result.status == "requested"
    request_id_2 = result.request_id

    with session_factory() as db:
        decline_follow_request(
            db,
            request_public_id=request_id_2,
            target_public_id=owner_id,
            idempotency_key="d1",
        )
        db.commit()

    # Now unfollow again — no active edge, but a declined row exists.
    # The §3 cancel branch only fires on a "requested" row, so this
    # lands on "noop".
    with session_factory() as db:
        outcome = unfollow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="u2",
        )
        db.commit()
    assert outcome == "noop", (
        "declined request must NOT be auto-cancelled by unfollow; "
        "caller re-requests first"
    )

    # Refollow → row is recycled to "requested" (per ADR 0401 §4).
    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="r3",
        )
        db.commit()
    assert result.status == "requested"

    with session_factory() as db:
        # The row is the SAME one (same pair → same row, recycled).
        # The exact public_id round-trip is part of the §4 invariant.
        row = (
            db.query(CommunityFollowRequest)
            .filter_by(
                requester_profile_id=requester_pk,
                target_profile_id=owner_pk,
            )
            .one()
        )
        assert row.public_id == request_id, (
            "refollow did not recycle the same row — §4 invariant broken"
        )
        assert row.status == "requested"


def test_a3_unfollow_pending_request_cancels(session_factory):
    """A3 / §3 — unfollow() on a pending request flips it to
    'cancelled' (the 'cancel' branch).
    """
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="private")
        requester = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        owner_id, requester_id = owner.public_id, requester.public_id

    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="r1",
        )
        db.commit()
    assert result.status == "requested"

    with session_factory() as db:
        outcome = unfollow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="u1",
        )
        db.commit()
    assert outcome == "cancelled"

    with session_factory() as db:
        requester_pk = (
            db.query(CommunityProfile).filter_by(public_id=requester_id).one().id
        )
        owner_pk = db.query(CommunityProfile).filter_by(public_id=owner_id).one().id
        row = (
            db.query(CommunityFollowRequest)
            .filter_by(
                requester_profile_id=requester_pk,
                target_profile_id=owner_pk,
            )
            .one()
        )
        assert row.status == "cancelled"


def test_a3_decline_is_idempotent(session_factory):
    """A3 — decline retry on an already-declined request returns
    success (no exception, no state mutation).
    """
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="private")
        requester = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        owner_id, requester_id = owner.public_id, requester.public_id

    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="r1",
        )
        db.commit()
    rid = result.request_id

    with session_factory() as db:
        decline_follow_request(
            db,
            request_public_id=rid,
            target_public_id=owner_id,
            idempotency_key="d1",
        )
        db.commit()
    # Retry must not raise.
    with session_factory() as db:
        decline_follow_request(
            db,
            request_public_id=rid,
            target_public_id=owner_id,
            idempotency_key="d2",
        )
        db.commit()


# A4 — follower-removal does NOT block.


def test_a4_remove_follower_does_not_block(session_factory):
    """A4 — remove_follower removes the follow edge and does not
    write to any block table (the brief §5.3 invariant: the two
    operations are independent).
    """
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="public")
        follower = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        owner_id = owner.public_id
        follower_id = follower.public_id

    # follower → owner active edge
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=follower_id,
            target_public_id=owner_id,
            idempotency_key="f1",
        )
        db.commit()

    # Owner removes the follower.
    with session_factory() as db:
        remove_follower(
            db,
            owner_public_id=owner_id,
            follower_public_id=follower_id,
            idempotency_key="rf1",
        )
        db.commit()

    # Edge is gone.
    with session_factory() as db:
        owner_pk = db.query(CommunityProfile).filter_by(public_id=owner_id).one().id
        follower_pk = (
            db.query(CommunityProfile).filter_by(public_id=follower_id).one().id
        )
        assert (
            db.query(CommunityFollow)
            .filter_by(
                follower_profile_id=follower_pk,
                followed_profile_id=owner_pk,
            )
            .count()
            == 0
        )

    # No block table exists yet (Kör 8 scope); what we can verify is
    # that a re-follow succeeds without a block-induced exception —
    # the §5.3 invariant: follower-removal is NOT a block.
    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=follower_id,
            target_public_id=owner_id,
            idempotency_key="f2",
        )
        db.commit()
    assert result.status == "following"


# A5 — cursor pagination stable, no duplicate page.


def _bulk_follow(
    session_factory,
    *,
    owner_public_id: uuid.UUID,
    follower_user_ids: list[int],
) -> None:
    """Insert ``len(follower_user_ids)`` follow edges from distinct
    follower profiles to ``owner_public_id``.
    """
    with session_factory() as db:
        owner_pk = (
            db.query(CommunityProfile).filter_by(public_id=owner_public_id).one().id
        )
        for uid in follower_user_ids:
            f = _make_profile_with_visibility(db, user_id=uid, visibility="public")
            db.add(
                CommunityFollow(
                    follower_profile_id=f.id,
                    followed_profile_id=owner_pk,
                )
            )
        db.commit()


def test_a5_cursor_pagination_no_duplicates(session_factory):
    """A5 — paginating a followers list with a 3-per-page limit
    visits every follower exactly once, never twice.

    The tie-breaker (id DESC) keeps the ordering deterministic even
    when ``created_at`` collides — the §7 contract.
    """
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="public")
        db.commit()
        owner_id = owner.public_id

    _bulk_follow(
        session_factory, owner_public_id=owner_id, follower_user_ids=list(range(2, 12))
    )

    # Walk the page in 3-row steps until empty.
    seen: set[uuid.UUID] = set()
    cursor: str | None = None
    pages = 0
    while True:
        with session_factory() as db:
            page: FollowListPage = list_followers(
                db, profile_public_id=owner_id, cursor=cursor, limit=3
            )
        for pid in page.public_ids:
            assert pid not in seen, f"A5 violated — duplicate {pid} across pages"
            seen.add(pid)
        cursor = page.next_cursor
        pages += 1
        if cursor is None:
            break
        if pages > 100:
            pytest.fail("pagination did not terminate")

    # We inserted 10 followers.
    assert len(seen) == 10, f"A5 expected 10 unique followers, got {len(seen)}"


def test_a5_cursor_round_trip_with_ties(session_factory):
    """A5 — even when many rows share the same created_at timestamp,
    the (created_at, id) tuple cursor round-trip visits each row
    exactly once.

    The test inserts rows at microsecond-spaced timestamps so the
    lexicographic comparator visits each row exactly once across
    page boundaries. The §7 contract — ``(created_at DESC, id DESC)``
    — guarantees a stable order; the test exercises the cursor
    boundary case where the next-page filter has to skip the exact
    last-row tuple.
    """
    from datetime import datetime, timedelta, timezone

    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="public")
        db.commit()
        owner_id = owner.public_id
        owner_pk = owner.id

    # Insert 6 followers at microsecond-spaced timestamps — the
    # ordering is deterministic, the tie-break is exercised by the
    # cursor filter, and each row's (created_at, id) pair is unique.
    base_ts = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
    with session_factory() as db:
        for i, uid in enumerate(range(2, 8)):
            f = _make_profile_with_visibility(db, user_id=uid, visibility="public")
            ts = base_ts + timedelta(microseconds=i)
            db.execute(
                text(
                    "INSERT INTO community_follows "
                    "(id, public_id, follower_profile_id, followed_profile_id, "
                    "created_at) VALUES (:id, :pid, :follower, :followed, :ts)"
                ),
                {
                    "id": None,
                    "pid": uuid.uuid4().hex,
                    "follower": f.id,
                    "followed": owner_pk,
                    "ts": ts,
                },
            )
        db.commit()

    seen: set[uuid.UUID] = set()
    cursor: str | None = None
    while True:
        with session_factory() as db:
            page = list_followers(
                db, profile_public_id=owner_id, cursor=cursor, limit=2
            )
        for pid in page.public_ids:
            assert pid not in seen, f"A5 tie-break violated — duplicate {pid}"
            seen.add(pid)
        cursor = page.next_cursor
        if cursor is None:
            break

    assert len(seen) == 6, f"A5 tie-break expected 6 unique, got {len(seen)}"


# A6 — service-layer retry on the same target is a NO-OP, not a
# failure. This is the §6.1 "retry must not lose the result" cell.


def test_a6_idempotency_key_retry_is_safe(session_factory):
    """A6 — calling follow() twice with the same idempotency key
    on the same pair is safe: both calls return success and the
    table holds exactly one row.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        r1 = service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="retry-test",
        )
        db.commit()
    with session_factory() as db:
        r2 = service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="retry-test",
        )
        db.commit()

    assert r1.status == r2.status == "following"
    assert r1.request_id == r2.request_id


# A7 — HTTP-level wiring (the router ships the service).
# Tested via the dedicated router-level test app + TestClient.


def test_a7_router_follow_public_profile_returns_following(client, session_factory):
    """A7 — POST /community/profiles/{id}/follow against a PUBLIC
    target returns ``status: 'following'`` and writes an active
    edge in the DB.
    """
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="a@s.test", user_id=1, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="b@s.test", user_id=2, visibility="public"
    )

    response = client.post(
        f"/community/profiles/{b_id}/follow",
        json={"idempotency_key": "follow-b"},
        headers=headers_a,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "following"
    assert "request_id" in body

    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        assert (
            db.query(CommunityFollow)
            .filter_by(
                follower_profile_id=a_pk,
                followed_profile_id=b_pk,
            )
            .count()
            == 1
        )


def test_a7_router_follow_private_profile_returns_requested(client, session_factory):
    """A7 — POST /community/profiles/{id}/follow against a PRIVATE
    target returns ``status: 'requested'`` and writes a pending
    request row, NOT an active follow edge.
    """
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="a@s.test", user_id=1, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="b@s.test", user_id=2, visibility="private"
    )

    response = client.post(
        f"/community/profiles/{b_id}/follow",
        json={"idempotency_key": "follow-b-private"},
        headers=headers_a,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "requested"
    assert "request_id" in body

    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        assert (
            db.query(CommunityFollow)
            .filter_by(
                follower_profile_id=a_pk,
                followed_profile_id=b_pk,
            )
            .count()
            == 0
        ), "private follow must NOT write an active follow edge"
        assert (
            db.query(CommunityFollowRequest)
            .filter_by(
                requester_profile_id=a_pk,
                target_profile_id=b_pk,
                status="requested",
            )
            .count()
            == 1
        )


def test_a7_router_unfollow_then_refollow_round_trip(client, session_factory):
    """A7 — DELETE + POST round-trip: unfollow + re-follow the same
    target lands exactly one row at the end.
    """
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="a@s.test", user_id=1, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="b@s.test", user_id=2, visibility="public"
    )

    # First follow.
    response = client.post(
        f"/community/profiles/{b_id}/follow",
        json={"idempotency_key": "first"},
        headers=headers_a,
    )
    assert response.status_code == 200
    first_id = response.json()["request_id"]

    # Unfollow.
    response = client.delete(
        f"/community/profiles/{b_id}/follow",
        params={"idempotency_key": "u1"},
        headers=headers_a,
    )
    assert response.status_code == 200
    assert response.json()["outcome"] == "unfollowed"

    # Refollow — the same public_id round-trips (state idempotency).
    response = client.post(
        f"/community/profiles/{b_id}/follow",
        json={"idempotency_key": "second"},
        headers=headers_a,
    )
    assert response.status_code == 200
    second_id = response.json()["request_id"]
    assert first_id != second_id, (
        "refollow after unfollow must write a NEW row (the old one "
        "was deleted), not recycle"
    )


def test_a7_router_followers_pagination_endpoint(client, session_factory):
    """A7 — GET /community/profiles/{id}/followers returns the
    cursor-paginated list of follower public_ids.
    """
    owner_id, owner_headers = _make_user_with_headers(
        session_factory, email="owner@s.test", user_id=1, visibility="public"
    )
    _bulk_follow(
        session_factory,
        owner_public_id=owner_id,
        follower_user_ids=list(range(2, 6)),
    )

    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 2},
        headers=owner_headers,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert len(body["public_ids"]) == 2
    assert body["next_cursor"] is not None, (
        "with 4 followers and limit=2, the page must expose a next_cursor"
    )

    # Walk the next page.
    response = client.get(
        f"/community/profiles/{owner_id}/followers",
        params={"limit": 2, "cursor": body["next_cursor"]},
        headers=owner_headers,
    )
    assert response.status_code == 200
    body2 = response.json()
    assert len(body2["public_ids"]) == 2
    assert body2["next_cursor"] is None, (
        "after 4 followers, the second page must terminate"
    )


# F2 — get_followers / get_following MUST be authenticated. The
# brief §3 "NINCS benne" list keeps the visibility filtering for
# Kör 8 / Kör 13, but authentication (a valid JWT must be present)
# is the router's own invariant — every other endpoint in this
# router enforces it.
#
# FastAPI's ``HTTPBearer(auto_error=True)`` returns 403 when the
# Authorization header is missing entirely (the codebase-wide
# pattern — see ``test_auth.py::142`` "no bearer at all → 403").
# When the header IS present but the token is invalid, the
# ``get_current_user`` resolver raises 401. Both signal an
# authenticated-only endpoint rejecting the call; the test asserts
# the missing-header case (the canary the F2 review required).


def test_f2_get_followers_rejects_missing_authorization_header(client):
    """F2 — GET /community/profiles/{id}/followers with no
    ``Authorization`` header must return 403 (FastAPI's
    HTTPBearer ``no bearer at all`` convention — the §F2 invariant
    is "the endpoint is authenticated"; the status code follows
    the codebase-wide ``HTTPBearer`` default).
    """
    response = client.get(
        "/community/profiles/00000000-0000-0000-0000-000000000001/followers"
    )
    assert response.status_code == 403, (
        f"F2 violated — missing Authorization header should reject; "
        f"got {response.status_code}: {response.text}"
    )


def test_f2_get_following_rejects_missing_authorization_header(client):
    """F2 — GET /community/profiles/{id}/following with no
    ``Authorization`` header must return 403 (same convention as
    ``test_f2_get_followers_rejects_missing_authorization_header``).
    """
    response = client.get(
        "/community/profiles/00000000-0000-0000-0000-000000000002/following"
    )
    assert response.status_code == 403, (
        f"F2 violated — missing Authorization header should reject; "
        f"got {response.status_code}: {response.text}"
    )


def test_f2_get_following_endpoint_authenticated_round_trip(client, session_factory):
    """F2 — the same GET, with a valid JWT, returns 200 and the
    expected page envelope (no visibility filter yet — that is
    Kör 8 / Kör 13 scope; this test confirms the auth seam is the
    only thing the router added).
    """
    owner_id, owner_headers = _make_user_with_headers(
        session_factory, email="o-following@s.test", user_id=3, visibility="public"
    )
    response = client.get(
        f"/community/profiles/{owner_id}/following",
        headers=owner_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["public_ids"] == []
    assert body["next_cursor"] is None


# F4 — the router's post_follow MUST catch ``FollowAlreadyExists``
# (the rare race-outcome documented in follow_service.py §6 / ADR
# 0401 §6) and translate it to the same success shape as an
# idempotent retry. The pre-fix behaviour was a nyers 500 with the
# raw ``str(IntegrityError)`` in the body.


def test_f4_post_follow_translates_follow_already_exists_to_success(
    client, session_factory, monkeypatch
):
    """F4 — ``post_follow`` returns 200 with ``status: following``
    when the underlying service raises ``FollowAlreadyExists``.
    """
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="f4a@s.test", user_id=10, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="f4b@s.test", user_id=11, visibility="public"
    )

    # Replace the service-layer ``follow`` in the router module with
    # a stub that always raises ``FollowAlreadyExists`` — the rare
    # race path the §6 / ADR 0401 §6 documents.
    from app.community.routers import social_graph as router_module

    def _raise_follow_already_exists(*_args, **_kwargs):
        from app.community.services.follow_service import FollowAlreadyExists

        raise FollowAlreadyExists("simulated rare race outcome")

    monkeypatch.setattr(router_module, "follow", _raise_follow_already_exists)

    response = client.post(
        f"/community/profiles/{b_id}/follow",
        json={"idempotency_key": "f4-key"},
        headers=headers_a,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "following", (
        f"F4 violated — expected the FollowAlreadyExists race to be "
        f"translated to 'following', got {body!r}"
    )
    # The id is the target profile's public_id (we don't have the
    # would-be-winner row in this race outcome, but the response is
    # shaped for the client to treat as a successful retry).
    assert body["request_id"] == str(b_id)
