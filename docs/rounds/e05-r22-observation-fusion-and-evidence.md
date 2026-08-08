# E05-R22 — Vision observation fusion és evidence engine

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-08, kód mérve: main @ `960a346`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 22; §9.5–9.6, §23.1–23.2
- **Branch:** `codex/e05-r22-observation-fusion-and-evidence`
- **Előfeltétel:** **E05-R09, E05-R16, E05-R18, E05-R19, E05-R20, E05-R21 merge**
- **Brief szerzője:** Claude (batch, 2026-08-05) · **Pre-flight revízió:**
  Claude Sonnet 5 (2026-08-08) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/evidence/vision_observation.dart",
  "lib/features/vision/domain/evidence/vision_evidence.dart",
  "lib/features/vision/domain/evidence/evidence_provenance.dart",
  "lib/features/vision/domain/evidence/confidence_model.dart",
  "lib/features/vision/application/observation_fusion.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/application/observation_fusion_test.dart",
  "test/features/vision/domain/confidence_model_test.dart",
  "test/fixtures/vision/evidence",
  "docs/adr/0190-vision-observation-fusion-and-evidence.md",
  "docs/rounds/e05-r22-observation-fusion-and-evidence.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ✅ **Pre-flight ELVÉGEZVE (2026-08-08).** Eredmény lásd §0.0 és az új §5.7–§5.9.
> Rövid összefoglaló: a négy confidence-komponens forrása a kódban mérve és
> fixen kötve (`model`⇐`MetricObservation`, `quality`⇐`VisionFrameQuality`/
> `VisionQualitySummary`, `geometry`⇐`GeometryConfidence`, `sync`⇐`SyncQuality`
> — **nem** `PickingSyncQuality`); a brief „0162" előzetes ADR-hivatkozása
> **sosem lett fájl** (nem elavult foglalás, hanem sosem realizált terv) — a
> `tools/round-slots.py reserve-adr` **0190**-et adott, lásd
> [`docs/adr/0190-vision-observation-fusion-and-evidence.md`](../adr/0190-vision-observation-fusion-and-evidence.md).
> Az „observed/inferred/notObservable/experimental" négyes gyártási szabálya
> — a brief eredeti szövege ezt nem pinnelte le — most §5.8-ban pontos.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** Hét mért pont, a pipeline-prompt §1 két kötelező mérési szabálya
szerint (elérhetetlen cél-státusz / erőforrás-tulajdonlás), plusz a brief saját
kötelező pre-flight-feladata (a négy confidence-komponens tényleges forrása).
Teljes indoklás: [ADR 0190](../adr/0190-vision-observation-fusion-and-evidence.md)
Kontextus szakasza — itt csak az összefoglaló és a brief-re gyakorolt hatás:

1. **ADR-szám: a brief „0162" hivatkozása sosem lett fájl** (nem elavult
   foglalás, mint a 0170→0189 minta E05-R21-nél, hanem sosem realizált terv —
   a `docs/execution/pipeline-queue.tsv` E05-R22 sora is `nincs`-et tart).
   `tools/round-slots.py reserve-adr --round E05-R22` → **0190**.
2. **„model" komponens = `MetricObservation.confidence`** (`domain/metrics/metric_observation.dart`,
   R18) — motoronként (fretting/picking/posture) saját formulával már
   kiszámolva, változtatás nélkül fogyasztva.
3. **„geometry" komponens = `GeometryConfidence.confidence`** (`domain/geometry/geometry_confidence.dart`,
   R16); csak a `guitarRelativeTracking`-et igénylő metrikáknál aktív — a
   nem-gitár-relatív metrikáknál (pl. `poseTracking`-only posture) a komponens
   semleges `1.0`.
4. **„quality" komponens = `VisionFrameQuality`/`VisionQualitySummary`**
   (`domain/quality/`, R09) — **mérve: ma egyik metrika-motor sem fogyasztja**
   (`grep -rn "VisionFrameQuality\|VisionQualitySummary" lib/features/vision/domain/metrics/`
   nulla találat), tehát ez a kör az **első** technikai-confidence fogyasztója.
   A típus doc-commentje „setup observability only" — a fúzió a nyers
   frame-mérésekre a SAJÁT ablakán olvas rá, **nem** a
   `VisionQualitySummary.fromFrames` cue-priorizáló (egyetlen aktív cue)
   kimenetét használja számként (az bemutatási logika, nem tiszta jel).
5. **„sync" komponens = `SyncQuality`** (`domain/sync/sync_quality.dart`,
   R21) — **NEM** `PickingSyncQuality` (`domain/metrics/picking_metrics.dart:75`,
   R19). A két, azonos névkészletű (`poor/acceptable/good/excellent`), de
   szándékosan különálló enum közül a `PickingSyncQuality` a picking-motor
   SAJÁT, kemény, ma **injektált** (be nem kötött) event-level kapuja; a
   `SyncQuality` a fúziós réteg lágy komponense. A kettő bekötése egymásba
   **nem** ennek a körnek a dolga (érintené a `picking_metric_engine.dart`/
   `picking_metrics.dart` fájlokat, amelyek kívül esnek az `allowed_paths`-on).
6. **`{Fretting,Picking,Posture}MetricDefinition.window`/`.minimumVisibility`
   ma HASZNÁLATON KÍVÜLI mezők** (`grep -n "\.window\b" lib/features/vision/domain/metrics/*.dart`
   — az egyetlen motor-oldali találat egy MÁSIK típus mezője). A fúzió ezt a
   mezőt használja ablak-hosszként (nem vezet be párhuzamos fogalmat) — lásd
   új §5.7.
7. **„observed/inferred/notObservable/experimental" — elérhetetlen
   cél-státusz, ma sehol nem implementált.** A pipeline-prompt §1/1 mérési
   szabálya szerint minden brief-hivatkozott státuszhoz meg kell mérni, MELYIK
   bemenet termeli — ennek a négyesnek **nincs** meglévő gyártója (a SDD §9.6
   csak a mezőtípust nevezi, a `CapabilityState` (§7.2) sincs implementálva,
   és egyik élő capability-enumnak sincs kísérleti értéke). Pontos gyártási
   szabály: új §5.8.
8. **Erőforrás-tulajdonlás (pipeline-prompt §1/2): nem releváns** — a brief
   egyetlen acceptance-cellája sem rendel lease/lock/handle/subscription-t
   egy réteghez; a `.acquire(`-hívás (`CameraSessionLease`) a kamera-session
   életciklusáé, amit ez a tisztán domain/application réteg nem érint.

## 1. Cél

A landmark-, geometry-, quality- és audio-adatokból **verziózott, visszakövethető
`VisionEvidence`** előállítása: ablakos aggregáció, komponensenkénti
confidence-propagáció, stabil ID és provenance.

## 2. Jelenlegi állapot (mért, megelőző körök)

- A metrikák (R18/R19/R20) egyedi `MetricObservation`-öket adnak, mindegyik a
  saját `MetricDefinition` szerződésével; **fusion nincs**.
- Az R09/R16/R21 adja a quality-, geometry- és sync-komponenseket — **mérve
  (§0.0/4): a quality-komponenst (R09) ma egyik metrika-motor sem fogyasztja**,
  ez a kör az első technikai-confidence fogyasztója.
- **Mérve (§0.0/6): a `{Fretting,Picking,Posture}MetricDefinition.window`/
  `.minimumVisibility` mezők ma deklarálva és validálva, de egyik motor sem
  olvassa ki** — pontosan erre a fúziós ablak-hossz szerepre lettek fenntartva
  R18-ban.
- Az Epic 4 tutor-oldala már ismeri a „forrásra hivatkozó" mintát
  (`TutorSourceRef`, ADR 0141) — a vision provenance ehhez **hasonló**
  filozófiájú, de **saját** típus (nem importál tutor-típust).

## 3. Scope

**Benne:** `VisionObservation` (nyers, ablakos), `VisionEvidence` (verziózott,
stabil ID + provenance), `EvidenceProvenance` (mely metrika, mely ablak, mely
model-verzió, mely geometry-source, mely sync-bucket), `ConfidenceModel`
(komponensek: model · quality · geometry · sync), fusion pipeline az
observed / inferred / notObservable / experimental állapotokkal.

**Kívül — TILOS:** feedback policy és insight (R23), UI, persistence (R28),
tutor-adapter (R27), metrika-szerződés átírása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/evidence/vision_observation.dart` | ÚJ | ablakos megfigyelés |
| `.../domain/evidence/vision_evidence.dart` | ÚJ | verziózott bizonyíték |
| `.../domain/evidence/evidence_provenance.dart` | ÚJ | visszakövethetőség |
| `.../domain/evidence/confidence_model.dart` | ÚJ | komponens-propagáció |
| `.../application/observation_fusion.dart` | ÚJ | fusion pipeline |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/*`, `test/fixtures/vision/evidence` | ÚJ | tesztek |
| `docs/adr/0190-*.md` | ÚJ | fúzió/evidence-szerződés (§0.0/1) |
| `docs/rounds/e05-r22-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `lib/features/ai_tutor/`; `docs/rag`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs single-frame negatív evidence.** Minden metrikához kötelező
   minimum frame-szám / minimum látható időtartam; alatta `notObservable`.
   **NEM elfogadható:** „egy frame-ből is látszik" kivétel.
2. **A confidence komponensekből áll, és a fusion csak csökkentheti**
   (min- vagy szorzat-jellegű kombináció, dokumentálva). **NEM elfogadható:**
   átlagolás, amely egy gyenge komponenst elrejt (pl. `sync=poor` mellett
   magas összesített confidence).
3. **Minden evidence provenance-szal jár**, és a provenance elég ahhoz, hogy a
   bizonyíték **újraszámolható** legyen (metrika, ablak, model-verzió,
   geometry-source, sync-bucket, thresholds-verzió). **NEM elfogadható**
   provenance nélküli evidence, még „belső" célra sem.
4. **Ugyanarra az ablakra nincs duplikált evidence** — a fusion idempotens az
   ablak-kulcsra nézve.
5. **Az evidence ID stabil**: azonos bemenetre azonos ID (determinisztikus
   hash az ablak-kulcsból + metrikából), nem véletlenszám és nem `DateTime.now()`.
6. **Korlátos memória:** a pipeline **nem** tarthat meg minden nyers
   observationt; az ablakon kívüliek eldobódnak.
7. **A fúziós ablak-hossz metrikánként a meglévő
   `{Fretting,Picking,Posture}MetricDefinition.window` mezőt használja**
   (§0.0/6, ADR 0190 Döntés 3) — **NEM elfogadható** egy második, ettől
   független ablak-hossz-fogalom bevezetése. Az „1. pont" minimum
   frame-szám/látható-időtartam és a SDD §23.2 „maximum gap" ÚJ, fúzió-tulajdonú
   küszöbök, erre az ablakra **rátéve**, nem helyette.
8. **Az `ObservationState` (`observed`/`inferred`/`notObservable`/
   `experimental`) gyártási szabálya rögzítve** (§0.0/7, ADR 0190 Döntés 4):
   - `experimental` — capability-szintű kapu, minden mást felülír; **ma egyik
     élő capability-enumnak sincs kísérleti értéke**, tehát a jelenlegi három
     katalógusból elérhetetlen. A `case` kimerítő (nincs `default`/throw), de
     **mesterséges trigger kitalálása tilos** — a teszt egy negatív,
     kizárásos cella (lásd §6).
   - `notObservable` — frame-szám/látható-időtartam a minimum alatt, VAGY a
     belső szakadás meghaladja a metrikára dokumentált maximális gap-et.
   - `inferred` — a minimum küszöb teljesül, ÉS van a max-gap-en belüli,
     áthidalt szakadás — a confidence **szigorúan** alacsonyabb, mint
     szakadás nélkül lenne.
   - `observed` — a minimum küszöb teljesül, és nincs belső szakadás.
9. **A `quality` komponens a nyers `VisionFrameQuality` mérésekre olvas rá a
   fúzió saját ablakán** (§0.0/4, ADR 0190 Döntés 1) — **NEM** a
   `VisionQualitySummary.fromFrames` cue-priorizáló kimenetét használja
   számként. A `sync` komponens a `SyncQuality`-t (R21) olvassa, **NEM** a
   picking-motor belső `PickingSyncQuality` kapuját (§0.0/5, ADR 0190
   Döntés 1) — a két sync-jel bekötése egymásba kívül esik ezen a körön.

## 6. Acceptance criteria

- [ ] **Golden evidence snapshot:** rögzített fixture-session → determinisztikus,
      bit-stabil evidence-lista (kétszeri futás azonos JSON-t ad, ID-kkel együtt).
- [ ] **Confidence-propagáció mátrix:** minden komponens (model/quality/
      geometry/sync) **jó / határon / rossz** értéke × a másik három jó — a
      kombinált confidence a leggyengébb komponensnél **nem lehet nagyobb**;
      12 cella, mind assertálva.
- [ ] **Minimum-frame mátrix:** a metrika minimum frame-száma **alatt / rajta /
      fölött** — az „alatt" `notObservable`.
- [ ] **Gap/occlusion teszt:** ablakon belüli szakadás → az evidence vagy
      `notObservable`, vagy csökkentett confidence — de **soha** változatlan.
- [ ] **Duplikáció-teszt:** ugyanaz az ablak kétszer feldolgozva → **egy**
      evidence (ID-egyezés), nem kettő.
- [ ] **Memória-teszt:** 10 perces szintetikus session után a megtartott
      observation-ok száma korlátos (számmal assertálva), és a memóriahasználat
      nem nő monoton (a fixture-alapú számláló ezt méri).
- [ ] **Valódi-sértés próba (§10):** a confidence-kombináció átlagolásra
      cserélése → a propagáció-mátrix PIROS → visszaállítás.
- [ ] **`experimental` kizárásos teszt (§5/8):** a mai teljes három katalógus
      (`FrettingMetricId`/`PickingMetricId`/`PostureMetricId`, minden
      `capability`-jükkel) egyetlen tiszta ablakra sem termel
      `ObservationState.experimental`-t — a `case` mégis kimerítő (fordítási
      hiba egy hiányzó ágra).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: golden snapshot + propagáció-mátrix + duplikáció.
2. Observation + evidence + provenance modellek.
3. `ConfidenceModel` (komponens-kombináció).
4. Fusion pipeline + memória-korlát; gate.

## 9. Kockázatok

- **Az átlagoló confidence** a legvalószínűbb csendes hiba: rossz szinkron
  mellett is „elég magabiztos" evidence. A 12 cellás mátrix ezt fogja meg.
- **Az ID `DateTime.now()`-ból** származik → a golden snapshot instabil lesz;
  a determinisztikus hash kötelező.

**STOP:** provenance elhagyása, átlagoló confidence vagy single-frame evidence
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r22-observation-fusion-and-evidence-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
