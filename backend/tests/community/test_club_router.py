"""End-to-end mérés a klub-router végpontjaira.

MÉRT hiány (2026-09-05): a ``services/club_service.py`` a Kör 24 óta létezik
és tesztelt, és a ``ClubMembershipView`` docstringje ki is mondja, hogy „a
future router rounds it through Pydantic" — az a router SOSEM készült el. A
Flutter-oldali ``CommunityClubRepository`` kilenc metódusa így végpont nélkül
állt, és a három klub-képernyő elérhetetlen maradt.

Ez a modul a VALÓDI HTTP-felületet méri, nem a service-t — annak megvan a
saját sora (``test_club_service.py``). Amit itt mérünk: a wire-alak
(leak-guard + a néző saját szerepe), a kivétel → státusz leképezés, és a
``community_clubs_enabled`` regisztrációs kapu.
"""

from __future__ import annotations

import uuid

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok: a `_make_test_engine()` a `Base.metadata`-ból
# hozza létre a táblákat.
from app.community import build_community_router
from app.community.models.club import CommunityClub  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.config import Settings
from app.database import Base


def _profile_for(session_factory, email: str) -> uuid.UUID:
    """Community-profil a megadott e-mailű felhasználóhoz."""
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        profile = CommunityProfile(user_id=user_id)
        db.add(profile)
        db.commit()
        return profile.public_id
    finally:
        db.close()


@pytest.fixture
def clubs_client():
    """Klub-kapuval BEKAPCSOLT app + két hitelesített, profillal rendelkező user."""
    settings = Settings(community_enabled=True, community_clubs_enabled=True)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, owner_headers = make_authenticated_user(
            session_factory, email="owner@strumsight.app"
        )
        _, other_headers = make_authenticated_user(
            session_factory, email="other@strumsight.app"
        )
        owner_public = _profile_for(session_factory, "owner@strumsight.app")
        other_public = _profile_for(session_factory, "other@strumsight.app")
        try:
            yield client, owner_headers, other_headers, owner_public, other_public
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _create_club(client, headers, *, name="A klub", visibility="public") -> dict:
    response = client.post(
        "/community/clubs",
        headers=headers,
        json={
            "name": name,
            "description": "leírás",
            "visibility": visibility,
            "idempotency_key": f"club-{name}",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


class TestClubRouterEndToEnd:
    def test_a1_create_returns_201_with_the_leak_guarded_shape(self, clubs_client):
        client, owner, _, owner_public, _ = clubs_client

        club = _create_club(client, owner)

        assert uuid.UUID(club["public_id"])
        assert club["name"] == "A klub"
        assert club["owner_public_id"] == str(owner_public)
        # Leak-guard: belső id és owner_profile_id NEM megy ki.
        assert "id" not in club
        assert "owner_profile_id" not in club
        # A létrehozó azonnal tag — a `my_role` a service-ből jön.
        assert club["my_role"] is not None
        assert club["member_count"] >= 1

    def test_a2_list_shows_the_club_to_the_owner(self, clubs_client):
        client, owner, _, _, _ = clubs_client
        created = _create_club(client, owner)

        response = client.get("/community/clubs", headers=owner)

        assert response.status_code == 200, response.text
        page = response.json()
        assert created["public_id"] in [item["public_id"] for item in page["items"]]
        # A service `limit`-alapú, nem kurzoros — a mező jelen van, de üres.
        assert page["next_cursor"] is None

    def test_a3_my_role_is_per_viewer_not_a_global_field(self, clubs_client):
        """A `my_role` a NÉZŐRE vonatkozik, nem a klub tulajdonsága.

        Ez a cella azt a hibaosztályt fogja, amit a posts-router F2 javító
        köre mért: ott a szerző-azonosítót a HÍVÓÉBÓL oldották fel. Itt a
        veszély ugyanaz — ha a `my_role` a klub sorából jönne, minden néző
        a tulajdonos szerepét látná.
        """
        client, owner, other, _, _ = clubs_client
        created = _create_club(client, owner, visibility="public")

        as_owner = client.get(
            f"/community/clubs/{created['public_id']}", headers=owner
        ).json()
        as_other = client.get(
            f"/community/clubs/{created['public_id']}", headers=other
        ).json()

        assert as_owner["my_role"] is not None
        assert as_other["my_role"] is None
        # A klub AZONOS — csak a néző szerepe különbözik.
        assert as_owner["public_id"] == as_other["public_id"]
        assert as_owner["member_count"] == as_other["member_count"]

    def test_a4_member_list_carries_only_public_ids(self, clubs_client):
        client, owner, _, owner_public, _ = clubs_client
        created = _create_club(client, owner)

        response = client.get(
            f"/community/clubs/{created['public_id']}/members", headers=owner
        )

        assert response.status_code == 200, response.text
        items = response.json()["items"]
        assert len(items) >= 1
        row = items[0]
        assert row["profile_public_id"] == str(owner_public)
        assert row["role"]
        assert "profile_id" not in row
        assert "club_id" not in row

    def test_a5_join_reports_what_actually_happened(self, clubs_client):
        """A válasz megkülönbözteti a TAGSÁGOT a FÜGGŐ KÉRELEMTŐL.

        A kettő összemosása az „optimista jelölés" hibaosztálya lenne: a UI
        csatlakozottnak mutatná a felhasználót, miközben csak kérelem ment be.
        """
        client, owner, other, _, _ = clubs_client
        created = _create_club(client, owner, visibility="public")

        response = client.post(
            f"/community/clubs/{created['public_id']}/join", headers=other, json={}
        )

        assert response.status_code == 200, response.text
        assert response.json()["outcome"] in {"joined", "requested", "unchanged"}

    def test_a6_an_unknown_club_is_404_not_500(self, clubs_client):
        client, owner, _, _, _ = clubs_client

        response = client.get(f"/community/clubs/{uuid.uuid4()}", headers=owner)

        assert response.status_code == 404, response.text

    def test_a7_a_caller_without_a_community_profile_is_404(self):
        settings = Settings(community_enabled=True, community_clubs_enabled=True)
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        try:
            with TestClient(app) as client:
                _, headers = make_authenticated_user(session_factory)

                response = client.get("/community/clubs", headers=headers)

                assert response.status_code == 404, response.text
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_a8_an_undocumented_body_field_is_refused(self, clubs_client):
        client, owner, _, _, _ = clubs_client

        response = client.post(
            "/community/clubs",
            headers=owner,
            json={"name": "X", "visibility": "public", "owner_profile_id": 1},
        )

        assert response.status_code == 422, response.text


class TestClubsGate:
    """A `community_clubs_enabled` REGISZTRÁCIÓS kapu."""

    def _paths(self, *, clubs_enabled: bool) -> set[str]:
        settings = Settings(
            community_enabled=True, community_clubs_enabled=clubs_enabled
        )
        router = build_community_router(settings)
        assert router is not None
        return {route.path for route in router.routes}

    def test_a9_club_routes_are_absent_when_the_gate_is_off(self):
        on = self._paths(clubs_enabled=True)
        off = self._paths(clubs_enabled=False)

        assert "/community/clubs" in on
        # Kapu KI: a route-ok NEM regisztrálódnak — 404, nem futásidejű 403.
        assert "/community/clubs" not in off
        assert not any(path.startswith("/community/clubs") for path in off)

    def test_a10_the_other_routers_are_unaffected_by_the_clubs_gate(self):
        on = self._paths(clubs_enabled=True)
        off = self._paths(clubs_enabled=False)

        # A kapu KIZÁRÓLAG a klub-felületet mozdítja: minden más útvonal
        # mindkét álláson ott van.
        non_club_on = {p for p in on if not p.startswith("/community/clubs")}
        assert non_club_on == off
