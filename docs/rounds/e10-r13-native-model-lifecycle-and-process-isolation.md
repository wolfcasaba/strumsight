# E10-R13 — Natív modell lifecycle és process isolation

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: teljes egészében natív Android, valódi eszközön tesztelendő**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 13
- **Kör-azonosító:** `E10-R13`
- **Branch:** `<motor>/e10-r13-native-model-lifecycle-and-process-isolation`
- **Előfeltétel:** `E10-R07` (natív plugin skeleton) VALÓS Android build-del lezárva
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0428` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "native service process isolation binder death reconnect"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold`

Ez a kör TELJES EGÉSZÉBEN natív Kotlin kód (`LocalAiService.kt`, `LocalAiRuntimeFacade.kt`, `SelectedRuntimeAdapter.kt`) + `androidTest` instrumentáció — nincs értelmes Dart-oldali leválasztás, mert a kör LÉNYEGE maga a natív réteg (UI-thread-mentesség, single-flight load, Binder death/reconnect, process isolation). Ehhez:

1. natív Android build- és tesztfuttatási képesség kell (ezen a dev boxon nincs Android SDK; a CI ma csak `flutter build apk`-t futtat, `connectedAndroidTest`-et nem);
2. a Kör 7 (`hold`) VALÓS, buildelt `RuntimeAdapter`/`FakeRuntimeAdapter` alapja;
3. 20 egymást követő load/unload ciklus VALÓDI eszközön mért memória-visszaadási bizonyítéka (SDD §21.4/13.7) — ez elvi lehetetlenség emulátor vagy szimuláció alapján hitelesen.

**Mi oldja fel:** a Kör 7 lezárása VALÓS build-del, és emberi/CI-oldali megerősítés natív instrumentation-teszt futtatási képességről (akár egy jövőbeli, a felhasználó által jóváhagyott device-farm CI job, akár egy human-in-the-loop session).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiService.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiRuntimeFacade.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/runtime/SelectedRuntimeAdapter.kt",
  "android/app/src/androidTest/java/com/wolfcasaba/strumsight/localai/",
  "docs/rounds/e10-r13-native-model-lifecycle-and-process-isolation.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
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

**Ha ezt a kört mégis dispatch-elnék natív build/teszt-futtatás nélkül:** az implementer ELSŐ lépése a `./gradlew connectedAndroidTest --dry-run` (vagy ekvivalens elérhetőség-ellenőrzés) futtatása. Ha nincs csatlakoztatott eszköz/emulátor, AZONNAL `tools/codex-signal.sh blocked "nincs natív teszt-futtatási képesség — emberi/CI infra szükséges"`.

## 1. Cél

A kiválasztott runtime load/unload/session kezelése legyen explicit, szálbiztos és natív crash esetén helyreállítható.

## 2. Jelenlegi állapot — mért tények

- A Kör 7 `RuntimeAdapter` interfészt és `FakeRuntimeAdapter`-t ad — ez a kör a PRODUCTION `SelectedRuntimeAdapter`-t implementálja rá.
- A Kör 12 (`local_ai_resource_coordinator.dart`) Dart-oldali lease-mechanizmusa a bemenete: a natív réteg csak lease birtokában fogadhat generálási kérést (a natív oldal ezt egy platform-message flagként kapja).

## 3. Scope

**Benne van:** production `RuntimeAdapter` load/warmup/create-session/reset/unload · generálás UI/main threaden KÍVÜL · single-flight model load · in-process VAGY külön-process service (a Kör 7 ADR 0422 döntése szerint) · Binder death/reconnect és generation-failure mapping külön process esetén · natív resource ownership diagram és close-sorrend dokumentáció · repeated load/unload ciklusban memória-visszaadás mérése VALÓDI eszközön.

**NINCS benne (tilos):**

- A tokenstream Flutter-oldali fogyasztása — ez Kör 14 dolga.
- Bármilyen döntés a runtime kiválasztásáról — az a Kör 7 ADR-je, ez a kör csak IMPLEMENTÁLJA.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**Tilos zóna:** `lib/**` (ez a kör tisztán natív; a Flutter-oldali fogyasztás Kör 14/23 dolga) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0428)

### 5.1 A generálás SOSEM fut UI/main threaden

Minden inference-hívás dedikált háttérszálon vagy külön processben fut; a natív kód explicit assertiont tartalmaz erre (debug build-ben).

### 5.2 Egyszerre legfeljebb egy aktív load és egy aktív generálás

Single-flight garancia: párhuzamos load-hívás ugyanarra a modellre a folyamatban lévő műveletre várakozik, nem indít másodikat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A generálás sosem fut a UI threaden (debug assertion aktiválva) | `LocalAiServiceInstrumentedTest` |
| A2 | Kétszeri egyidejű load ugyanarra a modellre nem indít két betöltést | `LocalAiServiceInstrumentedTest` |
| A3 | Kétszeri unload nem crashel | `LocalAiServiceInstrumentedTest` |
| A4 | Binder death után a service reconnect és a folyamatban lévő kérés kontrolláltan failed | `LocalAiServiceInstrumentedTest` (külön-process esetén) |
| A5 | 20 egymást követő load/unload ciklus után a memória a kiindulási szinthez közeli (nincs monoton növekedés) | VALÓS eszközön mért riport, `docs/benchmarks/` |
| A6 | Natív exception kontrollált `LocalAiFailure`-ra map-elt, nem app-crash | `LocalAiServiceInstrumentedTest` |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** indíts egy generálást explicit a main threadről (ideiglenes teszt-módosítás), futtasd az instrumentation tesztet → az **A1** cellának PIROSNAK kell lennie (a debug assertion elkapja) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
cd android && ./gradlew connectedAndroidTest
```

VALÓS csatlakoztatott eszközön vagy emulátoron. A `native_gate = true`, a CI-terv `build-apk.yml`-t választ. A `gate_tests` regresszió-őre (Kör 1 óta stabil feature-flag teszt) a `tools/round-gate.sh`-on át bizonyítja, hogy a natív munka nem érintett véletlenül Flutter-oldali kódot:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `SelectedRuntimeAdapter.kt` — a Kör 7 ADR szerinti runtime SDK becsomagolása.
2. `LocalAiRuntimeFacade.kt` — load/warmup/session/reset/unload, single-flight garancia.
3. `LocalAiService.kt` — in-process vagy külön-process architektúra a Kör 7 döntése szerint.
4. Binder death/reconnect kezelés (ha külön process).
5. 20-ciklusos memória-teszt VALÓS eszközön.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A UI thread blokkolása.** Ha egy jövőbeli refaktor véletlenül main threadre tolja az inference-t, a teljes app befagyna (A1).
- **A memória vissza nem adása.** Ismételt load/unload ciklusok monoton növekvő memóriát okozhatnak, ha a natív erőforrások nem szabadulnak fel (A5).
- **A Binder death csendes elnyelése.** Egy elveszett kapcsolat, ami nem jelez hibát, a Flutter oldalon örökké "generating" állapotban ragadt UI-t eredményezne.

## 10. Implementation handoff — az implementer tölti ki (VALÓS eszköz-hozzáférés után)

## 11. Review — a Claude tölti ki
