# E05-R18 — Bal kéz (fretting) metric engine

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 18; §19
- **Branch:** `codex/e05-r18-fretting-hand-metric-engine`
- **Előfeltétel:** **E05-R13, E05-R15, E05-R16 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/metrics/fretting_metrics.dart",
  "lib/features/vision/domain/metrics/fretting_metric_engine.dart",
  "lib/features/vision/domain/metrics/metric_definition.dart",
  "lib/features/vision/domain/metrics/metric_observation.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/fretting_metric_engine_test.dart",
  "test/features/vision/domain/metric_definition_test.dart",
  "test/fixtures/vision/fretting",
  "docs/rounds/e05-r18-fretting-hand-metric-engine.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R13/R15/R16 merge; olvasd újra
> az R15 confidence-propagációs szabályát és az R16 `lost` állapotát (ekkor
> nincs gitárrelatív metrika). Nincs ÚJ ADR (0162 végrehajtása).
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

A **megfigyelhető, nagyobb léptékű** fretting-metrikák pure Dart,
confidence-aware implementációja — UI-szöveg és exact fret/string claim nélkül.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R13 adja a simított, szerep-hozzárendelt kéz-trackeket; az R15 a
  gitárrelatív u/v pozíciókat és a régiókat; az R16 a geometry-confidence-t és
  a `lost` állapotot.
- **Nincs metrika-réteg.** A Practice-oldali esemény-idővonal (chord change
  targetek) a `lib/features/practice/public.dart`-on át érhető el — ebben a
  körben **csak olvasott bemenetként**, adapter nélkül (az integráció az R25).

## 3. Scope

**Benne:** `MetricDefinition` (minimum visibility, ablak, confidence-formula,
`requiredCapability`), `MetricObservation` (érték + confidence + observability),
és hat metrika: **wrist deviation proxy**, **hand-to-neck distance**,
**chord-change travel**, **ready-position time**, **position stability
(sustain)**, **finger spread proxy**.

**Kívül — TILOS:** UI-szöveg vagy lokalizáció, insight/feedback policy (R23),
fusion (R22), Practice integráció (R25), exact fret/string állítás.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/metrics/metric_definition.dart` | ÚJ | metrika-szerződés |
| `.../domain/metrics/metric_observation.dart` | ÚJ | kimeneti modell |
| `.../domain/metrics/fretting_metrics.dart` | ÚJ | metrika-katalógus |
| `.../domain/metrics/fretting_metric_engine.dart` | ÚJ | számítás |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/domain/*`, `test/fixtures/vision/fretting` | ÚJ | tesztek |
| `docs/rounds/e05-r18-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; ARB; `docs/rag`; DSP. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs exact fret/string claim** (ADR 0162/0164). A metrikák **proxyk**, és
   a nevük is ezt mondja. **NEM elfogadható:** „a 3. bundon van a mutatóujjad"
   típusú kimenet, sem olyan mező, amelyből a UI ezt olvasná ki.
2. **Minden metrika deklarált szerződéssel jár:** minimum visibility, ablakhossz,
   confidence-formula, `requiredCapability`. Szerződés nélküli metrika **nem
   kerülhet a katalógusba** — ezt teszt méri (a katalógus minden eleme validált).
3. **Alacsony megfigyelhetőségnél nincs érték:** `notObservable`, nem 0 és nem
   „becsült" szám. **NEM elfogadható:** hiányzó adat kitöltése átlaggal.
4. **A metric engine nem generál UI-szöveget** és nem ismer lokalizációt.
5. **Bal- és jobbkezes paritás:** a metrikák a **gitáros szerep** szerint
   számolnak (R13), nem fizikai kéz szerint; a `leftHanded` beállítás nem
   fordíthatja meg az előjeleket.
6. **NaN/Infinity soha** — degenerált bemenetre `notObservable`.
7. **`lost` geometria alatt a gitárrelatív metrikák `notObservable`-ök** (R16).

## 6. Acceptance criteria

- [ ] **Metrikánként külön unit teszt** (6 metrika), mindegyikhez legalább:
      tipikus eset · határeset · degenerált eset.
- [ ] **Visibility-mátrix metrikánként:** a minimum visibility **alatt / rajta /
      fölött** — az „alatt" `notObservable`, a másik kettő érték. A „rajta"
      cellák értékét `python3 -c` számolja (a §10-ben idézve).
- [ ] **Katalógus-teszt:** minden metrika-definíció tartalmaz nem-üres
      visibility, ablak, confidence-formula és capability mezőt; hiányzó mező
      esetén a teszt PIROS.
- [ ] **Mirror / left-handed paritás:** `leftHanded` be/ki × front/back kamera
      = 4 cella, azonos fizikai mozgásra azonos metrikaérték (tolerancián belül).
- [ ] **`lost`-geometria teszt:** R16 `lost` állapotban a gitárrelatív metrikák
      `notObservable`-t adnak (hívásszámláló: a számítás nem fut le).
- [ ] **NaN/Infinity guard** a teljes fixture-mátrixon.
- [ ] **Valódi-sértés próba (§10):** a minimum visibility ellenőrzés kiiktatása
      → a visibility-mátrix „alatt" cellája PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. Fixture-készlet (szintetikus landmark-pályák) + RED mátrixok.
2. `MetricDefinition` + `MetricObservation`.
3. A hat metrika egyenként (metrika → teszt → következő).
4. Katalógus-validáció; gate.

## 9. Kockázatok

- **A proxy-metrika „exact" ígéretté csúszik** a névadásban — a §5.1 tiltása és
  a katalógus-teszt (nevek ellenőrzése) fogja meg.
- **A fixture-ök idealizált pályákból készülnek**, ezért minden metrikához
  kell legalább egy zajos fixture is, különben a küszöbök valótlanok
  (a mért hibaosztály: „referenciacellát valódi adatból").

**STOP:** exact fret claim, UI-szöveg bevezetése vagy a visibility-kapu
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r18-fretting-hand-metric-engine-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
