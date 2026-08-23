# E09-R18 — Biztonsági review (dedikált, READ-ONLY)

Reviewer: Claude (security-reviewer) · Dátum: 2026-08-23 · Kockázat: high
Diff: `git diff ed6cfd01..2e50d7e3` · HEAD `2e50d7e3` (izolált klón `/tmp/review-e09-r18`)

## Verdikt

**PASS** — nincs merge-blokkoló (CRITICAL/BLOCKER) lelet.
CRITICAL: 0 · BLOCKER: 0 · **MAJOR: 2 (mindkettő latens)** · MINOR: 2 · NOTE: 3.

A kör az objektumtár-pipeline ALAPJA: nincs HTTP-router (§0.0 D1, szándékos),
az `S3CompatibleObjectStore` bekötetlen, a szolgáltatás minden acceptance-cellát
az injektált `InMemoryObjectStore` fake-en keresztül mér. Ezért egyik lelet sem
él egy szállított úton — **de a két MAJOR a signed-URL biztonsági rétegének
tényleges (nem csak dokumentált) érvényesítését érinti, és a router-bekötő KÖR
ELŐTT javítandó**, mert ott válnak élővé. A merge-osztályozás szerint a MAJOR nem
határsértés, ezért nem tiltja a merge-öt, de a fix nem halasztható a wiring
utánra.

Az IDOR-, MIME-, méret-, checksum- és flag-fail-closed határokat a kód
ténylegesen tartja (lásd „Pozitív bizonyíték").

---

## Leletek

### F1 / MAJOR (latens) — a finalize lejárat-újraellenőrzés a kiadott signed-URL ablakot figyelmen kívül hagyja

**Fájl:** `backend/app/community/services/media_upload_service.py:566-574` (és a
hiányzó `expires_at` oszlop a migrációban).

A finalize a lejáratot így számolja:
```python
expires_at = row.created_at + (SIGNED_URL_EXPIRES_IN)  # modul-konstans, 5 perc
```
A `finalize_upload` NEM fogad `signed_url_expires_in` paramétert, és a sornak
NINCS tárolt `expires_at`/`expires_in` mezője. A kiadott URL tényleges ablaka
(`create_upload_intent(signed_url_expires_in=...)`, ami az `intent.signed_upload.
expires_at`-be be is épül) elveszik; a szerveroldali „defense-in-depth" újra-
ellenőrzés a hardkódolt 5 perces konstansból re-derivál. A docstring (561-573.
sor) azt állítja, hogy „a caller-supplied `signed_url_expires_in` paramétert
használja" — ez a kódban nem igaz.

**Failure scenario (REPRODUKÁLT):** intent 60 s-os signed URL-lel
(`signed_url_expires_in=timedelta(seconds=60)`), az objektum feltöltve, finalize
`now = created_at + 90 s` időpontban (30 s-mal a URL lejárta UTÁN). Elvárt:
`MediaUploadExpired`. **Mért:** a sor `FINALIZED` állapotba kerül — a lejárt
signed URL uploadja elfogadva. (Ideiglenes teszt a `tests/community/`-ben, a
gyári fixtúrákkal; a repro `assert row.upload_state == UPLOAD_STATE_FINALIZED`
zölden futott le.)

Az `A2` cella (`test_a2_finalize_rejects_expired_signed_url`) csak azért zöld,
mert a `later`-t pont `created_at + 5 perc`-re állítja: a hardkódolt default
határon való egybeesés adja a zöldet, nem a 60 s-os ablak érvényesítése — hamis
biztonságérzet.

**Sértett szabály:** brief §5.2 / A2 („a signed URL lejárata dokumentált, rövid
ablak … a szerver a finalize-nál újra-ellenőrzi").

**Javítás iránya:** tárold a kiadott `expires_at`-et a `community_media` soron
(új oszlop), és a finalize e tárolt abszolút időbélyegen mérjen
(`now >= row.expires_at`), ne egy modul-konstansból re-deriváljon. Az A2 tesztet
állítsd a valódi ablakra (`later = created_at + 90 s` a 60 s-os intentnél → RED
a mai kóddal).

---

### F2 / MAJOR (latens) — a signed URL nem érvényesíti a content-type / content-length korlátot (kitalált query-paraméterek)

**Fájl:** `backend/app/community/storage/object_store.py:513-518`.

A presign a content-type és content-length korlátot kitalált,
nem-szabványos query-paraméterként fűzi a signed URL-be:
```python
params["X-Amz-SignedHeaders-Content-Type"] = content_type
params["X-Amz-SignedHeaders-Content-Length"] = str(max_content_length)
```
Ilyen SigV4 mechanizmus nincs. Az AWS/MinIO a content-type-ot csak akkor
kényszeríti ki, ha az `Content-Type` **aláírt HEADER** (a `X-Amz-SignedHeaders`
listában és canonical headers-ben szerepel), a content-length-et presigned PUT
URL egyáltalán nem korlátozza (arra a POST policy való). Egy `X-Amz-SignedHeaders-
Content-Type` nevű extra aláírt query-param a bucket számára csak egy ismeretlen
`X-Amz-*` paraméter — nem eredményez semmilyen kényszerítést. A kommentek
(„the bucket enforces them at PUT time", 458-459/514-518. sor) tévesek.

**Failure scenario:** egy érvényes presigned PUT URL birtokában a kliens tetszőleges
`Content-Type`-pal és tetszőleges méretben (a bucket saját limitjéig) tölthet fel;
a §5.2 által előírt „content-length és content-type explicit korlátozás" a signed
URL szintjén NEM valósul meg. Élő úton nem exploitálható, mert az adapter
bekötetlen — ezért latens.

**Kompenzáló kontroll:** a `finalize_upload` a `head_object`-ből újraolvassa és
ellenőrzi a content-type-ot (597-607.) és a méretet (612.), így a hibás upload a
finalize-nál elbukik — de az „első védelmi vonal" (signed-URL korlát) illuzórikus,
és a §5.2/§6.1 defense-in-depth egyik rétege hiányzik.

**Sértett szabály:** brief §5.2, ADR 0410.

**Javítás iránya:** a content-type-ot valódi aláírt headerként vidd be
(`X-Amz-SignedHeaders=content-type;host` + canonical header), vagy dokumentáld
explicit módon, hogy a signed-URL nem korlátoz és a finalize head_object az
EGYETLEN kényszerítő réteg (a méret-cap intent-oldali `size`-hoz kötése is
ilyenkor pontosítandó — ma a finalize csak `MAX_UPLOAD_BYTES`-hoz mér, nem a
deklarált mérethez).

---

### F3 / MINOR (latens) — `_as_utc` a szerver LOKÁLIS időzónáját csatolja, nem UTC-t

**Fájl:** `backend/app/community/services/media_upload_service.py:346-347`.
```python
if value.tzinfo is None:
    return value.replace(tzinfo=datetime.now().astimezone().tzinfo)
```
A docstring „re-attach `timezone.utc`"-t ígér, de a kód a szerver lokális
tz-jét csatolja — **eltérés a hivatkozott precedenstől** (`post_service._as_utc`
`datetime.UTC`-t csatol, `post_service.py:162-168`). SQLite-ról a naiv, UTC-ként
tárolt `created_at` így lokális offszettel kap tzinfo-t.

**Failure scenario:** negatív offszetű (pl. UTC−5) szerveren az `expires_at`
abszolút pillanata 5 órával KÉSŐBBRE tolódik → lejárt signed URL-ek órákig
elfogadva a finalize-nál (F1-et súlyosbítja). Pozitív offszeten fordítva, valid
uploadok korai elutasítása. UTC szerveren (jelen box, tipikus prod) no-op.

**Javítás iránya:** másold a `post_service._as_utc` mintát (`datetime.UTC`).

---

### F4 / MINOR (latens) — a checksum-védelem inert a szállított S3-adapterrel

**Fájl:** `backend/app/community/storage/object_store.py:362`
(`sha256_hex=None`) + `media_upload_service.py:796-800`.

A `_validate_checksum` csak akkor tüzel, ha `row.checksum_sha256` ÉS
`metadata.sha256_hex` is nem-None. Az `S3CompatibleObjectStore.head_object`
MINDIG `sha256_hex=None`-t ad (a custom `X-Amz-Meta-Sha256` header kiolvasása egy
jövőbeli kör dolga). Így a produkciós adapterrel az A5 checksum-guard SOHA nem
fut — a védelmet kizárólag az `InMemoryObjectStore` fake tölti fel.

**Failure scenario:** a bucketbe tett objektum tartalma eltér a kliens által
deklarált SHA-256-tól; a valós adapteren a finalize checksum-ellenőrzés kimarad,
a sor `FINALIZED` lesz — a §6 A5 garancia a valós úton nem érvényesül.

**Javítás iránya:** a wiring-kör kösse be a bucket-oldali SHA-256 kiolvasását, és
adjon hozzá egy tesztet, ami a valós adapter head_object-jén méri az A5-öt; addig
dokumentáld, hogy az A5 fake-only.

---

### F5 / NOTE — a tényleges objektum-méret nem kerül vissza a sorra

`media_upload_service.py:612` — a finalize a `metadata.size`-t csak
`MAX_UPLOAD_BYTES`-hoz méri, de sem a deklarált `row.size_bytes`-hoz nem
hasonlítja, sem a valós méretet nem írja vissza a sorba. A DB a kliens által
állított méretet őrzi, ami eltérhet a bucketben tárolttól (adat-integritás, nem
határsértés). Javítás: `row.size_bytes = metadata.size` a sikeres finalize-nál,
és/vagy egyeztetés a deklarált mérettel.

### F6 / NOTE — env-változónevek eltérése

`object_store_from_env` a `STRUMSIGHT_OBJECT_STORE_ENDPOINT/BUCKET/REGION/
ACCESS_KEY/SECRET_KEY` neveket olvassa (`object_store.py:592-596`), a handoff
§10.4 viszont `STRUMSIGHT_S3_*`-t dokumentál. Bekötetlen; a wiring-kör előtt
egységesítendő, nehogy a titkot rossz név alá tegyék (nem szivárgás, dokumentum-
konzisztencia).

### F7 / NOTE — a Dart uploader a DioException-t `cause`-ként továbbadja

`lib/features/community/data/api/community_media_uploader.dart:262-265` — a
`CommunityMediaUploadFailed.cause` a `DioException`, ami a `requestOptions.uri`-n
keresztül a teljes signed URL-t hordozza (aláírás, de NEM a signing secret). A
fájl maga nem naplóz (nincs `print`/logger hívás); a NOTE a fogyasztónak szól:
a `cause`-t ne logolja crash-report/analytics szintre. A `objectKey` doc-comment
„logged for crash-report correlation only" — tényleges log-hívás nincs, de a
jövőbeli fogyasztónak redakció kell.

---

## Pozitív bizonyíték (végignézett határok, amelyek TARTANAK)

- **IDOR finalize/cancel (§5.3/A6):** mindkét út a `public_id`-lookup UTÁN
  ténylegesen ellenőrzi `row.profile_id != profile.id` → uniform `MediaNotFound`
  (`media_upload_service.py:545-548`, `686-688`). Nem-létező, idegen-tulajdonú,
  cancelled/failed és nem-finalizált mind ugyanarra a 404-re esik → nincs
  létezés-enumeráció. Belső `id` sosem hagyja el a szolgáltatást; azonosítás
  végig `public_id` (UUIDv4).
- **Szerveroldali re-validáció, nem kliens-bizalom (§5.3):** a `finalize_upload`
  aláírása (`476-485`) csak `media_public_id`-t fogad — NINCS kliens-oldali
  size/checksum/content-type body; minden érték a `head_object`-ből jön.
- **MIME nem extension-alapú (A3):** a `metadata.content_type`-ot méri az
  allowlist ellen ÉS az intent-deklaráció ellen (`597-607`); tesztek: bucket-MIME
  mismatch + non-allowlisted bucket-MIME + intent-seam.
- **Méret-küszöb inkluzív (A4/§6.1):** `size > MAX_UPLOAD_BYTES` reject
  (intent `412`, finalize `612`) → `MAX-1`/`MAX` elfogad, `MAX+1` elutasít; a
  parametrizált teszt-hármas fedi.
- **Nincs teljes-fájl pufferelés a backendben (§5.1):** a szolgáltatás sehol nem
  olvassa az objektum bájtjait; direkt-to-store minta, a backend csak intent +
  finalize metaadatot kezel.
- **Checksum teljes-digest egyenlőség (A5):** `_validate_checksum` teljes 64-char
  hex SHA-256 `!=` összehasonlítás (`796-804`), nincs csonkítás; a §6.1 valódi-
  sértés próba gépesített cellája (`test_a5_checksum_real_violation_probe`) él.
  (A valós adapteren F4 miatt inert.)
- **Orphan-cleanup biztonság (A7):** flag-gated (`742-743`, KI → `return 0`,
  side-effect nélkül — `test_a1_orphan_cleanup_is_noop_when_flag_off`); csak
  `pending`/`uploaded` + lejárt `retention_until` sorokat söpör, `finalized`-et
  soha; nem hívható authentikálatlanul (nincs router ebben a körben).
- **Feature-flag fail-closed (A1):** mind a 4 publikus belépési pont ELSŐKÉNT a
  `settings.community_media_enabled`-et nézi; az A1 mind a 4-et fedi (intent/
  finalize/cancel `MediaUploadDisabled`, cleanup `return 0`).
- **Migráció (§addititív):** kizárólag ÚJ `community_media` tábla; FK →
  `community_profiles.id` `ON DELETE CASCADE`, `object_key` UNIQUE, `public_id`
  unique index + két scan-index; nincs destruktív művelet meglévő táblán.
- **Titok-szivárgás:** a signing secret sosem kerül a URL-be (csak signature +
  access_key_id/credential, ez a presigned-URL szabványos alakja) vagy logba;
  `check_secrets` gate zöld (0 finding, 3499 fájl).

## Reprodukció

Az F1 latens elfogadást egy eldobható pytest bizonyította a gyári fixtúrákon
(60 s intent + finalize `+90 s` → `FINALIZED`). A klón nem módosult (a repro
fájl törölve). A többi lelet kód-olvasásból + a precedens (`post_service._as_utc`)
összevetéséből.
