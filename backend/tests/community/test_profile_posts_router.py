"""``GET /community/profiles/{public_id}/posts`` — a hiányzó végpont (E17-R11).

MÉRT hiány (2026-09-06 audit §5.2, „a ``profilePosts`` végpont"): a Flutter
``CommunityFeedRepository`` szerződése a Kör 5 óta nevesíti a profil-poszt
olvasást, a szerveren viszont se route, se service nem volt. A Dart oldal
ezért ``UnimplementedError``-t dobott — helyesen, mert az üres oldal azt
ÁLLÍTOTTA volna, hogy a profilnak nincs posztja.

Amit ez a modul mér, sorra:

* P1 — a saját posztok minden közönséggel visszajönnek a tulajdonosnak;
* P2 — nyilvános profil, nem-követő néző: csak a ``public`` posztok;
* P3/P4/P5 — csak-követőknek profil, blokkolt pár és nem létező profil:
  EGYFORMA 404 (a három ág nem különböztethető meg kívülről);
* P6 — a klubba írt poszt NEM szivárog ki a profil-listán;
* P7 — a lágyan törölt és a moderált poszt kimarad;
* P8 — a kurzoros lapozás duplikátum és kihagyás nélkül halad;
* P9 — a hamisított kurzor friss első oldalt ad, nem hibát vagy szivárgást.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import pytest
from conftest import _build_app, _make_test_engine, make_authenticated_user
from fastapi.testclient import TestClient
from sqlalchemy import text as _sa_text
from sqlalchemy.orm import sessionmaker

# Load-bearing modell-importok a `Base.metadata`-hoz.
from app.community.models.bookmark import CommunityBookmark  # noqa: F401
from app.community.models.club import CommunityClub  # noqa: F401
from app.community.models.comment import CommunityComment  # noqa: F401
from app.community.models.post import (
    MODERATION_STATE_REMOVED,
    CommunityPost,
)
from app.community.models.profile import CommunityPrivacySettings, CommunityProfile
from app.community.models.reaction import CommunityReaction  # noqa: F401
from app.community.models.safety_relationships import (  # noqa: F401
    CommunityBlock,
    CommunityMute,
)
from app.community.models.social_graph import CommunityFollow
from app.config import Settings
from app.database import Base

# strumsight:allow-secret teszt-fixture Settings, nem éles kulcs
_SECRET = "a-real-32-char-test-secret-key-value"


@dataclass
class _Env:
    """A teszt-környezet EGY objektumban.

    A profil-poszt végpont négy szereplőt kíván (néző, szerző, a kettő
    profil-azonosítója, és a szerkeszthető session), és mindegyik cella
    másik részhalmazát használja. Egy sokelemű tuple kicsomagolása
    cellánként újra és újra elrontható; a mezőnevek nem.
    """

    client: TestClient
    session_factory: object
    viewer_headers: dict[str, str]
    author_headers: dict[str, str]
    viewer_id: int
    author_id: int

    def author_public_id(self) -> str:
        return _public_id_of(self.session_factory, self.author_id)

    def get_posts(
        self,
        public_id: str,
        headers: dict[str, str],
        *,
        page_size: int | None = None,
        cursor: str | None = None,
    ):
        params: dict[str, object] = {}
        if page_size is not None:
            params["page_size"] = page_size
        if cursor is not None:
            params["cursor"] = cursor
        return self.client.get(
            f"/community/profiles/{public_id}/posts",
            headers=headers,
            params=params,
        )


def _profile_for(session_factory, email: str, *, visibility: str) -> int:
    """Profil + adatvédelmi sor a megadott láthatósággal.

    Az adatvédelmi sor NEM elhagyható: a szolgáltatás a hiányzó sort
    ``private``-ként olvassa (a biztonságos alapérték), tehát egy sor
    nélküli profil minden nézőnek 404-et adna, és a teszt akaratlanul a
    hibaágat mérné.
    """
    db = session_factory()
    try:
        user_id = int(
            db.execute(
                _sa_text("SELECT id FROM users WHERE email = :e"), {"e": email}
            ).first()[0]
        )
        profile = CommunityProfile(user_id=user_id)
        db.add(profile)
        db.flush()
        db.add(
            CommunityPrivacySettings(
                profile_id=profile.id,
                visibility=visibility,
                audience_default="followers",
                updated_at=datetime.now(timezone.utc),
            )
        )
        db.commit()
        return int(profile.id)
    finally:
        db.close()


def _public_id_of(session_factory, profile_id: int) -> str:
    db = session_factory()
    try:
        return str(
            db.query(CommunityProfile)
            .filter(CommunityProfile.id == profile_id)
            .one()
            .public_id
        )
    finally:
        db.close()


def _seed_post(
    session_factory,
    *,
    profile_id: int,
    body: str,
    audience: str = "public",
    minutes_ago: int = 0,
    club_id: int | None = None,
    moderation_state: str | None = None,
    deleted: bool = False,
) -> None:
    now = datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)
    db = session_factory()
    try:
        post = CommunityPost(
            profile_id=profile_id,
            audience=audience,
            club_id=club_id,
            body=body,
            created_at=now,
            updated_at=now,
            deleted_at=now if deleted else None,
        )
        if moderation_state is not None:
            post.moderation_state = moderation_state
        db.add(post)
        db.commit()
    finally:
        db.close()


def _follow(session_factory, *, follower: int, followed: int) -> None:
    db = session_factory()
    try:
        db.add(
            CommunityFollow(follower_profile_id=follower, followed_profile_id=followed)
        )
        db.commit()
    finally:
        db.close()


def _block(session_factory, *, blocker: int, blocked: int) -> None:
    db = session_factory()
    try:
        db.add(CommunityBlock(blocker_profile_id=blocker, blocked_profile_id=blocked))
        db.commit()
    finally:
        db.close()


def _env_for(author_visibility: str):
    settings = Settings(
        community_enabled=True,
        community_writes_enabled=True,
        community_clubs_enabled=True,
        secret_key=_SECRET,
    )
    engine = _make_test_engine()
    session_factory = sessionmaker(bind=engine, autoflush=False, autocommit=False)
    app = _build_app(engine, session_factory, settings)
    client = TestClient(app)
    client.__enter__()
    _, viewer_headers = make_authenticated_user(
        session_factory, email="viewer@strumsight.app"
    )
    _, author_headers = make_authenticated_user(
        session_factory, email="author@strumsight.app"
    )
    env = _Env(
        client=client,
        session_factory=session_factory,
        viewer_headers=viewer_headers,
        author_headers=author_headers,
        viewer_id=_profile_for(
            session_factory, "viewer@strumsight.app", visibility="public"
        ),
        author_id=_profile_for(
            session_factory, "author@strumsight.app", visibility=author_visibility
        ),
    )
    try:
        yield env
    finally:
        client.__exit__(None, None, None)
        Base.metadata.drop_all(bind=engine)
        engine.dispose()


@pytest.fixture
def public_author():
    """Nyilvános szerző + tőle független néző (nem követi)."""
    yield from _env_for("public")


@pytest.fixture
def followers_only_author():
    """Csak-követőknek szerző + nem-követő néző."""
    yield from _env_for("followers")


class TestProfilePostsVisibility:
    def test_p1_the_owner_sees_every_audience_of_their_own_posts(self, public_author):
        env = public_author
        _seed_post(
            env.session_factory, profile_id=env.author_id, body="pub", minutes_ago=3
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="foll",
            audience="followers",
            minutes_ago=2,
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="priv",
            audience="private",
            minutes_ago=1,
        )

        response = env.get_posts(env.author_public_id(), env.author_headers)

        assert response.status_code == 200, response.text
        bodies = [item["body"] for item in response.json()["items"]]
        assert bodies == ["priv", "foll", "pub"]

    def test_p2_a_non_follower_sees_only_public_posts(self, public_author):
        env = public_author
        _seed_post(
            env.session_factory, profile_id=env.author_id, body="pub", minutes_ago=2
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="foll",
            audience="followers",
            minutes_ago=1,
        )

        response = env.get_posts(env.author_public_id(), env.viewer_headers)

        assert response.status_code == 200, response.text
        assert [item["body"] for item in response.json()["items"]] == ["pub"]

    def test_p2b_a_follower_also_sees_followers_only_posts(self, public_author):
        env = public_author
        _seed_post(
            env.session_factory, profile_id=env.author_id, body="pub", minutes_ago=2
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="foll",
            audience="followers",
            minutes_ago=1,
        )
        _follow(env.session_factory, follower=env.viewer_id, followed=env.author_id)

        response = env.get_posts(env.author_public_id(), env.viewer_headers)

        assert [item["body"] for item in response.json()["items"]] == [
            "foll",
            "pub",
        ]

    def test_p3_p4_p5_every_hidden_branch_is_the_same_404(self, followers_only_author):
        """A három rejtett ág megkülönböztethetetlen.

        Egy 403 vagy egy eltérő törzs elárulná, hogy a profil létezik, csak
        nem látható — ugyanaz a szivárgás, amit a poszt- és a klub-olvasás
        egységes 404-e zár.
        """
        env = followers_only_author
        _seed_post(env.session_factory, profile_id=env.author_id, body="pub")
        author_public = env.author_public_id()

        followers_only = env.get_posts(author_public, env.viewer_headers)
        missing = env.get_posts(str(uuid.uuid4()), env.viewer_headers)
        _block(env.session_factory, blocker=env.viewer_id, blocked=env.author_id)
        blocked = env.get_posts(author_public, env.viewer_headers)

        assert followers_only.status_code == 404, followers_only.text
        assert missing.status_code == 404
        assert blocked.status_code == 404
        assert followers_only.json() == missing.json() == blocked.json()

    def test_p4b_a_block_hides_even_a_public_profile(self, public_author):
        """A blokk a láthatóság ELŐTT dönt — nyilvános profilt is elrejt.

        A blokkot itt a SZERZŐ adja ki: a szűrő szimmetrikus, tehát a néző
        felől is rejtenie kell.
        """
        env = public_author
        _seed_post(env.session_factory, profile_id=env.author_id, body="pub")
        _block(env.session_factory, blocker=env.author_id, blocked=env.viewer_id)

        response = env.get_posts(env.author_public_id(), env.viewer_headers)

        assert response.status_code == 404, response.text


class TestProfilePostsRowFilters:
    def test_p6_a_club_post_never_leaks_through_the_profile_list(self, public_author):
        """A klubba írt poszt klub-tartalom.

        A klub-feed csak a klub TAGJAINAK adja ki; ha a szerző
        profil-listája is kiadná, a tagsági kapu megkerülhető lenne. A
        kontroll-eset a klub nélküli poszt, ami ugyanabban a válaszban ott
        van.
        """
        env = public_author
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="sima",
            minutes_ago=2,
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="klubos",
            club_id=4242,
            minutes_ago=1,
        )

        response = env.get_posts(env.author_public_id(), env.viewer_headers)

        assert [item["body"] for item in response.json()["items"]] == ["sima"]

    def test_p6b_the_owner_does_not_see_their_club_post_here_either(
        self, public_author
    ):
        """A tulajdonosnak sem: a két felület nem mondhat mást arról, hogy
        egy klub-poszt hol látszik."""
        env = public_author
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="klubos",
            club_id=4242,
        )

        response = env.get_posts(env.author_public_id(), env.author_headers)

        assert response.json()["items"] == []

    def test_p7_deleted_and_moderated_posts_are_excluded(self, public_author):
        env = public_author
        _seed_post(
            env.session_factory, profile_id=env.author_id, body="él", minutes_ago=3
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="törölt",
            minutes_ago=2,
            deleted=True,
        )
        _seed_post(
            env.session_factory,
            profile_id=env.author_id,
            body="moderált",
            minutes_ago=1,
            moderation_state=MODERATION_STATE_REMOVED,
        )

        response = env.get_posts(env.author_public_id(), env.viewer_headers)

        assert [item["body"] for item in response.json()["items"]] == ["él"]

    def test_p7b_the_page_carries_the_shared_projection_fields(self, public_author):
        """A profil-poszt UGYANAZT a wire-alakot viszi, mint a feed eleme.

        Egy szűkebb alak arra kényszerítené a klienst, hogy kitalált
        nullákat rajzoljon a profil posztjai alá, miközben a feedben
        ugyanaz a poszt a valódi számokat mutatja.
        """
        env = public_author
        _seed_post(env.session_factory, profile_id=env.author_id, body="egy")

        item = env.get_posts(env.author_public_id(), env.viewer_headers).json()[
            "items"
        ][0]

        assert item["reaction_count"] == 0
        assert item["comment_count"] == 0
        assert item["viewer_reaction"] is None
        assert item["viewer_bookmarked"] is False
        assert "resource_version" in item


class TestProfilePostsPagination:
    def test_p8_the_cursor_walks_the_pages_without_gaps_or_duplicates(
        self, public_author
    ):
        env = public_author
        for index in range(5):
            _seed_post(
                env.session_factory,
                profile_id=env.author_id,
                body=f"p{index}",
                minutes_ago=5 - index,
            )
        author_public = env.author_public_id()

        first = env.get_posts(author_public, env.viewer_headers, page_size=2).json()
        second = env.get_posts(
            author_public,
            env.viewer_headers,
            page_size=2,
            cursor=first["next_cursor"],
        ).json()
        third = env.get_posts(
            author_public,
            env.viewer_headers,
            page_size=2,
            cursor=second["next_cursor"],
        ).json()

        walked = [
            item["body"] for page in (first, second, third) for item in page["items"]
        ]
        assert walked == ["p4", "p3", "p2", "p1", "p0"]
        assert third["next_cursor"] is None

    def test_p9_a_forged_cursor_returns_a_fresh_first_page(self, public_author):
        """A hamisított kurzor nem hiba és nem szivárgás.

        A HMAC-ellenőrzés bukása után a szolgáltatás friss első oldalt ad;
        egy 500-as veremkiírás és egy elfogadott hamis pozíció is rosszabb
        válasz lenne.
        """
        env = public_author
        _seed_post(env.session_factory, profile_id=env.author_id, body="egy")

        response = env.get_posts(
            env.author_public_id(),
            env.viewer_headers,
            cursor="Zm9yZ2Vk.Zm9yZ2Vk",
        )

        assert response.status_code == 200, response.text
        assert [item["body"] for item in response.json()["items"]] == ["egy"]
