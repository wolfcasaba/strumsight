# E06-R04 — Review

Brief: `docs/rounds/e06-r04-pipeline-contract-stage-and-progress.md`
Diff: `git diff f0a89502...ea8d95d9` (implementer commit over the orchestrator
pre-flight commit); `git diff origin/main...ea8d95d9` for the full round diff.
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-11
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 (deferred follow-up, lásd lent) · NOTE: 5

Egyfordulós implementáció (`continuations=0`), gépi scope-audit `ok`
(11/11 fájl az engedélyezett listán), a kör saját gate-je zöld, a
független újrafuttatás (izolált `/tmp` klón) is zöld, és két saját
valódi-sértés próba mindkettő a várt cellát fogta.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Stage-sorrend (N=5, futási + provenance sorrend azonos, mind az 5 timing jelen) | ✅ | `analysis_pipeline_test.dart:17-56` „runs stages in order…"; `runOrder`/`stageVersions`/`stageTimings` mind az 5 bejegyzést tartalmazza, sorrendben |
| 2 | Progress-sorrend, szigorúan monoton, property-teszten is | ✅ | `analysis_pipeline.dart:127-136` (`publish()` `StateError`-ral bukik nem-monoton fázisra) + `analysis_pipeline_property_test.dart` — 80 determinisztikus (LCG-seedelt, 1–9 stage-es) minta, mind szigorúan nő |
| 3 | Cancel-mátrix, mind a 4 cella | ✅ | `analysis_pipeline_test.dart:60-131` parametrizált teszt (before/between/during-checkpoint/after-final); mind a 4: `cancelled`, `value=null`, nincs `AnalysisRunResultEvent`, `isProgressClosed=true`. Saját Probe A (lásd lent) a (c) cellát piros-visszaigazolta |
| 4 | Degradálható vs fatális mátrix | ✅ | `analysis_pipeline_test.dart:133-176` — degradable: `degraded`, 1 warning, `stageOutputs` nem tartalmazza a bukott stage-et, a következő stage lefut (`calls=1`); fatal: `failed`, a következő stage hívásszámlálója 0. Saját Probe B (lásd lent) a fatal-early-stop ágat piros-visszaigazolta |
| 5 | Késői event mátrix, `droppedLateEvents==2` | ✅ | `analysis_pipeline_test.dart:178-202` — run#1 stale contextje run#2 aktívvá válása UTÁN hív `reportProgress`+`publishResult`-ot; `pipeline.droppedLateEvents == 2` |
| 6 | Duplikált stage ID → kontrollált hiba | ✅ | `analysis_pipeline_test.dart:204-213` `throwsArgumentError`; `analysis_pipeline.dart:73-78` konstruktor-validáció |
| 7 | Nincs Flutter a pipeline-ban | ✅ | Saját `grep -rn "package:flutter" lib/features/audio_analysis/engine/ .../analysis_progress.dart` — 0 találat (függetlenül futtatva, nem az implementer állítására hagyatkozva) |
| 8 | V1 érintetlen | ✅ | `git diff --stat` nem tartalmaz `lib/features/analyze/**`-t; a gate `test test/features/analyze` lépése zöld (63/63) |

## Scope-audit

Saját, független `git diff --stat origin/main...ea8d95d9`: **pontosan a 11
engedélyezett fájl** (5 production, 3 új teszt, 1 property-teszt, 1 fake, a
round brief `§10` handoff). Egyezik a gépi jelzés `scope_audit=ok`,
`scope_audit_changed=11` mezőivel. Listán kívüli fájl: **nincs**.

## Valódi-sértés próbák (eldobható, saját kézzel, izolált `/tmp` klónban futtatva)

**Probe A — cancel-checkpoint guard.** A `test/support/fake_analysis_stages.dart`
ciklusából ideiglenesen kivettem a `context.cancellationToken
.throwIfCancelled()` hívást (a brief §6.1 utolsó sorának saját megismétlése,
függetlenül az implementer saját állításától). Eredmény: a „during a stage
checkpoint" cancel-teszt PIROS lett (`Expected: <0>, Actual: <3>` —
mindhárom checkpoint lefutott, a cancel észrevétlen maradt). Visszaállítva,
zöld.

**Probe B — fatal-stage early-stop guard (saját, az implementer állításától
független cella).** Az `analysis_pipeline.dart`-ban ideiglenesen
`if (false && !classifiedFailure.isDegradable)`-re cseréltem a fatális-ág
feltételét. Eredmény: a „stops after a fatal stage failure…" teszt PIROS lett
(`Expected: AnalysisCompletionStatus.failed, Actual:
AnalysisCompletionStatus.degraded` — a pipeline a fatális hibát átcsúsztatta
a degradálható ágba, a következő stage lefutott volna). Visszaállítva, zöld.

Mindkét próba után `git status --short` a klónban tiszta — nincs vissza nem
állított mutáció.

## Architektúra + termékhatárok (AGENTS.md §5/§6)

- Domain-függetlenség: `analysis_progress.dart` framework-mentes (csak
  `analysis_document.dart`-ot importál). Az `engine/` réteg is tiszta Dart —
  ellenőrizve (lásd 7. acceptance).
- `public.dart`: **csak** a progress- és cancellation-contract export
  (`analysis_progress.dart`, `engine/analysis_cancellation.dart`) — az
  engine implementáció (`analysis_stage.dart`, `analysis_context.dart`,
  `analysis_pipeline.dart`) **szándékosan nem** cross-feature export. Egyezik
  a brief §4 „progress + token export" sorával.
- `StageFailure` a sealed core `AppFailure`-t **kompozícióval** bővíti
  (`isDegradable`/`unavailableCapabilities` egy burkoló osztályon), nem a
  sealed hierarchia módosításával — nem sérti a core-ot.
- Gate `architecture` lépés (izolált klónban, saját kézzel futtatva): zöld
  (12 allowlistolt eltérés, változatlan az implementáció előtti állapothoz
  képest — nem nőtt).
- Erőforrás-lifecycle: a `StreamController` **minden** kilépési úton
  lezárul (`finish()` mindig hívja, `unawaited`-del — helyesen, mert egy
  single-subscription controller `close()`-ja hallgatólagos listener nélkül
  sosem teljesülne; a teszt `_observe` helper emiatt külön várja meg az
  `onDone`-t is, nem csak a `result`-ot). Nincs időzítő, nincs mic/isolate
  ebben a körben.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futtatás, izolált `/tmp` klón |
| analyze | zöld | ✅ saját futtatás |
| test test/features/audio_analysis | zöld | ✅ saját futtatás |
| test test/property | zöld | ✅ saját futtatás (80/80 minta) |
| test test/features/analyze | zöld (63/63, V1 regressziómentesség) | ✅ saját futtatás |
| architecture | zöld | ✅ saját futtatás |
| secrets | zöld (2170 fájl, 0 lelet) | ✅ saját futtatás |
| l10n | zöld (1019 kulcs) | ✅ saját futtatás |
| Router CI (push, `ea8d95d9`) | success | ✅ `gh run view 31494909290` |
| Full Gate (workflow_dispatch, `ea8d95d9`) | success (11m17s) | ✅ `gh run view 31494921432` |
| Biztonsági review (risk=high, AGENTS.md §15.1) | **PASS**, 0 CRITICAL/BLOCKER/MAJOR, 1 MINOR, 4 NOTE | ✅ `docs/reviews/e06-r04-pipeline-contract-stage-and-progress-security.md` |

## Megállapítások

### F1 — MINOR (deferred follow-up) — Stage tetszőleges terminális eredményt injektálhat a progress streambe

- **Fájl:** `lib/features/audio_analysis/engine/analysis_context.dart:89-90`
  (`AnalysisStageContext.publishResult`) +
  `lib/features/audio_analysis/engine/analysis_pipeline.dart:129-143`
  (`publish` — a result-eventek megkerülik a monoton-fázis ellenőrzést).
- **Teljes elemzés:** a dedikált biztonsági review MINOR-1 pontja (`docs/reviews/e06-r04-pipeline-contract-stage-and-progress-security.md`) —
  reprodukált próbával: egy stage `publishResult(complete)`-et hívhat, ami a
  pipeline saját, valódi terminális eventje ELŐTT landol a streamen, a
  pipeline tényleges (pl. `degraded`/`failed`) eredményétől függetlenül.
- **Hatás MOST:** nulla — a `analysis_context.dart` nincs a `public.dart`-ban
  exportálva (nem cross-feature elérhető), és a kör egyetlen fake stage-e
  sem hívja a `publishResult`-ot (holt, spekulatív felület egy jövőbeli
  isolate-backed stage-hez).
- **Döntés (orchesztrátor, 2026-08-11):** **NEM ebben a körben javítjuk** —
  a kör kizárólag a szerződést vezeti be, a `publishResult`-nak ma nincs
  hívója, és a helyes javítás (eltávolítás VAGY a pipeline-hitelesség
  megkülönböztetése) egy tervezési döntés, ami akkor dől el helyesen, amikor
  egy valódi stage-nek először lesz rá oka (R07 DSP-bekötés vagy R22
  isolate-consumer). **Kötelező R07 pre-flight ellenőrzés** (a HANDOFF.md-be
  felvéve): vagy távolítsd el a `publishResult`-ot, ha még mindig hívatlan,
  vagy zárd le a `publish()`-t stage-eredetű terminális eventek ellen,
  MIELŐTT bármelyik valódi stage hívhatná.
- **Státusz:** OPEN (deferred follow-up, nem ennek a körnek a hatásköre)

### N1 — NOTE — Homogén `AnalysisPipeline<T>` vs. az SDD §8.4 heterogén stage-lánca

- **Fájl:** `lib/features/audio_analysis/engine/analysis_pipeline.dart:59-63`
- **Megfigyelés:** a kör `AnalysisPipeline<T>`-je `List<AnalysisStage<T, T>>`-t
  vár — minden stage-nek UGYANAZT a `T`-t kell fogyasztania/termelnie. Az SDD
  §8.4 kompozíció-diagramja (InputValidator → Preprocessor →
  SignalQualityStage → FeatureExtractionStage → … →
  AnalysisDocumentAssembler) koncepcionálisan **heterogén** átalakító-láncot
  sugall (más bemenet/kimenet stage-enként). A brief ezt nem zárja ki (a
  `AnalysisStage<I,O>` generikus interfész homogén megvalósítása is érvényes
  példány), és ebben a körben csak `int→int` fake stage-ek vannak — nem
  falszifikálható most.
- **Hatás:** nem blokkoló MOST. Az R07+ stage-eknek vagy (a) egyetlen közös
  „munkaállapot" burkolótípuson kell osztozniuk (envelope-minta), vagy (b) a
  pipeline-nak heterogén kompozícióra kell bővülnie — ez a döntés nincs
  kimondva.
- **Javasolt irány:** a következő DSP-stage-et bekötő kör (R07) pre-flightja
  explicit döntsön (és ha kell, dokumentáljon egy §0.0 revíziót vagy ADR-t)
  arról, melyik mintát követi.
- **Státusz:** OPEN (follow-up, nem ennek a körnek a hatásköre)

### N2 — NOTE — `dirty_files=1` a `done` jelzésben, tiszta fában

- **Fájl:** `.codex-round-status` (gitignore-olt, nem trackelt)
- **Megfigyelés:** a záró jelzés `dirty_files=1`-et írt, de a munkapéldány
  (`/home/ubuntu/ss-terra-e06-r04`) a jelzés után közvetlenül és a review
  minden pontján **tisztán** állt (`git status --short` üres, HEAD =
  `ea8d95d9`, minden az 11 engedélyezett fájlban commitolva). A
  `tools/codex-signal.sh` a `dirty_files` mezőt `git status --porcelain`
  puszta sorszámával számolja, a `.codex-round-status`-t magát NEM zárja ki
  (szemben a `codex-round.sh` saját `verify_claim()`-jével, ami igen) — a
  legvalószínűbb magyarázat egy időzítési műtermék a jelzésfájl saját
  írása körül, nem elveszett munka.
- **Hatás:** nincs — a jelen kör evidenciáját nem gyengíti (a tényleges
  tartalom teljes és tiszta).
- **Javasolt irány:** ha ismétlődik más köröknél is, a `codex-signal.sh`
  `dirty_files` számítása kapja meg ugyanazt a `.codex-round-status`
  kizárást, mint a `codex-round.sh` `verify_claim()`-je — ez nem ennek a
  körnek a hatásköre (`tools/` védett zóna, AGENTS.md §15.1 „a MÉRCÉHEZ nem
  nyúlsz").
- **Státusz:** OPEN (tooling follow-up, nem kód-hatáskör)

### N3 — N5 — lásd a dedikált biztonsági review-t

A dedikált biztonsági review (`docs/reviews/e06-r04-pipeline-contract-stage-and-progress-security.md`)
három további NOTE-ot rögzít (intra-fázis `completedUnits` és a szigorú
monoton-fázis kapu ütközése; nincs timeout a `stage.run()`-on — tudatos
körhatár; `UnknownFailure.cause` nyers hiba/stacktrace, ma nem renderelt/
loggolt) — mind forward-looking, egyik sem blokkol, nem ismétlem itt.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge. **Mindkettő teljesül:** a Full Gate (`31494921432`, exact-SHA
`ea8d95d9`, 11m17s) és a Router CI (`31494909290`) is **success**; a
biztonsági review **PASS**, 0 CRITICAL/BLOCKER/MAJOR. Az egyetlen MINOR
(F1) tudatosan deferred follow-up, nem OPEN blokkoló. **Merge engedélyezve.**
