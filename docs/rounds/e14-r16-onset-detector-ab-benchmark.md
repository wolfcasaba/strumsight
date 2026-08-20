# E14-R16 — Canonical SuperFlux A/B benchmark

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 16 (strum recovery blokk)
- **Kör-azonosító:** `E14-R16`
- **Branch:** `<motor>/e14-r16-onset-detector-ab-benchmark`
- **Előfeltétel:** `E14-R08` (grouped harness) és `E14-R15` (hard-negative
  taxonómia + hamis-esemény metrika) merge-elve.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0368` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/engine/dsp/superflux_onset_detector.dart` konstansait
> (mérve: `_floor = -9.0`, `_delta = 12.0`, `_lambda = 1.0`) és a
> `tool/benchmarks/real_audio_dsp_baseline.dart` alakját — ez a kör azt a
> mintát követi. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tool/benchmarks/onset_ab_benchmark.dart",
  "lib/features/live/engine/dsp/onset_detector_variant.dart",
  "lib/features/live/public.dart",
  "test/tooling/onset_ab_benchmark_test.dart",
  "docs/eval/onset-detector-ab.md",
  "docs/rounds/e14-r16-onset-detector-ab-benchmark.md",
]
gate_tests = [
  "test/tooling/onset_ab_benchmark_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A jelenlegi onset-detektort **össze kell mérni** a canonical változatokkal
(24 sáv/oktáv SuperFlux, complex-domain, egyszerű spectral flux), ugyanazon a
csoportosított korpuszon, CPU- és latency-méréssel együtt — és **a production
konstans NEM mozdul** ebben a körben. A kör kimenete report + ADR-döntés,
nem hangolás.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **AGENTS.md §9:** shipping DSP-konstans csak mért A/B és ADR után mozdul —
  ez a kör pontosan azt a mérést állítja elő.
- **E99-R04/R05 (GOV-06/06b):** a `tool/benchmarks/real_audio_dsp_baseline.dart`
  + `docs/eval/real-audio-dsp-baseline.md` a bevált alak; a GOV-06b tanulsága
  szerint a nem validált állítást (BPM) VISSZA kell vonni — ugyanez a szigor.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/engine/dsp/superflux_onset_detector.dart` — maximum-szűrt
  log-mel flux, adaptív küszöb; a konstansok: `_floor = -9.0`, `_delta = 12.0`,
  `_lambda = 1.0`.
- `tool/benchmarks/` — két benchmark él (`real_audio_dsp_baseline.dart`,
  `song_trainer_pitch_benchmark.dart`); a harmadik ide illeszkedik.
- Nincs olyan futtatható artefaktum, amely TÖBB onset-változatot mérne
  ugyanazon a bemeneten.

## 3. Scope

**Benne:** variáns-interfész (current / canonical-24 / complex-domain / simple
flux), benchmark-CLI, per-subgroup report, CPU+latency mérés, doksi.

**Nincs benne:** a production konstansok módosítása, modellcsere, a live
pipeline bekötésének megváltoztatása, `ml/**`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `tool/benchmarks/onset_ab_benchmark.dart` | a futtatható A/B |
| `lib/features/live/engine/dsp/onset_detector_variant.dart` | variáns-interfész (ÚJ, a meglévő detektor változatlan) |
| `lib/features/live/public.dart` | additív export |
| `test/tooling/onset_ab_benchmark_test.dart` | determinizmus + variáns-mátrix |
| `docs/eval/onset-detector-ab.md` | a report és a döntési javaslat |
| `docs/rounds/e14-r16-onset-detector-ab-benchmark.md` | §10 handoff |

**Tilos zóna:** minden más — **kiemelten**
`lib/features/live/engine/dsp/superflux_onset_detector.dart` és
`dsp_config.dart` (a konstansok!), `lib/features/live/engine/ml/**`,
`assets/**`, `ml/**`, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0368)

### 5.1 A production út érintetlen

A meglévő detektor egyetlen konstansa sem változik; a variánsok ÚJ fájlban
élnek, és csak a benchmark hívja őket. **NEM elfogadható**: „a canonical jobb,
ezért egyből átállítom".

### 5.2 Azonos bemenet, azonos split

Minden variáns ugyanazt a csoportosított korpuszt kapja (E14-R08), különben az
összehasonlítás értelmetlen.

### 5.3 A latency és a CPU is metrika

Az accuracy önmagában nem dönt: a report Pareto-nézetet ad (accuracy vs
latency vs CPU), és a javaslatot ezzel indokolja.

### 5.4 Determinisztikus report

Ugyanaz a bemenet bitre ugyanazt a reportot adja; nincs `DateTime.now()` a
riport belsejében.

### 5.5 A nem validált állítás visszavont

Amelyik metrikát a korpusz nem bizonyítja (pl. hiányzó annotáció), az a
reportban **kifejezetten „nem mért"**-ként szerepel — nem becsülve.

## 6. Acceptance criteria

1. A benchmark mind a négy variánst futtatja ugyanazon a fixture-ön, és
   variánsonként ad onset P/R/F1-et a 25/50/100 ms tűrésekre.
2. A tűrés-határ **inkluzív**: a hármas cella a 50 ms-ra — a küszöb **alatt**
   (49 ms eltérés) párosít, pontosan **rajta** (50 ms) párosít (a határ ide
   tartozik), a küszöb **fölött** (51 ms) nem párosít.
3. Kétszeri futás bájtra azonos reportot ad.
4. A report tartalmaz latency- és CPU-oszlopot minden variánsra.
5. A `superflux_onset_detector.dart` és a `dsp_config.dart` diffje **üres**
   (a review `git diff --stat`-tal ellenőrzi; a teszt a konstansok értékét
   is rögzíti).
6. Hiányzó annotációra a report „nem mért" jelölést ad, nem 0-t.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A production konstans „menet közben" módosul | 5. pont konstans-cellája |
| A párosítás exkluzív határral | 2. pont **50 ms** cellája |
| A riportba időbélyeg kerül | 3. pont |
| Csak accuracy, latency nélkül | 4. pont |
| Hiányzó annotáció → 0 | 6. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: a `_delta` konstans ideiglenes megváltoztatásával az
5. pont konstans-cellája **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Variáns-interfész + a négy implementáció (a current a meglévőt HÍVJA).
2. Benchmark-CLI a `real_audio_dsp_baseline.dart` alakja szerint.
3. Determinizmus- és variáns-teszt.
4. Report + javaslat a doksiban (a döntés ADR-je a Claude-é).

## 9. Kockázatok

- **Hangolás-csúszás:** a legnagyobb kockázat, hogy a mérés után az implementer
  „gyorsan" átállítja a production konstansokat — az 5.1 és a tilos zóna ezt
  fail-closed tiltja.
- **Korpusz-hiány:** ha az E14-R08 fixture nem elég, `blocked` a jelzés, nem
  kitalált szám.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
