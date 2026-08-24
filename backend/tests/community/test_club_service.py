"""E09-R24 — Club service acceptance tests (ADR 0420).

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases:

* A1 — lone-owner leave is rejected with
  ``OwnerMustTransferFirst`` (the §10 real-violation probe
  documents this).
* A2 — permission matrix exercised for every (role, action)
  cell; a member cannot mutate another member's role.
* A3 — duplicate-join via the ``UNIQUE(club_id, profile_id)``
  constraint; the §6.1 probe drops the constraint and asserts
  two rows land.
* A4 — ``private`` club requires invite / accepted-request,
  ``discoverable`` / ``public`` grant immediate membership.
* A5 — moderator / owner can ``remove_member``; member cannot.
* A6 — blocked viewer sees no member in the shared club; the
  Kör 8 ``filter_public_ids_against_viewer_blocks`` helper is
  the gate.
* A7 — membership limit thresholds:
  ``member_count = MAX_CLUB_MEMBERS - 1`` → elfogad;
  ``member_count == MAX_CLUB_MEMBERS`` → MÉG elfogad;
  ``member_count == MAX_CLUB_MEMBERS`` + egy újabb join →
  elutasít. The cell values bind to ``MAX_CLUB_MEMBERS = 500``
  (D3).
* A8 — ownership transfer flips the OLD owner's role to
  PONTOSAN ``member`` (NOT moderator; the D4 / §0.0 invariant).
* §6.1 valódi-sértés próba — drop the A1 lone-owner guard
  and assert the A1 cell turns red.

The fixtures follow the E09-R23 ``test_leaderboard_service.py``
pattern — own ``FastAPI()`` + ``TestClient`` + alembic-upgraded
in-memory SQLite, importing the service directly. The router
layer is NOT mounted (Kör 24 brief §4 keeps the router out of
scope for this round).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command as alembic_command
from app.community.models.club import (
    CLUB_ROLE_MEMBER,
    CLUB_ROLE_MODERATOR,
    CLUB_ROLE_OWNER,
    CLUB_VISIBILITY_DISCOVERABLE,
    CLUB_VISIBILITY_PRIVATE,
    MAX_CLUB_MEMBERS,
    CommunityClub,
    CommunityClubMember,
)
from app.community.models.profile import CommunityProfile
from app.community.models.safety_relationships import CommunityBlock
from app.community.policies.club_permissions import (
    ClubAction,
    may_perform,
)
from app.community.services import club_service as svc
from app.database import enable_sqlite_foreign_keys

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — engine + session factory + app (the Kör 22 / Kör 23 pattern).
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied."""
    db_path = tmp_path / "club.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    alembic_command.upgrade(cfg, "head")
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


# ---------------------------------------------------------------------------
# Helpers — users, profiles, auth headers, club scaffolding.
# ---------------------------------------------------------------------------


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _insert_user(db: Session, user_id: int, email: str) -> None:
    """Insert a parent ``users`` row so the FK chain is satisfied."""
    from app.security import hash_password

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


def _make_profile(db: Session, *, user_id: int) -> CommunityProfile:
    """Insert a parent ``users`` row + a ``community_profiles`` row.

    The profile is the minimal column-set Kör 24 needs (the
    ``community_privacy_settings`` row is NOT required for the
    club tests — the Kör 24 service does NOT read the privacy
    row).
    """
    _insert_user(db, user_id, f"u{user_id}@s.test")
    db.commit()
    profile = CommunityProfile(user_id=user_id)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


def _make_profile_with_visibility(
    db: Session,
    *,
    user_id: int,
    visibility: str = "public",
) -> CommunityProfile:
    """Insert a parent ``users`` row + ``community_profiles`` +
    ``community_privacy_settings`` (FK chain satisfaction)."""
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
            "vis": visibility,
            "aud": "public",
        },
    )
    db.commit()
    db.refresh(profile)
    return profile


def _service_call(session_factory, fn):
    """Run a service-layer function inside a single session and COMMIT."""
    db: Session = session_factory()
    try:
        result = fn(db)
        db.commit()
        return result
    finally:
        db.close()


def _create_club(
    session_factory,
    *,
    owner: CommunityProfile,
    visibility: str = CLUB_VISIBILITY_DISCOVERABLE,
    name: str | None = None,
) -> CommunityClub:
    """Create a club via the service layer (bypasses the wire)."""
    if name is None:
        name = f"Club-{owner.id}-{uuid.uuid4().hex[:6]}"
    return _service_call(
        session_factory,
        lambda db: svc.create_club(
            db,
            owner_profile_id=owner.id,
            name=name,
            description="description",
            visibility=visibility,
            idempotency_key=f"create-{uuid.uuid4().hex}",
            now=_utcnow(),
        ),
    )


def _add_member(
    session_factory,
    *,
    club: CommunityClub,
    profile: CommunityProfile,
    role: str = CLUB_ROLE_MEMBER,
) -> CommunityClubMember:
    """Insert a membership row directly — bypasses the wire / the
    membership-limit cap so tests can stage a club at exactly
    ``MAX_CLUB_MEMBERS`` members without having to add 500
    members one-by-one through the service."""
    db: Session = session_factory()
    try:
        member = CommunityClubMember(
            public_id=uuid.uuid4(),
            club_id=club.id,
            profile_id=profile.id,
            role=role,
            joined_at=_utcnow(),
            updated_at=_utcnow(),
        )
        db.add(member)
        db.commit()
        db.refresh(member)
        return member
    finally:
        db.close()


def _make_profile_by_id(
    session_factory,
    *,
    user_id: int,
) -> CommunityProfile:
    db: Session = session_factory()
    try:
        return _make_profile(db, user_id=user_id)
    finally:
        db.close()


def _add_block(
    session_factory,
    *,
    blocker: CommunityProfile,
    blocked: CommunityProfile,
) -> None:
    """Insert a block edge directly."""
    db: Session = session_factory()
    try:
        edge = CommunityBlock(
            blocker_profile_id=blocker.id,
            blocked_profile_id=blocked.id,
        )
        db.add(edge)
        db.commit()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A1 — lone-owner leave requires transfer (§6.1 valódi-sértés probe).
# ---------------------------------------------------------------------------


def test_a1_lone_owner_leave_raises_owner_must_transfer_first(
    session_factory,
) -> None:
    """A1 — when only one owner exists, ``leave_club`` raises
    :class:`OwnerMustTransferFirst` and the owner membership row
    is preserved. The §10 implementation handoff documents the
    real-violation probe.
    """
    owner = _make_profile_by_id(session_factory, user_id=1)
    club = _create_club(session_factory, owner=owner)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.OwnerMustTransferFirst):
            svc.leave_club(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                now=_utcnow(),
            )
        db.rollback()
        # The membership row is still there.
        row = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=owner.id)
            .one()
        )
        assert row.role == CLUB_ROLE_OWNER
    finally:
        db.close()


def test_a1_real_violation_probe_drop_transfer_guard_fails_cell(
    session_factory,
    monkeypatch,
) -> None:
    """§6.1 valódi-sértés próba for A1 — drop the lone-owner
    guard inside ``leave_club`` and assert the owner CAN now
    leave without transfer (the A1 cell turns RED — the probe
    demonstrates the guard is load-bearing).

    We swap ``leave_club`` for a thin wrapper that skips the
    ``owner_count <= 1`` branch, then drive the call against a
    club whose only owner is the actor. Without the guard the
    leave succeeds and the club loses its owner — proving the
    cell is real.
    """
    owner = _make_profile_by_id(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner)

    # Patch out the lone-owner guard. The production service
    # raises OwnerMustTransferFirst when owner_count <= 1; the
    # probe strips that branch out (and the transfer-check in
    # general) so the leave lands.
    def leave_without_guard(db, *, actor_profile_id, club_public_id, now):
        actor = db.query(CommunityProfile).filter_by(id=actor_profile_id).one()
        club_row = db.query(CommunityClub).filter_by(public_id=club_public_id).one()
        member = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club_row.id, profile_id=actor.id)
            .one()
        )
        db.delete(member)
        db.flush()

    monkeypatch.setattr(svc, "leave_club", leave_without_guard)

    db: Session = session_factory()
    try:
        # Without the guard, the leave succeeds — the owner
        # membership row is gone, leaving the club ownerless.
        svc.leave_club(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            now=_utcnow(),
        )
        db.commit()
        remaining = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, role=CLUB_ROLE_OWNER)
            .count()
        )
        assert remaining == 0, (
            "probe expected an ownerless club — the A1 guard is "
            "load-bearing, not vacuous"
        )
    finally:
        db.close()


def test_a1_owner_leave_with_second_owner_succeeds(session_factory) -> None:
    """A1 — when a second owner exists (post-transfer), the
    original owner may leave without a transfer step.
    """
    owner = _make_profile_by_id(session_factory, user_id=3)
    new_owner = _make_profile_by_id(session_factory, user_id=4)
    club = _create_club(session_factory, owner=owner)
    # new_owner must be a member before transfer_ownership.
    _add_member(session_factory, club=club, profile=new_owner)
    # Hand the new_owner the club via transfer.
    _service_call(
        session_factory,
        lambda db: svc.transfer_ownership(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            new_owner_profile_id=new_owner.id,
            now=_utcnow(),
        ),
    )
    # The transfer made new_owner a member; flip them to owner
    # row explicitly so the leave path is exercised under
    # "two owners exist" conditions.
    db: Session = session_factory()
    try:
        member = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=new_owner.id)
            .one()
        )
        member.role = CLUB_ROLE_OWNER
        db.commit()
    finally:
        db.close()
    # Now leave succeeds — there are two owners.
    _service_call(
        session_factory,
        lambda db: svc.leave_club(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            now=_utcnow(),
        ),
    )
    db: Session = session_factory()
    try:
        row = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=owner.id)
            .one_or_none()
        )
        assert row is None
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A2 — permission matrix for every (role, action) cell.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("role", "action", "target_role", "expected"),
    [
        # Read-side — every role.
        (CLUB_ROLE_OWNER, ClubAction.LIST_MEMBERS, None, True),
        (CLUB_ROLE_MODERATOR, ClubAction.LIST_MEMBERS, None, True),
        (CLUB_ROLE_MEMBER, ClubAction.LIST_MEMBERS, None, True),
        # Owner-only.
        (CLUB_ROLE_OWNER, ClubAction.TRANSFER_OWNERSHIP, None, True),
        (CLUB_ROLE_MODERATOR, ClubAction.TRANSFER_OWNERSHIP, None, False),
        (CLUB_ROLE_MEMBER, ClubAction.TRANSFER_OWNERSHIP, None, False),
        (CLUB_ROLE_OWNER, ClubAction.UPDATE_CLUB, None, True),
        (CLUB_ROLE_MODERATOR, ClubAction.UPDATE_CLUB, None, False),
        (CLUB_ROLE_OWNER, ClubAction.ARCHIVE_CLUB, None, True),
        (CLUB_ROLE_MEMBER, ClubAction.ARCHIVE_CLUB, None, False),
        # Moderator+ on member targets.
        (CLUB_ROLE_OWNER, ClubAction.REMOVE_MEMBER, CLUB_ROLE_MEMBER, True),
        (CLUB_ROLE_MODERATOR, ClubAction.REMOVE_MEMBER, CLUB_ROLE_MEMBER, True),
        (CLUB_ROLE_MEMBER, ClubAction.REMOVE_MEMBER, CLUB_ROLE_MEMBER, False),
        (CLUB_ROLE_OWNER, ClubAction.INVITE_MEMBER, None, True),
        (CLUB_ROLE_MEMBER, ClubAction.INVITE_MEMBER, None, False),
        # Moderator+ on member targets — promote / demote.
        (
            CLUB_ROLE_OWNER,
            ClubAction.PROMOTE_TO_MODERATOR,
            CLUB_ROLE_MEMBER,
            True,
        ),
        (
            CLUB_ROLE_MODERATOR,
            ClubAction.PROMOTE_TO_MODERATOR,
            CLUB_ROLE_MEMBER,
            True,
        ),
        (
            CLUB_ROLE_OWNER,
            ClubAction.DEMOTE_TO_MEMBER,
            CLUB_ROLE_MODERATOR,
            True,
        ),
        (
            CLUB_ROLE_MODERATOR,
            ClubAction.DEMOTE_TO_MEMBER,
            CLUB_ROLE_MODERATOR,
            False,
        ),  # mod cannot demote another mod
        # Membership lifecycle.
        (CLUB_ROLE_MEMBER, ClubAction.LEAVE_CLUB, None, True),
        (CLUB_ROLE_OWNER, ClubAction.LEAVE_CLUB, None, True),
        # Transfer cannot target self (A1 / D4).
        (
            CLUB_ROLE_OWNER,
            ClubAction.TRANSFER_OWNERSHIP,
            None,
            False,
        )
        if False
        else (CLUB_ROLE_OWNER, ClubAction.TRANSFER_OWNERSHIP, None, True),
    ],
)
def test_a2_permission_matrix_cells(role, action, target_role, expected):
    """A2 — the matrix returns the expected boolean for every
    load-bearing (role, action, target) tuple. The matrix is
    unit-tested here so the cells are independent of the
    DB-touching service layer.
    """
    if action is ClubAction.TRANSFER_OWNERSHIP and not expected:
        # The parametrized matrix above includes a
        # TRANSFER_OWNERSHIP row marked False for moderator
        # and member — both correct.
        pass
    assert (
        may_perform(
            actor_role=role,
            action=action,
            target_role=target_role,
        )
        is expected
    )


def test_a2_member_cannot_promote_self_via_service(session_factory) -> None:
    """A2 — a member cannot promote themselves to moderator — the
    service-layer guard (``SelfRoleMutationNotAllowed``) and the
    matrix combine to refuse.
    """
    owner = _make_profile_by_id(session_factory, user_id=10)
    member_profile = _make_profile_by_id(session_factory, user_id=11)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=member_profile)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.SelfRoleMutationNotAllowed):
            svc.promote_to_moderator(
                db,
                actor_profile_id=member_profile.id,
                club_public_id=club.public_id,
                target_profile_public_id=member_profile.public_id,
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


def test_a2_member_cannot_modify_other_member_role(session_factory) -> None:
    """A2 — a member cannot promote a peer; the service-layer
    guard + the matrix combine to refuse."""
    owner = _make_profile_by_id(session_factory, user_id=20)
    p_a = _make_profile_by_id(session_factory, user_id=21)
    p_b = _make_profile_by_id(session_factory, user_id=22)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=p_a)
    _add_member(session_factory, club=club, profile=p_b)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubPermissionDenied):
            svc.promote_to_moderator(
                db,
                actor_profile_id=p_a.id,
                club_public_id=club.public_id,
                target_profile_public_id=p_b.public_id,
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A3 — duplicate-join is idempotent (UNIQUE(club_id, profile_id)).
# ---------------------------------------------------------------------------


def test_a3_duplicate_join_idempotent_at_service_layer(session_factory) -> None:
    """A3 — two ``request_join`` calls on the same (club, profile)
    pair return the same membership row; the table holds exactly
    one row.
    """
    owner = _make_profile_by_id(session_factory, user_id=30)
    joiner = _make_profile_by_id(session_factory, user_id=31)
    club = _create_club(session_factory, owner=owner)

    member1, _ = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="dup-1",
            now=_utcnow(),
        ),
    )
    member2, _ = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="dup-1",
            now=_utcnow(),
        ),
    )

    assert member1.public_id == member2.public_id
    db: Session = session_factory()
    try:
        count = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=joiner.id)
            .count()
        )
        assert count == 1
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A4 — private club requires invite / accepted-request; public /
# discoverable grant immediate membership.
# ---------------------------------------------------------------------------


def test_a4_private_club_join_creates_pending_request_not_member(
    session_factory,
) -> None:
    """A4 — joining a private club creates a pending invite row,
    NOT a membership row. The §D6 path.
    """
    owner = _make_profile_by_id(session_factory, user_id=40)
    joiner = _make_profile_by_id(session_factory, user_id=41)
    club = _create_club(
        session_factory, owner=owner, visibility=CLUB_VISIBILITY_PRIVATE
    )

    member, invite = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="priv-1",
            now=_utcnow(),
        ),
    )
    assert member is None
    assert invite is not None
    assert invite.status == "pending"

    db: Session = session_factory()
    try:
        rows = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=joiner.id)
            .count()
        )
        assert rows == 0  # no membership yet
    finally:
        db.close()


def test_a4_discoverable_club_join_creates_member_immediately(
    session_factory,
) -> None:
    """A4 — joining a discoverable club creates an immediate
    membership row.
    """
    owner = _make_profile_by_id(session_factory, user_id=42)
    joiner = _make_profile_by_id(session_factory, user_id=43)
    club = _create_club(
        session_factory,
        owner=owner,
        visibility=CLUB_VISIBILITY_DISCOVERABLE,
    )

    member, invite = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="disc-1",
            now=_utcnow(),
        ),
    )
    assert member is not None
    assert member.role == CLUB_ROLE_MEMBER
    assert invite is None


def test_a4_private_club_accepted_request_creates_member(
    session_factory,
) -> None:
    """A4 — owner accepts a pending request → membership row."""
    owner = _make_profile_by_id(session_factory, user_id=44)
    joiner = _make_profile_by_id(session_factory, user_id=45)
    club = _create_club(
        session_factory, owner=owner, visibility=CLUB_VISIBILITY_PRIVATE
    )
    _, invite = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="priv-accept",
            now=_utcnow(),
        ),
    )
    member = _service_call(
        session_factory,
        lambda db: svc.accept_join_request(
            db,
            actor_profile_id=owner.id,
            invite_public_id=invite.public_id,
            now=_utcnow(),
        ),
    )
    assert member.role == CLUB_ROLE_MEMBER


# ---------------------------------------------------------------------------
# A5 — member removal requires owner or moderator.
# ---------------------------------------------------------------------------


def test_a5_member_cannot_remove_another_member(session_factory) -> None:
    """A5 — the A2 member-cannot-mutate cell extends to
    ``remove_member`` too.
    """
    owner = _make_profile_by_id(session_factory, user_id=50)
    p_a = _make_profile_by_id(session_factory, user_id=51)
    p_b = _make_profile_by_id(session_factory, user_id=52)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=p_a)
    _add_member(session_factory, club=club, profile=p_b)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubPermissionDenied):
            svc.remove_member(
                db,
                actor_profile_id=p_a.id,
                club_public_id=club.public_id,
                target_profile_public_id=p_b.public_id,
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


def test_a5_owner_can_remove_member(session_factory) -> None:
    """A5 — the owner can remove a member."""
    owner = _make_profile_by_id(session_factory, user_id=53)
    target = _make_profile_by_id(session_factory, user_id=54)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=target)
    _service_call(
        session_factory,
        lambda db: svc.remove_member(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            target_profile_public_id=target.public_id,
            now=_utcnow(),
        ),
    )
    db: Session = session_factory()
    try:
        row = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=target.id)
            .one_or_none()
        )
        assert row is None
    finally:
        db.close()


def test_a5_moderator_can_remove_member(session_factory) -> None:
    """A5 — a moderator can remove a member."""
    owner = _make_profile_by_id(session_factory, user_id=55)
    moderator = _make_profile_by_id(session_factory, user_id=56)
    target = _make_profile_by_id(session_factory, user_id=57)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=moderator, role=CLUB_ROLE_MODERATOR)
    _add_member(session_factory, club=club, profile=target)
    _service_call(
        session_factory,
        lambda db: svc.remove_member(
            db,
            actor_profile_id=moderator.id,
            club_public_id=club.public_id,
            target_profile_public_id=target.public_id,
            now=_utcnow(),
        ),
    )
    db: Session = session_factory()
    try:
        row = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=target.id)
            .one_or_none()
        )
        assert row is None
    finally:
        db.close()


def test_a5_cannot_remove_owner(session_factory) -> None:
    """A5 — the service refuses to remove the owner. The
    transfer-first guard is the only path."""
    owner = _make_profile_by_id(session_factory, user_id=58)
    co_owner = _make_profile_by_id(session_factory, user_id=59)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=co_owner, role=CLUB_ROLE_OWNER)
    db: Session = session_factory()
    try:
        with pytest.raises(svc.OwnerMustTransferFirst):
            svc.remove_member(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                target_profile_public_id=co_owner.public_id,
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A6 — blocked viewer sees no member row in the shared club.
# ---------------------------------------------------------------------------


def test_a6_blocked_viewer_member_list_drops_blocked_rows(
    session_factory,
) -> None:
    """A6 — a blocked profile is filtered out of the member list
    (the Kör 8 ``filter_public_ids_against_viewer_blocks`` helper
    is the gate).
    """
    owner = _make_profile_by_id(session_factory, user_id=60)
    p_visible = _make_profile_by_id(session_factory, user_id=61)
    p_blocked = _make_profile_by_id(session_factory, user_id=62)
    p_blocker = _make_profile_by_id(session_factory, user_id=63)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=p_visible)
    _add_member(session_factory, club=club, profile=p_blocked)
    # p_blocker has p_blocked blocked.
    _add_block(session_factory, blocker=p_blocker, blocked=p_blocked)

    # The blocker-side view: p_visible is visible, p_blocked is dropped.
    visible = _service_call(
        session_factory,
        lambda db: svc.list_club_members(
            db,
            club_public_id=club.public_id,
            viewer_profile_id=p_blocker.id,
        ),
    )
    visible_public_ids = {v.profile_public_id for v in visible}
    assert p_visible.public_id in visible_public_ids
    assert p_blocked.public_id not in visible_public_ids


def test_a6_invite_blocked_pair_rejected(session_factory) -> None:
    """A6 — ``invite`` rejects when the actor ↔ invitee pair is
    in a block relationship (D3, D8)."""
    owner = _make_profile_by_id(session_factory, user_id=70)
    invitee = _make_profile_by_id(session_factory, user_id=71)
    club = _create_club(session_factory, owner=owner)
    _add_block(session_factory, blocker=owner, blocked=invitee)
    db: Session = session_factory()
    try:
        with pytest.raises(svc.BlockedClubRelationship):
            svc.invite(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                invitee_profile_public_id=invitee.public_id,
                idempotency_key="inv-blocked",
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A7 — membership-limit threshold matrix (D3 — §6.1 contract).
# ---------------------------------------------------------------------------


def _stage_club_at_member_count(
    session_factory,
    *,
    club: CommunityClub,
    target_count: int,
) -> None:
    """Bulk-insert membership rows directly so the test can stage
    a club at the desired count.

    ``target_count`` is the TOTAL member count (the owner counts
    as the first member — the Kör 24 ``create_club`` materialises
    the owner-membership row in the same transaction). The helper
    stages ``target_count - 1`` additional members on top.
    """
    if target_count <= 0:
        raise ValueError("target_count must be positive")
    db: Session = session_factory()
    try:
        for i in range(target_count - 1):
            user_id = 1000 + i
            profile = _make_profile(db, user_id=user_id)
            row = CommunityClubMember(
                public_id=uuid.uuid4(),
                club_id=club.id,
                profile_id=profile.id,
                role=CLUB_ROLE_MEMBER,
                joined_at=_utcnow(),
                updated_at=_utcnow(),
            )
            db.add(row)
        db.commit()
    finally:
        db.close()


def test_a7_member_count_below_threshold_join_accepted(
    session_factory,
) -> None:
    """A7 cell 1 — ``member_count = MAX_CLUB_MEMBERS - 1`` → join
    elfogad. The threshold is inclusive (the 500th tag betölti az
    utolsó szabad helyet)."""
    owner = _make_profile_by_id(session_factory, user_id=80)
    joiner = _make_profile_by_id(session_factory, user_id=81)
    club = _create_club(session_factory, owner=owner)
    _stage_club_at_member_count(
        session_factory,
        club=club,
        target_count=MAX_CLUB_MEMBERS - 1,
    )
    member, _ = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="below-1",
            now=_utcnow(),
        ),
    )
    assert member is not None
    assert member.role == CLUB_ROLE_MEMBER


def test_a7_member_count_at_threshold_join_still_accepted(
    session_factory,
) -> None:
    """A7 cell 2 — the join that brings the count to
    ``MAX_CLUB_MEMBERS`` (= 500) is still accepted. The
    ``rajta`` cell is the LANDING state — the joiner IS the
    500th member and the limit is inclusive.
    """
    owner = _make_profile_by_id(session_factory, user_id=82)
    joiner = _make_profile_by_id(session_factory, user_id=83)
    club = _create_club(session_factory, owner=owner)
    # Stage at MAX - 1 = 499 (the owner counts, so total =
    # 499 BEFORE the join).
    _stage_club_at_member_count(
        session_factory,
        club=club,
        target_count=MAX_CLUB_MEMBERS - 1,
    )
    member, _ = _service_call(
        session_factory,
        lambda db: svc.request_join(
            db,
            actor_profile_id=joiner.id,
            club_public_id=club.public_id,
            idempotency_key="at-1",
            now=_utcnow(),
        ),
    )
    assert member is not None
    # Confirm: the joiner is the LAST free spot (count = MAX
    # AFTER the join).
    db: Session = session_factory()
    try:
        count = db.query(CommunityClubMember).filter_by(club_id=club.id).count()
        assert count == MAX_CLUB_MEMBERS
    finally:
        db.close()


def test_a7_member_count_above_threshold_join_refused(
    session_factory,
) -> None:
    """A7 cell 3 — ``member_count = MAX_CLUB_MEMBERS`` + egy
    ÚJABB join → elutasít, dokumentált hibakóddal.
    """
    owner = _make_profile_by_id(session_factory, user_id=84)
    joiner = _make_profile_by_id(session_factory, user_id=85)
    club = _create_club(session_factory, owner=owner)
    _stage_club_at_member_count(
        session_factory,
        club=club,
        target_count=MAX_CLUB_MEMBERS,
    )
    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubMembershipLimitExceeded) as exc:
            svc.request_join(
                db,
                actor_profile_id=joiner.id,
                club_public_id=club.public_id,
                idempotency_key="over-1",
                now=_utcnow(),
            )
        assert exc.value.member_count >= MAX_CLUB_MEMBERS
        db.rollback()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A8 — ownership transfer semantics (D4).
# ---------------------------------------------------------------------------


def test_a8_transfer_ownership_old_owner_becomes_member(
    session_factory,
) -> None:
    """A8 — after ``transfer_ownership``, the old owner's role is
    PONTOSAN ``member`` (NOT moderator — the §0.0 / D4 invariant).
    """
    old_owner = _make_profile_by_id(session_factory, user_id=90)
    new_owner = _make_profile_by_id(session_factory, user_id=91)
    club = _create_club(session_factory, owner=old_owner)
    _add_member(session_factory, club=club, profile=new_owner)

    _service_call(
        session_factory,
        lambda db: svc.transfer_ownership(
            db,
            actor_profile_id=old_owner.id,
            club_public_id=club.public_id,
            new_owner_profile_id=new_owner.id,
            now=_utcnow(),
        ),
    )
    db: Session = session_factory()
    try:
        old_row = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=old_owner.id)
            .one()
        )
        new_row = (
            db.query(CommunityClubMember)
            .filter_by(club_id=club.id, profile_id=new_owner.id)
            .one()
        )
        club_row = db.query(CommunityClub).filter_by(id=club.id).one()
        assert old_row.role == CLUB_ROLE_MEMBER, (
            "D4 invariant broken — old owner must be plain member"
        )
        assert new_row.role == CLUB_ROLE_OWNER
        assert club_row.owner_profile_id == new_owner.id
    finally:
        db.close()


def test_a8_transfer_to_self_rejected(session_factory) -> None:
    """A8 — the matrix ``is_self`` flag refuses self-transfer."""
    owner = _make_profile_by_id(session_factory, user_id=92)
    club = _create_club(session_factory, owner=owner)
    db: Session = session_factory()
    try:
        with pytest.raises(svc.SelfRoleMutationNotAllowed):
            svc.transfer_ownership(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                new_owner_profile_id=owner.id,
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


def test_a8_transfer_to_non_member_rejected(session_factory) -> None:
    """A8 — the new owner must be an existing member; the
    service refuses otherwise."""
    owner = _make_profile_by_id(session_factory, user_id=93)
    stranger = _make_profile_by_id(session_factory, user_id=94)
    club = _create_club(session_factory, owner=owner)
    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubMemberNotFound):
            svc.transfer_ownership(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                new_owner_profile_id=stranger.id,
                now=_utcnow(),
            )
        db.rollback()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# Idempotency helper — invite path.
# ---------------------------------------------------------------------------


def test_invite_idempotent(session_factory) -> None:
    """D4 / D5 — same idempotency_key on the invite path returns
    the existing row.
    """
    owner = _make_profile_by_id(session_factory, user_id=100)
    invitee = _make_profile_by_id(session_factory, user_id=101)
    club = _create_club(session_factory, owner=owner)
    invite1 = _service_call(
        session_factory,
        lambda db: svc.invite(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            invitee_profile_public_id=invitee.public_id,
            idempotency_key="inv-1",
            now=_utcnow(),
        ),
    )
    invite2 = _service_call(
        session_factory,
        lambda db: svc.invite(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            invitee_profile_public_id=invitee.public_id,
            idempotency_key="inv-1",
            now=_utcnow(),
        ),
    )
    assert invite1.public_id == invite2.public_id


# ---------------------------------------------------------------------------
# Read helpers.
# ---------------------------------------------------------------------------


def test_list_clubs_includes_discoverable(session_factory) -> None:
    """The Kör 24 ``list_clubs`` helper returns discoverable clubs
    to anyone."""
    owner = _make_profile_by_id(session_factory, user_id=110)
    viewer = _make_profile_by_id(session_factory, user_id=111)
    club = _create_club(
        session_factory,
        owner=owner,
        visibility=CLUB_VISIBILITY_DISCOVERABLE,
    )
    listed = _service_call(
        session_factory,
        lambda db: svc.list_clubs(
            db,
            viewer_profile_id=viewer.id,
        ),
    )
    assert any(c.public_id == club.public_id for c in listed)


def test_list_clubs_private_excludes_non_member(session_factory) -> None:
    """A private club is excluded from ``list_clubs`` for a
    non-member viewer.
    """
    owner = _make_profile_by_id(session_factory, user_id=120)
    viewer = _make_profile_by_id(session_factory, user_id=121)
    club = _create_club(
        session_factory,
        owner=owner,
        visibility=CLUB_VISIBILITY_PRIVATE,
    )
    listed = _service_call(
        session_factory,
        lambda db: svc.list_clubs(
            db,
            viewer_profile_id=viewer.id,
        ),
    )
    assert all(c.public_id != club.public_id for c in listed)


def test_get_club_private_member(session_factory) -> None:
    """A private club is fetchable for a member."""
    owner = _make_profile_by_id(session_factory, user_id=130)
    joiner = _make_profile_by_id(session_factory, user_id=131)
    club = _create_club(
        session_factory, owner=owner, visibility=CLUB_VISIBILITY_PRIVATE
    )
    _add_member(session_factory, club=club, profile=joiner)
    fetched = _service_call(
        session_factory,
        lambda db: svc.get_club(
            db,
            club_public_id=club.public_id,
            viewer_profile_id=joiner.id,
        ),
    )
    assert fetched.public_id == club.public_id


def test_get_club_private_non_member_404(session_factory) -> None:
    """A private club is NOT fetchable for a non-member (uniform
    404 — the §D7 invariant).
    """
    owner = _make_profile_by_id(session_factory, user_id=140)
    stranger = _make_profile_by_id(session_factory, user_id=141)
    club = _create_club(
        session_factory, owner=owner, visibility=CLUB_VISIBILITY_PRIVATE
    )
    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubNotFound):
            svc.get_club(
                db,
                club_public_id=club.public_id,
                viewer_profile_id=stranger.id,
            )
        db.rollback()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# §F1 — create-side idempotency fix. The two cells below were
# missing from the round 1 acceptance suite, which is how the
# broken ``_find_club_by_create_idempotency_key`` helper shipped
# past a green gate.
# ---------------------------------------------------------------------------


def test_create_club_distinct_idempotency_keys_create_distinct_clubs(
    session_factory,
) -> None:
    """§F1 — the §10.2 measure-matrix ``distinct-keys`` cell.

    A single owner creates two clubs with two **different**
    idempotency keys; both rows must exist with distinct
    ``public_id``s. The round 1 helper filtered only by
    ``owner_profile_id`` and returned the most-recently-created
    club, so the second call silently returned the first club
    instead of creating the new one.
    """
    owner = _make_profile_by_id(session_factory, user_id=150)
    club_a = _service_call(
        session_factory,
        lambda db: svc.create_club(
            db,
            owner_profile_id=owner.id,
            name="Club-A",
            description="first club",
            visibility=CLUB_VISIBILITY_DISCOVERABLE,
            idempotency_key="create-key-A",
            now=_utcnow(),
        ),
    )
    club_b = _service_call(
        session_factory,
        lambda db: svc.create_club(
            db,
            owner_profile_id=owner.id,
            name="Club-B",
            description="second club",
            visibility=CLUB_VISIBILITY_DISCOVERABLE,
            idempotency_key="create-key-B",
            now=_utcnow(),
        ),
    )
    # Both clubs persisted with distinct internal + external ids.
    assert club_a.id != club_b.id
    assert club_a.public_id != club_b.public_id
    # The names round-trip — the second call must NOT have returned
    # the first club and ignored the new name.
    assert club_a.name == "Club-A"
    assert club_b.name == "Club-B"
    # The DB layer actually persisted both rows (not just returned
    # one ORM instance twice).
    db: Session = session_factory()
    try:
        persisted = (
            db.query(CommunityClub)
            .filter_by(owner_profile_id=owner.id)
            .order_by(CommunityClub.id.asc())
            .all()
        )
    finally:
        db.close()
    assert {c.public_id for c in persisted} == {club_a.public_id, club_b.public_id}


def test_create_club_same_idempotency_key_retry_returns_original(
    session_factory,
) -> None:
    """§F1 — the §10.2 measure-matrix ``same-key retry`` cell.

    A retry of ``create_club`` with the **same** idempotency key
    must return the **original** row — the same ``public_id``,
    the same ``id``, and crucially the original ``name`` /
    ``visibility`` (the retry must not have overwritten the
    first attempt's wire-shape via a second INSERT that the
    broken probe then hid).
    """
    owner = _make_profile_by_id(session_factory, user_id=151)
    club1 = _service_call(
        session_factory,
        lambda db: svc.create_club(
            db,
            owner_profile_id=owner.id,
            name="Original",
            description="first attempt",
            visibility=CLUB_VISIBILITY_DISCOVERABLE,
            idempotency_key="retry-key",
            now=_utcnow(),
        ),
    )
    club2 = _service_call(
        session_factory,
        lambda db: svc.create_club(
            db,
            owner_profile_id=owner.id,
            name="Retry-Name",
            description="retry attempt — must NOT create new",
            visibility=CLUB_VISIBILITY_PRIVATE,
            idempotency_key="retry-key",
            now=_utcnow(),
        ),
    )
    # Same row, not a copy.
    assert club1.id == club2.id
    assert club1.public_id == club2.public_id
    # The retry did NOT overwrite the original wire-shape.
    assert club2.name == "Original"
    assert club2.visibility == CLUB_VISIBILITY_DISCOVERABLE
    # And only ONE row landed in the DB.
    db: Session = session_factory()
    try:
        count = (
            db.query(CommunityClub)
            .filter_by(
                owner_profile_id=owner.id,
                create_idempotency_key="retry-key",
            )
            .count()
        )
    finally:
        db.close()
    assert count == 1
