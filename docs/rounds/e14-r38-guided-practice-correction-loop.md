# E14-R38 — Guided practice: bizonyíték-állapot a kitalált konfidencia helyett, és a javító-hurok (ADR 0551)

- **Kör:** E14-R38 · **Csomag:** PKG-F · **ADR:** 0551
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → **lokális gate nem futtatható**;
  egyetlen teszt sem futott le itt. Mérce: `full-gate.yml` + `build-apk.yml`.

## 1. Cél

A terv §2/R38 első és legfontosabb pontja: a
`ChordObservation.confidence = 1.0` hazugság megszüntetése, úgy, hogy egy
bizonytalan/elutasított akkordolvasat **bizonytalanként** rögzüljön és a
pontozás **sose büntesse rossz akkordként**; a lefedettség a pontszám MELLETT
jelenjen meg; és egy kihagyott/bizonytalan cél után a session feedback slotja
mondja ki a következő konkrét javítást — a reducer állapotgépének
érintése nélkül.

## 2. Mért állapot (a kör előtt)

- `live_practice_observation_gateway.dart:249`:
  `ChordObservation(at: at, label: chordLabel, confidence: 1.0)`. A fájl saját
  fejléce mondta ki, hogy az érték kitalált.
- Két olvasó: `chord_change_analyzer.dart:167` (küszöb) és `:332` (rendezés).
  Mindkettőnek minden megfigyelés használhatónak látszott.
- `practice_chord_scorer.dart` az ablak leghosszabb stabil címkéjét
  hasonlította a célhoz → egy bizonytalan, rossz címkéjű olvasat
  `ChordOutcome.wrong` + `scorePerMille: 0`.
- Az `uncertain` szó a teljes `lib/features/practice/**`-ben nem fordult elő.
- A `LiveFrame` ADR 0516 óta hordozza a `chordDecision`/`chordRejectReason`
  mezőt, a `LivePipeline` mindig ki is tölti.
- `PracticeSessionHost` interfészt három teszt-fake implementálja (egy közülük
  `test/fixtures/**`, nem PKG-F tulajdon) → az interfész **nem bővíthető** egy
  új taggal anélkül, hogy idegen fájlok pirosra váltanának.

## 3. Scope

**Benne:** `ChordEvidence` + `ChordObservation.{evidence, rejectReasonCode}` +
nullázható `confidence`; `chord_change_analyzer` bizonyíték-szabálya és
rendezése; `practice_chord_scorer` bizonyíték-szűrése + `recognitionCoverage`;
`PracticeMetricReasonCode.chordUncertain`; a gateway leképezése;
`PracticeCorrection` + `resolvePracticeCorrection`;
`PracticeSessionController.latestCorrection`;
`practiceLatestCorrectionProvider`; `PracticeCorrectionBanner`; bekötés a
session-képernyő `feedback` slotjába.

**Kívül:** a reducer / `PracticeSessionState` / `PracticeSessionHost`
(kikötés, illetve idegen tulajdonú fake-ek); `PracticeSessionResult` +
history-szerializáló bővítése coverage-dzsel (a terv R38/2. pontja — külön,
migrációs kör); az „egy tapos ismétlés a leggyengébb szakaszra" (R38/3).

## 4. Fájlok

**lib (új):** `features/practice/domain/model/practice_correction.dart`,
`features/practice/domain/service/practice_correction_resolver.dart`,
`features/practice/presentation/widgets/practice_correction_banner.dart`
**lib (módosított):** `features/practice/domain/model/practice_observation.dart`,
`features/practice/domain/model/practice_metrics.dart`,
`features/practice/domain/service/chord_change_analyzer.dart`,
`features/practice/domain/service/practice_chord_scorer.dart`,
`features/practice/data/live_practice_observation_gateway.dart`,
`features/practice/application/practice_session_controller.dart`,
`features/practice/application/practice_session_providers.dart`,
`features/practice/presentation/screens/practice_session_screen.dart`
**test (új):** `features/practice/domain/practice_uncertain_chord_scoring_test.dart`,
`features/practice/domain/practice_correction_resolver_test.dart`,
`features/practice/presentation/practice_correction_banner_test.dart`
**test (módosított):** `features/practice/data/live_practice_observation_gateway_test.dart`
(két cella a RÉGI, hibás `confidence == 1.0`-t rögzítette → most `isNull`;
plusz két új csoport), `features/practice/domain/practice_direction_scorer_test.dart`
(a teljes ok-kód halmaz bővült)

## 6. Elfogadás

| # | Feltétel | Állapot |
|---|---|---|
| B1 | uncertain/rejected olvasat **bizonytalanként** rögzül | **PINNED-BY-TEST** (gateway: mind a 6 döntés → evidence leképezés; a reject-ok stabil kódként utazik) |
| B2 | uncertain SOSEM büntetődik rossz akkordként | **PINNED-BY-TEST** (`insufficientData` + `chordUncertain`, `scorePerMille == null`) + **hamisító cella** (ugyanaz a rossz címke `measured`-ként IGENIS `wrong`) |
| B3 | a score nem változik pusztán az absztinenciától | **PINNED-BY-TEST** (property-jellegű cella: 1/3/10 absztinencia, azonos `chordPerMille`, csökkenő coverage) |
| B4 | coverage külön jelenik meg | **PINNED-BY-TEST** (`recognitionCoverage`: `NotApplicable` nulla megfigyelésnél, 0,5 fél-fél esetben) |
| B5 | javító-hurok: kihagyott/bizonytalan cél után konkrét javítás, reducer-változás NÉLKÜL | **PINNED-BY-TEST** (rezolver: 9 tiszta cella; banner: 11 reject-ok paritás + 3 widget-cella; a reducer diffje üres) |
| B6 | a javítás sosem vádol a modell bizonytalanságáért | **PINNED-BY-TEST** (`recognitionUnclear` → reject-ok mondat, `expectedChord == null`, „Play " nem jelenik meg) |
| B7 | `PracticeSessionResult` coverage/quality mezője | **NOT-DONE** (terv R38/2 — perzisztált formátumot érint, saját migrációs kör) |
| B8 | egy tapos ismétlés a gyenge szakaszra | **NOT-DONE** (terv R38/3 — külön UI-döntés) |
| B9 | mennyi az absztinencia aránya éles játékban | **NEEDS-MEASUREMENT** — a coverage mező pontosan ezért létezik; számot csak eszközös session ad |
| B10 | Practice/Song/Live integrációs teszt | **NEM ÉRINTI** — a meglévő `test/e2e/**` lánc változatlanul fut; ez a kör nem adott új útvonalat |

## 10. Handoff

1. **l10n beolvasztás:** `<scratch>/l10n/PKG-F.json` `base` szegmens 4 R38-kulcsa
   (`practiceCorrectionTitle`, `…PlayChord` {chord}, `…HitTarget`, `…Unclear`).
   A banner a reject-okokra a MEGLÉVŐ `liveReject*` kulcsokat használja — új
   kulcs oda nem kell, és a paritást teszt őrzi.
2. **Nyitva:** B7 (result-coverage perzisztálás) és B8 (egy tapos ismétlés).
