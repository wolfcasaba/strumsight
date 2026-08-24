"""E09-R25 — Club content service acceptance tests (ADR 0420).

Covers every cell of the brief §6 acceptance matrix that lands
on the backend service layer, plus the §6.1 measure-matrix
regression cases:

* A1 — a non-member cannot read the club feed; ``list_club_feed``
  raises :class:`ClubNotVisible` and the cursor never carries a
  row past the membership probe.
* A3 — pin / unpin / end-challenge permission check; a
  moderator of a DIFFERENT club cannot pin inside this club
  (the §5.2 cross-club invariant).
* A4 — pin-limit (``MAX_CLUB_PINNED_POSTS``); the
  §6.1 valódi-sértés próba drops the limit check and asserts
  the cell turns RED.
* A5 — non-member is rejected at the club-challenge create
  boundary (the §A5 IDOR guarantee).
* A6 — block relation drops the author from the pinned /
  challenges projection (the §Kör 8 / §A6 invariant).
* A7 — club feed pagination is stable; no duplicate row across
  two consecutive pages.

The fixtures follow the Kör 22 / Kör 23 / Kör 24 pattern — own
SQLite engine + alembic upgrade head. The inline
``community_club_pinned_posts`` table now ships with its own
alembic migration (E09-R25 follow-up — the §0.0d addendum) and is
registered on the project-wide ``Base.metadata``, so the fixture
relies on the alembic upgrade alone to materialise it.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command as alembic_command
from app.community.feed.club_feed import (
    ClubFeedPage,
    ClubNotVisible,
    list_club_feed,
)
from app.community.models.challenge import (
    CHALLENGE_TYPE_CLUB,
)
from app.community.models.club import (
    CLUB_ROLE_MEMBER,
    CLUB_ROLE_MODERATOR,
    CLUB_VISIBILITY_DISCOVERABLE,
    CommunityClub,
    CommunityClubMember,
)
from app.community.models.post import (
    MODERATION_STATE_VISIBLE,
    CommunityPost,
)
from app.community.models.profile import CommunityProfile
from app.community.models.safety_relationships import CommunityBlock
from app.community.services import club_content_service as svc
from app.community.services.club_content_service import (
    MAX_CLUB_PINNED_POSTS,
    create_club_challenge,
    end_club_challenge,
    list_club_challenges,
    list_club_pinned,
    pin_post,
)
from app.database import enable_sqlite_foreign_keys

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — engine + session factory (the Kör 22 / Kör 23 / Kör 24
# pattern). The fixture adds the ``community_club_pinned_posts``
# table to the metadata BEFORE the alembic upgrade + create_all
# chain, so the table is reachable from the test session.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    """File-backed SQLite engine with the full alembic chain applied.

    The fixture runs ``alembic upgrade head`` against a private
    SQLite database; the migration chain — including the E09-R25
    ``e09_r25_0019_community_club_pinned_posts`` migration — is the
    sole schema-authoritative source. The inline
    ``community_club_pinned_posts`` table is registered on the
    project-wide ``Base.metadata`` so the migration-contract guard
    (``test_upgrade_head_matches_current_orm_schema``) sees it as
    part of the expected schema (the §0.0d review addendum).
    """
    db_path = tmp_path / "club_content.db"
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
# Helpers — users, profiles, posts, clubs, members, blocks.
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

    Mirrors the Kör 24 ``_make_profile`` helper.
    """
    _insert_user(db, user_id, f"u{user_id}@s.test")
    db.commit()
    profile = CommunityProfile(user_id=user_id)
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return profile


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


def _create_club(
    session_factory,
    *,
    owner: CommunityProfile,
    visibility: str = CLUB_VISIBILITY_DISCOVERABLE,
) -> CommunityClub:
    """Create a club via the service layer (Kör 24 path)."""
    from app.community.services.club_service import create_club

    db: Session = session_factory()
    try:
        club = create_club(
            db,
            owner_profile_id=owner.id,
            name=f"Club-{owner.id}-{uuid.uuid4().hex[:6]}",
            description="description",
            visibility=visibility,
            idempotency_key=f"create-{uuid.uuid4().hex}",
            now=_utcnow(),
        )
        db.commit()
        db.refresh(club)
        return club
    finally:
        db.close()


def _add_member(
    session_factory,
    *,
    club: CommunityClub,
    profile: CommunityProfile,
    role: str = CLUB_ROLE_MEMBER,
) -> CommunityClubMember:
    """Insert a membership row directly."""
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


def _create_post(
    session_factory,
    *,
    author: CommunityProfile,
    club: CommunityClub | None,
    body: str = "hello world",
    audience: str = "public",
    moderation_state: str = MODERATION_STATE_VISIBLE,
    deleted: bool = False,
) -> CommunityPost:
    """Insert a post row directly (bypasses the wire)."""
    db: Session = session_factory()
    try:
        post = CommunityPost(
            public_id=uuid.uuid4(),
            profile_id=author.id,
            audience=audience,
            club_id=club.id if club is not None else None,
            body=body,
            moderation_state=moderation_state,
            deleted_at=_utcnow() if deleted else None,
        )
        db.add(post)
        db.commit()
        db.refresh(post)
        return post
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
# A1 — non-member cannot read the club feed.
# ---------------------------------------------------------------------------


def test_a1_non_member_cannot_list_club_feed(session_factory) -> None:
    """A1 — a non-member's ``list_club_feed`` call raises
    :class:`ClubNotVisible`. The membership probe rejects the
    request before any post is materialised.
    """
    owner = _make_profile_by_id(session_factory, user_id=1)
    outsider = _make_profile_by_id(session_factory, user_id=2)
    club = _create_club(session_factory, owner=owner)
    _create_post(session_factory, author=owner, club=club)

    db: Session = session_factory()
    try:
        with pytest.raises(ClubNotVisible):
            list_club_feed(
                db,
                viewer_profile_id=outsider.id,
                club_public_id=club.public_id,
                cursor=None,
                page_size=25,
                cursor_secret="test-secret",
            )
    finally:
        db.close()


def test_a1_real_violation_probe_drop_membership_check(
    session_factory, monkeypatch
) -> None:
    """§6.1 valódi-sértés próba for A1 — drop the membership
    probe and assert a non-member now receives a feed page
    (the A1 cell turns RED). The probe demonstrates the gate
    is load-bearing.

    The fixture patches
    ``club_feed._resolve_visible_club_for_member`` to skip
    the membership check; the rest of the projection still
    runs. Without the gate, the outsider sees the owner's
    club-scoped post — proving the membership probe is the
    only thing standing between the outsider and the feed.
    """
    owner = _make_profile_by_id(session_factory, user_id=3)
    outsider = _make_profile_by_id(session_factory, user_id=4)
    club = _create_club(session_factory, owner=owner)
    _create_post(session_factory, author=owner, club=club)

    from app.community.feed import club_feed

    def skip_membership(db, *, club_public_id, viewer_profile_id):
        return (
            db.query(CommunityClub)
            .filter_by(public_id=club_public_id, deleted_at=None)
            .one()
        )

    monkeypatch.setattr(
        club_feed,
        "_resolve_visible_club_for_member",
        skip_membership,
    )

    db: Session = session_factory()
    try:
        page = list_club_feed(
            db,
            viewer_profile_id=outsider.id,
            club_public_id=club.public_id,
            cursor=None,
            page_size=25,
            cursor_secret="test-secret",
        )
        assert isinstance(page, ClubFeedPage)
        assert len(page.items) == 1
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A3 — pin / unpin permission check; cross-club moderator guard.
# ---------------------------------------------------------------------------


def test_a3_member_cannot_pin_post(session_factory) -> None:
    """A3 — a member (not owner / moderator) cannot pin a post
    inside the club. The permission check raises
    :class:`ClubPinForbidden`.
    """
    owner = _make_profile_by_id(session_factory, user_id=5)
    member = _make_profile_by_id(session_factory, user_id=6)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=member, role=CLUB_ROLE_MEMBER)
    post = _create_post(session_factory, author=owner, club=club)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubPinForbidden):
            pin_post(
                db,
                actor_profile_id=member.id,
                club_public_id=club.public_id,
                post_public_id=post.public_id,
                now=_utcnow(),
            )
    finally:
        db.close()


def test_a3_other_club_moderator_cannot_pin_here(session_factory) -> None:
    """A3 §5.2 — a moderator of a DIFFERENT club cannot pin a
    post inside THIS club. The cross-club guard anchors the
    role check to THIS club's membership row.

    The actor (``owner_b``) is the owner / moderator of
    ``club_b`` only — they are NOT a member of ``club_a``.
    The membership probe rejects the actor before the role
    check ever runs.
    """
    owner_a = _make_profile_by_id(session_factory, user_id=7)
    club_a = _create_club(session_factory, owner=owner_a)
    owner_b = _make_profile_by_id(session_factory, user_id=8)
    _create_club(session_factory, owner=owner_b)
    # owner_b is the OWNER of club_b — the Kör 24
    # ``create_club`` service already inserts the owner as a
    # member with role ``owner`` (the §D4 invariant). owner_b
    # is NOT a member of club_a. The cross-club guard rejects
    # the actor at the membership probe.
    post = _create_post(session_factory, author=owner_a, club=club_a)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubPinForbidden):
            pin_post(
                db,
                actor_profile_id=owner_b.id,
                club_public_id=club_a.public_id,
                post_public_id=post.public_id,
                now=_utcnow(),
            )
    finally:
        db.close()


def test_a3_owner_can_pin_post(session_factory) -> None:
    """A3 — the owner CAN pin a post inside their own club."""
    owner = _make_profile_by_id(session_factory, user_id=9)
    club = _create_club(session_factory, owner=owner)
    post = _create_post(session_factory, author=owner, club=club)

    db: Session = session_factory()
    try:
        row = pin_post(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
        )
        db.commit()
        assert row.post_public_id == post.public_id
    finally:
        db.close()


def test_a3_moderator_of_same_club_can_pin_post(session_factory) -> None:
    """A3 — a moderator of THIS club CAN pin a post inside it."""
    owner = _make_profile_by_id(session_factory, user_id=10)
    moderator = _make_profile_by_id(session_factory, user_id=11)
    club = _create_club(session_factory, owner=owner)
    _add_member(
        session_factory,
        club=club,
        profile=moderator,
        role=CLUB_ROLE_MODERATOR,
    )
    post = _create_post(session_factory, author=owner, club=club)

    db: Session = session_factory()
    try:
        row = pin_post(
            db,
            actor_profile_id=moderator.id,
            club_public_id=club.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
        )
        db.commit()
        assert row.post_public_id == post.public_id
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A4 — pin-limit (MAX_CLUB_PINNED_POSTS).
# ---------------------------------------------------------------------------


def test_a4_pin_limit_enforced(session_factory) -> None:
    """A4 — once a club has ``MAX_CLUB_PINNED_POSTS`` pinned
    posts, the next ``pin_post`` raises
    :class:`ClubPinLimitExceeded`.
    """
    owner = _make_profile_by_id(session_factory, user_id=12)
    club = _create_club(session_factory, owner=owner)
    posts = [
        _create_post(session_factory, author=owner, club=club, body=f"post-{i}")
        for i in range(MAX_CLUB_PINNED_POSTS + 1)
    ]

    db: Session = session_factory()
    try:
        for i in range(MAX_CLUB_PINNED_POSTS):
            pin_post(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                post_public_id=posts[i].public_id,
                now=_utcnow(),
            )
            db.commit()
        with pytest.raises(svc.ClubPinLimitExceeded):
            pin_post(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                post_public_id=posts[MAX_CLUB_PINNED_POSTS].public_id,
                now=_utcnow(),
            )
    finally:
        db.close()


def test_a4_real_violation_probe_drop_pin_limit(session_factory, monkeypatch) -> None:
    """§6.1 valódi-sértés próba for A4 — drop the pin-limit
    check and assert the cell turns RED (an over-cap pin
    succeeds).

    The probe raises :data:`MAX_CLUB_PINNED_POSTS` to a
    unreachable value so the limit branch never trips (the
    service's ``if current_count >= MAX_CLUB_PINNED_POSTS``
    check is always False). The probe pins
    ``MAX_CLUB_PINNED_POSTS + 2`` posts and asserts all of
    them land in the junction table.
    """
    owner = _make_profile_by_id(session_factory, user_id=13)
    club = _create_club(session_factory, owner=owner)
    posts = [
        _create_post(session_factory, author=owner, club=club, body=f"post-{i}")
        for i in range(MAX_CLUB_PINNED_POSTS + 2)
    ]

    monkeypatch.setattr(svc, "MAX_CLUB_PINNED_POSTS", 10_000)

    db: Session = session_factory()
    try:
        for post in posts:
            pin_post(
                db,
                actor_profile_id=owner.id,
                club_public_id=club.public_id,
                post_public_id=post.public_id,
                now=_utcnow(),
            )
            db.commit()
        # Without the limit, every pin succeeded — the cell is
        # now over MAX_CLUB_PINNED_POSTS, proving the limit
        # guard is load-bearing.
        count = svc._current_pinned_count(db, club_id=club.id)
        assert count == MAX_CLUB_PINNED_POSTS + 2
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A5 — non-member cannot create a club challenge.
# ---------------------------------------------------------------------------


def test_a5_non_member_cannot_create_club_challenge(session_factory) -> None:
    """A5 — a non-member's ``create_club_challenge`` call raises
    :class:`ClubChallengeActorNotMember`. The eligibility gate
    rejects the request before any row is inserted.
    """
    owner = _make_profile_by_id(session_factory, user_id=14)
    outsider = _make_profile_by_id(session_factory, user_id=15)
    club = _create_club(session_factory, owner=owner)

    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubChallengeActorNotMember):
            create_club_challenge(
                db,
                actor_public_id=outsider.public_id,
                club_public_id=club.public_id,
                metric="score",
                difficulty=5,
                starts_at=_utcnow(),
                ends_at=_utcnow() + timedelta(days=7),
                now=_utcnow(),
            )
    finally:
        db.close()


def test_a5_member_creates_club_challenge_with_public_id_str(session_factory) -> None:
    """A5 — a member CAN create a club challenge. The challenge
    row's ``club_id`` column stores the club's ``public_id``
    UUID string form — NOT the internal BigInteger id (the
    §0.0 #1 invariant).
    """
    owner = _make_profile_by_id(session_factory, user_id=16)
    club = _create_club(session_factory, owner=owner)

    db: Session = session_factory()
    try:
        challenge = create_club_challenge(
            db,
            actor_public_id=owner.public_id,
            club_public_id=club.public_id,
            metric="score",
            difficulty=5,
            starts_at=_utcnow(),
            ends_at=_utcnow() + timedelta(days=7),
            now=_utcnow(),
        )
        db.commit()
        # The §0.0 #1 invariant — ``club_id`` is the wire
        # string form of the UUID, NOT the internal bigint.
        assert challenge.club_id == str(club.public_id)
        assert challenge.club_id != str(club.id)
        assert challenge.type == CHALLENGE_TYPE_CLUB
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A6 — block relation drops the author from the pinned /
# challenges projection (the §Kör 8 / §A6 invariant).
# ---------------------------------------------------------------------------


def test_a6_block_drops_author_from_pinned_list(session_factory) -> None:
    """A6 — a member who has blocked the post's author does NOT
    see that author's pinned posts in the club's pinned list
    (the §A6 block filter, mirroring Kör 8 / Kör 13).
    """
    owner = _make_profile_by_id(session_factory, user_id=17)
    member = _make_profile_by_id(session_factory, user_id=18)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=member, role=CLUB_ROLE_MEMBER)
    post = _create_post(session_factory, author=owner, club=club)
    _add_block(session_factory, blocker=member, blocked=owner)

    _service_call(
        session_factory,
        lambda db: pin_post(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
        ),
    )

    db: Session = session_factory()
    try:
        pinned = list_club_pinned(
            db,
            viewer_profile_id=member.id,
            club_public_id=club.public_id,
        )
        assert pinned == ()
    finally:
        db.close()


def test_a6_block_drops_author_from_club_challenges(session_factory) -> None:
    """A6 — a member who has blocked the challenge's author
    does NOT see that author's challenges in the club's
    challenges list (the §A6 block filter).
    """
    owner = _make_profile_by_id(session_factory, user_id=19)
    member = _make_profile_by_id(session_factory, user_id=20)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=member, role=CLUB_ROLE_MEMBER)
    _add_block(session_factory, blocker=member, blocked=owner)

    _service_call(
        session_factory,
        lambda db: create_club_challenge(
            db,
            actor_public_id=owner.public_id,
            club_public_id=club.public_id,
            metric="score",
            difficulty=5,
            starts_at=_utcnow(),
            ends_at=_utcnow() + timedelta(days=7),
            now=_utcnow(),
        ),
    )

    db: Session = session_factory()
    try:
        challenges = list_club_challenges(
            db,
            viewer_profile_id=member.id,
            club_public_id=club.public_id,
            now=_utcnow(),
        )
        assert challenges == ()
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A7 — club feed pagination is stable; no duplicate row across
# two consecutive pages.
# ---------------------------------------------------------------------------


def test_a7_club_feed_pagination_is_stable(session_factory) -> None:
    """A7 — paginating the club feed with cursor tokens returns
    no duplicate rows. The Kör 13 / Kör 25 cursor contract:
    the ``next_cursor`` is the last KEPT row's sort key, and
    the second page's WHERE clause excludes that row.
    """
    owner = _make_profile_by_id(session_factory, user_id=21)
    club = _create_club(session_factory, owner=owner)
    posts = [
        _create_post(
            session_factory,
            author=owner,
            club=club,
            body=f"post-{i}",
        )
        for i in range(3)
    ]

    db: Session = session_factory()
    try:
        page1 = list_club_feed(
            db,
            viewer_profile_id=owner.id,
            club_public_id=club.public_id,
            cursor=None,
            page_size=2,
            cursor_secret="test-secret",
        )
        assert len(page1.items) == 2
        assert page1.next_cursor is not None

        page2 = list_club_feed(
            db,
            viewer_profile_id=owner.id,
            club_public_id=club.public_id,
            cursor=page1.next_cursor,
            page_size=2,
            cursor_secret="test-secret",
        )
        assert len(page2.items) == 1
        # No duplicate post across the two pages (the §A7
        # stability invariant).
        page1_post_ids = {item.post_id for item in page1.items}
        page2_post_ids = {item.post_id for item in page2.items}
        assert page1_post_ids.isdisjoint(page2_post_ids)
        assert page1_post_ids | page2_post_ids == {post.id for post in posts}
        # Total rows = sum of pages; no row was lost.
        assert len(page1_post_ids | page2_post_ids) == len(posts)
    finally:
        db.close()


# ---------------------------------------------------------------------------
# A3 — end-challenge permission check (mirrors pin / unpin).
# ---------------------------------------------------------------------------


def test_a3_member_cannot_end_club_challenge(session_factory) -> None:
    """A3 §5.2 — a member (not owner / moderator) cannot end a
    club challenge. The cross-club moderator guard is
    layered on top of the membership check.
    """
    owner = _make_profile_by_id(session_factory, user_id=22)
    member = _make_profile_by_id(session_factory, user_id=23)
    club = _create_club(session_factory, owner=owner)
    _add_member(session_factory, club=club, profile=member, role=CLUB_ROLE_MEMBER)
    challenge = _service_call(
        session_factory,
        lambda db: create_club_challenge(
            db,
            actor_public_id=owner.public_id,
            club_public_id=club.public_id,
            metric="score",
            difficulty=5,
            starts_at=_utcnow(),
            ends_at=_utcnow() + timedelta(days=7),
            now=_utcnow(),
        ),
    )

    db: Session = session_factory()
    try:
        with pytest.raises(svc.ClubPinForbidden):
            end_club_challenge(
                db,
                actor_profile_id=member.id,
                club_public_id=club.public_id,
                challenge_public_id=challenge.public_id,
                now=_utcnow(),
            )
    finally:
        db.close()


def test_a3_owner_can_end_club_challenge(session_factory) -> None:
    """A3 §5.2 — the owner CAN end a club challenge. The
    ``ends_at`` column is set to ``now`` (the §0.0 #2 implicit-
    state contract).
    """
    owner = _make_profile_by_id(session_factory, user_id=24)
    club = _create_club(session_factory, owner=owner)
    challenge = _service_call(
        session_factory,
        lambda db: create_club_challenge(
            db,
            actor_public_id=owner.public_id,
            club_public_id=club.public_id,
            metric="score",
            difficulty=5,
            starts_at=_utcnow(),
            ends_at=_utcnow() + timedelta(days=7),
            now=_utcnow(),
        ),
    )

    now = _utcnow()
    db: Session = session_factory()
    try:
        ended = end_club_challenge(
            db,
            actor_profile_id=owner.id,
            club_public_id=club.public_id,
            challenge_public_id=challenge.public_id,
            now=now,
        )
        db.commit()
        # The §0.0 #2 invariant — ``ends_at`` is the contract;
        # activation / ending is window-based. SQLite drops
        # tzinfo on read; the test normalizes the read value to
        # UTC-aware for the comparison (the Kör 21 ``_as_utc``
        # precedent).
        ended_at = ended.ends_at
        if ended_at.tzinfo is None:
            ended_at = ended_at.replace(tzinfo=timezone.utc)
        assert ended_at <= now
    finally:
        db.close()
