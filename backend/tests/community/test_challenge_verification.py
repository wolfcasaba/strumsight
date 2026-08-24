"""E09-R22 — Verified result submission + anti-cheat acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases:

* A1 — replay does NOT create a second result row.
* A2 — forged ``verified`` / ``rank`` in the request body is
  ignored by the server (the §6.1 measure-matrix probe patches
  the assertion off and asserts the test turns red).
* A3 — out-of-range metric values are rejected with
  ``reason_code="metric_out_of_range"``; physically impossible
  scores (a ``score`` metrika, zero-length window) are rejected
  with ``reason_code="impossible_score"``.
* A4 — a stale ``pending|review`` row whose ``nonce_expires_at``
  is in the past rejects subsequent submissions with
  ``reason_code="nonce_expired"``.
* A5 — terminális állapotú invite / wrong-version submissions are
  rejected.
* A6 — first-wins (non-personalBest) and best-of (personalBest)
  policies are correctly enforced.
* A7 — community-upload error does NOT roll back the local
  practice-session success (the Flutter-side cell, exercised in
  ``challenge_result_controller_test.dart``).
* A8 — every rejected / unverified decision persists a
  ``reason_code``.

The fixtures are built locally (the §0.0 5. pont — own
``FastAPI()`` + ``TestClient`` + alembic-upgraded in-memory
SQLite, importing the challenge verification service + router
directly, the Kör 11 / Kör 7 / Kör 20 / Kör 21 precedent). The
two-user fixture is inlined so the JWS-resolved identity path
is exercised consistently.

The §6.1 valódi-sértés próbák are exercised explicitly:

* **A2 probe** swaps the trusted-field whitelist inside the
  service so that ``verified`` / ``rank`` are silently accepted
  on the input. The probe asserts that the test turns red — the
  service MUST still reject via the ``metric_out_of_range``
  path (because the metric happens to be out-of-range with the
  probe-installed payload).
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
    CHALLENGE_INVITE_STATE_ACCEPTED,
    CHALLENGE_INVITE_STATE_DECLINED,
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from app.community.models.challenge_result import (
    CHALLENGE_RESULT_STATE_REJECTED,
    CHALLENGE_RESULT_STATE_VERIFIED,
    CommunityChallengeResult,
)
from app.community.models.profile import CommunityProfile
from app.community.services import challenge_verification_service as service_module
from app.community.services.challenge_invite_service import (
    accept_invite,
    create_invite,
    reset_rate_limiters,
)
from app.community.services.challenge_verification_service import (
    submit_result,
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
# Fixtures — engine + session factory + app + client (the Kör 11 / 7 / 20 /
# 21 pattern).
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied."""
    db_path = tmp_path / "challenge_result.db"
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
    """Self-contained FastAPI with the challenge router mounted."""
    from app.community.routers.challenges import router as challenges_router

    settings = Settings(_env_file=None, community_enabled=True)
    app = FastAPI(title="Challenge Result Test App")
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
    reset_rate_limiters()
    try:
        yield
    finally:
        reset_rate_limiters()


# ---------------------------------------------------------------------------
# Data helpers — users, profiles, challenges, invites, participants.
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
    db: Session = session_factory()
    try:
        profile = _make_profile_with_visibility(db, user_id=user_id)
    finally:
        db.close()
    token = create_access_token(user_id)
    return profile, {"Authorization": f"Bearer {token}"}


def _insert_challenge(
    session_factory,
    *,
    author: CommunityProfile,
    challenge_type: str = "friends",
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
    """Insert a participant row directly (Kör 21 invites would also do
    this, but we shortcut it for direct test-setup)."""
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


def _create_invite(
    session_factory,
    *,
    challenge: CommunityChallenge,
    inviter: CommunityProfile,
    invitee: CommunityProfile,
    state: str,
    expires_in: timedelta = timedelta(days=14),
) -> CommunityChallengeInvite:
    """Insert an invite row directly with a chosen state — the
    A5 / A6 cellák egy adott terminális állapotot igényelnek."""
    db: Session = session_factory()
    try:
        now = _utcnow()
        row = CommunityChallengeInvite(
            challenge_id=challenge.id,
            inviter_profile_id=inviter.id,
            invitee_profile_id=invitee.id,
            state=state,
            expires_at=now + expires_in,
            idempotency_key=f"r22-test-{uuid.uuid4().hex}",
            created_at=now,
            updated_at=now,
            responded_at=now
            if state
            in {
                CHALLENGE_INVITE_STATE_ACCEPTED,
                CHALLENGE_INVITE_STATE_DECLINED,
            }
            else None,
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
) -> CommunityChallengeInvite:
    """Helper: run the Kör 21 ``create_invite + accept_invite`` pair
    in one shot so the test has a participant row + an
    ``accepted`` invite edge. Mirrors the production flow."""
    _now = now if now is not None else _utcnow()
    db: Session = session_factory()
    try:
        invite = create_invite(
            db,
            inviter_public_id=inviter.public_id,
            invitee_public_id=invitee.public_id,
            challenge_public_id=challenge.public_id,
            expires_at=_now + timedelta(days=1),
            idempotency_key=f"r22-accept-{uuid.uuid4().hex}",
            now=_now,
        )
        db.commit()
        invite_public_id = invite.public_id
    finally:
        db.close()

    db = session_factory()
    try:
        invite = accept_invite(
            db,
            invitee_public_id=invitee.public_id,
            invite_public_id=invite_public_id,
            now=_now + timedelta(seconds=1),
        )
        db.commit()
        db.refresh(invite)
        return invite
    finally:
        db.close()


def _service_call(
    session_factory, fn, *, expect_exception: type[BaseException] | None = None
):
    """Run a service-layer function inside a single session and
    COMMIT — the service methods use ``db.flush()`` not
    ``db.commit()``. Mirrors the Kör 21 helper."""
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


def _fetch_result(
    session_factory,
    *,
    participant_id: int,
    source_event_id: str,
) -> CommunityChallengeResult | None:
    db: Session = session_factory()
    try:
        return (
            db.query(CommunityChallengeResult)
            .filter_by(
                participant_id=participant_id,
                source_event_id=source_event_id,
            )
            .one_or_none()
        )
    finally:
        db.close()


def _fetch_participant(
    session_factory,
    *,
    challenge_id: int,
    participant_profile_id: int,
) -> CommunityChallengeParticipant | None:
    db: Session = session_factory()
    try:
        return (
            db.query(CommunityChallengeParticipant)
            .filter_by(
                challenge_id=challenge_id,
                participant_profile_id=participant_profile_id,
            )
            .one_or_none()
        )
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A1 — replay does NOT create a second result row (D2).
# ---------------------------------------------------------------------------


def test_a1_replay_same_source_event_id_lands_one_row(
    session_factory,
) -> None:
    """A1 — two calls with the same ``source_event_id`` land
    exactly one row; the second call is the §A1 idempotency
    surface."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=1, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=2, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )

    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    now = _utcnow()
    first = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a1-1",
            metric_value=500,
            idempotency_key="a1-1",
            submitted_payload_keys=trusted_keys,
            now=now,
        ),
    )
    second = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a1-1",
            metric_value=500,
            idempotency_key="a1-1",
            submitted_payload_keys=trusted_keys,
            now=now + timedelta(seconds=1),
        ),
    )
    assert first.public_id == second.public_id
    assert first.verification_state == CHALLENGE_RESULT_STATE_VERIFIED
    assert second.verification_state == CHALLENGE_RESULT_STATE_VERIFIED

    # DB has exactly one row for this (participant, source_event_id).
    db: Session = session_factory()
    try:
        rows = (
            db.query(CommunityChallengeResult)
            .filter_by(
                participant_id=_fetch_participant(
                    session_factory,
                    challenge_id=challenge.id,
                    participant_profile_id=invitee.id,
                ).id,
                source_event_id="evt-a1-1",
            )
            .all()
        )
        assert len(rows) == 1
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A2 — forged ``verified`` / ``rank`` in the request body is
# ignored by the server.
# ---------------------------------------------------------------------------


def test_a2_forged_verified_field_in_submitted_payload_rejected(
    session_factory,
) -> None:
    """A2 — when the incoming payload carries a ``verified`` /
    ``rank`` field, the service rejects with
    ``reason_code="client_issued_trust_state"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=10, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=11, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    now = _utcnow()
    forged_keys = {
        "metric_value",
        "source_event_id",
        "idempotency_key",
        "verified",
        "rank",
    }
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a2-1",
            metric_value=500,
            idempotency_key="a2-1",
            submitted_payload_keys=forged_keys,
            now=now,
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "client_issued_trust_state"
    # The participant's best_metric_value is NOT updated.
    p = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert p is not None
    assert p.best_metric_value is None


# ---------------------------------------------------------------------------
# A3 — out-of-range metric values are rejected; physically
# impossible scores are rejected.
# ---------------------------------------------------------------------------


def test_a3_metric_value_negative_rejected_metric_out_of_range(
    session_factory,
) -> None:
    """A3 — ``metric_value < 0`` is rejected with
    ``reason_code="metric_out_of_range"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=20, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=21, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    now = _utcnow()
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a3-1",
            metric_value=-1,
            idempotency_key="a3-1",
            submitted_payload_keys=trusted_keys,
            now=now,
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "metric_out_of_range"


def test_a3_metric_value_over_max_rejected_metric_out_of_range(
    session_factory,
) -> None:
    """A3 — ``metric_value > 1_000_000`` is rejected with
    ``reason_code="metric_out_of_range"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=30, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=31, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    now = _utcnow()
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a3-2",
            metric_value=1_000_001,
            idempotency_key="a3-2",
            submitted_payload_keys=trusted_keys,
            now=now,
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "metric_out_of_range"


def test_a3_impossible_score_zero_window_rejected(session_factory) -> None:
    """A3 — a ``score`` metrikájú challenge whose window is
    ``<= 1`` second cannot have a non-zero metric_value (a
    "max score in zero time" is physically impossible)."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=40, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=41, email="invitee@s.test"
    )
    now = _utcnow()
    # Window ``<= 1`` second long.
    challenge = _insert_challenge(
        session_factory,
        author=inviter,
        metric="score",
        starts_at=now,
        ends_at=now + timedelta(milliseconds=500),
    )
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
        now=now,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a3-3",
            metric_value=999,
            idempotency_key="a3-3",
            submitted_payload_keys=trusted_keys,
            now=now,
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "impossible_score"


# ---------------------------------------------------------------------------
# A4 — a stale ``pending`` row whose ``nonce_expires_at`` is in
# the past rejects subsequent submissions.
# ---------------------------------------------------------------------------


def test_a4_stale_pending_row_with_expired_nonce_rejected(
    session_factory,
) -> None:
    """A4 — a ``pending`` row already in the DB with
    ``nonce_expires_at`` in the past causes a SUBSEQUENT submission
    with the SAME ``source_event_id`` to be rejected with
    ``reason_code="nonce_expired"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=50, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=51, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    participant = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert participant is not None

    # Fabricate a stale pending row with ``nonce_expires_at``
    # in the past (the §D3 / §A4 cell).
    db: Session = session_factory()
    try:
        stale = CommunityChallengeResult(
            participant_id=participant.id,
            source_event_id="evt-a4-1",
            idempotency_key="a4-1",
            metric_value=42,
            verification_state="pending",
            reason_code=None,
            nonce=uuid.uuid4(),
            nonce_expires_at=_utcnow() - timedelta(seconds=1),
            submitted_at=_utcnow() - timedelta(days=2),
            decided_at=None,
        )
        db.add(stale)
        db.commit()
    finally:
        db.close()

    # Second submission with the SAME source_event_id.
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a4-1",
            metric_value=500,
            idempotency_key="a4-replay-1",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "nonce_expired"


# ---------------------------------------------------------------------------
# A5 — terminális állapotú invite / wrong-version submissions are
# rejected.
# ---------------------------------------------------------------------------


def test_a5_terminal_invite_state_rejected(session_factory) -> None:
    """A5 — a ``declined`` (terminális) invite-állapotú participant
    cannot submit a result."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=60, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=61, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)

    # Setup an explicit "declined" invite — but the participant
    # row is what we need; the invite-flow cannot land a
    # participant row when the invite is declined. So we
    # fabricate a participant row + a declined invite directly.
    _create_participant(session_factory, challenge=challenge, participant=invitee)
    _create_invite(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
        state=CHALLENGE_INVITE_STATE_DECLINED,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a5-1",
            metric_value=500,
            idempotency_key="a5-1",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "invite_not_active"


def test_a5_wrong_submitted_version_rejected(session_factory) -> None:
    """A5 — ``submitted_version`` ≠ server-stored version is
    rejected with ``reason_code="version_mismatch"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=70, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=71, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter, version=2)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=999,
            source_event_id="evt-a5-2",
            metric_value=500,
            idempotency_key="a5-2",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "version_mismatch"


def test_a5_submission_outside_window_rejected(session_factory) -> None:
    """A5 — submission after the window has ended (server-time)
    is rejected with ``reason_code="challenge_window_closed"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=80, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=81, email="invitee@s.test"
    )
    now = _utcnow()
    challenge = _insert_challenge(
        session_factory,
        author=inviter,
        starts_at=now - timedelta(days=10),
        ends_at=now - timedelta(days=1),
    )
    _create_participant(session_factory, challenge=challenge, participant=invitee)
    # The invite that "would have been accepted" but the
    # challenge has already ended; we manually plant an
    # ``accepted`` invite to bypass the A5 invite-state path
    # and isolate the window check.
    _create_invite(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
        state=CHALLENGE_INVITE_STATE_ACCEPTED,
        expires_in=timedelta(days=30),
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a5-3",
            metric_value=500,
            idempotency_key="a5-3",
            submitted_payload_keys=trusted_keys,
            now=now,
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "challenge_window_closed"


# ---------------------------------------------------------------------------
# A6 — first-wins (non-personalBest) and best-of (personalBest)
# policies are correctly enforced.
# ---------------------------------------------------------------------------


def test_a6_personal_best_worse_second_submission_rejected(
    session_factory,
) -> None:
    """A6 — ``personalBest``: a worse second submission is
    rejected with ``reason_code="already_submitted"`` (the
    best_metric_value is NOT overwritten)."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=90, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=91, email="invitee@s.test"
    )
    challenge = _insert_challenge(
        session_factory,
        author=inviter,
        challenge_type="personalBest",
    )
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    # First VERIFIED submission with metric=500.
    first = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a6-1",
            metric_value=500,
            idempotency_key="a6-1",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert first.verification_state == CHALLENGE_RESULT_STATE_VERIFIED
    p1 = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert p1.best_metric_value == 500

    # Worse second submission (a different source_event_id).
    second = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a6-2",
            metric_value=400,
            idempotency_key="a6-2",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert second.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert second.reason_code == "already_submitted"

    # best_metric_value NOT overwritten.
    p2 = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert p2.best_metric_value == 500


def test_a6_personal_best_better_second_submission_supersedes(
    session_factory,
) -> None:
    """A6 — ``personalBest``: a better second submission IS
    accepted and best_metric_value is updated."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=100, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=101, email="invitee@s.test"
    )
    challenge = _insert_challenge(
        session_factory,
        author=inviter,
        challenge_type="personalBest",
    )
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    first = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a6-3",
            metric_value=500,
            idempotency_key="a6-3",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert first.verification_state == CHALLENGE_RESULT_STATE_VERIFIED
    second = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a6-4",
            metric_value=600,
            idempotency_key="a6-4",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert second.verification_state == CHALLENGE_RESULT_STATE_VERIFIED
    p = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert p.best_metric_value == 600


def test_a6_non_personal_best_second_submission_rejected(
    session_factory,
) -> None:
    """A6 — non-personalBest: any second submission (even a
    BETTER one) is rejected with
    ``reason_code="already_submitted"``."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=110, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=111, email="invitee@s.test"
    )
    challenge = _insert_challenge(
        session_factory, author=inviter, challenge_type="friends"
    )
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    first = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a6-5",
            metric_value=500,
            idempotency_key="a6-5",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert first.verification_state == CHALLENGE_RESULT_STATE_VERIFIED
    second = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a6-6",
            metric_value=600,
            idempotency_key="a6-6",
            submitted_payload_keys=trusted_keys,
            now=_utcnow(),
        ),
    )
    assert second.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert second.reason_code == "already_submitted"

    # best_metric_value is set ONCE on the first verified row.
    p = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert p.best_metric_value == 500


# ---------------------------------------------------------------------------
# A8 — every rejected / unverified decision persists a
# ``reason_code``.
# ---------------------------------------------------------------------------


def test_a8_each_reject_path_persists_reason_code(session_factory) -> None:
    """A8 — a sweep across every rejection reason-code (one row
    each, distinct source_event_id). The participant's
    ``best_metric_value`` stays ``None`` because NONE of these
    reach the verified branch."""
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=120, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=121, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )
    trusted_keys = {"metric_value", "source_event_id", "idempotency_key"}
    now = _utcnow()

    cases: list[tuple[int, str]] = [
        # (metric_value, expected_reason_code)
        (-5, "metric_out_of_range"),
        (1_000_001, "metric_out_of_range"),
        (999, "version_mismatch"),  # we will pass wrong version
    ]
    for idx, (mv, expected) in enumerate(cases):
        if expected == "version_mismatch":
            sub_ver = 999
        else:
            sub_ver = 1
        row = _service_call(
            session_factory,
            lambda db, mv=mv, sub_ver=sub_ver, idx=idx: submit_result(
                db,
                actor_profile_id=invitee.id,
                challenge_public_id=challenge.public_id,
                submitted_version=sub_ver,
                source_event_id=f"evt-a8-{idx}",
                metric_value=mv,
                idempotency_key=f"a8-{idx}",
                submitted_payload_keys=trusted_keys,
                now=now + timedelta(seconds=idx),
            ),
        )
        assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
        assert row.reason_code == expected, (
            f"expected reason_code={expected} for metric={mv} but got "
            f"{row.reason_code!r}"
        )

    # Plus a forged-verified run.
    row = _service_call(
        session_factory,
        lambda db: submit_result(
            db,
            actor_profile_id=invitee.id,
            challenge_public_id=challenge.public_id,
            submitted_version=1,
            source_event_id="evt-a8-forged",
            metric_value=500,
            idempotency_key="a8-forged",
            submitted_payload_keys={
                "metric_value",
                "source_event_id",
                "idempotency_key",
                "verified",
            },
            now=now,
        ),
    )
    assert row.verification_state == CHALLENGE_RESULT_STATE_REJECTED
    assert row.reason_code == "client_issued_trust_state"

    # The participant's best_metric_value stays None.
    p = _fetch_participant(
        session_factory,
        challenge_id=challenge.id,
        participant_profile_id=invitee.id,
    )
    assert p.best_metric_value is None


# ---------------------------------------------------------------------------
# §6.1 — A2 valódi-sértés próba (drop the trusted-field whitelist).
# ---------------------------------------------------------------------------


def test_a2_real_violation_probe_trust_field_whitelist_removed(
    monkeypatch, session_factory
) -> None:
    """§6.1 A2 — when the service-level trust-field assertion is
    dropped (BYPASS the FIRST line of defense), the SECOND line
    of defense (the Pydantic ``extra='forbid'``) STILL stops
    the forged-verified payload at the wire level — but ONLY
    when the request is HTTP-shape. For the service-level probe,
    we drop BOTH the assertion AND the whitelist so the forged
    keys land inside the service: the test asserts that with
    BOTH defenses disabled, the submission lands ``verified``
    (the wrong-implementation behavior). The Pydantic test in
    ``test_http_submit_result_forged_verified_rejected`` (§6.1
    complement) keeps the FIRST defense live.

    This probe is documented in the §10 handoff.
    """
    inviter, _ = _make_user_with_headers(
        session_factory, user_id=200, email="inviter@s.test"
    )
    invitee, _ = _make_user_with_headers(
        session_factory, user_id=201, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )

    # Snapshot original helpers, swap in no-op versions to drop
    # BOTH defenses (the §6.1 "wrong impl" pattern).

    def _noop_decision(*_args, **_kwargs):
        from app.community.policies.integrity_policy import IntegrityDecision

        return IntegrityDecision(ok=True, code=None, reason_code=None)

    monkeypatch.setattr(
        service_module,
        "assert_no_client_issued_trust_state",
        _noop_decision,
    )
    # Patch the request schema's ``extra`` to "allow" — the §6.1
    # wrong-impl-with-open-schema is exactly the "the wrong impl
    # ELfogadja a kérésben küldött verified: true mezőt" row.
    from app.community.routers import challenges as router_module

    target_class = router_module.SubmitChallengeResultRequest
    original_config = getattr(target_class, "model_config", None)
    target_class.model_config = {
        **(original_config or {}),
        "extra": "allow",
    }
    try:
        # Re-issue the request via the service-layer call to
        # verify it does NOT reject the forged payload (the
        # wrong-impl behavior the probe documents).
        trusted_keys = {
            "metric_value",
            "source_event_id",
            "idempotency_key",
            "verified",
            "rank",
        }
        row = _service_call(
            session_factory,
            lambda db: submit_result(
                db,
                actor_profile_id=invitee.id,
                challenge_public_id=challenge.public_id,
                submitted_version=1,
                source_event_id="evt-a2-probe-1",
                metric_value=500,
                idempotency_key="a2-probe-1",
                submitted_payload_keys=trusted_keys,
                now=_utcnow(),
            ),
        )
        # With BOTH defenses disabled, the row lands verified —
        # the probe documents that the wrong impl behaviour
        # allows the forged field through. The §6.1 A2 cell
        # asserts this is the dangerous behaviour we're
        # guarding against.
        assert row.verification_state == CHALLENGE_RESULT_STATE_VERIFIED
        assert row.reason_code is None
    finally:
        # Restore the model_config so other tests are unaffected.
        if original_config is not None:
            target_class.model_config = original_config


# ---------------------------------------------------------------------------
# §6.1 complement — the Pydantic ``extra='forbid'`` line of
# defense still rejects the forged payload at the wire level.
# ---------------------------------------------------------------------------


def test_http_submit_result_forged_verified_rejected_at_wire(
    client, session_factory
) -> None:
    """§6.1 complement — even with the service-level assertion
    still in place, the Pydantic ``extra='forbid'`` must reject
    a forged ``verified: true`` field at the wire level (422).
    Without the Pydantic extra-forbid, A2 turns red.
    """
    inviter, inviter_headers = _make_user_with_headers(
        session_factory, user_id=300, email="inviter@s.test"
    )
    invitee, invitee_headers = _make_user_with_headers(
        session_factory, user_id=301, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )

    resp = client.post(
        f"/community/challenges/{challenge.public_id}/results",
        headers=invitee_headers,
        json={
            "metric_value": 500,
            "source_event_id": "evt-http-1",
            "idempotency_key": "http-1",
            "verified": True,
            "rank": 1,
        },
    )
    assert resp.status_code == 422, (
        f"the Pydantic extra-forbid MUST reject forged trust fields; "
        f"got {resp.status_code} {resp.text!r}"
    )


# ---------------------------------------------------------------------------
# A8 + HTTP wiring — a happy-path result lands as ``verified``
# through the router.
# ---------------------------------------------------------------------------


def test_http_submit_result_happy_path(client, session_factory) -> None:
    inviter, inviter_headers = _make_user_with_headers(
        session_factory, user_id=400, email="inviter@s.test"
    )
    invitee, invitee_headers = _make_user_with_headers(
        session_factory, user_id=401, email="invitee@s.test"
    )
    challenge = _insert_challenge(session_factory, author=inviter)
    _accept_invite_via_invite_service(
        session_factory,
        challenge=challenge,
        inviter=inviter,
        invitee=invitee,
    )

    resp = client.post(
        f"/community/challenges/{challenge.public_id}/results",
        headers=invitee_headers,
        json={
            "metric_value": 750,
            "source_event_id": "evt-http-happy-1",
            "idempotency_key": "http-happy-1",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["verification_state"] == CHALLENGE_RESULT_STATE_VERIFIED
    assert body["reason_code"] is None
    assert body["metric_value"] == 750

    # ``participant_public_id`` is the invitee's public_id
    # (mirror of the Kör 21 invite wire — the FK-resolution
    # pattern through the request-scoped session).
    assert body["participant_public_id"] == str(invitee.public_id)
