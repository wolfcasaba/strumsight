# E10-R28 — App lifecycle, low-memory és crash recovery

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: valódi natív Android lifecycle/process-recreation teszt, a Kör 13/27-re épül**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 28
- **Kör-azonosító:** `E10-R28`
- **Branch:** `<motor>/e10-r28-lifecycle-and-crash-recovery`
- **Előfeltétel:** `E10-R27` VALÓS eszközön lezárva
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0441` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "app lifecycle low memory crash recovery draft persistence"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold`

A kör core deliverable-je natív `onTrimMemory`, service-connection helyreállítás, orientation/activity/process-recreation tesztelés — mindegyik VALÓS Android lifecycle-eseményt igényel (`android/app/src/androidTest/`), amit csak fizikai/emulált eszközön lehet hitelt érdemlően kiváltani és mérni. Ugyanaz a natív-infrastruktúra korlát, mint Kör 6/7/13/27-nél.

**Mi oldja fel:** a Kör 13/27 lezárása VALÓS eszközön, majd emberi/CI-infra megerősítés natív instrumentation-teszt futtatási képességről.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/application/local_ai_lifecycle_controller.dart",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiServiceConnection.kt",
  "test/features/offline_ai/lifecycle/",
  "android/app/src/androidTest/java/com/wolfcasaba/strumsight/localai/",
  "docs/rounds/e10-r28-lifecycle-and-crash-recovery.md",
]
gate_tests = [
  "test/features/offline_ai/lifecycle/",
]
native_gate = true
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A modellprocess és conversation controller kezelje az app pause/resume, process death, low-memory és natív crash helyzeteket adatvesztés nélkül.

## 2. Jelenlegi állapot — mért tények

- A Kör 13 natív service-rétege és a Kör 23 gateway adja az alapot, amire ez a kör a lifecycle-védelmet építi.
- A Kör 17 `tutor_memory_compactor.dart` adja a perzisztencia-réteget a draft mentéshez.

## 3. Scope

**Benne van:** background-be kerüléskor nincs új generálás, aktív generálás policy szerint cancel/grace-cancel · `onTrimMemory` szintek kezelése, unload policy · külön-process service-connection helyreállítás, folyamatban lévő kérés `failed`-re jelölése · félbeszakadt tokenstream NEM folytatódik vakon · user draft és validált assistant blockok tranzakciós mentése · ismételt runtime crash után karantén/rollback (a Kör 10 mechanizmusát hívva) · recovery banner/retry UI state · orientation change, activity recreation, full process recreation VALÓS tesztje.

**NINCS benne (tilos):**

- A Kör 10 rollback-mechanizmus módosítása — csak HÍVJA.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0441)

### 5.1 Félbeszakadt tokenstream SOSEM folytatódik vakon — mindig új, tiszta generálási kísérlet vagy explicit hibaállapot

### 5.2 A user draft SOSEM vész el process-death esetén

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Background-be kerüléskor az aktív generálás policy szerint cancel-elődik | VALÓS instrumentation teszt |
| A2 | `onTrimMemory` kritikus szinten a modell unload-olódik | instrumentation teszt |
| A3 | Service-death után a folyamatban lévő kérés kontrolláltan `failed` | instrumentation teszt |
| A4 | Process recreation után a user draft visszaáll | instrumentation teszt |
| A5 | Ismételt (3×) crash után a package karanténba kerül (Kör 10 hívva) | instrumentation teszt |
| A6 | Orientation change nem indít duplikált generálást vagy árva streamet | instrumentation teszt |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a draft-mentést process-death szimuláció előtt, futtasd a tesztet → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
cd android && ./gradlew connectedAndroidTest
tools/round-gate.sh test/features/offline_ai/lifecycle
```

## 8. Implementációs sorrend

1. `local_ai_lifecycle_controller.dart` — background/trim-memory/draft-mentés Dart-oldali logika.
2. `LocalAiServiceConnection.kt` — natív reconnect.
3. A karantén/rollback bekötése (Kör 10 hívása).
4. Recovery banner/retry UI.
5. VALÓS eszközön: orientation/activity/process recreation tesztek.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A draft-adatvesztés.** A felhasználó frusztrációjának legvalószínűbb forrása egy crash után (A4, 5.2).
- **A ghost "generating" állapot.** Egy nem kezelt service-death a UI-t örökre "gondolkodik" állapotban hagyhatja (A3).
- **A vak stream-folytatás.** Korrupt vagy duplikált szöveget eredményezhetne (5.1).

## 10. Implementation handoff — az implementer tölti ki (VALÓS eszköz-hozzáférés után)

## 11. Review — a Claude tölti ki
