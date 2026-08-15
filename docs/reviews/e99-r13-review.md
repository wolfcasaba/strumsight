# E99-R13 — Review

Brief: `docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md`
Diff: `1636b40d..7c6b762e`
Reviewer: Codex (gpt-5.6-terra) · Dátum: 2026-08-15
Verdikt: APPROVED

## Összegzés

Nyitott lelet: BLOCKER 0 · MAJOR 0 · MINOR 0 · NOTE 1 (F2, scope-on kívüli).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Provider valódi runnert ad | ✅ | `v2_analysis_runner_test.dart`, célzott futás zöld |
| A2–A3 | PCM → dokumentum a teljes builder-láncon | ✅ funkcionálisan | ugyanazon célzott teszt zöld; `buildFullAnalysisStages()` a runnerben |
| A4 | PCM nem kerül a dokumentumba | ✅ | A4 zöld; valódi-sértés próbában a marker beírása pirosra váltotta a cellát, visszaállítás után újra zöld |
| A5–A7 | target, cancellation, shadow-továbbadás | ✅ / a teljes kör-gate állítása szerint | implementer gate-bizonyíték; a teljes független gate nem adott terminális kimenetet ebben a harnessben |
| A8–A9 | flag és engine érintetlen | ✅ | scope-diff és audit: nincs tiltott útvonal |

## Scope-audit

`python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e99-r13 --brief docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md --base 1636b40d` → `Legacy scope audit OK` (10 változott útvonal, ebből a brief-revízió és a megengedett alkalmazás-/tesztfájlok). Engedélyezett fájlokon kívüli implementációs változás nincs.

## Megállapítások

### F1 — MAJOR — A teljes V2 DSP-lánc a UI-isolate-ban fut

- **Fájl:** `lib/features/audio_analysis/application/v2_analysis_runner.dart:16-36`
- **Probléma:** `V2AnalysisRunner.start()` közvetlenül egy in-process `AnalysisPipeline`-t indít. Az `AnalysisIsolateRunner` üzenet-határa bővült ugyan PCM-mel és targettel, de a V2 provider nem használja azt.
- **Hatás:** a teljes 20-stage DSP-lánc a UI-isolate-on fut. Ez eltér az ADR 0254 következményétől (PCM → dokumentum „izolátumban, megszakíthatóan”), és a brief §2.3/§5.2 explicit isolátum-határától. A brief §10 handoff erre hivatkozott „ADR 0254 §5.4” nem létezik az ADR-ben, ezért nem felmentés.
- **Kötelező javítás:** a valódi V2 futást izolátumba kell vinni úgy, hogy a jelenlegi `AnalysisRunHandle` cancellation/progress szerződés és az A2–A6 tesztelhető maradjon. A meglévő `analysis_isolate_runner.dart` és `v2_analysis_runner.dart` a briefben engedélyezett helyek; ne nyiss tiltott utat és ne lazíts tesztet.
- **Ellenőrzés:** a brief teljes `tools/round-gate.sh` parancsa, plusz olyan célzott teszt, amely bizonyítja, hogy a V2 stage-ek tényleg az izolátum-oldali futtatásból jönnek.
- **Státusz:** FIXED (9ff4c246) — a `V2AnalysisRunner` mostantól az `AnalysisIsolateRunner`-re delegál (nem saját `AnalysisPipeline`-t indít in-process). Az izolátum-határ `operation` szerződése egy `reportProgress` callback-kel bővült, hogy a per-stage fázis-események (A2/A3) továbbra is átjussanak; a végső drótra kerülő dokumentum `completion` mezője a pipeline hiteles összesített állapotát (`pipelineResult.completion`) kapja, mert a dokumentum-összeállító stage saját `completion` mezője csak az ingest-időbeli kapacitás-állapotot tükrözi (ez okozta az A5 piros futását, amíg a drót-dokumentum a saját, korábbi mezőjét vitte át változatlanul). Új, célzott teszt (`v2_analysis_runner_test.dart`, „F1 — the 20-stage chain runs off the calling isolate…”) bizonyítja esemény-sorrenddel (timer előbb, mint az eredmény), hogy a lánc valóban nem a hívó izolátumon fut. A `tools/round-gate.sh` a brief §7 parancsával (mind a négy célzott teszt-fájl) zölden lefutott.

### F2 — NOTE — A controller út továbbra is üres PCM-helyőrzőt használ

- **Fájl:** `lib/features/audio_analysis/application/analyze_audio_use_case.dart:19-31`
- **Megfigyelés:** a `AnalysisController` még csak dokumentumot ad át, ezért ez a use case szándékosan üres PCM-et képez. A brief §10.5 ezt ismert, későbbi körre halasztott korlátként rögzíti; a flag-ek továbbra is OFF-on vannak.
- **Státusz:** NOTE — nem ennek a körnek a scope-ja, de rollout előtt valódi capture/import út szükséges.

### F3 — MAJOR — Az izolátumból jövő progress runId-ja nem a külső handle-é

- **Fájl:** `lib/features/audio_analysis/application/analysis_isolate_runner.dart:171-177`, `lib/features/audio_analysis/application/v2_analysis_runner.dart:58-75`
- **Probléma:** a V2 pipeline az izolátumban `analysis-run-1` azonosítójú progress-eventeket küld, míg az `AnalysisIsolateRunner` által visszaadott handle azonosítója `analysis-isolate-1`. A szülő változtatás nélkül továbbítja az eseményt.
- **Hatás:** `AnalysisController._onProgress` kizárólag az aktív handle `runId`-jával egyező eseményt fogad el (`analysis_controller.dart:109-120`); ezért minden valódi V2 progress-event eldobódik késői eredményként. Ez megsérti a változatlan `AnalysisRunHandle.progress` contractot.
- **Kötelező javítás:** a szülő isolate runnerben a bejövő progress-eventeket a külső `runId`-ra kell újracsomagolni/térképezni, a phase és számláló-adatok változatlan megőrzésével. Adj regressziós tesztet, amely a handle és minden továbbított phase-event `runId` egyezését ellenőrzi.
- **Ellenőrzés:** a brief teljes `tools/round-gate.sh` parancsa és az új regressziós teszt.
- **Státusz:** FIXED (f5129590) — az `AnalysisIsolateRunner._IsolateAnalysisRun` mostantól minden izolátumból beérkező `AnalysisProgressEvent`-et a saját (külső) `runId`-jára térképez (`_remapRunId`), a `phase`/`completedUnits`/`totalUnits` adatok érintetlenül maradnak. Új regressziós teszt (`v2_analysis_runner_test.dart`, „F3 — every forwarded progress event carries the handle's runId, not the isolate-internal pipeline runId") ellenőrzi, hogy minden továbbított esemény `runId`-ja a handle `runId`-jával egyezik. A brief §7 négy célzott teszt-fájlos `tools/round-gate.sh` parancsa zölden lefutott (format/analyze/mind a négy teszt/architecture/secrets/l10n).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format/analyze/architecture/célzott kör-gate | implementer: zöld | a wrapper `done` jelzése és handoff rögzíti; a reviewerben indított teljes gate kétszer az analyze-lépés után terminális kód nélkül szakadt meg, ezért önmagában nem újraigazolt |
| `v2_analysis_runner_test.dart` | zöld | ✅ függetlenül lefutott: 7 teszt zöld |
| A4 valódi-sértés | zöld állapotban nem szivárog | ✅ ideiglenes codec-markerrel a cella piros, visszaállítás után zöld |
| CI (teljes suite + property + APK) | nincs | ❌ review előtt nem dispatch-elhető az F1 miatt |

## Merge-döntés

Az F3 nyitott MAJOR, ezért ADR 0052 szerint merge tilos. Javító implementer-kör szükséges ugyanazon branchen.

## Független újraellenőrzés — 2026-08-15 (friss main-re rebase után)

Verdikt: CHANGES REQUIRED

Az `origin/main` friss `c1d3b089` SHA-jára rebase-elt diff scope-auditja
zöld (`12 changed path(s), 2 generated/ignored`). A reviewer saját, izolált
klónjában a brief §7 pontos `tools/round-gate.sh` hívása teljesen zöld lett:
format, analyze, mind a négy célzott teszt, architecture, secrets és l10n.
Az A4 valódi-sértés próbában a `0.918273645` PCM-marker a drót-dokumentum
`input.fingerprint` mezőjébe került; az A4 teszt várt módon piros lett
(`Expected: false, Actual: true`), majd a változtatás vissza lett állítva.

### F4 — MAJOR — A lezárt handle a nyers PCM-et a futás után is megtartja

- **Fájl:** `lib/features/audio_analysis/application/analysis_isolate_runner.dart:137-139,259-270`
- **Probléma:** `_IsolateAnalysisRun` végleges `request` mezője tartja az
  `AnalysisRunRequest.audio.input.samples` listát. A teljesítés és a
  `cancel()` is csak az izolátumot/portokat zárja le; a requestet nem engedi
  el. Bármely hívó, amely a már lezárt `AnalysisRunHandle`-t megtartja,
  ezzel a nyers PCM-et is erősen elérhetővé teszi.
- **Hatás:** sérti a brief §5.2 és ADR 0254 §2 előírását, hogy a minta a futás
  végén eldobódik. Ez privacy- és memória-élettartam-hiba, nem pusztán GC-időzítés.
- **Kötelező javítás:** a belső request/audio referencia legyen megszüntethető,
  és spawn után, illetve minden terminális/cancel úton legyen nullázva; teszt
  bizonyítsa a teljesítés és a cancel utáni audio-elengedést. Csak a briefben
  engedélyezett `analysis_isolate_runner.dart` és célzott tesztfájlok érinthetők.

Az F1 és F3 javítását az izolált gate a megfelelő célzott tesztekkel újra
igazolta, de F4 nyitott MAJOR mellett merge tilos. Ugyanazon `sonnet-impl`
motor javító köre szükséges.

## F4 javításának független ellenőrzése — 2026-08-15

Verdikt: APPROVED

Az `fe0c905f` javítás a `_IsolateAnalysisRun` belső request referenciáját
nullázhatóvá tette. A referencia a spawn átadása után, `cancel()` esetén és az
összes terminális `_dispose()` úton elengedésre kerül. Két regressziós teszt
ellenőrzi, hogy befejezett, illetve spawn közben törölt run handle után a
handle már nem tart requestet, így a PCM-listát sem.

Az új, izolált klónban végrehajtott, a brief §7 szerinti teljes gate zöld:
format, analyze, a négy célzott teszt, architecture, secrets és l10n. A friss
mainre vett scope-audit is zöld (`c1d3b089..fe0c905f`, 12 changed paths,
2 generated/ignored). Az F4 javításnak nincs nyitott BLOCKER vagy MAJOR
utóhatása.

## Rebase utáni független ellenőrzés — 2026-08-15

Verdikt: APPROVED

Az `ef6f5d41` exact head a `bf07f415` mainre történt tiszta rebase eredménye;
a kör saját alkalmazás- és tesztdiffje változatlan maradt. Egy új, izolált
`/tmp/review-e99-r13-UMEMmZ` klónban a kötelező scope-audit
`Legacy scope audit OK (12 changed path(s), 2 generated/ignored)` eredményt
adott. A brief §7 szerinti teljes `tools/round-gate.sh` hívás zölden lezárult:
format, analyze, a négy célzott teszt, architecture, secrets és l10n.
Nyitott BLOCKER vagy MAJOR nincs; a merge további feltétele kizárólag az
exact-`ef6f5d41` CI-bizonyíték.
