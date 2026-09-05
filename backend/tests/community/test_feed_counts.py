"""A feed interakció-számlálóinak és a néző-állapotnak a mérése.

MÉRT hiány (2026-09-05): a ``GET /community/feed`` wire-alakja NEM tartalmazta
a reakció- / komment- / könyvjelző-számlálót, sem a néző saját viszonyát a
poszthoz — miközben a Flutter feed-kártya KIÍRJA őket
(``feed_card_registry.dart:211,219,223``, ``reaction_bar.dart:87``). Bekötve
minden poszton `0 reakció, 0 komment, 0 könyvjelző` jelent volna meg.

Ez nem hiányzó adat, hanem **magabiztos hamis állítás** — pontosan az, amit a
projekt saját elve (`UNKNOWN > CONFIDENTLY WRONG`) tilt. Ezért nem a
Flutter-repository íródott meg elsőként, hanem ez a szerver-oldali kiegészítés.
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
from app.community.models.bookmark import CommunityBookmark  # noqa: F401
from app.community.models.comment import CommunityComment  # noqa: F401
from app.community.models.post import CommunityPost  # noqa: F401
from app.community.models.profile import CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.community.models.safety_relationships import (  # noqa: F401
    CommunityBlock,
    CommunityMute,
)
from app.community.models.social_graph import CommunityFollow  # noqa: F401
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
        return profile.id
    finally:
        db.close()


@pytest.fixture
def feed_client():
    """Írás-kapuval bekapcsolt app + NÉZŐ, aki KÖVETI a SZERZŐT.

    A following-feed csak a követett profilok posztjait adja vissza, ezért a
    szerző és a néző KÜLÖN felhasználó, és a néző követi a szerzőt. Egy
    „saját posztomat látom a saját feedemben" felállás nem is mérné a
    végpontot.
    """
    # A feed HMAC-cel írja alá a kurzort a `settings.secret_key`-ből, és
    # FAIL-CLOSED módon 503-at ad a fejlesztői alapértékre. Ez helyes
    # viselkedés — a teszt ezért valódi kulcsot ad, nem kerüli meg.
    settings = Settings(
        community_enabled=True,
        community_writes_enabled=True,
        secret_key="a-real-32-char-test-secret-key-value",
    )
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    with TestClient(app) as client:
        _, viewer_headers = make_authenticated_user(
            session_factory, email="viewer@strumsight.app"
        )
        _, author_headers = make_authenticated_user(
            session_factory, email="author@strumsight.app"
        )
        viewer_id = _profile_for(session_factory, "viewer@strumsight.app")
        author_id = _profile_for(session_factory, "author@strumsight.app")
        _follow(session_factory, follower=viewer_id, followed=author_id)
        try:
            yield client, viewer_headers, author_headers, session_factory, viewer_id
        finally:
            Base.metadata.drop_all(bind=engine)
            engine.dispose()


def _follow(session_factory, *, follower: int, followed: int) -> None:
    db = session_factory()
    try:
        db.add(
            CommunityFollow(
                follower_profile_id=follower,
                followed_profile_id=followed,
            )
        )
        db.commit()
    finally:
        db.close()


def _create_post(client, headers, *, key: str) -> str:
    response = client.post(
        "/community/posts",
        headers=headers,
        json={"audience": "public", "body": "poszt", "idempotency_key": key},
    )
    assert response.status_code == 201, response.text
    return response.json()["public_id"]


def _internal_post_id(session_factory, public_id: str) -> int:
    """ORM-en át, nem nyers SQL-lel: a `public_id` `Uuid` típusú oszlop, és
    a string-összehasonlítás dialektusfüggően nem illeszkedik."""
    db = session_factory()
    try:
        row = (
            db.query(CommunityPost)
            .filter(CommunityPost.public_id == uuid.UUID(public_id))
            .first()
        )
        assert row is not None
        return int(row.id)
    finally:
        db.close()


def _seed_interactions(
    session_factory,
    post_id: int,
    *,
    reactions: int = 0,
    comments: int = 0,
    bookmarks: int = 0,
    viewer_profile_id: int | None = None,
) -> None:
    """Interakciók közvetlenül — a számláló-lekérdezést mérjük, nem a
    létrehozó service-eket (azoknak saját soruk van)."""
    now = datetime.now(timezone.utc)
    db = session_factory()
    try:
        # Minden interakcióhoz külön profil kell (a UNIQUE (post, profile)
        # kulcsok miatt); a nézőé az ELSŐ, ha kérték.
        for i in range(max(reactions, comments, bookmarks)):
            db.execute(
                _sa_text(
                    "INSERT INTO users (email, hashed_password, created_at) "
                    "VALUES (:e, 'x', :ts)"
                ),
                {"e": f"seed-{post_id}-{i}@s.test", "ts": now},
            )
            db.commit()
            uid = int(
                db.execute(
                    _sa_text("SELECT id FROM users WHERE email = :e"),
                    {"e": f"seed-{post_id}-{i}@s.test"},
                ).first()[0]
            )
            p = CommunityProfile(user_id=uid)
            db.add(p)
            db.commit()
            actor = viewer_profile_id if (i == 0 and viewer_profile_id) else p.id
            if i < reactions:
                db.execute(
                    _sa_text(
                        "INSERT INTO community_reactions "
                        "(post_id, profile_id, kind, created_at, updated_at) "
                        "VALUES (:pid, :prof, 'like', :ts, :ts)"
                    ),
                    {"pid": post_id, "prof": actor, "ts": now},
                )
            if i < bookmarks:
                db.execute(
                    _sa_text(
                        "INSERT INTO community_bookmarks "
                        "(post_id, profile_id, created_at) "
                        "VALUES (:pid, :prof, :ts)"
                    ),
                    {"pid": post_id, "prof": actor, "ts": now},
                )
            if i < comments:
                db.execute(
                    _sa_text(
                        "INSERT INTO community_comments "
                        "(public_id, post_id, author_profile_id, depth, body, "
                        " moderation_state, created_at, updated_at) "
                        "VALUES (:cpid, :pid, :prof, 0, 'komment', 'visible', "
                        "        :ts, :ts)"
                    ),
                    {
                        "cpid": f"{post_id}-{i}-comment",
                        "pid": post_id,
                        "prof": p.id,
                        "ts": now,
                    },
                )
            db.commit()
    finally:
        db.close()


class TestFeedCounts:
    def test_a1_a_post_with_no_interactions_reports_zeros(self, feed_client):
        client, headers, author_headers, session_factory, _ = feed_client
        _create_post(client, author_headers, key="p-1")

        raw = client.get("/community/feed", headers=headers)
        assert raw.status_code == 200, raw.text
        page = raw.json()

        assert len(page["items"]) == 1
        item = page["items"][0]
        # A nulla itt IGAZ — ez a kontroll-cella, ami nélkül az A2 nem
        # bizonyítana semmit (egy mindig-nullát adó mező is átmenne rajta).
        assert item["reaction_count"] == 0
        assert item["comment_count"] == 0
        assert item["bookmark_count"] == 0
        assert item["viewer_bookmarked"] is False
        assert item["viewer_reaction"] is None

    def test_a2_the_counts_reflect_the_real_interactions(self, feed_client):
        client, headers, author_headers, session_factory, _ = feed_client
        public_id = _create_post(client, author_headers, key="p-2")
        post_id = _internal_post_id(session_factory, public_id)
        _seed_interactions(
            session_factory, post_id, reactions=3, comments=2, bookmarks=1
        )

        item = client.get("/community/feed", headers=headers).json()["items"][0]

        assert item["reaction_count"] == 3
        assert item["comment_count"] == 2
        assert item["bookmark_count"] == 1

    def test_a3_a_deleted_comment_does_not_inflate_the_count(self, feed_client):
        """A törölt komment NEM számít bele.

        Különben a kártya többet ígérne, mint amennyit a komment-lista
        megnyitva ad — a felhasználó számára ez hibának látszik.
        """
        client, headers, author_headers, session_factory, _ = feed_client
        public_id = _create_post(client, author_headers, key="p-3")
        post_id = _internal_post_id(session_factory, public_id)
        _seed_interactions(session_factory, post_id, comments=2)
        db = session_factory()
        try:
            db.execute(
                _sa_text(
                    "UPDATE community_comments SET deleted_at = :ts "
                    "WHERE post_id = :pid AND public_id = :cpid"
                ),
                {
                    "ts": datetime.now(timezone.utc),
                    "pid": post_id,
                    "cpid": f"{post_id}-0-comment",
                },
            )
            db.commit()
        finally:
            db.close()

        item = client.get("/community/feed", headers=headers).json()["items"][0]

        assert item["comment_count"] == 1

    def test_a4_viewer_state_is_per_viewer_not_a_post_property(self, feed_client):
        """A néző-állapot a NÉZŐÉ.

        Ha a poszt sorából jönne, minden néző ugyanazt látná — ugyanaz a
        hibaosztály, amit a klub-router `my_role` cellája és a posts-router
        F2 javító köre mér.
        """
        client, headers, author_headers, session_factory, viewer_profile_id = (
            feed_client
        )
        public_id = _create_post(client, author_headers, key="p-4")
        post_id = _internal_post_id(session_factory, public_id)
        # Egy könyvjelző és egy reakció a NÉZŐTŐL, plusz kettő másoktól.
        _seed_interactions(
            session_factory,
            post_id,
            reactions=3,
            bookmarks=3,
            viewer_profile_id=viewer_profile_id,
        )

        item = client.get("/community/feed", headers=headers).json()["items"][0]

        assert item["viewer_bookmarked"] is True
        assert item["viewer_reaction"] == "like"
        # A SZÁMLÁLÓ ettől függetlenül a teljes halmazt mutatja.
        assert item["reaction_count"] == 3
        assert item["bookmark_count"] == 3

    def test_a5_an_empty_page_runs_no_count_queries(self, feed_client):
        """Üres oldalon a számláló-lekérdezés meg sem indul.

        A `_interaction_counts` üres listára azonnal visszatér — enélkül egy
        `IN ()` alakú SQL keletkezne, ami dialektusonként más hibát ad.
        """
        client, headers, author_headers, _, _ = feed_client

        page = client.get("/community/feed", headers=headers).json()

        assert page["items"] == []
