"""Community (Epic 9) feature-flag defaults + readiness placeholder.

E09-R01, ADR 0395 — the test asserts the §6 / §6.1 acceptance matrix on the
backend side. The five ``community_*_enabled`` fields default to ``False`` in
every environment (no env-aware flip like ``diagnostics_enabled``), and a
``Settings`` constructed with explicit kwargs must honour each one
independently.

The ``community_postgres_ready`` property is a Kör-2 hand-off placeholder —
it answers *only* the URL-shape question (SQLite vs PostgreSQL); the full
readiness predicate is E09-R02's job.
"""

from __future__ import annotations

from collections.abc import Iterator

import pytest
from pydantic import ValidationError

from app.config import Settings


@pytest.fixture(autouse=True)
def _isolate_community_env(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Strip every STRUMSIGHT_COMMUNITY_*_ENABLED env var before each test.

    The CI runner and the local dev shell may both leak prior flags through
    ``pydantic-settings``, and a single leaked ``True`` would silently flip
    the matrix from red to green (the exact failure mode §6.1 names as the
    'Csak egy flag kap production-off védelmet' case). Stripping explicitly
    makes each test look at the *defaults*, no more, no less.
    """
    for key in (
        "STRUMSIGHT_COMMUNITY_ENABLED",
        "STRUMSIGHT_COMMUNITY_WRITES_ENABLED",
        "STRUMSIGHT_COMMUNITY_MEDIA_ENABLED",
        "STRUMSIGHT_COMMUNITY_LEADERBOARD_ENABLED",
        "STRUMSIGHT_COMMUNITY_CLUBS_ENABLED",
    ):
        monkeypatch.delenv(key, raising=False)
    yield


def test_community_master_switch_defaults_off() -> None:
    """A1 — ``community_enabled`` defaults to False in every environment.

    Renaming or accidentally setting the class-level default to ``True``
    would activate the entire Epic 9 surface for every deployment. The
    default must be ``False``, period.
    """
    settings = Settings()

    assert settings.community_enabled is False


@pytest.mark.parametrize(
    "field",
    [
        "community_writes_enabled",
        "community_media_enabled",
        "community_leaderboard_enabled",
        "community_clubs_enabled",
    ],
)
def test_each_subflag_defaults_off_independently(field: str) -> None:
    """§6.1 row 2 — every sub-flag defends itself.

    The §6.1 matrix names a specific failure mode: 'only one flag gets the
    production-off protection, the other four do not'. This parametrised
    test keeps each sub-flag on its own so a regression in one cannot
    piggy-back on the others. Renaming the field is a class of error this
    test will surface as a missing parametrise-case.
    """
    settings = Settings()

    assert getattr(settings, field) is False, (
        f"{field} must default to False — Epic 9 kill switch regression."
    )


def test_all_five_flags_have_the_same_default() -> None:
    """Defence in depth — assert all five are False *together* on one instance.

    The parametrised test above covers each field individually, but a
    single declaration-default typo could still flip several at once. This
    test pins the matrix as a whole so a future change that races all five
    fields to ``True`` is also caught.
    """
    settings = Settings()

    assert (
        settings.community_enabled,
        settings.community_writes_enabled,
        settings.community_media_enabled,
        settings.community_leaderboard_enabled,
        settings.community_clubs_enabled,
    ) == (False, False, False, False, False)


def test_env_var_can_flip_master_switch() -> None:
    """The STRUMSIGHT_COMMUNITY_ENABLED env var reaches the field as expected.

    Note that this is the documented *production opt-in* path. The default
    is off; an explicit flip is the only way to turn Community on.
    """
    import os

    os.environ["STRUMSIGHT_COMMUNITY_ENABLED"] = "true"
    try:
        settings = Settings()
        assert settings.community_enabled is True
        # The sub-flags remain under their own independent env-var control —
        # flipping the master does NOT cascade.
        assert settings.community_writes_enabled is False
        assert settings.community_media_enabled is False
    finally:
        os.environ.pop("STRUMSIGHT_COMMUNITY_ENABLED", None)


def test_constructor_kwargs_override_independently() -> None:
    """Each sub-flag is independently overridable through the Settings ctor.

    The acceptance table requires every sub-flag to be reachable
    individually (matrix row 2). A regression that, for instance, tied
    ``community_leaderboard_enabled`` to ``community_enabled`` would flip
    both from this single value — this test catches that.
    """
    settings = Settings(
        community_enabled=True,
        community_writes_enabled=False,
        community_media_enabled=True,
        community_leaderboard_enabled=False,
        community_clubs_enabled=True,
    )

    assert settings.community_enabled is True
    assert settings.community_writes_enabled is False
    assert settings.community_media_enabled is True
    assert settings.community_leaderboard_enabled is False
    assert settings.community_clubs_enabled is True


def test_constructor_rejects_non_bool() -> None:
    """The fields are typed ``bool`` — pydantic must reject garbage.

    A regression that loosened the type to ``str`` (to ease migration) would
    leak through to API code that does ``if settings.community_enabled``
    and quietly accept truthy strings. This test pins the contract.
    """
    with pytest.raises(ValidationError):
        Settings(community_enabled="enabled")  # type: ignore[arg-type]


def test_community_postgres_ready_is_false_for_sqlite_default() -> None:
    """A5 — the readiness placeholder answers False for SQLite URLs.

    The dev default is ``sqlite:///./strumsight.db``. Until a deployment
    switches the URL to a ``postgresql+psycopg://…`` shape, the property
    must be False — signalling that E09-R02's full PG-cut-over has not
    happened yet.
    """
    settings = Settings()  # default database_url is SQLite

    assert settings.community_postgres_ready is False


def test_community_postgres_ready_is_true_for_postgres_url() -> None:
    """A5 — the readiness placeholder answers True for PostgreSQL URLs.

    This is a *placeholder*, not a connection probe — it only inspects the
    URL shape. The full readiness predicate is E09-R02's job. Keeping this
    narrow keeps the test honest about what is and isn't being asserted.
    """
    settings = Settings(database_url="postgresql+psycopg://user:pass@host/db")

    assert settings.community_postgres_ready is True


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+psycopg://user:pass@host:5432/db",
        "postgresql://user:pass@host/db",
        "POSTGRESQL://USER:PASS@HOST/DB",  # case should not matter for prefixes
        "postgresql+psycopg2://...",
    ],
)
def test_community_postgres_ready_recognises_pg_flavours(url: str) -> None:
    """URL prefixes other than ``sqlite`` count as PG-ready.

    The property answers a boolean readiness question for the operator;
    the exact psycopg driver string is E09-R02's concern.
    """
    settings = Settings(database_url=url)

    assert settings.community_postgres_ready is True
