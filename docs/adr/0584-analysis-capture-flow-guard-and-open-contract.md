# ADR 0584 — Az Analysis V2 felvevő-ág gépi őre és a „korábbi elemzés megnyitása" szerződése

**Státusz:** elfogadva (2026-09-18, E17-R02 — Chapter 17 „Teljes bekötés", Kör 2)

**Kör:** `E17-R02` · **Brief:** [`docs/rounds/e17-r02-analysis-v2-capture-wiring.md`](../rounds/e17-r02-analysis-v2-capture-wiring.md)

Kapcsolódik: [ADR 0241](0241-analysis-overview-presentation-boundary.md) §1 (a V2
route-ok fail-closed `extra`-szerződése), [ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)
(párhuzamos V2 rollout-határ), [ADR 0275](0275-five-area-shell-behind-a-flag.md) §1
(a flag-rollout termékdöntés), [ADR 0087](0087-round-brief-scope-authority.md) §2
(a kör-brief scope-hatásköre), [ADR 0112](0112-self-healing-pipeline.md) §2
(a kör pre-flight-revíziója).

## Kontextus

A három capture-képernyő (`AnalysisHomeScreen`, `AnalysisRecordingScreen`,
`AnalysisProcessingScreen`) bekötése **nem ebben a körben született**: a
`050e45028` commit (2026-09-05) a pipeline-on kívül elvégezte. A kör
pre-flightja ezt mérte újra a `main @ 4c12083c`-n:

```
$ dart run tool/check_screen_reachability.dart --format json
AnalysisHomeScreen        reachable=true  flagGated=true  conds=[audioAnalysisV2Enabled]
AnalysisRecordingScreen   reachable=true  flagGated=true  conds=[audioAnalysisV2Enabled]
AnalysisProcessingScreen  reachable=true  flagGated=true  conds=[audioAnalysisV2Enabled]
```

A commit azonban **bizonyíték nélkül** landolt: nincs hozzá kör-brief, review, ADR,
és a három route-konstansra (`AppRoutes.analysisCapture|analysisRecord|
analysisProcessing`) a teljes `test/` fában nulla mérő cella hivatkozik. A
projekt mércéje szerint (`AGENTS.md` §12, [L09](../LESSONS.md#l09)) a működő kód
és a bizonyított kód nem ugyanaz: őr nélkül a bekötést bármelyik későbbi kör
észrevétlenül visszabonthatja, és a flag-kötöttség elcsúszása sem bukna ki.

A pre-flight ezen felül egy MÉRT hibát talált a bekötésben:

```
app_router.dart  onOpenAnalysis: (summary) => context.go(AppRoutes.analysisTimeline, extra: summary)
app_router.dart  path: AppRoutes.analysisTimeline
                 redirect: (_, state) => state.extra is AnalysisDocument ? null : AppRoutes.live
```

Az `AnalysisSummary` nem `AnalysisDocument`, tehát a „korábbi elemzés
megnyitása" koppintás **mindig** a fail-closed ágra, a `/live` képernyőre visz.

## Döntés

1. **A bekötést gépi őr rögzíti, nem a commit-üzenet.** A kör egyetlen új mérő
   fájlja (`test/features/audio_analysis/capture_wiring_test.dart`) pinneli: a
   három route létét és flag-kötöttségét MINDKÉT flag-álláson, a
   home → recording → processing átmenetet valós providerekkel, és a widgetek
   injektált szerződését. A bejárás-cellák a megjelenő KÖVETKEZŐ KÉPERNYŐ
   típusát mérik, nem csak a `router.state.uri.path`-t
   ([L654](../LESSONS.md#l654)).

2. **A rollout-kapu marad az `audioAnalysisV2Enabled`, és a kör az ÉRTÉKÉT nem
   írja át.** Új, capture-specifikus flag nem születik: két igazságforrás
   ugyanarra a rollout-döntésre. A mérés `appConfigProvider`-override-dal
   történik, nem alapérték-billentéssel ([L534](../LESSONS.md#l534)).

3. **A capture-képernyők tiszta prezentációs jellege szerződés.** A
   függőségeket a route-építő kompozíció adja; a widgetekben `ref.watch`/
   `ref.read` nem jelenhet meg. Ezt forrás-szintű cella méri, nem szemrevétel.

4. **A „korábbi elemzés megnyitása" a route saját szerződését elégíti ki.** A
   kompozíció betölti a dokumentumot (`analysisRepositoryProvider.getById`, a
   `library_item_detail_screen.dart:176` mért mintája), és `AnalysisDocument`-et
   ad át. A route `extra`-szerződését (ADR 0241 §1) NEM lazítjuk, és a
   repository-olvasást NEM tesszük a képernyőbe (3. pont). Betöltési hibánál a
   meglévő fail-closed út marad — új felhasználói üzenet új l10n-kulcsot
   kívánna, ami a kör `allowed_paths`-án kívül esik.

5. **A legacy `AnalyzeScreen` bájtra érintetlen.** A V2 párhuzamos ág; a legacy
   út a ma működő felvevő.

## Következmények

- A bekötés visszabontása vagy kapun kívülre csúszása mostantól piros cellát ad;
  a kör falszifikációs próbája (a route feltétel nélküli bekötése) ezt méri is.
- A „korábbi elemzés megnyitása" a boldog ágon valóban a timeline-t nyitja meg.
- **Tudatosan nyitva marad:** a kezdőlap „legutóbbi elemzések" listája a
  betöltési HIBÁT ma üres listaként mutatja (`recent.value ?? []` →
  „még nincs elemzésed"). Ez hazug UI; az őszinte hibaállapot új l10n-kulcsot
  kíván, ezért külön kör tárgya. A hiány a kör záró jelentésébe és a
  `HANDOFF.md` §6-ba kerül — nem feledés, hanem H3-elkerülés
  (ADR 0087 §2: a lista tágítása nem az orchestrátor hatásköre).

## A visszavonás feltétele

Ha egy későbbi rollout-döntés az `audioAnalysisV2Enabled`-et bekapcsolja, a 4.
pont fail-closed ága felhasználói üzenetet kap (l10n-kulccsal), és a 2. pont
mérési módja (override) változatlanul marad. A 3. pont visszavonása csak a
capture-képernyők widget-tesztjeinek (7+16+23 cella) együttes átírásával
lehetséges — az a saját körében, ADR-rel indokolva.
