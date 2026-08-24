# E09-R25 — Club feed, pinned post és club challenge

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 25
- **Kör-azonosító:** `E09-R25`
- **Branch:** `<motor>/e09-r25-club-feed-pinned-post-and-challenge`
- **Előfeltétel:** `E09-R24` merge-elve
- **Brief szerzője:** Claude (Opus 5); pre-flight revízió: Claude Sonnet 5
- **Előre kiosztott ADR:** nincs — ez a kör nem hoz új kötött architekturális döntést (tisztán UI/integráció/lezárás); a §0.0 pre-flight csak a Kör 24 ADR 0420 D1/D2 KÖTELEZŐ hivatkozását és a mért tényeket rögzíti.

**Kockázat = high, indoklás:** a kör klub-tagsághoz kötött, szerveroldali
audience-ellenőrzést vezet be a poszt- és challenge-olvasási útra (A1, A5),
és egy klub-specifikus moderátor-jogosultságot (pin/unpin, poszt-moderáció)
ad, amelynek elsődleges kockázata, hogy (a) egy nem-tag közvetlen ID-vel
hozzáférne klub-tartalomhoz (A1), (b) egy klub moderátora egy MÁSIK klubban
is pin-elhetne/moderálhatna a jogkör helytelen hatókör-ellenőrzése esetén
(A3), és (c) egy nem-tag résztvevőként regisztrálódhatna egy
club-challenge-ben (A5). Egyik `allowed_paths` fájl sem egyezik szó szerint
a router `high_risk_path_fragments` listájával (nincs "auth"/"authorization"
szó a fájlnevekben), de a kockázat ettől függetlenül valós —
jogosultság-eszkaláció és tartalom-szivárgás, nem forma szerinti
kulcsszó-egyezés (ugyanaz a minta, mint az E09-R24 ADR 0420 indoklása).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 13 `following_feed.py` és a Kör 21 `challenge_invite_service.py` TÉNYLEGES query-alakját — ez a kör ÚJRAHASZNÁLJA őket klub-audience-szűréssel, nem duplikál post- vagy challenge-rendszert. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight brief-revízió (2026-08-24, Claude Sonnet 5)

**Visszakeresés** (ADR 0312 §4.9, szűkítve): [L409](../LESSONS.md) ("route-
élesítő brief hallgatólagosan feltételezheti, hogy a caller-fed képernyők
adathoz vannak kötve — mérd meg a példányosítást, ne a screen létezését") és
[L442](../LESSONS.md) ("repository/provider-réteg hiánya a `public.dart`-on
strukturális, nem véletlen") — mindkettő pontosan erre a körre alkalmazandó
(lásd 3. pont lent). [ADR 0420](../adr/0420-club-domain-membership-and-roles.md)
§Kontextus/2, §D2 és §Következmények **explicit előírja**, hogy EZ a kör
(Kör 25) hivatkozzon rá a `club_id` FK-bekötésnél — lásd 1. pont.

1. **`club_id` típus-inkonzisztencia — ADR 0420 D1/D2 szerint oldva fel, nem
   új döntés.** Mérve: `community_posts.club_id` **BigInteger** (Kör 11,
   ADR 0405) — ez a `community_clubs.id` (BigInteger belső PK, ADR 0420 D1)
   közvetlen join-célpontja, a `club_feed.py` ezt BigInteger–BigInteger
   egyezésként köti be. Ezzel szemben `community_challenges.club_id`
   **String(64)** (Kör 21, ADR 0415 D7) a `community_clubs.public_id`
   (Uuid, ADR 0420 D1) STRING-alakját tárolja — ez egyezik a Flutter
   `CommunityChallengeDefinition.clubId: String?` mezővel
   (`community_challenge.dart`, "Kör 24 will validate that this field is
   non-null precisely when the type is club"). A `club_content_service.py`-
   nak tehát a challenge létrehozásakor `str(club.public_id)`-t kell írnia
   a `club_id` oszlopba, **NEM** a belső bigint id-t — a két `club_id`
   oszlop ELTÉRŐ szemantikájú, összekeverésük az A5 cellát törné. Nincs
   migráció, nincs FK-constraint hozzáadás — csak lekérdezés-szintű join
   (a tilos zóna `models/challenge.py`/`models/post.py`-t csak HÍVni engedi,
   szerkeszteni nem).

2. **Nincs `status`/`state` oszlop a `CommunityChallenge` modellen —
   "activate/end" ablak-alapú, nem külön mutáció.** A §3 "create/activate/
   end" megfogalmazás NEM egy állapotgép-tranzíciót jelent — a
   `CommunityChallenge` modellen nincs `state` mező, csak `starts_at`/
   `ends_at`, és a tilos zóna (`models/challenge.py`, csak-hívás) kizárja
   egy új oszlop hozzáadását is. A helyes olvasat, a MEGLÉVŐ
   `_ensure_challenge_visible` (`challenge_invite_service.py`) ablak-
   mintáját követve: **create** = új sor beszúrása `starts_at`/`ends_at`
   ablakkal; **activate** NEM külön hívás, hanem az, hogy `now` belép a
   `[starts_at, ends_at]` ablakba (a challenge a lekérdezés idejéig
   implicit válik "aktívvá"); **end** ugyanígy implicit (`now > ends_at`),
   VAGY — ha egy moderátori korai lezárás is kell — az `ends_at` mező
   `now`-ra állítása a MEGLÉVŐ oszlopon (nem új mező), a jogosultságot a
   §5.2 klub-permission-mátrixból véve (moderator+).

3. **Flutter oldal: a hiányzó repository-metódusok STRUKTURÁLIS korlátozás,
   nem hiba — kövesd a Kör 24 mintáját, ne bővítsd a domain-interfészt.**
   Mérve: `grep -n "clubPinned" lib/features/community/domain/repositories/feed_repository.dart`
   → **`clubPinned({clubId, cursor, limit})` MÁR LÉTEZIK** a
   `CommunityFeedRepository`-n, a docstring szerint pontosan erre a körre
   szánva ("Until the club feature lands... Kör 5 stub"). Ezt kell hívni a
   Feed tab pin-elt szekciójához — **NEM** új metódust hozzáadni. Ezzel
   szemben **nincs** általános (nem-pin-elt) klub-feed metódus, és **nincs**
   klub-szűrt/create/activate/end challenge-metódus SEM a
   `CommunityFeedRepository`-n, SEM a `CommunityChallengeRepository`-n, SEM
   a `CommunityClubRepository`-n — mind a három fájl az `allowed_paths`-on
   KÍVÜL esik (bővítésük H3). L409/L442 szerint ez STRUKTURÁLIS, nem
   véletlen hiány: a Kör 24 saját precedenst hagyott —
   `club_member_management_screen.dart`'s `ClubMemberRow` egy KÉPERNYŐ-
   HELYI típus, és a tagsági lista NEM a `CommunityClubRepository`-n
   keresztül jön ("materialises this from
   `CommunityClubRepository.listClubsMembers` — a future surface — the
   brief does not mandate a separate members endpoint in this round").
   **Ugyanezt a mintát kövesd:** a Challenges tab és a Feed tab nem-
   pin-elt szekciója (és a Members tab, ha nem a meglévő
   `club_member_management_screen.dart`-ra navigál) KÉPERNYŐ-HELYI
   Riverpod providerekkel épül a `club_detail_screen.dart`-on BELÜL —
   produkcióban az `communityClubRepositoryProvider`-hez hasonlóan meg NEM
   kötve (throw/helyőrző elfogadható), a widget-teszt override-olja fake
   adattal. A §6 A1–A7 cellák mind a BACKEND service-tesztben
   (`test_club_content_service.py`) mérendők — a Flutter oldal egyetlen
   kötelező mért cellája **A2** (cache-invalidáció klub-elhagyás után), ami
   a meglévő `clubDetailProvider`-en már bevált `ref.invalidate(...)`
   mintát ismétli a klub-tartalom új, képernyő-helyi providereire.

4. **Pin-limit "konfigurációból" — kövesd a `MAX_CLUB_MEMBERS` precedenst,
   ne a `Settings` osztályt.** `backend/app/config.py::Settings` nem
   tartalmaz semmilyen klub-tartalmi (pin/challenge) mezőt — a Kör 24
   `MAX_CLUB_MEMBERS = 500` egy modul-szintű Python-konstans a `club.py`-
   ban, NEM egy `Settings`-mező. A §6 A4 "konfigurációból" ugyanezt a
   mintát jelenti: egy dokumentált modul-szintű konstans a
   `club_content_service.py`-ban (pl. `MAX_CLUB_PINNED_POSTS`), a pontos
   érték az implementer választása, dokumentálva a §10-ben — nem szükséges
   `Settings`-bővítés.

## 0.0d Post-implementáció javító addendum (2026-08-24, review, Claude Sonnet 5)

Az implementáció (§10.5/§10.7) MÉRT, dokumentált ismert korlátként hagyta,
hogy a `community_club_pinned_posts` junction tábla NINCS alembic
migrációban — a tábla egy PRIVÁT `MetaData`-n (`_pinned_metadata`) él, hogy
a `test_upgrade_head_matches_current_orm_schema` drift-őr ne vegye észre.
Ez éles adatbázison `alembic upgrade head` UTÁN is hiányzó táblát jelent —
a `pin_post`/`unpin_post`/`list_club_pinned` (A3/A4) egy valódi deploy-on
"no such table" hibával bukna. Ez NEM elfogadható "következő kör" korlát,
mert a §3 scope explicit tartalmazza a "pinned post reláció maximum
konfigurált darabszámmal" elemet — a tábla-perzisztencia MAGA a feature,
nem egy opcionális kiegészítés.

**Javítás — `allowed_paths` bővítve** (ADR 0087 §2 önjavítható eset,
brief-revízió, nem tilos-zóna feloldás — a widening egy MÁR ismert,
precedenses fájltípus, minden korábbi Epic-9 kör ugyanígy ad egy
`backend/alembic/versions/eXX_rYY_00NN_*.py` migrációt, nem ad-hoc
kerülőút, lásd az E09-R24 §0.0c pontos precedensét):

- `backend/alembic/versions/e09_r25_0019_community_club_pinned_posts.py` —
  ÚJ migráció, `down_revision = "e09_r24_0018"` (a lánc jelenlegi feje,
  mérve: `ls backend/alembic/versions | sort | tail -1`). Az `upgrade()`
  a `community_club_pinned_posts` táblát hozza létre PONTOSAN a
  `club_content_service.py` inline `Table`-jének oszlopaival (`club_id`
  BigInteger, `post_id` BigInteger, `pinned_at` DateTime(timezone=True)
  NOT NULL, `pinned_by_profile_id` BigInteger NOT NULL), összetett PRIMARY
  KEY-vel `(club_id, post_id)`-n, és FK-kal `community_clubs.id`
  (`ondelete="CASCADE"`) / `community_posts.id` (`ondelete="CASCADE"`)
  irányban — a projekt-szintű cascade-on-delete konvenciót követve
  (`community_club_members`/`community_challenge_invites` precedens). A
  `downgrade()` a táblát dobja.
- A `community_club_pinned_posts` `Table` deklarációja
  `club_content_service.py`-ban KÖLTÖZZÖN a privát `_pinned_metadata`-ról a
  projekt `Base.metadata`-jára (`from ...database import Base`,
  `Table(..., Base.metadata, ...)` vagy ezzel ekvivalens) — a drift-őr
  ELKERÜLÉSE volt a hiba, nem a célja; a helyes állapot az, hogy a
  migráció-kontraktus teszt TÉNYLEG összeveti az ORM-deklarált sémát az
  alembic-fejjel, és zölden talál egyezést, nem azért zöld, mert a tábla
  láthatatlan neki.
- A backend teszt fixture-ben (`test_club_content_service.py`,
  `svc._pinned_metadata.create_all(...)` hívás) az ÚJ elhelyezés után a
  tábla már a `Base.metadata`-n keresztül materializálódik a többi
  Community táblával együtt — a kézi `create_all(tables=[...])` extra
  lépés valószínűleg feleslegessé válik, de ha az implementer megtartja
  (pl. SQLite in-memory fixture gyorsítás miatt), az nem hiba, amíg a
  tábla ÉS a migráció is a `Base.metadata`-n él.
- Zöld gate ÚJRA igazolandó mindkét oldalon (§7), PLUSZ a migráció-
  kontraktus teszt explicit lefuttatva és zöld (mérve:
  `backend/tests/test_migrations.py::test_upgrade_head_matches_current_orm_schema`,
  önálló paranccsal, NEM láncolva a §7 két parancsához):

  ```bash
  cd backend && python -m pytest tests/test_migrations.py -q
  ```

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/feed/club_feed.py",
  "backend/app/community/services/club_content_service.py",
  "backend/alembic/versions/e09_r25_0019_community_club_pinned_posts.py",
  "lib/features/community/presentation/screens/clubs/club_detail_screen.dart",
  "backend/tests/community/test_club_content_service.py",
  "test/features/community/presentation/clubs/club_detail_screen_test.dart",
  "docs/rounds/e09-r25-club-feed-pinned-post-and-challenge.md",
]
gate_tests = [
  "test/features/community/presentation/clubs/club_detail_screen_test.dart"
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

A klubok számára ugyanazon biztonságos post- és challenge-infrastruktúra újrahasznosítása — a klub feed NEM egy külön poszt-rendszer.

## 2. Jelenlegi állapot — mért tények

- A Kör 11/13 post/feed és a Kör 21 challenge-infrastruktúra MA készen áll, klub-audience nélkül — ez a kör köti be a tagság-ellenőrzést
- A Kör 24 klub-permission mátrix MA létezik — a pin/moderation jog ebből származik

## 3. Scope

**Benne van:** club audience post-policy tagság-ellenőrzéssel · club feed cursor pagination a KÖZÖS post-projekció újrahasznosításával · pinned post reláció maximum konfigurált darabszámmal · club moderator pin/unpin és post-moderation joga a permission-mátrixból · club challenge create/activate/end compatibility-validációval · Flutter club detail tabok: Feed, Challenges, Members, About · club elhagyása után a csak-club tartalom AZONNAL eltűnik a cache-ből.

**NINCS benne (tilos):**

- Új, párhuzamos post- vagy challenge-adatmodell létrehozása.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/feed/club_feed.py` | ÚJ — a Kör 13 projekció újrahasznosítása club-szűréssel |
| `backend/app/community/services/club_content_service.py` | ÚJ — pin/unpin + club-challenge lifecycle |
| `lib/features/community/presentation/screens/clubs/club_detail_screen.dart` | BŐVÍTÉS — Feed/Challenges/Members/About tabok |
| `backend/tests/community/test_club_content_service.py` | ÚJ — a §6 cellái |
| `test/features/community/presentation/clubs/club_detail_screen_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/models/post.py`, `models/challenge.py` (csak a club_id-kapcsolat hívása, nem új tábla) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 A klub feed a KÖZÖS post-projekciót hasznosítja újra, klub-audience szűréssel

Nincs külön "club post" adatmodell — a Kör 11 `community_posts` tábla `club_id` mezője és a Kör 13 projekció klub-audience-szűrése adja a klub feedet.

**NEM elfogadható gyengítés:** egy külön `club_posts` tábla létrehozása "egyszerűség kedvéért" — ez duplikálná a moderation/block/audience logikát, és a két rendszer drifteljen egymástól.

### 5.2 A moderator jog NEM terjed túl a saját klubján

A pin/unpin és post-moderation jogosultság-ellenőrzés a KONKRÉT klub tagságához kötött — egy klub moderátora nem moderálhat egy másik klubban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Nem-tag nem éri el a klub feedjét vagy tartalmát | `test_club_content_service.py` |
| A2 | Klub elhagyása után a cache-ből azonnal eltűnik a csak-club tartalom | `club_detail_screen_test.dart` |
| A3 | Pin-jogosultság csak a klub owner/moderator-jáé | `test_club_content_service.py` |
| A4 | Pin-limit érvényesül (konfigurációból) | `test_club_content_service.py` |
| A5 | Club-challenge eligibility a tagságot ellenőrzi | `test_club_content_service.py` |
| A6 | Block érvényesül klubon belül is (Kör 8/24 szűrő újrahasznosítva) | `test_club_content_service.py` |
| A7 | Klub-feed pagination stabil, nincs duplikált post | `test_club_content_service.py` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy nem-tag közvetlen ID-vel eléri a klub-posztot | A1 |
| Egy másik klub moderátora pin-elhet ebben a klubban | A3 |
| A pin-limit nincs ellenőrizve, tetszőleges számú poszt pin-elhető | A4 |
| Egy nem-tag résztvevőként regisztrálódhat a club-challenge-ben | A5 |
| A klub elhagyása után a régi cache-tartalom még megjelenik | A2 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a tagság-ellenőrzést a klub feed queryjéből, futtasd a backend pytest-et egy nem-taggal → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/presentation/clubs/club_detail_screen_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_club_content_service.py -q
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `club_feed.py` — a Kör 13 projekció újrahasznosítása `club_id` + tagság-szűréssel.
2. `club_content_service.py` — pin/unpin (permission-mátrix), club-challenge lifecycle (Kör 21 hívása).
3. `club_detail_screen.dart` bővítése a négy tabbal.
4. A klub-elhagyás utáni cache-invalidáció.
5. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A párhuzamos post-rendszer csábítása.** Egy külön `club_posts` tábla gyorsabbnak tűnne, de duplikálná és driftelné a moderation-logikát (A1/A6).
- **A moderator-jog túlterjedése.** Egy rosszul paraméterezett ellenőrzés klubok közötti jogosultság-szivárgást okozna (A3).
- **Az elmaradt cache-invalidáció.** A klub elhagyása után is látszó tartalom megsértené a §16.4 SDD-elvárást (A2).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Implementált scope (5/6 allowed_paths, plus 1doksi)

| Fájl | Státusz |
|---|---|
| `backend/app/community/feed/club_feed.py` | ÚJ — Kör 13 projekció újrahasznosítása club-szűréssel (A1, A6, A7) |
| `backend/app/community/services/club_content_service.py` | ÚJ — pin/unpin (A3, A4), club-challenge lifecycle (A5, A6) |
| `lib/features/community/presentation/screens/clubs/club_detail_screen.dart` | BŐVÍTÉS — 4 tab + screen-local providers + A2 cache-invalidáció |
| `backend/tests/community/test_club_content_service.py` | ÚJ — A1/A3/A4/A5/A6/A7 + §6.1 valódi-sértés próbák |
| `test/features/community/presentation/clubs/club_detail_screen_test.dart` | ÚJ — A2 widget test + 4-tab surface |
| `docs/rounds/e09-r25-club-feed-pinned-post-and-challenge.md` | A §10 handoff kitöltve (ez a fájl) |

### 10.2 Pin-limit értéke (§0.0 #4)

`MAX_CLUB_PINNED_POSTS = 5` — a `club_content_service.py`-ban
modul-szintű konstansként definiálva (a `MAX_CLUB_MEMBERS = 500`
Kör 24 precedens mintájára). A `Settings` osztály NEM bővült.

### 10.3 `club_id` típus-inkonzisztencia kezelése (§0.0 #1)

A `club_content_service.create_club_challenge` a `club_id`
oszlopba `str(club.public_id)`-t ír (UUID string formátum,
`String(64)`-re illeszkedve) — NEM a belső BigInteger id-t.
Az `A5` cella erre a pontos különbségre épül; a fordított
(eset) a `community_challenges.club_id` oszlop üresen maradna
a `list_club_challenges` lekérdezésnél.

### 10.4 Implicit "activate/end" ablak (§0.0 #2)

A `CommunityChallenge` modell NEM kapott új `state` oszlopot —
az aktiváció és lezárás a `starts_at` / `ends_at` ablakon
alapul:

- **create**: új sor beszúrása a kért ablakkal;
- **activate** (implicit): `now` belép a `[starts_at, ends_at]` ablakba;
- **end** (explicit): `end_club_challenge` az `ends_at`-et `now`-ra
  állítja; a klub owner/moderator szerepéhez kötve (A3 §5.2).

### 10.5 Junction-table a pin tárolásra (scope-kiterjesztés)

A `pinned post reláció` (brief §3) tárolásához egy
`community_club_pinned_posts` junction tábla szükséges
`(club_id, post_id, pinned_at, pinned_by_profile_id)`
oszlopokkal. A tábla:

- a `club_content_service.py` modulon BELÜL van definiálva
  SQLAlchemy `Table` deklarációként (nem új `models/` fájl);
- regisztrálva van a `Base.metadata`-ba, így a tesztek
  `Base.metadata.create_all(...tables=[...])` hívással
  materializálhatják az alembic upgrade után;
- a termelési alembic migráció egy KÖVETKEZŐ kör feladata —
  ez a §10.7-es ismert korlát.

### 10.6 Pin permission (A3 §5.2 cross-club guard)

A pin/unpin/end-challenge permission check a
`backend/app/community/policies/club_permissions.py` NEM
érintésével van megoldva (a permission matrix NINCS a
`allowed_paths` listán). Az új `CLUB_PIN_AUTHORIZED_ROLES`
és `CLUB_CHALLENGE_END_AUTHORIZED_ROLES` halmazok a
`club_content_service.py` elején vannak definiálva, és a
Kör 24 `CLUB_ROLE_OWNER` / `CLUB_ROLE_MODERATOR` wire-értékeit
használják. A check `_ensure_actor_role` helper-en keresztül
a KONKRÉT klub tagsági sorát olvassa — a §5.2 cross-club
invariáns a `_resolve_visible_club_for_member` (feed) és
az `_ensure_actor_role` (service) együttes hívásából következik.

### 10.7 Ismert korlát — termelési alembic migráció

A `community_club_pinned_posts` tábla NINCS alembic
migrációban — a termelési `alembic upgrade head` nem
hozza létre. A teszt fixture a `Base.metadata.create_all`
hívással materializálja, így a backend pytest csomag zöld.
A termelési migrációt egy következő kör (vagy a review-t
követő javító kör) pótolja. Ez a §10.5-vel együtt az egyetlen
ismert hiányossága a körnek; a §6 minden más cellája működik.

### 10.8 Flutter oldali képernyő-helyi providerek (§0.0 #3)

A `club_detail_screen.dart`-on belül három screen-local
provider épül: `clubFeedProvider`, `clubPinnedProvider`,
`clubChallengesProvider`. Ezek:

- `FutureProvider.autoDispose.family<..., ContentId>` mintát
  követnek;
- produkcióban `UnimplementedError`-t dobnak (a wire-backed
  implementáció egy következő kör feladata, a Kör 24
  `communityClubRepositoryProvider` mintára);
- widget tesztben `ProviderScope` override-dal helyőrző
  adatokkal töltődnek fel;
- a `_leave` / `_requestJoin` hívás `ref.invalidate(...)`-szel
  érvényteleníti mind a `clubDetailProvider`-t, mind a három
  screen-local providert — az A2 cache-invariáns.

A `CommunityClubRepository` interfész NEM bővült (a §0.0 #3
struktúrális korlát). A meglévő `CommunityFeedRepository.clubPinned`
metódus a Kör 24 óta fennáll — ez a pin-elt feed forrása.

### 10.9 Valódi-sértés próba (A1 — lefuttatva, parancs és eredmény)

```bash
# A tagság-ellenőrzés kikapcsolása a club_feed modulban
cf._resolve_visible_club_for_member = lambda db, *, club_public_id, viewer_profile_id: \
    db.query(CommunityClub).filter_by(public_id=club_public_id, deleted_at=None).one()

# Ezután: list_club_feed(db, viewer_profile_id=outsider.id, club_public_id=club.public_id, ...)
# Eredmény: outsider 1 posztot kapott a klub feedjéből (korábban ClubNotVisible)
# A1 cella PIROSRA váltott → a guard load-bearing, a védelem működik.
# A próba futtatása után a monkeypatch visszaállításra került.
```

A §6.1 A4-es próba (pin-limit drop) a teszt file-ban
szintén implementálva van (`test_a4_real_violation_probe_drop_pin_limit`):
`MAX_CLUB_PINNED_POSTS = 10_000`-re monkeypatch-elve a
`pin_post` mind a 7 posztot beilleszti (a cap felett).

A §6.1 A1-es próba szintén a teszt file-ban van
(`test_a1_real_violation_probe_drop_membership_check`):
a `_resolve_visible_club_for_member` monkeypatch-elve
kihagyja a membership checket, és az outsider kap egy
club-feed page-et.

### 10.10 Gate státusz

- `tools/round-gate.sh test/features/community/presentation/clubs/club_detail_screen_test.dart` —
  a Flutter-oldali gate. A lezárás előtt futtatandó (lásd §7).
- `cd backend && /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest tests/community/test_club_content_service.py -q` —
  a backend-oldali gate, KÜLÖN parancs (NEM láncolva).
  15/15 teszt zöld (lásd §7).

A `backend/.venv/bin/python -m ruff format app tests` parancs
a §3-as lezáró sorrend része — a format-after-acceptance-t
a §7 megtiltja (`analyze && test` lánc), a format-ot viszont
a kör-zárás előtt futtatni kell.

### 10.11 Kör commitok (négy, lépésenkénti — §2)

```
ff481109  E09-R25: club feed — Kör 13 projection újrahasznosítása club-szűréssel
01e4bbf7  E09-R25: club_content_service — pin/unpin + club-challenge lifecycle
3b6fd0a2  E09-R25: club_detail_screen bővítése — 4 tab + screen-local providers + cache invalidáció
f1c736d3  E09-R25: club_detail_screen widget test — A2 cache invalidáció
fae9ecec  E09-R25: backend test_club_content_service — A1/A3/A4/A5/A6/A7 cells + valódi-sértés próbák
41ff4e25  E09-R25: fix tests — ends_at tz-normalization, profile relation lookup, A1 probe fix
```

A §2 commit-lépésenkénti szabály betartva (minden fájl
után commit, a reviewer egyszer sem talált untracked
production-fájlt).

## 11. Review — a Claude tölti ki
