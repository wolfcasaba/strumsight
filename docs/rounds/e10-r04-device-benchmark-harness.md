# E10-R04 — Device benchmark harness és mérési schema

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 4
- **Kör-azonosító:** `E10-R04`
- **Branch:** `<motor>/e10-r04-device-benchmark-harness`
- **Előfeltétel:** `E10-R03` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a mérési schema önmagában nem köt architekturális döntést; az ADR-igényes runtime-választás a Kör 6/7 dolga.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "device benchmark harness percentile aggregation report"` → nincs releváns előzmény (a találatok más domain hibaosztályai) — ez a kör a projekt ELSŐ ilyen jellegű infrastruktúrája, a §5/§9 saját tervezésére támaszkodik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/core/ai/` és
> `lib/features/offline_ai/` TÉNYLEGES tartalmát (a Kör 2/3 hozta létre) — az
> új benchmark modellek ide illeszkednek, nem önálló domainbe. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Hardver-korlát (batch-prep megjegyzés, KÖTELEZŐ figyelembe venni indításkor)

Ez a doboz (a fejlesztői/CI környezet) **nem rendelkezik Android SDK-val, emulátorral vagy fizikai eszközzel**, és a `.github/workflows/**` (ahol egy jövőbeli `connectedAndroidTest` job élne) a projekt védett zónája — egy autonóm kör nem nyithatja meg. A SDD Kör 4 eredeti fájllistája `android/app/src/androidTest/`-et is tartalmazza; ez a brief **szándékosan kihagyja** az `allowed_paths`-ból. Ez a kör kizárólag a **hordozható, futtatható mérési sémát és a jelentés-összesítőt** szállítja (Dart modellek + `tool/local_ai_benchmark_report.dart`), FIXTURE mintaadatokkal tesztelve — a tényleges on-device mérés futtatása a Kör 6 (bake-off, `hold`) és a Kör 32 (device matrix, `hold`) emberi jóváhagyású dolga.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/ai/benchmark/benchmark_scenario.dart",
  "lib/core/ai/benchmark/benchmark_sample.dart",
  "lib/core/ai/benchmark/benchmark_summary.dart",
  "lib/core/ai/benchmark/benchmark_environment.dart",
  "tool/local_ai_benchmark_report.dart",
  "test/core/ai/benchmark/benchmark_summary_test.dart",
  "test/core/ai/benchmark/benchmark_report_test.dart",
  "docs/rounds/e10-r04-device-benchmark-harness.md",
]
gate_tests = [
  "test/core/ai/benchmark/benchmark_summary_test.dart",
  "test/core/ai/benchmark/benchmark_report_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Közös, verziózott mérési séma és jelentés-összesítő, amellyel BÁRMELY jövőbeli runtime/modell-jelölt eredménye azonos módon rögzíthető és összehasonlítható — anélkül, hogy ez a kör valódi eszközön futna.

## 2. Jelenlegi állapot — mért tények

- `lib/core/ai/` a Kör 2 hozza létre (domain value objectek) — ez a kör bővíti egy `benchmark/` alkönyvtárral, nem hoz létre új top-level domaint.
- A projektben MA nincs semmilyen benchmark-aggregációs kód sem `lib/`, sem `tool/` alatt — ez teljesen új infrastruktúra.
- A `tool/` könyvtár MA a Flutter CLI-eszközöket tartja (`tool/check_architecture.dart`, `tool/ci/*`) — az új `local_ai_benchmark_report.dart` ugyanide illeszkedik, hasonló CLI-jelleggel (bemenet: JSON minták, kimenet: összehasonlító report).

## 3. Scope

**Benne van:** `BenchmarkScenario`, `BenchmarkSample`, `BenchmarkSummary`, `BenchmarkEnvironment` immutable value objectek · percentilis- és átlagszámítás (TTFT, decode tok/s, cold/warm load, peak memory, cancellation latency, thermal delta) · JSON szerializáció és validáció · `nonRepresentativePerformance` flag emulátor-eredményhez · összehasonlító report generátor (`tool/local_ai_benchmark_report.dart`) FIXTURE JSON bemenetekkel.

**NINCS benne (tilos):**

- `android/app/src/androidTest/` vagy bármilyen natív Android fájl — lásd §0.0.
- Valódi eszközön történő mérés futtatása vagy valódi mérési adat véglegesítése — csak FIXTURE minták a tesztekhez.
- Runtime- vagy modellválasztás — ez Kör 6/7 dolga.
- `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/ai/benchmark/benchmark_scenario.dart` | ÚJ — scenario leíró (rövid/közepes/többturnos, nyelv) |
| `lib/core/ai/benchmark/benchmark_sample.dart` | ÚJ — egy mérési minta (nyers metrikák) |
| `lib/core/ai/benchmark/benchmark_summary.dart` | ÚJ — aggregált percentilisek |
| `lib/core/ai/benchmark/benchmark_environment.dart` | ÚJ — eszköz/runtime metaadat + `nonRepresentativePerformance` |
| `tool/local_ai_benchmark_report.dart` | ÚJ — JSON→összehasonlító report CLI |
| `test/core/ai/benchmark/benchmark_summary_test.dart` | a §6 cellái |
| `test/core/ai/benchmark/benchmark_report_test.dart` | a §6 cellái |

**Tilos zóna:** `android/**` · `lib/features/offline_ai/**` (a Kör 2/3-on túli bővítés más köré tartozik) · `local_ai/**` (Python-oldali eszközök, Kör 5+) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések

### 5.1 Nincs ÚJ kötött döntés — mechanikus mérési infrastruktúra

Ez a kör nem vezet be architekturális szerződést; a `BenchmarkSummary` egy tisztán adat-aggregáló érték-objektum, ami a Kör 2 value-object mintáját követi (immutable, wire-string enumok).

**NEM elfogadható gyengítés:** emulátoron mért adat `nonRepresentativePerformance=false`-ként vagy a flag kihagyásával való rögzítése — ez a Kör 9.2/21.5 SDD-szabály ("emulator csak contract célra, nem performance döntésre") megkerülése lenne, még akkor is, ha technikailag "csak egy mérési kör".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A percentilis-számítás (p50/p95) helyes ismert, kézzel kiszámolt mintahalmazon | `benchmark_summary_test.dart` |
| A2 | Érvénytelen minta (negatív TTFT, hiányzó kötelező mező) elutasított | `benchmark_summary_test.dart` |
| A3 | A JSON round-trip (encode→decode) bájtra egyező mezőket ad | `benchmark_summary_test.dart` |
| A4 | Emulátor-eredmény mindig `nonRepresentativePerformance=true`-t hordoz, és a report ezt külön szekcióban jelöli | `benchmark_report_test.dart` |
| A5 | A report nem tartalmaz promptszöveget vagy szabad szöveges mezőt a kimenetben | `benchmark_report_test.dart` |
| A6 | Minden scenario (rövid/közepes/többturnos × hu/en) egyedi, ütközésmentes azonosítót kap | `benchmark_summary_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A p95 számítás lineáris interpolálás nélkül, egyszerű index-kerekítéssel fut | A1 (a kézzel kiszámolt referenciaérték eltér) |
| A validáció elfogadja a negatív TTFT-t | A2 |
| A JSON encode/decode veszít egy mezőt (pl. `thermalDelta`) | A3 |
| Az emulátor-környezet flag alapértéke `false` | A4 |
| A report a `BenchmarkSample.rawPromptPreview`-hoz hasonló szabad szöveges mezőt ír ki | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az emulátor-detektáló ág alapértékét `nonRepresentativePerformance=false`-ra, futtasd a gate-et → az **A4** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/ai/benchmark/benchmark_summary_test.dart test/core/ai/benchmark/benchmark_report_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `BenchmarkScenario`, `BenchmarkEnvironment` value objectek.
2. `BenchmarkSample` — nyers metrikák, validáció konstruktorban.
3. `BenchmarkSummary` — percentilis-aggregáció.
4. JSON encode/decode mindhárom modellre.
5. `tool/local_ai_benchmark_report.dart` — FIXTURE JSON bemenetből összehasonlító report.
6. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az emulátor-adat valós adatnak álcázása.** A `nonRepresentativePerformance` flag hiánya vagy hibás alapértéke a Kör 6/32 döntéseit torzítaná el (A4).
- **A séma túl korai lezárása.** Ha a séma nem terjeszthető bővíthetően (pl. új metrika hozzáadása töri a JSON-t), a Kör 6 bake-off kénytelen lenne visszamenőleg módosítani — ezért a modellek `Map<String, Object?>`-alapú, ismeretlen-mező-toleráns dekódolást használjanak.
- **Szabad szöveg becsúszása a reportba.** Egy debug célból hozzáadott promptelőnézet mező sértené a §15.1 SDD-szabályt (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
