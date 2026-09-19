"""Klub-poszt írás: cím-forma és tagsági kapu (E17-R11).

MÉRT hiány (2026-09-06 audit §5.2, „Klub-poszt ``club_id``"): a klub-feed
(``GET /community/clubs/{id}/feed``) a ``community_posts.club_id`` oszlopra
szűr, de a poszt-írás felülete csak a BELSŐ egész azonosítót fogadta, és azt
mindenféle klub-oldali ellenőrzés NÉLKÜL írta a sorba. Két következménye
volt:

1. a Flutter kliens — ami kizárólag publikus azonosítót ismer — nem tudott
   klubba posztolni egyáltalán;
2. bármely hitelesített hívó egy egész szám kitalálásával BÁRMELYIK klub
   feedjébe betehetett egy posztot, és a klub tagjai azt a klub tartalmaként
   olvasták volna.

A modul mindkettőt méri: az új ``club_public_id`` cím-formát, és azt, hogy a
tagsági kapu MINDKÉT cím-formára fut.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok a `Base.metadata`-hoz.
from app.community.models.club import CommunityClub
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.config import Settings
from app.database import Base


def _profile_for(session_factory, email: str) -> int:
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
        return int(profile.id)
    finally:
        db.close()


@pytest.fixture
def club_post_client():
    """Klub- és írás-kapuval bekapcsolt app, tulajdonos + kívülálló."""
    settings = Settings(
        community_enabled=True,
        community_writes_enabled=True,
        community_clubs_enabled=True,
        secret_key="a-real-32-char-test-secret-key-value",  # strumsight:allow-secret teszt-fixture Settings, nem éles kulcs
    )
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, owner_headers = make_authenticated_user(
            session_factory, email="club-owner@strumsight.app"
        )
        _, outsider_headers = make_authenticated_user(
            session_factory, email="outsider@strumsight.app"
        )
        _profile_for(session_factory, "club-owner@strumsight.app")
        _profile_for(session_factory, "outsider@strumsight.app")
        try:
            yield client, owner_headers, outsider_headers, session_factory
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _create_club(client, headers, *, name: str = "Blues") -> dict:
    response = client.post(
        "/community/clubs",
        headers=headers,
        json={
            "name": name,
            "description": "leírás",
            "visibility": "public",
            "idempotency_key": f"club-{name}",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


def _internal_club_id(session_factory, public_id: str) -> int:
    db = session_factory()
    try:
        row = (
            db.query(CommunityClub)
            .filter(CommunityClub.public_id == uuid.UUID(public_id))
            .first()
        )
        assert row is not None
        return int(row.id)
    finally:
        db.close()


class TestClubPostCreate:
    """C1–C6 — a klub-poszt írás cím-formája és tagsági kapuja."""

    def test_c1_a_member_can_post_by_club_public_id(self, club_post_client):
        """C1 — a kliens PUBLIKUS azonosítóval posztol a klubba.

        Ez az a hívás, amit a Flutter oldal ténylegesen küld: belső egész
        azonosítót nem ismer, és nem is szabad ismernie (ADR 0396 §1).
        """
        client, owner, _, _ = club_post_client
        club = _create_club(client, owner)

        response = client.post(
            "/community/posts",
            headers=owner,
            json={
                "audience": "public",
                "body": "klub-poszt publikus azonosítóval",
                "club_public_id": club["public_id"],
                "idempotency_key": "c1",
            },
        )

        assert response.status_code == 201, response.text
        assert response.json()["club_public_id"] == club["public_id"]

    def test_c2_the_created_post_shows_up_in_that_clubs_feed(self, club_post_client):
        """C2 — a publikus azonosítóval írt poszt a klub feedjébe kerül.

        A cím-forma feloldása nem elég: a sor ``club_id`` oszlopának a
        klub BELSŐ azonosítóját kell kapnia, különben a feed sosem
        találja meg.
        """
        client, owner, _, _ = club_post_client
        club = _create_club(client, owner)
        created = client.post(
            "/community/posts",
            headers=owner,
            json={
                "audience": "public",
                "body": "klub-feedbe kerül",
                "club_public_id": club["public_id"],
                "idempotency_key": "c2",
            },
        )
        assert created.status_code == 201, created.text

        feed = client.get(f"/community/clubs/{club['public_id']}/feed", headers=owner)

        assert feed.status_code == 200, feed.text
        bodies = [item["body"] for item in feed.json()["items"]]
        assert bodies == ["klub-feedbe kerül"]

    def test_c3_a_non_member_is_refused_with_the_same_404_as_a_missing_club(
        self, club_post_client
    ):
        """C3 — a nem-tag NEM tud a klubba posztolni, és a válaszból nem
        derül ki, hogy a klub létezik-e."""
        client, owner, outsider, _ = club_post_client
        club = _create_club(client, owner)

        refused = client.post(
            "/community/posts",
            headers=outsider,
            json={
                "audience": "public",
                "body": "idegen poszt",
                "club_public_id": club["public_id"],
                "idempotency_key": "c3-a",
            },
        )
        unknown = client.post(
            "/community/posts",
            headers=outsider,
            json={
                "audience": "public",
                "body": "nem létező klub",
                "club_public_id": str(uuid.uuid4()),
                "idempotency_key": "c3-b",
            },
        )

        assert refused.status_code == 404, refused.text
        assert unknown.status_code == 404, unknown.text
        assert refused.json() == unknown.json()

    def test_c4_the_internal_club_id_form_is_membership_checked_too(
        self, club_post_client
    ):
        """C4 — a RÉGI cím-forma (belső egész) ugyanazon a kapun megy át.

        Ez a mért lyuk: a ``club_id`` mezőt a szolgáltatás ellenőrzés
        nélkül írta a sorba, tehát egy egész szám kitalálása elég volt egy
        idegen klub feedjébe posztolni.
        """
        client, owner, outsider, session_factory = club_post_client
        club = _create_club(client, owner)
        internal_id = _internal_club_id(session_factory, club["public_id"])

        response = client.post(
            "/community/posts",
            headers=outsider,
            json={
                "audience": "public",
                "body": "belső azonosítóval becsempészve",
                "club_id": internal_id,
                "idempotency_key": "c4",
            },
        )

        assert response.status_code == 404, response.text
        feed = client.get(f"/community/clubs/{club['public_id']}/feed", headers=owner)
        assert feed.json()["items"] == []

    def test_c5_mismatched_addressing_forms_are_a_400_not_a_silent_pick(
        self, club_post_client
    ):
        """C5 — két ellentmondó cím-forma HIBA, nem néma választás.

        Ha a szolgáltatás egyiket választaná, a hívó azt hinné, hogy a
        másik klubba posztolt.
        """
        client, owner, _, session_factory = club_post_client
        first = _create_club(client, owner, name="Blues")
        second = _create_club(client, owner, name="Jazz")
        first_internal = _internal_club_id(session_factory, first["public_id"])

        response = client.post(
            "/community/posts",
            headers=owner,
            json={
                "audience": "public",
                "body": "ellentmondás",
                "club_id": first_internal,
                "club_public_id": second["public_id"],
                "idempotency_key": "c5",
            },
        )

        assert response.status_code == 400, response.text

    def test_c6_a_post_without_a_club_is_unaffected(self, club_post_client):
        """C6 — kontroll: klub nélkül a poszt-írás változatlan, és a
        válasz ``club_public_id``-ja ``None``."""
        client, owner, _, _ = club_post_client

        response = client.post(
            "/community/posts",
            headers=owner,
            json={
                "audience": "public",
                "body": "sima poszt",
                "idempotency_key": "c6",
            },
        )

        assert response.status_code == 201, response.text
        payload = response.json()
        assert payload["club_id"] is None
        assert payload["club_public_id"] is None


class TestClubPostServiceGate:
    """C7 — a valódi-sértés próba a szolgáltatás rétegben.

    A kapu attól kapu, hogy a tagsági próba dönt; ez a cella közvetlenül a
    ``_resolve_club_for_author`` hívást méri, HTTP nélkül, hogy a router
    hibakezelése ne tudja elfedni a szolgáltatás viselkedését.
    """

    def test_c7_resolve_club_for_author_raises_for_a_non_member(self, club_post_client):
        from app.community.services.post_service import (
            ClubPostNotAllowed,
            _resolve_club_for_author,
        )

        client, owner, _, session_factory = club_post_client
        club = _create_club(client, owner)
        internal_id = _internal_club_id(session_factory, club["public_id"])

        db = session_factory()
        try:
            owner_profile_id = int(
                db.execute(
                    _sa_text(
                        "SELECT p.id FROM community_profiles p "
                        "JOIN users u ON u.id = p.user_id WHERE u.email = :e"
                    ),
                    {"e": "club-owner@strumsight.app"},
                ).first()[0]
            )
            outsider_profile_id = int(
                db.execute(
                    _sa_text(
                        "SELECT p.id FROM community_profiles p "
                        "JOIN users u ON u.id = p.user_id WHERE u.email = :e"
                    ),
                    {"e": "outsider@strumsight.app"},
                ).first()[0]
            )
            assert (
                _resolve_club_for_author(
                    db,
                    author_profile_id=owner_profile_id,
                    club_id=internal_id,
                    club_public_id=None,
                )
                == internal_id
            )
            with pytest.raises(ClubPostNotAllowed):
                _resolve_club_for_author(
                    db,
                    author_profile_id=outsider_profile_id,
                    club_id=internal_id,
                    club_public_id=None,
                )
        finally:
            db.close()

    def test_c8_a_soft_deleted_club_refuses_the_write(self, club_post_client):
        """C8 — a lágyan törölt klub nem fogad posztot.

        A tagsági sor a törléskor megmarad, tehát a tagsági próba önmagában
        átengedné; a klub-oldali ``deleted_at`` szűrő a második feltétel.
        """
        client, owner, _, session_factory = club_post_client
        club = _create_club(client, owner)

        db = session_factory()
        try:
            row = (
                db.query(CommunityClub)
                .filter(CommunityClub.public_id == uuid.UUID(club["public_id"]))
                .one()
            )
            row.deleted_at = datetime.now(timezone.utc)
            db.commit()
        finally:
            db.close()

        response = client.post(
            "/community/posts",
            headers=owner,
            json={
                "audience": "public",
                "body": "törölt klubba",
                "club_public_id": club["public_id"],
                "idempotency_key": "c8",
            },
        )

        assert response.status_code == 404, response.text
