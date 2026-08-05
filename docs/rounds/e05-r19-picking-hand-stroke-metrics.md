# E05-R19 — Jobb kéz (picking) stroke metric engine

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 19; §20
- **Branch:** `codex/e05-r19-picking-hand-stroke-metrics`
- **Előfeltétel:** **E05-R13, E05-R15, E05-R18 merge** (a sync-kapu az R21-ben élesedik)
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/metrics/picking_metrics.dart",
  "lib/features/vision/domain/metrics/stroke_window.dart",
  "lib/features/vision/domain/metrics/picking_metric_engine.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/picking_metric_engine_test.dart",
  "test/features/vision/domain/stroke_window_test.dart",
  "test/fixtures/vision/picking",
  "docs/rounds/e05-r19-picking-hand-stroke-metrics.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R13/R15/R18 merge; olvasd újra
> az R18 `MetricDefinition` szerződését (ez a kör ugyanazt használja) és az R13
> picking-simítás amplitúdó-korlátját. **A strum-onset forrás a meglévő audio
> oldal** (`lib/features/live/public.dart` / practice observation gateway) —
> ebben a körben **injektált eseménylistaként**, adapter nélkül.
> Nincs ÚJ ADR. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

Audio-onset köré rendezett **stroke-pálya és konzisztencia** metrikák: irány,
amplitúdó, sebesség, linearitás, le/fel aszimmetria, ütemenkénti konzisztencia
és picking-zóna kategória — semleges, stílusítélet nélküli megfigyelésként.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R18 rögzítette a `MetricDefinition`/`MetricObservation` szerződést és a
  `notObservable` szabályt — ez a kör **ugyanazt** használja, nem ír újat.
- Az R13 picking-profilja megőrzi a gyors stroke amplitúdóját (≥ 90 %).
- **Az audio–vision szinkron még nincs kész (R21).** Ezért ebben a körben a
  stroke-ablak **injektált** eseménylistával és **injektált sync-minőséggel**
  dolgozik; az éles óra-illesztés az R21-é.

## 3. Scope

**Benne:** `StrokeWindow` (esemény előtti/utáni ablak definíció), trajectory
irány / amplitúdó / sebesség / linearitás, down-up aszimmetria, beat-to-beat
konzisztencia aggregáció, picking-zóna **relatív** kategória (R15 régió),
esemény-szintű vs session-aggregát elválasztás, és a **sync-kapu**: rossz
szinkron mellett **csak** lassú aggregát metrika érvényes.

**Kívül — TILOS:** óra-illesztés/kalibráció (R21), fusion (R22), insight/policy
(R23), UI, DSP-paraméter, audio-oldali kód.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/metrics/stroke_window.dart` | ÚJ | esemény-ablak |
| `.../domain/metrics/picking_metrics.dart` | ÚJ | metrika-katalógus |
| `.../domain/metrics/picking_metric_engine.dart` | ÚJ | számítás |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/domain/*`, `test/fixtures/vision/picking` | ÚJ | tesztek |
| `docs/rounds/e05-r19-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/features/live/`; `docs/rag`; DSP.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs univerzális stílusítélet.** A wrist vs arm hozzájárulás **semleges
   observation**, nem „helyes/helytelen". **NEM elfogadható:** „a csuklóból
   kellene pengetned" típusú, normatív kimenet a metric engine-ből.
2. **Sync-kapu:** esemény-szintű metrika **csak** `good` vagy `excellent`
   sync-minőség mellett érvényes; alatta `notObservable`, és **csak** a
   lassabb, aggregát metrikák maradnak. **NEM elfogadható:** „rosszabb
   szinkronnál nagyobb ablakkal azért számoljuk ki" — a bucket a kapu.
3. **A stroke-ablak szerződése kötött:** az esemény **előtti** és **utáni**
   ablak külön konstans, dokumentálva; az ablak nem nyúlhat át a következő
   eseményre (átfedés esetén az ablak vágódik, és ezt jelzi).
4. **Az irány-mapping tükrözés- és balkezes-helyes** (a szerep az R13-ból jön).
   **NEM elfogadható:** a „lefelé = +y" hardcode a kamera-térben.
5. **Esemény-szintű ≠ session-aggregát:** a két kimenet külön típus, és az
   aggregát **megmondja, hány eseményből** származik (n < minimum → `notObservable`).
6. **Pure Dart, injektált óra**; nincs `DateTime.now()`.

## 6. Acceptance criteria

- [ ] **Stroke-fixture-mátrix:** lefelé / felfelé / vegyes / nagyon gyors
      váltogatás — irány, amplitúdó, sebesség és linearitás elvárt értékekkel
      (fixture-értékek `python3 -c`-vel számolva, a §10-ben idézve).
- [ ] **Sync-mátrix:** `poor / acceptable / good / excellent` — az első kettőnél
      esemény-szintű metrika **nincs** (notObservable), a másik kettőnél van;
      mind a négy külön cella, és a **határ mindkét oldala** mérve.
- [ ] **Nincs-esemény teszt:** üres eseménylista → nincs esemény-szintű kimenet,
      és az aggregát `notObservable` (nem 0 érték).
- [ ] **Átfedő ablak teszt:** két közeli onset → az ablakok vágódnak, nem
      duplikálják a mintákat (a mintaszám assertálva).
- [ ] **Mirror/balkezes paritás:** 4 cella (leftHanded × front/back) — azonos
      fizikai mozgásra azonos irány-osztály.
- [ ] **Aggregát-minimum:** n < minimum eseményszám → `notObservable`;
      n = minimum → érték (a határ két oldala).
- [ ] **Valódi-sértés próba (§10):** a sync-kapu eltávolítása → a sync-mátrix
      `poor` cellája PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. A gyors down/up szekvencia valós
eszközös mérése a device-mátrix **PENDING** sora.

## 8. Implementációs sorrend

1. Fixture-ök (számolt elvárásokkal) + RED sync- és stroke-mátrix.
2. `StrokeWindow` + vágási szabály.
3. Metrikák egyenként.
4. Aggregáció + minimum-szabály; gate.

## 9. Kockázatok

- **A sync-kapu „később bekötendő" marad** és élesben mindig `good`-ot kap —
  ezért a kapu itt, injektált minőséggel készül el, és az R21 csak a valódi
  forrást köti rá.
- **Az idealizált fixture** eltünteti a valós zajt; minden metrikához kell
  zajos fixture is (mért hibaosztály).

**STOP:** normatív stílusítélet, sync-kapu megkerülése vagy audio-oldali kód
érintése helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r19-picking-hand-stroke-metrics-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
