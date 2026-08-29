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

## 11. Review — a Claude tölti ki
