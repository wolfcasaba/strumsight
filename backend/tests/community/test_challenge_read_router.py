"""End-to-end mérés a kihívás OLVASÓ végpontjaira — WP-H4 (2026-09-06).

MÉRT hiány: a ``routers/challenges.py`` öt útvonalat vitt, és MIND
írás volt. A kliens (``challenge_repository_impl.dart``) viszont HÁROM
GET-et hívt — ``/community/challenges``,
``/community/challenges/{id}``, ``/community/challenges/{id}/me`` —, és
mindhárom 404-et kapott; a
``docs/contracts/client-backend-endpoints.json`` ezt három
``known_gap`` sorként rögzítette is. A ``club_detail_screen.dart``
Kihívások füle ugyanezért adott vissza „nem tudjuk" állapotot.

Ez a modul a VALÓDI HTTP-felületet méri, nem a service-t. Cellák:

* **A1** — a lista a kliens által hívott útvonalon él, és a
  leak-guardolt alakot adja (belső ``id`` / ``author_profile_id``
  sehol).
* **A2** — a részlet és a saját részvétel ugyanazon a wire-alakon
  megy, amit a Dart dekóder olvas.
* **A3** — REJTETT és ISMERETLEN megkülönbözhetetlen: egy másik
  felhasználó baráti kihívása ugyanazt a 404-et adja, mint egy nem
  létező public_id.
* **A4** — lapozás: az utolsó oldalon NINCS ``next_cursor``
  (a „halted"), a nem-utolsón VAN (a „continued"), és a folytatás
  nem ismétli az első oldal sorait.
* **A5** — a klub-hatókör: a klub kihívásai a klub-végponton
  jönnek, privát klub nem-tagnak 404 (nem üres lista).
* **A6** — regisztrációs kapu: kikapcsolt modul mellett az útvonal
  NEM létezik (nem futásidejű 403).
* **A7** — blokk-viszony: a blokkolt szerző globális kihívása
  eltűnik a listából ÉS a részletről is.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok: a `_make_test_engine()` a `Base.metadata`-ból
# hozza létre a táblákat.
from app.community import build_community_router
from app.community.models.challenge import (
    CHALLENGE_INVITE_STATE_ACCEPTED,
    CHALLENGE_INVITE_STATE_SENT,
    CHALLENGE_TYPE_CLUB,
    CHALLENGE_TYPE_FRIENDS,
    CHALLENGE_TYPE_PERIODIC_GLOBAL,
    CommunityChallenge,
    CommunityChallengeInvite,
    CommunityChallengeParticipant,
)
from app.community.models.challenge_result import (  # noqa: F401
    CommunityChallengeResult,
)
from app.community.models.club import (
    CLUB_ROLE_OWNER,
    CommunityClub,
    CommunityClubMember,
)
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.community.models.safety_relationships import CommunityBlock
from app.config import Settings
from app.database import Base

_NOW = datetime(2026, 9, 6, 12, 0, tzinfo=timezone.utc)


def _profile_for(session_factory, email: str) -> int:
    """Community-profil a megadott e-mailű felhasználóhoz; belső id."""
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


def _public_id_of(session_factory, profile_id: int) -> str:
    """A profil public_id-ja KANONIKUS (kötőjeles) sztringként.

    A nyers SQL a SQLite-on 32 jegyű hexet ad vissza (a ``Uuid``
    oszlop tárolt alakja) — a wire viszont a kötőjeles alakot viszi,
    ezért a ``uuid.UUID`` normalizálás nem kozmetika: enélkül a
    cella a TÁROLT alakot mérné a wire helyett.
    """
    db = session_factory()
    try:
        raw = db.execute(
            _sa_text("SELECT public_id FROM community_profiles WHERE id = :i"),
            {"i": profile_id},
        ).first()[0]
        return str(raw if isinstance(raw, uuid.UUID) else uuid.UUID(hex=str(raw)))
    finally:
        db.close()


def _seed_challenge(
    session_factory,
    *,
    author_profile_id: int,
    challenge_type: str = CHALLENGE_TYPE_PERIODIC_GLOBAL,
    metric: str = "score",
    club_id: str | None = None,
    starts_at: datetime | None = None,
    ends_at: datetime | None = None,
    created_at: datetime | None = None,
) -> CommunityChallenge:
    """Kihívás-sor közvetlen beírása.

    Nincs „challenge létrehozás" végpont (a Kör 21 §D6 scope-shrink),
    tehát a sorok fixture-ből jönnek — ugyanúgy, ahogy a
    ``test_challenge_invite_service.py`` teszi.
    """
    db = session_factory()
    try:
        row = CommunityChallenge(
            author_profile_id=author_profile_id,
            type=challenge_type,
            metric=metric,
            difficulty=3,
            starts_at=starts_at or (_NOW - timedelta(days=1)),
            ends_at=ends_at or (_NOW + timedelta(days=7)),
            version=1,
            club_id=club_id,
            created_at=created_at or _NOW,
            updated_at=created_at or _NOW,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        db.expunge(row)
        return row
    finally:
        db.close()


def _seed_club(
    session_factory, *, owner_profile_id: int, visibility: str
) -> CommunityClub:
    db = session_factory()
    try:
        club = CommunityClub(
            owner_profile_id=owner_profile_id,
            name=f"Klub {visibility}",
            description="leírás",
            visibility=visibility,
        )
        db.add(club)
        db.flush()
        db.add(
            CommunityClubMember(
                club_id=club.id,
                profile_id=owner_profile_id,
                role=CLUB_ROLE_OWNER,
            )
        )
        db.commit()
        db.refresh(club)
        db.expunge(club)
        return club
    finally:
        db.close()


@pytest.fixture
def read_client():
    """Kihívás-olvasó app + két hitelesített, profillal rendelkező user."""
    settings = Settings(
        _env_file=None,
        database_url="sqlite://",
        community_enabled=True,
        community_clubs_enabled=True,
    )
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        make_authenticated_user(session_factory, email="a@strumsight.app")
        make_authenticated_user(session_factory, email="b@strumsight.app")
        _, headers_a = make_authenticated_user(
            session_factory, email="a2@strumsight.app"
        )
        _, headers_b = make_authenticated_user(
            session_factory, email="b2@strumsight.app"
        )
        profile_a = _profile_for(session_factory, "a2@strumsight.app")
        profile_b = _profile_for(session_factory, "b2@strumsight.app")
        try:
            yield (
                client,
                session_factory,
                headers_a,
                headers_b,
                profile_a,
                profile_b,
            )
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


class TestChallengeListEndpoint:
    def test_a1_list_lives_on_the_path_the_client_already_calls(self, read_client):
        client, factory, headers_a, _, profile_a, _ = read_client
        challenge = _seed_challenge(factory, author_profile_id=profile_a)

        response = client.get("/community/challenges", headers=headers_a)

        assert response.status_code == 200, response.text
        page = response.json()
        assert [item["public_id"] for item in page["items"]] == [
            str(challenge.public_id)
        ]
        row = page["items"][0]
        # Leak-guard: a belső azonosítók NEM mennek ki.
        assert "id" not in row
        assert "author_profile_id" not in row
        # A wire-alak a Dart `decodeChallengeDefinition` kulcsai.
        assert row["author_public_id"] == _public_id_of(factory, profile_a)
        assert row["type"] == CHALLENGE_TYPE_PERIODIC_GLOBAL
        assert row["metric"] == "score"
        assert row["difficulty"] == 3
        assert row["version"] == 1
        assert row["starts_at"] and row["ends_at"]

    def test_a3_a_foreign_friends_challenge_is_absent_from_the_list(
        self, read_client
    ):
        """A baráti kihívás a meghívottak ügye — nem a nyilvánosságé."""
        client, factory, _, headers_b, profile_a, _ = read_client
        _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_FRIENDS,
        )

        response = client.get("/community/challenges", headers=headers_b)

        assert response.status_code == 200, response.text
        assert response.json()["items"] == []

    def test_a3_the_invitee_does_see_the_friends_challenge(self, read_client):
        """Ugyanaz a sor a MEGHÍVOTTNAK látszik — a szűrő nem „mindent
        eltakar", hanem a viszonyt méri."""
        client, factory, _, headers_b, profile_a, profile_b = read_client
        challenge = _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_FRIENDS,
        )
        db = factory()
        try:
            db.add(
                CommunityChallengeInvite(
                    challenge_id=challenge.id,
                    inviter_profile_id=profile_a,
                    invitee_profile_id=profile_b,
                    state=CHALLENGE_INVITE_STATE_SENT,
                    expires_at=_NOW + timedelta(days=3),
                )
            )
            db.commit()
        finally:
            db.close()

        response = client.get("/community/challenges", headers=headers_b)

        assert response.status_code == 200, response.text
        assert [i["public_id"] for i in response.json()["items"]] == [
            str(challenge.public_id)
        ]

    def test_a4_the_last_page_carries_no_cursor(self, read_client):
        """Az utolsó oldal `next_cursor`-ja `None` — a kliens dekódere
        ebből dönti el, hogy MEGÁLLT (`halted`) vagy folytat."""
        client, factory, headers_a, _, profile_a, _ = read_client
        _seed_challenge(factory, author_profile_id=profile_a)

        response = client.get(
            "/community/challenges", headers=headers_a, params={"limit": 5}
        )

        assert response.status_code == 200, response.text
        assert response.json()["next_cursor"] is None

    def test_a4_a_full_page_carries_a_cursor_that_continues_without_repeating(
        self, read_client
    ):
        client, factory, headers_a, _, profile_a, _ = read_client
        seeded = [
            _seed_challenge(
                factory,
                author_profile_id=profile_a,
                metric=f"metric-{index}",
                created_at=_NOW - timedelta(minutes=index),
            )
            for index in range(3)
        ]

        first = client.get(
            "/community/challenges", headers=headers_a, params={"limit": 2}
        ).json()
        assert len(first["items"]) == 2
        assert first["next_cursor"] is not None

        second = client.get(
            "/community/challenges",
            headers=headers_a,
            params={"limit": 2, "cursor": first["next_cursor"]},
        ).json()

        assert second["next_cursor"] is None
        first_ids = [item["public_id"] for item in first["items"]]
        second_ids = [item["public_id"] for item in second["items"]]
        assert set(first_ids).isdisjoint(second_ids)
        assert sorted(first_ids + second_ids) == sorted(
            str(row.public_id) for row in seeded
        )

    def test_a4_a_malformed_cursor_restarts_from_the_top(self, read_client):
        """Sérült kurzor NEM 500 és nem 400: a lista elejéről indul —
        különben a lapozó kliens beragadna."""
        client, factory, headers_a, _, profile_a, _ = read_client
        _seed_challenge(factory, author_profile_id=profile_a)

        response = client.get(
            "/community/challenges",
            headers=headers_a,
            params={"cursor": "nem-egy-kurzor"},
        )

        assert response.status_code == 200, response.text
        assert len(response.json()["items"]) == 1

    def test_an_unknown_status_filter_is_422_not_a_silent_no_op(self, read_client):
        client, factory, headers_a, _, profile_a, _ = read_client
        _seed_challenge(factory, author_profile_id=profile_a)

        response = client.get(
            "/community/challenges", headers=headers_a, params={"status": "aktív"}
        )

        assert response.status_code == 422, response.text

    def test_the_status_filter_uses_server_time(self, read_client):
        client, factory, headers_a, _, profile_a, _ = read_client
        _seed_challenge(
            factory,
            author_profile_id=profile_a,
            metric="ended",
            starts_at=datetime(2020, 1, 1, tzinfo=timezone.utc),
            ends_at=datetime(2020, 2, 1, tzinfo=timezone.utc),
        )
        _seed_challenge(factory, author_profile_id=profile_a, metric="live")

        active = client.get(
            "/community/challenges", headers=headers_a, params={"status": "active"}
        ).json()
        ended = client.get(
            "/community/challenges", headers=headers_a, params={"status": "ended"}
        ).json()

        assert [item["metric"] for item in active["items"]] == ["live"]
        assert [item["metric"] for item in ended["items"]] == ["ended"]

    def test_a7_a_blocked_authors_challenge_disappears(self, read_client):
        client, factory, _, headers_b, profile_a, profile_b = read_client
        challenge = _seed_challenge(factory, author_profile_id=profile_a)
        before = client.get("/community/challenges", headers=headers_b).json()
        assert len(before["items"]) == 1

        db = factory()
        try:
            db.add(
                CommunityBlock(
                    blocker_profile_id=profile_b, blocked_profile_id=profile_a
                )
            )
            db.commit()
        finally:
            db.close()

        after = client.get("/community/challenges", headers=headers_b).json()
        detail = client.get(
            f"/community/challenges/{challenge.public_id}", headers=headers_b
        )

        assert after["items"] == []
        # A részleten is ELTŰNIK — nem csak a listából van kiszűrve.
        assert detail.status_code == 404


class TestChallengeDetailEndpoint:
    def test_a2_detail_returns_the_wire_shape_the_client_decodes(self, read_client):
        client, factory, headers_a, _, profile_a, _ = read_client
        challenge = _seed_challenge(factory, author_profile_id=profile_a)

        response = client.get(
            f"/community/challenges/{challenge.public_id}", headers=headers_a
        )

        assert response.status_code == 200, response.text
        body = response.json()
        assert body["public_id"] == str(challenge.public_id)
        assert body["club_id"] is None
        assert "id" not in body

    def test_a3_hidden_and_unknown_are_indistinguishable(self, read_client):
        """A leak-guard cellája: a REJTETT sor és a NEM LÉTEZŐ
        public_id ugyanazt a státuszt ÉS ugyanazt a szöveget adja."""
        client, factory, _, headers_b, profile_a, _ = read_client
        hidden = _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_FRIENDS,
        )

        hidden_response = client.get(
            f"/community/challenges/{hidden.public_id}", headers=headers_b
        )
        unknown_response = client.get(
            f"/community/challenges/{uuid.uuid4()}", headers=headers_b
        )

        assert hidden_response.status_code == unknown_response.status_code == 404
        assert hidden_response.json() == unknown_response.json()


class TestMyParticipationEndpoint:
    def test_a2_no_participation_is_a_200_with_a_null_participant(self, read_client):
        """A „nem veszel részt" ÁLLÍTÁS (200 + null), nem hiba (404) —
        a két jelentés összemosása elárulná egy rejtett sor létét."""
        client, factory, headers_a, _, profile_a, _ = read_client
        challenge = _seed_challenge(factory, author_profile_id=profile_a)

        response = client.get(
            f"/community/challenges/{challenge.public_id}/me", headers=headers_a
        )

        assert response.status_code == 200, response.text
        assert response.json() == {"participant": None}

    def test_a2_a_participant_row_carries_the_state_and_the_best_metric(
        self, read_client
    ):
        client, factory, _, headers_b, profile_a, profile_b = read_client
        challenge = _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_FRIENDS,
        )
        db = factory()
        try:
            db.add(
                CommunityChallengeInvite(
                    challenge_id=challenge.id,
                    inviter_profile_id=profile_a,
                    invitee_profile_id=profile_b,
                    state=CHALLENGE_INVITE_STATE_ACCEPTED,
                    expires_at=_NOW + timedelta(days=3),
                )
            )
            db.add(
                CommunityChallengeParticipant(
                    challenge_id=challenge.id,
                    participant_profile_id=profile_b,
                    best_metric_value=4200,
                )
            )
            db.commit()
        finally:
            db.close()

        response = client.get(
            f"/community/challenges/{challenge.public_id}/me", headers=headers_b
        )

        assert response.status_code == 200, response.text
        participant = response.json()["participant"]
        assert participant["participant_public_id"] == _public_id_of(
            factory, profile_b
        )
        assert participant["invite_state"] == CHALLENGE_INVITE_STATE_ACCEPTED
        assert participant["best_metric_value"] == 4200
        assert "challenge_id" not in participant

    def test_a3_a_hidden_challenge_is_404_not_a_null_participant(self, read_client):
        client, factory, _, headers_b, profile_a, _ = read_client
        hidden = _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_FRIENDS,
        )

        response = client.get(
            f"/community/challenges/{hidden.public_id}/me", headers=headers_b
        )

        assert response.status_code == 404, response.text


class TestClubChallengesEndpoint:
    def test_a5_the_club_tab_endpoint_returns_the_clubs_active_challenges(
        self, read_client
    ):
        client, factory, headers_a, _, profile_a, _ = read_client
        club = _seed_club(factory, owner_profile_id=profile_a, visibility="public")
        in_club = _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_CLUB,
            club_id=str(club.public_id),
        )
        # Ugyanennek a szerzőnek egy klubon KÍVÜLI kihívása: nem
        # szabad megjelennie a klub fülén.
        _seed_challenge(factory, author_profile_id=profile_a, metric="global")

        response = client.get(
            f"/community/clubs/{club.public_id}/challenges", headers=headers_a
        )

        assert response.status_code == 200, response.text
        page = response.json()
        assert [item["public_id"] for item in page["items"]] == [
            str(in_club.public_id)
        ]
        assert page["items"][0]["club_id"] == str(club.public_id)

    def test_a5_an_empty_club_returns_an_empty_list_not_an_error(self, read_client):
        client, factory, headers_a, _, profile_a, _ = read_client
        club = _seed_club(factory, owner_profile_id=profile_a, visibility="public")

        response = client.get(
            f"/community/clubs/{club.public_id}/challenges", headers=headers_a
        )

        assert response.status_code == 200, response.text
        assert response.json()["items"] == []

    def test_a5_a_private_club_is_404_for_a_non_member_not_an_empty_list(
        self, read_client
    ):
        """A klub-kapu ELŐBB dől el, mint a szűrés: egy üres lista
        elárulná, hogy a klub LÉTEZIK."""
        client, factory, _, headers_b, profile_a, _ = read_client
        club = _seed_club(factory, owner_profile_id=profile_a, visibility="private")
        _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_CLUB,
            club_id=str(club.public_id),
        )

        response = client.get(
            f"/community/clubs/{club.public_id}/challenges", headers=headers_b
        )

        assert response.status_code == 404, response.text

    def test_a5_a_private_clubs_challenge_is_hidden_from_the_global_list_too(
        self, read_client
    ):
        """A privát klub kihívása a fő listából is kiesik — különben a
        klub-kapu megkerülhető lenne egy sima lista-kéréssel."""
        client, factory, _, headers_b, profile_a, _ = read_client
        club = _seed_club(factory, owner_profile_id=profile_a, visibility="private")
        _seed_challenge(
            factory,
            author_profile_id=profile_a,
            challenge_type=CHALLENGE_TYPE_CLUB,
            club_id=str(club.public_id),
        )

        response = client.get("/community/challenges", headers=headers_b)

        assert response.status_code == 200, response.text
        assert response.json()["items"] == []


class TestRegistrationLevelGate:
    def test_a6_the_read_routes_do_not_exist_when_the_module_is_off(self):
        """ADR 0497 D1 — kikapcsolva az útvonal NEM regisztrálódik
        (sima 404), nem futásidejű 403."""
        settings = Settings(
            _env_file=None, database_url="sqlite://", community_enabled=False
        )
        engine = _make_test_engine()
        session_factory = sessionmaker(
            bind=engine, autoflush=False, autocommit=False
        )
        app = _build_app(engine, session_factory, settings)
        try:
            paths = {
                route.path
                for route in app.routes
                if getattr(route, "path", "").startswith("/community")
            }
            assert paths == set()
            with TestClient(app) as client:
                assert client.get("/community/challenges").status_code == 404
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()

    def test_a6_the_club_challenges_route_follows_the_clubs_sub_flag(self):
        settings = Settings(
            _env_file=None,
            database_url="sqlite://",
            community_enabled=True,
            community_clubs_enabled=False,
        )
        engine = _make_test_engine()
        session_factory = sessionmaker(
            bind=engine, autoflush=False, autocommit=False
        )
        app = _build_app(engine, session_factory, settings)
        try:
            paths = {getattr(route, "path", "") for route in app.routes}
            # A kihívás-olvasás megvan…
            assert "/community/challenges" in paths
            # …a klub-hatókörű viszont a klub-kapu alatt áll.
            assert "/community/clubs/{public_id}/challenges" not in paths
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()
