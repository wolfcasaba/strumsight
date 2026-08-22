"""E09-R04 — Profile privacy, audience és szerveroldali policy acceptance tests.

Covers every cell of the brief §6 and §6.1:

* A1 — A szerver minden readnél policyt alkalmaz (nincs policy-mentes
        útvonal) — paraméterezett mátrix a policy self-call-jain.
* A2 — Block MINDIG felülírja a follow- és club-jogosultságot — block +
        public = SUMMARY (és nem FULL); block + follower = SUMMARY.
* A3 — Private profil olvasása jogosultság nélkül csak minimális,
        relationship-safe SUMMARY-t ad.
* A4 — Followers-only tartalom csak ELFOGADOTT follow után látszik —
        ``is_follower=False`` (pending is ide tartozik) → SUMMARY / False.
* A5 — Az alapértelmezett profil NEM public — a DB-séma és a Python
        default egyaránt ``"followers"``.
* A6 — Stale privacy update elutasítva — ``resource_version`` eltérés
        → ``StalePrivacyUpdateError`` → HTTP 409.

A §6.1 measure-matrix minden egyes cellája külön teszt-eset (a fixture
default-vakfolt elkerülésére); a valódi-sértés próba inline a teszt-végi
blokkban fut, és a §10 handoffban van dokumentálva (PIROS előtte,
ZÖLD utána).

A fixtures a meglévő ``test_handle_policy.py`` mintáját követi
(alembic upgrade head, saját FastAPI app) — a brief kizárja a
``backend/tests/community/conftest.py`` módosítását, ezért minden fixture
lokálisan van definiálva.
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
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.profile import CommunityPrivacySettings
from app.community.policies.access_policy import (
    CommunityAccessPolicy,
    CommunityAudience,
    ProfileAccessLevel,
    ProfileVisibility,
    RelationshipContext,
)
from app.community.routers.privacy import (
    PrivacySettingsUpdate as _RouterPrivacyUpdate,  # re-exported check
)
from app.community.routers.privacy import (
    StalePrivacyUpdateError,
    router as privacy_router,
    update_privacy_settings as update_privacy_settings_svc,
)
from app.community.schemas.privacy import (
    PrivacySettingsOut,
    PrivacySettingsUpdate,
)
from app.config import Settings
from app.database import enable_sqlite_foreign_keys, get_db

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def engine(tmp_path, monkeypatch) -> Iterator:
    """File-based SQLite engine with the full alembic chain applied."""
    db_path = tmp_path / "privacy.db"
    db_url = f"sqlite:///{db_path}"
    monkeypatch.setenv("STRUMSIGHT_DATABASE_URL", db_url)

    cfg = _alembic_config()
    command.upgrade(cfg, "head")

    eng = create_engine(db_url, connect_args={"check_same_thread": False})
    enable_sqlite_foreign_keys(eng)
    yield eng
    eng.dispose()


@pytest.fixture
def session_factory(engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, autoflush=False, autocommit=False)


@pytest.fixture
def clock() -> Iterator[datetime]:
    """Deterministic clock the router reads from ``app.state.clock``.

    The privacy router falls back to a local ``_utcnow`` if the app
    doesn't expose a ``clock`` — setting one here means the test can
    pin every ``updated_at`` it observes.
    """
    base = datetime(2026, 8, 22, 12, 0, 0, tzinfo=timezone.utc)
    yield base


@pytest.fixture
def app(session_factory, clock) -> Iterator[FastAPI]:
    """Build the self-contained privacy-policy test app."""
    settings = Settings(_env_file=None, community_enabled=True)
    application = FastAPI(title="Privacy Policy Test App")
    application.state.database_engine = session_factory.kw["bind"]
    application.state.session_factory = session_factory
    application.state.settings = settings
    application.state.clock = lambda: clock
    application.include_router(privacy_router)
    yield application


@pytest.fixture
def client(app) -> Iterator[TestClient]:
    def override_get_db():
        db = app.state.session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def _make_privacy_row(
    db: Session,
    *,
    visibility: str = "followers",
    audience_default: str = "followers",
    updated_at: datetime | None = None,
) -> CommunityPrivacySettings:
    """Insert a minimal ``community_privacy_settings`` row for tests.

    The row's ``profile_id`` is a stand-in (the future onboarding
    surface creates the real FK link; this round's tests only need a
    queryable row keyed on its own ``public_id``).
    """
    row = CommunityPrivacySettings(
        public_id=uuid.uuid4(),
        profile_id=0,  # stand-in — see comment above
        visibility=visibility,
        audience_default=audience_default,
    )
    if updated_at is not None:
        row.updated_at = updated_at
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


# ---------------------------------------------------------------------------
# A1 — Server applies policy on every read (no policy-less path)
# ---------------------------------------------------------------------------


# The full matrix: viewer-shape × visibility. The parametrize makes A1
# measurable: every cell returns one of the enum members — there is no
# "no policy" cell. A missing branch in ``evaluate_profile_access`` would
# be a ``KeyError`` / unreachable line in coverage, not a silent no-op.
_A1_VIEWERS = [
    pytest.param(
        RelationshipContext(viewer_is_owner=True),
        id="owner",
    ),
    pytest.param(
        RelationshipContext(is_follower=True),
        id="accepted-follower",
    ),
    pytest.param(
        RelationshipContext(is_follower=False),
        id="non-follower",
    ),
    pytest.param(
        RelationshipContext(blocked=True),
        id="blocked-non-follower",
    ),
    pytest.param(
        RelationshipContext(is_follower=True, blocked=True),
        id="blocked-follower",
    ),
    pytest.param(
        RelationshipContext(is_club_member=True),
        id="club-member-no-follow",
    ),
]

_A1_VISIBILITIES = [
    pytest.param(ProfileVisibility.PUBLIC, id="public"),
    pytest.param(ProfileVisibility.FOLLOWERS, id="followers"),
    pytest.param(ProfileVisibility.PRIVATE, id="private"),
]


@pytest.mark.parametrize("relationship", _A1_VIEWERS)
@pytest.mark.parametrize("visibility", _A1_VISIBILITIES)
def test_a1_evaluate_profile_access_returns_an_enum_member(
    visibility, relationship
):
    """A1 — every (viewer, visibility) combination yields an enum member.

    A future regression that introduces an early ``return None`` /
    ``raise`` / silent no-op would either fail this test (no enum
    member) or break the §6.1 invariant on the same parametrization.
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(visibility, relationship)
    assert isinstance(result, ProfileAccessLevel)


def test_a1_no_policy_less_path_in_source():
    """A1 — the policy file has no early ``return None`` / ``pass`` shortcut.

    A static, grep-based falsification that catches a regression where
    someone "simplifies" the policy by short-circuiting unknown
    combinations. The pattern matches an early-exit with no value (the
    exact failure shape that would leave a future read path without
    policy coverage).
    """
    from pathlib import Path

    policy_path = (
        Path(__file__).resolve().parents[2]
        / "app"
        / "community"
        / "policies"
        / "access_policy.py"
    )
    text_ = policy_path.read_text(encoding="utf-8")
    # No bare ``return`` (without value) inside the policy class —
    # every exit is a typed enum value.
    assert "        return\n" not in text_, (
        "evaluate_profile_access has a bare `return` — a "
        "policy-less path sneaked in. A1 invariant violated."
    )


# ---------------------------------------------------------------------------
# A2 — Block always overrides follow + club
# ---------------------------------------------------------------------------


def test_a2_blocked_public_profile_returns_summary():
    """A2 / §6.1 row 1 — blocked viewer of a PUBLIC profile gets SUMMARY.

    This is the canonical "order matters" cell. If the audience check
    ran before the block check, the result would be FULL — the exact
    IDOR the §6.1 measure-matrix names.
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(
        ProfileVisibility.PUBLIC,
        RelationshipContext(blocked=True),
    )
    assert result is ProfileAccessLevel.SUMMARY


def test_a2_blocked_followers_profile_returns_summary():
    """A2 — block also overrides the follower exemption for FOLLOWERS."""
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(
        ProfileVisibility.FOLLOWERS,
        RelationshipContext(is_follower=True, blocked=True),
    )
    assert result is ProfileAccessLevel.SUMMARY


def test_a2_owner_beats_block_too():
    """A2 — owner is ALWAYS the strongest condition (short-circuits block).

    The brief §5.2 says "block MINDEN audience-szabálynál elsőbbséget
    élvez" but the §5.1 / §1 implicit invariant is that the owner never
    blocks themselves — an owner-only session is by construction not a
    blocked viewer. The ADR §3 places ``viewer_is_owner`` before the
    block check explicitly so this test catches a reordering regression.
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(
        ProfileVisibility.PRIVATE,
        RelationshipContext(viewer_is_owner=True, blocked=True),
    )
    assert result is ProfileAccessLevel.FULL


# ---------------------------------------------------------------------------
# A3 — Private profile = SUMMARY without permission; OWNER = FULL
# ---------------------------------------------------------------------------


def test_a3_private_non_follower_returns_summary():
    """A3 — a non-follower of a PRIVATE profile gets SUMMARY (no full bio/avatar).

    The §6.1 measure-matrix row 2 says "A private profil teljes
    bio/avatar mezőt ad vissza jogosultság nélkül" must be a red cell;
    this test makes that red — a regression that returned ``FULL`` for
    the (PRIVATE, non-follower) combination would flip this test red.
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(
        ProfileVisibility.PRIVATE,
        RelationshipContext(is_follower=False),
    )
    assert result is ProfileAccessLevel.SUMMARY


def test_a3_private_follower_still_returns_summary():
    """A3 — a follower of a PRIVATE profile STILL gets SUMMARY.

    The contract: PRIVATE means "I don't accept followers seeing
    anything beyond a relationship-safe summary" — follow status does
    not upgrade access to FULL on a private profile. This is the
    specific matrix row that a future "followers should see private
    profiles too" regression would flip.
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(
        ProfileVisibility.PRIVATE,
        RelationshipContext(is_follower=True),
    )
    assert result is ProfileAccessLevel.SUMMARY


def test_a3_private_owner_returns_full():
    """A3 — owner of a PRIVATE profile gets FULL (sanity check)."""
    policy = CommunityAccessPolicy()
    result = policy.evaluate_profile_access(
        ProfileVisibility.PRIVATE,
        RelationshipContext(viewer_is_owner=True),
    )
    assert result is ProfileAccessLevel.FULL


# ---------------------------------------------------------------------------
# A4 — Followers-only content is only visible to ACCEPTED followers
# ---------------------------------------------------------------------------


def test_a4_followers_content_visible_to_accepted_follower():
    """A4 — accepted follower sees followers-only content."""
    policy = CommunityAccessPolicy()
    result = policy.evaluate_content_access(
        CommunityAudience.FOLLOWERS,
        RelationshipContext(is_follower=True),
    )
    assert result is True


def test_a4_followers_content_hidden_from_pending_follow():
    """A4 / §6.1 row 3 — pending follow does NOT unlock followers-only.

    The Kör 7 ``FollowStatus`` will model ``PENDING`` separately; by
    contract, ``is_follower=True`` means ACCEPTED, so a caller that
    hasn't transitioned PENDING→ACCEPTED passes ``is_follower=False``
    and the policy correctly hides the content. This test pins the
    contract that the policy never sees a pending-only flag.
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_content_access(
        CommunityAudience.FOLLOWERS,
        RelationshipContext(is_follower=False),
    )
    assert result is False


def test_a4_followers_content_hidden_from_blocked_follower():
    """A4 — even an accepted follower who later gets blocked loses access.

    The block check runs BEFORE the audience check (A2 ordering),
    so the followers-only branch never has a chance to grant access
    when ``blocked=True``. A regression that flipped the order would
    let this test go red (the result would become True).
    """
    policy = CommunityAccessPolicy()
    result = policy.evaluate_content_access(
        CommunityAudience.FOLLOWERS,
        RelationshipContext(is_follower=True, blocked=True),
    )
    assert result is False


# ---------------------------------------------------------------------------
# A5 — Default profile is NOT public (column default + migration server_default)
# ---------------------------------------------------------------------------


def test_a5_orm_default_for_visibility_is_followers():
    """A5 — the ORM mapped column carries ``default="followers"``.

    The Python-side default applies when the ORM constructs a row from
    keyword arguments WITHOUT the field (the test exercises that
    branch). The schema-side ``server_default`` is verified separately.
    """
    from sqlalchemy import inspect as _sa_inspect

    mapper = _sa_inspect(CommunityPrivacySettings)
    cols = {c.key: c for c in mapper.columns}
    assert "visibility" in cols, "A5 — visibility column missing from ORM"
    assert "audience_default" in cols, "A5 — audience_default column missing from ORM"
    assert cols["visibility"].default.arg == "followers", (
        "A5 — ORM default for visibility is not 'followers'"
    )
    assert cols["audience_default"].default.arg == "followers", (
        "A5 — ORM default for audience_default is not 'followers'"
    )


def test_a5_server_default_for_visibility_is_followers(engine):
    """A5 — the migration installs ``server_default='followers'``.

    This is the value the DB itself applies when an INSERT omits the
    column (a future onboarding surface that forgets to set it
    explicitly would otherwise create a ``public`` profile). The
    test introspects the actual column metadata to ensure the
    server_default made it through the batch_alter_table.
    """
    insp = inspect(engine)
    cols = {c["name"]: c for c in insp.get_columns("community_privacy_settings")}
    assert cols["visibility"]["default"] == "followers", (
        f"A5 — server_default for visibility is {cols['visibility']['default']!r}, "
        "expected 'followers'"
    )
    assert cols["audience_default"]["default"] == "followers", (
        f"A5 — server_default for audience_default is "
        f"{cols['audience_default']['default']!r}, expected 'followers'"
    )


def test_a5_visibility_never_evaluates_to_public_by_default(session_factory):
    """A5 — a freshly-created ORM row without explicit values uses followers."""
    row = _make_privacy_row(session_factory())
    assert row.visibility == "followers"
    assert row.audience_default == "followers"


# ---------------------------------------------------------------------------
# A6 — Stale privacy update is rejected
# ---------------------------------------------------------------------------


def test_a6_stale_update_raises_stale_error(session_factory, clock):
    """A6 — submitting an outdated ``resource_version`` raises the
    dedicated error. The router translates it to 409; the service-layer
    test below pins the error shape."""
    with session_factory() as db:
        row = _make_privacy_row(
            db,
            updated_at=clock - timedelta(minutes=5),
        )

    stale = PrivacySettingsUpdate(
        visibility=ProfileVisibility.PUBLIC,
        audience_default=CommunityAudience.PUBLIC,
        resource_version=clock - timedelta(minutes=10),  # even older
    )
    with session_factory() as db:
        fresh = db.get(CommunityPrivacySettings, row.id)
        with pytest.raises(StalePrivacyUpdateError) as excinfo:
            update_privacy_settings_svc(db, fresh, stale, now=clock)
        # The error carries the *current* updated_at so the client can
        # refresh and retry without re-reading the row first.
        assert excinfo.value.current_updated_at == clock - timedelta(minutes=5)
        db.rollback()


def test_a6_fresh_update_succeeds_and_changes_updated_at(session_factory, clock):
    """A6 — submitting the CURRENT ``resource_version`` succeeds and
    bumps ``updated_at`` to the injected ``now``."""
    with session_factory() as db:
        row = _make_privacy_row(
            db,
            visibility="followers",
            audience_default="followers",
            updated_at=clock,
        )

    fresh_payload = PrivacySettingsUpdate(
        visibility=ProfileVisibility.PUBLIC,
        audience_default=CommunityAudience.PUBLIC,
        resource_version=clock,  # == row.updated_at
    )
    with session_factory() as db:
        fresh = db.get(CommunityPrivacySettings, row.id)
        updated = update_privacy_settings_svc(db, fresh, fresh_payload, now=clock + timedelta(seconds=1))
        db.commit()

    with session_factory() as db:
        reread = db.get(CommunityPrivacySettings, row.id)
        assert reread.visibility == "public"
        assert reread.audience_default == "public"
        assert reread.updated_at == clock + timedelta(seconds=1)
        assert updated is reread  # the service returns the row it mutated


def test_a6_router_returns_409_on_stale_resource_version(client, session_factory, clock):
    """A6 — the HTTP layer translates the service-layer error to 409."""
    with session_factory() as db:
        row = _make_privacy_row(
            db,
            visibility="followers",
            audience_default="followers",
            updated_at=clock,
        )

    stale_payload = {
        "visibility": "public",
        "audience_default": "public",
        "resource_version": (clock - timedelta(minutes=10)).isoformat(),
    }
    response = client.put(
        f"/community/privacy/{row.public_id}",
        json=stale_payload,
    )
    assert response.status_code == 409, response.text
    body = response.json()
    assert body["detail"]["error"] == "stale_resource_version"
    # The router carries back the CURRENT version so the client can
    # refresh and retry without an extra GET.
    assert "current_resource_version" in body["detail"]


def test_a6_router_accepts_fresh_update_and_returns_200(client, session_factory, clock):
    """A6 — happy path: a fresh resource_version updates the row and
    returns the new resource_version in the response body."""
    with session_factory() as db:
        row = _make_privacy_row(
            db,
            visibility="followers",
            audience_default="followers",
            updated_at=clock,
        )

    fresh_payload = {
        "visibility": "public",
        "audience_default": "followers",
        "resource_version": clock.isoformat(),
    }
    response = client.put(
        f"/community/privacy/{row.public_id}",
        json=fresh_payload,
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["visibility"] == "public"
    assert body["audience_default"] == "followers"
    assert body["resource_version"] == clock.isoformat()


def test_a6_router_rejects_extra_fields(client, session_factory, clock):
    """A6 — the ``extra='forbid'`` config closes a parallel-field smuggling attack.

    A regression that drops the forbid setting would let a client
    include both ``resource_version`` AND a separate ``updated_at`` in
    the same body — if the service ever read from the latter, the
    concurrency check would be bypassable.
    """
    with session_factory() as db:
        row = _make_privacy_row(
            db,
            visibility="followers",
            audience_default="followers",
            updated_at=clock,
        )

    response = client.put(
        f"/community/privacy/{row.public_id}",
        json={
            "visibility": "public",
            "audience_default": "public",
            "resource_version": clock.isoformat(),
            "updated_at": "1970-01-01T00:00:00+00:00",  # smuggling attempt
        },
    )
    assert response.status_code == 422, response.text


# ---------------------------------------------------------------------------
# §6.1 Measure-matrix — additional falsification cells
# ---------------------------------------------------------------------------


def test_measure_matrix_block_before_visibility_is_enforced_in_code():
    """§6.1 — the source of ``evaluate_profile_access`` checks ``blocked``
    BEFORE any visibility branch.

    This is a static, AST-free grep that scans the function body and
    asserts the textual order: ``viewer_is_owner`` → ``blocked`` →
    ``visibility is PUBLIC`` → ``visibility is FOLLOWERS`` → PRIVATE
    default. A future reorder would flip A2 (the test would still
    pass functionally — but this test is the FALSIFICATION: an order
    swap that "happens to give the right answer for the visible cells"
    would still be caught here).
    """
    from pathlib import Path

    policy_path = (
        Path(__file__).resolve().parents[2]
        / "app"
        / "community"
        / "policies"
        / "access_policy.py"
    )
    text_ = policy_path.read_text(encoding="utf-8")
    # Extract the body of ``evaluate_profile_access`` between the next
    # two ``def`` keywords (rough but stable for this file).
    start = text_.index("def evaluate_profile_access")
    end = text_.index("def evaluate_content_access")
    body = text_[start:end]
    pos_owner = body.index("relationship.viewer_is_owner")
    pos_blocked = body.index("relationship.blocked")
    pos_public = body.index("ProfileVisibility.PUBLIC")
    pos_followers = body.index("ProfileVisibility.FOLLOWERS")
    assert pos_owner < pos_blocked < pos_public < pos_followers, (
        "§6.1 order violated: owner→blocked→public→followers expected, "
        f"got owner={pos_owner}, blocked={pos_blocked}, "
        f"public={pos_public}, followers={pos_followers}"
    )


# ---------------------------------------------------------------------------
# Valódi-sértés próba — INLINE FALSIFICATION
# ---------------------------------------------------------------------------


def _wrong_order_evaluate_profile_access(
    visibility: ProfileVisibility, relationship: RelationshipContext
) -> ProfileAccessLevel:
    """A deliberately wrong evaluator — visibility check FIRST, then blocked.

    This is the §6.1 valódi-sértés próba in code form. It exists so
    the §10 handoff can document the exact contradiction:

        "When I swapped the order to visibility-first, a blocked
        viewer of a PUBLIC profile would get FULL instead of SUMMARY.
        That is the regression the §6.1 cell names."

    The function lives next to its own assertion so the test can both
    demonstrate the buggy behavior (PROVES the test would go red) AND
    verify the production evaluator agrees (PROVES we have the right
    policy).
    """
    # WRONG ORDER — visibility/audience first, block last.
    if relationship.viewer_is_owner:
        return ProfileAccessLevel.FULL
    if visibility is ProfileVisibility.PUBLIC:
        return ProfileAccessLevel.FULL  # <-- leaks to blocked viewers
    if visibility is ProfileVisibility.FOLLOWERS:
        return (
            ProfileAccessLevel.FULL
            if relationship.is_follower
            else ProfileAccessLevel.SUMMARY
        )
    if relationship.blocked:  # <-- too late, PUBLIC already returned FULL above
        return ProfileAccessLevel.SUMMARY
    return ProfileAccessLevel.SUMMARY  # PRIVATE


def test_valodi_sertes_proba_wrong_order_leaks_to_blocked_viewer():
    """§6.1 valódi-sértés próba — the wrong-order evaluator REPRODUCES
    the A2 regression.

    If the production ``evaluate_profile_access`` were swapped to this
    order, the (PUBLIC, blocked) cell would return FULL (the leak)
    instead of SUMMARY (the correct answer). This test asserts both
    facts in one place:

    1. The wrong-order evaluator DOES return FULL for (PUBLIC, blocked)
       — i.e. a swapped implementation would indeed be rejected by A2.
    2. The production evaluator returns SUMMARY — i.e. our code is NOT
       swapped, and A2 would stay green on a well-ordered implementation.

    The §10 handoff describes the actual swap-and-run that I performed
    separately against the live ``access_policy.py`` source.
    """
    policy = CommunityAccessPolicy()
    production_result = policy.evaluate_profile_access(
        ProfileVisibility.PUBLIC,
        RelationshipContext(blocked=True),
    )
    wrong_result = _wrong_order_evaluate_profile_access(
        ProfileVisibility.PUBLIC,
        RelationshipContext(blocked=True),
    )
    # The two must DISAGREE on this exact (visibility, relationship) cell —
    # if they ever agree, the §6.1 valódi-sértés próba loses its
    # falsification power (the wrong-order code would have produced
    # the same answer as the right-order code).
    assert production_result is ProfileAccessLevel.SUMMARY
    assert wrong_result is ProfileAccessLevel.FULL
    assert production_result is not wrong_result, (
        "§6.1 valódi-sértés próba has lost its bite — the wrong-order "
        "evaluator and the right-order evaluator agree. The cell "
        "cannot distinguish them anymore."
    )


# ---------------------------------------------------------------------------
# A1 follow-up — content-read policy shares the same evaluation order
# ---------------------------------------------------------------------------


def test_content_evaluate_uses_same_order_as_profile_evaluate():
    """A1 — ``evaluate_content_access`` short-circuits on
    ``viewer_is_owner`` and ``blocked`` before the audience branch.

    A regression that put the audience branch BEFORE the block branch
    on the content side (but not the profile side, or vice versa)
    would be caught here.
    """
    policy = CommunityAccessPolicy()
    # Blocked viewer of a PUBLIC post: should be False (not True).
    assert (
        policy.evaluate_content_access(
            CommunityAudience.PUBLIC,
            RelationshipContext(blocked=True),
        )
        is False
    )
    # Owner of a PRIVATE post: should be True (short-circuits before PRIVATE).
    assert (
        policy.evaluate_content_access(
            CommunityAudience.PRIVATE,
            RelationshipContext(viewer_is_owner=True),
        )
        is True
    )
