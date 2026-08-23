# ADR 0410 — Média upload contract és objektumtár integráció

- **Státusz:** Elfogadva (E09-R18 pre-flight, 2026-08-23)
- **Kör:** E09-R18 — Média upload contract és objektumtár integráció
- **Implementer motor:** MiniMax M3 — az ADR-t az orchesztrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055).
- **Epic:** Chapter 10 — Epic 9 (Community Platform), Kör 18 (a 32 kör közül a
  tizennyolcadik)
- **Kontext-ADR-ek:** [0396](0396-community-profile-schema-and-privacy-defaults.md)
  §1 (a `public UUID + bigint PK` minta, amit a `CommunityMedia` tábla is
  követ), [0405](0405-post-crud-and-audience-enforcement.md) (a
  service-szintű domain-kivétel → HTTP-fordítás felelősség-szétválasztás
  mintája, amit ez a kör is követ, ROUTER NÉLKÜL), [0408](0408-bookmark-and-controlled-import.md)
  (a legutóbbi, önálló migrációs slot-foglalás precedense).
- **Sorszám-jegyzet:** a brief fejléce `0407`-et adott előre kiosztott
  ADR-ként, de az azóta E09-R16 (`Kommentek, reply és mention`) foglalta el —
  a `tools/round-slots.py reserve-adr --round E09-R18` friss számot adott
  (`0410`; a `0408`/`0409` már más köröké). A brief §0.0 D1 rögzíti a
  korrekciót.

## Kontextus

**Mért 2026-08-23-án, a pre-flightban:**

1. `backend/app/config.py:83` a `community_media_enabled: bool = False`
   flaget **MÁR tartalmazza** (Epic 9 baseline, E09-R01) — semmilyen
   `config.py`-módosítás nem szükséges, a service egyszerűen
   `settings.community_media_enabled`-et olvassa (ugyanaz a minta, mint
   `backend/app/community/__init__.py:61`'s `if not settings.community_enabled`).
2. **A brief `allowed_paths`-a NEM tartalmaz router-fájlt** (nincs
   `backend/app/community/routers/media.py`, és a `backend/app/main.py`
   tilos zóna). Ez STRUKTURÁLIS, nem hiányosság: a Kör 18 fő érintett
   fájllistája a `docs/sdd/10-epic-09-community-platform.md`-ben (3101–3108.
   sor) is kizárólag `models/media.py` + `services/media_upload_service.py`
   + `storage/object_store.py` + a Dart uploadert sorolja — a HTTP-bekötés
   (router + `main.py`-mountolás) egy KÉSŐBBI kör dolga, ugyanaz a
   "service-réteg kész, router-wiring később" minta, mint a Kör 12 óta
   `UnimplementedError`-t dobó `communityFeedRepositoryProvider`/
   `post_repository_impl.dart` pár (lásd HANDOFF §6). Az A1 acceptance
   ("upload-endpoint teljesen elérhetetlen") ezért a
   **service-függvény szintjén** dől el: `media_upload_service.py` minden
   publikus belépési pontja (`create_upload_intent`, `finalize_upload`,
   `cancel_upload`) a hívás ELSŐ lépéseként ellenőrzi
   `settings.community_media_enabled`-et, és flag KI állapotban egy
   dedikált kivételt dob (`MediaUploadDisabled`, ugyanaz a minta, mint a
   Kör 11 `PostNotFound`/`StalePostUpdateError` domain-kivétel osztály). A
   `backend/tests/community/test_media_upload.py` közvetlenül ezt a
   service-réteget hívja, FastAPI `TestClient` és router nélkül — pontosan
   úgy, ahogy `test_bookmark_service.py`/`test_reaction_service.py` is a
   saját, önálló engine/session-t építi a `conftest.py` (nem-allowed-path)
   fixture-jei helyett.
3. **Nincs S3-SDK a repóban, és a `backend/requirements.txt` NINCS az
   `allowed_paths`-on** (mérve: `grep boto backend/requirements.txt` → nulla
   találat; a fájl tartalma kizárólag `fastapi`, `uvicorn`, `SQLAlchemy`,
   `alembic`, `pydantic[-settings]`, `email-validator`, `PyJWT`, `bcrypt`,
   `python-multipart`, `httpx`). Csomagtelepítés a kör alatt tilos
   (implementer-preambulum §4). A "konkrét S3-kompatibilis adapter" ezért
   **kizárólag a Python stdlibre (`hmac`, `hashlib`, `urllib.parse`,
   `datetime`) és a MÁR jelenlévő `httpx`-re** épülhet: az AWS SigV4
   presigned-URL séma (query-string aláírás) egy nyilvános, SDK nélkül
   implementálható algoritmus — a `boto3`/`minio` kliens csak kényelmi
   burkoló, nem az egyetlen módja a séma előállításának. A `httpx` a
   finalize-oldali `HEAD`-hívásra (object existence/size/etag lekérdezés)
   szolgál egy valódi bucket ellen; a fejlesztői/CI-teszt path egy
   in-memory fake `ObjectStore`-implementációt kap (lásd D2).
4. `backend/alembic/versions/` legfrissebb slotja `e09_r17_0011_community_bookmark.py`
   — a brief `e09_r18_0012_community_media.py` neve a következő sorszámmal
   konzisztens, nincs drift.
5. A projekt SHA-256-ot használ minden meglévő content-hash/checksum
   helyen (`docs/adr/0090` asset store `<sha256>.<ext>` elrendezés;
   `profile_search_repository.py`/`following_feed.py` HMAC-SHA256 signed
   cursor). A média checksum mezője ugyanezt az algoritmust veszi át — nincs
   ok új hash-family bevezetésére.
6. `lib/features/community/data/api/` könyvtár MA nem létezik (a
   `data/` alatt eddig csak `local/`, `dto/`, `repositories/` van) — az
   uploader az ELSŐ fájl ott, új könyvtárral. A `dio: ^5.7.0`
   (`pubspec.yaml`) natívan támogat `CancelToken`-t és `onSendProgress`
   callbacket — nincs szükség új pluginra vagy win32-érintésre.

## Döntés

**D1 — ADR-szám korrekció.** A brief előre kiosztott `0407`-e elavult; ez az
ADR `0410` néven készül, a `tools/round-slots.py reserve-adr` friss
foglalása szerint.

**D2 — Vendor-semleges `ObjectStore` interfész + stdlib-only S3-adapter,
tesztekhez in-memory fake.** `backend/app/community/storage/object_store.py`
definiál egy absztrakt `ObjectStore` protokollt/ABC-t:

- `create_upload_url(key, *, content_type, max_content_length, expires_in) -> SignedUpload`
  (a signed PUT-URL + a lejárat időbélyege + az elvárt fejlécek).
- `head_object(key) -> ObjectMetadata | None` (méret, checksum/etag,
  content-type — `None`, ha az objektum nem létezik).
- `delete_object(key) -> None` (idempotens — a törölt/nemlétező objektumra
  is sikeresen tér vissza, az orphan-cleanup job newline-safe ismételt
  futtatásához).

Két implementáció:

1. **`S3CompatibleObjectStore`** — a konkrét, "valódi bucket" adapter.
   A presigned PUT-URL-t AWS SigV4 query-string aláírással állítja elő
   (`hmac`/`hashlib`/`urllib.parse`, stdlib), a `head_object`/`delete_object`
   pedig aláírt `HEAD`/`DELETE` HTTP-hívás a MÁR jelenlévő `httpx`-en
   keresztül. Nincs `boto3`/`minio`-import.
2. **`InMemoryObjectStore`** (vagy ezzel egyenértékű fake) — a
   `test_media_upload.py` ezt injektálja: a `create_upload_url` egy
   determinisztikus, tesztelhető lejáratú URL-t ad, a `head_object` a teszt
   által előre beállított (méret, checksum) párt adja vissza a finalize-
   ellenőrzés determinisztikus meghajtásához (a §6 A2/A4/A5/küszöb-hármas
   cellák enélkül nem lennének reprodukálhatók valódi hálózati hívás
   nélkül).

A `media_upload_service.py` az `ObjectStore` interfészen keresztül dolgozik
(dependency injection, a `now: datetime` caller-supplied clock mintájával
együtt, `post_service.py` precedens) — sosem az egyik konkrét implementációt
importálja közvetlenül.

**D3 — Flag-ellenőrzés a service-rétegben, router nélkül.** A brief
`allowed_paths`-a nem tartalmaz router-fájlt (mérve, Kontextus/2. pont). A
`media_upload_service.py` minden publikus függvénye elsőként
`settings.community_media_enabled`-et ellenőrzi, és `MediaUploadDisabled`
kivételt dob flag KI esetén — a HTTP-bekötés (router + `main.py`) egy
későbbi kör hatásköre, ugyanúgy, ahogy a Kör 2 `build_community_router`
factory-ja is deferrelte a `main.py`-mountolást.

**D4 — Checksum: SHA-256, a projekt egységes content-hash algoritmusa.**
A `CommunityMedia.checksum_sha256` mező (vagy ezzel egyenértékű nevű oszlop)
64 hex karakteres SHA-256 digest — ugyanaz a család, mint az ADR 0090 asset
store és a signed-cursor HMAC-SHA256.

**D5 — A `public UUID + bigint PK` minta követése.** `CommunityMedia`
`id: BigInteger` internal PK + `public_id: Uuid` — a kliens sosem látja a
belső sorszámot, a finalize/cancel/ownership-ellenőrzés a `public_id`-n
keresztül azonosítja a médiát (ADR 0396 §1 precedens).

**D6 — A méret-küszöb inkluzív, kétszeresen ellenőrzött.** A
`MAX_UPLOAD_BYTES` modul-szintű konstans a `media_upload_service.py`-ban (a
`backend/app/config.py` nincs az `allowed_paths`-on, tehát nem kap saját
`Settings`-mezőt ebben a körben — egy jövőbeli kör tehetné konfigurálhatóvá).
`size <= MAX_UPLOAD_BYTES` elfogadott, `size > MAX_UPLOAD_BYTES` elutasított
— a finalize a signed URL content-length korlátozásától FÜGGETLENÜL is
újra megméri (defense-in-depth, brief §6.1 küszöb-hármas).

## Következmények

- A router-wiring (HTTP endpoint, `main.py` mountolás) egy KÉSŐBBI kör
  tartozása marad — ugyanaz a mért tartozás-osztály, mint a feed/post
  repository HTTP-bekötés. Ezt a HANDOFF §6-nak dokumentálnia kell a záró
  rituáléban.
- A `S3CompatibleObjectStore` stdlib-only SigV4 implementációja a jövőben
  cserélhető egy SDK-alapúra (`boto3`), ha egy jövőbeli kör a
  `requirements.txt`-et is az `allowed_paths`-ára veszi — az `ObjectStore`
  interfész emiatt nem vendor-specifikus (a metódusnevek nem AWS-terminológiát
  tükröznek, hanem a domain-műveletet).
- A Kör 19 (média feldolgozás/moderation state) erre a `CommunityMedia`
  táblára épít majd egy `processing_state` oszlopot/állapotgépet — ez a kör
  csak az upload-state-et (pending/uploaded/finalized/cancelled/failed)
  definiálja, a feldolgozási állapotgépet NEM.

## Alternatívák

- **Proxy-upload a FastAPI backenden át:** elvetve (brief §5.1, §12.4
  SDD-alapelv sértése — memória/hálózat-terhelés, DoS-vektor).
- **`boto3` hozzáadása a `requirements.txt`-hez:** elvetve ebben a körben —
  a fájl nincs az `allowed_paths`-on, és csomagtelepítés a kör alatt tilos.
  Egy jövőbeli kör dönthet úgy, hogy a stdlib SigV4-et lecseréli SDK-ra, ha
  a fájl felkerül egy brief engedélyezett listájára.
- **Router + `main.py`-mountolás EBBEN a körben:** elvetve — nincs az
  `allowed_paths`-on, és a brief scope-ja explicit kizárja a poszt/komment
  UI-integrációt (csak "a flag mögött LÉTEZIK az uploader-komponens").
