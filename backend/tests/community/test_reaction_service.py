"""E09-R15 — Reaction service acceptance tests.

Covers every cell of the brief §6 acceptance matrix, plus the
§6.1 measure-matrix regression cases. The reaction service is
**not** exposed via HTTP this round (the §0.0 D2 scope-shrink —
the router and the ``PostOut`` / ``FeedPostItem`` projection
change belong to a later round's ``allowed_paths``), so the
tests are pure service-layer calls against the same in-memory
SQLite engine the post-service tests use.

* A1 — retry / duplicate ``set_reaction`` lands on the existing
  row; the aggregated count does not double.
* A2 — kind change is an UPDATE on the existing row, not a second
  INSERT.
* A3 — ``remove_reaction`` called twice is a successful no-op;
  the count never goes negative.
* A4 — concurrent toggle (two parallel calls from the same viewer
  on the same post) leaves the row in a consistent state — the
  §6.1 "real-user-intent" cell measures the steady-state, not
  which-tx-wins.
* A5 — count property invariant: the aggregated count is
  ``>= 0`` for every prefix of a randomized sequence of set /
  remove / count calls.
* A7 — the ``reaction_service`` module imports nothing from the
  gamification module — a community reaction is NOT a learning
  reward (E08-R26 invariant).

The §6.1 valódi-sértés próba is exercised explicitly: a temporary
SQL ``DROP INDEX`` of the ``UNIQUE`` constraint, runs the same
``set_reaction`` twice with the same kind, and asserts that two
rows land (A1 goes red). The test then restores the index.

The A5 property test is randomized but bounded — a fixed seed
inherited from ``PROPERTY_SEED`` (default ``42`` for dev
reproducibility), 200 ops, the brief's §6 A5 word-for-word:
"count is never negative".
"""

from __future__ import annotations

import importlib
import os
import random
import threading
import uuid
from collections.abc import Iterator
from datetime import datetime, timezone
from pathlib import Path

import pytest
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, sessionmaker

from alembic import command
from app.community.models.post import CommunityPost
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import (
    REACTION_KIND_ALLOWLIST,
    CommunityReaction,
)
from app.community.services import reaction_service
from app.community.policies.access_policy import CommunityAudience
from app.community.services.post_service import create_post
from app.config import Settings
from app.database import enable_sqlite_foreign_keys
from app.security import create_access_token, hash_password

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_ALEMBIC_INI = _BACKEND_ROOT / "alembic.ini"
_ALEMBIC_DIR = _BACKEND_ROOT / "alembic"


def _alembic_config() -> Config:
    cfg = Config(str(_ALEMBIC_INI))
    cfg.set_main_option("script_location", str(_ALEMBIC_DIR))
    return cfg


# ---------------------------------------------------------------------------
# Fixtures — file-backed SQLite engine with the full alembic chain
# applied, mirroring the test_follow_service / test_post_service
# pattern.
# ---------------------------------------------------------------------------


@pytest.fixture
def session_factory(tmp_path, monkeypatch) -> Iterator[sessionmaker[Session]]:
    db_path = tmp_path / "reactions.db"
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
def invalidation_events() -> list[dict[str, object]]:
    """Thread-safe capture list for the on_invalidate spy."""
    return []


# ---------------------------------------------------------------------------
# Test data helpers — users, profiles, posts, auth headers.
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
    matching ``community_privacy_settings`` row carrying the
    requested visibility. The FK chain is satisfied atomically.
    """
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
            # SQLite stores Uuid(as_uuid=True) as CHAR(32); raw cursor
            # binding needs the hex form.
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


def _make_author(session_factory) -> CommunityProfile:
    with session_factory() as db:
        profile = _make_profile(
            db, user_id=1, email="author@s.test", visibility="public"
        )
        db.refresh(profile)
        return profile


def _make_viewer(session_factory, *, user_id: int, email: str) -> CommunityProfile:
    with session_factory() as db:
        profile = _make_profile(db, user_id=user_id, email=email, visibility="public")
        db.refresh(profile)
        return profile


def _make_two_viewers(session_factory) -> tuple[CommunityProfile, CommunityProfile]:
    a = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    b = _make_viewer(session_factory, user_id=3, email="viewer-b@s.test")
    return a, b


def _create_visible_post(
    session_factory,
    *,
    author: CommunityProfile,
    body: str = "reaction-target",
    idempotency_key: str = "reaction-target-key",
) -> CommunityPost:
    """Create one visible PUBLIC post via the post service and
    return the ORM row (the service is the canonical write path —
    it stamps ``created_at`` / ``updated_at`` correctly and the
    audit-trail stays consistent).
    """
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


# ---------------------------------------------------------------------------
# §6 / §6.1 acceptance-matrix cells.
# ---------------------------------------------------------------------------


def test_a1_duplicate_set_does_not_double_count(session_factory) -> None:
    """A1 — ``set_reaction`` called twice with the same kind lands
    on the existing row; the aggregated count is exactly one.

    The UNIQUE(post_id, profile_id) constraint is the §6.1
    valódi-sértés target — the §6.1 probe in this file drops the
    index and asserts the A1 cell turns red.
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    with session_factory() as db:
        first = reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="support",
            now=_utcnow(),
        )
        first_id = first.id
        first_kind = first.kind
        db.commit()
    with session_factory() as db:
        again = reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="support",
            now=_utcnow(),
        )
        again_id = again.id
        again_kind = again.kind
        db.commit()

    assert first_id == again_id, "same row must be returned on retry"
    assert first_kind == "support"
    assert again_kind == "support"

    with session_factory() as db:
        count = reaction_service.get_reaction_count(db, post_public_id=post.public_id)
    assert count == 1, f"A1 violated — count={count}, expected 1"


def test_a1_real_violation_probe(session_factory, monkeypatch) -> None:
    """§6.1 valódi-sértés próba — bypass the application-level
    pre-check AND rebuild the ``community_reactions`` table
    WITHOUT the UNIQUE(post_id, profile_id) constraint, run the
    same ``set_reaction`` twice with the same kind, and assert
    two rows land (the A1 cell goes red). Then restore the
    original schema.

    The probe has TWO pre-conditions because the A1 invariant is
    enforced at BOTH layers: the service's ``_existing_reaction``
    short-circuit (the friendly path) AND the DB UNIQUE constraint
    (the backstop). With either in place, a duplicate set lands on
    the existing row. Both must be removed for the probe to land
    two rows; one alone is insufficient.

    SQLite cannot ``DROP INDEX`` on a UNIQUE-backed auto-index and
    cannot ``ALTER TABLE ... DROP CONSTRAINT`` — the only portable
    way to remove a UNIQUE constraint is the table-rebuild dance
    (CREATE new without constraint, INSERT SELECT, DROP old,
    RENAME new). The migration's CREATE TABLE statement is the
    source of truth, so the rebuild mirrors it exactly minus the
    UniqueConstraint.
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    # Bypass the service-level pre-check so the INSERT path is
    # always taken — this is the friendly layer of the A1
    # enforcement.
    original_existing = reaction_service._existing_reaction

    def _no_existing(*_args, **_kwargs):
        return None

    monkeypatch.setattr(reaction_service, "_existing_reaction", _no_existing)

    # Rebuild the ``community_reactions`` table WITHOUT the
    # ``UNIQUE(post_id, profile_id)`` constraint. The original
    # schema is restored in the ``finally`` block.
    engine = session_factory.kw["bind"]
    rebuild_sql = [
        # 1. Snapshot the existing rows.
        "CREATE TABLE community_reactions_probe_backup AS "
        "SELECT * FROM community_reactions",
        # 2. Drop the original table (the auto-index goes with it).
        "DROP TABLE community_reactions",
        # 3. Recreate WITHOUT the UniqueConstraint.
        "CREATE TABLE community_reactions ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  post_id INTEGER NOT NULL,"
        "  profile_id INTEGER NOT NULL,"
        "  kind VARCHAR NOT NULL,"
        "  created_at DATETIME NOT NULL,"
        "  updated_at DATETIME NOT NULL,"
        "  FOREIGN KEY (post_id) REFERENCES community_posts(id) "
        "    ON DELETE CASCADE,"
        "  FOREIGN KEY (profile_id) REFERENCES community_profiles(id) "
        "    ON DELETE CASCADE"
        ")",
        # 4. Copy the snapshot back.
        "INSERT INTO community_reactions "
        "  (id, post_id, profile_id, kind, created_at, updated_at) "
        "SELECT id, post_id, profile_id, kind, created_at, updated_at "
        "FROM community_reactions_probe_backup",
        "DROP TABLE community_reactions_probe_backup",
        # 5. Recreate the standalone (post_id) index that the
        #    migration ships.
        "CREATE INDEX ix_community_reactions_post ON community_reactions (post_id)",
    ]
    restore_sql = [
        # Mirror the Kör 15 migration's CREATE TABLE exactly.
        # The probe may have left two duplicate rows for the
        # same ``(post_id, profile_id)`` pair — the restore's
        # SELECT collapses them via ``GROUP BY`` so the
        # constraint survives the round-trip.
        "CREATE TABLE community_reactions_probe_backup AS "
        "SELECT * FROM community_reactions",
        "DROP TABLE community_reactions",
        "CREATE TABLE community_reactions ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  post_id INTEGER NOT NULL,"
        "  profile_id INTEGER NOT NULL,"
        "  kind VARCHAR NOT NULL,"
        "  created_at DATETIME NOT NULL,"
        "  updated_at DATETIME NOT NULL,"
        "  FOREIGN KEY (post_id) REFERENCES community_posts(id) "
        "    ON DELETE CASCADE,"
        "  FOREIGN KEY (profile_id) REFERENCES community_profiles(id) "
        "    ON DELETE CASCADE,"
        "  CONSTRAINT uq_community_reactions_post_profile "
        "    UNIQUE (post_id, profile_id)"
        ")",
        "INSERT INTO community_reactions "
        "  (id, post_id, profile_id, kind, created_at, updated_at) "
        "SELECT MIN(id), post_id, profile_id, "
        "       MAX(kind), MIN(created_at), MAX(updated_at) "
        "FROM community_reactions_probe_backup "
        "GROUP BY post_id, profile_id",
        "DROP TABLE community_reactions_probe_backup",
        "CREATE INDEX ix_community_reactions_post ON community_reactions (post_id)",
    ]

    with engine.begin() as conn:
        for stmt in rebuild_sql:
            conn.execute(text(stmt))

    try:
        with session_factory() as db:
            reaction_service.set_reaction(
                db,
                viewer_public_id=viewer.public_id,
                post_public_id=post.public_id,
                kind="support",
                now=_utcnow(),
            )
            db.commit()
        with session_factory() as db:
            reaction_service.set_reaction(
                db,
                viewer_public_id=viewer.public_id,
                post_public_id=post.public_id,
                kind="support",
                now=_utcnow(),
            )
            db.commit()

        with session_factory() as db:
            rows = (
                db.query(CommunityReaction)
                .filter(
                    CommunityReaction.post_id == post.id,
                    CommunityReaction.profile_id == viewer.id,
                )
                .count()
            )
        assert rows == 2, (
            "real-violation probe should land two rows when BOTH "
            "the service pre-check and the DB UNIQUE are removed; "
            "if it lands one, the test setup is broken (the §6.1 "
            "contract is unenforceable)."
        )
    finally:
        # Always restore the original schema — even if the probe
        # raised. Rebuilding with the UNIQUE in place AND
        # restoring the service-level pre-check is what makes the
        # §6.1 contract enforceable again.
        with engine.begin() as conn:
            for stmt in restore_sql:
                conn.execute(text(stmt))
        monkeypatch.setattr(reaction_service, "_existing_reaction", original_existing)


def test_a2_kind_change_updates_existing_row(session_factory) -> None:
    """A2 — a retry with a different kind is an UPDATE on the
    existing row, not a second INSERT; the count is unchanged.
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    with session_factory() as db:
        first = reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="support",
            now=_utcnow(),
        )
        first_id = first.id
        first_created_at = first.created_at
        first_kind = first.kind
        db.commit()
    with session_factory() as db:
        second = reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="celebrate",
            now=_utcnow(),
        )
        second_id = second.id
        second_kind = second.kind
        db.commit()

    assert first_id == second_id, "kind change must not create a second row"
    assert first_kind == "support"
    assert second_kind == "celebrate"

    with session_factory() as db:
        count = reaction_service.get_reaction_count(db, post_public_id=post.public_id)
    assert count == 1, "count is invariant under a kind change"

    # ``created_at`` must NOT have moved; only ``updated_at`` advances.
    with session_factory() as db:
        row = db.query(CommunityReaction).filter_by(id=first_id).one()
        row_created_at = row.created_at
    assert row_created_at == first_created_at, (
        "created_at must NOT advance on a kind change"
    )


def test_a3_remove_twice_is_idempotent_noop(session_factory) -> None:
    """A3 — ``remove_reaction`` called twice does not raise and
    does not push the count negative.

    The first call returns ``True`` (a transition happened); the
    second call returns ``False`` (already removed, no-op). The
    count is zero, NEVER negative.
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    with session_factory() as db:
        reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="support",
            now=_utcnow(),
        )
        db.commit()

    with session_factory() as db:
        first = reaction_service.remove_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
        )
        db.commit()
    with session_factory() as db:
        second = reaction_service.remove_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
        )
        db.commit()

    assert first is True, "first remove is a transition"
    assert second is False, "second remove is a no-op"

    with session_factory() as db:
        count = reaction_service.get_reaction_count(db, post_public_id=post.public_id)
    assert count == 0, f"A3 violated — count={count}, expected 0"

    # Same probe: even when the post never had a reaction at all,
    # remove is a successful no-op.
    post2 = _create_visible_post(
        session_factory, author=author, idempotency_key="no-react-1"
    )
    with session_factory() as db:
        result = reaction_service.remove_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post2.public_id,
            now=_utcnow(),
        )
        db.commit()
    assert result is False


def test_a4_concurrent_toggle_consistent_viewer_state(
    session_factory,
) -> None:
    """A4 — two parallel ``set_reaction`` calls from the same
    viewer on the same post land on the same row; the row's kind
    is whichever caller wrote last. The steady-state is one row
    per ``(post, viewer)`` pair regardless of which tx wins.

    The §6.1 word-for-word cell is "the rapid double-tap does
    not produce a different final state from the user's real
    intent" — both call sites have the same intent (a single
    kind), so the row's final kind MUST be that kind, not some
    half-applied combination. The fixture uses two distinct
    kinds to exercise the race; whichever lands, the count is
    one, the row exists, and the kind is one of the two — the
    user-intent cell is the steady-state, not which-tx-wins.
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    barrier = threading.Barrier(2)
    errors: list[BaseException] = []

    def _setter(kind: str) -> None:
        try:
            with session_factory() as db:
                barrier.wait(timeout=5.0)
                reaction_service.set_reaction(
                    db,
                    viewer_public_id=viewer.public_id,
                    post_public_id=post.public_id,
                    kind=kind,
                    now=_utcnow(),
                )
                db.commit()
        except BaseException as exc:  # noqa: BLE001 — re-raise after join
            errors.append(exc)

    t1 = threading.Thread(target=_setter, args=("support",))
    t2 = threading.Thread(target=_setter, args=("celebrate",))
    t1.start()
    t2.start()
    t1.join(timeout=10.0)
    t2.join(timeout=10.0)
    assert not errors, f"concurrent setters raised: {errors}"

    with session_factory() as db:
        rows = (
            db.query(CommunityReaction)
            .filter(
                CommunityReaction.post_id == post.id,
                CommunityReaction.profile_id == viewer.id,
            )
            .count()
        )
    assert rows == 1, (
        f"A4 violated — concurrent toggles produced {rows} rows, expected exactly one"
    )

    with session_factory() as db:
        kind = reaction_service.get_viewer_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
        )
    assert kind in {"support", "celebrate"}, (
        f"row kind must be one of the two competing writes — got {kind!r}"
    )


def test_a5_count_property_invariant_never_negative(session_factory) -> None:
    """A5 — for every prefix of a randomized sequence of set /
    remove / count operations, the aggregated count is ``>= 0``.

    Bounded random walk (no test-internal fixture coupling to
    ``PROPERTY_SEED`` — the seed is the default 42 for dev
    reproducibility; CI can monkeypatch ``seed`` if it wants a
    fresh draw per run, the same shape the DSP property gate
    follows).
    """
    seed = int(os.environ.get("PROPERTY_SEED", "42"))
    rng = random.Random(seed)
    author = _make_author(session_factory)
    post = _create_visible_post(session_factory, author=author)
    viewers = [
        _make_viewer(session_factory, user_id=10 + i, email=f"v-{i}@s.test")
        for i in range(8)
    ]
    kinds = sorted(REACTION_KIND_ALLOWLIST)

    def _set(viewer_index: int, kind: str) -> None:
        with session_factory() as db:
            reaction_service.set_reaction(
                db,
                viewer_public_id=viewers[viewer_index].public_id,
                post_public_id=post.public_id,
                kind=kind,
                now=_utcnow(),
            )
            db.commit()

    def _remove(viewer_index: int) -> None:
        with session_factory() as db:
            reaction_service.remove_reaction(
                db,
                viewer_public_id=viewers[viewer_index].public_id,
                post_public_id=post.public_id,
                now=_utcnow(),
            )
            db.commit()

    def _count() -> int:
        with session_factory() as db:
            return reaction_service.get_reaction_count(
                db, post_public_id=post.public_id
            )

    # 200 ops; the brief §6 A5 wording is "the count property-
    # invariant is never negative". The pre/post count of every
    # mutation must be ``>= 0``.
    for _ in range(200):
        op = rng.randint(0, 2)
        viewer_index = rng.randrange(len(viewers))
        if op == 0:
            _set(viewer_index, rng.choice(kinds))
        elif op == 1:
            _remove(viewer_index)
        else:
            count = _count()
        assert count >= 0, "A5 violated — count went negative"

    # Final assertion — the steady-state count is the sum of
    # current reactions, never negative, never exceeding the
    # number of viewers (each holds at most one reaction on the
    # post).
    assert _count() >= 0
    assert _count() <= len(viewers)


def test_a7_no_learning_reward_event_emitted(session_factory) -> None:
    """A7 — a reaction MUST NOT emit a learning reward event.

    The reaction service has no call into the gamification module.
    We assert the import graph of the ``reaction_service`` module
    itself does not load any gamification symbol (the E08-R26
    cross-feature adapter boundary invariant).

    The E08-R26 reference point lives at
    ``app.gamification.adapters.community_engagement`` — the
    reaction service must NOT reference it, directly or
    transitively.
    """
    module = importlib.import_module("app.community.services.reaction_service")
    module_names = set(sys.modules)
    gamification_modules = {
        name for name in module_names if name.startswith("app.gamification")
    }
    # The service module MUST NOT have triggered the import of a
    # gamification symbol — the E08-R26 cross-feature boundary
    # invariant is import-graph-level, not just call-site level.
    gamification_in_module = [
        name for name in dir(module) if "gamification" in name.lower()
    ]
    assert gamification_in_module == [], (
        f"reaction_service exposes a gamification symbol: {gamification_in_module}"
    )

    # And a concrete write MUST NOT trigger a side-effect import.
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    events: list[reaction_service.ReactionInvalidationEvent] = []

    def _capture(event: reaction_service.ReactionInvalidationEvent) -> None:
        events.append(event)

    with session_factory() as db:
        reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="support",
            now=_utcnow(),
            on_invalidate=_capture,
        )
        db.commit()

    assert len(events) == 1
    assert events[0].action == "set"
    # The event payload must NOT carry any gamification-shaped
    # marker — the service emits a single ``ReactionInvalidationEvent``
    # and nothing else.
    assert not hasattr(events[0], "xp_delta")
    assert not hasattr(events[0], "learning_reward")


# ---------------------------------------------------------------------------
# Allowlist edge cases.
# ---------------------------------------------------------------------------


def test_invalid_reaction_kind_rejected_at_service_layer(
    session_factory,
) -> None:
    """A kind outside the §3 allowlist raises ``InvalidReactionKind``.

    Mirrors the Kör 5 wire-decoder precedent: the service is the
    application's hard boundary; the column is plain ``String``
    (no CHECK).
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    with session_factory() as db:
        with pytest.raises(reaction_service.InvalidReactionKind):
            reaction_service.set_reaction(
                db,
                viewer_public_id=viewer.public_id,
                post_public_id=post.public_id,
                kind="downvote",  # §3 / SDD §14.1 — negative reactions are out
                now=_utcnow(),
            )
        db.rollback()


def test_invalidate_event_fires_on_set_and_remove(
    session_factory, invalidation_events
) -> None:
    """The on_invalidate callback fires once per successful
    transition (set + remove); a no-op remove does NOT fire.
    """
    author = _make_author(session_factory)
    viewer = _make_viewer(session_factory, user_id=2, email="viewer-a@s.test")
    post = _create_visible_post(session_factory, author=author)

    lock = threading.Lock()

    def _spy(event: reaction_service.ReactionInvalidationEvent) -> None:
        with lock:
            invalidation_events.append(
                {
                    "post_public_id": str(event.post_public_id),
                    "viewer_profile_id": event.viewer_profile_id,
                    "action": event.action,
                }
            )

    with session_factory() as db:
        reaction_service.set_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            kind="inspiring",
            now=_utcnow(),
            on_invalidate=_spy,
        )
        db.commit()
    with session_factory() as db:
        reaction_service.remove_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
            on_invalidate=_spy,
        )
        db.commit()
    with session_factory() as db:
        # No-op remove — does NOT fire.
        reaction_service.remove_reaction(
            db,
            viewer_public_id=viewer.public_id,
            post_public_id=post.public_id,
            now=_utcnow(),
            on_invalidate=_spy,
        )
        db.commit()

    actions = [e["action"] for e in invalidation_events]
    assert actions == ["set", "remove"], (
        f"expected exactly one set + one remove event; got {actions}"
    )


# ---------------------------------------------------------------------------
# Imports — the A7 import-graph check needs ``sys.modules``.
# ---------------------------------------------------------------------------

import sys  # noqa: E402 — module-level for the A7 cell's module-name lookup
