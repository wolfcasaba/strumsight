# E12-R18 — Security threat model és release scan

- **Státusz:** READY (pre-flight lefuttatva 2026-08-29, kód olvasva: `main @ 6996253b`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 18
- **Kör-azonosító:** `E12-R18`
- **Branch:** `sonnet-impl/e12-r18-threat-model-and-release-security-scan`
- **Előfeltétel:** `E12-R17` merge-elve (az adat-leltár a threat model adat-oldali bemenete) — **teljesült** (`6ead9581`)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`0481`](../adr/0481-program-threat-model-and-release-security-scan.md) — a `tools/round-slots.py reserve-adr` foglalása (lásd §0.0 R1)

**Visszakeresett előzmény** (ADR 0312, szűkített korpusz ELŐSZÖR):

- `--corpus lessons,halts,adr "threat model release security scan secret dependency replay path traversal"` → **[ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md)** (bm25#1), **[L34](../LESSONS.md#l34)** (emb#1 — a scan a megőrzött configra és backupra is terjedjen ki), **[ADR 0091](../adr/0091-song-import-security-boundary.md)** (bm25#4), **[L220](../LESSONS.md#l220)** (emb#2).
- `--corpus lessons,halts "vak scanner fixture bizonyított piros út kivétel lejárat fail-closed"` → **[L220](../LESSONS.md#l220)** (bm25#3 emb#1), **[L116](../LESSONS.md#l116)** (emb#3 — *az ellenőrzéshez szükséges adat megvolt, az ellenőrzés hiányzott*), **[L483](../LESSONS.md#l483)** (egy őr, ami előtagra vak, a saját hibaosztályát engedi vissza).
- Teljes korpusz: `"security_scan.py threat-model.md exceptions.yaml tool/release release scan"` → a saját brief-szakaszai + `docs/plans/gpt/121-gov-04-release-checklist.md#Security` (a release-checklist biztonsági sora).

**L220 alkalmazása:** minden új scan-cellának SAJÁT, bizonyított piros útja kell
legyen. **L116 alkalmazása — ez a kör gerince:** a védelmek adata (a mérő
tesztek) MEGVAN a fán, csak nincs, ami release-döntéssé kösse.

## 0.0 Pre-flight brief-revízió (2026-08-29, Claude) — KÖTELEZŐ OLVASNI

A brief 2026-08-27-én, előre készült. A pre-flight négy állítását cáfolta meg.
Az alábbi revíziók a kör SAJÁT, még nem merge-elt artefaktumát érintik (ADR 0087
§2), tehát az orchestrátor hatáskörében vannak.

### R1 — Az ADR-szám `0458` → **`0481`**

`tools/round-slots.py reserve-adr --round E12-R18` → `0481`. Az előre kiosztott
`0458` elavult (a Ch12 batch-tartomány elcsúszott — ugyanez történt az
E12-R16-ban `0456`→`0477` és az E12-R17-ben `0457`→`0479` esetén). A foglaló az
egyetlen érvényes forrás (a promptok §1.0.1, `tools/tests/test_adr_numbering.py`).

### R2 — A kör NEM ír újra meglévő mércét: BIZONYÍTÉK-KÖTÉST szállít

A pre-flight kimérte, hogy az eredeti brief mind az öt viselkedési
acceptance-cellája MÁR MÉRVE VAN a fán:

| Eredeti cella | A fán MA mérő cella |
|---|---|
| A3 replay elutasítása | `backend/tests/community/test_challenge_verification.py::test_a1_replay_same_source_event_id_lands_one_row`, `::test_a4_stale_pending_row_with_expired_nonce_rejected` |
| A4 path traversal a feltöltési úton | `backend/tests/test_diagnostics.py::test_diagnostics_session_id_cannot_escape_data_dir` |
| oversized payload | `backend/tests/test_diagnostics.py::test_diagnostics_oversize_endpoint_returns_413`, `::test_diagnostics_stops_reading_when_stream_exceeds_limit` |
| A5 manipulált modellcsomag | `test/tooling/ml_asset_manifest_test.dart` (`models[]` ÉS `vision_models[]`, VALÓDI fájl-hash), `test/tooling/vision_model_integrity_test.dart` |
| A1 titok-minta | `tool/ci/check_secrets.dart` + `test/tooling/check_secrets_test.dart` |

Ezek újra-implementálása **második igazságforrást** hozna létre — pontosan az a
hibaosztály, amit az E12-R16 review MAJOR-ja és az ADR 0477 mért
([L555](../LESSONS.md#l555)). Ezért a kör kimenete az ADR 0481 D2 szerinti
**bizonyíték-kötés**: a threat model minden ellenintézkedése géppel olvasható
`guard`-ot nevez meg, és a `security_scan.py` fail-closed módon méri a
guardok LÉTEZÉSÉT a fán.

### R3 — A replay-szemantika MÉRT alakja: idempotens, nem „elutasított"

`backend/app/community/services/challenge_verification_service.py:546`
(`_handle_replay`): terminális állapot → az EREDETI sor változatlanul; lejárt
nonce-ú `pending`/`review` → `rejected` + `reason_code="nonce_expired"`; élő
nonce → érintetlen sor. DB-oldali őr: `uq_community_challenge_results_replay`
(`participant_id`, `source_event_id`). A threat model replay-sora ezt a MÉRT
alakot írja le, nem az „elutasított" megfogalmazást.

### R4 — A feltöltési út mért helye

A feltöltési út a `POST /diagnostics`
(`backend/app/routers/diagnostics.py:119`); a kliens session-id-jét a
`_safe_id()` (`diagnostics.py:56`) MÁR normalizálja. A Community media-feltöltés
(`backend/app/community/services/…`, ADR 0410) presigned PUT úton megy, MIME- és
méret-allowlisttel (`backend/tests/community/test_media_upload.py`). A threat
model mindkét utat KÜLÖN komponensként veszi fel.

### R5 — Ami a fán ténylegesen HIÁNYZIK (ez a kör tényleges tartalma)

1. Program-szintű `docs/security/threat-model.md` — **nincs**.
2. Gépi kötés fenyegetés → ellenintézkedés → bizonyíték — **nincs**.
3. Lejáró kivétel-nyilvántartás — **nincs** (a fán egyetlen `exceptions`-szerű
   YAML sem található).
4. Függőség-korlát ellenőrzés + dátumozott advisory-lista — **nincs**
   (`tool/release/generate_sbom.py` SBOM-ot állít elő, de nem dönt).
5. Egyetlen, release előtt futtatható, fail-closed biztonsági döntés — **nincs**.

## 0.1 Miért nincs új CI-workflow ebben a körben

A `.github/workflows/security.yml` bevezetése a merge-kapu környékét érinti, és
a repó mért szabálya szerint egy workflow-változás bizonyítéka mindig egy
DISPATCH-elt futás (ADR 0052/0053). Ez a kör a scanner-eszközöket és a mércét
szállítja lokálisan futtatható alakban; a CI-bekötés a Kör 25 (RC assembly)
része, ahol a futás bizonyítéka amúgy is kötelező.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/security/threat-model.md",
  "docs/security/exceptions.yaml",
  "tool/release/security_scan.py",
  "test/tooling/security_scan_test.dart",
  "backend/tests/test_security_release.py",
  "docs/rounds/e12-r18-threat-model-and-release-security-scan.md",
]
gate_tests = [
  "test/tooling/security_scan_test.dart",
  "test/tooling/check_secrets_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör tárgya a támadási felület és a titok-kezelés;
egy vak scanner (L220 hibaosztálya) hamis zöldet ad éppen ott, ahol a legdrágább.
A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0.2 Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**A kör-jelzés kötelező** — jelzés nélküli futás bukott futás.

**STOP-protokoll (scope-ütközés):** ha a munkához a §4 engedélyezett listáján
KÍVÜL eső fájlt kellene módosítanod, ne tedd: `stopped` jelzés + a §10-be írt
jelentés (mi ütközik, mi kellene).

**STOP-protokoll (valódi lelet):** ha a scan MÉRT, kritikus sebezhetőséget talál
a termékkódban (`lib/**`, `backend/app/**`), a kimenet a `stopped` jelzés és
jelentés — a javítás önálló, review-zott kör (ADR 0481 D7).

**A brief §8 a terved — nincs külön task-lista.**
**Doc-commentben csak tesztben bizonyított állítás szerepelhet** (`const`,
`immutable`, „fail-closed" stb. csak akkor, ha van rá cella).

## 1. Cél

Program-szintű threat model és lokálisan futtatható, fail-closed release-scan:
a fenyegetések ellenintézkedései géppel **bizonyítékhoz kötve**, lejáró
kivétel-nyilvántartással, függőség-korlát és titok-ellenőrzéssel.

## 2. Jelenlegi állapot — mért tények (2026-08-29, `main @ 6996253b`)

- `docs/security/`: `community-access-matrix.md`, `community-threat-model.md`
  (nyolc kategória: Identity, IDOR, Audience bypass, Block bypass, Spam, Media
  upload, Challenge replay, Moderation abuse — ADR 0395), `signing-key-runbook.md`.
  Program-szintű `threat-model.md` **nincs**.
- `tool/release/`: `build_ai_report.py` (418), `generate_sbom.py` (417),
  `verify_artifacts.py` (111), `verify_signing_policy.py` (337),
  `ai_report_schema.json`. `security_scan.py` **nincs**.
- `tool/ci/check_secrets.dart` (291 sor): `checkSecrets({required Directory projectRoot})`
  könyvtár-függvény + `main()`; öt szabály (`privateKey`, `providerToken`,
  `jsonWebToken`, `credentialAssignment`, `credentialInUrl`), placeholder-szűrő
  (`example|sample|dummy|fake|placeholder|redacted|changeme|your[_-]|test[_-]?only|xxx|\.\.\.`),
  `allowMarker` / `allowFileMarker`, fail-closed `git ls-files`.
- `test/tooling/check_secrets_test.dart` (290 sor) — relatív importtal
  (`import '../../tool/ci/check_secrets.dart';`) hívja a könyvtár-függvényt egy
  ideiglenes git-fán.
- `test/tooling/ml_asset_manifest_test.dart` + `vision_model_integrity_test.dart`
  + `lib/core/ml/vision_model_manifest.dart:263` — a modellcsomag-integritás
  (VALÓDI fájl-sha256) MÁR mérve, `models[]` és `vision_models[]` egyaránt.
- `backend/tests/`: `test_hardening.py` (200 sor: `TestRateLimiter`,
  `TestAuthThrottle`, `TestProdBootGuards`), `test_diagnostics.py`,
  `community/test_challenge_verification.py`, `community/test_media_upload.py`.
  Dedikált release-security teszt **nincs**.
- `backend/requirements.txt`: 12 függőség, mind alsó ÉS felső korláttal
  (`fastapi>=0.115,<0.116` …). `backend/requirements-dev.txt` szintén létezik.
- `.github/workflows/security.yml` **nem létezik** (a §0.1 szerint ebben a körben
  nem is jön létre).
- Python 3.12.3, `PyYAML 6.0.1` elérhető a boxon és a CI-n.

## 3. Scope

**Benne van:**

1. `docs/security/threat-model.md` — STRIDE-szerű, komponensenként (kliens-tároló,
   backend API, diagnosztika-feltöltés, community media-feltöltés, modell-csomag,
   community, release-lánc); a Community-modell (ADR 0395), a song-import határ
   (ADR 0091) és a signing/secret policy (ADR 0448) **hivatkozva, nem másolva**;
   minden ellenintézkedés géppel olvasható `guard`-blokkot hordoz.
2. `tool/release/security_scan.py` — fail-closed release-scan négy ággal:
   `guards` (bizonyíték-kötés), `exceptions` (lejárat), `dependencies`
   (verzió-korlát + dátumozott advisory-lista), `secrets` (delegálás a
   `tool/ci/check_secrets.dart` gate-re).
3. `docs/security/exceptions.yaml` — `owner` + `expires` kötelező; lejárt kivétel
   → nem-nulla kilépés.
4. `test/tooling/security_scan_test.dart` — a §6 kliens-oldali cellái.
5. `backend/tests/test_security_release.py` — a §6 backend-oldali cellái (a
   backend-guardok feloldhatósága + a valódi-sértés próba).

**NINCS benne (tilos):**

- ÚJ CI-workflow (§0.1).
- Termékkód javítása (`lib/**`, `backend/app/**`) — ADR 0481 D7.
- **Meglévő védelmi teszt újra-implementálása** (§0.0 R2 táblázata): a replay-,
  traversal-, oversize- és modell-checksum-viselkedést NEM méred újra; a
  meglévő cellákat GUARDKÉNT kötöd be.
- Második titok-minta-készlet a `security_scan.py`-ben (ADR 0481 D3).
- Valódi titok, kulcs vagy sebezhetőségi PoC commitolása; a fixture SZINTETIKUS
  és a scanner mintáira ILLESZKEDIK ([L220](../LESSONS.md#l220)).
- `docs/adr/**` — az ADR 0481 KÉSZ, a Claude írta.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/security/threat-model.md` | ÚJ — program-szintű modell + guard-kötés |
| `docs/security/exceptions.yaml` | ÚJ — kivétel-nyilvántartás lejárattal |
| `tool/release/security_scan.py` | ÚJ — a scan-eszköz |
| `test/tooling/security_scan_test.dart` | ÚJ — a kliens-oldali §6 cellák |
| `backend/tests/test_security_release.py` | ÚJ — a backend-oldali §6 cellák |
| `docs/rounds/e12-r18-threat-model-and-release-security-scan.md` | a §10 handoff kitöltése |

**Tilos zóna:** `lib/**` · `backend/app/**` · `.github/**` · `docs/adr/**` ·
`tools/**` · `tool/ci/**` · `docs/security/community-*.md` · minden meglévő teszt.

## 5. Kötött architekturális döntések (ADR 0481)

A hét döntés teljes szövege:
[`docs/adr/0481-program-threat-model-and-release-security-scan.md`](../adr/0481-program-threat-model-and-release-security-scan.md).
Röviden:

- **D1** — a threat model BEEMEL, nem duplikál (ADR 0395 / 0091 / 0448).
- **D2** — minden ellenintézkedés géppel olvasható `guard`-ot nevez meg; a
  `release_gate: true` guardok LÉTEZÉSÉT a scan fail-closed méri.
- **D3** — a titok-ág DELEGÁL a `tool/ci/check_secrets.dart`-ra; nincs második
  regex-készlet; a nem futtatható gate **kritikus lelet**, nem `skipped`.
- **D4** — a kivétel `owner` + `expires` nélkül nem létezik; a határ INKLUZÍV
  (ma lejáró MÉG érvényes); a „ma" `--today`-jel átadható.
- **D5** — kritikus lelet → nem-nulla kilépés; nincs `--force`/`--no-fail`
  elnyelő ág.
- **D6** — hiányzó vagy parse-hibás bemenet → fail-closed nem-nulla kilépés.
- **D7** — a kör nem javít termékkódot; valódi lelet → `stopped`.

### 5.1 A `guard`-blokk alakja (kötött)

A `docs/security/threat-model.md` minden ellenintézkedése alatt egy
```` ```yaml ```` blokk áll, PONTOSAN ezekkel a kulcsokkal:

```yaml
id: T-DIAG-01
component: diagnostics-upload
threat: tampering
release_gate: true
guard:
  path: backend/tests/test_diagnostics.py
  test: test_diagnostics_session_id_cannot_escape_data_dir
```

- `id` — egyedi a dokumentumban; `[A-Z0-9-]+`.
- `component` — a §3 komponens-listájából.
- `threat` — STRIDE-érték: `spoofing|tampering|repudiation|information-disclosure|denial-of-service|elevation-of-privilege`.
- `release_gate` — bool. `true` ⇒ a guard létezését a scan MÉRI.
- `guard.path` — a repó gyökeréhez képesti, LÉTEZŐ útvonal.
- `guard.test` — opcionális; ha megvan, a `path` fájlnak tartalmaznia kell a
  teszt nevét (pytest `def <név>`, Dart `test('<név>'`); a puszta
  substring-egyezés elég, de a hiánya **kritikus lelet**.

Ismeretlen kulcs, hiányzó kötelező kulcs vagy ismeretlen `threat`-érték:
**kritikus lelet** (D6).

### 5.2 A `security_scan.py` CLI-szerződése (kötött)

```
python3 tool/release/security_scan.py \
  [--root <repó-gyökér>] \
  [--threat-model docs/security/threat-model.md] \
  [--exceptions docs/security/exceptions.yaml] \
  [--requirements backend/requirements.txt] \
  [--today YYYY-MM-DD] \
  [--only guards|exceptions|dependencies|secrets] \
  [--secrets-cmd "<parancs>"] \
  [--format text|json]
```

- Kilépési kód: `0` = nincs kritikus lelet; `1` = van kritikus lelet;
  `2` = a bemenet nem értelmezhető (D6). **Nincs más kód, és nincs elnyelő
  kapcsoló.**
- `--secrets-cmd` alapértéke `dart run tool/ci/check_secrets.dart`; a
  parancs a `--root` könyvtárban fut. Nem-nulla kilépés vagy nem futtatható
  parancs → **kritikus lelet** (D3).
- `--format json` géppel olvasható leletlistát ír (`findings[]`:
  `id`, `severity`, `branch`, `message`), a `text` emberit; **egyik sem
  írhat ki titok-értéket**, csak helyet (a `check_secrets.dart` mért szabálya).
- A `--today` alapértéke a mai UTC dátum.

### 5.3 A `dependencies` ág (kötött)

- Minden `--requirements` sor (komment és üres sor kivételével) **felső
  korlátot** hordozzon (`<`, `<=`, `==` vagy `~=`). Korlát nélküli sor →
  kritikus lelet.
- A `security_scan.py` egy dátumozott, a fájlban kommenttel dokumentált
  `_ADVISORIES` konstanst hordoz (`package`, `affected` verzió-kifejezés,
  `id`, `severity`). Az advisory-találat kritikus lelet, hacsak nincs rá
  ÉLŐ kivétel az `exceptions.yaml`-ban.
- Az advisory-lista a KÖR IDEJÉN a fán MÉRT függőségekre nézve legyen üres vagy
  valós — kitalált CVE tilos; az üres lista is elfogadott, ha a §6 A6 cellája a
  szintetikus advisory-val bizonyítja a piros utat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `secrets` ág DELEGÁL: egy szintetikus, ismert-rossz (a `check_secrets` mintáira ILLESZKEDŐ, nem placeholder) literált tartalmazó fán a scan **kritikus leletet** ad és nem-nullával lép ki | `security_scan_test.dart` |
| A2 | A `secrets` ág fail-closed: nem futtatható / nem-nulla `--secrets-cmd` → kritikus lelet, NEM `skipped` | `security_scan_test.dart` |
| A3 | Lejárt kivétel → nem-nulla kilépés; a küszöb INKLUZÍV (§6.1 cellahármas) | `security_scan_test.dart` |
| A4 | `owner` vagy `expires` nélküli kivétel-bejegyzés → kritikus lelet | `security_scan_test.dart` |
| A5 | A `guards` ág kritikus leletet ad, ha egy `release_gate: true` ellenintézkedés `guard.path`-ja nem létezik, VAGY a `guard.test` neve nincs benne a fájlban | `security_scan_test.dart` |
| A6 | Felső korlát nélküli függőségi sor, illetve advisory-találat → kritikus lelet; ÉLŐ kivétellel viszont átmegy | `security_scan_test.dart` |
| A7 | Hiányzó vagy parse-hibás threat model / `exceptions.yaml` → **exit 2** (D6), nem 0 | `security_scan_test.dart` |
| A8 | A SZÁLLÍTOTT `docs/security/threat-model.md` minden §3-beli komponenshez legalább egy `id`-t rendel, és minden `release_gate: true` blokk guardja MA feloldható a fán | `security_scan_test.dart` (a valódi fán futtatva, exit 0) |
| A9 | A threat model backend-oldali `release_gate: true` guardjai pytest node-idként MA feloldhatók (`--collect-only`), és egy elrontott node-id PIROS | `backend/tests/test_security_release.py` |
| A10 | A meglévő `check_secrets_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Küszöb-cellahármas a kivétel-lejáratra

A határ INKLUZÍV: a mai napon lejáró kivétel MÉG érvényes. A három cella
`--today`-jel determinisztikus, a dátumokat **`python3 -c`-vel számold ki**,
ne gépeld be:

```bash
python3 -c "import datetime as d; t=d.date(2026,8,29); print(t-d.timedelta(days=1), t, t+d.timedelta(days=1))"
# 2026-08-28 2026-08-29 2026-08-30
```

| Cella | `expires` | `--today` | Elvárás |
|---|---|---|---|
| küszöb ALATT | `2026-08-28` | `2026-08-29` | kritikus lelet, exit 1 |
| PONTOSAN rajta | `2026-08-29` | `2026-08-29` | átmegy, exit 0 |
| küszöb FÖLÖTT | `2026-08-30` | `2026-08-29` | átmegy, exit 0 |

### 6.2 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A szintetikus fixture nem illeszkedik a `check_secrets` egyetlen mintájára sem (vak scan, L220) | A1 |
| A titok-ág a nem futtatható gate-et `skipped`-nek veszi és 0-val lép ki | A2 |
| A lejárat-ellenőrzés figyelmeztet, de 0-val lép ki | A3 |
| A kivétel-parser elfogadja a `expires` nélküli bejegyzést | A4 |
| A `guards` ág csak a `guard.path` létezését nézi, a `guard.test` nevét nem | A5 |
| A `dependencies` ág csak a formátumot nézi, a felső korlát hiányát nem | A6 |
| A hiányzó bemenetre „nincs lelet, tehát 0" ág (L220 általánosítása) | A7 |
| A threat model egy komponenst guard nélkül hagy, vagy elavult guardot nevez meg | A8 |
| Egy backend-guard node-id elgépelve / átnevezve, és senki nem méri | A9 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a
`security_scan.py` `guards` ágából a `guard.test`-név ellenőrzését (vagy tedd
mindig igazzá), futtasd a §7 gate-et → az **A5** cellának PIROSNAK kell lennie →
állítsd vissza. A §10-be írd be a próba PONTOS parancsát és a kapott kimenetet.

## 7. Kötelező ellenőrzések

A mérce artefaktum, nem prompt-szöveg — futtasd PONTOSAN így, csővezeték és
`tail` nélkül:

```bash
tools/round-gate.sh test/tooling/security_scan_test.dart test/tooling/check_secrets_test.dart
```

Backend sáv (KÜLÖN processzként, a gate után):

```bash
cd backend && python -m pytest tests/test_security_release.py tests/test_hardening.py -q
```

A scan valós fán futtatva (a §10-be másolva a kimenetet):

```bash
python3 tool/release/security_scan.py
```

## 8. Implementációs sorrend

1. `docs/security/threat-model.md` — komponensenként a fenyegetések és
   ellenintézkedések, mindegyik alatt az §5.1 `guard`-blokkal. A guardokat a fán
   MÉRD ki (a §0.0 R2 táblázata a kiindulás), ne találd ki.
2. `tool/release/security_scan.py` — a négy ág az §5.2 CLI-szerződéssel.
3. `docs/security/exceptions.yaml` — legalább egy valós, ÉLŐ (jövőbeli
   lejáratú) bejegyzés vagy egy kimondottan üres, sémáját dokumentáló fájl.
4. `test/tooling/security_scan_test.dart` — A1–A8, a §6.1 cellahármassal.
5. `backend/tests/test_security_release.py` — A9.
6. A valódi-sértés próba lefuttatása és a §10 kitöltése.

## 9. Kockázatok

- **Vak scanner (L220).** A fixture nem illeszkedik a mintákra, és minden zöld
  (A1). A fixture-t a `check_secrets.dart` MÉRT szabályaiból származtasd
  (`test/tooling/check_secrets_test.dart` mintái a példa), és a fájl elejére
  tedd ki a `strumsight:allow-secret-file` markert, hogy a repó SAJÁT titok-gate-je
  ne akadjon el rajta — a meglévő `check_secrets_test.dart` pontosan így tesz.
- **Duplikáció (E12-R16 MAJOR / L555).** Egy meglévő védelem újra-mérése második
  igazságforrás; a §3 tiltja.
- **Kritikus lelet a termékkódban.** Ilyenkor `stopped` (ADR 0481 D7).
- **A kivétel-nyilvántartás elfajulása.** Lejárat nélküli kivétel = a threat
  model kikapcsolása (A3/A4).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-08-29.

### 10.1 Szállított fájlok

| Fájl | Tartalom |
|---|---|
| `docs/security/threat-model.md` | 7 komponens (client-storage, backend-api, diagnostics-upload, community-media-upload, model-package, community, release-chain), 14 `guard`-blokk, mind `release_gate: true`, mind a fán MA MÉRT tesztre mutat. D1 szerint BEEMEL (ADR 0395/0091/0448-ra hivatkozik, nem másol). |
| `docs/security/exceptions.yaml` | Séma dokumentálva, üres `exceptions: []` — a pre-flight idején nincs elfogadott kockázat. |
| `tool/release/security_scan.py` | A négy ág (`guards`, `exceptions`, `dependencies`, `secrets`) az §5.2 CLI-szerződéssel; exit 0/1/2, nincs elnyelő kapcsoló. |
| `test/tooling/security_scan_test.dart` | A1–A8 + a §6.1 küszöb-cellahármas + egy `--format json` szanitás-teszt, összesen 22 teszt. |
| `backend/tests/test_security_release.py` | A9 — a `security_scan.py`-t modulként betöltve (nem újraírt parser) kinyeri a 8 backend `release_gate` guardot, mindegyiket `pytest --collect-only`-jal feloldja, majd egy elrontott node-idet pirosra bizonyít. |

### 10.2 A guard-lista (mind release_gate: true, mind MÉRT a fán)

client-storage: T-CLIENT-01 (`test/core/storage/secure_store_test.dart`) ·
backend-api: T-API-01 (`backend/tests/test_auth.py`) ·
diagnostics-upload: T-DIAG-01, T-DIAG-02 (`backend/tests/test_diagnostics.py`) ·
community-media-upload: T-MEDIA-01, T-MEDIA-02, T-MEDIA-03
(`backend/tests/community/test_media_upload.py`) ·
model-package: T-MODEL-01 (`test/tooling/vision_model_integrity_test.dart`),
T-MODEL-02 (`test/tooling/ml_asset_manifest_test.dart`) ·
community: T-COMM-01 (`backend/tests/community/test_challenge_verification.py`),
T-COMM-02 (`backend/tests/community/test_access_policy.py`) ·
release-chain: T-RELEASE-01 (`test/tooling/signing_policy_test.dart`),
T-RELEASE-02 (`test/tooling/check_secrets_test.dart`), T-RELEASE-03
(`test/tooling/security_scan_test.dart` — a scan saját, ebben a körben írt
bizonyított piros útja a felső-korlát-nélküli függőség cellára).

Egyik guard sem a §0.0 R2 táblázatban felsorolt öt védelem ÚJRA-mérése — a
replay-, traversal-, oversize- és modell-checksum-viselkedést a meglévő
tesztek (`test_challenge_verification.py`, `test_diagnostics.py`,
`vision_model_integrity_test.dart`) hordozzák, a `guards` ág csak a
LÉTEZÉSÜKET méri.

### 10.3 Futtatott parancsok és tényleges kimenetük

**A kliens-oldali gate** (`tools/round-gate.sh test/tooling/security_scan_test.dart test/tooling/check_secrets_test.dart`,
csonkítás nélkül, teljes futás):

```
[1] format                                    zöld
[2] analyze                                   zöld (No issues found!)
[3] test test/tooling/security_scan_test.dart zöld (22/22, "All tests passed!")
[4] test test/tooling/check_secrets_test.dart zöld (13/13, unchanged — A10)
[5] architecture                              zöld
[6] secrets                                   zöld (Secret scan OK, 4076 file(s), 0 finding(s))
[7] l10n                                      zöld
[8] backend ruff format                       zöld (133 files already formatted)
[9] backend ruff check                        zöld (All checks passed!)
[10] backend pytest (teljes suite)            zöld (100%, egy `x` = várt xfail, 0 hiba)
```

A `backend pytest` lépés a TELJES backend suite-ot futtatja (a round-gate
saját szabálya, nem szűkíthető) — ezen a boxon kb. 10 percig fut (mért:
11:46–11:57), de a kilépési kód `0`, minden `.` zöld, a Gate-összegzés
mind a tíz lépésre `zöld`-et mutat.

**A backend-sáv célzottan** (`cd backend && python -m pytest
tests/test_security_release.py tests/test_hardening.py -q`):

```
...........................                                              [100%]
27 passed
```

(10 a `test_security_release.py`-ból — 1 „van legalább egy guard” + 8
paraméterezett node-id-feloldás + 1 elrontott node-id piros —, 17 a
változatlan `test_hardening.py`-ból.)

**A scan a valós fán** (`python3 tool/release/security_scan.py`):

```
security_scan: OK — no critical or fatal finding.
```

Exit code: `0`.

### 10.4 A valódi-sértés próba (KÖTELEZŐ, §6.2 A5 cella)

A `check_guards()`-ban a `guard.test` substring-ellenőrzést ideiglenesen
kikapcsoltam (`if False and needle_python not in guard_text and ...`), majd
lefuttattam:

```
$ flutter test test/tooling/security_scan_test.dart
```

Eredmény — **PONTOSAN az A5 cella pirosodott**, minden más zöld maradt:

```
00:01 +9 -1: A5 — the guards branch checks both guard.path AND guard.test a guard.test name absent from guard.path is a critical finding [E]
  Expected: <1>
    Actual: <0>
  security_scan: OK — no critical or fatal finding.
...
Some tests failed.
Failing tests:
  .../test/tooling/security_scan_test.dart: A5 — the guards branch checks both guard.path AND guard.test a guard.test name absent from guard.path is a critical finding
```

Ezután a substring-ellenőrzést visszaállítottam, és megerősítettem, hogy a
teljes fájl újra zöld (`22/22, "All tests passed!"`).

### 10.5 Nyitott kockázatok / megjegyzések

- Az `exceptions.yaml` jelenleg üres — ez a MÉRT állapotot tükrözi (nincs
  elfogadott kockázat), nem egy hiányzó funkciót.
- A `_ADVISORIES` lista egyetlen, valós, dátumozott bejegyzést tartalmaz
  (PyJWT CVE-2022-29217, `<2.4.0`), amely a jelenlegi pin
  (`PyJWT>=2.8,<3`) felett NEM aktiválódik — szándékosan valós, nem
  kitalált CVE, hogy az A6 piros útja bizonyított legyen anélkül, hogy a
  fánk saját, éles függőségére hamis riasztást adna.
- A kivétel-elnyelés (exception suppression) ebben a körben a `dependencies`
  ágra (és a default teljes futásra) van bekötve; a `--only guards` / `--only
  secrets` izolált módok szándékosan NEM konzultálnak az `exceptions.yaml`-lal
  (egyszerűbb, önálló branch-tesztelhetőség — a brief egyik acceptance-cellája
  sem kéri guard- vagy secrets-kivételt).
- A `.github/workflows/security.yml` CI-bekötése szándékosan NINCS ebben a
  körben (§0.1) — Kör 25 (RC assembly) feladata.
- Termékkód-javításra a scan a valós fán NEM talált okot (D7 nem
  alkalmazandó ebben a körben).

## 10.6 Javító kör (E12-R18 review fixes, 2026-08-29, Claude Sonnet 5)

A kötelező `security-reviewer` (`docs/reviews/e12-r18-review-security.md`)
4 MAJOR + 3 javítandó MINOR leletet mért, izolált klónban futtatott
próbákkal, a zöld §10.3 gate mellett. A leletlistát a `REVIEW-FINDINGS.md`
gyűjtötte össze; az alábbi táblázat leletenként a javítást, az ÚJ cellát és
a TÉNYLEGES parancs-kimenetet rögzíti (ADR 0481 D2 — a javítás önmagában nem
elég, a saját mérce is bizonyítson).

### MAJOR-1 — egy `exceptions.yaml` sor kikapcsolta a teljes `secrets` ágat

**Javítás** (`tool/release/security_scan.py`): a `secrets` ág leletei
**soha, semmilyen `--only` módban nem elnyelhetők** — a
`run()`-ban a `secrets` blokk többé nem hívja `_apply_exceptions`-t (D3: a
titok-kapu fail-closed delegáció, nem elfogadható kockázat). A kivétel-
bejegyzés kötelező `branch` mezőt kapott (`_REQUIRED_EXCEPTION_KEYS`), amely
csak `guards` vagy `dependencies` lehet (`_EXCEPTABLE_BRANCHES`) — ismeretlen
vagy hiányzó `branch` kritikus lelet (`exceptions.invalid-branch` /
`exceptions.missing-field`). A `live` szótár kulcsa mostantól
`(branch, finding)` pár, nem csak `finding` — egy `dependencies`-re szóló
bejegyzés nem nyel el egy azonos id-jű `guards`-leletet, és fordítva. A
modul-docstring (`:1-43`) és a `docs/security/exceptions.yaml` sémadoksija
igazítva a mért viselkedéshez.

**Új cellák** (`test/tooling/security_scan_test.dart`, csoport `MAJOR-1`, 5
teszt): (a) a review pontos repróját (owner+jövőbeli-lejárat kivétel a két
fix `secrets.*` id-re, `--secrets-cmd /bin/false`, default teljes futás)
bizonyítottan EXIT=1 marad; (b) `branch` nélküli bejegyzés →
`exceptions.missing-field`; (c) `branch: secrets` (vagy bármilyen nem
`guards`/`dependencies` érték) → `exceptions.invalid-branch`; (d) egy
`dependencies`-branchre szóló kivétel NEM nyeli el az azonos id-jű
`guards`-leletet; (e) pozitív kontroll — egy helyesen `branch: guards`-ra
szóló kivétel TOVÁBBRA IS elnyeli a saját ágának leletét (D4 nem sérült túl).

**Mérve — a régi kódon (a),(b),(c),(d) PIROS, (e) is PIROS** (a `live` dict
korábban `finding`-re kulcsolt, `branch` mező nem is létezett):
```
$ (5 régi security_scan.py-ra: cp /tmp/security_scan_new.py biztonsági
   mentés után `git show 7798dfc4:tool/release/security_scan.py` a helyére,
   majd `flutter test test/tooling/security_scan_test.dart`)
00:01 +14 -4: MAJOR-1 … an exception naming a secrets finding id does not
  suppress a failing --secrets-cmd on the default (full) run [E]
  … Expected: <1>  Actual: <0>
… (mind az öt MAJOR-1 cella a régi kódon PIROS vagy hibásan zöld a
   várttal ellentétesen — lásd a teljes log fentebb a beszélgetésben)
```
Az ÚJ kódon mind az öt zöld (lásd §10.6 végi teljes gate-log).

### MAJOR-2 — a guard „létezése" nyers substring: skip/comment/rename átcsúszott

**Javítás** (`tool/release/security_scan.py`): a `check_guards` többé nem
nyers substringet keres. Új helperek: `_strip_python_trivia` /
`_strip_dart_comments` (a `# `/`//`/`/* */` komment és a string-tartalom
kimaszkolása a repó saját `_withoutTrivia` mintája szerint —
`test/core/architecture_dependency_test.dart:1227`, csak olvasva, nem
módosítva), `_python_guard_status` (LEZÁRT `def <név>(` tű + a megelőző
~400 karakterben `@pytest.mark.skip`/`xfail`/`unittest.skip`/`pytest.skip(`
keresés), `_dart_guard_status` (a `test(` hívás egymást követő, Dart-
auto-konkatenált string-literáljainak összefűzése — így egy `'rész 1 '` +
`'rész 2'` alakú, több sorra tördelt névre is illeszkedik —, a hívás teljes
zárójel-tartományában `skip:`/`@Skip(` keresés). `found=False` → „not
found”, `found=True és disabled=True` → külön kritikus lelet („disabled
(skip/xfail marker)”).

**Új cellák** (csoport `MAJOR-2`, 5 teszt + `MAJOR-2 cross-check`, 1 teszt):
(1) python `@pytest.mark.skip` a guard fölött → kritikus; (2) Dart
`test(...)` kikommentelve → kritikus; (3) python `def <név>_v2(` (utótag-
átnevezés) NEM csúszik át a lezárt tűn; (4) Dart `skip: true` paraméter →
kritikus; (5) pozitív kontroll — a szállított consent-guardok saját, két
literálra tördelt alakja élőben feloldódik. A `MAJOR-2 cross-check` egy
FÜGGETLEN, Dart-ban újraírt (nem a python parsert hívó) `test('<név>'`
feloldást futtat a valós fa mind a hat Dart-guardjára — ugyanaz a szerep,
mint a backend A9 `--collect-only` keresztmérésének, csak Dart oldalon.

**Mérve — a régi kódon 4/5 PIROS, (5) hibásan PIROS is** (a régi tű nem
kezelte a több-literálos konkatenációt sem):
```
00:02 +15 -5: … a guard.test that exists but is skip-marked … [E]
  Expected: <1>  Actual: <0>
00:02 +15 -6: … a Dart guard.test whose test( call is commented out … [E]
  Expected: <1>  Actual: <0>
00:02 +15 -7: … a python guard.test renamed with a suffix … [E]
  Expected: <1>  Actual: <0>
00:02 +15 -8: … a Dart guard.test with a skip: argument … [E]
  Expected: <1>  Actual: <0>
00:02 +15 -9: … split across two adjacent string literals … still resolves … [E]
  Expected: <0>  Actual: <1>
  - T-FIXTURE-08 … guard.test 'first part…second part…' not found …
```
Az ÚJ kódon mind a hat (5+1 cross-check) zöld.

### MAJOR-3 — hiányzott a §5 nem tárgyalható határ (egress + consent)

**Javítás** (`docs/security/threat-model.md`): új, 8. komponens
(`client-egress`), két `release_gate: true` guard a MÁR MEGLÉVŐ
`test/privacy/consent_enforcement_test.dart` (E12-R17) konkrét celláira —
`T-EGRESS-01` (`upload() with consent false never touches the wire
adapter` — nyers audio nem hagyja el az eszközt consent nélkül) és
`T-EGRESS-02` (`a profile update sent while signed in reaches the wire; the
same call after logout does not — same container, no restart (A6)` —
kijelentkezés után nincs rejtett hálózati kérés). Plusz `T-DIAG-03`
(`backend/tests/test_diagnostics.py::test_diagnostics_rejects_bad_token` —
a `POST /diagnostics` `X-Diag-Token`/`hmac.compare_digest` spoofing-kapuja)
és `T-API-02`
(`backend/tests/test_hardening.py::TestAuthThrottle::test_login_brute_force_gets_429_with_retry_after`
— login brute-force throttle, DoS). Egyik sem méri újra a védelmet
(ADR 0481 §0.0 R2 szelleme) — csak bekötik a MEGLÉVŐ mércét a
release-döntésbe.

**Mérve a fán, MINDEN guard MA feloldható** (a `grep -n "def <név>\|test('<név>"
<path>` lelépés minden új guardra elvégezve a bekötés előtt):
```
$ grep -n "def test_diagnostics_rejects_bad_token(" backend/tests/test_diagnostics.py
64:def test_diagnostics_rejects_bad_token(client, tmp_path, monkeypatch):
$ grep -n "def test_login_brute_force_gets_429_with_retry_after(" backend/tests/test_hardening.py
43:    def test_login_brute_force_gets_429_with_retry_after(self, client):
$ grep -n "test('upload() with consent false never touches the wire adapter'" test/privacy/consent_enforcement_test.dart
145:      'upload() with consent false never touches the wire adapter',
```
(a `T-EGRESS-02` konkatenált nevét a MAJOR-2 javítás oldja fel — lásd fent.)

Backend oldali kereszt-bizonyíték: `T-DIAG-03` és `T-API-02` automatikusan
bekerült a `backend/tests/test_security_release.py`
`_backend_guard_node_ids()` listájába (10 backend node-id 8 helyett) —
ehhez a `_resolve_node_id` helper is javításra szorult (lásd alább, a
mérce-mátrix melléklete).

**Melléklet — a `_backend_guard_node_ids` saját hibája, amit a T-API-02
bekötése fogott ki:** a régi node-id konstrukció `f"{path}::{test}"`
alakú volt, ami módszer-szintű (`class Test...:`) tesztre HIBÁSAN
kollabál, mert a valódi pytest node-id `path::Class::test`. A
`T-API-02` (`TestAuthThrottle` osztályban) ezt PIROSRA fogta:
```
$ cd backend && python3 -m pytest tests/test_security_release.py -q
FAILED …test_backend_guard_resolves_as_a_pytest_node_id[tests/test_hardening.py::test_login_brute_force_gets_429_with_retry_after]
  ERROR: not found: …/backend/tests/test_hardening.py::test_login_brute_force_gets_429_with_retry_after
  (no match in any of [<Module test_hardening.py>])
```
Javítás: `_resolve_node_id` a `pytest --collect-only <path>` (NEM `-q` —
a `-q` egyetlen „`<file>: <szám>`” összegző sorra csonkítja a kimenetet,
node-id nélkül) teljes node-id listáját olvassa, és a `::<guard_test>`
utótagra illeszti — osztály-beágyazástól függetlenül helyes node-id-t ad.
Ez a saját mérce hibája volt, nem a threat modellé; a T-API-02 bekötése
fogta ki, pontosan a brief §6.2 „minden guardot MÉRJ LE” elve szerint.

### MAJOR-4 — a `T-CLIENT-01` guard nem a leírt fenyegetést mérte

**Javítás** (`docs/security/threat-model.md`): a guard átkötve
`test/core/storage/secure_store_test.dart` (`_MemoryStorage` fake fölötti
generikus round-trip) helyett
`test/features/auth/token_store_test.dart::round-trips a token under the
documented secure key`-re — ez a TÉNYLEGES tárolási utat méri
(`SecureTokenStore` → `StorageKeys.secureAuthToken` kulcs → `SecureStore`
interfész). A „`FlutterSecureStore` az egyetlen import-hely” állítás
átfogalmazva **kimondottan nem mért feltevésként** (jövőbeli
architektúra-cella tárgya), nem release-blokkoló tényként.

**Mérve:**
```
$ grep -n "test('round-trips a token under the documented secure key'" test/features/auth/token_store_test.dart
45:  test('round-trips a token under the documented secure key', () async {
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
```

### MINOR-1 — a `guard.path` kiléphetett a repóból

**Javítás**: `check_guards`-ban `resolved_guard.is_relative_to(root.resolve())`
ellenőrzés a `is_file()` ELŐTT — kilépő út (abszolút vagy `../`-lánc) saját
kritikus lelet (`guard.path escapes the repo root`), nem csendes „not a
file”.

**Új cellák** (csoport `MINOR-1`, 2 teszt): `/etc/hostname` és
`../../../../etc/hosts` mindkettő kritikus lelet.

**Mérve — a régi kódon mindkettő PIROS** (a review saját reprója):
```
00:02 +16 -10: … an absolute guard.path is a critical finding … [E]
  Expected: <1>  Actual: <0>
00:02 +16 -11: … a `..`-relative guard.path escaping the root … [E]
  Expected: <1>  Actual: <0>
```

### MINOR-2 — a `release_gate` átbillentése néma volt

**Javítás**: az A8 doksi-substring-teszt (`contains('component: <name>')`)
mellé egy ÚJ, a SZÁLLÍTOTT modellre kötött cella — mind a 18 ismert `id`
(a MAJOR-3 4 új guardjával bővült lista) `id:`/`component:`/`threat:`/
`release_gate: true` négysoros blokkjára illeszkedő regex, sorrendben.

**Mérve — a review pontos reprója (mind a 18 `release_gate: true` →
`false`) a régi A8-cellán ZÖLD maradt volna, az ÚJ cella PIROSRA fogja:**
```
$ sed 's/^release_gate: true$/release_gate: false/' docs/security/threat-model.md > /tmp/… (18 találat)
$ flutter test test/tooling/security_scan_test.dart --plain-name "MINOR-2"
00:00 +0 -1: … each known id resolves to id + release_gate: true, in order [E]
  Expected: true  Actual: <false>
  T-CLIENT-01 is missing, or not release_gate: true, in the shipped threat model
```
(a threat-model.md ezután visszaállítva, `python3 tool/release/security_scan.py --only guards` → EXIT=0 megerősítve.)

### MINOR-3 — jelen lévő, de guard nélküli threat model zöld volt

**Javítás**: `check_guards` elején — ha `entries` üres VAGY nincs köztük
`release_gate: true`, a teljes ág EGYETLEN kritikus lelettel tér vissza
(`guards.no-release-gate-entries`), a fájlonkénti ellenőrzés helyett/előtt.

**Új cella** (csoport `MINOR-3`, 1 teszt): az egyetlen guard-blokk
` ```yaml ``` ` helyett ` ```text ``` ` fenceben (a review pontos reprója) →
EXIT=1, `no-release-gate-entries`.

**Mérve — a régi kódon PIROS:**
```
00:02 +17 -12: … all guard blocks demoted to a non-```yaml``` fence exits 1 … [E]
  Expected: <1>  Actual: <0>
```

### Kötelező ellenőrzések — TÉNYLEGES kimenet (javító kör után)

```
$ tools/round-gate.sh test/tooling/security_scan_test.dart test/tooling/check_secrets_test.dart
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/security_scan_test.dart                  zöld (37/37, "All tests passed!")
    test test/tooling/check_secrets_test.dart                  zöld (13/13, unchanged — A10)
    architecture                                               zöld
    secrets                                                    PIROS (kilépési kód 1)
```

```
$ cd backend && python -m pytest tests/test_security_release.py tests/test_hardening.py -q
.............................                                              [100%]
(29 passed — 12 test_security_release.py: 1 „van legalább egy guard” + 10
paraméterezett node-id-feloldás + 1 elrontott node-id piros; 17
test_hardening.py, változatlan)
```

```
$ python3 tool/release/security_scan.py
security_scan: 1 finding(s).
- [critical] secrets: secrets delegate command 'dart run tool/ci/check_secrets.dart' exited 1:
  Secret scan failed (4082 file(s) scanned, 1 finding(s)).
  - docs/reviews/e12-r18-review-security.md:421: provider token literal
  (secrets.delegate-failed)
EXIT=1
```

**A `[6] secrets` PIROS oka — MÉRT, a kör saját hat fájlján KÍVÜLI, előfeltétel
állapot, nem az én diffem regressziója.** A `docs/reviews/e12-r18-review-security.md:421`
sora (a reviewer saját dokumentuma, `7798dfc4`, ez a kör §4 tiltott zónája —
„Ne módosítsd a `docs/reviews/e12-r18-review-security.md` fájlt”) szó szerint
idézi az A1 acceptance-cella szintetikus titok-fixture-jét (a
`test/tooling/security_scan_test.dart:114` `sk-` előtagú, 30 karakteres
fixture-értékét) az inline allow-jelölő NÉLKÜL — ezt a
`tool/ci/check_secrets.dart` (szintén tiltott zóna, `tool/ci/**`) a valós
fán bárhol megtalálja, FÜGGETLENÜL az én security_scan.py/threat-model.md
javításaimtól:
```
$ dart run tool/ci/check_secrets.dart
Secret scan failed (4082 file(s) scanned, 1 finding(s)).
- docs/reviews/e12-r18-review-security.md:421: provider token literal
```
Mérve: ez a `secrets` ág EGYETLEN lelete — a MAJOR/MINOR javítások mind a
négy másik ágon (`guards`, `exceptions`, `dependencies`) és a `secrets` ág
saját fail-closed logikáján is bizonyítottan hibátlanok (lásd a §10.6 fenti
cellái). A `--only guards`/`--only dependencies`/`--only exceptions` külön
futtatva mind EXIT=0 (lásd MAJOR-3/MAJOR-4 mérései fent). A fix egy
`strumsight:allow-secret` jelölőt igényelne a review-dokumentum saját
sorában — ez a hat engedélyezett fájlon és a tiltott zónán (`tool/ci/**`,
`docs/reviews/**`) is kívül esik, tehát a jelen kör hatáskörén kívül van
(STOP-protokoll, scope-ütközés). Orchestrátor-döntés szükséges: vagy a
review-dokumentum kap egy külön, dedikált (nem `sonnet-impl`-javító) kört
a jelölő hozzáadására, vagy a `check_secrets.dart` szabálya bővül a
`docs/reviews/**` kizárásával.

### Nyitott, átvitt tételek (NEM javítva ebben a körben, a brief tiltása szerint)

MINOR-4 (a `--format json` futás-metaadata hiánya — a Kör 25 bekötéséhez
tartozik), MINOR-5 (az advisory-illesztés tartományos kifejezés-hiánya), N1
(a delegált parancs stdout/stderr-je szó szerint a leletben — ma nem
szivárgás, mérve), N2 (a 180 s timeout hideg CI-fordításon hamis kritikust
adhat), N3 (a `dependencies` ág egyetlen manifestet lát —
`requirements-dev.txt` és a Dart-oldal nincs bekötve), N4 (rendben —
`shell=False`, `yaml.safe_load`, argv-alapú `--collect-only` hívás).

## 10.7 Második javító kör (E12-R18 fix2, 2026-09-01, Claude Sonnet 5)

A `docs/reviews/e12-r18-review-security-followup.md` a §10.6 javítás után
7/7 leletet ZÁRVA mért, és két ÚJ leletet nyitott: **S8** (MAJOR, latens —
fájl-/group-szintű elnémítás továbbra is zöld) és **S9** (MINOR — a MAJOR-4
guard-cél-javításának nincs piros útja). Ez a kör mindkettőt zárja.

### S8 — fájl-/group-szintű elnémítás most már kritikus lelet

**Javítás** (`tool/release/security_scan.py`): három új helper zárja a
review három konkrét forgatókönyvét, a MEGLÉVŐ `_python_guard_status` /
`_dart_guard_status` (közvetlen def/test-környezet) MELLETT, nem helyette:

- `_python_module_skip_disabled` (:573-598) — a modul BÁRHOL elhelyezett
  `pytestmark = pytest.mark.skip(...)` vagy `.xfail(...)` sorát (bare vagy
  `pytestmark = [...]` lista alakban) keresi regexszel
  (`_PY_PYTESTMARK_ASSIGN`), és ha talál `pytest.mark.skip`/`.xfail`
  markert az értékben, a modul MINDEN guardját `disabled=True`-ra állítja
  (`check_guards`, :360-363: `disabled or (found and
  _python_module_skip_disabled(...))`).
- `_dart_file_skipped` (:605-619) — a fájl `library;` direktívája (az első
  `import`/`part`/`export` előtti fejléc) fölötti `@Skip(...)` annotációt
  keresi (`_DART_LIBRARY_SKIP`), függetlenül attól, hogy a `test(` hívás
  fölötti 200 karakteres prelude-ba belefér-e.
- `_dart_enclosing_group_skipped` (:625-634) — a `test(` hívást megelőző
  ÖSSZES `group(...)` hívást végigmegy, és ha bármelyik, a test hívást
  ténylegesen körülölelő span `skip:`-et tartalmaz, `disabled=True` (a
  meglévő `_dart_call_span` zárójel-egyensúlyozóját újrahasználva).

**Új cellák** (`test/tooling/security_scan_test.dart`, csoport `S8`, 4
teszt): (1) bare `pytestmark = pytest.mark.skip(...)`; (2) lista alakú
`pytestmark = [pytest.mark.skip(...)]`; (3) Dart `@Skip(...)` a `library;`
fölött; (4) Dart `group('disabled', skip: true, () { test(...) })`.

**BIZONYÍTOTT PIROS ÚT — mind a négy S8-forgatókönyv, a régi (`HEAD`,
`4783c9f7`) `security_scan.py`-on, az ÚJ tesztfájllal** (`cp
tool/release/security_scan.py /tmp/security_scan_new.py; git show
HEAD:tool/release/security_scan.py > tool/release/security_scan.py;
flutter test test/tooling/security_scan_test.dart --plain-name "S8"`):

```
00:00 +0 -1: … a module-level `pytestmark = pytest.mark.skip(...)` silences
  the whole python file even though the test itself carries no marker [E]
  Expected: <1>  Actual: <0>
  security_scan: OK — no critical or fatal finding.
00:00 +0 -2: … a module-level `pytestmark = [pytest.mark.skip(...)]` list
  form silences the whole python file too [E]
  Expected: <1>  Actual: <0>
00:00 +1 -3: … a Dart `group(..., skip: true)` wrapping the guard.test
  silences it even though the test's own call carries no marker [E]
  Expected: <1>  Actual: <0>
00:00 +1 -3: Some tests failed.
```

3/4 cella bizonyítottan PIROS a régi kódon. A negyedik (Dart
library-level `@Skip`) a régi kódon is ZÖLDNEK mérve — nem azért, mert a
régi kód kezelte a fájl-szintű `@Skip`-et, hanem mert a próba-fixture
rövidsége miatt a `@Skip(...)\nlibrary;` sor véletlenül BELEFÉRT a régi
`_dart_guard_status` 200 karakteres prelude-ablakába (a `test(` hívás
fölötti nyers karaktertávolság), ami a réginek KOINCIDENCIA-fedést adott
egy 10 soros fixture-ön, nem valódi fájl-szintű ellenőrzést egy valós,
hosszabb tesztfájlon. Ez maga a review S8-leletének pontos állítása
("fájl-szintű karantén… ami a MAJOR-2 javítása le akart zárni, de nem
zárt le") — a mérés ezt megerősíti, nem gyengíti.

A `/tmp/security_scan_new.py` visszamásolása után (`cp
/tmp/security_scan_new.py tool/release/security_scan.py`) mind a 4 S8-cella
ZÖLD (`00:02 +4: All tests passed!`).

### S9 — a MAJOR-4 guard-cél-javításának pinnelt mércéje

**Javítás** (`test/tooling/security_scan_test.dart`, csoport `MINOR-1`
záró cellája, `knownGuardTargets` + az új `each known id resolves to its
OWN shipped guard.path + guard.test` teszt): a MEGLÉVŐ `knownGuardIds`
lista (id + `release_gate: true`, sorrend) MELLÉ egy `id → (path, test)`
map, amely mind a 18 ismert guardra a TÉNYLEGESEN szállított
`guard.path`/`guard.test` párra illeszkedő teljes 6-soros blokkot
(`id:`/`component:`/`threat:`/`release_gate: true`/`guard:`/`  path:`/
`  test:`) várja a threat modellben, sorrendtől függetlenül regexpel
ellenőrizve. `security_scan.py` maga NEM változott ehhez a lelethez — a
scan a guard-célt már ma is helyesen FELOLDJA, akármelyik célra mutasson;
a hiányzó mérce a fájl SAJÁT ismert-lista cellája volt, nem a scan logikája.

**BIZONYÍTOTT PIROS ÚT — a `T-CLIENT-01` guard visszagyengítve a MAJOR-4
előtti célra** (`docs/security/threat-model.md`: `guard.path` →
`test/core/storage/secure_store_test.dart`, `guard.test` → `round-trips a
secret`, a MAJOR-4 javítás pontos visszavonása):

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.      SCAN_EXIT=0
```

A `security_scan.py` maga — várhatóan — NEM veszi észre: a gyengébb cél is
feloldódik, `check_guards` csak azt méri, hogy a `path`/`test` LÉTEZIK, nem
hogy melyik konkrét pár az elvárt. Ez pontosan az S9-lelet állítása.

```
$ flutter test test/tooling/security_scan_test.dart --plain-name \
  "each known id resolves to its OWN shipped guard.path"
00:00 +0 -1: … each known id resolves to its OWN shipped guard.path +
  guard.test — a silent retarget to a weaker guard is a critical finding,
  not a pass (S9) [E]
  Expected: true  Actual: <false>
  T-CLIENT-01 no longer resolves to its shipped guard.path
  (test/features/auth/token_store_test.dart) + guard.test (round-trips a
  token under the documented secure key) in the threat model
```

Az ÚJ cella a `security_scan.py` vakfoltját fogja ki, PIROSRA váltva a
csendes visszagyengítést, amit a scan önmagában zöldnek mérne. A
`docs/security/threat-model.md` ezután visszaállítva a szállított célra
(`git diff docs/security/threat-model.md` üres a mérés után); `flutter
test test/tooling/security_scan_test.dart` a teljes fán **`00:05 +42: All
tests passed!`**.

### Kötelező ellenőrzések — TÉNYLEGES kimenet (második javító kör után)

```
$ tools/round-gate.sh test/tooling/security_scan_test.dart test/tooling/check_secrets_test.dart
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/security_scan_test.dart                  zöld
    test test/tooling/check_secrets_test.dart                  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
    backend ruff format                                        zöld
    backend ruff check                                         zöld
    backend pytest                                             zöld

MINDEN GATE ZÖLD.
```

(A §10.6 idején mért `[6] secrets` PIROS — a `docs/reviews/…` fájl saját,
jelölő nélküli fixture-idézete — időközben lezárult, a `32ed9cae
docs(review): allow-secret-file marker a review-jelentésen` commit-tal;
ez a kör nem nyúlt a `docs/reviews/**` tiltott zónához.)

```
$ python3 tool/release/security_scan.py
security_scan: OK — no critical or fatal finding.
EXIT=0

$ cd backend && python3 -m pytest tests/test_security_release.py tests/test_hardening.py -q
.............................                                              [100%]
(29 passed)
EXIT=0
```

**Összegzés:** S8 + S9 mindkettő ZÁRVA, mérve. A fa a két engedélyezett
fájlon (`tool/release/security_scan.py`, `test/tooling/security_scan_test.dart`)
kívül tiszta — a mérési rontások (`security_scan.py` régi verzióra,
`threat-model.md` visszagyengítve) mindegyike visszaállítva a mérés után.

## 10.8 Harmadik javító kör (E12-R18 fix3, 2026-09-01, Claude Sonnet 5)

A `docs/reviews/e12-r18-review-security-fix2.md` a §10.7 után az S8 négy
NEVESÍTETT forgatókönyvét és az S9-et ZÁRVA mérte, de az S8 *hibaosztályát*
("fájl-szintű elnémítás mellett a kapu EXIT 0-t ad") nem tekintette
zártnak: két, a VALÓS fán reprodukált egysoros megkerülést talált (**S10**,
**S11**, mindkettő MAJOR), plusz két kontrollált-fixture-ön mért, a mai fán
nem realizálható leletet (**S12**, **S13**, MINOR). Ez a kör mind a négyet
zárja, `tool/release/security_scan.py`-ban.

### S10 — Dart `@Skip(...)` a `library;` NÉLKÜL

**Javítás** (`tool/release/security_scan.py`, `_dart_file_skipped`): a
korábbi `_DART_LIBRARY_SKIP` regex kifejezetten `@Skip(...)\nlibrary`
alakot várt. Az új `_DART_SKIP_ANNOTATION` (`@Skip\(`) + `_DART_DIRECTIVE`
(`library|import|part|export`) pár a fájl ELSŐ direktívája (bármelyik a
négy közül) ELŐTTI fejlécben keres `@Skip(`-et — a `library;` sor többé nem
követelmény, mert a `package:test` a fájl első DIREKTÍVÁJÁNAK metaadatát
olvassa (`test_core`'s `parse_metadata.dart`:
`directives.first.metadata`), nem kifejezetten a `library`-ét. Ha a fájlnak
egyáltalán nincs direktívája, a függvény `False`-t ad — nincs mit
`.first.metadata`-ként olvasnia a test-keretnek, tehát a fejléc soha nem
válik "az egész fájllá" (ami hamis pozitívot adna a
`security_scan_test.dart` saját, string-be ágyazott fixture-jeire, amelyek
minden esetben a fájl valódi importjai UTÁN élnek).

**BIZONYÍTOTT PIROS ÚT — a VALÓS fán** (`test/tooling/vision_model_integrity_test.dart`
legelső sora elé `@Skip('whole file disabled — no library directive')`, a
`library;` sor NÉLKÜL, közvetlenül az első `import` fölé):

```
$ python3 tool/release/security_scan.py --only guards
security_scan: 1 finding(s).
- [critical] guards: T-MODEL-01 (model-package): guard.test 'bad checksum
  fails the integrity gate' is present but disabled (skip/xfail marker) in
  test/tooling/vision_model_integrity_test.dart — a silenced protection is
  release-blocking, not a silent regression (ADR 0481 D2) (T-MODEL-01)
S10_EXIT=1
```

A javítás előtt ugyanez a rontás `security_scan: OK` / `SCAN_EXIT=0` volt
(a review saját mérése). Rontás visszaállítva (`git checkout --
test/tooling/vision_model_integrity_test.dart`).

**Új cella** (`test/tooling/security_scan_test.dart`, csoport `S10`):
`@Skip(...)` közvetlenül az első `import` fölött, `library;` direktíva
NÉLKÜL → `EXIT=1`.

### S11 — python `pytest.skip(..., allow_module_level=True)`

**Javítás** (`tool/release/security_scan.py`, `_python_module_skip_disabled`):
új `_PY_MODULE_LEVEL_SKIP_CALL` regex (`^pytest\.skip\(`, oszlop-0-n
horgonyozva) a `pytestmark`-keresés MELLETT — egy nem-indentált
`pytest.skip(` hívás csak modul-szinten fordulhat elő (egy függvény/teszt
törzsében lévő hívás mindig indentált), ezért ez a minta megbízhatóan
modul-szintű elnémítást jelez, függetlenül attól, hogy a guard `def`-je
milyen távol van tőle (a korábbi 400 karakteres `_python_guard_status`
prelude-ablak, amit az S11 megkerült, itt nem szűkít).

**BIZONYÍTOTT PIROS ÚT — a VALÓS fán** (`backend/tests/test_diagnostics.py`
tetejére `import pytest` + `pytest.skip('whole file disabled',
allow_module_level=True)`):

```
$ python3 tool/release/security_scan.py --only guards
security_scan: 3 finding(s).
- [critical] guards: T-DIAG-01 … is present but disabled … (T-DIAG-01)
- [critical] guards: T-DIAG-02 … is present but disabled … (T-DIAG-02)
- [critical] guards: T-DIAG-03 … is present but disabled … (T-DIAG-03)
S11_EXIT=1
```

Mind a három diagnosztika-guard egyszerre néma volt a javítás előtt
(`SCAN_EXIT=0`, a review saját mérése), most mindhárom nevesítve. Rontás
visszaállítva.

**Új cella** (`test/tooling/security_scan_test.dart`, csoport `S11`): bare
`pytest.skip('...', allow_module_level=True)` modul tetején → `EXIT=1`.

### S12 — osztály-szintű `@pytest.mark.skip` a 400 karakteres ablakon kívül

**Javítás** (`tool/release/security_scan.py`, új
`_python_class_skip_disabled`): a guard `def`-et tartalmazó legközelebbi
`^class ` deklaráció felkutatása (`_PY_CLASS_DEF.finditer` a `def_idx`-ig),
majd a class-sor FÖLÖTTI, megszakítás nélküli `@...` dekorátor-sorok
visszafelé bejárása `@pytest.mark.skip`/`@pytest.mark.xfail`/
`@unittest.skip` mintára — ablak-független, tetszőleges távolságra a `def`-
től. Bekötve a `check_guards`-ba a meglévő `_python_module_skip_disabled`
mellé (`or`-ral).

**BIZONYÍTOTT PIROS ÚT — kontrollált fixture-ön** (`/tmp/s8probe`, mert a
mai fa egyetlen osztályba ágyazott guardja, `T-API-02`, az osztály ELSŐ
metódusa — a lelet ott nem realizálható): `@pytest.mark.skip(reason='class
disabled')` egy `class TestEverything:` fölött, 30 kitöltő metódus, majd a
guard-metódus:

```
$ python3 tool/release/security_scan.py --root /tmp/s8probe \
      --threat-model threat-model.md --only guards
security_scan: 1 finding(s).
- [critical] guards: T-FIXTURE-S12 … is present but disabled … (T-FIXTURE-S12)
S12_EXIT=1
```

A javítás előtt ez `security_scan: OK` / `EXIT=0` volt (a review saját
mérése, `pytest` oldalon `31 skipped`).

**Új cella** (`test/tooling/security_scan_test.dart`, csoport `S12`):
osztály-dekorátor + 30 kitöltő metódus + a guard-metódus → `EXIT=1`.

### S13 — `_dart_enclosing_group_skipped` hamis pozitív

**Javítás** (`tool/release/security_scan.py`, új `_dart_call_head` +
átírt `_dart_enclosing_group_skipped`): a korábbi ellenőrzés a `group(...)`
hívás TELJES span-jában (string-tartalommal együtt) kereste a `skip:`-et,
ami a body-n BELÜLI, testvér-hívások saját `skip:` argumentumát, vagy egy
description-string `skip:`-et tartalmazó szövegét is találatnak vette. Az
új `_dart_call_head` a hívás nyitó `(`-je és a `group`/`test` mindig
nulla-argumentumú callback-jének (`() {`/`() async {`) kezdete közötti
szöveget adja vissza, string-literál TARTALOM nélkül — ez a group SAJÁT
argumentum-feje, ahol a `skip:` névvel ellátott argumentum ténylegesen él a
fán mindenütt használt sorrendben (`group('d', skip: true, () {...})`). A
callback TÖRZSE (beágyazott hívások, description-stringek) kimarad a
keresésből.

**BIZONYÍTOTT PIROS ÚT (a hamis pozitív HIÁNYA) — a VALÓS fán**
(`test/tooling/check_secrets_test.dart`: a `T-RELEASE-02` guard-teszt köré
egy NEM-skipelt `group('mixed', () { … })`, benne egy független, `skip:
true`-val jelölt testvér-teszttel):

```
$ python3 tool/release/security_scan.py --only guards
security_scan: OK — no critical or fatal finding.
S13_EXIT=0
```

A javítás ELŐTTI kóddal ugyanez a szerkesztés `EXIT=1`-et adott (a review
saját mérése, `T-RELEASE-02 … is present but disabled` hamis állítással).
Egy második, kontrollált fixture-ön ugyanez igaz egy tisztán
string-literálbeli `skip:` előfordulásra (`group('contains the substring
skip: in its own description', …)`) is: `EXIT=0`.

**Regresszió-őr, ugyanazon a mechanizmuson** — az S13-narrowing nem
nyithatja vissza az S8/3-at: `group('disabled', skip: true, () { test(…)
})` MOST IS `EXIT=1`, `T-RELEASE-02 … is present but disabled` ✅, és az
S8/3b „A" variáns (egymásba ágyazott group, a KÜLSŐ skipelt) is `EXIT=1`
maradt ✅ (mindkettő mérve a valós fán, rontás visszaállítva).

**Új cellák** (`test/tooling/security_scan_test.dart`, csoport `S13`, 3
teszt): (1) testvér `skip: true` közös, NEM-skipelt groupban → `EXIT=0`;
(2) `skip:`-et tartalmazó description-string → `EXIT=0`; (3) a group SAJÁT
`skip: true`-ja továbbra is `EXIT=1` (regresszió-őr).

### Regresszió-ellenőrzés — a mérés a valós fán

Mind a négy S8-forgatókönyv (pytestmark bare, pytestmark lista, Dart
library `@Skip`, Dart group `skip: true`) + az S8/3b „A"/„C" variáns +
az S9-cella a javítás UTÁN is a review mérésével egyező módon viselkedik
(mind PIROS a megfelelő rontásra), és a teljes fa `python3
tool/release/security_scan.py` `EXIT=0`.

### Kötelező ellenőrzések — TÉNYLEGES kimenet (harmadik javító kör után)

```
$ tools/round-gate.sh test/tooling/security_scan_test.dart test/tooling/check_secrets_test.dart
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/tooling/security_scan_test.dart                  zöld
    test test/tooling/check_secrets_test.dart                  zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld
    backend ruff format                                        zöld
    backend ruff check                                         zöld
    backend pytest                                             zöld

MINDEN GATE ZÖLD.
```

`flutter test test/tooling/security_scan_test.dart`: **`00:04 +48: All
tests passed!`** (42 → 48, a hat új S10–S13 cella).
`flutter test test/tooling/check_secrets_test.dart`: **`00:00 +13: All
tests passed!`** (változatlan — ez a kör nem módosította ezt a fájlt).

```
$ python3 tool/release/security_scan.py
security_scan: OK — no critical or fatal finding.
EXIT=0

$ cd backend && python3 -m pytest tests/test_security_release.py tests/test_hardening.py -q
.............................                                              [100%]
(29 passed)
EXIT=0
```

**Összegzés:** S10, S11, S12, S13 mind ZÁRVA, mérve — beleértve a S10/S11
VALÓS fán reprodukált rontását is, nem csak kontrollált fixture-t. A fa a
két engedélyezett fájlon (`tool/release/security_scan.py`,
`test/tooling/security_scan_test.dart`) kívül tiszta a kör végén; minden
mérési rontás (`vision_model_integrity_test.dart`, `test_diagnostics.py`,
`check_secrets_test.dart`, a `/tmp/s8probe` kontrollált fixture)
visszaállítva.

## 11. Review — a Claude tölti ki
