# ADR 0398 — Profile privacy, audience policy és a szerveroldali `CommunityAccessPolicy`

- **Státusz:** Elfogadva (E09-R04 pre-flight, 2026-08-22)
- **Kör:** E09-R04 — Profil privacy, audience és szerveroldali policy
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 4 (a 32 kör közül a negyedik)
- **Kontext-ADR-ek:** [0397](0397-community-public-identity-and-handle-policy.md)
  (Kör 3 — `community_profiles` handle-oszlopok, whitelist-only Pydantic
  minta, `try/except IntegrityError` konkurencia-védelem), [0396](0396-community-backend-module-boundary-and-first-migration.md)
  (Kör 2 — `community_privacy_settings` séma-váz, `build_community_router`
  flag-mögötti minta), [0291](0291-community-is-optional-and-private-by-default.md)
  (a közösség nem nyilvános alapból).
- **Sorszám-jegyzet:** a szám a `tools/round-slots.py reserve-adr --round
  E09-R04` foglalótól jött (Epic 9 batch-tartomány 0395–0419), és a
  `docs/execution/pipeline-queue.tsv`-ben előre dokumentált `0398` értékkel
  egyezik.

## Kontextus

**Mért 2026-08-22-én, a pre-flightban (a brief §0.0-ja a teljes tényellenőrzést
hordozza):**

1. `backend/app/community/models/profile.py` (E09-R02/R03) MA `id` + `public_id`
   + `user_id` + `display_name` + `created_at` + `handle_display`/
   `handle_normalized`/`handle_changed_at` (`CommunityProfile`), és `id` +
   `public_id` + `profile_id` + `updated_at` (`CommunityPrivacySettings`,
   93–131. sor) — **nincs `visibility`/`audience` mező egyik osztályon sem**.
2. `backend/tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema`
   egy MEGLÉVŐ gate-teszt, ami `compare_metadata(...) == []`-t vár el az
   `alembic upgrade head` UTÁN — ez determinisztikusan pirosra vált, ha a
   migráció oszlopot ad hozzá, de az ORM-osztály nem tükrözi (brief §0.0 B1).
   Ez a kör ezért a `CommunityPrivacySettings` osztályt is bővíti (a brief
   §0.0 revíziója engedi).
3. `docs/rounds/e09-r07-follow-and-follow-request-graph.md` és
   `docs/rounds/e09-r08-block-mute-and-safety-relationships.md` (mindkettő
   előre megírt, még nem induló kör) a `RelationshipContext` paraméter-
   objektumot MÁR név szerint hivatkozza, és a Kör 8 brief kifejezetten a
   `RelationshipContext.blocked` mezőnevet olvassa ki ebből a körből — ez a
   döntés tehát nem szabadon választható, hanem előre kötött kontraktus.
4. Nincs még follow-, block- vagy club-adatmodell (Kör 7/8/24) — a
   `RelationshipContext` ezért ebben a körben egy tisztán szintetikus,
   hívó által összeállított paraméter-objektum, amit a jövőbeli körök
   valódi lekérdezésekkel töltenek fel.

## Döntés

### 1. Új oszlopok a `CommunityPrivacySettings`-en (nem külön tábla, nem a `CommunityProfile`-on)

```python
# backend/app/community/models/profile.py — CommunityPrivacySettings bővítés
visibility: Mapped[str] = mapped_column(
    String, default="followers", server_default="followers", nullable=False
)
audience_default: Mapped[str] = mapped_column(
    String, default="followers", server_default="followers", nullable=False
)
```

- Mindkettő a MEGLÉVŐ `theme_mode: Mapped[str] = mapped_column(String, ...)`
  mintát követi (`backend/app/models.py`) — plain `String`, nem SQLAlchemy
  `Enum` típus, az érvényesség Pydantic/domain szinten dől el, nem DB
  `CHECK`-kel (konzisztens a projekt meglévő enum-tárolási szokásával).
- **Miért a `CommunityPrivacySettings`-en, nem a `CommunityProfile`-on:** a
  brief §0.0 pre-flight figyelmeztetése ("az audience-enum ide, nem egy új
  táblába kerül") kifejezetten a MEGLÉVŐ privacy-settings táblát jelöli ki;
  a `CommunityProfile` a brief §0.0 revíziója szerint továbbra is TILOS zóna
  marad (nulla módosítás azon az osztályon).
- **Miért `server_default="followers"`:** az alembic-oszlop `NOT NULL`, és
  bár ma nincs élő sor a táblában (a Kör 6 onboarding előtti állapot),
  a `server_default` biztonságossá teszi a migrációt egy jövőbeli,
  már-nem-üres táblán is — konzisztens a projekt "biztonságos oszlop-bővítés"
  szokásával.

### 2. `RelationshipContext` — a jövőbeli körök KÖTÖTT szerződése

```python
# backend/app/community/policies/access_policy.py
from dataclasses import dataclass


@dataclass(frozen=True)
class RelationshipContext:
    """Szintetikus, hívó által összeállított kapcsolat-leírás — ez a kör
    NEM olvas valódi follow/block/club táblát (azok Kör 7/8/24), a jövőbeli
    körök ezt a mezőnevet és típust MÁR name szerint hivatkozzák (Kör 8
    brief §2: ``RelationshipContext.blocked``), ezért a mezőnevek innentől
    stabil, visszamenőleg nem módosítható szerződés.
    """

    viewer_is_owner: bool = False
    blocked: bool = False
    is_follower: bool = False
    is_club_member: bool = False
```

- `blocked` — PONTOSAN ez a névalak (nem `is_blocked`), mert a Kör 8 brief
  §2/§4 már ezt a nevet olvassa ki a Kör 4 kódjából.
- `is_follower` — kizárólag ELFOGADOTT (accepted) follow-kapcsolatot jelent,
  SOHA pending-et (A4 — ld. §3 alább). A jövőbeli Kör 7 a saját
  `FollowStatus` enumjából ezt a boolean-t számítja ki a policy hívása
  ELŐTT — a policy maga nem ismeri a pending/accepted/declined
  állapotgépet, csak az eredményt.
- `is_club_member` — ebben a körben HASZNÁLATON KÍVÜLI, `False` default,
  fenntartva a Kör 24 (club domain) számára — a §6 mátrix-dokumentum a
  "club member" kombinációt megnevezi, ezért a mező a kontraktus RÉSZE,
  de a kiértékelő függvények ezt ebben a körben nem olvassák (nincs élő
  club-adat, amivel ki lehetne tölteni).

### 3. A kiértékelési sorrend — block ELŐBB, majd owner, majd visibility/audience, majd relationship

```python
# backend/app/community/policies/access_policy.py
from enum import Enum


class ProfileVisibility(str, Enum):
    PUBLIC = "public"
    FOLLOWERS = "followers"
    PRIVATE = "private"


class CommunityAudience(str, Enum):
    PUBLIC = "public"
    FOLLOWERS = "followers"
    PRIVATE = "private"


class ProfileAccessLevel(str, Enum):
    NONE = "none"
    SUMMARY = "summary"
    FULL = "full"


class CommunityAccessPolicy:
    def evaluate_profile_access(
        self, visibility: ProfileVisibility, relationship: RelationshipContext
    ) -> ProfileAccessLevel:
        if relationship.viewer_is_owner:
            return ProfileAccessLevel.FULL
        if relationship.blocked:
            # A2/§5.2: a blockolt fél számára a profil MINDIG úgy
            # viselkedik, mintha private lenne — FÜGGETLENÜL a
            # tényleges visibility-től, MÉG public profilnál is.
            return ProfileAccessLevel.SUMMARY
        if visibility is ProfileVisibility.PUBLIC:
            return ProfileAccessLevel.FULL
        if visibility is ProfileVisibility.FOLLOWERS:
            return (
                ProfileAccessLevel.FULL
                if relationship.is_follower
                else ProfileAccessLevel.SUMMARY
            )
        return ProfileAccessLevel.SUMMARY  # PRIVATE

    def evaluate_content_access(
        self, audience: CommunityAudience, relationship: RelationshipContext
    ) -> bool:
        """Post/komment audience-kiértékelés — Kör 11/13 fogja hívni élő
        tartalommal; ebben a körben hívó nélküli, önállóan tesztelt
        komponens (ADR 0397 §5 `IdentityService.new_public_id()`
        precedense — 'MA hívó nélküli, tesztelt komponens')."""
        if relationship.viewer_is_owner:
            return True
        if relationship.blocked:
            return False
        if audience is CommunityAudience.PUBLIC:
            return True
        if audience is CommunityAudience.FOLLOWERS:
            return relationship.is_follower
        return False  # PRIVATE
```

**NEM elfogadható gyengítés (§5.2 megismétlése konkrét kódra vetítve):** a
`blocked` ág a `viewer_is_owner` UTÁN, de a `visibility`/`audience` ág ELŐTT
fut — a tulajdonos-ellenőrzés nem "audience-szabály", hanem egy különálló,
block-nál is erősebb eset (a tulajdonos sosem blokkolhatja saját magát a
mérvadó útvonalakon; ha egy jövőbeli önblokk-eset mégis előállna, az a
Kör 8 dolga, itt nem kezelt). A block-ág utáni bármilyen `visibility`-ellenőrzés
BÁRMILYEN sorrendben az A2 valódi-sértés próba tárgya.

### 4. Private/blocked válasz: `ProfileAccessLevel.SUMMARY`, nem `NONE`

A `NONE` szint fenntartva egy jövőbeli, explicit "a profil nem létezik vagy
törölve/moderálva van" esetre (Kör 27/28) — ez a kör csak a `SUMMARY`/`FULL`
határt teszteli (A3). A `SUMMARY` szint azt jelenti: a hívó (jövőbeli router)
csak a whitelistelt, "relationship-safe" mezőket adhatja vissza — ennek a
körnek nincs élő router-integrációja (a `routers/profile.py` tilos zóna),
ezért a "mely mezők" döntést egy jövőbeli kör (a policy-t ténylegesen hívó
profil-endpoint) hozza meg; ez az ADR csak a szint-hármas nevét és
sorrendjét rögzíti.

### 5. Az alapértelmezett `visibility`/`audience_default`: `"followers"`

A brief §5.3 megengedi `private` VAGY `followers` alapértéket, de tiltja a
`public`-ot. A `"followers"` mellett döntök (nem `"private"`): ez a
gyakorlatban használt közösségi-app alapérték (a felhasználó az elfogadott
követőinek látszik alapból, de nem a teljes nyilvánosságnak) — a `private`
opciót a termék később, egy jövőbeli onboarding-kör (Kör 6) UI-választásként
kínálhatja fel, de a DB-szintű alapérték sosem enged automatikus
nyilvánosságot (A5).

### 6. Optimistic concurrency: a MEGLÉVŐ `updated_at` a resource-version, nincs új oszlop

```python
# backend/app/community/schemas/privacy.py
class PrivacySettingsUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    visibility: ProfileVisibility
    audience_default: CommunityAudience
    resource_version: datetime  # a kliens utoljára látott `updated_at`-je


class PrivacySettingsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    public_id: uuid.UUID
    visibility: ProfileVisibility
    audience_default: CommunityAudience
    resource_version: datetime  # == a sor `updated_at` mezője
```

```python
# backend/app/community/services/... vagy routers/privacy.py — a service-függvény
class StalePrivacyUpdateError(Exception):
    """A409 — a kliens elavult resource_version-t küldött."""


def update_privacy_settings(
    db: Session,
    settings_row: CommunityPrivacySettings,
    payload: PrivacySettingsUpdate,
    *,
    now: datetime,
) -> CommunityPrivacySettings:
    if payload.resource_version != settings_row.updated_at:
        raise StalePrivacyUpdateError(settings_row.updated_at)
    settings_row.visibility = payload.visibility.value
    settings_row.audience_default = payload.audience_default.value
    settings_row.updated_at = now
    db.commit()
    return settings_row
```

**Miért nincs külön `version`/`etag` oszlop:** a `community_privacy_settings`
táblának MÁR van `updated_at` (Kör 2, `onupdate=_utcnow`) — ez pontosan azt a
szerepet tölti be, amit egy külön verziószám tenne, és elkerüli egy
HARMADIK új oszlop hozzáadását ugyanazon a bővítés-korlátozott modellen
(§1). A `now` explicit paraméter (nem `_utcnow()` közvetlen hívás a
service-ben) az ADR 0397 `IdentityService.change_handle(..., now=...)`
mintáját követi — determinisztikus teszteléshez.

**NEM elfogadható gyengítés:** a `resource_version` ellenőrzés kihagyása
"mert ez csak egy belső endpoint" indokkal, vagy az ellenőrzés az
adatbázis-commit UTÁNI összehasonlítással (ami már késő — a race pontosan a
commit ELŐTTI olvasás-írás ablakban történik; a teszt ezt egy stale
`resource_version`-nel hívott UPDATE-tel bizonyítja, ADR §6.1 A6 cella).

### 7. Dart-oldali enum — egyetlen fájl, wire-value parity

```dart
// lib/features/community/domain/policies/community_audience.dart
enum ProfileVisibility {
  public('public'),
  followers('followers'),
  private('private');

  const ProfileVisibility(this.wireValue);
  final String wireValue;
}

enum CommunityAudience {
  public('public'),
  followers('followers'),
  private('private');

  const CommunityAudience(this.wireValue);
  final String wireValue;
}
```

A wire-értékek BETŰ SZERINT egyeznek a backend `str, Enum` `.value`-ival
(§3) — ez a mérce a jövőbeli Flutter-oldali JSON (de)szerializációhoz
(Kör 5+, amikor a `lib/features/community/` gyökér megnyílik).

## Elutasított alternatívák

- **`visibility`/`audience_default` a `CommunityProfile`-on, nem a
  `CommunityPrivacySettings`-en.** Elvetve: a brief §0.0 pre-flight
  figyelmeztetése kifejezetten a privacy-settings táblát jelöli ki, és a
  `CommunityProfile` a brief tilos zónája szerint továbbra is érintetlen
  marad — a `CommunityPrivacySettings` bővítése a MINIMÁLIS, brief-kompatibilis
  beavatkozás.
- **Külön `community_privacy_field_overrides` tábla a granuláris (mező-szintű)
  privacy-hez.** Elvetve: a brief §2 kifejezetten kimondja, hogy a granuláris
  taxonómia Kör 6+ scope (ADR 0396 kontextus 94–100. sor idézete) — ez a kör
  csak a profil- és audience-szintű, nem mező-szintű döntést szállítja.
- **`RelationshipContext` mint Pydantic `BaseModel`, nem `dataclass`.**
  Elvetve: ez a típus SOHA nem kel át a HTTP-határon (nincs élő route, ami
  szerializálná) — a `frozen=True` dataclass olcsóbb és a hívó (jövőbeli
  follow/block szolgáltatás) számára ugyanolyan kényelmes, mint egy Pydantic
  modell, import-súly nélkül.
- **Külön `version: int` oszlop optimistic concurrency-hez, `updated_at`
  helyett.** Elvetve: egy HARMADIK új oszlop lenne a már bővítés-korlátozott
  `CommunityPrivacySettings`-en, miközben a MEGLÉVŐ `updated_at` pontosan
  ugyanazt a garanciát adja (monoton, minden íráskor változik) — a projekt
  "ne vezess be redundáns mezőt, ha a meglévő elég" elve mellett döntök.
- **`ProfileAccessLevel.NONE` visszaadása blockolt/private esetén (nem
  `SUMMARY`).** Elvetve: a brief §5.2 kifejezetten "private-ként viselkedik"
  szöveget használ, nem "láthatatlanként" — a `SUMMARY` az, ami egy privát
  profil MEGLÉVŐ viselkedését (minimális, relationship-safe adat) tükrözi;
  a `NONE` egy jövőbeli, teljesen más okú (törölt/moderált) állapot lenne.

## Következmények

- A `CommunityAccessPolicy.evaluate_content_access` MA hívó nélküli, tesztelt
  komponens (ADR 0397 §5 precedens) — a Kör 11/13 posts/feed endpointjai
  kötik majd be élő adattal.
- A `RelationshipContext` mezőnevei (`blocked`, `is_follower`,
  `viewer_is_owner`, `is_club_member`) mostantól stabil, a Kör 7/8/24
  briefjei által név szerint hivatkozott szerződés — egy jövőbeli
  átnevezés ezen ADR frissítését és a downstream briefek egyidejű
  felülvizsgálatát igényli.
- A `ProfileAccessLevel.SUMMARY` alatt PONTOSAN mely mezők láthatók, egy
  jövőbeli, a policy-t ténylegesen HÍVÓ kör (profil-endpoint integráció)
  döntése — ezt az ADR szándékosan nyitva hagyja.

## A visszavonás feltétele

Felülvizsgálandó, ha a Kör 7/8 mérten azt találja, hogy a
`RelationshipContext` mezőkészlete (pl. hiányzó `pending_follow: bool` a
follow-request UI-hoz) bővítést igényel — ekkor a bővítés (nem a meglévő
mezők átnevezése) a befogadó kör `allowed_paths`-ára tartozik, ADR-hivatkozással
erre a döntésre.
