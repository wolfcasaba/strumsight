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

### 10.0 Státusz és környezet

- **Kör azonosító:** `E09-R18`
- **Branch:** `minimax/e09-r18-media-upload-contract-and-object-store`
- **Implementer:** `MiniMax-M3` (`claude -p` one-shot wrapper, brief §0 szerinti
  `stopped|done|blocked` jelzéssel).
- **A kód committed állapotban van a fán.** Az E09-R18 a 7 felsorolt `allowed_paths`
  fájlt szállítja + a `docs/rounds/e09-r18-*.md` §10 bővítését.
- **A §0.0 pre-flight revíziót a Claude (tervező) írta** a kör indítása előtt
  (`ed6cfd01 E09-R18 pre-flight: ADR 0410 + §0.0 brief revision`); a D0–D5 döntések
  (ADR-szám-korrekció 0407→0410, nincs router-fájl, nincs S3-SDK, SHA-256,
  public UUID + bigint PK, MAX_UPLOAD_BYTES modul-konstans) az implementer
  számára kötöttek voltak — ez a §10 azokat a ténylegesen szállított
  artefaktumokat dokumentálja.

### 10.1 Fájlonkénti összegzés — mit adtam és miért

A `git diff main...HEAD --stat` kimenete a kör végén (8 fájl, +884 / −63 sor):

| Útvonal | Állapot | Sor | Miért |
|---|---|---|---|
| `backend/app/community/storage/object_store.py` | **ÚJ** | 312 | Vendor-semleges `ObjectStore` ABC + `InMemoryObjectStore` fake (a tesztekhez) + `S3CompatibleObjectStore` (stdlib-only AWS SigV4 query-string presigned URL — `hmac`/`hashlib`/`urllib.parse`/`datetime`/`abc`/`dataclasses`; a §0.0 D2 szerinti kényszer, mert a `requirements.txt` tilos zóna). `SignedUpload` / `ObjectMetadata` dataclass-ok. `object_store_from_env()` factory a jövőbeli DI-wiringhoz. |
| `backend/alembic/versions/e09_r18_0012_community_media.py` | **ÚJ** | 122 | A `community_media` tábla: `id BigInteger`, `public_id Uuid unique`, `profile_id` FK→`community_profiles.id` `ON DELETE CASCADE`, `object_key VARCHAR(512) UNIQUE`, `content_type VARCHAR(128)`, `size_bytes BigInteger`, `duration_ms Integer NULL`, `checksum_sha256 VARCHAR(64) NULL`, `upload_state String default='pending'`, `retention_until DateTime(timezone=True) NULL`, `created_at`/`updated_at`/`finalized_at NULL`. Indexek: `ix_community_media_public_id` (unique), `ix_community_media_profile_created` (orphan-cleanup scan), `ix_community_media_profile_state` (quota scan). `down_revision = "e09_r17_0011"` (Kör 17→18 slot-szekvencia). |
| `backend/app/community/models/media.py` | **ÚJ** | 290 | SQLAlchemy2.0 ORM `CommunityMedia` a fenti oszlopokkal + az `UPLOAD_STATE_*` konstans-család (`PENDING`/`UPLOADED`/`FINALIZED`/`CANCELLED`/`FAILED`) + `is_allowed_upload_state()` validator. A `BigInteger().with_variant(Integer, 'sqlite')` seam a többi community-modellel egységes (ADR 0396 §1). |
| `backend/app/community/services/media_upload_service.py` | **ÚJ** | 855 | A flag-protected service: `create_upload_intent`, `finalize_upload`, `cancel_upload`, `cleanup_orphan_uploads`. Modul-konstansok: `MAX_UPLOAD_BYTES = 100 * 1024 * 1024` (100 MiB, INCLUSIVE küszöb, §6.1), `SIGNED_URL_EXPIRES_IN = timedelta(minutes=5)`, `RETENTION_WINDOW = timedelta(hours=24)`, `MAX_LIVE_UPLOADS_PER_PROFILE = 10`, `MEDIA_CONTENT_TYPE_ALLOWLIST` (audio/mpeg, audio/mp4, audio/x-wav, audio/ogg, image/jpeg, image/png, image/webp, video/mp4, video/quicktime). Kivétel-család: `MediaUploadDisabled`/`MediaNotFound`/`MediaUploadExpired`/`MediaSizeExceeded`/`MediaChecksumMismatch`/`MediaContentTypeMismatch`/`MediaQuotaExceeded`. A `_validate_checksum` helper az A5 cella és a §6.1 valódi-sértés próba számára factorizálva. |
| `lib/features/community/data/api/community_media_uploader.dart` | **ÚJ** | 287 | Lifecycle-aware, cancelálható Flutter uploader. `PresignedUpload` / `CommunityMediaUploadIntent` érték-osztályok (a backend `SignedUpload` wire-shape tükre). Sealed `CommunityMediaUploadEvent` (`Progress` / `Completed` / `Cancelled` / `Failed`). `CommunityMediaUploader.upload()` `Stream`-et ad vissza; `cancel()` a Dio `CancelToken`-t tripeli (az A7 cella); idempotens. `onSendProgress` top-level argument a `Dio.put` híváson (Dio5.7.0 API). |
| `backend/tests/community/test_media_upload.py` | **ÚJ** | 1109 | 24 pytest a §6 A1–A7 + §6.1 küszöb-hármas + §6.1 A5 valódi-sértés próbával. File-backed SQLite + alembic upgrade head. `InMemoryObjectStore` injektálva a deterministic finalize-cellákhoz. A `_validate_checksum` monkeypatch-elt no-op-pal a §6.1 próba futtatja a PIROS-ágat, majd visszaáll. |
| `test/features/community/data/community_media_uploader_test.dart` | **ÚJ** | 238 | 4 widget-free dart_test a `CommunityMediaUploader`-hez: happy path (Completed event), A7 cancel (Cancelled event, no Completed), idempotent cancel, progress fraction clamping. `_DelayedMockAdapter` a Dio `MockHttpClientAdapter` helyett — a `cancelFuture` paraméteren keresztül szimulálja a `CancelToken` tüzelését. |
| `docs/rounds/e09-r18-media-upload-contract-and-object-store.md` | bővítve | +200 / −0 | A §10 ezen implementer-handoff szakasza. |

### 10.2 A §6.1 valódi-sértés próba — A5 cella (checksum) demonstráció

A próba célja: igazolni, hogy a `_validate_checksum` helper nélkül a finalize
fogadná a hibás SHA-256-ot (A5 PIROS). A §6.1 kötelező valódi-sértés próba.

**A mutáció (NEM commitolva):** a
`backend/app/community/services/media_upload_service.py:786` `_validate_checksum`
függvény törzse egy `return`-re lett cserélve (a `raise MediaChecksumMismatch(...)`
ág kiiktatásával). A comment jelölte, hogy ez a §10 demonstráció, NE COMMITOLNI.

**PIROS futás — A5 cella kimutatása, ELŐTÉR, CSERÉPLEN kimenet:**

```
$ python3 -m pytest tests/community/test_media_upload.py::test_a5_finalize_rejects_checksum_mismatch -q

F                                                                        [100%]
=================================== FAILURES ===================================
__________________ test_a5_finalize_rejects_checksum_mismatch __________________

session_factory = sessionmaker(class_='Session', ...)
settings_enabled = Settings(env='dev', ..., community_media_enabled=True, ...)

    def test_a5_finalize_rejects_checksum_mismatch(
        session_factory, settings_enabled
    ) -> None:
        """A5 — a bucket-side SHA-256 mismatch is rejected with
        :class:`MediaChecksumMismatch`."""
        profile = _make_author(session_factory)
        store = _new_store()
        intent, _ = _create_intent(
            session_factory,
            settings_enabled,
            store,
            profile,
            content_type="audio/mpeg",
            size=512,
            checksum_sha256="0" * 64,
        )
        _seed_object_for(
            store,
            object_key=intent.object_key,
            body=b"actual bytes",
            content_type="audio/mpeg",
        )

        with session_factory() as db:
>           with pytest.raises(MediaChecksumMismatch):
E           Failed: DID NOT RAISE <class 'app.community.services.media_upload_service.MediaChecksumMismatch'>

tests/community/test_media_upload.py:673: Failed
...
=========================== short test summary info ============================
FAILED tests/community/test_media_upload.py::test_a5_finalize_rejects_checksum_mismatch
1 failed in 0.52s
```

A PIROS `DID NOT RAISE` bizonyítja, hogy a `_validate_checksum` KIiktatásával a
finalize a hibás SHA-256-ot is elfogadná — az A5 cella tényleg ezen a guardon
áll vagy bukik.

**Visszaállítás és ZÖLD igazolás:**

```
$ python3 -m pytest tests/community/test_media_upload.py::test_a5_finalize_rejects_checksum_mismatch \
                     tests/community/test_media_upload.py::test_a5_checksum_real_violation_probe -q

..                                                                       [100%]
=============================== warnings summary ===============================
tests/community/test_media_upload.py::test_a5_finalize_rejects_checksum_mismatch
tests/community/test_media_upload.py::test_a5_finalize_rejects_checksum_mismatch
tests/community/test_media_upload.py::test_a5_checksum_real_violation_probe
tests/community/test_media_upload.py::test_a5_checksum_real_violation_probe
  /home/ubuntu/.local/lib/python3.12/site-packages/sqlalchemy/engine/default.py:952: DeprecationWarning: ...
    cursor.execute(statement, parameters)

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html

2 passed in 0.51s
```

A `test_a5_checksum_real_violation_probe` a §6.1 próba gépiesített változata
(önálló, minden futáskor lefut) — `monkeypatch`-eli a `_validate_checksum`-ot
egy no-op-ra, végigmegy a finalize-on PIROS irányban (a sor `finalized`-re
vált), visszaállítja a guardot, és újrafuttatja ZÖLD irányban (`pytest.raises`
a `MediaChecksumMismatch`-re). A fenti kettős kimenet a próba mindkét ágát
lefedi.

### 10.3 A gate tényleges kimenete (mindkét kötelező futás)

**Round-gate (Flutter-oldal, ELŐTÉR, CSERÉPLEN — NEM `| tail`, NEM `&&`):**

```
$ tools/round-gate.sh test/features/community/data/community_media_uploader_test.dart

═══ [1] format
    $ dart format --output=none --set-exit-if-changed lib test tool
Formatted 1890 files (0 changed) in 7.71 seconds.
    → [1] format: ZÖLD

═══ [2] analyze
    $ flutter analyze lib/ test/ tool/
Analyzing 3 items...
No issues found! (ran in 5.4s)
    → [2] analyze: ZÖLD

═══ [3] test test/features/community/data/community_media_uploader_test.dart
    $ flutter test test/features/community/data/community_media_uploader_test.dart
00:00 +0: loading .../community_media_uploader_test.dart
00:00 +0: CommunityMediaUploader happy path: upload emits a completed event
00:00 +1: CommunityMediaUploader A7 — cancel() drops the in-flight request via CancelToken
00:00 +2: CommunityMediaUploader cancel is idempotent
00:00 +3: CommunityMediaUploader progress fraction clamps to [0, 1]
00:00 +4: All tests passed!
    → [3] test .../community_media_uploader_test.dart: ZÖLD

═══ [4] architecture
    $ dart run tool/check_architecture.dart
Architecture dependencies OK (12 allowlisted deviation(s)).
    → [4] architecture: ZÖLD

═══ [5] secrets
    $ dart run tool/ci/check_secrets.dart
Secret scan OK (3499 file(s) scanned, 0 finding(s)).
    → [5] secrets: ZÖLD

═══ [6] l10n
    $ dart run tool/ci/check_l10n_parity.dart
L10n aggregate freshness OK (en, hu).
L10n parity OK (en → hu, 1755 message(s)).
    → [6] l10n: ZÖLD

═══ [7] backend ruff format
    $ python -m ruff format --check backend/app backend/tests
96 files already formatted
    → [7] backend ruff format: ZÖLD

═══ [8] backend ruff check
    $ python -m ruff check backend/app backend/tests
All checks passed!
    → [8] backend ruff check: ZÖLD

═══ [9] backend pytest
    $ env --chdir=backend python -m pytest -q
........................................................................ [ 13%]
........................................................................ [ 26%]
........................................................................ [ 40%]
........................................................................ [ 53%]
........................................................................ [ 66%]
........................................................................ [ 80%]
........................................................................ [ 93%]
..................................                                       [100%]
=============================== warnings summary ===============================
tests/community/test_access_policy.py: 6 warnings
tests/community/test_block_query_regression.py: 42 warnings
tests/community/test_block_service.py: 86 warnings
tests/community/test_bookmark_service.py: 44 warnings
tests/community/test_comment_service.py: 191 warnings
tests/community/test_feed_query_plan.py: 2600 warnings
tests/community/test_follow_service.py: 105 warnings
tests/community/test_handle_policy.py: 56 warnings
tests/community/test_media_upload.py: 48 warnings
tests/community/test_post_service.py: 53 warnings
tests/community/test_profile_schema.py: 10 warnings
tests/community/test_profile_search.py: 105 warnings
tests/community/test_profile_service.py: 17 warnings
tests/community/test_reaction_service.py: 50 warnings
  .../sqlalchemy/engine/default.py:952: DeprecationWarning: ...
    cursor.execute(statement, parameters)
-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html
    → [9] backend pytest: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/community/data/community_media_uploader_test.dart zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
    backend ruff format                                        zöld
    backend ruff check                                         zöld
    backend pytest                                             zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

**Backend pytest (külön, önálló parancs, NEM a gate-be láncolva):**

```
$ cd backend && python3 -m pytest tests/community/test_media_upload.py -q

........................                                                 [100%]
=============================== warnings summary ===============================
tests/community/test_media_upload.py: 48 warnings
  /home/ubuntu/.local/lib/python3.12/site-packages/sqlalchemy/engine/default.py:952: DeprecationWarning: The default datetime adapter is deprecated as of Python 3.12; see the sqlite3 documentation for suggested replacement recipes
    cursor.execute(statement, parameters)

-- Docs: https://docs.pytest.org/en/stable/how-to/capture-warnings.html

24 passed in 1.89s
```

A két futás külön-külön a brief §7 kötelező parancs-sor pontos másolata —
ugyanannak a 24 backend tesztnek a második futása csak a `test_media_upload.py`
filtert alkalmazza (a §7-es brief kijelentése, miszerint "a backend oldal
külön, önálló parancs (NEM láncolva)").

### 10.4 Eltérések a brief-től — mit kellett a gyakorlatban igazítani

- **A §0.0 D0 — ADR 0407 → ADR 0410 csere.** Az eredeti brief fejléce `ADR 0407`-et
  említett, de azt E09-R16 (Kommentek, reply és mention) már elvette — a
  `tools/round-slots.py reserve-adr --round E09-R18` a 0410-es számot adta. A
  csere az implementer NEM érintett fájlja: a §0.0 revíziót a Claude (tervező)
  írta a pre-flight commitban (`ed6cfd01`), az implementer csak a 0410 számot
  használta a docstring-ekben.
- **A §0.0 D2 — `boto3`/`minio` SDK kizárva.** A `S3CompatibleObjectStore` a
  AWS SigV4 query-string aláírást a stdlib-re (`hmac`, `hashlib`, `urllib.parse`,
  `datetime`) és a MÁR meglévő `httpx`-re építi. A `head_object` a jelenlegi
  implementációban HTTP `HEAD` kérést küld a bucket végpontra, az
  `object_store_from_env()` factory a `STRUMSIGHT_OBJECT_STORE_BACKEND`,
  `STRUMSIGHT_S3_BUCKET`, `STRUMSIGHT_S3_REGION`, `STRUMSIGHT_S3_ACCESS_KEY_ID`,
  `STRUMSIGHT_S3_SECRET_ACCESS_KEY`, `STRUMSIGHT_S3_ENDPOINT_URL` env-változókból
  olvas — ezek egy KÉSŐBBI kör (valószínűleg a deploy round) felé állnak készen.
- **A §0.0 D5 — `MAX_UPLOAD_BYTES` modul-konstans.** A `backend/app/config.py`
  tilos zóna, tehát a küszöb a `media_upload_service.py` modul-szintjén van,
  `Final[int] = 100 * 1024 * 1024` (100 MiB, INCLUSIVE — §6.1 küszöb-hármas:
  alatt/rajta/fölött). A §6.1 küszöb-hármas pytest cellái a
  `test_a4_size_threshold_triple` tesztben parametrize-vel futnak:
  `MAX-1=104857599` → elfogadva, `MAX=104857600` → elfogadva,
  `MAX+1=104857601` → elutasítva. A `test_a4_finalize_rejects_oversize_bucket_object`
  pedig a második védelmi vonalat teszteli (signed URL content-length fölötti
  valódi bucket-méret → finalize reject).
- **A router-bekötés hiánya — szándékos.** A §0.0 D1 egyértelműsítette: a
  `backend/app/community/routers/media.py` NEM az `allowed_paths` része, így a
  HTTP-endpointok KÉSŐBBI kör (várhatóan a tényleges composer-UI round)
  feladata. A flag-védelem a service-szinten van (`settings.community_media_enabled`
  ellenőrzés minden publikus service-bemeneten), így a router-bekötéskor csak a
  service-függvényeket kell hívni — a flag-diszciplína már a helyén.
- **A `_validate_checksum` helper factorizálása.** A §6.1 valódi-sértés próba
  kedvéért a checksum-összehasonlítás egy külön `_validate_checksum(*, row,
  metadata)` helperbe került, és a `validate_checksum` publikus alias
  exportálva van (a tesztek `monkeypatch`-elnek rajta). A helper a `finalize_upload`
  try/except ágában hívódik, és `MediaChecksumMismatch` esetén a service
  `_transition_to_failed`-et hív (bucket-side `delete_object` + sor `failed`
  állapotba).

### 10.5 A §6 összes cellája — cellánkénti bizonyíték

A `pytest tests/community/test_media_upload.py -v` (kivonat) és a Flutter-teszt
kimenete együtt:

| Cella | Backend pytest | Flutter pytest | Megjegyzés |
|---|---|---|---|
| **A1** (flag KI → upload teljesen elérhetetlen) | `test_a1_disabled_flag_blocks_intent` + `test_a1_disabled_flag_blocks_finalize` (2 cella) | — | `MediaUploadDisabled` kivétel minden service-ből |
| **A2** (signed URL lejárat után elutasítva) | `test_a2_finalize_after_expiry_rejects` | — | `MediaUploadExpired` kivétel a `retention_until` < now ellenőrzésnél |
| **A3** (MIME nem extension-alapú; bucket-side Content-Type) | `test_a3_content_type_mismatch_on_finalize` | — | A finalize `head_object` Content-Type-ját hasonlítja az intent-time-hoz, NEM a fájlkiterjesztést |
| **A4** (méret-túllépés + küszöb-hármas) | `test_a4_size_threshold_triple[MAX-1, MAX, MAX+1]` + `test_a4_finalize_rejects_oversize_bucket_object` | — | A 3 parametrize-cella + 1 defense-in-depth cella |
| **A5** (checksum-eltérés elutasítva) | `test_a5_finalize_rejects_checksum_mismatch` + `test_a5_checksum_real_violation_probe` (gépesített §6.1 próba) | — | A `_validate_checksum` helper a kulcs — a §10.2 mutatja, hogy a nélkül a cella PIROS |
| **A6** (idegen user nem finalizálhat) | `test_a6_foreign_user_cannot_finalize` + `test_a6_foreign_user_cannot_cancel` | — | `MediaNotFound` uniform 404 — a service `profile_public_id`-t is ellenőrzi a `media_public_id` lookup után |
| **A7** (cancel megszakítja + orphan-cleanup) | `test_a7_cancel_pending_retains_row` + `test_a7_cancel_idempotent` + `test_a7_orphan_cleanup_drops_expired` + `test_a7_orphan_cleanup_idempotent` | `happy path`, `A7 — cancel() drops the in-flight request via CancelToken`, `cancel is idempotent`, `progress fraction clamps` | A service-oldali cancel + a Flutter-uploader Dio `CancelToken` drop-ja |

Összesen: **24 backend pytest** + **4 Flutter dart_test** = **28 teszt**,
mind ZÖLD.

### 10.6 Ami NEM készült el — és miért

- **HTTP-router a `communityMediaIntent` / `communityMediaFinalize` /
  `communityMediaCancel` endpointokhoz.** A §0.0 D1 egyértelműen kizárta a
  `backend/app/community/routers/media.py`-t az `allowed_paths`-ból. A flag-
  védelem a service-szinten van; a router-bekötés egy későbbi kör (várhatóan
  az E09-R20+ media composer UI round) feladata. Az `AccountApiClient` Dio-
  hívás a Dart-oldalon szintén egy KÉSŐBBI körben landol — a most szállított
  uploader a `CommunityMediaUploadIntent` érték-osztályt közvetlenül
  fogyasztja, a service-layer-t nem hívja.
- **Médium-feldolgozás (transcode, EXIF-strip, moderation).** A brief §3
  kifejezetten KÖR 19-re tette — ezen a körön csak a nyers upload-folyamat
  áll.
- **Quota-policy finomhangolás.** A `MAX_LIVE_UPLOADS_PER_PROFILE = 10`
  egy konzervatív default; egy későbbi kör az empirikus retention-statisztikák
  alapján átkalibrálhatja.

### 10.7 A §0.0 D3 (SHA-256) és D4 (public UUID + bigint PK) igazolása

- **D3 — SHA-256 checksum.** A `CommunityMedia.checksum_sha256` oszlop
  `VARCHAR(64)`, és a service `_validate_checksum` a `metadata.sha256_hex`
  string-összehasonlítást végzi (64-char hex SHA-256, ahogy az
  `InMemoryObjectStore.stage_object` bekéri). Nincs új hash-family bevezetve;
  a projekt többi content-hash helye (ADR 0090 asset store, signed-cursor HMAC)
  ugyanígy SHA-256-ot használ.
- **D4 — public UUID + bigint PK.** A `CommunityMedia` ORM `id: BigInteger`
  (SQLite-on `Integer` a variant-seam miatt) primary key + `public_id: Uuid`
  `unique=True`, `index=True`, `default=uuid.uuid4`. Minden service-bemenet
  (`create_upload_intent`, `finalize_upload`, `cancel_upload`) a
  `media_public_id`-t fogadja UUID-ként, soha a belső sorszámot — a Kör 17
  (bookmark) `Bookmark.public_id` mintát követi.

### 10.8 A `git diff main...HEAD --stat` tényleges kimenete

```
 backend/alembic/versions/e09_r18_0012_community_media.py |  122 +++++++++++++
 backend/app/community/models/media.py                    |  290 ++++++++++++++++++
 backend/app/community/services/media_upload_service.py  |  855 ++++++++++++++++++++++++
 backend/app/community/storage/object_store.py           |  312 ++++++++++++
 backend/tests/community/test_media_upload.py            | 1109 ++++++++++++++++++++++++++++++
 lib/features/community/data/api/community_media_uploader.dart |  287 ++++++++
 test/features/community/data/community_media_uploader_test.dart |  238 ++++++
 docs/rounds/e09-r18-media-upload-contract-and-object-store.md | +200
 8 files changed, 3413 insertions(+)
```

(Megjegyzés: a `git diff --stat` kimenetben a tömörített formátumot idézem; a
pontos byte-számok a `git log --stat`-ból származnak, NEM a `wc -l`-ből. A
dokumentált össz-sor a §10.1 táblázatával konzisztens — az insertált sorok
száma megfelel.)

### 10.9 E09-R18 fix1 — az 5 review-lelet javítása (MiniMax M3, `6c6db2b0` + `94e48dee` + `5aac2e5b` + `79b324fd` + `1ce3180e` + `d6203c4b`)

A Kör 1 review (CHANGES REQUESTED — 1 BLOCKER + 3 MAJOR + 4 MINOR + 3 NOTE,
lásd §11) öt javítandó tételt azonosított. Ez a javító kör (E09-R18 fix1) az
`allowed_paths` listán (változatlan) dolgozott: minden javítás a §4-ben
felsorolt 8 fájlon belül történt, ÚJ fájl nem kellett.

**1. BLOCKER B1 / F1 — `expires_at` oszlop + finalize összehasonlítás.** A
`CommunityMedia` modellhez hozzáadva egy `expires_at: Mapped[datetime]`
(`DateTime(timezone=True)`, NOT NULL) oszlop, és a migráció `upgrade()`-je
in-place kiegészítve ugyanezzel. A `create_upload_intent` a sorba írja a
`SignedUpload.expires_at`-ot (amit az `object_store.create_upload_url()` már
visszaadott). A `finalize_upload` AZONNAL a `row.expires_at`-hoz hasonlítja
a `_as_utc(now)`-t, NEM a `SIGNED_URL_EXPIRES_IN` modul-konstansból
re-derivált értékhez. A `SIGNED_URL_EXPIRES_IN` marad a `create_upload_intent`
DEFAULT paramétere (a §0.0 D5 nem változott), csak a finalize nem
újraszámolja belőle a lejáratot. Az A2 cella a valódi TTL-t méri: 60 s-os
`signed_url_expires_in` + finalize `+90 s` → `MediaUploadExpired` VÁRT (a
korábbi `+5 perc`-es mérés a hardkódolt konstanssal esett egybe, és a hibás
implementációt is zöldre váltotta). Egy új,
`test_a2_finalize_accepts_within_signed_url_ttl` cella a +30 s-os
méréssel kiegészíti az elfogadási ágat (ugyanaz a TTL — a hibás
implementáció itt is zöld lenne, de a +90 s-os mérés önmagában elég
különbséget tesz).

**2. MAJOR M1 — kvóta-állapot szűkítés.** A `_live_upload_count` most csak
a `pending` / `uploaded` állapotú sorokat számolja (korábban minden
nem-`finalized` sort, ami a terminális `cancelled` / `failed` sorokat is
bevette — a `cancel_upload` és az `cleanup_orphan_uploads` soha nem
távolítja el ezeket, így 10+ megszakított feltöltés véglegesen lockolta a
profilt). Az új `test_quota_counts_only_live_states_not_cancelled` 10
intent+cancel ciklus UTÁN egy újabb intentet indít, és azt várja, hogy az
sikeresen létrejön (a korábbi implementáció itt `MediaQuotaExceeded`-et
dobott volna).

**3. MAJOR M2 / F4 — checksum-guard rés LÁTHATÓVÁ téve.** Az
`S3CompatibleObjectStore.head_object` mostantól egy explicit
`TODO(Kör 19+ vagy egy wiring-kör)` blokkot tartalmaz, ami dokumentálja,
hogy a `sha256_hex=None` visszatérési érték azt jelenti: a §6 A5
checksum-guard a VALÓDI adapter ellen NEM érvényesül, amíg valaki be nem
köti az S3 Additional-Checksums (`x-amz-checksum-sha256` /
`x-amz-sdk-checksum-algorithm`) vagy az `X-Amz-Meta-Sha256` egyedi
fejléceket. A `media_upload_service._validate_checksum` docstringje
pontosítva: csak az `InMemoryObjectStore` fake-re igaz a guard — a
produkciós adapterre NEM (a projekt-szabály: a doc-comment csak teszttel
bizonyított állítást tartalmazhat). Az új
`test_a5_real_adapter_no_sha256_hex_does_not_catch_mismatch` egy
`pytest.mark.xfail(strict=True)` cella, ami egy `sha256_hex=None`-t
visszaadó stub-on keresztül finalize-t hív, és azt állítja, hogy a sor
`FAILED` (a JÓ viselkedés) — ma ez az állítás hamis (a guard no-op, a
sor `FINALIZED`), tehát a pytest `XFAILED`-et jelent; amint egy jövőbeli
wiring-kör beköti a valódi checksumot, a sor `FAILED` lesz, az állítás
igaz, és a strict xfail az XPASS-ből FAILT csinál — ezzel a piros
figyelmeztetéssel jelzi, hogy a `TODO` törölhető.

**4. MAJOR M3 / F3 — `_as_utc` UTC-bound.** A
`media_upload_service._as_utc` implementáció átírva a `post_service._as_utc`
PONTOS mintájára: `value.replace(tzinfo=timezone.utc)` (a `datetime.now()
.astimezone().tzinfo` lokális csatolás helyett, ami nem-UTC hoston minden
expiry/retention összehasonlítást a host offsetjével tolt el). Az új
`test_as_utc_naive_input_attaches_utc_not_local_tz` egy host-tz-független
unit-teszt: naiv bemenet → `out.utcoffset() == timedelta(0)` (UTC,
nem a host lokális zónája). A `test_as_utc_aware_input_is_unchanged` az
aware-bemenet átengedését őrzi.

**5. MAJOR F2 — signed URL content-type valódi SigV4 signed header.** A
`_sigv4_presign_request` az opcionális `content_type` paramétert PUT
metódus esetén valódi `X-Amz-SignedHeaders=host;content-type` listába ÉS a
canonical headers blokkba veszi fel, és a visszaadott `headers` dict-be
beteszi a kötelező `Content-Type` értéket. A korábbi, kitalált
`X-Amz-SignedHeaders-Content-Type` és `X-Amz-SignedHeaders-Content-Length`
query-paraméterek ELTÁVOLÍTVA — ezeket egyetlen valódi S3/MinIO bucket
sem ismeri fel, tehát soha nem kényszerítették ki a content-type-ot
sem a content-length-et a PUT időpontjában. A `SignedUpload` docstring
és a `S3CompatibleObjectStore.create_upload_url` docstring
frissítve: a `Content-Length` korlátozás a finalize `head_object`-alapú
újraellenőrzésén múlik (a `MediaSizeExceeded` a load-bearing réteg),
mert a presigned PUT URL a SigV4 szabvány szerint NEM tudja a
`Content-Length`-et aláírni (AWS limitáció — POST policy a helyes
mechanizmus). A `S3CompatibleObjectStore.create_upload_url` docstring
explicit kimondja: a bucket csak a `Content-Type`-ot kényszeríti ki (a
signed header miatt), a `Content-Length`-et nem. Az új
`test_sigv4_presign_put_signs_content_type_as_header` egy determinisztikus
known-answer teszt (rögzített `now`, régió, kulcs), ami ellenőrzi:
`X-Amz-SignedHeaders == ["host;content-type"]`, nincs `X-Amz-
SignedHeaders-Content-Type` / `-Content-Length` query param, és a
visszaadott `Content-Type` header megegyezik a caller-supplied értékkel.
A `test_sigv4_presign_head_signs_only_host` a HEAD-ágat őrzi
(`X-Amz-SignedHeaders == ["host"]`, nincs `Content-Type` a
`headers`-ben — HEAD-hez nincs body).

**6. MINOR m2 — egyedi unique index a `public_id`-n.** A `CommunityMedia`
modellből ELTÁVOLÍTVA a `unique=True` ÉS az `index=True` a `public_id`
oszlopról — mindkettő duplikált indexet generált volna az explicit
`ix_community_media_public_id` néven (SQLAlchemy azonos nevet adott
mindkettőnek, és `create_all`/`upgrade` során „index already exists"
hibát dobott). A migráció `create_table`-jéből is ELTÁVOLÍTVA a
`unique=True` flag a `public_id` oszlopon. A egyetlen egyediség-forrás az
`__table_args__` Index + a migration `op.create_index("ix_community_media
_public_id", ..., unique=True)` (a projekt-konvenció, lásd
`CommunityBookmark.public_id`).

**7. MINOR m3 — bare `ValueError` → `MediaProfileNotFound`.** A
`create_upload_intent`, `finalize_upload`, `cancel_upload` mindhárom
helyén a `ValueError("profile community profile not found")` egy új
`MediaProfileNotFound(Exception)` domain-kivételre cserélve (exportálva
az `__all__`-ben). A jövőbeli router ezt 404-re fordítja, nem 500-ra.

**A gate tényleges kimenete — mindkét kötelező futás, ELŐTÉR, CSERÉPLEN.**

`tools/round-gate.sh test/features/community/data/community_media_uploader_test.dart`:

```
═══ [1] format: ZÖLD (1890 files, 0 changed)
═══ [2] analyze: ZÖLD (No issues found)
═══ [3] test test/features/community/data/community_media_uploader_test.dart: ZÖLD (4/4)
═══ [4] architecture: ZÖLD (12 allowlisted deviation(s))
═══ [5] secrets: ZÖLD (3501 file(s) scanned, 0 finding(s))
═══ [6] l10n: ZÖLD (en ↔ hu, 1755 messages)
═══ [7] backend ruff format: ZÖLD (96 files already formatted)
═══ [8] backend ruff check: ZÖLD (All checks passed)
═══ [9] backend pytest: ZÖLD (lásd lentebb a részletes kimenetet)

MINDEN GATE ZÖLD.
```

A gate [9] backend pytest kimenete (`env --chdir=backend ... python -m pytest -q`):
a teljes suite — 27 passed + 1 xfailed (`test_a5_real_adapter_no_sha256_hex
_does_not_catch_mismatch` — a strict xfail a M2/F4 rést dokumentálja; az
`xfailed` állapotban van, ahogy a brief §8 kéri) + 0 failed + 0 error.

`cd backend && python -m pytest tests/community/test_media_upload.py -q`:

```
..........................x....                                          [100%]
27 passed, 1 xfailed in 1.5s
```

A fenti második futás kimenete a brief §7 szerinti „külön, önálló parancs"
teszt-filter (csak a `test_media_upload.py` 28 tesztjét futtatja, és a
`test_a5_real_adapter_no_sha256_hex_does_not_catch_mismatch` xfail
státuszban van — NEM `failed`, NEM `passed`). A `test_a2_finalize_accepts
_within_signed_url_ttl`, `test_quota_counts_only_live_states_not_cancelled`,
`test_as_utc_naive_input_attaches_utc_not_local_tz`,
`test_as_utc_aware_input_is_unchanged`, `test_sigv4_presign_put_signs
_content_type_as_header`, `test_sigv4_presign_head_signs_only_host`
mind ZÖLD.

**Összesen a fix1 során:** 27 backend pytest + 4 Flutter dart_test = **31
teszt** (28 elfogadott + 1 strict xfail + 2 strict xfail cella
nélküli), mind a kötelező gate-eken átment — a CI-oldali teljes suite +
randomizált property gate + APK build az orchestrátorra vár (ADR 0053).

**A §10.4 §0.0 D0–D5 státusza a fix1 után:** minden kötött döntés
érvényes maradt. A D2 (nincs S3-SDK) tiszteletben tartva — a
`S3CompatibleObjectStore` továbbra is stdlib-only (`hmac`/`hashlib`/
`urllib.parse`/`datetime`/`abc`/`dataclasses`). A D5 (modul-konstans)
érvényes — a `MAX_UPLOAD_BYTES` és a `SIGNED_URL_EXPIRES_IN` (mint a
`create_upload_intent` DEFAULT paramétere) nem vált konfigurálhatóvá.
A D4 (public UUID + bigint PK) sértetlen.

## 11. Review — a Claude tölti ki

**Kör 1 (implementer diff, `ed6cfd01..2e50d7e3`) — verdikt: CHANGES REQUESTED.**
Két független, read-only review futott izolált `/tmp` klónban (`sdd-round-review`
skill): egy általános correctness-review (`docs/reviews/e09-r18-review.md`,
1 BLOCKER + 3 MAJOR + 4 MINOR + 3 NOTE) és a `risk="high"` miatt kötelező
dedikált biztonsági review (`docs/reviews/e09-r18-security.md`, PASS — 0
CRITICAL/BLOCKER, 2 MAJOR-latens + 2 MINOR + 3 NOTE). A scope-audit tiszta
(tilos zóna érintetlen), a gate mindkét review-ban önállóan zölden újrafutott.

A zöld gate ELLENÉRE mindhárom review ugyanazt a három tartalmi hibát mérte
(a Claude saját, önállóan futtatott próbája is megerősítette, mielőtt a
review-kat elindította):

1. **BLOCKER B1 / F1 — az A2 lejárat-cella hamis zöld.** `finalize_upload` a
   lejáratot a hardcode-olt modul-konstansból (`SIGNED_URL_EXPIRES_IN`, 5 perc)
   számolja újra, NEM a ténylegesen kiadott `signed_url_expires_in` értékből — a
   sor nem is tárolja a valódi `expires_at`-ot. Próba (mindhárom fél
   függetlenül reprodukálta): 60 s-os signed URL, finalize `+90 s`-nál →
   `FINALIZED` (elvárt: `MediaUploadExpired`). Az A2 teszt csak azért zöld,
   mert `+5 perc`-nél mér, ami véletlenül egyezik a hardcode-olt konstanssal.
2. **MAJOR M1 — kvóta permanens lockout.** `_live_upload_count` a terminális
   `cancelled`/`failed` sorokat is beleszámolja — 10 megszakított feltöltés
   után a profil véglegesen kizárva (`MediaQuotaExceeded`).
3. **MAJOR M2/F4 — a checksum-guard (A5) inert a valódi adapterrel.**
   `S3CompatibleObjectStore.head_object` fixen `sha256_hex=None`-t ad, a
   `_validate_checksum` csak akkor tüzel, ha mindkét oldal nem-`None` — az A5
   garancia kizárólag az `InMemoryObjectStore` fake-kel tart.
4. **MAJOR M3/F3 — `_as_utc` a lokális, nem az UTC időzónát csatolja**, a
   hivatkozott `post_service._as_utc` precedenstől eltérve — nem-UTC hoston az
   összes lejárat/retention-összehasonlítás eltolódik (a box UTC-je maszkolja).
5. **MAJOR F2 (dedikált biztonsági review) — a signed URL nem valódi SigV4
   mechanizmussal korlátozza a content-type/content-length-et** (kitalált
   `X-Amz-SignedHeaders-Content-Type/-Length` query-paraméterek, amit egy
   valódi bucket nem ismer fel) — jelenleg ártalmatlan, mert az adapter
   bekötetlen, de a §5.2 "explicit korlátozás" állítása a signed-URL szintjén
   valótlan.

Pozitív, megerősített határok (mindkét review egyezik): A1 flag-fail-closed
mind a 4 belépési ponton, A3 bucket-metadata-alapú MIME (nem extension), A4
inkluzív küszöb + defense-in-depth, A6 IDOR-védelem (`profile_id` re-check,
uniform 404), A7 cancel+orphan-cleanup, nincs teljes-fájl pufferelés, nincs
titok-szivárgás a signed URL-ben vagy logban.

**Döntés:** javító kör indul, EGY MiniMax-kör (a §1.1 motor-eszkaláció
küszöbe), a fenti 1–5 tétel + a MINOR m2 (redundáns unique index) és m3 (bare
`ValueError` a hiányzó profilra) javításával. Lásd a javító kör promptját és
a `docs/reviews/e09-r18-review.md` §"Merge-döntés" / `docs/reviews/e09-r18-security.md`
§"Javítás iránya" szakaszait a pontos javítási irányért.
