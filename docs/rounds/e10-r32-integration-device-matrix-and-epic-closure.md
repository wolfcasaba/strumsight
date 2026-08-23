# E10-R32 — Teljes integráció, device matrix, rollout és Epic lezárás

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: az egész epic minden valós-hardver/valós-modell tartozásának lezárását feltételezi**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 32 (ZÁRÓ KÖR)
- **Kör-azonosító:** `E10-R32`
- **Branch:** `<motor>/e10-r32-integration-device-matrix-and-epic-closure`
- **Előfeltétel:** MINDEN korábbi E10 kör (6, 7, 13, 27, 28, 29 is) VALÓS eredménnyel lezárva
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — audit-only záró kör, nem köt új architekturális döntést (a Kör 32 összegzi a korábbi ADR-eket).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "epic closure completion report device matrix full suite"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold`

Ez a ZÁRÓ kör az összes korábbi HOLD-kör (6 bake-off, 7 runtime-ADR, 13 natív lifecycle, 27 thermal, 28 crash-recovery, 29 model-export) VALÓS, kész eredményét feltételezi bemenetként — device matrix benchmark, signed package E2E flow, bilingual quality gate a RELEASE CANDIDATE csomagon, repülőgépes-módú local-only teszt VALÓDI eszközön. Amíg BÁRMELYIK előd hold-on van, ez a kör tárgy nélküli.

**Mi oldja fel:** minden előd VALÓS lezárása, majd egy dedikált emberi/QA jóváhagyású device-teszt forduló.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/sdd/epic-10-completion-report.md",
  "docs/support/local-ai-device-matrix.md",
  "docs/privacy/offline-ai.md",
  "HANDOFF.md",
  "README.md",
  "docs/rounds/e10-r32-integration-device-matrix-and-epic-closure.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
]
native_gate = true
```

**Kockázat = high, indoklás:** ez a kör az EGÉSZ Epic 10 production-readiness ítéletét hordozza — a `privacy`/`safety` kategóriák mindegyikét lefedi a végső ellenőrzés szintjén.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

Az Epic lezárásakor a teljes local-tutor útvonalat, modellcsomagot, device-támogatást és fallbacket VALÓS készüléken kell igazolni, és a dokumentációt a tényleges release-állapotra frissíteni.

## 2. Jelenlegi állapot — mért tények

- Ez a brief a batch-prep pillanatában (2026-08-22) NEM tud "jelenlegi állapotot" mérni a Kör 6-31 eredményéből, mert azok jövőbeliek — a TÉNYLEGES pre-flight (amikor ez a kör aktiválódik) újramér mindent.

## 3. Scope

**Benne van:** teljes Flutter/backend/natív/architecture tesztcsomag · signed package end-to-end install/verify/activate/generate/rollback/delete flow · bilingual quality gate a release candidate csomagon · device matrix benchmark + támogatási tábla · repülőgépes módú local-only teszt hálózati interceptorral, VALÓDI eszközön · Practice/Song/Analyze utáni debrief teszt · tool preview/confirmation flow teszt · mic/camera resource conflict, thermal stop, low-memory, process-death recovery teszt · README/AGENTS/HANDOFF/model-card/privacy-dokumentáció/SDD-index frissítés · `docs/sdd/epic-10-completion-report.md` · csak a megfelelt compact package kerül első stable rolloutba.

**NINCS benne (tilos):**

- Új funkció bevezetése — ez tisztán audit- és dokumentáció-záró kör.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — a kör a Kör 1-31 összes ADR-jét auditálja, nem ír felül egyet sem

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A teljes tesztcsomag (Flutter+backend+natív+architecture) zöld | CI-run link |
| A2 | Signed package E2E flow sikeres VALÓS eszközön | `docs/support/local-ai-device-matrix.md` |
| A3 | Bilingual quality gate teljesül a release candidate-en | `local_ai/evaluation/reports/` |
| A4 | Repülőgépes módban helyi kérdésre ZÉRÓ hálózati kérés (interceptor bizonyítja) | instrumentation teszt |
| A5 | Device matrix legalább a SDD §21.5 kategóriáit lefedi | `docs/support/local-ai-device-matrix.md` |
| A6 | A dokumentáció (README/AGENTS/HANDOFF) a TÉNYLEGES release-állapotot tükrözi | review — dokumentum-audit |
| A7 | Csak a compact package aktiválható első stable rolloutban; standard/tool-calling külön kapu mögött | feature-flag audit |

### 6.1 Falszifikációs próba (záró, audit-jellegű kör)

A falszifikáció a **reviewer eldobható próbája**: a reviewer VÉLETLENSZERŰEN kiválaszt három acceptance-pontot (A1-A7 közül), és MAGA reprodukálja a mögöttes mérést egy FÜGGETLEN eszközön/futtatásban — ha bármelyik eltér a jelentettől, a kör CHANGES REQUESTED.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
flutter test
flutter test test/property
dart run tool/check_architecture.dart
cd backend && python -m pytest -q
cd android && ./gradlew test && ./gradlew connectedAndroidTest
cd local_ai && python -m pytest -q
```

A teljes performance/thermal acceptance KIZÁRÓLAG a dokumentált valós eszközmátrixon tekinthető sikeresnek (SDD §27).

## 8. Implementációs sorrend

1. A teljes tesztcsomag futtatása és eredményének rögzítése.
2. Signed package E2E flow VALÓS eszközön.
3. Bilingual quality gate a release candidate-en.
4. Device matrix benchmark + tábla.
5. Repülőgépes-módú, resource-conflict, thermal, low-memory, process-death tesztek.
6. `docs/sdd/epic-10-completion-report.md` + a dokumentáció-frissítések.
7. Az első stable rollout kapujának beállítása (compact-only).

## 9. Kockázatok

- **A hamis "kész" jelentés.** Ha bármelyik korábbi HOLD-kör eredménye valójában nem VALÓS mérés, ez a kör azt örökölné és terjesztené tovább — a §6.1 reviewer-reprodukció ez ellen véd.
- **A standard/tool-calling korai rolloutja.** A SDD explicit csak a compact package-et engedi az első stable rolloutba (A7).
- **A dokumentáció elmaradása a kódtól.** README/AGENTS/HANDOFF elavulása megtévesztené a jövőbeli fejlesztőket a tényleges état-ról.

## 10. Implementation handoff — az implementer tölti ki (a teljes epic VALÓS lezárása után)

## 11. Review — a Claude tölti ki
