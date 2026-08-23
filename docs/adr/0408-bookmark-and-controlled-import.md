# ADR 0408 — Bookmark, mentett tartalom és biztonságos import

- **Státusz:** Elfogadva (E09-R17 pre-flight, 2026-08-23)
- **Kör:** E09-R17 — Bookmark, mentett tartalom és biztonságos import
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 17 (a 32 kör közül a
  tizenhetedik)
- **Kontext-ADR-ek:** [0404](0404-share-artifact-contracts.md) (Kör 10 — a
  `ShareArtifactUnion`/`schema_version` szerződés, amit ez a kör fogyaszt, nem
  redefiniál), [0405](0405-post-crud-and-audience-enforcement.md) (Kör 11 — a
  `deleted_at`/`moderation_state` soft-delete pár és az egységes-404 minta,
  amit a bookmark tombstone-kezelése alapul vesz), [0398](0398-profile-privacy-audience-policy-and-access-control.md)
  (Kör 4 idempotencia-precedens: PÁR-egyediség UNIQUE constraint, amit a Kör
  15 reakció-tábla és most a bookmark-tábla is követ).
- **Sorszám-jegyzet:** a brief fejléce `0406`-ot adott előre kiosztott
  ADR-ként, de az azóta E09-R13 (`Following feed és cursor pagination`)
  foglalta el, `0407`-et pedig E09-R16 (`Kommentek, reply és mention`) — a
  `tools/round-slots.py reserve-adr --round E09-R17` friss számot adott
  (`0408`). A brief §0.0 D1 rögzíti a korrekciót.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban:**

1. `backend/app/community/schemas/artifacts.py` MA a `_SongFieldsMixin`
   (`song_name`, `chords`, `strum_pattern`, `bpm`, `beats_per_bar`) mezőkészletet
   osztja meg `SongResultArtifact`/`OriginalProgressionArtifact`/
   `PlanTemplateArtifact` között — a Kör 17 import-célja tehát mindkét
   importálható típusnál (`planTemplate`, `originalProgression`) ugyanaz a
   wire-alak, amit `lib/features/songs/model/song.dart`'s `Song` típusa fed le
   (`Song.fromJson`/`.toJson` már ismeri ugyanezt a mezőkészletet, mert
   `song_share_mapper.dart` a FORDÍTOTT irányt — `Song → artifact` —
   valósítja meg, E09-R10).
2. **Erőforrás-tulajdonlás mérve** (`grep -rln "songsRepositoryProvider" lib/`):
   a `songsRepositoryProvider`/`SongsController.add()` (a helyes, új-id-t
   generáló, ütközés-mentes belépési pont egy ÚJ `Song` perzisztálására) a
   `lib/features/songs/providers/songs_provider.dart`-ban él, és **nulla**
   találat esik rá a `lib/features/songs/` mappán KÍVÜL — `lib/features/songs/
   public.dart` ma KIZÁRÓLAG a `model/song.dart`-ot exportálja (a `Song` típust
   magát, `SongsRepository`/`songsRepositoryProvider`/`SongsController`
   nélkül). A `docs/sdd/10-epic-09-community-platform.md` §7.3 explicit tiltja
   "más Flutter feature belső data rétegének importálását" — az
   `import_share_artifact.dart` tehát NEM importálhatja a `songs_provider.dart`-ot
   közvetlenül, és a `lib/features/songs/public.dart` bővítése **nincs** ennek a
   körnek az `allowed_paths`-ában (egy másik feature-t célzó kör mindig kívül
   esik ezen — ez STRUKTURÁLIS, nem véletlen hiányosság).
3. **Pontosan ugyanez a mintázat már megoldva egyszer** (L286, E07-R08, docs/LESSONS.md
   10644. sor): a Practice Engine adapter körben a cél-feature repository/
   provider rétege szintén exportálatlan volt a `public.dart`-on, és a
   feloldás — dokumentált §0.0 brief-revízióval — az volt, hogy az adapter
   PURE, hívó-táplált transzformátor lett, élő repository-olvasás/írás
   nélkül. Ugyanezt a mintát alkalmazza ez az ADR (D1).
4. `backend/app/community/models/reaction.py` (Kör 15) a `UNIQUE(post_id,
   profile_id)` konstraintra épülő idempotens set/remove minta ÉLŐ,
   tesztelt precedens — a bookmark-tábla ugyanezt a szerkezetet veszi át,
   `ON DELETE CASCADE` mindkét FK-n (poszt és profil hard-delete-jére).
5. `backend/app/community/models/post.py` a `deleted_at`/`moderation_state`
   soft-delete párt hordozza — egy poszt SOFT delete-je NEM törli a sort,
   tehát a bookmark FK-ja a törlés UTÁN is feloldható marad; a tombstone-kezelés
   ebből következően a bookmark-lista lekérdezés SAJÁT felelőssége (a
   szolgáltatás észleli a `deleted_at IS NOT NULL`/`moderation_state !=
   "visible"` állapotot, és egy biztonságos placeholder mezőt ad vissza a teljes
   poszt-body helyett — sosem `None`-mezőt render-elő crash-t).
6. `backend/app/community/feed/following_feed.py` HMAC-aláírt, opak cursor
   mintát használ — ez a modul NINCS ennek a körnek az `allowed_paths`-ában,
   tehát a bookmark-router NEM hívhatja/importálhatja. A bookmark-lista
   viszont kizárólag a SAJÁT tulajdonosának (a JWT-ből felold profilnak)
   szűrt, privát nézet — nincs adversarial lapozás-manipulációs kockázat, mint
   egy publikus feednél.
7. `backend/tests/community/test_post_service.py` és testvérei a
   `build_community_router`/`routers/profile.py` (tilos zóna) megkerülésével,
   SAJÁT `FastAPI()` + `TestClient()` példányt építenek, amely KIZÁRÓLAG a
   saját router-modult mountolja (`app.include_router(posts_router)`) — ez a
   projektben MÁR bevett minta minden Kör 11+ router-tesztre; a bookmark-router
   tesztje ugyanezt követi, nem igényel `main.py`/`profile.py` érintést.

## Döntés

### D1 — Az import PURE, hívó-táplált transzformátor: nincs élő `songsProvider`-írás ebben a körben

Az `import_share_artifact.dart` a schema/licenc/meta/ütközés-validáció UTÁN
egy ÚJ, friss (nem a forrás `sourceId`-t újrahasználó) `Song`-értéket épít és
ad vissza egy `ImportResult`-típusban — de **nem** hívja a `songsProvider`/
`SongsController.add()`-ot, mert az a `lib/features/songs/public.dart`-on
kívül él, aminek bővítése kívül esik ennek a körnek az `allowed_paths`-án
(lásd Kontextus 2. pont). A TÉNYLEGES helyi perzisztálás bekötése — a
Bookmarks képernyő "Import" gombjának a `songsProvider`-hez kötése — egy
jövőbeli kör dolga, amelynek `allowed_paths`-a MÁR tartalmazza (vagy explicit
bővíti) a `lib/features/songs/public.dart`-ot.

**Ez NEM gyengíti az A5 acceptance-t.** Az A5 cella ("Import új lokális
példányt hoz létre, a forrás community post változatlan marad") a PURE
use-case szintjén mérhető és mérendő: a teszt hívja `importShareArtifact
(artifact)`-ot, és ellenőrzi, hogy (a) a visszaadott `Song`/`ImportResult`
egy ÚJ, a `sourceId`-től független azonosítót visel, (b) a bemeneti
`ShareArtifact` objektum minden mezője változatlan marad a hívás után
(nincs mutáció) — mindkettő tesztelhető élő repository nélkül, pontosan az
Epic 7 R01-R08 minden adapterének mintáját követve (hívó-táplált wrapper,
nulla élő repository-olvasás, nulla production hívó ebben a körben).

**Elutasított alternatíva:** a `lib/features/songs/public.dart` bővítése egy
`songsProvider` exporttal. Elvetve: az `allowed_paths` nem tartalmazza ezt a
fájlt, és egy másik feature-t célzó kör `allowed_paths`-ának bővítése
STRUKTURÁLIS H3-kockázat (ADR 0087 §2) — az L286 lecke explicit erre inti:
"NE feltételezd az `allowed_paths` bővítését, ha van bevett pure-transformer
minta". Van.

### D2 — A bookmark-tábla a Kör 15 reakció-tábla `UNIQUE(post_id, profile_id)` mintáját veszi át

`community_bookmarks(id, post_id FK→community_posts.id ON DELETE CASCADE,
profile_id FK→community_profiles.id ON DELETE CASCADE, created_at,
UNIQUE(post_id, profile_id))`. A set idempotens (retry ugyanazon párra
no-op), a remove idempotens (már nem létező bookmarkra sikeres no-op, nem
404) — a `safety.py` block/mute DELETE-mintáját követve (ADR 0405 D10).

### D3 — A tombstone-kezelés a bookmark-lekérdezés SAJÁT felelőssége, nem egy megosztott feed-helper

A bookmark-lista szolgáltatás minden sorhoz betölti a kapcsolódó posztot, és
ha `deleted_at IS NOT NULL` VAGY `moderation_state != "visible"`, egy explicit
tombstone-jelölésű elemet ad vissza (pl. `is_available: false` + a poszt
tartalmi mezői nélkül) — SOSEM dereferál egy hiányzó/törölt mezőt, SOSEM 500-at
dob, és a bookmark SORT nem törli (a felhasználó privát listája megőrzi a
"ezt egyszer elmentettem" tényt akkor is, ha a tartalom már nem elérhető).

### D4 — A cursor-lapozás önálló, a bookmark-routerben él, nem a `feed/following_feed.py` HMAC-mintáját hívja

Mivel a `feed/**` modul nincs ennek a körnek az `allowed_paths`-ában, a
`routers/bookmarks.py` egy egyszerű, önálló `(created_at, id)` keyset-cursort
implementál (base64-kódolt, aláírás nélkül) — a lista mindig a JWT-ből
felold, hívó saját profiljára szűkül, tehát nincs olyan adversarial
lapozás-kockázat, ami a publikus feed HMAC-aláírását indokolná (az OWASP
IDOR-kockázat itt nem áll fenn: a bookmark-lista lekérdezés a `profile_id`-t
szerver-oldalon, a JWT-ből olvassa, nem a cursorból vagy egy kliens-küldött
paraméterből).

### D5 — A licenc/meta és névütközés-ellenőrzés kizárólag a Flutter use-case rétegben él, nincs backend-oldali "licence" mező

A `backend/app/community/schemas/artifacts.py` MA nem hordoz `licence`/
`deprecated` mezőt egyik artifact-típuson sem (mérve: 0 találat). A brief §3
"licenc/meta státusz" és "ismeretlen/deprecated artifact" ellenőrzése ebben a
körben kliens-oldali, a MEGLÉVŐ mezőkészletből levezetett szabály:
`schema_version != SHARE_ARTIFACT_SCHEMA_VERSION` ⇒ ismeretlen (A4, reject);
egy jövőbeli, MÁSODIK schema-verzió bevezetésekor az "deprecated, de még
ismert" kategória (A7, read-only fallback) ténylegesen betölthető lesz — addig
az A7 cella a §10 valódi-sértés próbájával egybevágóan a "poszt
`moderation_state != visible`, DE a bookmark-sor megmarad" esetet fedi le
(ugyanaz az állapot, mint D3), nem egy külön licenc-mezőt. Ez a leszűkítés
dokumentálva van a brief §0.0-jában is; nem lista-tágítás, hanem a MEGLÉVŐ
mezőkészlethez igazított, szűkebb-de-mérhető definíció.

## Elutasított alternatívák

- **`lib/features/songs/public.dart` bővítése ebben a körben** (lásd D1) —
  elvetve, `allowed_paths`-on kívüli fájl, van bevett pure-transformer
  precedens (L286).
- **A `feed/following_feed.py` HMAC-cursor helperének importálása** (D4) —
  elvetve, `feed/**` nincs az `allowed_paths`-ban, és a privát,
  csak-saját-profilra szűkített lista nem igényli az aláírt curzor
  védelmét.
- **Backend-oldali `licence`/`deprecated` mező hozzáadása az artifact-sémához
  ebben a körben** (D5) — elvetve, `docs/adr/**` (a Kör 10 kontraktus) és a
  `backend/app/community/schemas/artifacts.py` egyaránt kívül esik ennek a
  körnek az `allowed_paths`-án; a meglévő `schema_version` + `moderation_state`
  párból mérhetően levezethető, szűkebb definíció elégséges az A4/A7
  cellákhoz.

## Következmények

- A Bookmarks képernyő "Import" gombja ebben a körben validál és egy ÚJ
  `Song`-értéket épít, de NEM ír helyi storage-ba — egy jövőbeli kör kötelező
  follow-upja a `songsProvider` tényleges bekötése (a `lib/features/songs/
  public.dart` bővítésével, SAJÁT `allowed_paths`-ában).
- A D5 szűkítés azt jelenti, hogy amíg nincs második `schema_version`, az A7
  "deprecated" ág gyakorlatilag ugyanazt az állapotot fedi, mint az A3
  tombstone-ág — egy jövőbeli schema-bump körnek ezt a két ágat élesen szét
  kell választania.
- A D4 önálló cursor a bookmark-listára korlátozódik; ha egy jövőbeli kör egy
  PUBLIKUS bookmark-számlálót vagy megosztott listát vezetne be (a §5.2
  invariáns tudatos megszegésével — jelenleg nem tervezett), a HMAC-aláírt
  cursor mintára kellene váltania.

## A visszavonás feltétele

Felülvizsgálandó, amint (a) egy jövőbeli kör bekötné a tényleges
`songsProvider`-perzisztálást (D1 megszűnik, a "pure transformer" helyett élő
íróhívás lép életbe), vagy (b) egy második artifact `schema_version` jelenne
meg (D5 "deprecated" ága ténylegesen elválik a tombstone-ágtól).
