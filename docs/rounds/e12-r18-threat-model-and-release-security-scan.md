# E12-R18 — Security threat model és release scan

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 18
- **Kör-azonosító:** `E12-R18`
- **Branch:** `<motor>/e12-r18-threat-model-and-release-security-scan`
- **Előfeltétel:** `E12-R17` merge-elve (az adat-leltár a threat model adat-oldali bemenete)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0458` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "threat model security scan secret dependency replay tampering"` → **[L220](../LESSONS.md#l220)**: egy self-heal által beírt fixture-literál, amely NEM tartalmazza a secrets-scan placeholder-szavainak egyikét sem, a scannert némán vakká teszi. A kör minden új scan-cellájának ezért SAJÁT, bizonyított piros útja kell legyen.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `docs/security/community-threat-model.md` MÉRT szerkezetét (a Community sáv nyolc kategóriája, ADR 0395) és a `tool/ci/check_secrets.dart` + `test/tooling/check_secrets_test.dart` párost. A program-szintű threat model a Community-modellt BEEMELI, nem duplikálja.

## 0.0 Miért nincs új CI-workflow ebben a körben

A `.github/workflows/security.yml` bevezetése a merge-kapu környékét érinti, és a repó mért szabálya szerint egy workflow-változás bizonyítéka mindig egy DISPATCH-elt futás (ADR 0052/0053). Ez a kör a scanner-eszközöket és a mércét szállítja lokálisan futtatható alakban; a CI-bekötés a Kör 25 (RC assembly) része, ahol a futás bizonyítéka amúgy is kötelező.

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

**Kockázat = high, indoklás:** a kör tárgya a támadási felület és a titok-kezelés; egy vak scanner (L220 hibaosztálya) hamis zöldet ad éppen ott, ahol a legdrágább. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a scan MÉRT, kritikus sebezhetőséget talál a termékkódban, a kimenet a `stopped` jelzés és jelentés — a javítás önálló, review-zott kör.

## 1. Cél

Program-szintű threat model és lokálisan futtatható release-scan (titok, függőség, replay, path traversal, modell-manipuláció), lejáró kivétel-nyilvántartással.

## 2. Jelenlegi állapot — mért tények

- `docs/security/`: `community-access-matrix.md`, `community-threat-model.md` — a Community sávra korlátozott modell; program-szintű `threat-model.md` **nincs**.
- `tool/ci/check_secrets.dart` + `test/tooling/check_secrets_test.dart` **létezik** (L220 tanulságával); `tool/ci/check_song_fixture_licenses.dart` a fixture-licencekre.
- `test/tooling/vision_model_integrity_test.dart` **létezik** — a modell-integritás ellenőrzésének MÉRT precedense.
- `backend/tests/test_hardening.py` **létezik**; dedikált release-security teszt nincs.
- `.github/workflows/security.yml` **nem létezik** (a §0.0 szerint ebben a körben nem is jön létre).
- Community replay-védelem: az `e09_r22_0016_community_challenge_result` és a leaderboard `verified` projekció (ADR 0418) MÁR ad szerver-oldali védelmet.

## 3. Scope

**Benne van:** `docs/security/threat-model.md` (STRIDE-szerű, komponensenként: kliens-tároló, backend API, media-feltöltés, modell-csomag, diagnosztika, community; a Community-modell BEEMELVE hivatkozással) · `tool/release/security_scan.py` (titok-minta, függőség-verzió és ismert-sebezhetőség lista, upload-útvonal ellenőrzés; minden ág lokálisan futtatható és fail-closed) · `docs/security/exceptions.yaml` (owner + LEJÁRATI dátum kötelező, lejárt kivétel → nem-nulla kilépés) · `test/tooling/security_scan_test.dart` · `backend/tests/test_security_release.py` (replay-ismétlés elutasítása, path traversal a feltöltési úton, oversized payload).

**NINCS benne (tilos):**

- ÚJ CI-workflow (§0.0).
- Termékkód javítása (`lib/**`, `backend/app/**`).
- Valódi titok, kulcs vagy sebezhetőségi PoC commitolása; a fixture SZINTETIKUS, és tartalmazza a scanner placeholder-szavait ([L220](../LESSONS.md#l220)).
- `docs/adr/**` — az ADR 0458-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/security/threat-model.md` | ÚJ — program-szintű modell |
| `docs/security/exceptions.yaml` | ÚJ — kivétel-nyilvántartás lejárattal |
| `tool/release/security_scan.py` | ÚJ — a scan-eszköz |
| `test/tooling/security_scan_test.dart` | a kliens-oldali §6 cellák |
| `backend/tests/test_security_release.py` | a backend-oldali §6 cellák |

**Tilos zóna:** `lib/**` · `backend/app/**` · `.github/**` · `docs/adr/**` · `tools/**` · `docs/security/community-*.md`

## 5. Kötött architekturális döntések (ADR 0458)

### 5.1 Minden scan-cellának BIZONYÍTOTT piros útja van

Egy scan, aminek nincs ismert-rossz bemenete, nem mérce ([L220](../LESSONS.md#l220)). **NEM elfogadható gyengítés:** „a scanner lefutott, nem talált semmit" mint bizonyíték.

### 5.2 A kivétel owner és LEJÁRAT nélkül nem létezik

**NEM elfogadható gyengítés:** „örökös" kivétel vagy üres lejárat-mező.

### 5.3 Nyitott kritikus lelet mellett nincs RC

A `security_scan.py` kritikus leletnél nem-nulla kóddal lép ki, és ezt a Kör 25 RC-összeállítója olvassa. **NEM elfogadható gyengítés:** figyelmeztetés-szintre soroló „majd a következő release-ben" ág.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A titok-scan a SZINTETIKUS ismert-rossz fixture-t megtalálja | `security_scan_test.dart` |
| A2 | Lejárt kivétel → nem-nulla kilépés | `security_scan_test.dart` |
| A3 | Replay (ugyanaz az eredmény-beküldés kétszer) elutasított | `backend/tests/test_security_release.py` |
| A4 | Path traversal kísérlet a feltöltési úton elutasított | `backend/tests/test_security_release.py` |
| A5 | Manipulált (checksum-hibás) modellcsomag elutasított | `security_scan_test.dart` a MÉRT `vision_model_integrity` mintája szerint |
| A6 | A threat model minden komponenshez legalább egy azonosított fenyegetést és ellenintézkedést rendel | a dokumentum + a teszt szerkezeti cellája |
| A7 | A meglévő `check_secrets_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

**Küszöb-cellahármas a kivétel-lejáratra** (a határ INKLUZÍV: a mai napon lejáró kivétel MÉG érvényes): a küszöb **alatt** (lejárat = tegnap) → nem-nulla kilépés; **pontosan rajta** (lejárat = ma) → átmegy; a küszöb **fölött** (lejárat = holnap) → átmegy.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A fixture nem tartalmazza a scanner egyetlen mintáját sem (vak scan) | A1 |
| A lejárat-ellenőrzés figyelmeztet, de 0-val lép ki | A2 |
| A replay-védelem csak az azonos időbélyegű ismétlést fogja | A3 |
| A feltöltés a fájlnevet normalizálás nélkül használja | A4 |
| A modell-ellenőrzés csak a fájl méretét nézi | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a `security_scan.py` titok-mintái közül azt, amelyikre a fixture illeszkedik, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/security_scan_test.dart test/tooling/check_secrets_test.dart
```

Backend sáv (külön processzként):

```bash
cd backend && python -m pytest tests/test_security_release.py tests/test_hardening.py -q
```

## 8. Implementációs sorrend

1. `docs/security/threat-model.md` (a Community-modell beemelésével).
2. `tool/release/security_scan.py` + a SZINTETIKUS ismert-rossz fixture.
3. `test/tooling/security_scan_test.dart` — a küszöb-cellahármassal.
4. `backend/tests/test_security_release.py`.
5. `docs/security/exceptions.yaml` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Vak scanner.** A mért L220 hibaosztály: a fixture nem illeszkedik a mintákra, és minden zöld (A1).
- **Kritikus lelet a termékkódban.** Ilyenkor `stopped` — a javítás önálló kör (§0.0).
- **A kivétel-nyilvántartás elfajulása.** Lejárat nélküli kivétel = a threat model kikapcsolása (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
