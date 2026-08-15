# E99-R13 — Review

Brief: `docs/rounds/e99-r13-gov-30c-5-runner-audio-path-and-wiring.md`
Diff: `1636b40d..7c6b762e`
Reviewer: Codex (gpt-5.6-terra) · Dátum: 2026-08-15
Verdikt: CHANGES REQUIRED

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

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
