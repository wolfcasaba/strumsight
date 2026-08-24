# ADR 0420 — Klub domain, tagság és szerepkörök

- **Státusz:** Elfogadva (E09-R24 pre-flight, 2026-08-24)
- **Kör:** E09-R24 — Klub domain, tagság és szerepkörök
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 24 (a 32 kör közül a huszonnegyedik)
- **Kontext-ADR-ek:** [0399](0399-flutter-community-domain-and-public-api.md)
  (Kör 5 — `CommunityClub`/`ClubVisibility`/`ClubRole`/`CommunityClubRepository`
  MÁR élnek a `domain/**`-ban, tilos zóna, csak-hívás), [0402](0402-block-mute-and-safety-relationships.md)
  (Kör 8 — `query_filters.py::is_blocked_pair`/`filter_public_ids_against_viewer_blocks`,
  a §D4 pure-helper kontraktus EXPLICIT erre a körre bízta a bekötést),
  [0405](0405-post-crud-and-audience-enforcement.md) (Kör 11 — `community_posts.club_id`
  BigInteger, FK NÉLKÜL, Kör 24 horog), [0415](0415-community-challenge-invite-lifecycle.md)
  (Kör 21 — `community_challenges.club_id` STRING, FK NÉLKÜL, Kör 24 horog;
  idempotency DB-unique + `IntegrityError`-újraolvasás minta; L421 race-teszt lecke).
- **Sorszám-jegyzet:** a pipeline-prompt E09-R24-hez `0413`-at adott előre
  kiosztott ADR-ként, de ez a szám MÁR foglalt. A
  `tools/round-slots.py reserve-adr --round E09-R24` friss számot adott:
  **`0420`**.
- **Visszakeresés (ADR 0312, pre-flight §4.9):**
  `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "klub tagság
  owner transfer permission mátrix"` → **ADR 0405 §Következmények** (a
  `community_posts.club_id` FK-constraint és a `community_club.id`-ra mutató
  kapcsolat felülvizsgálandó, amikor ez a kör él club-tagot ad) és
  **ADR 0415 §Döntés/§A visszavonás feltétele** (a `community_challenges.club_id`
  ugyanez a horog, más típussal — lásd D2 lent) — **közvetlenül alkalmazandó**.
  `node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "duplikált join
  idempotency race concurrent membership block filter integráció"` → **L421**
  (`threading.Thread`-alapú konkurens próba szinkronizáció NÉLKÜL nem
  determinisztikus, E09-R07, 10 futásból 7 piros) — **közvetlenül alkalmazandó
  az A3 duplikált-join valódi-sértés próbájára, ha threading-alapú race-tesztet
  választ az implementer**, lásd D5. `node tools/knowledge-rag.mjs --top 5
  "community_club domain repository ClubRole ClubVisibility"` → a MÁR élő
  `community_club.dart`/`club_repository.dart` (Kör 5, ADR 0399) — lásd D1.

## Kontextus

**Mért 2026-08-24-én, a pre-flightban (ez a §0.0 hordozza a teljes
tényellenőrzést, a brief eredeti szövege felülíródik):**

1. `grep -rln "club" lib/features/community/domain/` → **`community_club.dart`**
   és **`club_repository.dart`** MÁR léteznek (Kör 5, ADR 0399) — ez NEM az
   első kör, ami a klub-entitást definiálja a Flutter-oldalon, csak az első,
   ami a szerveroldalt és a lifecycle-t megépíti. A kliens-kontraktus
   MEGKÖTI a backend wire-formátumot:
   - `ClubVisibility` **HÁROM** állapot: `private`, `discoverable`, `public`
     (`clubVisibilityFromWire`/`clubVisibilityToWire`, alsó-eset enum-name
     mint wire-string) — a brief eredeti "private/public" olvasata hiányos,
     a `discoverable` a klub-keresésben látszik, de a publikus profil-felületen
     nem (SDD §16.2).
   - `ClubRole` **HÁROM** állapot: `owner`, `moderator`, `member` — byte-azonos
     wire-string a `.name`-mel, ugyanaz a minta mint `ChallengeInviteState`
     (ADR 0415 D1).
   - `kCommunityClubMaxMembers = 500` MÁR ki van mérve a Flutter oldalon
     (`community_club.dart` sor 42) — az A7 küszöb-hármas EBBEN a körben
     NEM egy önkényes új konfigurációs érték, hanem ennek a MÁR élő
     konstansnak a szerveroldali tükrözése: `MAX_CLUB_MEMBERS = 500` a
     `club_service.py`-ban (vagy a modellben), a küszöb-cellák 499/500/501
     tagszámmal futnak (lásd D3).
   - `transferOwnership` doksi-kommentje EXPLICIT: "Existing `owner` becomes
     a plain `member`" — az A8 "member-re **vagy** moderator-ra" megfogalmazás
     TÉVES tágítás, a helyes állítás: a régi owner role-ja PONTOSAN `member`-re
     vált (lásd D4, a brief §6 A8 sora javítva).
   - A repository minden mutáló hívása (`requestJoin`, `invite`, `leave`,
     `removeMember`, `transferOwnership`) `idempotencyKey` paramétert visz —
     a szerveroldali service-nek ugyanazt a Kör 20/21 mintát kell követnie
     (DB unique constraint + előzetes olvasás + `IntegrityError` → rollback →
     újraolvasás), NEM egy új idempotencia-mechanizmust kitalálnia (lásd D5).
   - A metódus neve `requestJoin`, NEM `join` — ez összhangban van a brief A4
     "invite/elfogadott request" követelményével: egy `private` klubba a
     join-hívás egy FÜGGŐ kérést hoz létre, amit egy owner/moderator fogad el
     (lásd D6); `discoverable`/`public` klubnál a request azonnal taggá válik.
   - **`club_id`/`public_id` konvenció.** A megállapodott Community-mintát
     (belső `id: BigInteger` PK + `public_id: Uuid(as_uuid=True), unique=True`
     külső azonosító, mint `community_posts`/`community_challenges`) a
     `community_clubs` táblának is követnie kell — a `ContentId` value object
     a `public_id` UUID-ot string-ként csomagolja.
2. **Mért típus-inkonzisztencia a két MEGLÉVŐ `club_id` horogban (informatív,
   NEM ennek a körnek a feladata javítani).** `community_posts.club_id`
   (Kör 11, ADR 0405) **BigInteger**, `community_challenges.club_id` (Kör 21,
   ADR 0415 D7) **String**. Egyik sem FK. Amikor egy jövőbeli kör (Kör 25,
   klub-feed/klub-challenge) élő FK-t ad ezekhez, a típus-eltérést fel kell
   oldania — ez a `community_clubs.id`/`public_id` típusától függ, amit ez a
   kör most rögzít (D1 szerint BigInteger belső id, UUID public_id). A Kör 25
   brief-jének kell erre hivatkoznia.
3. `grep -n "def " backend/app/community/policies/query_filters.py` →
   `is_blocked_pair(db, *, profile_id_a, profile_id_b)` és
   `filter_public_ids_against_viewer_blocks(...)` — ez a §5.3 "közös szűrő"
   pontos hívási alakja, amit a klub-tartalom és tagság-lekérdezéseknek
   hívniuk kell (write-side és read-side is), NEM egy klub-specifikus
   párhuzamos block-ellenőrzés.
4. `ls backend/alembic/versions/ | sort | tail -1` → `e09_r23_0017_...` —
   a brief `e09_r24_0018_community_club.py` fájlneve és `down_revision =
   "e09_r23_0017"` a helyes, folytonos lánc-illesztés.
5. **A "create" képernyő nincs külön allowed_paths-fájlon.** A brief §3
   scope-szövege "list/detail/create/member-management képernyő"-t mond, de
   a §4 engedélyezett fájllista csak három screen-t sorol
   (`club_list_screen.dart`, `club_detail_screen.dart`,
   `club_member_management_screen.dart`) — NINCS önálló
   `club_create_screen.dart`. **Javítás (D7):** a klub-létrehozás UI
   (`createClub` hívás) a `club_list_screen.dart`-ba épül (pl. egy
   létrehozás-dialógus/route ugyanabban a fájlban), külön screen-fájl
   hozzáadása ehhez a körhöz **tilos** (H3, `allowed_paths` szűkítés, nem
   tágítás).

## Döntés

### D1 — `community_clubs` PK/public-id konvenció

Belső `id: BigInteger` (autoincrement) PK, `public_id: Uuid(as_uuid=True),
unique=True` külső azonosító — ugyanaz a minta, mint `community_posts`/
`community_challenges`/`community_profiles`. A `ContentId` Flutter value
object ezt az UUID-ot string-ként csomagolja.

### D2 — A típus-inkonzisztens `club_id` horgokhoz NEM nyúlunk ebben a körben

`community_posts.club_id` (BigInteger) és `community_challenges.club_id`
(String) tilos zóna (nincsenek az `allowed_paths`-on) — ez a kör csak a
`community_clubs`/`community_club_members`/`community_club_invites`
táblákat hozza létre. A típus-eltérés feloldása a Kör 25 (klub-feed/
klub-challenge FK bekötés) dolga, ADR 0405/0415 kontextus-hivatkozással.

### D3 — `MAX_CLUB_MEMBERS = 500`, a Flutter `kCommunityClubMaxMembers`
tükrözése

A szerveroldali membership-limit konstans értéke PONTOSAN `500`
(`community_club.dart` sor 42 tükrözése, nem önkényes új szám). A §6.1
küszöb-hármas cellái ehhez az értékhez kötve: `member_count = 499` (alatt,
elfogad), `member_count = 500` (rajta, MÉG elfogad — az 500. tag betölti az
utolsó szabad helyet), `member_count = 500` + egy ÚJABB join (fölött,
elutasít). Az invite-limit egy külön, kisebb konstans (a brief nem rögzít
pontos számot — az implementer választ egy dokumentált, ésszerű értéket, pl.
50 függő invite/klub, és a §10-ben rögzíti az indokot).

### D4 — Ownership transfer: a régi owner role-ja PONTOSAN `member`

A brief §6 A8 sora ("member-re vagy moderator-ra") javítva: a
`transferOwnership` után a régi owner role-ja mindig `member` (a Flutter
kliens-kontraktus doksi-kommentje ezt explicit rögzíti). Ha az owner egy
adott moderator-t akar owner-ré tenni ÉS saját magát moderator-on tartani,
az egy KÜLÖN, jövőbeli "role downgrade" művelet, nem ennek a körnek a
scope-ja.

### D5 — Idempotencia és a duplikált-join próba

A `requestJoin`/`invite`/`leave`/`removeMember`/`transferOwnership`
mindegyike a Kör 20/21 idempotency-mintát követi: DB unique constraint (pl.
`(club_id, profile_id)` a tagság-táblán, `(club_id, invitee_profile_id,
idempotency_key)` a meghívás-táblán) + előzetes olvasás + `IntegrityError` →
rollback → újraolvasás. Az A3 "duplikált join nem hoz létre két tagságot"
valódi-sértés próbája **ELSŐDLEGESEN** ezt a DB-szintű constraintot méri
(két egymást követő `requestJoin`/join-elfogadás hívás, a második az
UNIQUE-ot üti) — ez NEM igényel threading-et. Ha az implementer emellett egy
konkurens (két-szálas) race-tesztet is ír, az L421 lecke szerint a
`threading.Barrier`-t a PONTOS SQL-döntési pont elé kell tenni (egy
`_before_insert`/`_before_transition` seam), NEM a szál-indítás elé —
különben a próba nem determinisztikus (10-ből 7 piros mérve E09-R07-ben).

### D6 — Private klub belépés: `requestJoin` → függő kérés → owner/moderator
elfogadás; `discoverable`/`public` → azonnali tagság

A `club_service.py` `request_join` függvénye a klub `visibility` mezője
szerint ágazik: `private` esetén egy függő (`pending`) tagsági/kérés-sort hoz
létre, amit egy KÜLÖN, owner/moderator jogosultságú "elfogadás" hívás old fel
aktív tagsággá (ez a hívás a §4 engedélyezett `club_service.py`-ban él, HTTP
router nélkül is elfogadható ebben a körben — a Flutter kliens-kontraktus
ehhez a jövőben ad felületet). `discoverable`/`public` esetén a `request_join`
azonnal aktív tagságot hoz létre (a limit- és block-ellenőrzés után).

### D7 — Nincs önálló create-screen fájl

A klub-létrehozás UI a `club_list_screen.dart`-ba épül (dialógus vagy
beágyazott route), nem kap saját fájlt — az `allowed_paths` a mérvadó, a
brief §3 "create képernyő" szövege pontatlan volt.

### D8 — Block-szűrő újrahasznosítás

Minden klub-tartalom és tagság-lekérdezés (tag-lista, klub-kereső találatok,
member-management lista) a `query_filters.py::is_blocked_pair`/
`filter_public_ids_against_viewer_blocks` hívásokon megy át, write-side ÉS
read-side is — a `query_filters.py` maga tilos zóna (csak-hívás).

## Következmények

- A Kör 25 (klub-feed/klub-challenge) brief-jének explicit hivatkoznia kell
  erre az ADR-re a `community_posts.club_id`/`community_challenges.club_id`
  FK-bekötéskor (D1/D2 típus-döntés).
- A `club_service.py` "elfogadás" hívása (D6) HTTP endpoint nélkül marad
  ebben a körben — egy jövőbeli kör dolga a router-bekötés, ugyanúgy, ahogy a
  Kör 20 sem kötötte be minden notification-eseményt élőben.
- A membership-limit (`500`) és az invite-limit két KÜLÖN konstans — a
  §6.1 küszöb-hármas csak a membership-limitre kötelező, az invite-limitre
  az implementer választ egy dokumentált értéket.
