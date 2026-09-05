"""End-to-end mérés a komment-router négy végpontjára.

MÉRT hiány (2026-09-05): a ``services/comment_service.py`` a Kör 12 óta
létezik és tesztelt, de HTTP-router SOSEM került fölé. A Flutter-oldali
``CommunityPostRepository`` négy komment-metódusának így nem volt mit hívnia,
és a ``CommentsScreen`` elérhetetlen maradt.

Ez a modul a VALÓDI HTTP-felületet méri (TestClient a felcsatolt
aggregátoron), nem a service-t közvetlenül — a service-nek megvan a saját
tesztsora (``test_comment_service.py``). Amit itt mérünk, az kizárólag az,
amit a router hozzátesz: azonosító-feloldás, kivétel → státusz leképezés,
wire-alak, és a `community_writes_enabled` regisztrációs kapu.
"""

from __future__ import annotations

import uuid

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

from app.community import build_community_router

# A modell-importok LOAD-BEARING-ek: a `_make_test_engine()` a
# `Base.metadata`-ból hozza létre a táblákat, tehát a poszt- és
# komment-tábla csak akkor születik meg, ha az ORM-osztályuk már
# regisztrálva van (ugyanaz a minta, amit a conftest a `handle_history`
# importjánál dokumentál).
from app.community.models.comment import CommunityComment  # noqa: F401
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.config import Settings
from app.database import Base


def _create_profile(session_factory, headers_owner_user_id: int) -> None:
    """Community-profil a felhasználóhoz — a router 404-et ad enélkül.

    ORM-en át, nem nyers SQL-lel: a `community_profiles` több NOT NULL
    oszlopot hordoz (`created_at`), amiket az ORM alapértékei töltenek.
    """
    db = session_factory()
    try:
        db.add(CommunityProfile(user_id=headers_owner_user_id))
        db.commit()
    finally:
        db.close()


def _user_id_from(session_factory, email: str) -> int:
    db = session_factory()
    try:
        row = db.execute(
            _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
        ).first()
        assert row is not None
        return int(row[0])
    finally:
        db.close()


@pytest.fixture
def writes_enabled_client():
    """Saját app-példány BEKAPCSOLT írási kapuval.

    A megosztott `community_enabled` fixture `Settings(community_enabled=True)`
    értékkel épít, tehát a `community_writes_enabled` alapból HAMIS, és az
    írási route-ok NEM regisztrálódnak (ADR 0497 D2 — regisztrációs kapu, nem
    futásidejű 403). A komment-írás méréséhez ezért saját példány kell; a
    megosztott fixture átírása a többi teszt hatókörét mozdítaná el.
    """
    settings = Settings(community_enabled=True, community_writes_enabled=True)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        try:
            yield client, session_factory
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


@pytest.fixture
def authored_post(writes_enabled_client) -> tuple[TestClient, dict[str, str], str]:
    """Egy létező, saját poszt — a komment-végpontok bemenete."""
    client, session_factory = writes_enabled_client
    _, headers = make_authenticated_user(session_factory)
    user_id = _user_id_from(session_factory, "player-1@strumsight.app")
    _create_profile(session_factory, user_id)

    response = client.post(
        "/community/posts",
        headers=headers,
        json={
            "audience": "public",
            "body": "a poszt, ami alá kommentelünk",
            "idempotency_key": "post-for-comments",
        },
    )
    assert response.status_code == 201, response.text
    return client, headers, response.json()["public_id"]


class TestCommentRouterEndToEnd:
    def test_a1_create_returns_201_and_the_wire_shape(self, authored_post):
        client, headers, post_id = authored_post

        response = client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "első komment", "idempotency_key": "c-1"},
        )

        assert response.status_code == 201, response.text
        payload = response.json()
        # A wire-alak minden azonosítója opaque public_id, sosem belső id.
        assert uuid.UUID(payload["public_id"])
        assert payload["post_public_id"] == post_id
        assert uuid.UUID(payload["author_public_id"])
        assert payload["parent_public_id"] is None
        assert payload["body"] == "első komment"
        assert payload["depth"] == 0
        assert payload["deleted_at"] is None
        # A resource_version az optimista konkurencia tokenje.
        assert payload["resource_version"]

    def test_a2_list_returns_the_created_comment(self, authored_post):
        client, headers, post_id = authored_post
        client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "listázandó", "idempotency_key": "c-2"},
        )

        response = client.get(f"/community/posts/{post_id}/comments", headers=headers)

        assert response.status_code == 200, response.text
        page = response.json()
        assert [item["body"] for item in page["items"]] == ["listázandó"]
        assert page["next_cursor"] is None

    def test_a3_patch_updates_the_body_and_moves_resource_version(self, authored_post):
        client, headers, post_id = authored_post
        created = client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "eredeti", "idempotency_key": "c-3"},
        ).json()

        response = client.patch(
            f"/community/comments/{created['public_id']}",
            headers=headers,
            json={
                "body": "javított",
                "resource_version": created["resource_version"],
                "idempotency_key": "c-3-edit",
            },
        )

        assert response.status_code == 200, response.text
        assert response.json()["body"] == "javított"

    def test_a4_patch_with_a_stale_version_is_409_and_names_the_current_one(
        self, authored_post
    ):
        client, headers, post_id = authored_post
        created = client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "eredeti", "idempotency_key": "c-4"},
        ).json()
        client.patch(
            f"/community/comments/{created['public_id']}",
            headers=headers,
            json={
                "body": "első szerkesztés",
                "resource_version": created["resource_version"],
            },
        )

        # A MÁSODIK szerkesztés a MÁR ELAVULT verzióval megy.
        response = client.patch(
            f"/community/comments/{created['public_id']}",
            headers=headers,
            json={
                "body": "ütköző szerkesztés",
                "resource_version": created["resource_version"],
            },
        )

        assert response.status_code == 409, response.text
        detail = response.json()["detail"]
        # Egy csupasz 409 nem mondaná meg, MIHEZ képest elavult — a kliens
        # ebből tud újratölteni és újrapróbálni.
        assert detail["code"] == "stale_resource_version"
        assert detail["current_resource_version"]

    def test_a5_delete_soft_deletes_and_the_comment_leaves_the_list(
        self, authored_post
    ):
        client, headers, post_id = authored_post
        created = client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "törlendő", "idempotency_key": "c-5"},
        ).json()

        response = client.delete(
            f"/community/comments/{created['public_id']}", headers=headers
        )

        assert response.status_code == 200, response.text
        assert response.json() == {"deleted": True}
        listing = client.get(
            f"/community/posts/{post_id}/comments", headers=headers
        ).json()
        assert listing["items"] == []

    def test_a6_unknown_post_is_an_empty_page_not_a_404_leak(self, authored_post):
        """Ismeretlen poszt → ÜRES oldal, nem 404.

        Ez a service SZÁNDÉKOS leak-guardja (`list_comments`: `post is None`
        → üres oldal), és a router NEM írja felül: egy nem létező és egy a
        néző elől REJTETT poszt megkülönböztethetetlen. Egy 404 itt azt
        árulná el, hogy a poszt létezik, csak nem látható.
        """
        client, headers, post_id = authored_post
        client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "látható komment", "idempotency_key": "c-6"},
        )

        unknown = client.get(
            f"/community/posts/{uuid.uuid4()}/comments", headers=headers
        )

        assert unknown.status_code == 200, unknown.text
        assert unknown.json() == {"items": [], "next_cursor": None}
        # A kontroll: a LÉTEZŐ poszt ugyanezen a hívón NEM üres — tehát az
        # üres válasz tényleg a poszt láthatóságáról szól, nem arról, hogy a
        # végpont mindig üreset ad.
        known = client.get(f"/community/posts/{post_id}/comments", headers=headers)
        assert len(known.json()["items"]) == 1

    def test_a7_an_oversized_body_is_rejected_at_the_wire(self, authored_post):
        client, headers, post_id = authored_post

        response = client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "x" * 100_000, "idempotency_key": "c-7"},
        )

        # A séma `max_length`-je ELŐBB fog, mint a DB round-trip.
        assert response.status_code == 422, response.text

    def test_a8_an_undocumented_body_field_is_refused(self, authored_post):
        client, headers, post_id = authored_post

        response = client.post(
            f"/community/posts/{post_id}/comments",
            headers=headers,
            json={"body": "ok", "moderation_state": "visible"},
        )

        # `extra="forbid"`: a kliens nem csempészhet be nem dokumentált mezőt.
        assert response.status_code == 422, response.text


class TestCommentWritesGate:
    """A `community_writes_enabled` REGISZTRÁCIÓS kapu — nem futásidejű 403."""

    def _routes(self, *, writes_enabled: bool) -> set[tuple[str, str]]:
        settings = Settings(
            community_enabled=True,
            community_writes_enabled=writes_enabled,
        )
        router = build_community_router(settings)
        assert router is not None
        return {
            (method, route.path)
            for route in router.routes
            for method in getattr(route, "methods", set())
        }

    def test_a9_write_routes_are_absent_when_the_gate_is_off(self):
        off = self._routes(writes_enabled=False)
        on = self._routes(writes_enabled=True)

        create = ("POST", "/community/posts/{post_public_id}/comments")
        patch = ("PATCH", "/community/comments/{public_id}")
        delete = ("DELETE", "/community/comments/{public_id}")

        assert create in on and patch in on and delete in on
        # Kapu KI: a route-ok NEM regisztrálódnak — 404, nem 403.
        assert create not in off and patch not in off and delete not in off

    def test_a10_the_read_route_stays_registered_either_way(self):
        listing = ("GET", "/community/posts/{post_public_id}/comments")

        assert listing in self._routes(writes_enabled=True)
        assert listing in self._routes(writes_enabled=False)
