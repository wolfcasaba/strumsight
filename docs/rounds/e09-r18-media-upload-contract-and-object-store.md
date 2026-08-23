# E09-R18 — Média upload contract és objektumtár integráció

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ db6293f4`)
- **Típus:** Chapter 10 (Epic 9 — Community Platform), Kör 18
- **Kör-azonosító:** `E09-R18`
- **Branch:** `<motor>/e09-r18-media-upload-contract-and-object-store`
- **Előfeltétel:** `E09-R17` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0407`~~ **ADR 0410** (a `0407`-et E09-R16 azóta elfoglalta — §0.0 D0). Az ADR-t a Claude írja meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 1 `communityMediaEnabled` flag TÉNYLEGES helyét — a teljes upload-pipeline ez alá a KÜLÖN flag alá kerül, nem a fő `communityEnabled` alá. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/community/models/media.py",
  "backend/app/community/services/media_upload_service.py",
  "backend/app/community/storage/object_store.py",
  "backend/alembic/versions/e09_r18_0012_community_media.py",
  "lib/features/community/data/api/community_media_uploader.dart",
  "backend/tests/community/test_media_upload.py",
  "test/features/community/data/community_media_uploader_test.dart",
  "docs/rounds/e09-r18-media-upload-contract-and-object-store.md",
]
gate_tests = [
  "test/features/community/data/community_media_uploader_test.dart"
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

## 0.0 Pre-flight revízió (Claude, 2026-08-23, `main @ 4117c748`)

**D0 — ADR-szám korrekció.** A fenti fejléc `ADR 0407`-e elavult (azóta
E09-R16 — Kommentek, reply és mention — foglalta el, lásd
`docs/adr/0407-comment-reply-and-mention.md`). A `tools/round-slots.py
reserve-adr --round E09-R18` friss számot adott: **ADR 0410**
(`docs/adr/0410-media-upload-contract-and-object-store.md`). Minden ezután
következő hivatkozás `0407` helyett `0410`-re értendő.

**D1 — nincs router-fájl az `allowed_paths`-on, és ez SZÁNDÉKOS.** A brief
§4 engedélyezett fájllistája nem tartalmaz `backend/app/community/routers/media.py`-t,
és a `backend/app/main.py` tilos zóna. Ez konzisztens a
`docs/sdd/10-epic-09-community-platform.md` Kör 18 "Fő érintett fájlok"
listájával (csak model/service/storage/Dart-uploader). Az A1 acceptance
("upload-endpoint teljesen elérhetetlen" flag KI állapotban) ezért a
**service-függvény szintjén** dől el: minden publikus
`media_upload_service.py`-belépési pont elsőként
`settings.community_media_enabled`-et ellenőrzi (a mező MÁR létezik,
`backend/app/config.py:83`, nem kell hozzáadni), és flag KI esetén
`MediaUploadDisabled` kivételt dob. A HTTP-router-bekötés egy KÉSŐBBI kör
tartozása — ugyanaz a minta, mint a Kör 12 óta `UnimplementedError`-t dobó
feed/post repository HTTP-integráció.

**D2 — nincs S3-SDK, és a `backend/requirements.txt` NINCS az
`allowed_paths`-on.** Mérve: a fájl kizárólag `fastapi`, `uvicorn`,
`SQLAlchemy`, `alembic`, `pydantic[-settings]`, `email-validator`, `PyJWT`,
`bcrypt`, `python-multipart`, `httpx`-et tartalmazza — nincs `boto3`, nincs
`minio`. Csomagtelepítés a kör alatt tilos (implementer-preambulum §4). A
"konkrét S3-kompatibilis adapter" ezért **kizárólag stdlibre (`hmac`,
`hashlib`, `urllib.parse`, `datetime`) és a MÁR jelenlévő `httpx`-re**
épülhet: az AWS SigV4 presigned-URL séma egy nyilvános, SDK nélkül
implementálható query-string aláírási algoritmus. A `test_media_upload.py`
egy in-memory fake `ObjectStore`-implementációt injektál a determinisztikus
finalize-cellákhoz (méret/checksum/expiry) — nem hív valódi hálózatot.
Részletek: `docs/adr/0410-media-upload-contract-and-object-store.md` D2.

**D3 — checksum algoritmus: SHA-256.** A projekt minden meglévő
content-hash helye (ADR 0090 asset store, signed-cursor HMAC) SHA-256-ot
használ — a média checksum mezője ugyanezt veszi át, nincs ok új
hash-family bevezetésére.

**D4 — `public UUID + bigint PK` minta.** `CommunityMedia` `id: BigInteger`
internal PK + `public_id: Uuid` (ADR 0396 §1 precedens) — a
finalize/cancel/ownership-ellenőrzés a `public_id`-n keresztül azonosít,
sosem a belső sorszámon.

**D5 — `MAX_UPLOAD_BYTES` modul-szintű konstans.** A `backend/app/config.py`
nincs az `allowed_paths`-on, tehát a küszöb egy `media_upload_service.py`-beli
konstans, nem `Settings`-mező (egy jövőbeli kör tehetné konfigurálhatóvá).

**Visszakeresés (ADR 0312, §4.9 kötelező):**
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "media
upload signed URL object store S3"` és `--corpus lessons,halts --top 5
"checksum ownership finalize upload validation server side"` — **nincs
közvetlenül releváns korábbi lecke vagy halt** erre a témára (ez az ELSŐ
objektumtár-integrációs kör a repóban). A legközelebbi releváns precedens
nem lecke, hanem élő kód-minta: az E08-R28 F1 MAJOR (wire-szerződés két fele
külön diffben szétcsúszhat még akkor is, ha ugyanaz a kör írja mindkettőt,
`HANDOFF.md` §6) — itt nem áll fenn ugyanígy, mert a Dart uploader csak a
backend ÁLTAL kiadott signed URL-t fogyasztja, nem önálló wire-kódolást
végez, de a finalize request/response alak Dart↔Python egyezését a review-nak
kézzel is meg kell néznie.

## 1. Cél

Feature flaggel védett, közvetlen objektumtáras és biztonságos médiafeltöltési pipeline ALAPJA — signed URL, ownership/checksum/MIME validáció, orphan cleanup.

## 2. Jelenlegi állapot — mért tények

- `communityMediaEnabled` (Kör 1) MA létezik, de semmi nem használja — ez a kör az első fogyasztója
- a projekt MA NEM rendelkezik objektumtár-integrációval — ez az ELSŐ S3-kompatibilis adapter a repóban, vendor-semleges interfésszel

## 3. Scope

**Benne van:** S3-kompatibilis object storage interfész, vendor-semleges adapter · media record: upload state, owner, MIME, size, duration, checksum, retention · upload intent + signed URL + finalize endpoint · rövid életű, content-length/content-type korlátozott signed URL · finalization: object existence, checksum, size, ownership ellenőrzés · orphan upload cleanup job + quota policy · lifecycle-aware, cancelálható, progress-mutató Flutter uploader.

**NINCS benne (tilos):**

- Média-feldolgozás (transcode, EXIF-strip, moderation) — Kör 19.
- Bármely poszt/komment médiacsatolásának UI-ja azon túl, hogy a flag mögött LÉTEZIK az uploader-komponens.
- `docs/adr/**` — az ADR 0407-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `backend/app/community/models/media.py` | ÚJ |
| `backend/app/community/services/media_upload_service.py` | ÚJ |
| `backend/app/community/storage/object_store.py` | ÚJ — vendor-semleges interfész + S3-adapter |
| `backend/alembic/versions/e09_r18_0012_community_media.py` | ÚJ |
| `lib/features/community/data/api/community_media_uploader.dart` | ÚJ |
| `backend/tests/community/test_media_upload.py` | ÚJ — a §6 cellái |
| `test/features/community/data/community_media_uploader_test.dart` | ÚJ |

**Tilos zóna:** `backend/app/community/models/post.py` (csak a media-referencia hozzáadása, nem a poszt-logika átírása) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0407)

### 5.1 A backend SOSEM tartja memóriában a teljes médiafájlt

A kliens KÖZVETLENÜL az objektumtárba tölt egy rövid életű, signed URL-lel — a backend csak az intent-et és a finalize-t kezeli.

**NEM elfogadható gyengítés:** egy "egyszerűbb" proxy-upload, ahol a fájl a FastAPI backendet körbejárva megy — ez a backend memóriáját/hálózatát terhelné, és a §12.4 SDD biztonsági alapelvét sértené.

### 5.2 A bucket private by default; a signed URL rövid életű és korlátozott

Content-length és content-type explicit korlátozás; a signed URL lejárata dokumentált, rövid ablak.

### 5.3 A finalization ellenőrzi az ownership-et, a checksumot és a méretet

Egy user nem finalizálhat egy másik user által kezdeményezett uploadot, és a szerver a tényleges objektum-metaadatot ellenőrzi, nem a kliens állítását fogadja el.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Feature flag KI állapotban az upload-endpoint teljesen elérhetetlen | `test_media_upload.py` |
| A2 | Signed URL lejárat után elutasított | `test_media_upload.py` |
| A3 | Rossz MIME-típus elutasítva (nem extension-alapú ellenőrzés) | `test_media_upload.py` |
| A4 | Méret-túllépés elutasítva | `test_media_upload.py` |
| A5 | Checksum-eltérés elutasítva a finalize-nál | `test_media_upload.py` |
| A6 | Idegen user nem finalizálhatja más uploadját | `test_media_upload.py` — ownership teszt |
| A7 | Cancel megszakítja az uploadot, és orphan-cleanup törli | `test_media_upload.py` + `community_media_uploader_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A média a FastAPI backenden keresztül, memóriában puffereltetve megy | A1 mellett architekturális sértés (§12.4), review-lelet |
| A signed URL lejárat után is elfogadott | A2 |
| A MIME-ellenőrzés a fájlkiterjesztésre támaszkodik | A3 |
| A finalize nem ellenőrzi a checksumot | A5 |
| Egy másik user `media_id`-jével bárki finalizálhat | A6 |

**A küszöb három kötelező cellája** (a médiafájl mérete a konfigurált `MAX_UPLOAD_BYTES`-hoz képest):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `size = MAX_UPLOAD_BYTES - 1` | elfogadva |
| **rajta** (a küszöbön) | `size == MAX_UPLOAD_BYTES` | elfogadva — a határ inkluzív (a limitig terjedő méret legitim) |
| a küszöb **fölött** | `size = MAX_UPLOAD_BYTES + 1` | elutasítva a finalize-nál, akkor is, ha a signed URL content-length ezt már korlátozta |

A hármas tömören: **alatt** → elfogad · **rajta** → elfogad · **fölött** → elutasít.

A határ `MAX_UPLOAD_BYTES` a záró, elfogadott érték — a finalize kétszer ellenőrzi (defense-in-depth a content-length fejléc mellett).

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a checksum-összehasonlítást a finalize endpointból, futtasd a backend pytest-et manipulált checksummal → az **A5** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/community/data/community_media_uploader_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
cd backend && python -m pytest tests/community/test_media_upload.py -q
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

1. `object_store.py` — vendor-semleges interfész + egy konkrét S3-kompatibilis adapter.
2. Migráció: `community_media` (owner, MIME, size, duration, checksum, state, retention).
3. `media_upload_service.py` — intent → signed URL → finalize, ownership/checksum/MIME/size ellenőrzéssel.
4. Orphan-upload cleanup job + quota policy.
5. `community_media_uploader.dart` — lifecycle-aware, cancelálható, progress.
6. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A proxy-upload memóriaterhelése.** Ha a fájl a backenden át megy, egy nagy feltöltés DoS-vektorrá válhat (A1 melletti architekturális kockázat).
- **Az extension-alapú MIME-ellenőrzés.** Egy átnevezett fájl könnyen megkerülné (A3) — ez a §12.4 kifejezett tiltása.
- **A checksum-ellenőrzés kihagyása.** Enélkül a finalize bármilyen objektumot elfogadna a kliens állítására hagyatkozva (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
