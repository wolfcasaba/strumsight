# E99-R10 — Review

Brief: docs/rounds/e99-r10-gov-30c-2-evaluation-stage-composition.md
Diff: `git diff 8c41612d...codex/e99-r10-gov-30c-2-evaluation-stage-composition` (`8c41612d..e49c5ee0`)
Reviewer: Claude (Sonnet 5, pipeline orchestrator) · Dátum: 2026-08-14
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 4

Első Terra-dispatch (session `019fffcc-…`) `stopped`-ot jelzett egy valós,
mért ütközésen: a brief 11 önálló értékelő stage-et kért, de a meglévő
`engine/analysis_pipeline.dart` `AnalysisPipeline<T>` konstruktora legfeljebb
`AnalysisProgressPhase.values.length` (9) stage-et enged
(`analysis_pipeline.dart:68-74`). Az orchesztrátor ezt egy dokumentált §0.0
brief-revízióval + ADR 0251 §5 kiegészítéssel oldotta fel (nem a forbidden
`analysis_pipeline.dart`/`analysis_progress.dart` módosításával): a production
kód továbbra is 11 granular stage-et épít, de a composition-teszt közvetlen,
szekvenciális `stage.run(...)` hívásokkal bizonyítja a láncot
`AnalysisPipeline` példányosítás helyett. A második Terra-dispatch (session
`019fffd7-…`) ez alapján implementált és `done`-t jelzett.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | `seed` elfogad `target`-et, `null` a default | ✅ | `analysis_work_state_test.dart`: „seed carries…” (target null) + „seed retains an explicitly supplied target without inferring one” (`same(target)` — referencia-azonosság, nincs másolás/következtetés) |
| A2 | Minden értékelő stage `AnalysisStage<AnalysisWorkState, AnalysisWorkState>` | ✅ | fordítás (analyze zöld) + `evaluation_pipeline_composition_test.dart` „A2” — 11 stage ID fix sorrendben |
| A3 | Referenciával: illesztés lefut, timing-metrikák megjelennek | ✅ | „A3–A5” teszt: `withReference.value!.alignment` not-null, `presentReferenceMetricIds.difference(absentReferenceMetricIds) == TimingMetricSuiteIds.target.all` |
| A4 | Referencia nélkül: `alignment == null`, timing-capability unavailable, nincs timing-metrika | ✅ | ugyanaz a teszt: `withoutReference.value!.alignment` null, `withoutReference.unavailableCapabilities` tartalmazza `timingAccuracy`-t, a metrika-halmaz-diff bizonyítja a timing-metrikák hiányát |
| A5 | Referencia nélkül a referencia-független metrikák ugyanúgy kiszámolódnak | ✅ | `absentReferenceMetricIds.intersection(DynamicsMetricIds.all) == DynamicsMetricIds.all` és ugyanez `RhythmMetricSuiteIds.inferred.all`-lal |
| A6 | `EventAligner` nem hívódik meg üres `expected`-del | ✅ | `evaluation_stages_test.dart` „A6” — injektált `align` hívás-számláló, `callCount == 0`; **önállóan is verifikálva** (lásd „Próbatesztek”) |
| A7 | `hasReferenceTarget` a `target` mezőből jön, nem az `AnalysisMode`-ból | ✅ | „A3–A5” teszt `withEmptyReference` ága: `mode: AnalysisMode.practiceTarget` + üres `expectedEvents` → `capabilityReports[timingAccuracy]!.reason == CapabilityUnavailableReason.noReferenceTarget` (a meglévő, E06-R19-es `CapabilityResolver` `hasReferenceTarget`-alapú logikáját méri, `capability_resolver.dart:189-192`) |
| A8 | A capability/confidence hibája megállítja a láncot | ✅ | „A8” teszt: fatális `_FailingStage` a 11. helyen → `result.value == null`, `result.failure != null` |
| A9 | `analysisV2RunnerProvider` a kör után is `StateError`-t dob | ✅ | `application/analysis_providers.dart:213-218` — a kör diffje `application/**`-t egyáltalán nem érinti (mérve, ld. lent) |
| A10 | Nulla DSP-matematika az adapterekben | ✅ | teljes `evaluation_stages.dart` átolvasva: minden stage a meglévő, review-zott modult hívja (`EventAligner`, `buildTargetTimingMetrics`, `buildRhythmMetrics`, `buildGatedPitchMetrics`, `buildDynamicsMetrics`, `detectLocalAccents`, `SubdivisionAnalyzer`, `buildChordTransitions`, `buildTechniqueProxyReport`, `CapabilityResolver`); az egyetlen saját logika esemény-VÁLASZTÁS (`_metricEvents`/`_strumEvents`, listaszűrés) és egy egyszerű számtani átlag (`modelConfidence`) — se nem szűrés, se nem transzformáció jel szinten |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. Önállóan futtatva izolált
`/tmp/review-e99-r10` klónban:

```
$ python3 tools/scope-audit.py --repo /tmp/review-e99-r10 --brief docs/rounds/e99-r10-gov-30c-2-evaluation-stage-composition.md --base 8c41612d
Legacy scope audit OK (8c41612d..e49c5ee04419, 6 changed path(s), 0 generated/ignored)
```

A 6 megváltozott útvonal pontosan az `allowed_paths` hat bejegyzése (2 engine +
3 teszt + a round brief §10 handoff).

## Megállapítások

### N1 — NOTE — `TechniqueProxyReport.metrics` elvész, bár a típus hordozná

- **Fájl:** `lib/features/audio_analysis/engine/stages/evaluation_stages.dart:347-374` (`TechniqueEvaluationStage`)
- **Megfigyelés:** a hívott `buildTechniqueProxyReport(...)` eredménye
  (`TechniqueProxyReport`) rendelkezik `List<AnalysisMetricResult> metrics`
  mezővel (`technique_proxies.dart:100-109`, ugyanaz a minta, mint a
  rhythm/pitch/dynamics stage-eknél), de a stage sosem olvassa ki — `return
  input;` a teljes report eldobásával. Jelenleg **hatástalan**: a hívás
  `analysisTechniqueProxiesEnabled: false, labModeActive: false`-szal megy,
  ami mindig `TechniqueProxyReport.disabled()`-t ad üres metrika-listával —
  az osztály doc-commentje ezt explicit ki is mondja („remain disabled and
  non-persisted until… a later round”). Nem blokkoló, mert egyetlen
  acceptance-cella sem méri a technique-proxy metrikák felszínre kerülését,
  és a mai kimenet a KAPCSOLÁS mellett is üres lenne.
- **Ajánlás:** ha egy jövőbeli kör kinyitja a Lab/flag kaput, ellenőrizze,
  hogy ez a discard nem marad-e csendben — érdemes lenne már itt
  `_appendMetrics(input, report.metrics)`-re cserélni, hiszen a mai
  `disabled()` ág változatlanul üres listát adna, tehát a csere kockázatmentes
  lett volna. Follow-up, nem ehhez a körhöz kötött gate.
- **Státusz:** OPEN (follow-up, nem blokkol)

### N2 — NOTE — Accent/subdivision/transition eredménye szerkezetileg nem fér bele a `metrics` listába

- **Fájl:** `evaluation_stages.dart:284-343` (`AccentEvaluationStage`,
  `SubdivisionEvaluationStage`, `TransitionEvaluationStage`)
- **Megfigyelés:** `detectLocalAccents` → `AccentDetectionResult`,
  `SubdivisionAnalyzer.analyze` → `SubdivisionAnalysis`, `buildChordTransitions`
  → `List<ChordTransition>` — egyik sem `AnalysisMetricResult`-alakú, és a
  brief nem ad kódolási receptet ezekhez (§3.1 csak öt mezőt sorol fel a
  munkaállapot bővítésére). A stage-ek ezért kiszámolják, majd eldobják az
  eredményt — csak a hívás-lánc elhelyezését/hibaosztályozását bizonyítják,
  a payloadot nem publikálják. Ez a helyes döntés EBBEN a körben (a brief
  explicit tiltja a saját kódolási séma kitalálását: „ne írj DSP-matematikát
  az adapterekben”), de azt jelenti, hogy ez a három modul MA nem jut el a
  leendő `AnalysisDocument`-ig.
- **Ajánlás:** a GOV-30c-3 pre-flightja mérje meg explicit, hogyan (vagy
  hogy egyáltalán) szükséges-e ezt a három jelentést a dokumentumba vinni —
  ez nem ennek a körnek a hibája, hanem egy nyitva hagyott, névvel ellátandó
  kérdés a bekötő körnek.
- **Státusz:** OPEN (follow-up a GOV-30c-3 pre-flightjának)

### N3 — NOTE — `modelConfidence` számítási módja új, brief-ben nem specifikált döntés

- **Fájl:** `evaluation_stages.dart:400-406` (`CapabilityConfidenceEvaluationStage`)
- **Megfigyelés:** `modelConfidence` a megfigyelt események `confidence`
  mezőinek súlyozatlan számtani átlaga (üres listánál `0.0`). A
  `CapabilityResolverInput.modelConfidence` egy PRIOR körből (E06-R19)
  örökölt kötelező mező; valakinek ki kellett választania egy képletet, mert
  a brief ezt nem írta elő. A választás biztonságos irányba téved (üres
  bemenet → 0.0, nem 1.0), és `[0,1]`-be esik minden bemenetre (az egyedi
  `confidence` értékek maguk is `[0,1]`-esek), de nincs dedikált unit teszt,
  ami a KONKRÉT átlagképletet — szemben pl. egy súlyozott vagy medián
  változattal — bizonyítaná.
- **Ajánlás:** ha egy jövőbeli kör érdemben épít erre az értékre (pl. UI-n
  megjelenő számként), érdemes ADR-szinten rögzíteni a képletet és
  hozzá edge-case tesztet írni. Nem blokkol, mert A1–A10 egyike sem
  specifikálja a pontos formulát, és a mai felhasználó felé nincs
  viselkedésváltozás (a `analysisV2RunnerProvider` változatlanul
  `StateError`-t dob).
- **Státusz:** OPEN (follow-up, nem blokkol)

### N4 — NOTE — a típus-illesztő helper a stage-fájlban él, nem a munkaállapot-fájlban

- **Fájl:** `evaluation_stages.dart:472-498` (`_hasReferenceTarget`,
  `_strumEvents`, `_metricEvents`, `_beatDuration`)
- **Megfigyelés:** a brief §9 kockázat-listája („A metrika-modulok bemeneti
  típusai eltérnek… A típus-illesztés önálló, tesztelt konverzió legyen a
  **munkaállapot fájljában**”) szó szerint az `analysis_work_state.dart`-ra
  utal; Terra ehelyett az ÚJ `evaluation_stages.dart` alján, privát,
  megosztott függvényekként központosította ugyanazt (nem szórta szét
  stage-enként). A centralizációs SZÁNDÉK teljesült, csak más fájlban — nem
  produkál duplikációt vagy rejtett DSP-t (tiszta lista-válogatás,
  `_beatDuration` egyszerű fail-safe alapérték-visszaadás).
- **Státusz:** OPEN (kozmetikai, nem blokkol)

## Próbatesztek (eldobható, dokumentálva)

**A6 valódi-sértés próba, önállóan megismételve** (a brief §6.1 kötelező
mércéje) — `/tmp/review-e99-r10`-ban ideiglenesen az üres-lista ág
eltávolítva (`if (target == null || target.expectedEvents.isEmpty) return
input;` → `if (target == null) return input;`), majd:

```
$ flutter test test/features/audio_analysis/engine/stages/evaluation_stages_test.dart test/features/audio_analysis/engine/evaluation_pipeline_composition_test.dart
…
00:00 +0 -1: … A6 — empty expected events never call the EventAligner [E]
  Expected: <Instance of 'Success<AnalysisWorkState>'>
    Actual: Failure<AnalysisWorkState>:<Failure<AnalysisWorkState>(unknown)>
00:00 +1 -2: … A3–A5 — the three reference cells preserve independent metrics [E]
  Expected: null
    Actual: <Instance of 'AlignmentResult'>
Some tests failed.
```

Mindkét érintett teszt PIROSRA vált, ahogy a mérce előírja. `git checkout --
lib/…/evaluation_stages.dart` után újra zöld
(`test/…/evaluation_stages_test.dart`: „All tests passed!”). A guard tehát
ténylegesen tartja magát, nem díszlet.

## Architektúra + termékhatárok

- **Domain-függetlenség / rétegződés:** `evaluation_stages.dart` kizárólag
  `domain/`, `engine/` testvér-modulokat és `core/foundation`-t importál —
  nincs Flutter/Riverpod/Dio/storage import. `application/**`,
  `public.dart`, `core/flags/**`, `engine/stages/ingest_stages.dart`
  TARTALMA és minden meglévő `engine/**` modul TARTALMA érintetlen (mérve
  `git diff --stat` a forbidden-zone útvonalakra — nulla sor).
- **Termékhatár (§5 „Gyenge confidence nem jelenhet meg biztos állításként”):**
  a legveszélyesebb hibamód (üres referenciával hamis illesztés) az A6
  próbateszttel MÉRVE zárva; a `CapabilityConfidenceEvaluationStage` minden
  bemeneti hiányt (`signalQuality == null` → fatális `StateError`, üres
  `metrics` → `modelConfidence = 0.0`, hiányzó `alignment` →
  `alignmentQuality = 0`) biztonsági irányba told, sosem fabrikál magas
  bizonyosságot hiányzó bemenetből.
- **Lifecycle:** nincs `StreamSubscription`/isolate/mic/timer/wakelock a
  diffben — pure, szinkron/aszinkron függvény-hívási lánc, nincs felszabadítandó
  erőforrás.
- **`dynamic`/`Object` kerülőút, üres `catch`, production `print`:** egyik
  sem található a diffben; `_runSafely` egyetlen `catch (error, stackTrace)`
  ága explicit `UnknownFailure`-ba csomagol, nem nyel el csendben.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (Terra) | ✅ — önállóan újrafuttatva izolált klónban, zöld |
| analyze | zöld (Terra) | ✅ — önállóan, `No issues found!` |
| `evaluation_pipeline_composition_test.dart` | zöld (Terra) | ✅ — önállóan, 3/3 teszt |
| `evaluation_stages_test.dart` | zöld (Terra) | ✅ — önállóan, 1/1 teszt |
| `analysis_work_state_test.dart` | zöld (Terra) | ✅ — önállóan, 6/6 teszt |
| architecture | zöld (Terra) | ✅ — önállóan, „12 allowlisted deviation(s)” (pre-existing, nem ez a kör hozta) |
| secrets | (nem állította, a gate maga futtatja) | ✅ — önállóan, 0 lelet |
| l10n | (nem állította, a gate maga futtatja) | ✅ — önállóan, paritás OK |
| CI (teljes suite + property + APK) | — | folyamatban, lásd a merge-döntés szakaszt |

Mind a nyolc lokális gate-lépés ZÖLD egy tőlem független, izolált
`/tmp/review-e99-r10` klónban (nem a megosztott munkafán) — a jelentett
eredmény tehát nem bemondás.

## Biztonsági review

`risk = "high"` a brief `ai-router` blokkjában → kötelező, párhuzamosan
dispatch-elve a `security-reviewer` ágenssel
(`docs/reviews/e99-r10-security.md`). Ennek a jelentésnek a lezárása
független, a merge-döntés bevárja.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge. A
correctness-review szerint ez a feltétel **teljesül** (0 BLOCKER, 0 MAJOR, 4
NOTE, mind follow-up). A tényleges merge-et a kötelező biztonsági review
lezárása és a CI (full-gate/build-apk + Router CI) zöldje előzi meg.
