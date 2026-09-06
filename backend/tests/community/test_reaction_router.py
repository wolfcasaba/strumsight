"""End-to-end mérés a reakció-router végpontjaira.

MÉRT hiány (2026-09-05): a ``services/reaction_service.py`` a Kör 15 óta
létezik és tesztelt, és a modul docstringje ki is mondja, hogy „the wire
router is **not** in this round's ``allowed_paths``" — az a router SOSEM
készült el. A ``CommunityPostRepository.setReaction`` és a ``ReactionBar``
widget így végpont nélkül állt.

Ez a modul a VALÓDI HTTP-felületet méri, nem a service-t — annak megvan a
saját sora (``test_reaction_service.py``). Amit itt mérünk: a wire-alak (a
művelet UTÁNI állapot), a fajta-váltás számláló-semlegessége, a kivétel →
státusz leképezés, a néző-szerinti szétválasztás, és a
``community_writes_enabled`` regisztrációs kapu.
"""

from __future__ import annotations

import uuid

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok a `Base.metadata`-hoz.
from app.community import build_community_router
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import (  # noqa: F401
    REACTION_KIND_ALLOWLIST,
    CommunityReaction,
)
from app.config import Settings
from app.database import Base


def _profile_for(session_factory, email: str) -> None:
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        db.add(CommunityProfile(user_id=user_id))
        db.commit()
    finally:
        db.close()


@pytest.fixture
def reactions_client():
    """Írás-kapuval BEKAPCSOLT app + két hitelesített, profillal rendelkező user."""
    settings = Settings(community_enabled=True, community_writes_enabled=True)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, author = make_authenticated_user(
            session_factory, email="author@strumsight.app"
        )
        _, other = make_authenticated_user(
            session_factory, email="other@strumsight.app"
        )
        _profile_for(session_factory, "author@strumsight.app")
        _profile_for(session_factory, "other@strumsight.app")
        try:
            yield client, author, other
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _create_post(client, headers, *, key: str = "post-1") -> str:
    response = client.post(
        "/community/posts",
        headers=headers,
        json={"audience": "public", "body": "poszt", "idempotency_key": key},
    )
    assert response.status_code == 201, response.text
    return response.json()["public_id"]


def _react(client, headers, post_id: str, kind: str, *, key: str | None = None):
    return client.put(
        f"/community/posts/{post_id}/reaction",
        headers=headers,
        json={"kind": kind, "idempotency_key": key},
    )


class TestReactionRouterEndToEnd:
    def test_a1_setting_a_reaction_returns_the_state_after(self, reactions_client):
        client, author, _ = reactions_client
        post_id = _create_post(client, author)

        response = _react(client, author, post_id, "support")

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["post_public_id"] == post_id
        assert body["viewer_reaction"] == "support"
        assert body["reaction_count"] == 1

    def test_a2_the_same_kind_twice_does_not_inflate_the_count(self, reactions_client):
        """Idempotens a `(poszt, néző)` páron.

        Egy dupla koppintás vagy egy hálózati újrapróbálkozás NEM ad
        második reakciót — a `UNIQUE(post_id, profile_id)` az igazságforrás.
        """
        client, author, _ = reactions_client
        post_id = _create_post(client, author)

        _react(client, author, post_id, "support")
        second = _react(client, author, post_id, "support")

        assert second.status_code == 200, second.text
        assert second.json()["reaction_count"] == 1

    def test_a3_changing_the_kind_leaves_the_count_unchanged(self, reactions_client):
        """A fajta-váltás UPDATE ugyanazon a soron, nem új sor.

        Ez az a cella, ami miatt a válasz az ÁLLAPOTOT hordozza: egy
        kliensoldali „+1 / -1" logika itt tévedne, mert a számláló nem
        mozdul, a néző saját reakciója viszont igen.
        """
        client, author, _ = reactions_client
        post_id = _create_post(client, author)
        _react(client, author, post_id, "support")

        changed = _react(client, author, post_id, "celebrate")

        assert changed.status_code == 200, changed.text
        assert changed.json()["viewer_reaction"] == "celebrate"
        assert changed.json()["reaction_count"] == 1

    def test_a4_an_invalid_kind_is_422_and_names_the_allowed_kinds(
        self, reactions_client
    ):
        """A hibaüzenet FELSOROLJA az érvényes fajtákat.

        Enélkül a kliens csak annyit tudna, hogy „rossz", azt nem, hogy mi
        lett volna jó — a router ezért nem írja felül a service üzenetét.
        """
        client, author, _ = reactions_client
        post_id = _create_post(client, author)

        response = _react(client, author, post_id, "nemletezo")

        assert response.status_code == 422, response.text
        detail = str(response.json()["detail"])
        for kind in REACTION_KIND_ALLOWLIST:
            assert kind in detail

    def test_a5_remove_is_idempotent_and_never_goes_negative(self, reactions_client):
        client, author, _ = reactions_client
        post_id = _create_post(client, author)
        _react(client, author, post_id, "support")

        first = client.delete(f"/community/posts/{post_id}/reaction", headers=author)
        second = client.delete(f"/community/posts/{post_id}/reaction", headers=author)

        assert first.status_code == 200, first.text
        assert first.json()["viewer_reaction"] is None
        assert first.json()["reaction_count"] == 0
        # A második törlés NEM hibaág — nincs mit eltávolítani.
        assert second.status_code == 200, second.text
        assert second.json()["reaction_count"] == 0

    def test_a6_viewer_reaction_is_per_viewer_the_count_is_global(
        self, reactions_client
    ):
        """A néző saját reakciója a NÉZŐÉ, a számláló a teljes halmazé.

        Ha a `viewer_reaction` a poszt sorából jönne, minden néző a
        szerzőét látná — ugyanaz a hibaosztály, amit a klub `my_role`
        cellája és a feed A4 cellája mér.
        """
        client, author, other = reactions_client
        post_id = _create_post(client, author)

        _react(client, author, post_id, "support")
        as_other = _react(client, other, post_id, "helpful")

        assert as_other.json()["viewer_reaction"] == "helpful"
        assert as_other.json()["reaction_count"] == 2
        # A szerző oldalán a SAJÁT reakciója változatlan, a szám viszont 2.
        as_author = _react(client, author, post_id, "support")
        assert as_author.json()["viewer_reaction"] == "support"
        assert as_author.json()["reaction_count"] == 2

    def test_a7_an_unknown_post_is_404_on_write_but_not_on_remove(
        self, reactions_client
    ):
        """Az ismeretlen poszt az ÍRÁS ágán 404, a törlés ágán nem.

        A törlésen nincs mit eltávolítani, és egy 404 elárulná, hogy a
        poszt létezik-e — ugyanaz a leak-guard, amit a komment-lista üres
        oldala visz. A kontroll-cella: a LÉTEZŐ poszton ugyanez a hívó 200-at
        kap, tehát a 200 nem egy általános „mindenre 200" viselkedés.
        """
        client, author, _ = reactions_client
        unknown = uuid.uuid4()
        real_post = _create_post(client, author)

        write = _react(client, author, str(unknown), "support")
        remove = client.delete(f"/community/posts/{unknown}/reaction", headers=author)
        control = client.delete(
            f"/community/posts/{real_post}/reaction", headers=author
        )

        assert write.status_code == 404, write.text
        assert remove.status_code == 200, remove.text
        assert remove.json()["reaction_count"] == 0
        assert control.status_code == 200, control.text

    def test_a8_a_caller_without_a_community_profile_is_404(self):
        settings = Settings(community_enabled=True, community_writes_enabled=True)
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        try:
            with TestClient(app) as client:
                _, headers = make_authenticated_user(session_factory)

                response = _react(client, headers, str(uuid.uuid4()), "support")

                assert response.status_code == 404, response.text
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_a9_an_undocumented_body_field_is_refused(self, reactions_client):
        client, author, _ = reactions_client
        post_id = _create_post(client, author)

        response = client.put(
            f"/community/posts/{post_id}/reaction",
            headers=author,
            json={"kind": "support", "viewer_public_id": str(uuid.uuid4())},
        )

        # A néző-azonosítót a JWT adja; egy törzs-oldali felülírási út nem
        # létezik, és a séma `extra="forbid"` ezt ki is mondja.
        assert response.status_code == 422, response.text


class TestReactionWritesGate:
    """A `community_writes_enabled` REGISZTRÁCIÓS kapu (ADR 0497 D1)."""

    def _paths(self, *, writes_on: bool) -> set[str]:
        settings = Settings(community_enabled=True, community_writes_enabled=writes_on)
        router = build_community_router(settings)
        assert router is not None
        return {route.path for route in router.routes}

    def test_a10_reaction_routes_are_absent_when_writes_are_off(self):
        on = self._paths(writes_on=True)
        off = self._paths(writes_on=False)

        reaction_path = "/community/posts/{post_public_id}/reaction"
        assert reaction_path in on
        # Kapu KI: az útvonal NEM regisztrálódik — 404, nem futásidejű 403.
        assert reaction_path not in off
