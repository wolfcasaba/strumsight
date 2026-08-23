# E10-R27 — Performance, thermal és battery policy implementáció

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`) — **`hold`: valódi natív Android thermal/memory integráció, a Kör 13 native lifecycle-ra épül**
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 27
- **Kör-azonosító:** `E10-R27`
- **Branch:** `<motor>/e10-r27-performance-thermal-and-battery-policy`
- **Előfeltétel:** `E10-R13` (natív lifecycle) VALÓS eszközön lezárva
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0440` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "thermal policy battery saver generation performance"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

## 0.0 MIÉRT `hold`

A kör CORE deliverable-je "Integráld az Android thermal status eventeket" (SDD 27.2) és a "repeated-turn thermal instrumentation teszt" (27.5) — ezek VALÓS Android thermal API-t és VALÓS, ismételt generálást igénylő méréseket jelentenek natív eszközön, a Kör 13 (`hold`) natív service-rétegére építve. A Dart-oldali POLICY (tier→max-context/output/backend leképezés) önmagában FAKE thermal/memory bemenettel is tesztelhető lenne, DE a kör címe és fő értéke ("enforce device health generation policies") csak a VALÓS integrációval bizonyítható — egy pusztán Dart-oldali, fake-bemenetű verzió üres/hamis biztonságérzetet adna erről a rendkívül biztonságkritikus rétegről (thermal runaway, OOM).

**Mi oldja fel:** a Kör 13 lezárása VALÓS eszközön, majd emberi/CI-infra megerősítés natív instrumentation-teszt futtatási képességről.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/offline_ai/application/generation_performance_policy.dart",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/ThermalMonitor.kt",
  "android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/DeviceMemoryProbe.kt",
  "android/app/src/androidTest/java/com/wolfcasaba/strumsight/localai/",
  "docs/rounds/e10-r27-performance-thermal-and-battery-policy.md",
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

## 1. Cél

A production runtime alkalmazza a capability-tierből származó output-, backend- és erőforrásprofilt, VALÓS thermal/memory jelzésekre reagálva.

## 2. Jelenlegi állapot — mért tények

- A Kör 11 Dart-oldali tier-resolvere (fake bemenettel) MÁR MEGVAN — ez a kör a VALÓS natív thermal/memory forrást köti be mögé.
- A Kör 12 `LocalAiResourceCoordinator` a Dart-oldali fogyasztó — ez a kör adja a VALÓS bemenetet neki.

## 3. Scope

**Benne van:** szöveg NÉLKÜLI generation performance monitor · VALÓS Android thermal status event integráció, konzervatív fallback (nincs API → konzervatív, nem "hideg") · tierhez kötött max context/output/backend profil · battery saverben compact/deterministic ajánlás · repeated-turn thermal instrumentation teszt VALÓS eszközön · cancellation mérése prefill/decode fázisban · memory headroom guard generálás előtt/közben · severe/critical thermal esetben kontrollált leállítás/tiltás.

**NINCS benne (tilos):**

- A Dart-oldali policy-VÁZ módosítása (Kör 12 fájlja) — csak a natív FORRÁS bekötése.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

## 5. Kötött architekturális döntések (ADR 0440)

### 5.1 Hiányzó/hibás thermal API SOSEM jelent automatikus "hideg" állapotot

Konzervatív policy lép életbe (mint a normál `moderate` állapot), nem az optimista `none/light`.

### 5.2 Critical thermal állapotban az AKTÍV generálás megszakad, nem csak az új tiltott

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Thermal állapot-átmenetek (none→moderate→severe→critical→emergency) VALÓS eszközön mérve, minden szinthez helyes policy-válasz | VALÓS instrumentation teszt |
| A2 | Battery saver esetén compact/deterministic javaslat | instrumentation teszt |
| A3 | Memory headroom guard megtagadja a generálást elégtelen memória esetén | instrumentation teszt |
| A4 | Critical thermal esetben az AKTÍV generálás megszakad | instrumentation teszt |
| A5 | Cancellation latency mérve prefill és decode fázisban külön | VALÓS eszközön mért riport |
| A6 | Nincs promptszöveg a performance-logban | instrumentation teszt |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a hiányzó-thermal-API ágat optimista `none`-ra, futtasd a tesztet → az érintett cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
cd android && ./gradlew connectedAndroidTest
```

A `gate_tests` regresszió-őre (Kör 1 óta stabil feature-flag teszt) a `tools/round-gate.sh`-on át bizonyítja, hogy a natív munka nem érintett véletlenül Flutter-oldali kódot:

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart
```

## 8. Implementációs sorrend

1. `ThermalMonitor.kt`/`DeviceMemoryProbe.kt` — VALÓS natív probe-ok.
2. `generation_performance_policy.dart` bekötése a valós forráshoz (a Kör 12 fake-jét lecserélve).
3. Repeated-turn thermal instrumentation teszt.
4. Memory headroom guard.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A thermal runaway.** A legdrágább hibaosztály fizikailag (eszköz-túlmelegedés) — ez a kör az utolsó védelmi vonal (A1/A4).
- **Az optimista hiányzó-API fallback.** Ismeretlen platformon veszélyes generálást engedne (5.1).
- **A memória-headroom alábecslése.** OOM-ot okozna éles használat közben (A3).

## 10. Implementation handoff — az implementer tölti ki (VALÓS eszköz-hozzáférés után)

## 11. Review — a Claude tölti ki
