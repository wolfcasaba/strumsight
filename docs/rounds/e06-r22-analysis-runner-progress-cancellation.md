# E06-R22 — Analysis runner, progress UI és cancellation

- **Státusz:** PLANNING (előre megírva 2026-08-07, kód olvasva: main @ `a6e6f3d`; pre-flight revízió 2026-08-12, main @ `e0c6754e`, ADR 0240)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 22; §6.5, §21, §22.1–22.4
- **Branch:** `codex/e06-r22-analysis-runner-progress-cancellation`
- **Előfeltétel:** **E06-R04, E06-R06, E06-R21 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/application/analyze_audio_use_case.dart",
  "lib/features/audio_analysis/application/cancel_analysis_use_case.dart",
  "lib/features/audio_analysis/application/save_analysis_use_case.dart",
  "lib/features/audio_analysis/application/analysis_controller.dart",
  "lib/features/audio_analysis/application/analysis_state.dart",
  "lib/features/audio_analysis/application/analysis_isolate_runner.dart",
  "lib/features/audio_analysis/application/analysis_providers.dart",
  "lib/features/audio_analysis/presentation/analysis_progress_view.dart",
  "lib/features/audio_analysis/public.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/audio_analysis/application/analysis_controller_test.dart",
  "test/features/audio_analysis/application/analysis_cancellation_test.dart",
  "test/features/audio_analysis/presentation/analysis_progress_view_test.dart",
  "docs/rounds/e06-r22-analysis-runner-progress-cancellation.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/app",
  "test/features/analyze",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R04/R06/R21 merge.
> Olvasd újra a `lib/features/analyze/providers/analyze_providers.dart` **mai**
> practice/streak-kreditálását (224–238. sor: `recordPracticeToday()` +
> `PracticeEntry` — **csak** ha van chord vagy strum) és a
> `test/features/analyze/analyze_screen_test.dart`-ot. A V2 útnak
> **pontosan egyszer** kell kreditálnia, és a V1 útnak **változatlanul** kell
> működnie. Ellenőrizd, hogy az R21 `analysis_providers.dart`-ja már létezik-e
> — ha igen, ez a kör **bővíti**, nem újat hoz létre. PREPARED→PLANNING.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Pre-flight revízió (2026-08-12, main @ `e0c6754e`).**

1. A brief `main@a6e6f3d`-n, Epic 6 kezdete ELŐTT íródott — a §2 "Az R04 adja
   a pipeline-t + cancellation tokent, az R06 a felvevőt, az R21 a
   repository-t" mondat előrejelzés volt, nem mérés. Újramérve: mindhárom
   előfeltétel-kör (R04/R06/R21) MERGE-elve van, az `analysis_providers.dart`
   (R21) már létezik — ez a kör bővíti, nem hozza létre újra, a brief §pre-
   flight-note szerint helyesen.
2. **Mért architekturális rés, ADR-rel feloldva:** ma NULLA konkrét,
   összeszerelt V2 DSP `AnalysisPipeline<T>`-példány létezik a `lib/`-ben
   (`grep -rln "AnalysisPipeline(" lib/` üres), és a három meglévő konkrét
   `AnalysisStage` (`SignalQualityStage`, `PreprocessingStage`,
   `ClipAnalyzerStage`) egymással össze nem fűzhető I/O-jú — egyik sem a lánc
   végállomása. A brief §6 acceptance criteria ugyanakkor MINDEN cellája
   fake/minimális pipeline-t ír elő (a §6.1 mérce-mátrix és az OD-01
   alapértelmezése szó szerint ezt mondja), tehát ez NEM blokkoló hiány,
   csak egy pontosítandó feltételezés. [ADR
   0240](../adr/0240-analysis-runner-and-pipeline-boundary.md) rögzíti: a
   kör pipeline-agnosztikus marad, `T = AnalysisDocument`-re rögzítve, a
   valódi stage-lánc összeszerelése egy jövőbeli, még nem ütemezett kör
   feladata (nyíltan dokumentált résként, nem hallgatólagos hiányként a
   §10/HANDOFF-ban).
3. Az ADR ugyanezen mérése alapján rögzíti a run-ID hitelesség kérdését is
   (a pipeline belső `_activeRunId`-ja példányonként/isolate-onként
   nullázódik, ezért NEM használható a controller késői-eredmény szűrőjeként
   — a controller saját, a futtatás indításakor kapott run ID-t követő
   mezője az egyetlen igazságforrás) és az isolate-életciklust (egy-lövetű,
   futásonkénti spawn+kill, nem újrahasznosított isolate).

**Pre-flight alapján:** ADR: **0240** (analysis runner and pipeline
boundary).

## 1. Cél

A V2 pipeline bekötése egy **run ID-vezérelt** állapotgépbe: progress,
megszakítás, késői eredmény elutasítása, degradált állapot, és **pontosan
egyszeri** practice/streak kreditálás — a V1 Analyze út érintése nélkül.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- `AnalyzeController` (`Notifier<AnalyzeState>`): fázisok `idle`, `recording`,
  `analyzing`, `done`, `micDenied`, `micError`; **nincs** `cancelled`,
  `degraded`, progress vagy run ID. Szándékosan **nincs** `copyWith`.
- A kreditálás: `_analyze` végén, ha `result.chords.isNotEmpty ||
  result.strums.isNotEmpty` → `streakProvider.recordPracticeToday()` +
  `practiceLogProvider.record(PracticeEntry(...))` (224–238. sor).
- A hosszú munka **egyetlen** `compute()` hop, megszakíthatatlan
  (`computeClipAnalysis`, 108–121).
- A Lab-diagnosztika feltöltése fire-and-forget `unawaited(...)` (219–223).
- A képernyő-lifecycle védelme `_screenAttached` + a start-handshake alatti
  tab-váltás kezelése (140–179).
- Az R04 adja a pipeline-t + cancellation tokent, az R06 a felvevőt, az R21 a
  repository-t.

## 3. Scope

**Benne:** `AnalyzeAudioUseCase`, `CancelAnalysisUseCase`,
`SaveAnalysisUseCase`; `AnalysisController` (run ID, progress throttle,
degraded állapot, késői eredmény elutasítása); `AnalysisIsolateRunner`
(az R04 pipeline futtatása az UI isolate-on kívül, progress-csatornával és
cancel-jelzéssel); `AnalysisState` sealed hierarchia a SDD §21.1 tizenegy
állapotával; a progress **nézet** (egyetlen widget: fázis + magyarázat +
cancel gomb + szemantika); ARB.

**Kívül — TILOS:** a V1 `AnalyzeController`/`analyze_screen` módosítása,
overview/timeline UI (R23/R24), cache (R28), export (R27).

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/analyze_audio_use_case.dart` | ÚJ | futtatás |
| `.../application/cancel_analysis_use_case.dart` | ÚJ | megszakítás |
| `.../application/save_analysis_use_case.dart` | ÚJ | mentés (R21 repo) |
| `.../application/analysis_controller.dart` | ÚJ | állapotgép + run ID |
| `.../application/analysis_state.dart` | ÚJ | sealed állapotok |
| `.../application/analysis_isolate_runner.dart` | ÚJ | isolate + progress csatorna |
| `.../application/analysis_providers.dart` | meglévő/ÚJ | wiring |
| `.../presentation/analysis_progress_view.dart` | ÚJ | progress nézet |
| `.../public.dart` | meglévő | export |
| `lib/l10n/*.arb` | meglévő | **additív** fázis-szövegek |
| `test/**` | ÚJ | controller + cancel + widget teszt |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/progress/**`,
`lib/features/streak/**` (a **hívásuk** megengedett a `public.dart`-on át, a
módosításuk nem). Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Run ID mindenhol:** minden futás egyedi ID-t kap; **késői** progress vagy
   eredmény **csak** akkor írhat állapotot, ha a run ID az aktív. Ezt
   számláló méri (`rejectedLateResults`) — a mérés **eszköze**.
   **NEM elfogadható:** `if (mounted)`-szerű, ID nélküli védelem.
2. **A cancel nem hiba, és nem hagy szemetet:** cancel után az isolate
   felszabadul, a progress stream lezárul, a temp fájl törlődik, az állapot
   `cancelled`, és a **korábban mentett** session sértetlen.
   **NEM elfogadható:** `Failure` a cancelre, és **NEM elfogadható** a
   „majd a GC elviszi" isolate-kezelés.
3. **Pontosan egyszeri kreditálás:** a practice/streak kredit **csak**
   `complete` (nem `degraded`, nem `cancelled`, nem `failed`) eredményre,
   **futásonként egyszer**, és a **V1-gyel azonos** feltétellel
   (van chord **vagy** strum). **NEM elfogadható:** a kredit ismétlődése
   retry/tabváltás után, és **NEM elfogadható** a V1-től eltérő feltétel.
4. **A degradált eredmény külön állapot** (`degradedCompleted`), nem
   `completed` + warning.
5. **A progress nem árasztja el az UI-t:** a controller **eseményszám-alapú**
   throttle-t alkalmaz (nem `Timer`-t), hogy a teszt determinisztikus legyen.
   **NEM elfogadható:** minden pipeline-esemény továbbítása az UI-nak.
6. **A controller nem végez FFT-t, JSON-t vagy plugin-hívást** (SDD §21.5):
   kizárólag koordinál. **NEM elfogadható:** DSP vagy szerializáció a
   controllerben.
7. **A V1 út változatlan:** a V2 az `audioAnalysisV2Enabled` flag mögött él,
   és a V1 `AnalyzeController` **nem** módosul.

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: Hogyan megy a progress az isolate-ból a UI-ba?
    blocking: true
    resolution_policy: use_default
    default: >-
      `Isolate.spawn` + `SendPort`/`ReceivePort` pár (a `compute` nem tud
      progresszt), a runner mögé zárva; a TESZT az `AnalysisIsolateRunner`
      interfészét fake-eli, és NEM indít valódi isolate-ot — így a gate
      determinisztikus. Legalább EGY teszt viszont valódi isolate-ot indít
      (smoke), hogy a szerializálhatóság bizonyított legyen.
  - id: OD-02
    question: Mi történik a cancel után érkező részeredménnyel?
    blocking: true
    resolution_policy: use_default
    default: "eldobódik, és a `rejectedLateResults` számláló nő."
  - id: OD-03
    question: Retry?
    blocking: false
    resolution_policy: use_default
    default: "kizárólag explicit user action; automatikus retry NINCS."
```

## 6. Acceptance criteria

- [ ] **Állapot-mátrix — tíz cella:** teljes siker; degradált siker; cancel;
      stage-hiba (fatal); késői eredmény; **cancel utáni új futás**;
      tab-váltás futás közben; app háttérbe kerülése; permission denied;
      input error. Mindegyikre a **végállapot** és a mellékhatások
      (isolate, stream, temp fájl) ellenőrzöttek.
- [ ] **Késői eredmény:** run#1 indul → cancel → run#2 indul → run#1 késői
      progress- **és** eredmény-eventje **nem** írja az állapotot, és
      `rejectedLateResults == 2`.
- [ ] **Kredit-mátrix — hat cella:** `complete` + van esemény → **pontosan 1**
      `recordPracticeToday` és **pontosan 1** `PracticeEntry`;
      `complete` + **nincs** esemény → **0** kredit (a V1-gyel azonos
      feltétel); `degraded` → **0**; `cancelled` → **0**; `failed` → **0**;
      ugyanaz a futás **kétszer** publikálva (késői event) → **még mindig 1**.
- [ ] **Progress throttle küszöb hármas:** a throttle `minEventsBetweenEmits`
      = 5 mellett **4 / 5 / 6** pipeline-esemény után történik-e kibocsátás —
      az **5.** eseménynél igen (inkluzív), a 4.-nél nem. A számokat a teszt
      közvetlenül vezérli (fake pipeline).
- [ ] **Cancel-takarítás:** cancel után a fake isolate `disposed == true`,
      a progress stream `isClosed == true`, és a temp fájl-lista **üres**.
- [ ] **Nincs DSP a controllerben:** forrásolvasó teszt méri, hogy az
      `analysis_controller.dart` nem importál `engine/` fájlt közvetlenül
      (csak use case-eket), és nem tartalmaz `jsonEncode`/`jsonDecode` hívást.
- [ ] **Isolate smoke:** **egy** teszt valódi isolate-ot indít egy minimális
      pipeline-nal, és bizonyítja, hogy a bemenet és a kimenet
      **szerializálható** (nem dob `Invalid argument`-ot).
- [ ] **Progress-nézet szemantika:** a widget-teszt méri, hogy a fázis
      szövege **lokalizált**, a cancel gomb elérhető (`Semantics` label), és
      **nincs** százalék, ha a pipeline nem ad `completedUnits`-ot.
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**`, `lib/features/progress/**` vagy
      `lib/features/streak/**` útvonalat; a `test/features/analyze` zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Nincs run ID, csak `mounted`-szerű védelem | a `rejectedLateResults == 2` cella |
| A cancel `Failure`-t ad | az állapot-mátrix cancel-cellája |
| A cancel nem szabadítja fel az isolate-ot | a `disposed == true` cella |
| A kredit `degraded`-re is megy | a degradált **0 kredit** cella |
| A kredit feltétele eltér a V1-től | a „nincs esemény → 0 kredit" cella |
| A kredit ismétlődik késői eventre | a „még mindig 1" cella |
| A throttle exkluzív | a **pontosan 5. esemény** kibocsát-cella |
| A throttle `Timer`-alapú | a determinisztikus 4/5/6 cella (flakel vagy sosem tüzel) |
| A controller JSON-t szerializál | a forrásolvasó cella |
| A pipeline bemenete nem szerializálható | az isolate smoke cella |
| Hamis százalék jelenik meg | a progress-nézet „nincs százalék" cella |
| **Valódi-sértés próba (§10):** a run ID-ellenőrzés ideiglenes kiszedése → a késői-eredmény cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/app test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `analysis_state.dart` (sealed, 11 állapot).
2. RED: állapot-, kredit-, throttle- és késői-eredmény mátrix (fake runner).
3. Use case-ek (analyze / cancel / save).
4. `analysis_controller.dart` (run ID, throttle, degraded).
5. `analysis_isolate_runner.dart` + isolate smoke teszt.
6. `analysis_progress_view.dart` + ARB; gate.

## 9. Kockázatok

- **Az isolate-szerializálhatóság** buktathatja a kört (`Float64List` és a
  domain-objektumok átvitele) — az OD-01 smoke tesztje ezt **korán** kimutatja;
  ha a domain nem szerializálható, a runner a **codec** (R03) JSON-ját
  használja a határon, és ezt a §10 rögzíti.
- **A kredit duplázása** a legvalószínűbb regresszió — hat cella méri.
- **A V1 és V2 közös mikrofon-lease-e** (R06 OD-01) azt jelenti, hogy a két út
  kizárja egymást; a UI-üzenet follow-up.

**STOP:** a V1 controller módosítása, automatikus retry vagy a kredit
feltételének megváltoztatása helyett `stopped` + brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Codex implementation — 2026-08-12

- `application/analysis_state.dart` — sealed, tizenegy állapotos V2 state
  machine; futáshoz kötött terminális/analyzing állapotok run ID-t hordoznak.
- `application/analyze_audio_use_case.dart`, `cancel_analysis_use_case.dart`,
  `save_analysis_use_case.dart` — a runner, cancellation handle és repository
  save szűk application-határai.
- `application/analysis_isolate_runner.dart` — futásonként friss isolate,
  JSON codec-határ, progress stream és kill+port-cleanup cancellation. A
  `AnalysisRunner` interface-et a controller tesztjei fake-elik.
- `application/analysis_controller.dart` — controller-saját aktív run ID,
  késői progress/result elutasítás-számláló, eseményszámláló-alapú inkluzív
  5-ös throttle, explicit cancel és pontosan egyszeri V1-alakú kredit-döntés.
- `application/analysis_providers.dart` — use-case és V1-kompatibilis
  practice/streak adapter; a konkrét V2 runner provider fail-closed,
  `StateError`-ral jelzi a még hiányzó stage-listát.
- `presentation/analysis_progress_view.dart` + ARB — lokalizált fázis,
  magyarázat, szemantikus cancel; egységszám nélkül nincs százalék.
- `public.dart` — additív V2 application/presentation export.

**Acceptance evidence.** `analysis_controller_test.dart` 10 zöld tesztje fedi
a teljes/degradált/fatal/cancelled végállapotokat, permission/input hibát,
cancel utáni új futást, tab-váltást és háttérbe kerülést, a késői progress és
result `rejectedLateResults == 2` elutasítását, a V1-azonos kreditpredikátum
eventes/üres/degradált/fatal/late esetét, valamint a 4/5/6 throttle-hármast.
`analysis_cancellation_test.dart` 2 zöld tesztje méri a fake run dispose,
stream-close és üres temp-lista cancel-takarítását, illetve a valódi
`Isolate.spawn` JSON codec smoke-ot. `analysis_progress_view_test.dart` zöld:
lokalizált fázis, semantic cancel és nincs hamis százalék. A controller
forrásolvasó tesztje kizárja a közvetlen `engine/` importot és a JSON hívást.
A V1-érintetlenséget a `test/features/analyze` gate-útvonal és a scope audit
bizonyítja.

**Futtatott ellenőrzések.** Célzottan zöld:
`flutter test test/features/audio_analysis/application/analysis_controller_test.dart`
(10), `flutter test test/features/audio_analysis/application/analysis_cancellation_test.dart`
(2), `flutter test test/features/audio_analysis/presentation/analysis_progress_view_test.dart`
(1), `flutter analyze` (No issues found). A kötelező
`tools/round-gate.sh test/features/audio_analysis test/app test/features/analyze`
záró, dokumentáció utáni futása zöld volt (format, analyze, mindhárom
teszt-útvonal és architecture).

**Git diff --stat (staged, záráskor):** 15 fájl, 1262 beszúrás, 3 törlés.

**Nyitott follow-up.** A valódi több-stage DSP pipeline összeszerelése
(közös work-state és konkrét `AnalysisStage<AnalysisDocument,
AnalysisDocument>` lista) szándékosan nincs ebben a körben: ADR 0240 Döntés 4
szerint egy jövőbeli, még nem ütemezett kör adja majd a
`analysisV2RunnerProvider` felülírását. A V2 flag továbbra is default `false`,
így ez a nyitott wiring nem user-facing regresszió.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e06-r22-analysis-runner-progress-cancellation-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
