# ADR 0481 — Program-szintű threat model: a védelem BIZONYÍTÉKHOZ kötve, a release-scan fail-closed

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** `E12-R18` (Chapter 12, Kör 18)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [`0395`](0395-community-baseline-feature-flags-and-threat-model-scope.md) (Community threat
  model — a program-szintű modell BEEMELI, nem duplikálja),
  [`0091`](0091-song-import-security-boundary.md) (song import security boundary
  — a nem megbízható fájlbemenet MÁR MÉRT határa),
  [`0448`](0448-production-signing-policy-and-secret-hardening.md) (signing
  policy + secret hardening — a `tool/release/verify_signing_policy.py` mércéje),
  [`0477`](0477-ai-release-evidence-aggregation-and-ga-scope-truth.md)
  (AI release evidence aggregation — a **bizonyíték-aggregáció** mért
  precedense, amelyet ez a kör a biztonsági sávra alkalmaz),
  [`0138`](0138-factory-hardening-scope-guard-and-independence.md) (a `tool/ci/check_secrets.dart` a
  titok-minták EGYETLEN forrása)

## Kontextus — a pre-flight MÉRT tényei (2026-08-29, `main @ 6996253b`)

A kör előre megírt briefje (2026-08-27) öt acceptance-cellát írt elő, amelyek
mind egy-egy KONKRÉT védelmi viselkedést mértek volna újra. A pre-flight
kimérte, hogy ezek a védelmek **ma már mind mérve vannak** a fán:

| Brief-cella (eredeti) | A fán MA mérő cella |
|---|---|
| A3 — replay elutasítása | `backend/tests/community/test_challenge_verification.py::test_a1_replay_same_source_event_id_lands_one_row`, `::test_a4_stale_pending_row_with_expired_nonce_rejected` |
| A4 — path traversal a feltöltési úton | `backend/tests/test_diagnostics.py::test_diagnostics_session_id_cannot_escape_data_dir` |
| oversized payload | `backend/tests/test_diagnostics.py::test_diagnostics_oversize_endpoint_returns_413`, `::test_diagnostics_stops_reading_when_stream_exceeds_limit` |
| A5 — manipulált modellcsomag | `test/tooling/ml_asset_manifest_test.dart` (`models[]` ÉS `vision_models[]`, VALÓDI fájl-hash: `ml_asset_manifest_test.dart:512`, `lib/core/ml/vision_model_manifest.dart:263`), `test/tooling/vision_model_integrity_test.dart` |
| A1 — titok-minta | `tool/ci/check_secrets.dart` + `test/tooling/check_secrets_test.dart` (L220) |

Két további mért pontosítás:

1. **A replay a fán IDEMPOTENS, nem „elutasított".**
   `backend/app/community/services/challenge_verification_service.py:546`
   (`_handle_replay`) három ága: terminális állapot → az EREDETI sor változatlanul
   visszaadva (A1); `pending`/`review` + lejárt nonce → `rejected` +
   `reason_code="nonce_expired"`; `pending`/`review` + élő nonce → érintetlen sor.
   A DB-oldali őr az `uq_community_challenge_results_replay`
   (`participant_id`, `source_event_id`) unique constraint. Az „elutasított"
   megfogalmazás tehát a fán MÉRT viselkedést tévesen írja le.
2. **A feltöltési út a `POST /diagnostics`**
   (`backend/app/routers/diagnostics.py:119`), és a kliens által adott
   session-id-t a `_safe_id()` (`diagnostics.py:56`) MÁR normalizálja
   (`c.isalnum() or c in "-_"`, 48 karakter). A traversal-védelem nem hiányzik —
   mérve van.

**A tényleges hiány tehát nem egy védelem, hanem a védelmek FÖLÖTTI szerződés:**
nincs program-szintű threat model, nincs gépi kötés fenyegetés → ellenintézkedés
→ bizonyíték, nincs lejáró kivétel-nyilvántartás, és nincs egyetlen, release
előtt futtatható, fail-closed döntés.

## Döntés

### D1 — A program-szintű threat model BEEMEL, nem duplikál

A `docs/security/threat-model.md` a komponenseket (kliens-tároló, backend API,
media-feltöltés, diagnosztika-feltöltés, modell-csomag, community, release-lánc)
STRIDE-szerűen fedi le, de a már meglévő, ADR-rel elfogadott modellekre
**hivatkozik** (Community: ADR 0395 nyolc kategóriája; song import: ADR 0091;
signing/secret: ADR 0448). Egy fenyegetés leírása két helyen két igazság —
az ADR 0477 D-döntéseinek ugyanaz volt a gyökere.

**NEM elfogadható gyengítés:** a Community nyolc kategóriájának átmásolása a
program-szintű dokumentumba.

### D2 — Minden ellenintézkedéshez géppel olvasható bizonyíték-kötés tartozik

A threat model minden ellenintézkedése géppel olvasható blokkot hordoz, amely
megnevezi a **guardot**: egy fán létező fájl-útvonalat és — ahol értelmezhető —
a konkrét teszt-azonosítót (pytest node-id vagy Dart teszt-név). A
`tool/release/security_scan.py` a `release_gate: true` jelölésű
ellenintézkedések guardjainak LÉTEZÉSÉT fail-closed módon méri: hiányzó,
átnevezett vagy törölt guard **kritikus lelet**.

Ez az ADR 0477 mért mintája (a bizonyíték-kapu a *követelményt* is őrzi, nem
csak a bizonyíték meglétét — [L555](../LESSONS.md#l555)), a biztonsági sávra
alkalmazva: egy védelmi teszt csendes törlése ma NEM pirosít semmit.

**NEM elfogadható gyengítés:** prózai „lásd a teszteket" hivatkozás gépi kötés
nélkül; vagy a guard-lista olyan felsorolása, amelynek nincs bizonyított piros
útja (átnevezett node-id → zöld).

### D3 — A scan nem ír újra meglévő mércét; a titok-ág DELEGÁL

A `security_scan.py` a titok-mintákat **nem deklarálja újra**: a titok-ág a
`tool/ci/check_secrets.dart` gate futtatásával dönt (a minták egyetlen forrása,
ADR 0138 / [L220](../LESSONS.md#l220)). A delegáció fail-closed: ha a hívott
gate nem futtatható (hiányzó `dart`, nem-nulla belső hiba), az **kritikus
lelet**, nem `skipped`.

**NEM elfogadható gyengítés:** a `security_scan.py`-be másolt második
regex-készlet; vagy a `dart` hiányára adott „nem tudtam mérni, tehát zöld" ág.

### D4 — A kivétel owner és LEJÁRAT nélkül nem létezik; a határ INKLUZÍV

A `docs/security/exceptions.yaml` minden bejegyzése kötelezően hordoz `owner`,
`expires` (ISO `YYYY-MM-DD`), az érintett lelet azonosítóját és az indoklást.
A lejárat-összevetés határa **inkluzív**: a MA lejáró kivétel MÉG érvényes; a
tegnap lejárt kivétel **kritikus lelet** → nem-nulla kilépés. Az összevetés
alapja a hívónak átadható „ma" (`--today`), hogy a küszöb-cellahármas
determinisztikusan mérhető legyen.

**NEM elfogadható gyengítés:** „örökös" kivétel, hiányzó/üres `expires`, vagy a
lejárt kivétel figyelmeztetés-szintre sorolása.

### D5 — Nyitott kritikus lelet mellett nincs RC

A `security_scan.py` kritikus leletnél **nem-nulla** kóddal lép ki, és a
kimenete géppel olvasható. A Kör 25 RC-összeállítója ezt a kilépési kódot
olvassa.

**NEM elfogadható gyengítés:** „majd a következő release-ben" figyelmeztetés-ág,
vagy egy `--force`/`--no-fail` kapcsoló, amely a kritikus leletet elnyeli.

### D6 — Ismeretlen bemenet fail-closed

Hiányzó vagy parse-hibás threat model, `exceptions.yaml` vagy függőség-manifest
esetén a scan **nem-nulla** kóddal lép ki. A „nem találtam bemenetet, tehát
tiszta" ág a mért hibaosztály (L220) általánosítása.

### D7 — A kör NEM javít termékkódot

A scan a fán MA meglévő állapotot méri. Ha kritikus, valódi lelet keletkezik a
termékkódra (`lib/**`, `backend/app/**`), a kör kimenete `stopped` jelzés és
jelentés — a javítás önálló, review-zott kör (a brief §0.0/§9).

## Következmények

- A biztonsági védelmek törlése vagy átnevezése mostantól **release-blokkoló**,
  nem csendes regresszió.
- A threat model karbantartása kikényszerített: új komponens guard nélkül nem
  kaphat `release_gate: true` sort.
- A kivételek elavulnak maguktól — nincs örökös kivétel.
- A CI-bekötés (`.github/workflows/security.yml`) SZÁNDÉKOSAN nem ebben a
  körben történik: egy workflow-változás bizonyítéka mindig egy dispatch-elt
  futás (ADR 0052/0053), ami a Kör 25 (RC assembly) kötelező része.
