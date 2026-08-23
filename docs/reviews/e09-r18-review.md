# Review-jelentés — E09-R18 (Média upload contract és objektumtár integráció)

- **Kör:** E09-R18 — ADR 0410
- **Diff-tartomány:** `ed6cfd01..2e50d7e3`
- **Ellenőr:** Claude (Opus), független READ-ONLY review izolált klónban (`/tmp/review-e09-r18`)
- **Verdikt:** **CHANGES REQUESTED**
- **Összegzés:** 1 BLOCKER · 3 MAJOR · 4 MINOR · 3 NOTE

A kör mind a 8 fájlt a `allowed_paths`-on belül szállította, a tilos zóna
érintetlen, a gate zöld (24 backend pytest + 4 Flutter dart_test lokálisan is
lefut nálam). Az architekturális döntések (D1–D5) formálisan teljesülnek. A
zöld suite azonban **két olyan biztonsági guardot fed el, amelyek a valós
futásban nem tartanak** — az A2 (lejárat) és az A5 (checksum a valódi
objektumtár ellen) — plus egy availability-bug (quota permanent lockout).

---

## Scope / tilos zóna — PASS

`git diff ed6cfd01..2e50d7e3 --stat` a tilos zónára (`models/post.py`,
`routers/**`, `main.py`, `conftest.py`, `requirements.txt`, `docs/adr/`) **üres**.
Az ADR 0410 a bázis-commitban (`ed6cfd01`, pre-flight) van, nem a diffben — helyes.
`object_store.py` nem importál `boto3`/`minio`-t (csak comment-említés) — D2 PASS.
SHA-256 (D3), public UUID + bigint PK (D4), `MAX_UPLOAD_BYTES` modul-konstans (D5) — PASS.

---

## BLOCKER

### B1 — Az A2 lejárat-ellenőrzés NEM a tényleges signed-URL TTL-t validálja (hamis zöld)

`finalize_upload` a lejáratot a modul-szintű **hardcode-olt** `SIGNED_URL_EXPIRES_IN`
(5 perc) konstansból számolja újra, nem az intent-kor ténylegesen használt
`signed_url_expires_in` értékből — a `finalize_upload` szignatúrájában
**nincs is `signed_url_expires_in` paraméter** (`media_upload_service.py:476-485`),
és a sor sosem perzisztálja a valódi `expires_at`-ot (a migrációban nincs ilyen oszlop).

```
media_upload_service.py:566-574
expires_at = row.created_at + (
    SIGNED_URL_EXPIRES_IN  # default — see ADR 0410 §D2.
)
```

A docstring (`:560-574`) kifejezetten — és valótlanul — azt állítja, hogy „the
service-side re-check uses the caller's `signed_url_expires_in` parameter". Ilyen
paraméter nem létezik.

**Független próba (reprodukálva):** 60 s TTL-lel kiadott signed URL a valódi
lejárata UTÁN, `now = created_at + 90 s`-nál **sikeresen finalizálódik**
(`state = finalized`). Ez pontosan a §6.1 mérce-mátrix „A signed URL lejárat után
is elfogadott → A2" hibás implementációja — mégis az A2 cella ZÖLD.

Miért nem fogja meg az A2 teszt: a `test_a2_finalize_rejects_expired_signed_url`
`now`-t pontosan `+5 perc`-re állítja, ami véletlenül egyenlő a hardcode-olt
ablakkal, így a teszt nem tud különbséget tenni „a valódi TTL-t ellenőrzi" és
„egy hardcode-olt konstanst ellenőrzi" között. A ténylegesen kiadott 60 s-os
ablakot a kód figyelmen kívül hagyja.

**Következmény:** egy kiszivárgott/lejárt presigned URL a valós lejárata után is
akár 5 percig finalizálható — a §5.2 „rövid életű, korlátozott" és a §6 A2
acceptance nem teljesül. Javítás: perzisztáld a `SignedUpload.expires_at`-ot a
soron (új oszlop) és a finalize AZ ELLEN hasonlítson, ne egy hardcode-olt
konstans-újraszámolással; az A2 teszt a valódi TTL-t (rövid ablak, `now` közvetlenül
utána) mérje, ne a default 5 percet.

---

## MAJOR

### M1 — Quota permanent lockout: a terminális `cancelled`/`failed` sorok örökre foglalják a kvótát

`_live_upload_count` minden nem-`finalized` sort számol
(`media_upload_service.py:321-338`), beleértve a terminális `cancelled` és
`failed` állapotot. A `cancel_upload` és a `cleanup_orphan_uploads` is
`cancelled`-re állít, amit soha semmi nem távolít el → örökre beszámít a kvótába.

**Független próba (reprodukálva):** 10 upload létrehozása majd mind a 10 lemondása
után a 11. `create_upload_intent` **`MediaQuotaExceeded`-t dob** — a profil
véglegesen kizárva minden további feltöltésből. A helper docstringje ezt
szándékoltként írja le, de ez egy valós availability-bug: normál használat
(10 megszakított/hálózat-vesztett feltöltés egy élettartam alatt) végleges
lockoutot okoz. A kvótának csak a valóban élő (`pending`/`uploaded`) sorokat
kellene számolnia.

### M2 — A checksum-guard (A5) csendes no-op a valódi objektumtár ellen

`_validate_checksum` (`:786-804`) csak akkor dob, ha `row.checksum_sha256` ÉS
`metadata.sha256_hex` is nem-`None`. A production `S3CompatibleObjectStore.head_object`
viszont **fixen `sha256_hex=None`-t ad vissza** (`object_store.py:363`) — a valódi
bucket ellen a checksum-összehasonlítás SOHA nem fut le, a finalize a kliens
állítására hagyatkozik. Az A5 garancia kizárólag az `InMemoryObjectStore`-ral
tart (az populálja a `sha256_hex`-et). Ez a klasszikus „silent no-op" csapda: a
teszt zöld, a prod-útvonal védtelen. Nincs teszt, ami a valós-adapter útvonalat
őrizné. Legalább egy explicit `xfail`/`skip`-jelölt teszt vagy egy TODO-guard
kellene, ami elbukik, amíg a S3-adapter nem tölti ki a `sha256_hex`-et (a §6 A5
állítás jelenleg csak a fake-re igaz).

### M3 — `_as_utc` a LOKÁLIS időzónát csatolja, nem UTC-t (nem-UTC hoston hibás lejárat)

```
media_upload_service.py:341-348
if value.tzinfo is None:
    return value.replace(tzinfo=datetime.now().astimezone().tzinfo)
```

A függvény neve és docstringje szerint „re-attach `timezone.utc`", a kód viszont a
`datetime.now().astimezone().tzinfo`-t (a host lokális zónáját) csatolja. A DB
UTC wall-time-ot tárol; egy nem-UTC hoston (pl. UTC+2) a visszaolvasott naiv
`created_at` a lokális offsettel értelmeződik, így minden lejárat/retention
összehasonlítás a host offsetjével eltolódik (a feltöltések órákkal korábban/később
járnak le). A box UTC-ben fut, ezért a teszt zöld — de a viselkedés
környezet-függő. Javítás: `value.replace(tzinfo=timezone.utc)`.

---

## MINOR

- **m1 — Hamis-magabiztos A2 teszt.** A `test_a2_finalize_rejects_expired_signed_url`
  60 s-os ablakot állít be, amit a kód ignorál, és `+5 perc`-nél mér, ami a
  hardcode-olt konstanssal egyezik. Nem különbözteti meg a helyes/hibás
  implementációt (lásd B1). Follow-up: a valódi TTL-hez kösd a mérést.
- **m2 — Redundáns unique constraint a `public_id`-n.** A migráció `create_table`-jén
  `public_id ... unique=True` (`e09_r18_0012:104-109`) PLUS egy külön
  `op.create_index(..., unique=True)` (`:147-152`) → két unique index ugyanazon
  az oszlopon. Elég egy.
- **m3 — Bare `ValueError` a hiányzó profilra.** `create_upload_intent:428`,
  `finalize_upload:540`, `cancel_upload:681` `ValueError`-t dob a
  `MediaNotFound`/domain-kivétel-család helyett — a leendő router 500-at adna 404
  helyett. Nem konzisztens a §5.3 uniform-404 diszciplínával.
- **m4 — Teljesen nem-tesztelt publikus felület.** `S3CompatibleObjectStore`
  (SigV4 presign/head/delete), `object_store_from_env`, `MediaInvalidationEvent`/
  `on_invalidate` egyetlen teszttel sincs érintve. A brief szerint jövőbeli kör
  wire-öli, de a SigV4-aláírás egy kriptográfiai algoritmus teszt nélkül —
  legalább egy determinisztikus known-answer vektort érdemes lenne rátenni.

## NOTE

- **n1 — Dart stream nem emittál valódi inkrementális progress-t.** Az `upload()`
  async* stream csak egy szintetikus 100%-os `CommunityMediaUploadProgress`-t ad
  a végén; a tényleges byte-progress a `onProgress` callbacken megy
  (`community_media_uploader.dart:221-246`). A docstring azt sugallja, hogy a
  progress a streamen utazik. A `fraction` clamp [0,1]-re helyes (teszt fedi).
  Lifecycle: `CancelToken`/stream nem szivárog cancel/dispose útvonalon — PASS.
- **n2 — A5 „valódi-sértés próba" hiteles.** Függetlenül kivettem a valódi guard-
  záradékot a `_validate_checksum`-ból és futtattam a
  `test_a5_finalize_rejects_checksum_mismatch`-et → `DID NOT RAISE` / RED, majd
  `git checkout` visszaállítás. A §10.2 demonstráció valódi, nem decoy.
- **n3 — IDOR/ownership (A6) valóban véd.** A `finalize`/`cancel` a `public_id`
  lookup UTÁN `row.profile_id == profile.id`-t ellenőriz, idegen tulajra uniform
  `MediaNotFound` — a `test_a6_*` a viselkedést méri. A backend sosem pufferolja a
  teljes fájlt (csak `head_object`) — §5.1 PASS. A méret-küszöb inkluzív
  (`> MAX` reject, `== MAX` accept) mind az intent, mind a finalize oldalon — PASS.

---

## Acceptance mátrix — cellánkénti verdikt

| Cella | Teszt | Verdikt |
|---|---|---|
| A1 (flag KI) | `test_a1_*` (4 db) | PASS — minden belépési pont flag-gated |
| A2 (lejárat) | `test_a2_finalize_rejects_expired_signed_url` | **FAIL (B1)** — hardcode-olt ablak, nem a valódi TTL; hamis zöld |
| A3 (MIME nem extension) | `test_a3_*` (3 db) | PASS — bucket-side Content-Type + allowlist |
| A4 (méret + hármas) | `test_a4_size_threshold_triple`, `..._oversize_bucket_object` | PASS — inkluzív küszöb, defense-in-depth |
| A5 (checksum) | `test_a5_*` + próba | RÉSZLEGES — fake ellen PASS; **valódi objektumtár ellen no-op (M2)** |
| A6 (idegen user) | `test_a6_foreign_user_cannot_{finalize,cancel}` | PASS — uniform 404, `profile_id` re-check |
| A7 (cancel + orphan) | backend 4 + Flutter 4 | PASS — cancel törli az objektumot, orphan-sweep idempotens |

---

## Merge-döntés

**CHANGES REQUESTED.** A B1 (A2 hamis zöld) merge-blokkoló; az M1–M3 szintén
nyitva-blokkoló osztály. A javító körnek: (1) perzisztálni a valódi `expires_at`-ot
és az ellen validálni + valódi-TTL A2 tesztet írni, (2) a kvótaszámlálást az élő
(`pending`/`uploaded`) állapotokra szűkíteni, (3) `_as_utc`-t valódi UTC-re
javítani, (4) az A5 valódi-adapter no-opját legalább egy elbukó guard-teszttel
láthatóvá tenni.
