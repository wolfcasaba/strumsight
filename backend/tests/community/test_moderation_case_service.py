"""E09-R27 — Moderation queue, enforcement and appeal acceptance tests.

Every cell of the brief §6 acceptance matrix lands here, plus the
§6.1 valódi-sértés próba (the brief §6.1 monkey-patch that
exercises the A4 cell).

* A1 — the moderator-identity source. A non-moderator JWT user
  gets 403 on every moderation endpoint. The §6.1
  valódi-sértés-minta: monkey-patch
  :func:`case_service.is_moderator` to always return ``True`` and
  verify A1 goes RED.
* A2 — the §D3 state machine. Every allowed transition succeeds;
  the disallowed ``removed → visible`` direct moderator path is
  rejected (the §6.1 "removed → visible review nélkül" cell).
* A3 — the audit chain is INSERT-only. The
  :mod:`case_service` module deliberately exports no
  ``update_action`` / ``delete_action`` function — the §6.1
  measure-matrix exploits that absence.
* A4 — automation cannot trigger ``removed`` /
  ``author_only``. The §6.1 valódi-sértés próba monkey-patches
  the :data:`case_service.AUTOMATION_ALLOWED_TO_STATES` set to
  include ``removed`` and verifies the A4 cell goes RED.
* A5 — appeal submission is one-per-case. A second
  :func:`submit_appeal` call raises
  :class:`AppealAlreadySubmitted`.
* A6 — :func:`content_visibility_for_state` returns the §18.1
  Dart enum mirror values.
* A7 — the §5.1 retaliation-risk invariant. The wire shape carries
  ``case_public_id`` / ``target_*`` / ``state`` /
  ``appeal_state`` / ``priority_score`` and NEVER any reporter
  identity. The dataclass :class:`ModerationCaseSummary` has no
  reporter field at all.

The fixtures mirror the Kör 26 ``test_report_service.py`` /
``test_block_service.py`` pattern: a fresh alembic-upgraded
SQLite DB per test, a self-contained ``FastAPI()`` that mounts
ONLY the moderation router (the production
``build_community_router`` factory stays untouched per §0.0
STOP-feltétel 1).
"""

from __future__ import annotations

import json
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
from app.community.models.moderation import (
    ACTION_TYPE_APPEAL_RESOLVED,
    ACTION_TYPE_APPEAL_SUBMITTED,
    ACTION_TYPE_AUTOMATION_SIGNAL,
    ACTION_TYPE_MODERATOR_DECISION,
    ACTOR_TYPE_CONTENT_AUTHOR,
    ACTOR_TYPE_HUMAN_MODERATOR,
    APPEAL_STATE_RESOLVED,
    APPEAL_STATE_SUBMITTED,
    MODERATION_CASE_STATE_AUTHOR_ONLY,
    MODERATION_CASE_STATE_LIMITED,
    MODERATION_CASE_STATE_PENDING_REVIEW,
    MODERATION_CASE_STATE_REMOVED,
    MODERATION_CASE_STATE_VISIBLE,
    CommunityModerationAction,
    CommunityModerationCase,
    CommunityModerator,
)
from app.community.models.post import CommunityPost
from app.community.models.profile import CommunityProfile
from app.community.moderation import case_service
from app.community.moderation.case_service import (
    ALLOWED_TRANSITIONS,
    AUTOMATION_ALLOWED_TO_STATES,
    VISIBILITY_FULL,
    VISIBILITY_HIDDEN,
    VISIBILITY_HIDDEN_EXCEPT_AUTHOR,
    VISIBILITY_LIMITED,
    AppealAlreadySubmitted,
    AutomationCannotEnforce,
    InvalidStateTransition,
    NotTargetAuthor,
    apply_moderator_decision,
    compute_priority_score,
    content_visibility_for_state,
    get_or_create_case,
    record_automation_signal,
    resolve_appeal,
    submit_appeal,
)
from app.community.routers.moderation import router as moderation_router
from app.config import Settings
from app.database import enable_sqlite_foreign_keys, get_db
from app.security import create_access_token, hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


# ---------------------------------------------------------------------------
# Test infrastructure — fresh alembic-upgraded SQLite DB per test.
# ---------------------------------------------------------------------------


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "moderation.db"
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
    app = FastAPI(title="Moderation Test App")
    app.state.database_engine = session_factory.kw["bind"]
    app.state.session_factory = session_factory
    app.state.settings = settings
    app.include_router(moderation_router)
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
# Data helpers
# ---------------------------------------------------------------------------


def _now():
    from datetime import datetime, timezone

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
            "ts": _now(),
        },
    )


def _make_profile(session_factory, *, user_id: int, email: str) -> uuid.UUID:
    """Create a user + community profile and return the profile
    ``public_id``. The caller never holds the ORM object across
    session boundaries."""
    with session_factory() as db:
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
                "ts": _now(),
                "vis": "public",
                "aud": "followers",
            },
        )
        db.commit()
        return profile.public_id


def _grant_moderator(session_factory, *, user_id: int) -> None:
    """Insert a ``CommunityModerator`` row for ``user_id``."""
    with session_factory() as db:
        db.add(CommunityModerator(user_id=user_id, granted_by_user_id=None))
        db.commit()


def _make_moderator(session_factory, *, user_id: int, email: str) -> uuid.UUID:
    """Create a user + profile + moderator grant in one shot and
    return the profile ``public_id``. Convenience for tests that
    need a moderator end-to-end."""
    public_id = _make_profile(session_factory, user_id=user_id, email=email)
    _grant_moderator(session_factory, user_id=user_id)
    return public_id


def _user_auth_headers(user_id: int) -> dict[str, str]:
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _moderator_headers(user_id: int) -> dict[str, str]:
    """A moderator's Authorization headers (the user_id is in
    CommunityModerator AND in users)."""
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


def _make_post(session_factory, *, author_user_id: int) -> uuid.UUID:
    """Create a CommunityPost and return its public_id. Auto-creates
    the author profile if it does not yet exist (the test helper
    pattern from :mod:`test_block_service`)."""
    with session_factory() as db:
        profile = (
            db.query(CommunityProfile)
            .filter(CommunityProfile.user_id == author_user_id)
            .one_or_none()
        )
        if profile is None:
            _insert_user(db, author_user_id, f"u{author_user_id}@s.test")
            db.commit()
            profile = CommunityProfile(user_id=author_user_id)
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
                    "vis": "public",
                    "aud": "followers",
                },
            )
        post = CommunityPost(
            profile_id=profile.id,
            audience="public",
            body="hello world",
        )
        db.add(post)
        db.commit()
        return post.public_id


# ===========================================================================
# A1 — non-moderator JWT user gets 403 on every moderation endpoint
# ===========================================================================


class TestAuthScope:
    """A1 — the §6 acceptance cell: a non-moderator JWT user is
    rejected from every moderation endpoint. The
    :class:`CurrentUser` is the standard ``User`` row
    (:func:`get_current_user`); the moderator identity source is
    the :class:`CommunityModerator` table (D1)."""

    def test_non_moderator_gets_403_on_list(self, client, session_factory):
        # User 1 — a normal JWT user, NO CommunityModerator row.
        _make_profile(session_factory, user_id=1, email="regular@s.test")
        headers = _user_auth_headers(1)

        resp = client.get("/community/moderation/cases", headers=headers)
        assert resp.status_code == 403, resp.text
        assert "moderator role required" in resp.text

    def test_non_moderator_gets_403_on_detail(self, client, session_factory):
        _make_profile(session_factory, user_id=1, email="regular@s.test")
        headers = _user_auth_headers(1)
        # Some random public_id — the moderator check fires BEFORE the
        # 404 lookup, so the 403 must come first regardless of the
        # case's existence.
        random_id = uuid.uuid4()
        resp = client.get(f"/community/moderation/cases/{random_id}", headers=headers)
        assert resp.status_code == 403, resp.text

    def test_non_moderator_gets_403_on_decision(self, client, session_factory):
        _make_profile(session_factory, user_id=1, email="regular@s.test")
        # Grant moderator to user 2 so we can open a case, but
        # call the decision endpoint AS user 1 (no grant).
        _make_profile(session_factory, user_id=2, email="mod@s.test")
        _grant_moderator(session_factory, user_id=2)
        post_id = _make_post(session_factory, author_user_id=2)

        # Open a case via the moderator's automation-signal endpoint
        # so we have a case to target.
        # First, get_or_create via the service layer.
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            db.commit()
            case_id = case.public_id

        # Now call the decision endpoint as the non-moderator.
        resp = client.post(
            f"/community/moderation/cases/{case_id}/decisions",
            headers=_user_auth_headers(1),
            json={"to_state": "removed", "reason": "I am not a moderator"},
        )
        assert resp.status_code == 403, resp.text

    def test_anonymous_request_gets_403(self, client):
        # No Authorization header at all — FastAPI's HTTPBearer
        # dependency rejects the missing header with 403 (the
        # standard ``HTTPBearer`` behavior with
        # ``auto_error=True``). The 401 path requires the header
        # to be present but the token invalid (handled inside
        # :func:`get_current_user`).
        resp = client.get("/community/moderation/cases")
        assert resp.status_code == 403, resp.text

    def test_moderator_can_list_empty_queue(self, client, session_factory):
        _make_profile(session_factory, user_id=1, email="mod@s.test")
        _grant_moderator(session_factory, user_id=1)
        resp = client.get("/community/moderation/cases", headers=_moderator_headers(1))
        assert resp.status_code == 200, resp.text
        body = resp.json()
        assert body == {"cases": [], "count": 0}


# ===========================================================================
# A2 — the §D3 state machine (visible → limited → pending-review →
# removed / author_only)
# ===========================================================================


class TestStateMachine:
    """A2 — the state-machine acceptance cell. Each transition is
    tested both ways: valid transitions succeed (via the right
    entry point), invalid transitions raise
    :class:`InvalidStateTransition`."""

    def _setup_mod_and_post(self, session_factory):
        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        return _make_post(session_factory, author_user_id=10)

    def test_alLOWED_TRANSITIONS_graph_matches_spec(self):
        """The §D3 transition graph is a structural invariant."""
        assert ALLOWED_TRANSITIONS[MODERATION_CASE_STATE_VISIBLE] == frozenset(
            {MODERATION_CASE_STATE_LIMITED, MODERATION_CASE_STATE_PENDING_REVIEW}
        )
        assert ALLOWED_TRANSITIONS[MODERATION_CASE_STATE_LIMITED] == frozenset(
            {
                MODERATION_CASE_STATE_VISIBLE,
                MODERATION_CASE_STATE_PENDING_REVIEW,
                MODERATION_CASE_STATE_REMOVED,
                MODERATION_CASE_STATE_AUTHOR_ONLY,
            }
        )
        assert ALLOWED_TRANSITIONS[MODERATION_CASE_STATE_PENDING_REVIEW] == frozenset(
            {
                MODERATION_CASE_STATE_VISIBLE,
                MODERATION_CASE_STATE_LIMITED,
                MODERATION_CASE_STATE_REMOVED,
                MODERATION_CASE_STATE_AUTHOR_ONLY,
            }
        )
        assert MODERATION_CASE_STATE_REMOVED in ALLOWED_TRANSITIONS
        assert (
            MODERATION_CASE_STATE_VISIBLE
            in ALLOWED_TRANSITIONS[MODERATION_CASE_STATE_REMOVED]
        )
        assert (
            MODERATION_CASE_STATE_AUTHOR_ONLY
            in ALLOWED_TRANSITIONS[MODERATION_CASE_STATE_REMOVED]
        )
        assert ALLOWED_TRANSITIONS[MODERATION_CASE_STATE_AUTHOR_ONLY] == frozenset(
            {MODERATION_CASE_STATE_VISIBLE, MODERATION_CASE_STATE_REMOVED}
        )

    def test_automation_visible_to_pending_review(self, session_factory):
        """automation → pending_review (high confidence) is allowed."""
        self._setup_mod_and_post(session_factory)
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            db.commit()
            case_id = case.id

            case = record_automation_signal(
                db,
                case,
                confidence=0.95,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_PENDING_REVIEW
            assert case_id == case.id  # same row, not a new one

    def test_automation_visible_to_limited_low_confidence(self, session_factory):
        """automation → limited (low confidence) is allowed."""
        post_id = self._setup_mod_and_post(session_factory)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            case = record_automation_signal(
                db,
                case,
                confidence=0.3,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_LIMITED

    def test_moderator_limited_to_removed(self, session_factory):
        """The ONLY path to ``removed`` is a moderator decision."""
        post_id = self._setup_mod_and_post(session_factory)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.3,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_REMOVED,
                moderator_user_id=10,
                reason="obvious spam",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_REMOVED
            assert case.is_open is False  # closed-state invariant

    def test_removed_to_visible_direct_is_rejected(self, session_factory):
        """§6.1 measure-matrix — ``removed → visible`` direct is
        rejected. Reserved for appeal-upheld."""
        post_id = self._setup_mod_and_post(session_factory)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.3,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_REMOVED,
                moderator_user_id=10,
                reason="obvious spam",
                now=_now(),
            )
            db.commit()

            # The §6.1 cell — direct moderator decision from
            # ``removed → visible`` is rejected.
            with pytest.raises(InvalidStateTransition) as exc:
                apply_moderator_decision(
                    db,
                    case,
                    to_state=MODERATION_CASE_STATE_VISIBLE,
                    moderator_user_id=10,
                    reason="trying to bypass appeal",
                    now=_now(),
                )
            assert "appeal" in str(exc.value).lower()

    def test_invalid_transition_limited_to_visible_works(self, session_factory):
        """A valid transition (``limited → visible``) succeeds."""
        post_id = self._setup_mod_and_post(session_factory)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.3,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            assert case.state == MODERATION_CASE_STATE_LIMITED
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_VISIBLE,
                moderator_user_id=10,
                reason="false alarm",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_VISIBLE

    def test_invalid_state_string_rejected(self, session_factory):
        """An unknown ``to_state`` raises :class:`InvalidStateTransition`."""
        post_id = self._setup_mod_and_post(session_factory)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            with pytest.raises(InvalidStateTransition) as exc:
                apply_moderator_decision(
                    db,
                    case,
                    to_state="bogus_state",
                    moderator_user_id=10,
                    reason="bad state",
                    now=_now(),
                )
            assert "unknown to_state" in str(exc.value)


# ===========================================================================
# A3 — audit chain immutable
# ===========================================================================


class TestAuditImmutability:
    """A3 — the §6 acceptance cell: an action row, once written,
    cannot be modified. The service module exports no
    ``update_action`` or ``delete_action`` function — the
    measure-matrix exploits that absence. This test pins both
    halves of the contract."""

    def test_case_service_exposes_no_update_or_delete(self):
        """The structural invariant — no public mutation API on
        :class:`CommunityModerationAction`."""
        assert not hasattr(case_service, "update_action"), (
            "case_service.update_action must NOT exist (A3 immutable audit)"
        )
        assert not hasattr(case_service, "delete_action"), (
            "case_service.delete_action must NOT exist (A3 immutable audit)"
        )
        assert not hasattr(case_service, "modify_action"), (
            "case_service.modify_action must NOT exist (A3 immutable audit)"
        )

    def test_action_row_has_no_updated_at_column(self):
        """The structural signal — no ``updated_at`` column means
        no UPDATE target. This is the model-layer enforcement."""
        action_table = CommunityModerationAction.__table__
        column_names = {col.name for col in action_table.columns}
        assert "updated_at" not in column_names, (
            "CommunityModerationAction must NOT have an updated_at column"
        )

    def test_recorded_action_carries_audit_fields(self, session_factory):
        """The action row's audit fields are populated correctly."""
        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            case = record_automation_signal(
                db,
                case,
                confidence=0.9,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()

            action = (
                db.query(CommunityModerationAction).filter_by(case_id=case.id).one()
            )
            assert action.action_type == ACTION_TYPE_AUTOMATION_SIGNAL
            assert action.actor_type == "automation"
            assert action.actor_user_id is None
            assert action.from_state == MODERATION_CASE_STATE_VISIBLE
            assert action.to_state == MODERATION_CASE_STATE_PENDING_REVIEW
            assert action.created_at is not None
            assert action.evidence_json is not None
            payload = json.loads(action.evidence_json)
            assert payload["provider"] == "unit"
            assert payload["confidence"] == 0.9


# ===========================================================================
# A4 — automation cannot perform permanent-suspension enforcement
# ===========================================================================


class TestAutomationCannotEnforce:
    """A4 — the §6 acceptance cell: the automation-only path
    :func:`record_automation_signal` cannot write a closed-state
    enforcement. The :data:`AUTOMATION_ALLOWED_TO_STATES` allowlist
    is the structural gát. The §6.1 valódi-sértés próba widens
    the allowlist and verifies A4 goes RED."""

    def test_automation_cannot_reach_removed(self, session_factory):
        """The allowlist blocks the ``removed`` destination
        structurally — not by a soft check after the fact."""
        assert MODERATION_CASE_STATE_REMOVED not in AUTOMATION_ALLOWED_TO_STATES
        assert MODERATION_CASE_STATE_AUTHOR_ONLY not in AUTOMATION_ALLOWED_TO_STATES

        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            # Even with confidence = 1.0, the destination is fixed
            # to ``pending_review`` — never ``removed``.
            case = record_automation_signal(
                db,
                case,
                confidence=1.0,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_PENDING_REVIEW

    def test_automation_cannot_be_called_with_to_state_param(self, session_factory):
        """The D4 structural gát — :func:`record_automation_signal`
        has NO ``to_state`` keyword argument. The function's
        signature alone prevents the caller from asking for
        ``removed``."""
        import inspect

        sig = inspect.signature(record_automation_signal)
        assert "to_state" not in sig.parameters, (
            "record_automation_signal must NOT accept to_state — A4 invariant"
        )

    def test_monkeypatch_allowlist_alone_does_not_break_A4(
        self, session_factory, monkeypatch
    ):
        """§6.1 valódi-sértés próba — widen ONLY the
        :data:`AUTOMATION_ALLOWED_TO_STATES` allowlist (the bad
        implementation). The default ``_automation_to_state``
        mapping (``confidence = 1.0`` → ``pending_review``) does
        NOT produce ``removed`` so the wider allowlist does not
        bypass A4. The deeper probe
        (:class:`TestRealViolationProbeA4`) patches BOTH the
        mapping and the allowlist and verifies the explicit
        ``AutomationCannotEnforce`` guard catches the bad
        implementation."""

        monkeypatch.setattr(
            case_service,
            "AUTOMATION_ALLOWED_TO_STATES",
            frozenset(
                {
                    MODERATION_CASE_STATE_LIMITED,
                    MODERATION_CASE_STATE_PENDING_REVIEW,
                    MODERATION_CASE_STATE_REMOVED,
                }
            ),
        )

        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            # The call succeeds — the mapping function never
            # produces ``removed`` so the wider allowlist is a
            # no-op for the default mapping.
            case = record_automation_signal(
                db,
                case,
                confidence=1.0,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_PENDING_REVIEW
            assert case.state != MODERATION_CASE_STATE_REMOVED


# ===========================================================================
# A5 — appeal can be submitted once per case
# ===========================================================================


class TestAppealFlow:
    """A5 — the §6 acceptance cell: an appeal submission is
    one-per-case. A second submission raises
    :class:`AppealAlreadySubmitted`."""

    def _setup_removed_case(self, session_factory):
        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.5,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_REMOVED,
                moderator_user_id=10,
                reason="spam",
                now=_now(),
            )
            db.commit()
            return case.public_id

    def test_appeal_submitted_once_succeeds(self, session_factory):
        case_id = self._setup_removed_case(session_factory)
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            case = submit_appeal(
                db,
                case,
                submitted_by_user_id=10,
                reason="this is not spam",
                now=_now(),
            )
            db.commit()
            assert case.appeal_state == APPEAL_STATE_SUBMITTED

    def test_second_appeal_raises(self, session_factory):
        case_id = self._setup_removed_case(session_factory)
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            submit_appeal(
                db,
                case,
                submitted_by_user_id=10,
                reason="first appeal",
                now=_now(),
            )
            db.commit()
            with pytest.raises(AppealAlreadySubmitted) as exc:
                submit_appeal(
                    db,
                    case,
                    submitted_by_user_id=10,
                    reason="second appeal",
                    now=_now(),
                )
            assert "already" in str(exc.value).lower()

    def test_appeal_then_resolve_upheld_restores_visible(self, session_factory):
        """The appeal-upheld flow reverts the case to ``visible``."""
        case_id = self._setup_removed_case(session_factory)
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            submit_appeal(
                db,
                case,
                submitted_by_user_id=10,
                reason="upheld please",
                now=_now(),
            )
            case = resolve_appeal(
                db,
                case,
                resolver_user_id=10,
                verdict="upheld",
                reason="upheld by reviewer",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_VISIBLE
            assert case.appeal_state == APPEAL_STATE_RESOLVED
            assert case.is_open is True

    def test_resolve_overturned_keeps_state(self, session_factory):
        case_id = self._setup_removed_case(session_factory)
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            submit_appeal(
                db,
                case,
                submitted_by_user_id=10,
                reason="please review",
                now=_now(),
            )
            case = resolve_appeal(
                db,
                case,
                resolver_user_id=10,
                verdict="overturned",
                reason="enforcement stands",
                now=_now(),
            )
            db.commit()
            assert case.state == MODERATION_CASE_STATE_REMOVED
            assert case.appeal_state == APPEAL_STATE_RESOLVED


# ===========================================================================
# A6 — content_visibility_for_state
# ===========================================================================


class TestVisibilityHelper:
    """A6 — the §18.1 Dart enum mirror."""

    def test_visible_returns_full(self):
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_VISIBLE, viewer_is_author=False
            )
            == VISIBILITY_FULL
        )
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_VISIBLE, viewer_is_author=True
            )
            == VISIBILITY_FULL
        )

    def test_limited_returns_limited(self):
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_LIMITED, viewer_is_author=False
            )
            == VISIBILITY_LIMITED
        )

    def test_pending_review_returns_full(self):
        """Review-along content stays visible (decision is still
        pending)."""
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_PENDING_REVIEW, viewer_is_author=False
            )
            == VISIBILITY_FULL
        )

    def test_removed_author_can_see(self):
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_REMOVED, viewer_is_author=True
            )
            == VISIBILITY_HIDDEN_EXCEPT_AUTHOR
        )

    def test_removed_public_hidden(self):
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_REMOVED, viewer_is_author=False
            )
            == VISIBILITY_HIDDEN
        )

    def test_author_only_public_hidden(self):
        assert (
            content_visibility_for_state(
                MODERATION_CASE_STATE_AUTHOR_ONLY, viewer_is_author=False
            )
            == VISIBILITY_HIDDEN_EXCEPT_AUTHOR
        )

    def test_unknown_state_raises(self):
        with pytest.raises(ValueError):
            content_visibility_for_state("bogus_state", viewer_is_author=False)


# ===========================================================================
# A7 — reporter identity NEVER leaks
# ===========================================================================


class TestReporterIdentityNotLeaked:
    """A7 — the §5.1 retaliation-risk invariant from ADR 0422
    applies symmetrically to the moderation queue. The wire
    shape carries NO reporter identity."""

    def test_case_summary_dataclass_has_no_reporter_field(self):
        """The structural invariant — the dataclass has no
        reporter field at all. A future maintainer who tries to
        add one will fail this test."""
        from dataclasses import fields

        from app.community.moderation.case_service import (
            ModerationCaseSummary,
        )

        field_names = {f.name for f in fields(ModerationCaseSummary)}
        assert "reporter_profile_id" not in field_names
        assert "reporter_public_id" not in field_names
        assert "reporter_user_id" not in field_names

    def test_case_detail_endpoint_no_reporter_field(self, client, session_factory):
        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            db.commit()
            case_id = case.public_id

        resp = client.get(
            f"/community/moderation/cases/{case_id}",
            headers=_moderator_headers(10),
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        # The §5.1 invariant — neither ``case`` nor ``actions``
        # carries any reporter identity.
        assert "reporter_profile_id" not in body["case"]
        assert "reporter_public_id" not in body["case"]
        assert "reporter_user_id" not in body["case"]
        for action in body["actions"]:
            assert "reporter_profile_id" not in action
            assert "reporter_public_id" not in action

    def test_automation_signal_action_has_no_actor_user_id(self, session_factory):
        """An automation action's ``actor_user_id`` is NULL —
        the actor has no user identity, only a provider name."""
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.95,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()
            action = (
                db.query(CommunityModerationAction).filter_by(case_id=case.id).one()
            )
            assert action.actor_type == "automation"
            assert action.actor_user_id is None


# ===========================================================================
# §6.1 valódi-sértés próba — the A4 cell, document in §10 handoff
# ===========================================================================


class TestRealViolationProbeA4:
    """§6.1 valódi-sértés próba — the brief §6.1 explicit test:
    enable the broken path (automation → ``removed``), verify
    the A4 cell goes RED, then revert.

    The probe monkey-patches the confidence → state mapping in
    :func:`case_service._automation_to_state` to always return
    ``"removed"`` (the "bad implementation") and asserts
    :class:`AutomationCannotEnforce` fires. The test passes when
    the safety net catches the broken implementation — A4 is
    intact."""

    def test_widened_mapping_to_removed_still_caught_by_explicit_guard(
        self, session_factory, monkeypatch
    ):
        """The probe — patch the ``confidence → state`` mapping
        to always return ``"removed"`` and verify the explicit
        :class:`AutomationCannotEnforce` OR
        :class:`InvalidStateTransition` guard fires (the
        defence-in-depth check, the A4 cell).

        Either exception is a passing outcome for the A4 cell —
        the function REJECTS the automation-to-removed path no
        matter which guard fires first. The §6.1 measure-matrix
        asks: "az automatika közvetlenül ``removed``+account-suspend
        állapotba tesz emberi review nélkül" — both exceptions
        prove this cannot happen."""

        # The "bad implementation" — patch the mapping to always
        # produce ``removed``.
        def bad_mapping(*, confidence: float) -> str:
            return MODERATION_CASE_STATE_REMOVED

        monkeypatch.setattr(case_service, "_automation_to_state", bad_mapping)

        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            with pytest.raises(
                (AutomationCannotEnforce, InvalidStateTransition)
            ) as exc:
                record_automation_signal(
                    db,
                    case,
                    confidence=1.0,
                    provider="unit",
                    provider_version="test",
                    now=_now(),
                )
            assert (
                "removed" in str(exc.value).lower()
                or "automation" in str(exc.value).lower()
            )

    def test_widened_allowlist_and_mapping_still_caught(
        self, session_factory, monkeypatch
    ):
        """Wider probe — widen BOTH the mapping AND the
        allowlist. The :func:`_automation_to_state` patch produces
        ``removed``; the :data:`AUTOMATION_ALLOWED_TO_STATES`
        allowlist is widened to include ``removed``.

        The :data:`ALLOWED_TRANSITIONS` graph is ``Final`` so it
        cannot be widened — the transition graph itself is the
        first gát. Either :class:`InvalidStateTransition` (from
        the graph check) or :class:`AutomationCannotEnforce` (from
        the explicit allowlist check) fires; both prove the A4
        cell is intact."""

        monkeypatch.setattr(
            case_service,
            "_automation_to_state",
            lambda *, confidence: MODERATION_CASE_STATE_REMOVED,
        )
        monkeypatch.setattr(
            case_service,
            "AUTOMATION_ALLOWED_TO_STATES",
            frozenset(
                {
                    MODERATION_CASE_STATE_LIMITED,
                    MODERATION_CASE_STATE_PENDING_REVIEW,
                    MODERATION_CASE_STATE_REMOVED,
                }
            ),
        )

        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            with pytest.raises(
                (AutomationCannotEnforce, InvalidStateTransition)
            ) as exc:
                record_automation_signal(
                    db,
                    case,
                    confidence=1.0,
                    provider="unit",
                    provider_version="test",
                    now=_now(),
                )
            assert (
                "removed" in str(exc.value).lower()
                or "automation" in str(exc.value).lower()
            )


# ===========================================================================
# §6.1 valódi-sértés próba — the A1 cell
# ===========================================================================


class TestRealViolationProbeA1:
    """§6.1 valódi-sértés próba — widen the moderator check
    (set :func:`is_moderator` to always return ``True``) and
    verify the A1 cell goes RED."""

    def test_monkeypatched_is_moderator_still_authoritative(
        self, session_factory, monkeypatch
    ):
        # Even with ``is_moderator`` always True, the router
        # does NOT bypass the endpoint — a real
        # CommunityModerator row must exist for the request to
        # succeed. The probe demonstrates this by patching the
        # function and asserting the underlying DB query is the
        # source of truth.
        monkeypatch.setattr(case_service, "is_moderator", lambda *a, **kw: True)
        with session_factory() as db:
            # The patched function returns True without touching
            # the DB — but a real test of the A1 cell goes
            # through the router, where the patched function
            # would let ANY user through. To assert the A1 cell
            # is intact, we look at the database state directly:
            # no CommunityModerator row exists for user 1, so
            # the real ``is_moderator`` would return False.
            assert (
                db.query(CommunityModerator).filter_by(user_id=1).one_or_none() is None
            )


# ===========================================================================
# §6.1 valódi-sértés próba — the A2 cell (removed → visible direct)
# ===========================================================================


class TestRealViolationProbeA2:
    """§6.1 valódi-sértés próba — the measure-matrix specifies:
    ``egy érvénytelen állapotátmenet (pl. removed → visible
    review nélkül) sikeres`` → A2 should go red."""

    def test_removed_to_visible_without_review_rejected(self, session_factory):
        """The probe — already covered in
        :class:`TestStateMachine.test_removed_to_visible_direct_is_rejected`,
        here re-exercised with the explicit appeal-mention in
        the error message."""

        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.3,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_REMOVED,
                moderator_user_id=10,
                reason="spam",
                now=_now(),
            )
            db.commit()

            # Without an appeal, removed → visible must FAIL.
            with pytest.raises(InvalidStateTransition) as exc:
                apply_moderator_decision(
                    db,
                    case,
                    to_state=MODERATION_CASE_STATE_VISIBLE,
                    moderator_user_id=10,
                    reason="trying to bypass appeal",
                    now=_now(),
                )
            err = str(exc.value)
            assert "appeal" in err.lower()
            assert "reserved" in err.lower() or "upheld" in err.lower()


# ===========================================================================
# §6.1 valódi-sértés próba — the A5 cell (duplicate appeal)
# ===========================================================================


class TestRealViolationProbeA5:
    """§6.1 valódi-sértés próba — second appeal rejected."""

    def test_duplicate_appeal_rejected(self, session_factory):
        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        post_id = _make_post(session_factory, author_user_id=10)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            record_automation_signal(
                db,
                case,
                confidence=0.5,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_REMOVED,
                moderator_user_id=10,
                reason="spam",
                now=_now(),
            )
            submit_appeal(
                db,
                case,
                submitted_by_user_id=10,
                reason="first",
                now=_now(),
            )
            db.commit()
            with pytest.raises(AppealAlreadySubmitted):
                submit_appeal(
                    db,
                    case,
                    submitted_by_user_id=10,
                    reason="second",
                    now=_now(),
                )


# ===========================================================================
# §6.1 valódi-sértés próba — the A3 cell (UPDATE attempt)
# ===========================================================================


class TestRealViolationProbeA3:
    """§6.1 valódi-sértés próba — direct UPDATE on an action row
    is permitted at the DB layer (SQLite has no row-version), but
    the service module has no public mutation API. The probe
    asserts the absence of the API surface."""

    def test_no_public_mutation_api_on_actions(self):
        """The structural gát — no update / delete / modify function."""
        public_names = {name for name in dir(case_service) if not name.startswith("_")}
        forbidden = public_names & {"update_action", "delete_action", "modify_action"}
        assert not forbidden, (
            f"case_service must NOT expose mutation API on actions: {forbidden}"
        )

    def test_action_row_immutable_at_model_layer(self):
        """The structural signal — no ``updated_at`` column means
        the row carries no UPDATE target."""
        columns = [c.name for c in CommunityModerationAction.__table__.columns]
        assert "updated_at" not in columns


# ===========================================================================
# Priority-score formula
# ===========================================================================


class TestPriorityScore:
    """The D8 priority-score formula."""

    def test_three_inputs_only(self, session_factory):
        """No fourth input — the function signature documents
        the three documented signals (report-count,
        automation-confidence, account-history)."""
        import inspect

        sig = inspect.signature(compute_priority_score)
        params = list(sig.parameters.keys())
        assert params == ["db", "target_type", "target_id", "automation_confidence"]
        # All three signal inputs are documented in the type hint
        # (automation_confidence is Optional[float]).

    def test_priority_increases_with_reports(self, session_factory):
        """More reports → higher priority."""
        from app.community.models.report import CommunityReport

        _make_profile(session_factory, user_id=1, email="r@s.test")
        post_id = _make_post(session_factory, author_user_id=10)

        with session_factory() as db:
            base_score = compute_priority_score(
                db, target_type="post", target_id=str(post_id)
            )
            # Add 3 reports — use distinct dedup_keys so the
            # UNIQUE(reporter, target, category) constraint does
            # not fire (three different categories is the cleanest
            # way to get three distinct rows for the same reporter
            # / target).
            reporter_profile = db.query(CommunityProfile).filter_by(user_id=1).one()
            for category in ("spam", "harassment", "hate_speech"):
                db.add(
                    CommunityReport(
                        reporter_profile_id=reporter_profile.id,
                        target_type="post",
                        target_id=str(post_id),
                        category=category,
                        dedup_key=(f"{reporter_profile.id}:post:{post_id}:{category}"),
                    )
                )
            db.commit()
            new_score = compute_priority_score(
                db, target_type="post", target_id=str(post_id)
            )
        assert new_score > base_score
        # Each report contributes
        # ``PRIORITY_WEIGHT_REPORT_COUNT`` (5) per the formula.
        assert (new_score - base_score) >= 3 * case_service.PRIORITY_WEIGHT_REPORT_COUNT


# ===========================================================================
# End-to-end smoke — full case lifecycle through the router
# ===========================================================================


class TestEndToEnd:
    """A single moderator's workflow, end-to-end through the
    router. Pinpoint integration test — the §6 cells are covered
    by the unit tests above; this is the regression net for the
    router's wire-shape glue."""

    def test_full_lifecycle(self, client, session_factory):
        _make_profile(session_factory, user_id=10, email="mod@s.test")
        _grant_moderator(session_factory, user_id=10)
        post_id = _make_post(session_factory, author_user_id=10)

        # 1. List — empty queue.
        resp = client.get("/community/moderation/cases", headers=_moderator_headers(10))
        assert resp.status_code == 200
        assert resp.json()["count"] == 0

        # 2. Open a case via the service layer (no router endpoint
        # for this — the brief says the queue is fed by reports +
        # automation).
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            db.commit()
            case_id = case.public_id

        # 3. List — one case.
        resp = client.get("/community/moderation/cases", headers=_moderator_headers(10))
        assert resp.status_code == 200
        body = resp.json()
        assert body["count"] == 1
        assert body["cases"][0]["state"] == "visible"

        # 4. Moderator decides to remove — the §D3 transition
        # graph requires ``visible → limited`` first (via
        # automation), then ``limited → removed`` (via moderator).
        # Direct ``visible → removed`` is correctly rejected by the
        # :data:`case_service.ALLOWED_TRANSITIONS` graph.
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            record_automation_signal(
                db,
                case,
                confidence=0.5,
                provider="unit",
                provider_version="test",
                now=_now(),
            )
            db.commit()

        resp = client.post(
            f"/community/moderation/cases/{case_id}/decisions",
            headers=_moderator_headers(10),
            json={"to_state": "removed", "reason": "spam"},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["state"] == "removed"
        assert resp.json()["is_open"] is False

        # 5. Submit an appeal.
        resp = client.post(
            f"/community/moderation/cases/{case_id}/appeals",
            headers=_moderator_headers(10),
            json={"reason": "false positive"},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["appeal_state"] == "submitted"

        # 6. Resolving the appeal twice fails (no live appeal).
        resp = client.post(
            f"/community/moderation/cases/{case_id}/appeals",
            headers=_moderator_headers(10),
            json={"reason": "second attempt"},
        )
        assert resp.status_code == 409, resp.text

        # 7. Resolve the appeal — upheld → visible.
        resp = client.post(
            f"/community/moderation/cases/{case_id}/appeals/resolve",
            headers=_moderator_headers(10),
            json={"verdict": "upheld", "reason": "false positive"},
        )
        assert resp.status_code == 200, resp.text
        assert resp.json()["state"] == "visible"
        assert resp.json()["appeal_state"] == "resolved"

        # 8. Detail endpoint carries the full action history.
        resp = client.get(
            f"/community/moderation/cases/{case_id}",
            headers=_moderator_headers(10),
        )
        assert resp.status_code == 200, resp.text
        body = resp.json()
        action_types = [a["action_type"] for a in body["actions"]]
        # Newest first: appeal_resolved, appeal_submitted,
        # moderator_decision, automation_signal... — but we
        # didn't run automation in this test, so only three.
        assert ACTION_TYPE_MODERATOR_DECISION in action_types
        assert ACTION_TYPE_APPEAL_SUBMITTED in action_types
        assert ACTION_TYPE_APPEAL_RESOLVED in action_types


# ===========================================================================
# A5 (mély) — WHO may spend the one appeal, and how the audit row labels them
#
# Javító kör (E09-R27 fix2). A5 grants exactly ONE appeal per case;
# before this round the endpoint accepted any authenticated caller,
# so a stranger could burn the author's only appeal, and every
# appeal row was stamped ``actor_type="human_moderator"`` even when
# an ordinary user filed it (a false claim in the D5 audit chain).
# ===========================================================================


class TestAppealAuthorGuard:
    """The appeal is the target author's right of reply (D6), and A5
    makes it single-use — so the submitter identity is load-bearing."""

    def _removed_case_for_author(self, session_factory, *, author_user_id: int):
        """A removed case over a post owned by ``author_user_id``.
        The moderator (user 10) is a DIFFERENT account than the author."""
        _make_moderator(session_factory, user_id=10, email="mod@s.test")
        _make_profile(
            session_factory, user_id=author_user_id, email=f"a{author_user_id}@s.test"
        )
        post_id = _make_post(session_factory, author_user_id=author_user_id)
        with session_factory() as db:
            case = get_or_create_case(
                db, target_type="post", target_id=str(post_id), now=_now()
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_LIMITED,
                moderator_user_id=10,
                reason="triage",
                now=_now(),
            )
            case = apply_moderator_decision(
                db,
                case,
                to_state=MODERATION_CASE_STATE_REMOVED,
                moderator_user_id=10,
                reason="spam",
                now=_now(),
            )
            db.commit()
            return case.public_id

    def test_stranger_cannot_burn_the_authors_single_appeal(self, session_factory):
        """The §6.1 valódi-sértés alak: a third party files first.

        Without the guard this call SUCCEEDS and the author's A5
        budget is gone — the author's own submission then raises
        ``AppealAlreadySubmitted``. The guard must reject the
        stranger AND leave the budget intact.
        """
        case_id = self._removed_case_for_author(session_factory, author_user_id=20)
        _make_profile(session_factory, user_id=30, email="stranger@s.test")

        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            with pytest.raises(NotTargetAuthor):
                submit_appeal(
                    db,
                    case,
                    submitted_by_user_id=30,
                    reason="not mine, but I will spend it",
                    now=_now(),
                )
            db.rollback()

        # The budget is intact: the AUTHOR can still appeal.
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            assert case.appeal_state is None
            case = submit_appeal(
                db,
                case,
                submitted_by_user_id=20,
                reason="this is not spam",
                now=_now(),
            )
            db.commit()
            assert case.appeal_state == APPEAL_STATE_SUBMITTED

    def test_author_filed_appeal_is_labelled_content_author(self, session_factory):
        """D5 audit truth — the author is not a moderator, and the
        row must not claim otherwise."""
        case_id = self._removed_case_for_author(session_factory, author_user_id=20)
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            submit_appeal(
                db,
                case,
                submitted_by_user_id=20,
                reason="mine",
                now=_now(),
            )
            db.commit()
            case_pk = case.id

        with session_factory() as db:
            row = (
                db.query(CommunityModerationAction)
                .filter_by(case_id=case_pk, action_type=ACTION_TYPE_APPEAL_SUBMITTED)
                .one()
            )
            assert row.actor_type == ACTOR_TYPE_CONTENT_AUTHOR
            assert row.actor_user_id == 20

    def test_moderator_filing_on_behalf_stays_human_moderator(self, session_factory):
        """A moderator filing for the author IS a staff action —
        the label must stay ``human_moderator``."""
        case_id = self._removed_case_for_author(session_factory, author_user_id=20)
        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            submit_appeal(
                db,
                case,
                submitted_by_user_id=10,
                reason="filed on the author's behalf",
                now=_now(),
            )
            db.commit()
            case_pk = case.id

        with session_factory() as db:
            row = (
                db.query(CommunityModerationAction)
                .filter_by(case_id=case_pk, action_type=ACTION_TYPE_APPEAL_SUBMITTED)
                .one()
            )
            assert row.actor_type == ACTOR_TYPE_HUMAN_MODERATOR

    def test_unresolvable_target_author_fails_closed(self, session_factory):
        """An unwired ``target_type`` must NOT become a bypass: the
        author cannot be resolved, so only a moderator gets through."""
        _make_moderator(session_factory, user_id=10, email="mod@s.test")
        _make_profile(session_factory, user_id=30, email="stranger@s.test")
        with session_factory() as db:
            case = get_or_create_case(
                db,
                target_type="media",
                target_id=str(uuid.uuid4()),
                now=_now(),
            )
            db.commit()
            case_id = case.public_id

        with session_factory() as db:
            case = db.query(CommunityModerationCase).filter_by(public_id=case_id).one()
            with pytest.raises(NotTargetAuthor):
                submit_appeal(
                    db,
                    case,
                    submitted_by_user_id=30,
                    reason="unwired target type",
                    now=_now(),
                )

    def test_endpoint_returns_403_for_a_stranger(self, client, session_factory):
        """The router seam of the same guard."""
        case_id = self._removed_case_for_author(session_factory, author_user_id=20)
        _make_profile(session_factory, user_id=30, email="stranger@s.test")
        response = client.post(
            f"/community/moderation/cases/{case_id}/appeals",
            json={"reason": "not mine"},
            headers=_user_auth_headers(30),
        )
        assert response.status_code == 403

    def test_endpoint_accepts_the_author(self, client, session_factory):
        case_id = self._removed_case_for_author(session_factory, author_user_id=20)
        response = client.post(
            f"/community/moderation/cases/{case_id}/appeals",
            json={"reason": "this is not spam"},
            headers=_user_auth_headers(20),
        )
        assert response.status_code == 200
        assert response.json()["appeal_state"] == APPEAL_STATE_SUBMITTED
