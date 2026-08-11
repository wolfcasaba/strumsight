# E06-R04 — Pipeline contract, stage context és progress

- **Státusz:** PREPARED → PLANNING (R1 revízió, 2026-08-11, orchesztrátor
  pre-flight — kód újraellenőrizve: main @ `4796d539`, előre megírva
  2026-08-07 @ `a6e6f3d`)
- **SDD-kör:** [`docs/sdd/07-epic-06-audio-analysis-2.md`](../sdd/07-epic-06-audio-analysis-2.md) Kör 4; §6.4–6.6, §8.4–8.5, §21.2, §22.4
- **Branch:** `codex/e06-r04-pipeline-contract-stage-and-progress`
- **Előfeltétel:** **E06-R02 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/audio_analysis/engine/analysis_pipeline.dart",
  "lib/features/audio_analysis/engine/analysis_stage.dart",
  "lib/features/audio_analysis/engine/analysis_context.dart",
  "lib/features/audio_analysis/engine/analysis_cancellation.dart",
  "lib/features/audio_analysis/domain/analysis_progress.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/engine/analysis_pipeline_test.dart",
  "test/features/audio_analysis/engine/analysis_cancellation_test.dart",
  "test/support/fake_analysis_stages.dart",
  "test/property/analysis_pipeline_property_test.dart",
  "docs/rounds/e06-r04-pipeline-contract-stage-and-progress.md",
]
gate_tests = [
  "test/features/audio_analysis",
  "test/property",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** friss `origin/main` + E06-R02 merge. Olvasd újra
> a `test/support/` meglévő fake-jeit (`fake_audio.dart`, `fake_engines.dart`,
> `fake_practice_session_clock.dart`) — az új fake stage-ek **azok stílusát**
> követik, nem új mintát vezetnek be. Ellenőrizd, hogy az R02 `public.dart`
> exportja tartalmazza-e már a progress-típust; ha igen, a duplikálás
> scope-sértés. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED → PLANNING (R1 revízió, 2026-08-11, orchesztrátor pre-flight).**
Új ADR nincs — a kör kizárólag a Ch7 §6.4–6.6, §8.4–8.5, §21.2, §22.4
alatt már elfogadott SDD-szerződéseket (progress-fázisok, stage-interfész,
cancellation token, run ID/késői-esemény szabály) ülteti át konkrét Dart
kódba; a §5 hét „kötött architekturális döntése" ezeknek a szerződéseknek a
tétel-szintű lebontása, nem új keresztmetsző elv.

### R1 — ADR-átszámozás (mért, pipeline-prompt §1)

A brief 2026-08-07-i megírásakor az E06-R01 hat ADR-jét még nem foglalták le,
ezért a §5.7 pont a `0200` placeholder-számot idézte. Az E06-R01 tényleges
`reserve-adr` futása **0215–0220**-at adta (lásd [ADR
0215](../adr/0215-analysis-document-versioning.md) fejléce, `HANDOFF.md`
E06-R01/E06-R02 close-out és az E06-R02 brief saját R1 revíziója —
ugyanabból a batch-ből származó, ugyanaz a drift). Leképezés (megegyezik az
E06-R02 R1 revíziójával): `0200→0215` (dokumentum-verziózás). A §5.7 pont
javítva **ADR 0215**-re.

Egyéb §2 „Jelenlegi állapot" állítás újra grep-elve **egyezik**: a
`computeClipAnalysis` híváslánc (`analyze_providers.dart:108-121`), a Lab-ági
`catch (_)` diagnosztika-elnyelés (`analyze_providers.dart:74-77`), a CRNN→
heurisztika `catch (_)` visszaesés (`clip_analyzer.dart:108-110`), az
`AnalyzeController`/`AnalyzeState` copyWith-mentessége, és az R02 domain
(`AnalysisCompletionStatus{complete,degraded,cancelled,failed}`,
`AnalysisWarning`, `AnalysisProvenance.stageVersions`) mind bitre egyeznek a
kódban mérttel. A `public.dart` MA nem exportál progress-típust (nincs
duplikáció-kockázat), és az `engine/` könyvtár még nem létezik (mind az öt
fájl valóban ÚJ). Nincs további revízió.

## 1. Cél

A moduláris, **megszakítható**, progresszt publikáló elemzési pipeline
**szerződése** — konkrét DSP nélkül. A kör kimenete az a váz, amibe az R07–R20
stage-ei bekötnek, és amin a cancel/degraded/fatal viselkedés **egyszer** és
tesztelten eldől.

## 2. Jelenlegi állapot (mért, `a6e6f3d`)

- A mai elemzés **egyetlen** `compute()` hívás
  (`analyze_providers.dart` 108–121): `computeClipAnalysis(pcm, sr, labMode)`
  → `runClipAnalysis` → `ClipAnalyzer.analyze`. **Nincs** progress, **nincs**
  cancellation, **nincs** stage-fogalom, **nincs** run ID.
- A részleges eredmény ma ad-hoc: a CRNN-hiba `catch (_)`-ben esik vissza a
  heurisztikára (`clip_analyzer.dart` 108–110), a Lab-ág `catch (_)`-ben
  dobja el a diagnosztikát (`analyze_providers.dart` 74–77). Ez **nem**
  degradált-jelölés, csak elnyelés.
- A `Notifier`-alapú `AnalyzeController` állapota `AnalyzeState{phase, result}`;
  szándékosan **nincs** `copyWith` (a doc-comment szerint azért, hogy ne
  vihessen tovább elavult `result`-ot) — de **run ID** nincs, így egy késői
  eredmény ma is felülírhatná az állapotot, ha lenne párhuzamos futás.
- Az R02 domain adja: `AnalysisDocument`, `AnalysisCompletionStatus`
  (`complete`/`degraded`/`cancelled`/`failed`), `AnalysisWarning`,
  `AnalysisProvenance` (stage-verziókkal).

## 3. Scope

**Benne:** `AnalysisStage<I,O>` interfész (`id`, `version`, `run`);
`AnalysisStageContext` (cancellation token, progress sink, provenance-gyűjtő,
stage-timing); `AnalysisPipeline` (sorrendben futtat, progresszt publikál,
cancellationt ellenőriz, **degradálható** és **fatális** hibát elkülönít,
stage ID/verziót provenance-be ír, késői eventet run ID-val szűr);
`AnalysisCancellationToken`; `AnalysisProgressEvent` sealed hierarchia a
kilenc SDD-fázissal; fake stage-ek a teszthez.

**Kívül — TILOS:** valódi DSP-stage, isolate-runner (R22), UI (R22/R23),
repository, `lib/features/analyze/**` érintése.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../engine/analysis_stage.dart` | ÚJ | stage interfész + result envelope |
| `.../engine/analysis_context.dart` | ÚJ | stage context (token, sink, timing) |
| `.../engine/analysis_cancellation.dart` | ÚJ | token + `throwIfCancelled` |
| `.../engine/analysis_pipeline.dart` | ÚJ | kompozíció + hibaosztályozás |
| `.../domain/analysis_progress.dart` | ÚJ | sealed progress event (fázisok) |
| `.../public.dart` | meglévő | progress + token export |
| `test/support/fake_analysis_stages.dart` | ÚJ | determinisztikus fake stage-ek |
| `test/features/audio_analysis/engine/*` | ÚJ | pipeline + cancel tesztek |
| `test/property/analysis_pipeline_property_test.dart` | ÚJ | progress-monotonitás property |

**Tilos zóna:** `lib/features/analyze/**`, `lib/features/live/**`,
`lib/features/audio_analysis/data/**`, `lib/features/audio_analysis/presentation/**`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Kétféle stage-hiba, egy szerződésben:** `StageFailure.degradable` →
   a pipeline **folytatódik**, warning + capability `unavailable` keletkezik,
   a végeredmény `degraded`; `StageFailure.fatal` → a pipeline **megáll**,
   `failed`. **NEM elfogadható:** `catch (_) { }` üres elnyelés, és **NEM
   elfogadható**, hogy egy degradálható hiba az egész futást megölje.
2. **A cancellation kooperatív és ellenőrzött:** a pipeline **minden stage
   előtt ÉS után** ellenőrzi a tokent, a hosszú ciklusok
   `throwIfCancelled()`-et hívnak. Cancel után a pipeline **nem publikál**
   dokumentumot, a progress stream **lezárul**, a completion `cancelled`.
   **NEM elfogadható:** a cancel „a következő stage-nél majd észrevesszük"
   típusú, csak stage-határon ellenőrzött megvalósítása a stage-en BELÜLI
   checkpoint-szerződés nélkül.
3. **A cancel nem hiba:** `AnalysisCompletionStatus.cancelled`, nem
   `AppFailure`. **NEM elfogadható:** cancel → `Failure` a hívó felé.
4. **Run ID szűri a késői eventet** (SDD §21.2): a pipeline minden futása
   egyedi run ID-t kap, és a progress/result eventeken hordozza; egy korábbi
   run eventje **eldobódik**, és ezt **számláló** méri (a mérés eszköze:
   a pipeline `droppedLateEvents` számlálót ad vissza a diagnosztikában).
5. **Nincs globális mutable state:** a stage-ek példányonként állapotmentesek,
   a kontextus a paraméter. **NEM elfogadható:** statikus cache a stage-ekben.
6. **Duplikált stage ID tiltott:** a pipeline felépítésekor **kontrollált
   hiba**, nem „az utolsó nyer".
7. **A stage timing provenance-be kerül** (id, version, elapsed), és a
   `stage.version` változása az analyzer-verzió számításának bemenete
   (ADR 0215).

### 5.1 Nyitott döntések — előre rögzített feloldással

```yaml
open_decisions:
  - id: OD-01
    question: A progress százalékot publikáljon?
    blocking: true
    resolution_policy: use_default
    default: >-
      NEM — fázis + részlépés (SDD §6.4: "a százalék csak akkor mutatható, ha
      determinisztikusan becsülhető"). A progress event opcionális
      `completedUnits/totalUnits` párt hordozhat, de a UI-nak nem kötelező.
  - id: OD-02
    question: A progress stream broadcast vagy single-subscription?
    blocking: false
    resolution_policy: use_default
    default: >-
      single-subscription `Stream` a pipeline-ból; a broadcast-ra alakítás a
      controller (R22) dolga — így a pipeline tesztje nem függ a listener
      számától.
```

## 6. Acceptance criteria

- [ ] **Stage-sorrend:** N=5 fake stage-re a futási sorrend és a
      provenance-be írt sorrend **azonos**, és a stage-timing mind az 5
      bejegyzésre jelen van.
- [ ] **Progress-sorrend:** a publikált fázisok az SDD §6.4 sorrendjét
      követik, **szigorúan monoton** fázisindexszel; a property-teszt véletlen
      stage-összeállításokra is méri.
- [ ] **Cancel-mátrix — négy cella:** (a) cancel **az első stage előtt**;
      (b) cancel **két stage között**; (c) cancel **stage KÖZBEN**
      (a fake stage `throwIfCancelled`-et hív a ciklusában); (d) cancel az
      **utolsó stage után, a dokumentum összeállítása előtt**. Mind a négyben:
      `cancelled` completion, **nincs** publikált dokumentum, a progress
      stream lezárt.
- [ ] **Degradálható vs fatális mátrix:** ugyanaz a fake hiba
      `degradable`-ként → a futás befejeződik, completion `degraded`,
      pontosan **1** warning, a hibás stage kimenete hiányzik; `fatal`-ként →
      completion `failed`, a következő stage **nem futott** (a fake stage
      hívásszámlálója 0).
- [ ] **Késői event mátrix:** run#1 elindul, cancel, run#2 elindul; run#1
      késve érkező progress- és result-eventje **eldobódik**, és
      `droppedLateEvents == 2`. A számláló a mérés **eszköze** — nélküle a
      cella mérhetetlen lenne.
- [ ] **Duplikált stage ID:** két azonos `id`-jű stage-ből álló pipeline
      felépítése **kontrollált hibát** ad (nem csendes felülírást).
- [ ] **Nincs Flutter a pipeline-ban:** az öt új `engine/` + `domain/` fájl
      egyike sem importál `package:flutter`-t; a teszt `flutter_test` nélkül,
      **tiszta Dart** unit-tesztként is lefut (a gate `test` lépése ezt
      futtatja).
- [ ] **V1 érintetlen:** `git diff --stat` nem tartalmaz
      `lib/features/analyze/**` útvonalat, és a V1 gate zöld.

> **Küszöb-konvenció:** minden numerikus küszöbhöz a mátrix **három** cellát
> ad — szigorúan **alatta**, pontosan **rajta**, szigorúan **fölötte** —, és a
> cellák értékei `python3 -c`-vel kiszámoltak, nem idealizált rácsból becsültek
> ([`docs/LESSONS.md`](../LESSONS.md) L13).

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A cancel csak stage-határon ellenőrződik | a cancel-mátrix **(c) stage KÖZBEN** cellája |
| A cancel `Failure`-t ad | a „cancel nem hiba" completion-cella |
| Cancel után is publikálódik a dokumentum | a cancel-mátrix mind a négy „nincs dokumentum" cellája |
| A degradálható hiba megöli a futást | a `degraded` completion + „a következő stage FUTOTT" cella |
| A fatális hiba után is fut a következő stage | a fatal-cella hívásszámláló `== 0` elvárása |
| A run ID szűrés hiányzik | a `droppedLateEvents == 2` cella |
| Duplikált stage ID esetén az utolsó nyer | a duplikált-ID kontrollált-hiba cella |
| A progress fázis nem monoton | a progress-sorrend property-teszt |
| **Valódi-sértés próba (§10):** a `throwIfCancelled` hívás ideiglenes törlése a fake stage ciklusából → a (c) cella **PIROS** → visszaállítás |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis test/property test/features/analyze
```

Külön processzek, nincs `&&`/pipe/`tail`.

## 8. Implementációs sorrend

1. `test/support/fake_analysis_stages.dart` (számlálós, cancellálható fake-ek).
2. RED: cancel-, degradált/fatális-, késői-event- és duplikált-ID-mátrix.
3. `analysis_cancellation.dart` + `analysis_progress.dart`.
4. `analysis_stage.dart` + `analysis_context.dart`.
5. `analysis_pipeline.dart` (hibaosztályozás, run ID, provenance).
6. Property-teszt; gate.

## 9. Kockázatok

- **A `Zone`-alapú cancellation csábító, de nem tesztelhető determinisztikusan**
  — a kör explicit token-szerződést ír elő, `Zone` nélkül.
- **A progress stream lezárása cancelnél könnyen kimarad** → a cancel-mátrix
  mind a négy cellája külön méri.
- **A degradált/fatális elkülönítés később DSP-döntéssé válik** (melyik stage
  melyik osztályba tartozik) — itt csak a **mechanizmus** dől el; a besorolás
  az adott stage körének a dolga.

**STOP:** ha a pipeline szerződéséhez az R02 domain módosítása kellene, az
**megállás és jelentés**, nem néma fájllista-tágítás.

## 10. Implementation handoff — az implementer tölti ki

### Megvalósítás

- `lib/features/audio_analysis/engine/analysis_cancellation.dart`: per-run,
  kooperatív cancellation token/source és kontrollált cancellation exception.
- `lib/features/audio_analysis/domain/analysis_progress.dart`: a Ch7 §6.4
  kilenc rendezett fázisa, run ID-s progress- és terminális result-eventek.
- `lib/features/audio_analysis/engine/analysis_stage.dart` és
  `analysis_context.dart`: a szó szerinti generikus stage contract, per-stage
  context, progress sink, valamint immutable stage-verzió/timing provenance.
  A sealed core `AppFailure` változatlan maradt; a degradálható/fatális döntést
  a `StageFailure` burkoló és a pipeline composition classifier hordozza.
- `lib/features/audio_analysis/engine/analysis_pipeline.dart`: stage-sorrend,
  cancellation előtti/utáni kontrollpont, degradálás/fatális leállás, run-ID
  alapú késői-event eldobás (`droppedLateEvents`) és dokumentum nélküli
  `cancelled` eredmény.
- `lib/features/audio_analysis/public.dart`: a cross-feature progress- és
  cancellation-contract exportja (engine implementáció nem exportált).
- `test/support/fake_analysis_stages.dart` és az új engine/property tesztek:
  determinisztikus számlálós fake, cancel/degradált/fatális/késői-event/
  duplikált-ID mátrix, illetve 80 determinisztikus véletlen stage-összeállítás
  monoton progress property-je.

### Acceptance evidence

1. **Stage-sorrend + provenance:** az `AnalysisPipeline runs stages in order
   and records every stage version and timing` teszt öt fake stage pontos
   futási-, verzió- és timing-sorrendjét ellenőrzi.
2. **Progress:** a property teszt 80, 1–9 stage-es összeállítást futtat;
   minden publikált fázis indexe szigorúan nő, akkor is, ha a stage nem küld
   saját progress-eventet (pipeline fallback).
3. **Cancel-mátrix:** a célzott teszt mind a négy cellája zöld: első stage
   előtt, két stage között, stage checkpoint közben és utolsó stage után;
   mindegyik `cancelled`, `value == null`, result-event nélküli és lezárt
   progress streamű. A valódi-sértés próbában a fake ciklusból ideiglenesen
   kivett `throwIfCancelled()` mellett a stage-közbeni cella elvárt módon
   piros lett (`completedCheckpoints`: várt 0, tényleges 3); a hívás vissza
   lett állítva.
4. **Degradálható/fatális:** ugyanaz a `MlFailure` degradálhatóként egy
   warningot és unavailable capability-t ad, majd futtatja a következő
   stage-et; fatal-ként `failed`, és a következő fake hívásszámlálója 0.
5. **Késői event:** cancel utáni run#2 mellett run#1 késő progress- és
   result-eventje eldobódik; a célzott teszt `droppedLateEvents == 2`-t mér.
6. **Duplikált ID:** a konstruktor kontrollált `ArgumentError`-t ad.
7. **Tiszta Dart:** `dart test test/features/audio_analysis/engine
   test/property/analysis_pipeline_property_test.dart` zöld; az öt új
   engine/domain production fájlban a `rg 'package:flutter' ...` ellenőrzés
   nem adott találatot.
8. **V1 érintetlen:** a teljes gate `test/features/analyze` lépése zöld, és a
   diff nem tartalmaz `lib/features/analyze/**` utat.

### Futtatott ellenőrzések

- RED: `flutter test test/features/audio_analysis/engine/analysis_cancellation_test.dart`
  — a még nem létező cancellation-contract importja miatt elvárt fordítási
  hibával állt meg.
- Célzott: `dart test test/features/audio_analysis/engine
  test/property/analysis_pipeline_property_test.dart` — 12 teszt zöld.
- Valódi-sértés: a checkpoint-hívás ideiglenes eltávolítása után a stage-közbeni
  cancel-teszt piros; visszaállítás után a pipeline teszt 9/9 zöld.
- Kötelező gate: `tools/round-gate.sh test/features/audio_analysis
  test/property test/features/analyze` — kilépési kód 0; format, analyze,
  mindhárom test-cél, architecture, secrets és l10n zöld.

### Diff és eltérések

`git diff --cached --stat` a staging után:

```text
 ...e06-r04-pipeline-contract-stage-and-progress.md |  86 ++++++-
 .../audio_analysis/domain/analysis_progress.dart   |  55 +++++
 .../engine/analysis_cancellation.dart              |  28 +++
 .../audio_analysis/engine/analysis_context.dart    |  91 ++++++
 .../audio_analysis/engine/analysis_pipeline.dart   | 248 +++++++++++++++++++
 .../audio_analysis/engine/analysis_stage.dart      |  35 +++
 lib/features/audio_analysis/public.dart            |   2 +
 .../engine/analysis_cancellation_test.dart         |  31 +++
 .../engine/analysis_pipeline_test.dart             | 270 +++++++++++++++++++++
 test/property/analysis_pipeline_property_test.dart |  47 ++++
 test/support/fake_analysis_stages.dart             |  62 +++++
 11 files changed, 954 insertions(+), 1 deletion(-)
```

Nincs eltérés a brief scope-jától. Nem futott Android APK build vagy CI-dispatch:
ezek az orchesztrátor merge-előtti feladatai. Következő kör: **E06-R05** a
kijelölt Epic 6 sorrendben.

## 11. Review — a független reviewer tölti ki

**APPROVED** (2026-08-11) — `docs/reviews/e06-r04-pipeline-contract-stage-and-progress-review.md`.
0 BLOCKER, 0 MAJOR, 1 MINOR (deferred follow-up — R07 pre-flight kötelező
ellenőrzés a `publishResult`-ra), 5 NOTE. Dedikált biztonsági review
(risk=high): **PASS**, 0 CRITICAL/BLOCKER/MAJOR —
`docs/reviews/e06-r04-pipeline-contract-stage-and-progress-security.md`.
Scope-audit (gépi ÉS saját): 11/11 fájl az engedélyezett listán belül. Két
saját valódi-sértés próba (cancel-checkpoint guard, fatal-stage early-stop
guard) mindkettő a várt cellát bukta meg, majd visszaállítva. Full Gate
(`31494921432`) + Router CI (`31494909290`) mindkettő success az exact SHA
`ea8d95d9`-n. Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN
BLOCKER/MAJOR után — mindhárom teljesül.
