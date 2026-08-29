# E12-R15 — Audio, camera és local AI resource coexistence

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 15
- **Kör-azonosító:** `E12-R15`
- **Branch:** `<motor>/e12-r15-resource-coexistence-policy`
- **Előfeltétel:** `E12-R11` merge-elve (a coexistence-cellák az e2e harness determinisztikus profilját használják)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0476` — a foglalótól MÉRVE (`tools/round-slots.py reserve-adr --round E12-R15` → `0476`); a 2026-08-27-i batch `0455` placeholderje elavult, lásd §0.0 R1.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "resource coordinator microphone camera priority release leak"` → **[ADR 0056](../adr/0056-exclusive-microphone-session.md)** (kizárólagos mikrofon-session: BUSY hiba, NEM lopás) és **[ADR 0184](../adr/0184-vision-camera-capture-stack.md)** (kamera capture stack). A prioritási szerződés e KETTŐ közé illeszkedik, és egyiket sem írhatja felül.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/core/audio/lifecycle/audio_session_coordinator.dart` és a `lib/core/camera/camera_session_coordinator.dart` MÉRT lease-szemantikáját (mindkettőhöz van teszt: `test/core/audio/audio_session_coordinator_test.dart`, `test/core/camera/camera_session_coordinator_test.dart`). A kör ezek FÖLÉ tesz koordinációt, nem beléjük.

## 0.0 Pre-flight revízió (2026-08-29, `main @ c207f91a`) — MÉRT állítások, amelyek felülírják a 2026-08-27-i brief-szöveget

A brief előre íródott. Az alábbi hat pontot a pre-flight **kigrepelte a fából**;
ahol a régi szöveg mást mond, **ez a szakasz az érvényes**.

**Visszakeresés (ADR 0312, szűkítve előbb):**
`--corpus lessons,halts,adr "resource arbiter priority microphone camera background AI suspend not steal lease"`
→ [ADR 0056](../adr/0056-exclusive-microphone-session.md) (a második owner
kontrollált BUSY hibát kap, NEM lop — `acquire` `Failure(AudioFailure(code:
'audio.session_busy'))`), [ADR 0184](../adr/0184-vision-camera-capture-stack.md)
(a kamera lifecycle-elengedése route-leave és háttérbe váltás útján),
[L100](../LESSONS.md#l100)/[L19](../LESSONS.md#l19) (az erőforrás-tulajdonlást a
TÉNYLEGES hívási láncon kell mérni, nem a réteg-diagramon).
`--corpus lessons,halts "e2e test camera lease leak route leave full app tree guard low memory"`
→ [L513](../LESSONS.md#l513) (`testWidgets` fake-clock zónája alatt egy broadcast
`StreamController.close()` awaitolása SOSEM tér vissza — az erőforrás-elengedést
mérő cella emiatt fagy), [L449](../LESSONS.md#l449) (a shell életben tartja a
meglátogatott brancheket, ezért a birtokló képernyő sosem szabadul fel),
[L453](../LESSONS.md#l453) (egy csatorna-mock csak azt az EGY csatornát
bizonyítja). Teljes korpuszon: SDD Ch10 §10.2 (`LocalAiResourceCoordinator`
felülete — low-memory jelzés is ott van felsorolva).

### R1 — az ADR száma `0476`, nem `0455`

MÉRT: `tools/round-slots.py reserve-adr --round E12-R15` → **`0476`**; a lemezen
a legmagasabb ADR a `0474`, és `0455` alakú fájl **nem létezik**
(`ls docs/adr/ | grep -E '^04(5[0-9]|6[0-9])'` → az első találat `0466`). A
Chapter 12 batch-tervezés `0455` placeholderje sosem ment át a foglalón.
**Minden `0455`-hivatkozás `0476`-ra értendő.** Az ADR-t a Claude MEGÍRTA a
pre-flightban (`docs/adr/0476-resource-coexistence-priority-and-suspension-contract.md`);
a `docs/adr/**` az implementer tilos zónája marad.

### R2 — low-memory jelzés a fán NEM létezik: az A4 az arbiter SAJÁT API-jára mér

MÉRT: `grep -rni 'memorypressure|didHaveMemoryPressure|lowMemory|low_memory'
lib/ test/ --include=*.dart` → **0 találat**. A
`WidgetsBindingObserver.didHaveMemoryPressure` sehol nincs bekötve, és a
platform-csatorna érintése a §3 szerint TILOS.

Az A4 tehát az arbiter saját, szinkron belépési pontjára mér (pl.
`ResourceArbiter.onMemoryPressure()`) — **nem** platform-jelzésre, és **nem**
`WidgetsBinding`-bekötésre. A bekötés az arbiter FÖLÖTTI réteg dolga
(`lib/features/**` / app-lifecycle observer), ami a listán kívül esik → a
bekötés megkísérlése **H3**. Ezt az ADR 0476 D4 köti meg, és a
`docs/contracts/resource-coexistence.md`-nek ki KELL mondania, hogy a jelzés
forrása még nincs bekötve.

### R3 — az A3 a VALÓDI koordinátor állapotán mér, nem a valódi app-fán

MÉRT hívási lánc (`grep -rn '\.acquire(' lib/` — a teljes találati halmaz):

| Hely | Mit szerez meg |
|---|---|
| `lib/core/audio/mic_capture.dart:82` | `AudioSessionCoordinator.acquire` |
| `lib/features/vision/application/vision_session_controller.dart:157` | `CameraSessionCoordinator.acquire` |
| `lib/features/vision/application/vision_setup_controller.dart:163` | `CameraSessionCoordinator.acquire` |

Mindhárom hívó **KÖZVETLENÜL** a koordinátort hívja, és mindhárom a kör tilos
zónájában van. Az arbiter tehát ebben a körben egyetlen képernyőre sincs
bekötve — **egy valódi `StrumSightApp`-fát bejáró teszt az arbiterből semmit nem
mérne**, csak a már meglévő koordinátor-viselkedést (amit a §7 gate amúgy is
futtat, A6).

Az A3 mérendő állítása ezért **pontosítva** (szűkítés, nem gyengítés): egy
arbiteren regisztrált kamera-fogyasztó route-leave/háttérbe-váltás szekvenciája
után a **VALÓDI `CameraSessionCoordinator`** legyen szabad —
`coordinator.activeOwner == null` **és** a kiadott `lease.isActive == false`.
A cella a valódi koordinátort példányosítja (nem mockolt `MethodChannel`-t,
[L453](../LESSONS.md#l453)), és a `test/e2e/resource_coexistence_test.dart`
útvonalon marad (a listán ez az útvonal szerepel).

**Fagyás-csapda ([L513](../LESSONS.md#l513)):** ha a cella `testWidgets`-et
használ, a `FakeCameraCapture.close()` (broadcast `StreamController.close()`)
Future-jét **TILOS awaitolni** — a fake-clock zónában sosem tér vissza, és a
cella nem hibázik, hanem a `flutter test` saját időkorlátjáig blokkol. Sima
`test()` cellában ez a csapda nem áll fenn; a §8 sorrendje ezért sima
`test()`-et javasol, `testWidgets` csak akkor, ha a widget-fa tényleg kell.

### R4 — az arbiter eredménye SAJÁT típus: új `FailureCode` konstans TILOS

MÉRT: a `FailureCode` egyetlen forrása
`lib/core/foundation/app_failure.dart` (abstract final class, `audioSessionBusy
= 'audio.session_busy'` a 39. soron, `cameraSessionBusy = 'camera.session_busy'`
az 56. soron) — és ez a fájl **NINCS** az engedélyezett listán. Az arbiter tehát
`lib/core/resources/**`-lokális, zárt eredménytípust ad vissza explicit
indok-értékkel (ADR 0476 D5); új hiba-sztringet nem talál ki, és a két
koordinátor BUSY-kódját nem duplikálja.

### R5 — `lib/core/` nem importálhat `lib/features/`-t (gépi kapu)

MÉRT: `tool/check_architecture.dart:332-339` — `coreMustNotImportFeatures`. Az
arbiter a fogyasztókat kizárólag a `ResourceConsumer` szerződésen keresztül
ismerheti. Ezt a `tools/round-gate.sh` `architecture` lépése méri
(`round-gate.sh:232-233`).

### R6 — a §6.1 mérce-mátrix két sorral bővül

Az R2/R3 pontosítás miatt a falszifikációs mátrix (§6.1) kiegészül a
„felfüggesztés helyett lease-elvétel a KAMERÁN" és a „memória-nyomás nem
rendezetten szabadít fel" sorokkal — lásd a frissített §6.1 táblát.

## 0.0.1 Az Offline AI ága MA nem létezik

A SDD Kör 15 „Analyze + local AI" és „AI cancellation" eseteket is kér. Az Epic 10 (Offline AI) sávja `hold`-on áll, tehát a fán MA nincs helyi AI-futtató. A kör ezért a helyi AI-t **absztrakt fogyasztóként** modellezi (`ResourceConsumer` szerződés + fake), és a valódi bekötés az Epic 10 Kör 12 (`e10-r12-local-ai-resource-coordinator.md`) dolga marad. A §5.3 ezt köti meg, hogy a két kör ne írjon egymásra.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/resources/resource_priority.dart",
  "lib/core/resources/resource_consumer.dart",
  "lib/core/resources/resource_arbiter.dart",
  "lib/core/resources/public.dart",
  "test/core/resources/resource_arbiter_test.dart",
  "test/e2e/resource_coexistence_test.dart",
  "docs/contracts/resource-coexistence.md",
  "docs/rounds/e12-r15-resource-coexistence-policy.md",
]
gate_tests = [
  "test/core/resources/resource_arbiter_test.dart",
  "test/e2e/resource_coexistence_test.dart",
  "test/core/audio/audio_session_coordinator_test.dart",
  "test/core/camera/camera_session_coordinator_test.dart",
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

**STOP-protokoll:** ha a koordináció bekötése az `audio_session_coordinator.dart` vagy a `camera_session_coordinator.dart` MÓDOSÍTÁSÁT igényelné, a kimenet a `stopped` jelzés — azok ADR 0056/0184 szerződései, és a listán nincsenek rajta.

## 1. Cél

Kimondott, tesztelt prioritási szerződés az egyszerre versengő erőforrás-fogyasztók (mikrofon, kamera, helyi AI) között — leak és néma elakadás nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/core/audio/lifecycle/`: `audio_session_coordinator.dart`, `audio_session_lease.dart`, `audio_lifecycle_guard.dart` — a mikrofon MA kizárólagos, a második kérő BUSY hibát kap (ADR 0056: „busy failure, not steal").
- `lib/core/camera/`: `camera_session_coordinator.dart`, `camera_session_lease.dart`, `camera_lifecycle_guard.dart` — ugyanaz a lease-minta.
- `lib/core/resources/` **nem létezik**; a két koordinátor MA nem tud egymásról.
- A vision termál-adapter (`thermal_state_adapter.dart`) és a device-tier (ADR 0196) MÁR ad degradációs létrát a kamerás ágon.
- `test/e2e/` a Kör 11 után létezik.

## 3. Scope

**Benne van:** `resource_priority.dart` (rendezett prioritás: élő tanulási hang > kamera-alapú visszajelzés > háttér-AI) · `resource_consumer.dart` (szerződés: `acquire`, `release`, `pauseForHigherPriority`) · `resource_arbiter.dart` (a MEGLÉVŐ két koordinátor FÖLÉ tett döntő; a lease-eket nem veszi el, hanem a kérés SORRENDJÉT és a háttér-fogyasztó felfüggesztését szabályozza) · `test/core/resources/resource_arbiter_test.dart` · `test/e2e/resource_coexistence_test.dart` (Live + kamera, háttérbe váltás, low-memory jelzés) · `docs/contracts/resource-coexistence.md`.

**NINCS benne (tilos):**

- A két meglévő koordinátor vagy lease módosítása (ADR 0056/0184).
- Valódi helyi AI-futtató bekötése (Epic 10 Kör 12 területe).
- Platform-csatorna vagy natív kód érintése.
- `docs/adr/**` — az ADR 0476-ot a Claude írja (a pre-flightban MEGÍRVA).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/resources/resource_priority.dart` | ÚJ — a prioritási rend |
| `lib/core/resources/resource_consumer.dart` | ÚJ — a fogyasztói szerződés |
| `lib/core/resources/resource_arbiter.dart` | ÚJ — a döntő |
| `lib/core/resources/public.dart` | ÚJ — barrel |
| `test/core/resources/resource_arbiter_test.dart` | a §6 cellái |
| `test/e2e/resource_coexistence_test.dart` | a folyam-cellák |
| `docs/contracts/resource-coexistence.md` | ÚJ — a szerződés leírása |

**Tilos zóna:** `lib/core/audio/**` · `lib/core/camera/**` · `lib/features/**` · `android/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0476)

### 5.1 Az arbiter NEM lop lease-t

A magasabb prioritású kérés a háttér-fogyasztót FELFÜGGESZTI vagy elutasítja az újat; egy már kiadott mikrofon-lease elvétele TILOS (ADR 0056). **NEM elfogadható gyengítés:** „preempt" mód bevezetése a Live-élmény javítására.

### 5.2 A felfüggesztett fogyasztó állapota nem vész el

`pauseForHigherPriority` után a fogyasztó folytatható; a félbehagyott munka nem tűnik el csendben. **NEM elfogadható gyengítés:** `cancel` hívása `pause` helyett, mert „egyszerűbb".

### 5.3 A helyi AI absztrakt fogyasztó marad ebben a körben

**NEM elfogadható gyengítés:** az Epic 10 tervezett API-jának előre-implementálása — a két kör így egymásra írna, és a `hold`-on álló sáv szerződése még nem végleges.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Élő hang kérése mellett a háttér-AI fogyasztó FELFÜGGESZTŐDIK (nem törlődik) | `resource_arbiter_test.dart` |
| A2 | Kiadott mikrofon-lease-t az arbiter NEM vesz el; a második kérő BUSY-t kap | `resource_arbiter_test.dart` + a meglévő audio-koordinátor teszt |
| A3 | Egy arbiteren regisztrált kamera-fogyasztó route-leave/háttérbe-váltás után felszabadítja a VALÓDI `CameraSessionCoordinator`-t: `activeOwner == null` ÉS `lease.isActive == false` (nincs leak) — §0.0 R3 | `resource_coexistence_test.dart` |
| A4 | Az arbiter SAJÁT memória-nyomás belépési pontjára (`onMemoryPressure()`, §0.0 R2) a legalacsonyabb prioritású AKTÍV fogyasztó áll le először, és a legmagasabb prioritású aktív marad futásban | `resource_arbiter_test.dart` |
| A5 | Felfüggesztés után a fogyasztó folytatható, az állapota megmarad | `resource_arbiter_test.dart` |
| A6 | A meglévő audio- és kamera-koordinátor tesztek VÁLTOZATLANUL zöldek | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az arbiter elveszi a kiadott mikrofon-lease-t | A2 |
| A `pauseForHigherPriority` valójában `cancel`-t hív | A5 |
| Low-memory esetén a legmagasabb prioritású fogyasztó áll le | A4 |
| A kamera-lease a képernyő elhagyása után nyitva marad | A3 |
| Az arbiter a KAMERA oldalán is elvesz: `CameraSessionCoordinator.revokeActive()`-ot hív a magasabb prioritású kérés kiszolgálására | A3 (a felfüggesztett fogyasztó lease-e is aktív marad → az A3 „szabad koordinátor" állítása és az A5 folytathatóság egyszerre bukik) |
| A memória-nyomás MINDEN fogyasztót leállít (nem rendezetten) | A4 (a legmagasabb prioritású aktív fogyasztónak futásban kell maradnia) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** cseréld az arbiter felfüggesztés-ágát lease-elvételre, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/resources/resource_arbiter_test.dart test/e2e/resource_coexistence_test.dart test/core/audio/audio_session_coordinator_test.dart test/core/camera/camera_session_coordinator_test.dart
```

## 8. Implementációs sorrend

1. `resource_priority.dart` + `resource_consumer.dart`.
2. `resource_arbiter.dart` — a MEGLÉVŐ koordinátorok fölé, azok módosítása NÉLKÜL.
3. `resource_arbiter_test.dart` (A1, A2, A4, A5).
4. `test/e2e/resource_coexistence_test.dart` (A3).
5. `docs/contracts/resource-coexistence.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A lease-lopás bevezetése.** ADR 0056 közvetlen sértése, és a valós hatása néma mikrofon-elvétel gyakorlás közben (A2).
- **Kamera-leak.** A mért hibaosztály a repóban létezik ([L453](../LESSONS.md#l453): egy csatorna mockolása nem bizonyítja a nem-nyitást) — az A3 cella teljes-app folyamon mérjen.
- **Előre-implementálás az Epic 10 helyett.** Kettős szerződés, később ütköző merge (§5.3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
