# E06-R26 — Practice, Song és Tutor integráció

- **Státusz:** PLANNING (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`; pre-flight újramérve 2026-08-13, `76c127bb`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 26; §27.1–27.4
- **Branch:** `codex/e06-r26-practice-song-tutor-integration`
- **Előfeltétel:** **E06-R13, E06-R20, E06-R22 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/application/adapters/practice_analysis_adapter.dart",
  "lib/features/audio_analysis/application/adapters/song_analysis_adapter.dart",
  "lib/features/audio_analysis/application/adapters/tutor_analysis_snapshot.dart",
  "lib/features/audio_analysis/application/adapters/progress_evidence_adapter.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/app/config/feature_flags.dart",
  "tool/check_architecture.dart",
  "test/features/audio_analysis/application/practice_analysis_adapter_test.dart",
  "test/features/audio_analysis/application/song_analysis_adapter_test.dart",
  "test/features/audio_analysis/application/tutor_analysis_snapshot_test.dart",
  "test/features/audio_analysis/application/progress_evidence_adapter_test.dart",
  "test/tooling/analysis_cross_feature_boundary_test.dart",
  "docs/rounds/e06-r26-practice-song-tutor-integration.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/tooling",
  "test/app",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R13/R20/R22 merge.
> Olvasd újra a **tényleges** publikus barreleket: `practice/public.dart`
> (a batch idején **43** export, köztük `CompiledPracticeTarget`, `Meter`,
> `PracticeEvent`, `BeatPosition`), `song_trainer/public.dart` (**2** export —
> csak képernyők! ha a Song-oldali domain nem érhető el a barrelen át, az
> adapter **`stopped`** + brief-revízió, NEM közvetlen import),
> `ai_tutor/public.dart` (**0** export a batch idején — ha üres marad, a
> Tutor-adapter a snapshot **típusát** szállítja, bekötés nélkül), és
> `progress/public.dart` (**4** export). A `tool/check_architecture.dart`
> allowlistje **csak szűkülhet** (ADR 0176). PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Új ADR nincs — az ADR 0176 (public barrel határ), 0132/0141
(Tutor adatvédelem és evidence-határ) és 0202 (raw audio) végrehajtása.

**Pre-flight újramérve `76c127bb`-n (2026-08-13) — a batch `a6e6f3d`-je óta 12
kör landolt (R14–R25).** Minden §2-beli export-szám és előfeltétel frissen
grep-elve:

- `practice/public.dart`: **45** export ma (a brief 43-at mért; a +2 az
  E03-R21 Speed Builder-exportjaival jött). Minden brief által NEVESÍTETT
  export (`CompiledPracticeTarget`, `Meter`, `BeatPosition`, `PracticeEvent`,
  `PracticeDefinition`, `practice_progress_providers.dart`) ma is él.
- `song_trainer/public.dart` (2 export), `ai_tutor/public.dart` (0 export),
  `progress/public.dart` (4 export, pontosan a nevesített 4 szimbólum) és a
  `tool/check_architecture.dart` 12-soros `analyze → live` allowlist —
  MIND változatlan, a brief pontosan írja le. OD-01/OD-02 alapja ma is áll.
- Előfeltétel (E06-R13/R20/R22) mind merge-elve (`git log --oneline --all`) —
  `AnalysisTarget` (`domain/target/analysis_target.dart`), az insight-modul
  (`engine/insights/{hotspot_ranker,insight_ranker,insight_registry,
  insight_rules}.dart`) és a runner (`application/analysis_controller.dart`,
  `analysis_isolate_runner.dart`) mind léteznek.

**Egy MÉRT korrekció a §2 táblához → új OD-04 (§5.1):** a
`compiled_practice_target.dart` a `CompiledTargetEvent`-et és az
`ExpectedChordSegment`-et **ugyanabban a fájlban** definiálja, mint a
`CompiledPracticeTarget`-et, de a barrel (`practice/public.dart:51`) egy
szűkítő `show` klózzal **kizárólag** a `CompiledPracticeTarget`-et
exportálja — a másik két típus neve NEM importálható az adapterből. A §2
eredeti „elérhető többek közt … CompiledTargetEvent, ExpectedChordSegment"
mondata téves — ez a két típus ma NEM exportált külön. Feloldás: OD-04,
zéró változás a `practice/public.dart`-on (tilos zóna érintetlen).

**Mért erőforrás-tulajdonlás (az 5. §Döntés 5-höz):** az egyszeri
progress/streak-kreditálás MA is az R22 `AnalysisController._creditOnce`-ban
él (`application/analysis_controller.dart:162-163`, `_creditedRunIds`
halmazzal `runId`-ra kulcsolva véd az ismétlés ellen), és ez ír egy
`PracticeEntry`-t (`application/analysis_providers.dart:210`). A
`ProgressEvidenceAdapter` ettől **strukturálisan különböző** típusú
evidence-t ad (skill evidence, NEM `PracticeEntry`), és a SAJÁT
idempotenciáját `documentId`-ra kulcsolja — a két mechanizmus egymás mellett
él, amíg az adapter nem hív `PracticeEntry`-konstruktort és nem nyúl az
`_creditedRunIds`-hoz.

**Grounding, nem blokkoló (implementációs segédlet):** `StrumDirection`
(`core/music/strum.dart`) és `Chord`/`ChordEvent` (`core/music/chord*.dart`)
**core**-megosztott típusok, nem feature-belsők — az adapter közvetlenül
importálhatja őket, van rá élő precedens ugyanebben a feature-ben
(`data/legacy_view_adapter.dart`, `engine/events/event_timeline_builder.dart`,
`engine/legacy/legacy_evidence.dart`). Az `ExpectedEvent`
(`domain/target/expected_event.dart`) konstruktora **dob**, ha `direction`
nem `null`, de a `type` nem `strum` — egy `CompiledTargetEvent`, aminek
**egyszerre** kitöltött a `chord` ÉS a `direction` mezője (pl. "üsd le
lefelé G-n"), ezért NEM képezhető le egyetlen `chordChange`-típusú
`ExpectedEvent`-re a direction megtartásával; a `direction` a `type:
strum`-ba megy, a `chord` pedig az `expectedChords`/`sections` felé — az
`ExpectedEvent`-nek nincs is `chord` mezője.

PREPARED → PLANNING.

## 1. Cél

A V2 elemzés bekötése a Practice Engine, a Song Trainer, az AI Tutor és a
Progress szerződéseihez — **kizárólag** publikus barreleken át, **redaktált**
Tutor-snapshottal, és **pontosan egyszeri** progress-kreditálással.

## 2. Jelenlegi állapot (mért, `a6e6f3d`; újramérve `76c127bb`-n, ld. §0.0)

- `lib/features/practice/public.dart`: **45** export ma (a batch idején 43
  volt); elérhető többek közt `CompiledPracticeTarget`, `Meter`,
  `BeatPosition`, `PracticeEvent`, `PracticeDefinition`,
  `practice_progress_providers.dart`. **`CompiledTargetEvent` és
  `ExpectedChordSegment` NINCS külön exportálva** (csak a
  `CompiledPracticeTarget` egy szűkítő `show`-val) — ld. OD-04 (§5.1) a
  feloldásért.
- `lib/features/song_trainer/public.dart`: **2** export — kizárólag
  `song_import_screen.dart` és `song_library_screen.dart`. A Song **domain**
  (`domain/models`, `services`) ma **nem** publikus.
- `lib/features/ai_tutor/public.dart`: **0** export (üres barrel).
- `lib/features/progress/public.dart`: **4** export (`PracticeEntry`,
  `PracticeStats`, `practice_log_provider`, `daily_goal_provider`).
- `tool/check_architecture.dart` a cross-feature importot a `public.dart`-hoz
  köti, és az allowlist (12 `analyze → live` bejegyzés) **csak szűkülhet**.
- Az R13 adja az `AnalysisTarget`-et, az R20 az insighteket, az R22 a
  controllert és a kreditálást.

## 3. Scope

**Benne:** `PracticeAnalysisAdapter` (Practice → `AnalysisTarget`, és
Analysis → scoring facts + hotspot action + javasolt retry tempo);
`SongAnalysisAdapter` (Song referencia-timeline → `AnalysisTarget`,
transzpozíció/capo/backing-offset/lejátszási sebesség kezelése,
**concert vs display pitch** elkülönítése); `TutorAnalysisSnapshot`
(kompakt, **redaktált** tények); `ProgressEvidenceAdapter` (verziózott skill
evidence, **egyszeri** bejegyzés); határ-őrteszt; **két** új flag:
`analysisPracticeIntegrationEnabled`, `analysisTutorIntegrationEnabled`
(mindkettő default OFF).

**Kívül — TILOS:** a Practice pontozásának felülírása, a Song Trainer vagy az
AI Tutor **bármely** fájljának módosítása, UI, új allowlist-bejegyzés.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/adapters/practice_analysis_adapter.dart` | ÚJ | Practice ↔ Analysis |
| `.../application/adapters/song_analysis_adapter.dart` | ÚJ | Song ↔ Analysis |
| `.../application/adapters/tutor_analysis_snapshot.dart` | ÚJ | redaktált tények |
| `.../application/adapters/progress_evidence_adapter.dart` | ÚJ | skill evidence |
| `.../public.dart` | meglévő | adapter export |
| `lib/app/config/feature_flags.dart` | meglévő | **additív** 2 flag, OFF |
| `tool/check_architecture.dart` | meglévő | **kizárólag** szabály-szigorítás |
| `test/**` | ÚJ | adapter + határ tesztek |

**Tilos zóna:** `lib/features/practice/**`, `lib/features/song_trainer/**`,
`lib/features/ai_tutor/**`, `lib/features/progress/**`, `lib/features/analyze/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Adapterek a FOGYASZTÓ helyett az Analysis oldalán** (az E05-R01 §5.7
   precedense): az adapter az `audio_analysis/application/adapters/` alatt él,
   és a **másik** feature `public.dart`-ját importálja.
   **NEM elfogadható:** közvetlen import a másik feature belső fájljára,
   és **NEM elfogadható** új allowlist-bejegyzés.
2. **A Practice score marad az elsődleges** (SDD §27.1): az Analysis
   **evidence-t** ad hozzá, nem írja felül. **NEM elfogadható:** az Analysis
   által számolt pontszám a Practice eredményképernyőjén.
3. **A Tutor csak redaktált tényeket kap** (ADR 0132/0141): a snapshot
   tartalmaz insight-ID-ket, metric factokat, confidence-t, hotspot
   tartományokat és target-kontextust; **nem** tartalmaz nyers audiot, teljes
   waveformot, több ezer eventet, sem fájlnevet consent nélkül.
   **NEM elfogadható:** a teljes `AnalysisDocument` átadása.
4. **A Tutor nem módosíthatja a mérést** (SDD §20.7): a snapshot **immutable**,
   és nincs visszaút a metrikák felé.
5. **Pontosan egyszeri progress-kredit:** az R22 kreditálása marad az egyetlen
   hely; a `ProgressEvidenceAdapter` **skill evidence**-t ad, ami **nem**
   gyakorlási bejegyzés. **NEM elfogadható:** második `PracticeEntry`.
6. **Song: concert és display pitch külön** (SDD §27.2): a capo és a
   transzpozíció után az elvárt hangok **concert** pitch-ben mennek az
   elemzésbe, a megjelenítés **display** pitch-ben marad.
   **NEM elfogadható:** a kettő összemosása.
7. **Flagek default OFF**, és flag OFF esetén az adapter **nem** példányosul.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Mi van, ha a song_trainer/public.dart nem exportálja a domaint?
    blocking: true
    resolution_policy: use_default
    default: >-
      A Song-adapter a SAJÁT, minimális bemeneti típusát definiálja
      (`SongReferenceSnapshot`: beat grid, elvárt akkordok/hangok, szakasz,
      offset, sebesség, capo, transzpozíció), és a FELTÖLTÉSE a Song oldalról
      egy KÉSŐBBI, Song-oldali körre marad (follow-up a §10-ben).
      Ebben a körben az adapter a snapshotból → AnalysisTarget irányt
      szállítja, teljes teszteléssel. A song_trainer/public.dart bővítése
      NEM ennek a körnek a dolga.
  - id: OD-02
    question: Mi van, ha az ai_tutor/public.dart üres?
    blocking: true
    resolution_policy: use_default
    default: >-
      a Tutor-adapter a snapshot TÍPUSÁT és a redakciós logikát szállítja,
      és az `audio_analysis/public.dart`-on át exportálja; a Tutor-oldali
      fogyasztás egy későbbi, Tutor-oldali kör dolga (follow-up).
      A Tutor feature érintése TILOS.
  - id: OD-03
    question: Mi a "javasolt retry tempo"?
    blocking: false
    resolution_policy: use_default
    default: >-
      a target tempó × (1 − k), ahol k a timing-hiba súlyosságából számolt,
      dokumentált lépcső {0, 0.05, 0.10, 0.15}; a lépcsőhatárok néven
      nevezett konstansok, és a javaslat SOHA nem megy 60 %-a alá a
      target tempónak.
  - id: OD-04
    question: >-
      A CompiledTargetEvent/ExpectedChordSegment nincs nevesítve exportálva a
      practice/public.dart-ból (csak a CompiledPracticeTarget, egy szűkítő
      show-klózzal, mérve a pre-flightban, §0.0) — hogyan olvassa őket az
      adapter az 5. §Döntés 1 (csak public.dart, nincs új allowlist-sor)
      megsértése nélkül?
    blocking: true
    resolution_policy: use_default
    default: >-
      Az adapter a `compiled.events` / `compiled.expectedChordSegments`
      listákat KIZÁRÓLAG típus-inferenciával járja be (`for (final e in
      compiled.events)`, `.map((e) => …)`) — a `CompiledTargetEvent`,
      `ExpectedChordSegment`, `PracticeLoopRange` típusneveket SEHOL nem írja
      ki explicit módon (nincs saját deklarált paraméter- vagy változótípus
      rájuk). Ez érvényes Dart — egy nem exportált típus publikus tagjai
      inferált statikus típuson át elérhetők —, és **nulla** változást
      igényel a `practice/public.dart`-on. Új `show`-bejegyzés hozzáadása
      vagy közvetlen fájl-import (`domain/model/compiled_practice_target.dart`)
      TILOS (5. §Döntés 1 + tilos zóna).
```

## 6. Acceptance criteria

- [ ] **Practice round-trip:** egy `CompiledPracticeTarget`-ből épített
      `AnalysisTarget` **minden** elvárt eseményt megőriz (darabszám, idő
      |Δ| ≤ 1 µs, típus, irány), és a `targetVersion` a provenance-be kerül.
- [ ] **Practice score nem duplikálódik:** teszt méri, hogy az adapter
      **nem** hív semmilyen Practice scoring API-t, és **nem** ad
      `sessionScore` mezőt vissza — kizárólag `facts`, `hotspots`,
      `recommendedRetryTempo`, `completionEligibility`.
- [ ] **Retry-tempo küszöb hármas + alsó korlát:** a lépcsőhatárokon
      (a timing-súlyosság **a határ alatt / pontosan rajta / fölötte**)
      a k értéke a szerződött lépcsőt adja; és egy negyedik cella, ahol a
      számított tempó a target **60 %-a alá** esne → a javaslat **pontosan
      60 %** (clamp). A számokat `python3 -c`-vel.
- [ ] **Song capo/transzpozíció mátrix — hat cella:** capo 0/2/5 ×
      transzpozíció 0/−2 — az elemzésbe menő elvárt hangok **concert**
      pitch-ben, a display érték **külön** mezőben; a mátrix minden cellája
      konkrét MIDI-számot vár (`python3 -c`-vel kiszámolva).
- [ ] **Backing offset és sebesség:** 0.75× lejátszási sebesség és +250 ms
      offset mellett az `AnalysisTarget` időbélyegei **arányosan és eltolva**
      állnak — három cella (offset nélkül / offset / offset + sebesség).
- [ ] **Tutor-redakció:** a snapshot **nem** tartalmaz PCM-et, waveformot,
      fájlnevet, eszközazonosítót; az eventek száma **≤ 50** (kemény korlát);
      és teszt méri, hogy a snapshot JSON-jában egyetlen olyan kulcs sincs,
      ami a redaktált mezőnevek listájában szerepel.
- [ ] **Tutor-immutabilitás:** a snapshot módosítási kísérlete (lista `add`)
      dob, és a snapshotból **nincs** visszaút a dokumentumhoz (nincs
      referencia-mező).
- [ ] **Progress evidence egyszer:** egy elemzés feldolgozása után **pontosan
      egy** skill-evidence bejegyzés keletkezik, verziózott forrással; a
      **másodszori** feldolgozás (ugyanaz a `documentId`) **nem** hoz újat.
- [ ] **Határ-őr:** `test/tooling/analysis_cross_feature_boundary_test.dart`
      méri, hogy az `audio_analysis` **egyetlen** fájlja sem importál
      `lib/features/<másik>/` alatti nem-`public.dart` útvonalat, és hogy a
      `tool/check_architecture.dart` allowlistje **nem nőtt**.
- [ ] **Flag-kapu:** mindkét új flag `false` minden környezetben; flag OFF
      esetén az adapter-providerek **nem** példányosulnak (hívásszámláló).
- [ ] **Más feature-ök érintetlenek:** `git diff --stat` nem tartalmaz
      `lib/features/{practice,song_trainer,ai_tutor,progress,analyze}/**`
      útvonalat.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Közvetlen import a másik feature belsejébe | a határ-őr teszt + `tool/check_architecture.dart` |
| Új allowlist-bejegyzés | a határ-őr „allowlist nem nőtt" cellája |
| Az adapter saját session score-t ad | a „Practice score nem duplikálódik" cella |
| A retry-tempo 60 % alá megy | a clamp-cella |
| A lépcsőhatár exkluzív | a „pontosan a határon" cella |
| A capo/transzpozíció összemosva | a hat MIDI-cellából a capo≠0, transzpozíció≠0 cellák |
| A sebesség nem skálázza az időbélyegeket | a 0.75× cella |
| A teljes dokumentum megy a Tutorhoz | a redakciós kulcs-teszt + az „≤ 50 event" cella |
| A snapshot mutálható | az immutabilitás cella |
| A progress evidence duplikálódik | a „másodszorra nem hoz újat" cella |
| **Valódi-sértés próba (§10):** egy redaktált mezőnév ideiglenes visszavétele a snapshotba → a redakciós kulcs-teszt **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/tooling test/app
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `test/tooling/analysis_cross_feature_boundary_test.dart` (az őr **előbb**).
2. RED: Practice round-trip, capo/transzpozíció, redakció, egyszeriség.
3. `practice_analysis_adapter.dart`.
4. `song_analysis_adapter.dart` (saját `SongReferenceSnapshot`, OD-01).
5. `tutor_analysis_snapshot.dart` (redakció + immutabilitás).
6. `progress_evidence_adapter.dart` (idempotens).
7. Flagek; gate.

## 9. Kockázatok

- **A Song és a Tutor barrelje nem elég gazdag** (OD-01, OD-02) — a kör így a
  **saját** oldalát szállítja teljesen, a fogyasztás follow-up. A §10-ben
  nevesíteni kell, melyik jövőbeli kör zárja ezt.
- **A `tool/check_architecture.dart` szigorítása** eltörhet más feature-t —
  ha egy meglévő import elbukik, az **megállás és jelentés**, nem az új
  szabály lazítása.
- **A concert/display pitch** a legkönnyebben elrontható rész — hat cella méri.

**STOP:** más feature módosítása, allowlist-bővítés vagy a teljes dokumentum
Tutorhoz küldése helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `practice_analysis_adapter.dart`: a publikus `CompiledPracticeTarget`
  snapshotot `AnalysisTarget`-té alakítja típus-inferenciával; a
  `definitionSnapshotVersion` a `targetVersion`, a retry-tempo névvel jelölt,
  inkluzív lépcsőkből és 60%-os alsó korlátból készül. A visszaadott evidence
  kizárólag facts/hotspots/retry-tempo/completion-eligibility, session score
  nincs.
- `song_analysis_adapter.dart`: OD-01 szerinti saját `SongReferenceSnapshot`
  contract. A transzpozíció utáni display MIDI és a capo-val módosított concert
  MIDI külön marad; a média-idő a lejátszási sebességgel skálázódik, majd kapja
  a backing offsetet. Song-oldali snapshot-feltöltés jövőbeli Song Trainer kör.
- `tutor_analysis_snapshot.dart`: OD-02 szerinti immutable, legfeljebb 50
  eventes, JSON-szinten redaktált snapshot. Tutor-oldali fogyasztása jövőbeli
  Tutor kör.
- `progress_evidence_adapter.dart`: `documentId`-kulcsos, egyszeri,
  `analysis-document.v<schema>` forrású skill-evidence; nem használ
  `PracticeEntry`-t.
- `public.dart`: a négy Analysis-oldali adaptercontract exportja.
- `feature_flags.dart`: `analysisPracticeIntegrationEnabled` és
  `analysisTutorIntegrationEnabled`, mindkettő minden environmentben OFF és
  része az értéksemantikának. OFF esetén a provider-factory nem példányosul.
- Az új adaptertesztek és boundary-őr a barrel-only importot és a változatlan
  12 elemű architecture allowlistet mérik.

### Mért numerikus értékek

`python3 -c` eredmény: retry lépcsők 100 BPM-nél `100/95/90/85`, alsó korlát
`60`; a concert/display MIDI mátrix `(capo, transpose) -> (display, concert)`:
`(0,0)->(60,60)`, `(0,-2)->(58,58)`, `(2,0)->(60,62)`,
`(2,-2)->(58,60)`, `(5,0)->(60,65)`, `(5,-2)->(58,63)`; a media-time cellák
mikroszekundumban `1000000/1250000/1583333` (alap / +250ms / +250ms 0.75x).

### Valódi-sértés próba

A `TutorAnalysisSnapshot.toJson()`-ba ideiglenesen visszahelyezett
`fileName` kulcsra a
`flutter test test/features/audio_analysis/application/tutor_analysis_snapshot_test.dart`
szándékosan piros lett: `Expected: not contains '"fileName"'`; a kulcsot
azonnal eltávolítottam, majd a célzott adaptertesztek 11/11 zöldek lettek.

### Futtatott ellenőrzések

- `flutter test test/tooling/analysis_cross_feature_boundary_test.dart`:
  kezdeti RED (hiányzó adapter-export), később zöld, 3/3.
- `flutter test test/features/audio_analysis/application/practice_analysis_adapter_test.dart test/features/audio_analysis/application/song_analysis_adapter_test.dart test/features/audio_analysis/application/tutor_analysis_snapshot_test.dart test/features/audio_analysis/application/progress_evidence_adapter_test.dart test/tooling/analysis_cross_feature_boundary_test.dart`:
  zöld, 12/12.
- A kötelező `tools/round-gate.sh test/features/audio_analysis test/tooling test/app`
  handoff után zöld: format, analyze, `audio_analysis` (533), tooling (64),
  app (73), architecture, secrets és l10n minden lépése sikeres. A teljes
  suite/property/APK csak CI-orchestrátor evidence, lokálisan nem futott.

### Eltérés / következő bekötés

`tool/check_architecture.dart` nem változott: az új barrel-only őr a meglévő
12 allowlist-bejegyzés változatlanságát méri. Sem Practice/Song/Tutor/Progress
feature-fájl, sem scoring API nem módosult.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r26-practice-song-tutor-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
**Kötelező:** `security-reviewer` (risk = high, AI-provider határ + adatminimalizálás).
