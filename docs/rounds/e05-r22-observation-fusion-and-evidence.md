# E05-R22 — Vision observation fusion és evidence engine

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 22; §9.5–9.6, §23.1–23.2
- **Branch:** `codex/e05-r22-observation-fusion-and-evidence`
- **Előfeltétel:** **E05-R09, E05-R16, E05-R18, E05-R19, E05-R20, E05-R21 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

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
  "docs/rounds/e05-r22-observation-fusion-and-evidence.md",
]
gate_tests = [
  "test/features/vision",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + az összes felsorolt kör merge;
> olvasd újra a metrikák `MetricObservation` alakját (R18/R19/R20), az R16
> geometry-confidence-ét, az R09 quality-summaryját és az R21 sync-bucketjeit —
> a confidence-formula ezekből **komponensenként** épül. Nincs ÚJ ADR (0162
> végrehajtása). PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Nincs előre kiosztott ADR.

## 1. Cél

A landmark-, geometry-, quality- és audio-adatokból **verziózott, visszakövethető
`VisionEvidence`** előállítása: ablakos aggregáció, komponensenkénti
confidence-propagáció, stabil ID és provenance.

## 2. Jelenlegi állapot (mért, megelőző körök)

- A metrikák (R18/R19/R20) egyedi `MetricObservation`-öket adnak, mindegyik a
  saját `MetricDefinition` szerződésével; **fusion nincs**.
- Az R09/R16/R21 adja a quality-, geometry- és sync-komponenseket.
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
