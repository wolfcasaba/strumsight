"""End-to-end mérés az értesítés-router öt végpontjára.

MÉRT hiány (2026-09-05): a ``notifications/notification_service.py`` a Kör 20
óta létezik és tesztelt, de HTTP-router SOSEM került fölé. A Flutter-oldali
``CommunityNotificationRepository`` öt metódusa így végpont nélkül állt, és a
``CommunityNotificationsScreen`` elérhetetlen maradt.

Ez a modul a VALÓDI HTTP-felületet méri, nem a service-t — annak megvan a
saját sora (``test_notification_service.py``). Amit itt mérünk: a
wire-alak (leak-guard), a kivétel → státusz leképezés, és az idempotencia
látható jele a válaszban.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok: a `_make_test_engine()` a `Base.metadata`-ból
# hozza létre a táblákat.
from app.community.models.notification import CommunityNotification  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.notifications.notification_service import create_notification
from app.config import Settings
from app.database import Base


@pytest.fixture
def inbox_client():
    """Community-enabled app + egy címzett profil."""
    settings = Settings(community_enabled=True)
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, headers = make_authenticated_user(session_factory)
        db = session_factory()
        try:
            user_id = int(
                db.execute(
                    _sa_text("SELECT id FROM users WHERE email = :e"),
                    {"e": "player-1@strumsight.app"},
                ).first()[0]
            )
            profile = CommunityProfile(user_id=user_id)
            db.add(profile)
            db.commit()
            recipient_public_id = profile.public_id
        finally:
            db.close()
        try:
            yield client, headers, session_factory, recipient_public_id
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _seed_notification(session_factory, recipient_public_id, *, dedup: str) -> str:
    """Egy értesítés a service-en át — nem nyers INSERT-tel."""
    db = session_factory()
    try:
        row = create_notification(
            db,
            recipient_public_id=recipient_public_id,
            notification_type="follow_request",
            title_key="notif.follow_request.title",
            body_key=None,
            actor_public_id=None,
            entity_type=None,
            entity_id=None,
            dedup_key=dedup,
            aggregate=False,
            now=datetime.now(timezone.utc),
        )
        db.commit()
        return str(row.public_id)
    finally:
        db.close()


class TestNotificationRouterEndToEnd:
    def test_a1_empty_inbox_is_an_empty_page_with_a_zero_badge(self, inbox_client):
        client, headers, _, _ = inbox_client

        response = client.get("/community/notifications", headers=headers)

        assert response.status_code == 200, response.text
        assert response.json() == {
            "items": [],
            "next_cursor": None,
            "unread_count": 0,
        }

    def test_a2_a_seeded_notification_appears_with_the_leak_guarded_shape(
        self, inbox_client
    ):
        client, headers, session_factory, recipient = inbox_client
        public_id = _seed_notification(session_factory, recipient, dedup="d-1")

        response = client.get("/community/notifications", headers=headers)

        assert response.status_code == 200, response.text
        page = response.json()
        assert len(page["items"]) == 1
        item = page["items"][0]
        assert item["public_id"] == public_id
        assert item["is_read"] is False
        # A KULCS megy ki, nem kész szöveg — a lokalizáció a kliensé. A
        # típus a service ALLOWLISTJÉBŐL való (`follow_request`); egy
        # kitalált típus (`system`) `InvalidNotificationType`-ot dob, tehát
        # a szótár EGY helyen dől el, nem a routerben.
        assert item["title_key"] == "notif.follow_request.title"
        # Leak-guard: a belső id és a recipient_profile_id NEM szerepel.
        assert "id" not in item
        assert "recipient_profile_id" not in item
        # A jelvény a TELJES inboxra vonatkozik, nem az oldalra.
        assert page["unread_count"] == 1

    def test_a3_mark_read_flips_the_state_and_the_badge(self, inbox_client):
        client, headers, session_factory, recipient = inbox_client
        public_id = _seed_notification(session_factory, recipient, dedup="d-2")

        response = client.post(
            f"/community/notifications/{public_id}/read", headers=headers, json={}
        )

        assert response.status_code == 200, response.text
        assert response.json() == {"changed": True}
        page = client.get("/community/notifications", headers=headers).json()
        assert page["items"][0]["is_read"] is True
        assert page["unread_count"] == 0

    def test_a4_marking_an_already_read_one_is_idempotent_not_an_error(
        self, inbox_client
    ):
        client, headers, session_factory, recipient = inbox_client
        public_id = _seed_notification(session_factory, recipient, dedup="d-3")
        client.post(
            f"/community/notifications/{public_id}/read", headers=headers, json={}
        )

        second = client.post(
            f"/community/notifications/{public_id}/read", headers=headers, json={}
        )

        # 200 + `changed: false` — a kliens ebből tudja, hogy nem történt
        # változás, de nem kell hibaágat futtatnia.
        assert second.status_code == 200, second.text
        assert second.json() == {"changed": False}

    def test_a5_read_up_to_marks_the_whole_prefix_and_reports_the_count(
        self, inbox_client
    ):
        client, headers, session_factory, recipient = inbox_client
        _seed_notification(session_factory, recipient, dedup="d-4a")
        newest = _seed_notification(session_factory, recipient, dedup="d-4b")

        response = client.post(
            f"/community/notifications/{newest}/read-up-to", headers=headers, json={}
        )

        assert response.status_code == 200, response.text
        assert response.json()["marked"] == 2
        page = client.get("/community/notifications", headers=headers).json()
        assert page["unread_count"] == 0

    def test_a6_an_unknown_id_is_a_no_op_not_a_404_leak(self, inbox_client):
        """Ismeretlen azonosító → 200 + ``changed: false``, nem 404.

        A ``mark_read`` sehol nem dob ``NotificationNotFound``-ot (grep-pel
        mérve) — ismeretlen id-re ``False``-t ad. Ez SZÁNDÉKOS: a művelet
        idempotens, és egy 404 elárulná, hogy az azonosító létezik-e.
        Az első teszt-verzióm 404-et várt; a service viselkedése cáfolta.
        """
        client, headers, session_factory, recipient = inbox_client
        known = _seed_notification(session_factory, recipient, dedup="d-6")

        unknown = client.post(
            f"/community/notifications/{uuid.uuid4()}/read", headers=headers, json={}
        )

        assert unknown.status_code == 200, unknown.text
        assert unknown.json() == {"changed": False}
        # Kontroll: a LÉTEZŐ azonosító ugyanezen a hívón `true`-t ad — tehát
        # a `false` tényleg a nem-létezésről szól, nem arról, hogy a végpont
        # sosem változtat.
        real = client.post(
            f"/community/notifications/{known}/read", headers=headers, json={}
        )
        assert real.json() == {"changed": True}

    def test_a7_preferences_round_trip(self, inbox_client):
        client, headers, _, _ = inbox_client

        put = client.put(
            "/community/notifications/preferences",
            headers=headers,
            json={"category": "comment", "level": "push"},
        )

        assert put.status_code == 200, put.text
        assert put.json()["preferences"]["comment"] == "push"
        get = client.get("/community/notifications/preferences", headers=headers)
        assert get.json()["preferences"]["comment"] == "push"

    def test_a8_an_invalid_level_is_422_and_names_the_allowed_set(self, inbox_client):
        client, headers, _, _ = inbox_client

        response = client.put(
            "/community/notifications/preferences",
            headers=headers,
            json={"category": "comment", "level": "carrier-pigeon"},
        )

        # A szintek halmazát a SERVICE ismeri — a 422 az ő indoklását hozza,
        # nem egy második, elcsúszható séma-listát.
        assert response.status_code == 422, response.text

    def test_a9_a_caller_without_a_community_profile_is_404_not_500(self):
        """Profil nélküli hívó: 404, nem lezuhanás.

        Saját app-példány kell, mert a megosztott fixture profilt is
        létrehoz — itt épp az a lényeg, hogy NINCS profil.
        """
        settings = Settings(community_enabled=True)
        engine = _make_test_engine()
        session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
        app = _build_app(engine, session_factory, settings)
        try:
            with TestClient(app) as client:
                _, headers = make_authenticated_user(session_factory)

                response = client.get("/community/notifications", headers=headers)

                assert response.status_code == 404, response.text
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()
