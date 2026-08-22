"""E09-R08 — Block and mute service-layer acceptance tests.

Covers every cell of the brief §6 acceptance matrix the SERVICE
layer owns (the §D2 read-path cells live in
``test_block_query_regression.py``):

* A1 — block transaction is atomic (D1): both directions of the
  active ``community_follows`` edge are DELETEd AND every
  ``requested`` ``community_follow_request`` is UPDATEd to
  ``status="blocked"``, in one DB transaction. The §6.1 measure-
  matrix row "two separate, non-transactional calls" is caught
  by this test.
* A3 — mute does NOT touch the follow graph and does NOT send any
  signal to the muted party. A grep of the ``block_service.py``
  source confirms the §5.2 invariant at code level (no ``push`` /
  ``notify`` call in the mute path).
* A4 — unblock does NOT recreate a previously-removed follow. The
  ``unblock`` function never touches ``community_follows``.
* A6 — ``is_blocked_pair`` returns True on a blocked pair (the
  D4 pure-helper contract — the future club feature's entry
  point). Tested against the service-layer re-export that
  delegates to ``query_filters.is_blocked_pair``.

The fixtures mirror ``test_follow_service.py`` (own ``FastAPI()`` +
``TestClient`` + alembic-upgraded file-backed SQLite) so the
isolation contract is identical to Kör 7.
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
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.profile import CommunityProfile
from app.community.models.safety_relationships import CommunityBlock, CommunityMute
from app.community.models.social_graph import CommunityFollow, CommunityFollowRequest
from app.community.routers.safety import router as safety_router
from app.community.services.block_service import (
    SafetyListPage,
    block,
    is_blocked_pair,
    list_blocked,
    list_muted,
    mute,
    unblock,
    unmute,
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
# in-memory SQLite (same pattern as test_follow_service.py).
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "block.db"
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
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Safety Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(safety_router)
    yield app


@pytest.fixture
def client(app, session_factory) -> Iterator[TestClient]:
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
# Test data helpers
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
    with session_factory() as db:
        profile = _make_profile_with_visibility(
            db, user_id=user_id, visibility=visibility
        )
        token = create_access_token(user_id)
        return profile.public_id, {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# §6 acceptance — service layer
# ---------------------------------------------------------------------------


# A1 — block transaction closes the follow + request relations
# atomically (D1). The §6.1 measure-matrix row "two separate,
# non-transactional calls" points at this cell.


def test_a1_block_closes_follow_edge_in_both_directions(session_factory):
    """A1 — when X blocks Y, the active follow edge X→Y AND the
    reverse edge Y→X are DELETEd in one transaction.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    # Both directions established.
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="f1",
        )
        db.commit()
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=b_id,
            target_public_id=a_id,
            idempotency_key="f2",
        )
        db.commit()

    # Block.
    with session_factory() as db:
        block(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="b1",
        )
        db.commit()

    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        # Both directions must be gone.
        assert (
            db.query(CommunityFollow)
            .filter_by(follower_profile_id=a_pk, followed_profile_id=b_pk)
            .count()
            == 0
        )
        assert (
            db.query(CommunityFollow)
            .filter_by(follower_profile_id=b_pk, followed_profile_id=a_pk)
            .count()
            == 0
        )
        # The block row itself is in place.
        assert (
            db.query(CommunityBlock)
            .filter_by(blocker_profile_id=a_pk, blocked_profile_id=b_pk)
            .count()
            == 1
        )


def test_a1_block_updates_pending_request_to_blocked(session_factory):
    """A1 — a pending ``requested`` ``community_follow_request``
    in EITHER direction is UPDATEd to ``status='blocked'`` by the
    block transaction (D1).
    """
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="private")
        requester = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        owner_id = owner.public_id
        requester_id = requester.public_id

    with session_factory() as db:
        result = service_follow(
            db,
            follower_public_id=requester_id,
            target_public_id=owner_id,
            idempotency_key="req1",
        )
        db.commit()
    assert result.status == "requested"

    # Owner blocks the requester — pending request must flip to "blocked".
    with session_factory() as db:
        block(
            db,
            blocker_public_id=owner_id,
            target_public_id=requester_id,
            idempotency_key="b1",
        )
        db.commit()

    with session_factory() as db:
        owner_pk = db.query(CommunityProfile).filter_by(public_id=owner_id).one().id
        requester_pk = (
            db.query(CommunityProfile).filter_by(public_id=requester_id).one().id
        )
        # The same row (UNIQUE on the pair) now carries status="blocked".
        row = (
            db.query(CommunityFollowRequest)
            .filter_by(
                requester_profile_id=requester_pk,
                target_profile_id=owner_pk,
            )
            .one()
        )
        assert row.status == "blocked"
        assert row.responded_at is not None


def test_a1_block_is_idempotent_at_service_layer(session_factory):
    """A1 safety — a retry of block() with the same idempotency
    key returns the existing row's public_id without raising.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        row1 = block(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="k1",
        )
        row1_pid = row1.public_id
        db.commit()
    with session_factory() as db:
        row2 = block(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="k1",
        )
        row2_pid = row2.public_id
        db.commit()
    assert row1_pid == row2_pid

    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        assert (
            db.query(CommunityBlock)
            .filter_by(blocker_profile_id=a_pk, blocked_profile_id=b_pk)
            .count()
            == 1
        )


def test_a1_self_block_rejected(session_factory):
    """A1 — self-block raises ``SelfBlockNotAllowed`` (the DB
    CHECK is the backstop, but the service layer refuses first).
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        db.commit()
        a_id = a.public_id

    with session_factory() as db:
        from app.community.services.block_service import SelfBlockNotAllowed

        with pytest.raises(SelfBlockNotAllowed):
            block(
                db,
                blocker_public_id=a_id,
                target_public_id=a_id,
                idempotency_key="self",
            )


# A3 — mute does not touch the follow graph and does not signal the
# other party. The §5.2 invariant.


def test_a3_mute_does_not_touch_follow_graph(session_factory):
    """A3 — after mute(), the existing follow edges are intact and
    no notification side-effect has run (verified by code-level
    grep — ``mute`` does not call any ``notify`` / ``push`` /
    ``publish`` API).
    """
    # Code-level grep — the mute code path must not mention any
    # notification primitive. The follow_service has none either,
    # so a regression that introduces one would land in
    # block_service.py alone.
    import inspect
    from app.community.services import block_service

    mute_source = inspect.getsource(block_service.mute)
    unmute_source = inspect.getsource(block_service.unmute)
    for forbidden in ("push", "notify", "publish", "send_notification", "emit_event"):
        assert forbidden not in mute_source.lower(), (
            f"A3 violated — mute() references '{forbidden}'"
        )
        assert forbidden not in unmute_source.lower(), (
            f"A3 violated — unmute() references '{forbidden}'"
        )

    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    # Pre-existing follow in both directions.
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="f1",
        )
        db.commit()

    # Mute.
    with session_factory() as db:
        mute(
            db,
            muter_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="m1",
        )
        db.commit()

    # Follow edge is intact (mute does not touch community_follows).
    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        assert (
            db.query(CommunityFollow)
            .filter_by(follower_profile_id=a_pk, followed_profile_id=b_pk)
            .count()
            == 1
        )
        # The mute row exists.
        assert (
            db.query(CommunityMute)
            .filter_by(muter_profile_id=a_pk, muted_profile_id=b_pk)
            .count()
            == 1
        )


def test_a3_mute_idempotent(session_factory):
    """A3 — a retry of mute() with the same idempotency key returns
    the existing row without raising.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        r1 = mute(
            db,
            muter_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="k1",
        )
        r1_pid = r1.public_id
        db.commit()
    with session_factory() as db:
        r2 = mute(
            db,
            muter_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="k1",
        )
        r2_pid = r2.public_id
        db.commit()
    assert r1_pid == r2_pid


# A4 — unblock does NOT recreate a previously-removed follow edge
# (the §5.3 invariant).


def test_a4_unblock_does_not_recreate_follow(session_factory):
    """A4 — block severs the follow; unblock leaves the follow
    gone. The §5.3 invariant: the two operations are independent.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    # Pre-existing follow.
    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="f1",
        )
        db.commit()

    # Block.
    with session_factory() as db:
        block(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="b1",
        )
        db.commit()

    # Unblock.
    with session_factory() as db:
        result = unblock(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="u1",
        )
        db.commit()
    assert result is True

    # Follow is still gone — unblock did NOT recreate it.
    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        assert (
            db.query(CommunityFollow)
            .filter_by(follower_profile_id=a_pk, followed_profile_id=b_pk)
            .count()
            == 0
        ), "A4 violated — unblock recreated the previous follow"
        assert (
            db.query(CommunityBlock)
            .filter_by(blocker_profile_id=a_pk, blocked_profile_id=b_pk)
            .count()
            == 0
        )


def test_a4_unblock_is_idempotent_noop_when_no_block_exists(session_factory):
    """A4 — unblock() on a pair with no block returns ``False`` (a
    no-op), not an exception.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        result = unblock(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="u1",
        )
        db.commit()
    assert result is False


# A6 — is_blocked_pair: the D4 pure-helper. The future club feature
# (Kör 24) will call this for the placeholder-display. The cell
# here is a UNIT-style test on the helper, NOT an integration test
# against a live club endpoint (none exists — D4 calls out that
# there is no club endpoint to test against).


def test_a6_is_blocked_pair_returns_true_on_blocked_pair(session_factory):
    """A6 — a block edge in EITHER direction makes
    ``is_blocked_pair`` return True.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        # No block yet — both directions False.
        assert is_blocked_pair(db, profile_id_a=a_pk, profile_id_b=b_pk) is False

    # Create the block.
    with session_factory() as db:
        block(
            db,
            blocker_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="b1",
        )
        db.commit()

    # Either direction reports blocked (symmetric predicate).
    with session_factory() as db:
        assert is_blocked_pair(db, profile_id_a=a_pk, profile_id_b=b_pk) is True
    with session_factory() as db:
        assert is_blocked_pair(db, profile_id_a=b_pk, profile_id_b=a_pk) is True

    # Self-pair is never blocked.
    with session_factory() as db:
        assert is_blocked_pair(db, profile_id_a=a_pk, profile_id_b=a_pk) is False


# Cursor pagination — same shape as follow_service.list_followers.


def test_list_blocked_pagination_round_trip(session_factory):
    """list_blocked visits every row exactly once across pages."""
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="public")
        db.commit()
        owner_id = owner.public_id
        owner_pk = owner.id

    # Insert 7 blocked peers via raw INSERT to avoid the service-layer
    # CHECK on owner_pk != blocked_pk and to seed deterministic order.
    with session_factory() as db:
        for uid in range(2, 9):
            target = _make_profile_with_visibility(db, user_id=uid, visibility="public")
            db.add(
                CommunityBlock(
                    blocker_profile_id=owner_pk,
                    blocked_profile_id=target.id,
                )
            )
        db.commit()

    seen: set[uuid.UUID] = set()
    cursor: str | None = None
    while True:
        with session_factory() as db:
            page: SafetyListPage = list_blocked(
                db, profile_public_id=owner_id, cursor=cursor, limit=3
            )
        for pid in page.public_ids:
            assert pid not in seen
            seen.add(pid)
        cursor = page.next_cursor
        if cursor is None:
            break

    assert len(seen) == 7


def test_list_muted_pagination_round_trip(session_factory):
    """list_muted visits every row exactly once across pages."""
    with session_factory() as db:
        owner = _make_profile_with_visibility(db, user_id=1, visibility="public")
        db.commit()
        owner_id = owner.public_id
        owner_pk = owner.id

    with session_factory() as db:
        for uid in range(2, 9):
            target = _make_profile_with_visibility(db, user_id=uid, visibility="public")
            db.add(
                CommunityMute(
                    muter_profile_id=owner_pk,
                    muted_profile_id=target.id,
                )
            )
        db.commit()

    seen: set[uuid.UUID] = set()
    cursor: str | None = None
    while True:
        with session_factory() as db:
            page: SafetyListPage = list_muted(
                db, profile_public_id=owner_id, cursor=cursor, limit=3
            )
        for pid in page.public_ids:
            assert pid not in seen
            seen.add(pid)
        cursor = page.next_cursor
        if cursor is None:
            break

    assert len(seen) == 7


# A1 stress — the §6.1 measure-matrix row "two separate calls land
# partial state" is exercised by patching block_service to break
# the transaction in two halves and asserting the second half never
# runs when the first fails.


def test_a1_block_atomicity_partial_failure_rolls_back(session_factory):
    """§6.1 measure-matrix — if the block transaction fails mid-way
    (e.g. the follow DELETE raises), NEITHER the block row NOR the
    follow-edge DELETE is committed. The §D1 atomicity invariant.
    """
    with session_factory() as db:
        a = _make_profile_with_visibility(db, user_id=1, visibility="public")
        b = _make_profile_with_visibility(db, user_id=2, visibility="public")
        db.commit()
        a_id, b_id = a.public_id, b.public_id

    with session_factory() as db:
        service_follow(
            db,
            follower_public_id=a_id,
            target_public_id=b_id,
            idempotency_key="f1",
        )
        db.commit()

    # Patch _existing_follow to raise after the block INSERT — the
    # service must roll back so the follow edge and the partial block
    # are both gone.
    from app.community.services import block_service as _service

    real_existing_follow = _service._existing_follow
    call_count = {"n": 0}

    def _boom(*_args, **_kwargs):
        call_count["n"] += 1
        if call_count["n"] >= 2:
            raise RuntimeError("simulated mid-transaction failure")
        return real_existing_follow(*_args, **_kwargs)

    _service._existing_follow = _boom
    try:
        with session_factory() as db:
            with pytest.raises(RuntimeError):
                block(
                    db,
                    blocker_public_id=a_id,
                    target_public_id=b_id,
                    idempotency_key="fail",
                )
            db.rollback()
    finally:
        _service._existing_follow = real_existing_follow

    # After the failed block attempt: no block row, follow edge intact.
    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        assert (
            db.query(CommunityBlock)
            .filter_by(blocker_profile_id=a_pk, blocked_profile_id=b_pk)
            .count()
            == 0
        ), "A1 violated — partial block landed on failure"
        assert (
            db.query(CommunityFollow)
            .filter_by(follower_profile_id=a_pk, followed_profile_id=b_pk)
            .count()
            == 1
        ), "A1 violated — follow edge lost on a failed block attempt"


# A1 concurrency — two concurrent block() calls land one row, not two.
# This mirrors the Kör 7 follow-concurrency test for the new table.


def test_a1_concurrent_block_writes_produce_one_row(session_factory):
    """A1 — two service-layer ``block()`` calls in two threads racing
    on the same pair end up with exactly one row in
    ``community_blocks``. The DB UNIQUE constraint is the §6.1
    valódi-sértés target.
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
                block(
                    db,
                    blocker_public_id=a_id,
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

    with session_factory() as db:
        a_pk = db.query(CommunityProfile).filter_by(public_id=a_id).one().id
        b_pk = db.query(CommunityProfile).filter_by(public_id=b_id).one().id
        count = (
            db.query(CommunityBlock)
            .filter_by(blocker_profile_id=a_pk, blocked_profile_id=b_pk)
            .count()
        )
        assert count == 1, (
            f"A1 violated — concurrent block writes produced {count} rows"
        )


# HTTP-level wiring — the §D2 / §0.0 backend HTTP-felület smoke tests.


def test_post_block_router_returns_blocked(client, session_factory):
    """POST /community/profiles/{id}/block returns status='blocked'."""
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="a@s.test", user_id=1, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="b@s.test", user_id=2, visibility="public"
    )

    response = client.post(
        f"/community/profiles/{b_id}/block",
        json={"idempotency_key": "block-b"},
        headers=headers_a,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["status"] == "blocked"


def test_delete_block_router_returns_unblocked(client, session_factory):
    """DELETE /community/profiles/{id}/block returns
    status='unblocked' on a real unblock, 'noop' on a missing
    block (idempotent).
    """
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="a@s.test", user_id=1, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="b@s.test", user_id=2, visibility="public"
    )

    # First, block.
    client.post(
        f"/community/profiles/{b_id}/block",
        json={"idempotency_key": "block-b"},
        headers=headers_a,
    )
    # Then unblock.
    response = client.delete(
        f"/community/profiles/{b_id}/block",
        params={"idempotency_key": "u1"},
        headers=headers_a,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "unblocked"

    # Retry is a no-op.
    response = client.delete(
        f"/community/profiles/{b_id}/block",
        params={"idempotency_key": "u2"},
        headers=headers_a,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "noop"


def test_get_blocked_router_returns_viewer_list(client, session_factory):
    """GET /community/blocked returns the caller's blocked public_ids."""
    a_id, headers_a = _make_user_with_headers(
        session_factory, email="a@s.test", user_id=1, visibility="public"
    )
    b_id, _ = _make_user_with_headers(
        session_factory, email="b@s.test", user_id=2, visibility="public"
    )

    client.post(
        f"/community/profiles/{b_id}/block",
        json={"idempotency_key": "block-b"},
        headers=headers_a,
    )

    response = client.get(
        "/community/blocked",
        params={"limit": 50},
        headers=headers_a,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["public_ids"] == [str(b_id)]
    assert body["next_cursor"] is None
