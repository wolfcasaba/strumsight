# E05-R19 — Jobb kéz (picking) stroke metric engine

- **Státusz:** PLANNING (pre-flight §0.0 revízióval lezárva 2026-08-08; előre
  megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 19; §20
- **Branch:** `minimax/e05-r19-picking-hand-stroke-metrics` (a `codex/` prefix
  az eredeti Codex/Terra-implementációra épülő batch-írásból maradt; a
  tényleges motor `minimax` — E05-R15–R18 névkonvenció)
- **Előfeltétel:** **E05-R13, E05-R15, E05-R18 merge** (a sync-kapu az R21-ben élesedik) — mind a három merge-elve, `main` @ `a382cf7` (E05-R18 az utolsó merge-elt kör)
- **Brief szerzője:** Claude (batch) · **Implementáció:** MiniMax M3
  (pipeline-prompt előírás, 2026-08-08 — a Terra/codex-harness ideiglenesen
  tiltva, ld. pipeline-prompt „⛔ IDEIGLENES MOTOR-TILTÁS")

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

> ⚠ **Pre-flight (KÖTELEZŐ, ELVÉGEZVE 2026-08-08):** `origin/main` +
> E05-R13/R15/R18 merge igazolva (`main` @ `a382cf7`). Az R18 `MetricObservation`
> szerződése literálisan újrahasznált, a `MetricDefinition` MINTÁJA követve
> (nem importálva — §0.0/3), és az R13 picking-simítás amplitúdó-korlátja
> (`landmark_smoothing.dart` `pickingAlpha = 0.85`, ≥90% amplitúdó-megőrzés)
> újraolvasva. **A strum-onset forrás a meglévő audio oldal**
> (`lib/features/live/public.dart` / practice observation gateway) — ebben a
> körben **injektált eseménylistaként**, adapter nélkül. Nincs ÚJ ADR
> (megerősítve, §0.0/1). A §6 mirror/paritás kritérium 4→2 cellára javítva
> (§0.0/2, L176 megelőzés). PREPARED→PLANNING, brief commit az implementer
> indítása ELŐTT (ez a commit).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** A pre-flight (Claude Sonnet 5, orchestrátor, 2026-08-08) a
pipeline-prompt §1 mérési szabálya szerint (grep-eld ki a kódból, ne a táblát
mérd) a következőket ellenőrizte a `main` @ `a382cf7` állapoton, és négy
ponton talált mért eltérést vagy pontosítandó hiányt a batch-írt szöveghez
képest:

1. **ADR-ellenőrzés: nincs új ADR — megerősítve a tényleges ADR-szöveg
   elolvasásával, nem a brief állításának elfogadásával.** `docs/adr/0179-
   vision-capability-aware-feedback.md` §Döntés 1–2 (a `requiredCapability`/
   `confidence`/`observability` hármas és a `notObservable` szabály) és
   `docs/adr/0181-vision-manual-calibration-fallback.md` §Döntés 3 (a
   koordinátageometria pure Dart, teszthető) EPIC-szintű döntések — egyik sem
   fretting-specifikus, mindkettő szó szerint ugyanúgy vonatkozik a picking
   kézre. Az R18 ugyanezt a két ADR-t hajtotta végre a bal kézre; ez a kör a
   jobb kézre hajtja végre — nincs új architekturális döntés, tehát nincs új
   ADR.
2. **§6 „Mirror/balkezes paritás" javítva 4 cellából 2 cellára — az E05-R18
   F4 MAJOR lelet (`docs/LESSONS.md` L176) megismétlésének megelőzése.** Az
   eredeti szöveg („4 cella: `leftHanded` × front/back") EZEN a rétegen nem
   falszifikálható: a metric engine bemenete egy már normalizált,
   timestamp+`HandTrack`(+opcionális guitar-landmark) alakú frame-sorozat
   (az R18 `FrettingFrame`-mintája — `lib/features/vision/domain/metrics/
   fretting_metric_engine.dart:11-21` — grep-elve: nincs benne se `leftHanded`
   bool, se kamera-facing mező), és a picking engine bemenete ugyanezt az
   alakot fogja követni. A kamera-tükrözés és a `leftHanded`→szerep deriváció
   a `HandTrackAssigner`-ben (R8/R13) MÁR megtörtént, és OTT property-
   tesztelt (R13 §6: „front preview mirroring cannot alter the model input
   space", `lib/features/vision/domain/landmarks/hand_track.dart:65-67`
   dokumentálja az invariánst). Egy 4 cellás `leftHanded`×front/back teszt
   ezen a rétegen szükségképpen bit-azonos bemenettel futna mind a négy
   cellában — ez PONTOSAN az E05-R18 F4 MAJOR mintája (a review saját
   szavaival: „ezen a rétegen nincs is olyan bemeneti tengely, amit variálni
   lehetne"), amit egy teljes MÁSODIK javító kör zárt. A §6 lent **2 cellás,
   `HandTrack.handedness`-tengelyű** (`left` vs `right`, minden más mező
   bit-azonos) verzióra javítva — ez az egyetlen ténylegesen variálható
   bemeneti tengely ezen a rétegen. A review-tól ugyanazt a mutáció-próbát
   várom el, mint ami R18 F4-et igazolta (hamis `handedness`-ág injektálva az
   engine-be — ha a teszt akkor sem bukik, nem load-bearing).
3. **`MetricDefinition` (R18, `metric_definition.dart`) NEM literálisan
   újrahasználható — csak `MetricObservation` az.** A brief §2 („ez a kör
   ugyanazt használja, nem ír újat") pontatlan: `metric_observation.dart`
   (`MetricObservation`/`MetricObservability`) valóban generikus (nincs
   Fretting-specifikus mező) — ez importálható és bitre újrahasználható. De
   `metric_definition.dart` `MetricDefinition` osztálya **hardcode-olja** a
   `final FrettingMetricId id;` és `final FrettingCapability
   requiredCapability;` mezőket (grep-elve — nem generikus típusparaméter),
   és a fájl maga **nincs a §4 engedélyezett listán** ebben a körben (csak
   R18-ban volt az). A helyes út: `picking_metrics.dart` (ÚJ, ebben a körben
   engedélyezett) saját `PickingMetricId` + `PickingCapability` enumot és egy
   `MetricDefinition`-nel AZONOS ALAKÚ (ugyanaz a kötelező-mező-validáló
   `throw ArgumentError` minta, ugyanaz az `isValid` getter) saját osztályt
   ír — a MINTÁT követi, a KÓDOT nem importálja. **NEM elfogadható:** kísérlet
   a `metric_definition.dart` módosítására/generizálására — az a §4 tiltott
   zónája, `stopped`-ot ér.
4. **Irány-enum: a core `StrumDirection` (`lib/core/music/strum.dart:5`,
   `enum StrumDirection { down, up }`) újrahasználandó a le/fel
   trajektória-osztályhoz, nem egy párhuzamos vision-lokális enum.** Ez már
   a kanonikus le/fel fogalom a kódbázisban (Live/DSP is ezt használja), és a
   vision domain már importál core modult (`fretting_metric_engine.dart:3`
   `core/geometry/guitar_space.dart` — precedens, hogy a feature-domain→core
   import architekturálisan tiszta). Ha egy köztes trajektória-irány
   (pl. csak-vízszintes vagy null=ambiguous eset) szükséges a `down`/`up`-on
   túl, az egy KÜLÖN, vision-lokális enum lehet — de a `down`/`up` végítélet
   a meglévő `StrumDirection`-t adja vissza, nem egy duplikált párját.

## 1. Cél

Audio-onset köré rendezett **stroke-pálya és konzisztencia** metrikák: irány,
amplitúdó, sebesség, linearitás, le/fel aszimmetria, ütemenkénti konzisztencia
és picking-zóna kategória — semleges, stílusítélet nélküli megfigyelésként.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R18 rögzítette a `MetricDefinition`/`MetricObservation` szerződést és a
  `notObservable` szabályt. **`MetricObservation` literálisan újrahasználva**
  (generikus, nincs Fretting-specifikus mező). **`MetricDefinition` mintája
  követve, de nem importálva** — az az R18 osztály `FrettingMetricId`/
  `FrettingCapability`-re hardcode-olt és a fájl nincs ebben a körben
  engedélyezve; §0.0/3 részletezi.
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
- [ ] **Mirror/balkezes paritás:** **2 cella** (`HandTrack.handedness`
      tengelye: `left` vs `right`, minden más mező bit-azonos) — azonos
      fizikai mozgásra azonos irány-osztály. **NEM** 4 cella (`leftHanded` ×
      front/back kamera) — ezen a rétegen a bemenet már normalizált
      `HandTrack`-sorozat, nincs benne `leftHanded` bool vagy kamera-facing
      mező (a kamera-tükrözés/szerep-derivció a `HandTrackAssigner`-ben, R8/
      R13-ban már megtörtént és property-tesztelt). Egy 4 cellás verzió itt
      szükségképpen bit-azonos bemenettel futna mind a négy cellában — ez az
      E05-R18 F4 MAJOR lelete (`docs/LESSONS.md` L176), ne ismételd meg. A
      review saját mutáció-próbával (hamis `handedness`-ág injektálva) várja
      igazolva látni, hogy a teszt load-bearing. Ld. §0.0/2.
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
