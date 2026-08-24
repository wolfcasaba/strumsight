"""E09-R23 — Leaderboard service + opt-in acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases:

* A1 — only verified results land in the projection; the §6.1
  valódi-sértés próba drops the WHERE filter and asserts the
  test turns red.
* A2 — deterministic tie-breaker ``(metric_value DESC,
  submitted_at ASC, id ASC)``; L109-style many-permutations
  probe.
* A3 — opt-out profile (no ``community_leaderboard_opt_ins``
  row) is excluded.
* A4 — ``type='friends'`` projection is filtered to the viewer's
  ``community_follows`` graph; non-friends types have no
  follow-graph filter.
* A5 — multi-page cursor pagination is stable, no duplicate
  rows, last page returns ``next_cursor=None``.
* A6 — disqualification/delete (DB-mutation) leaves the
  projection deterministic on the next read (the §D5
  test-szintű DB-mutáció surface).

The fixtures follow the E09-R22 test_challenge_verification.py
pattern — own ``FastAPI()`` + ``TestClient`` + alembic-upgraded
in-memory SQLite, importing the leaderboard service + router
directly.

The §6.1 valódi-sértés próba is exercised explicitly:

* **A1 probe** swaps the service's WHERE clause to remove
  ``verification_state='verified'`` and asserts that an
  injected ``pending`` row would land in the projection. The
  probe verifies the test cell would FAIL without the WHERE
  filter — that is, the filter is load-bearing, not dead.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.challenge import (
    CHALLENGE_TYPE_FRIENDS,
    CommunityChallenge,
    CommunityChallengeParticipant,
)
from app.community.models.challenge_result import (
    CHALLENGE_RESULT_STATE_PENDING,
    CHALLENGE_RESULT_STATE_REJECTED,
    CHALLENGE_RESULT_STATE_VERIFIED,
    CommunityChallengeResult,
)
from app.community.models.leaderboard import CommunityLeaderboardOptIn
from app.community.models.profile import CommunityProfile
from app.community.models.social_graph import CommunityFollow
from app.community.routers.leaderboards import router as leaderboards_router
from app.community.services import leaderboard_service as service_module
from app.community.services.challenge_invite_service import (
    accept_invite,
    create_invite,
)
from app.community.services.leaderboard_service import (
    get_leaderboard_page,
    get_own_rank,
    rebuild_leaderboard,
    set_opt_in,
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
# Fixtures — engine + session factory + app + client (the Kör 22 pattern).
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied."""
    db_path = tmp_path / "leaderboard.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")
    engine = create_engine(
        db_url,
        connect_args={"check_same_thread": False},
    )
    enable_sqlite_foreign_keys(engine)
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
    """Self-contained FastAPI with the leaderboards router mounted."""
    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Leaderboard Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(leaderboards_router)
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
# Data helpers — users, profiles, challenges, invites, participants,
# opt-ins, follows, verified results.
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
    display_name: str | None = None,
    handle: str | None = None,
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
            "ts": _utcnow(),
            "vis": "public",
            "aud": "public",
        },
    )
    if handle is not None:
        db.execute(
            text(
                "UPDATE community_profiles SET display_name = :dn, handle = :h "
                "WHERE id = :pid"
            ),
            {"dn": display_name, "h": handle, "pid": profile.id},
        )
    elif display_name is not None:
        db.execute(
            text(
                "UPDATE community_profiles SET display_name = :dn WHERE id = :pid"
            ),
            {"dn": display_name, "pid": profile.id},
        )
    db.commit()
    db.refresh(profile)
    return profile


def _make_user_with_headers(
    session_factory,
    *,
    user_id: int,
    email: str,
    display_name: str | None = None,
    handle: str | None = None,
) -> tuple[CommunityProfile, dict[str, str]]:
    db: Session = session_factory()
    try:
        profile = _make_profile(
            db,
            user_id=user_id,
            display_name=display_name,
            handle=handle,
        )
    finally:
        db.close()
    token = create_access_token(user_id)
    return profile, {"Authorization": f"Bearer {token}"}


def _insert_challenge(
    session_factory,
    *,
    author: CommunityProfile,
    challenge_type: str = CHALLENGE_TYPE_FRIENDS,
    metric: str = "score",
    version: int = 1,
    starts_at: datetime | None = None,
    ends_at: datetime | None = None,
) -> CommunityChallenge:
    now = _utcnow()
    start = starts_at if starts_at is not None else now
    end = ends_at if ends_at is not None else now + timedelta(days=7)
    challenge = CommunityChallenge(
        author_profile_id=author.id,
        type=challenge_type,
        metric=metric,
        difficulty=1,
        starts_at=start,
        ends_at=end,
        version=version,
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


def _create_participant(
    session_factory,
    *,
    challenge: CommunityChallenge,
    participant: CommunityProfile,
) -> CommunityChallengeParticipant:
    """Insert a participant row directly."""
    db: Session = session_factory()
    try:
        row = CommunityChallengeParticipant(
            challenge_id=challenge.id,
            participant_profile_id=participant.id,
            best_metric_value=None,
            joined_at=_utcnow(),
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return row
    finally:
        db.close()


def _accept_invite_via_invite_service(
    session_factory,
    *,
    challenge: CommunityChallenge,
    inviter: CommunityProfile,
    invitee: CommunityProfile,
    now: datetime | None = None,
) -> None:
    """Run ``create_invite + accept_invite`` so the test has a
    participant row (the Kör 22 helper)."""
    _now = now if now is not None else _utcnow()
    db: Session = session_factory()
    try:
        invite = create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=_now + timedelta(days=1),
            idempotency_key=f"r23-accept-{uuid.uuid4().hex}",
            now=_now,
        )
        db.commit()
        invite_public_id = invite.public_id
    finally:
        db.close()

    db = session_factory()
    try:
        accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite_public_id,
            now=_now + timedelta(seconds=1),
        )
        db.commit()
    finally:
        db.close()


def _set_opt_in(
    session_factory,
    *,
    profile: CommunityProfile,
) -> None:
    """Insert the ``community_leaderboard_opt_ins`` row directly
    (bypassing the service so we can drive the test setup without
    double-commit / fixture drift)."""
    db: Session = session_factory()
    try:
        db.add(
            CommunityLeaderboardOptIn(
                profile_id=profile.id,
                opted_in_at=_utcnow(),
            )
        )
        db.commit()
    finally:
        db.close()


def _create_follow_edge(
    session_factory,
    *,
    follower: CommunityProfile,
    followed: CommunityProfile,
) -> None:
    """Insert an active follow edge directly."""
    db: Session = session_factory()
    try:
        edge = CommunityFollow(
            follower_profile_id=follower.id,
            followed_profile_id=followed.id,
        )
        db.add(edge)
        db.commit()
    finally:
        db.close()


def _insert_verified_result(
    session_factory,
    *,
    participant: CommunityChallengeParticipant,
    metric_value: int,
    source_event_id: str,
    submitted_at: datetime | None = None,
    verification_state: str = CHALLENGE_RESULT_STATE_VERIFIED,
) -> CommunityChallengeResult:
    """Insert a ``CommunityChallengeResult`` row directly with a
    chosen ``verification_state`` and ``submitted_at``.

    Used to bypass the Kör 22 service layer (which is tilos zóna
    for this round) and to give the leaderboard service an
    arbitrary starting state.
    """
    db: Session = session_factory()
    try:
        row = CommunityChallengeResult(
            participant_id=participant.id,
            source_event_id=source_event_id,
            idempotency_key=f"r23-{source_event_id}",
            metric_value=metric_value,
            verification_state=verification_state,
            reason_code=None
            if verification_state == CHALLENGE_RESULT_STATE_VERIFIED
            else "test_synthesised",
            nonce=uuid.uuid4(),
            nonce_expires_at=_utcnow() + timedelta(days=30),
            submitted_at=submitted_at if submitted_at is not None else _utcnow(),
            decided_at=_utcnow()
            if verification_state
            in {
                CHALLENGE_RESULT_STATE_VERIFIED,
                CHALLENGE_RESULT_STATE_REJECTED,
            }
            else None,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return row
    finally:
        db.close()


def _service_call(session_factory, fn):
    """Run a service-layer function inside a single session and COMMIT."""
    db: Session = session_factory()
    try:
        result = fn(db)
        db.commit()
        return result
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A1 — verified-only projection (D2 / §5.1).
# ---------------------------------------------------------------------------


def test_a1_only_verified_results_appear(session_factory) -> None:
    """A1 — ``pending`` / ``unverified`` / ``rejected`` rows are
    EXCLUDED from the leaderboard. Only ``verified`` rows land.
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=1, email="author@s.test"
    )
    p_verified, _ = _make_user_with_headers(
        session_factory,
        user_id=2,
        email="p-verified@s.test",
        display_name="Verified Player",
        handle="verified_player",
    )
    p_pending, _ = _make_user_with_headers(
        session_factory, user_id=3, email="p-pending@s.test"
    )
    p_rejected, _ = _make_user_with_headers(
        session_factory, user_id=4, email="p-rejected@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p_verified_row = _create_participant(
        session_factory, challenge=challenge, participant=p_verified
    )
    p_pending_row = _create_participant(
        session_factory, challenge=challenge, participant=p_pending
    )
    p_rejected_row = _create_participant(
        session_factory, challenge=challenge, participant=p_rejected
    )
    _set_opt_in(session_factory, profile=p_verified)
    _set_opt_in(session_factory, profile=p_pending)
    _set_opt_in(session_factory, profile=p_rejected)
    _insert_verified_result(
        session_factory,
        participant=p_verified_row,
        metric_value=500,
        source_event_id="evt-a1-verified",
    )
    _insert_verified_result(
        session_factory,
        participant=p_pending_row,
        metric_value=999,
        source_event_id="evt-a1-pending",
        verification_state=CHALLENGE_RESULT_STATE_PENDING,
    )
    _insert_verified_result(
        session_factory,
        participant=p_rejected_row,
        metric_value=750,
        source_event_id="evt-a1-rejected",
        verification_state=CHALLENGE_RESULT_STATE_REJECTED,
    )

    page = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    public_ids = [entry.public_id for entry in page.entries]
    assert public_ids == [p_verified.public_id]


def test_a1_probe_drops_verified_filter_pending_row_would_appear(
    session_factory,
) -> None:
    """A1 valódi-sértés próba — when the WHERE filter on
    ``verification_state='verified'`` is dropped (the §6.1
    measure-matrix probe), a ``pending`` row MUST land in the
    projection. This proves the filter is load-bearing — the
    test cell is real, not vacuously green.
    """
    from app.community.services import leaderboard_service as svc

    original_build = svc._build_base_query

    def patched_build(*, challenge_id, viewer_profile_internal_id, friends_scope):
        stmt = original_build(
            challenge_id=challenge_id,
            viewer_profile_internal_id=viewer_profile_internal_id,
            friends_scope=friends_scope,
        )
        # Drop the verified-only filter (the §6.1 measure-matrix
        # probe). The probe only succeeds — proving the filter is
        # load-bearing — when the ``pending`` row WOULD land in
        # the projection.
        from sqlalchemy import and_

        new_conditions = []
        for clause in stmt.whereclause.clauses:
            if isinstance(clause, and_):
                # Drop the verification_state clause.
                clauses = [
                    c for c in clause.clauses
                    if not (
                        hasattr(c, "left")
                        and getattr(c.left, "key", None)
                        == "verification_state"
                    )
                ]
                new_conditions.append(and_(*clauses) if clauses else None)
            else:
                if not (
                    hasattr(clause, "left")
                    and getattr(clause.left, "key", None)
                    == "verification_state"
                ):
                    new_conditions.append(clause)
        new_conditions = [c for c in new_conditions if c is not None]
        from sqlalchemy.sql import expression

        stmt = stmt.where(expression.and_(*new_conditions)) if new_conditions else stmt.where(
            expression.true()
        )
        return stmt

    svc._build_base_query = patched_build
    try:
        author, _ = _make_user_with_headers(
            session_factory, user_id=10, email="author10@s.test"
        )
        p_pending, _ = _make_user_with_headers(
            session_factory, user_id=11, email="p-pending2@s.test"
        )
        challenge = _insert_challenge(
            session_factory, author=author, challenge_type="dailyCommunity"
        )
        p_pending_row = _create_participant(
            session_factory, challenge=challenge, participant=p_pending
        )
        _set_opt_in(session_factory, profile=p_pending)
        _insert_verified_result(
            session_factory,
            participant=p_pending_row,
            metric_value=999,
            source_event_id="evt-a1-probe",
            verification_state=CHALLENGE_RESULT_STATE_PENDING,
        )
        page = _service_call(
            session_factory,
            lambda db: get_leaderboard_page(
                db,
                challenge_public_id=challenge.public_id,
                viewer_profile_public_id=author.public_id,
                cursor=None,
                limit=20,
            ),
        )
        # The pending row WOULD land — proof that the filter is
        # the load-bearing invariant. With the filter ON
        # (production behaviour), the row is excluded.
        assert any(e.public_id == p_pending.public_id for e in page.entries)
    finally:
        svc._build_base_query = original_build


# ---------------------------------------------------------------------------
# A2 — deterministic tie-breaker (D4).
# ---------------------------------------------------------------------------


def test_a2_deterministic_tie_break_by_submitted_at_then_id(
    session_factory,
) -> None:
    """A2 — three rows with the same ``metric_value`` order by
    ``(submitted_at ASC, id ASC)`` — the L109 measurement
    pattern (many rows, same tie-break key, deterministic).
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=20, email="author20@s.test"
    )
    profiles = []
    for i in range(21, 24):
        profile, _ = _make_user_with_headers(
            session_factory,
            user_id=i,
            email=f"p{i}@s.test",
            display_name=f"Player {i}",
            handle=f"player_{i}",
        )
        profiles.append(profile)
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    # Insert in REVERSE chronological order to prove the order is
    # NOT insertion-order.
    base_time = _utcnow()
    inserted = []
    for index, profile in enumerate(reversed(profiles)):
        p_row = _create_participant(
            session_factory, challenge=challenge, participant=profile
        )
        _set_opt_in(session_factory, profile=profile)
        result = _insert_verified_result(
            session_factory,
            participant=p_row,
            metric_value=500,
            submitted_at=base_time + timedelta(seconds=index),
            source_event_id=f"evt-a2-{profile.id}",
        )
        inserted.append((profile, result))
    # Reverse back to the natural ordering for the assertion
    # — earlier ``submitted_at`` first, ties broken by id.
    inserted = list(reversed(inserted))

    page = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    page_ids = [entry.public_id for entry in page.entries]
    expected_ids = [profile.public_id for profile, _ in inserted]
    assert page_ids == expected_ids


def test_a2_tie_break_stable_across_calls(session_factory) -> None:
    """A2 — repeated calls return the same order (L109)."""
    author, _ = _make_user_with_headers(
        session_factory, user_id=30, email="author30@s.test"
    )
    p1, _ = _make_user_with_headers(
        session_factory,
        user_id=31,
        email="p31@s.test",
        handle="alpha",
    )
    p2, _ = _make_user_with_headers(
        session_factory,
        user_id=32,
        email="p32@s.test",
        handle="beta",
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p1_row = _create_participant(
        session_factory, challenge=challenge, participant=p1
    )
    p2_row = _create_participant(
        session_factory, challenge=challenge, participant=p2
    )
    _set_opt_in(session_factory, profile=p1)
    _set_opt_in(session_factory, profile=p2)
    base = _utcnow()
    _insert_verified_result(
        session_factory,
        participant=p1_row,
        metric_value=400,
        submitted_at=base,
        source_event_id="evt-a2-31",
    )
    _insert_verified_result(
        session_factory,
        participant=p2_row,
        metric_value=400,
        submitted_at=base + timedelta(seconds=1),
        source_event_id="evt-a2-32",
    )

    # Run the query multiple times — the order must be stable.
    first = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    second = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    third = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    first_ids = [e.public_id for e in first.entries]
    second_ids = [e.public_id for e in second.entries]
    third_ids = [e.public_id for e in third.entries]
    assert first_ids == second_ids == third_ids
    assert first_ids == [p1.public_id, p2.public_id]


# ---------------------------------------------------------------------------
# A3 — opt-out exclusion (D2 / §5.3).
# ---------------------------------------------------------------------------


def test_a3_opt_out_profile_excluded_from_leaderboard(
    session_factory,
) -> None:
    """A3 — a profile WITHOUT a
    ``community_leaderboard_opt_ins`` row does NOT appear in
    the leaderboard, even with a verified result.
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=40, email="author40@s.test"
    )
    p_opted_in, _ = _make_user_with_headers(
        session_factory, user_id=41, email="opt-in@s.test"
    )
    p_opted_out, _ = _make_user_with_headers(
        session_factory, user_id=42, email="opt-out@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p_in_row = _create_participant(
        session_factory, challenge=challenge, participant=p_opted_in
    )
    p_out_row = _create_participant(
        session_factory, challenge=challenge, participant=p_opted_out
    )
    # ONLY p_opted_in opts in.
    _set_opt_in(session_factory, profile=p_opted_in)
    _insert_verified_result(
        session_factory,
        participant=p_in_row,
        metric_value=500,
        source_event_id="evt-a3-in",
    )
    _insert_verified_result(
        session_factory,
        participant=p_out_row,
        metric_value=900,  # higher metric but opt-out
        source_event_id="evt-a3-out",
    )

    page = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    public_ids = [e.public_id for e in page.entries]
    assert p_opted_in.public_id in public_ids
    assert p_opted_out.public_id not in public_ids


def test_a3_set_opt_in_toggle_idempotent(session_factory) -> None:
    """A3 — ``set_opt_in`` toggles both directions; a second
    call with the same value is idempotent (no exception).
    """
    _, _ = _make_user_with_headers(
        session_factory, user_id=50, email="author50@s.test"
    )
    profile, _ = _make_user_with_headers(
        session_factory, user_id=51, email="toggle@s.test"
    )

    # First opt-in.
    state1 = _service_call(
        session_factory,
        lambda db: set_opt_in(
            db, profile_id=profile.id, opted_in=True, now=_utcnow()
        ),
    )
    assert state1 == "opted_in"
    # Second opt-in is idempotent.
    state2 = _service_call(
        session_factory,
        lambda db: set_opt_in(
            db, profile_id=profile.id, opted_in=True, now=_utcnow()
        ),
    )
    assert state2 == "opted_in"
    # Opt-out flips.
    state3 = _service_call(
        session_factory,
        lambda db: set_opt_in(
            db, profile_id=profile.id, opted_in=False, now=_utcnow()
        ),
    )
    assert state3 == "opted_out"
    # Second opt-out is idempotent.
    state4 = _service_call(
        session_factory,
        lambda db: set_opt_in(
            db, profile_id=profile.id, opted_in=False, now=_utcnow()
        ),
    )
    assert state4 == "opted_out"


# ---------------------------------------------------------------------------
# A4 — friends-scope follow-graph filter (D4 / Kontextus 5).
# ---------------------------------------------------------------------------


def test_a4_friends_scope_filters_by_viewer_follows(
    session_factory,
) -> None:
    """A4 — for ``type='friends'`` challenges, only participants
    the viewer FOLLOWS appear in the leaderboard.
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=60, email="author60@s.test"
    )
    viewer, _ = _make_user_with_headers(
        session_factory, user_id=61, email="viewer61@s.test"
    )
    p_followed, _ = _make_user_with_headers(
        session_factory, user_id=62, email="followed@s.test"
    )
    p_unfollowed, _ = _make_user_with_headers(
        session_factory, user_id=63, email="unfollowed@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type=CHALLENGE_TYPE_FRIENDS
    )
    p_followed_row = _create_participant(
        session_factory, challenge=challenge, participant=p_followed
    )
    p_unfollowed_row = _create_participant(
        session_factory, challenge=challenge, participant=p_unfollowed
    )
    _set_opt_in(session_factory, profile=p_followed)
    _set_opt_in(session_factory, profile=p_unfollowed)
    _create_follow_edge(
        session_factory, follower=viewer, followed=p_followed
    )
    _insert_verified_result(
        session_factory,
        participant=p_followed_row,
        metric_value=500,
        source_event_id="evt-a4-followed",
    )
    _insert_verified_result(
        session_factory,
        participant=p_unfollowed_row,
        metric_value=900,  # higher metric but not followed
        source_event_id="evt-a4-unfollowed",
    )

    page = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=viewer.public_id,
            cursor=None,
            limit=20,
        ),
    )
    public_ids = [e.public_id for e in page.entries]
    assert public_ids == [p_followed.public_id]


def test_a4_non_friends_scope_has_no_follow_filter(
    session_factory,
) -> None:
    """A4 — for non-friends challenge types, the follow-graph
    filter does NOT apply — all opted-in profiles with verified
    results are visible.
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=70, email="author70@s.test"
    )
    p1, _ = _make_user_with_headers(
        session_factory, user_id=71, email="p71@s.test"
    )
    p2, _ = _make_user_with_headers(
        session_factory, user_id=72, email="p72@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p1_row = _create_participant(
        session_factory, challenge=challenge, participant=p1
    )
    p2_row = _create_participant(
        session_factory, challenge=challenge, participant=p2
    )
    _set_opt_in(session_factory, profile=p1)
    _set_opt_in(session_factory, profile=p2)
    # No follow edges between the viewer and either participant.
    _insert_verified_result(
        session_factory,
        participant=p1_row,
        metric_value=400,
        source_event_id="evt-a4-daily-1",
    )
    _insert_verified_result(
        session_factory,
        participant=p2_row,
        metric_value=900,
        source_event_id="evt-a4-daily-2",
    )

    page = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    public_ids = [e.public_id for e in page.entries]
    assert p1.public_id in public_ids
    assert p2.public_id in public_ids


# ---------------------------------------------------------------------------
# A5 — pagination stability (D4 / L109).
# ---------------------------------------------------------------------------


def test_a5_pagination_stable_no_duplicates(session_factory) -> None:
    """A5 — walk 7 rows with page size 3: page 1 (3) + page 2
    (3) + page 3 (1) = 7 rows, no duplicates, last page has
    ``next_cursor=None``.
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=80, email="author80@s.test"
    )
    profiles = []
    for i in range(81, 88):
        profile, _ = _make_user_with_headers(
            session_factory,
            user_id=i,
            email=f"p{i}@s.test",
            display_name=f"Player {i}",
            handle=f"player_{i}",
        )
        profiles.append(profile)
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    base = _utcnow()
    for index, profile in enumerate(profiles):
        p_row = _create_participant(
            session_factory, challenge=challenge, participant=profile
        )
        _set_opt_in(session_factory, profile=profile)
        # Stagger ``metric_value`` so the order is unambiguous.
        _insert_verified_result(
            session_factory,
            participant=p_row,
            metric_value=700 - index,  # 700, 699, 698, …
            submitted_at=base + timedelta(seconds=index),
            source_event_id=f"evt-a5-{profile.id}",
        )

    seen: list[uuid.UUID] = []
    cursor: str | None = None
    page_count = 0
    while True:
        page_count += 1
        page = _service_call(
            session_factory,
            lambda db: get_leaderboard_page(
                db,
                challenge_public_id=challenge.public_id,
                viewer_profile_public_id=author.public_id,
                cursor=cursor,
                limit=3,
            ),
        )
        seen.extend(e.public_id for e in page.entries)
        if page.next_cursor is None:
            break
        cursor = page.next_cursor
        # Defensive — avoid infinite loops if the cursor logic
        # is buggy.
        assert page_count <= 5

    assert len(seen) == 7
    assert len(set(seen)) == 7  # no duplicates
    assert page_count == 3  # 3 + 3 + 1


# ---------------------------------------------------------------------------
# A6 — disqualification/delete deterministic refresh (D5).
# ---------------------------------------------------------------------------


def test_a6_disqualification_deletes_entry_deterministically(
    session_factory,
) -> None:
    """A6 — direct DB-mutation of a verified row's
    ``verification_state`` to ``rejected`` removes the entry
    from the projection deterministically on the next read
    (the §D5 test-szintű DB-mutáció surface).
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=90, email="author90@s.test"
    )
    p1, _ = _make_user_with_headers(
        session_factory, user_id=91, email="p91@s.test"
    )
    p2, _ = _make_user_with_headers(
        session_factory, user_id=92, email="p92@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p1_row = _create_participant(
        session_factory, challenge=challenge, participant=p1
    )
    p2_row = _create_participant(
        session_factory, challenge=challenge, participant=p2
    )
    _set_opt_in(session_factory, profile=p1)
    _set_opt_in(session_factory, profile=p2)
    _insert_verified_result(
        session_factory,
        participant=p1_row,
        metric_value=500,
        source_event_id="evt-a6-1",
    )
    _insert_verified_result(
        session_factory,
        participant=p2_row,
        metric_value=400,
        source_event_id="evt-a6-2",
    )

    # Both visible before the mutation.
    page_before = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    before_ids = [e.public_id for e in page_before.entries]
    assert p1.public_id in before_ids
    assert p2.public_id in before_ids

    # Direct DB mutation: flip p1's verified result to rejected
    # (the §D5 test-szintű DB-mutáció).
    db: Session = session_factory()
    try:
        db.execute(
            text(
                "UPDATE community_challenge_results "
                "SET verification_state = 'rejected', reason_code = 'disqualified' "
                "WHERE participant_id = :pid AND source_event_id = :evt"
            ),
            {"pid": p1_row.id, "evt": "evt-a6-1"},
        )
        db.commit()
    finally:
        db.close()

    # The §D5 no-op rebuild (re-reads the projection from scratch).
    rebuild_count = _service_call(
        session_factory,
        lambda db: rebuild_leaderboard(
            db, challenge_public_id=challenge.public_id
        ),
    )
    assert rebuild_count == 1  # p2 only — p1 is now rejected

    page_after = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    after_ids = [e.public_id for e in page_after.entries]
    assert p1.public_id not in after_ids
    assert after_ids == [p2.public_id]


def test_a6_row_deletion_removes_entry_deterministically(
    session_factory,
) -> None:
    """A6 — direct DELETE of a verified row removes the entry
    from the projection deterministically (the §D5 alternate
    branch — "vagy törli a sort").
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=100, email="author100@s.test"
    )
    p1, _ = _make_user_with_headers(
        session_factory, user_id=101, email="p101@s.test"
    )
    p2, _ = _make_user_with_headers(
        session_factory, user_id=102, email="p102@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p1_row = _create_participant(
        session_factory, challenge=challenge, participant=p1
    )
    p2_row = _create_participant(
        session_factory, challenge=challenge, participant=p2
    )
    _set_opt_in(session_factory, profile=p1)
    _set_opt_in(session_factory, profile=p2)
    _insert_verified_result(
        session_factory,
        participant=p1_row,
        metric_value=500,
        source_event_id="evt-a6del-1",
    )
    _insert_verified_result(
        session_factory,
        participant=p2_row,
        metric_value=400,
        source_event_id="evt-a6del-2",
    )

    # Direct DELETE: remove p1's row entirely.
    db: Session = session_factory()
    try:
        db.execute(
            text(
                "DELETE FROM community_challenge_results "
                "WHERE participant_id = :pid AND source_event_id = :evt"
            ),
            {"pid": p1_row.id, "evt": "evt-a6del-1"},
        )
        db.commit()
    finally:
        db.close()

    page_after = _service_call(
        session_factory,
        lambda db: get_leaderboard_page(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=author.public_id,
            cursor=None,
            limit=20,
        ),
    )
    after_ids = [e.public_id for e in page_after.entries]
    assert p1.public_id not in after_ids
    assert after_ids == [p2.public_id]


# ---------------------------------------------------------------------------
# own-rank helper (D6 / Kontextus 6).
# ---------------------------------------------------------------------------


def test_own_rank_returns_null_when_opted_out(session_factory) -> None:
    """The own-rank endpoint returns ``None`` when the viewer is
    opted-out, even with a verified result.
    """
    author, _ = _make_user_with_headers(
        session_factory, user_id=110, email="author110@s.test"
    )
    p, _ = _make_user_with_headers(
        session_factory, user_id=111, email="p111@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=author, challenge_type="dailyCommunity"
    )
    p_row = _create_participant(
        session_factory, challenge=challenge, participant=p
    )
    # NOTE: no opt-in row for ``p``.
    _insert_verified_result(
        session_factory,
        participant=p_row,
        metric_value=500,
        source_event_id="evt-own-rank",
    )

    entry = _service_call(
        session_factory,
        lambda db: get_own_rank(
            db,
            challenge_public_id=challenge.public_id,
            viewer_profile_public_id=p.public_id,
        ),
    )
    assert entry is None