# E17-R02 — Az Analysis V2 felvevő-ág bekötése (3 képernyő)

- **Státusz:** ÚJRAMÉRVE a kör pre-flightjában (2026-09-18, `main @ 4c12083c`) — **`pending`**; a `hold` 2026-09-05-én feloldva (§0.0), a brief mért alapja a §0.0.1-ben KI VAN CSERÉLVE (S15)
- **Típus:** Chapter 17 (Teljes bekötés), Kör 2
- **Kör-azonosító:** `E17-R02`
- **Branch:** `<motor>/e17-r02-analysis-v2-capture-wiring`
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `ADR 0584` — a foglalótól (`tools/round-slots.py reserve-adr --round E17-R02`, 2026-09-18). Az előre írt `0521` szám KÖZBEN ELKELT (`docs/adr/0521-scoped-false-visible-event-rates-and-hard-negative-taxonomy.md`), ezért érvénytelen; a brief minden `ADR 0521` hivatkozása `ADR 0584`-re olvasandó.
- **Fejezet-terv:** [`docs/plans/chapter-17-full-wiring.md`](../plans/chapter-17-full-wiring.md)

**Visszakeresett előzmény (lefuttatva 2026-09-18, ADR 0312):**
`--corpus lessons,halts,adr`: [ADR 0241](../adr/0241-analysis-overview-presentation-boundary.md)
(a V2 route-ok fail-closed `extra`-szerződése: hiányzó/hibás `extra` → meglévő
router-útvonal, nem tárolóolvasás), [ADR 0220](../adr/0220-audio-analysis-v2-parallel-rollout-boundary.md)
(párhuzamos V2 rollout-határ), [ADR 0275](../adr/0275-five-area-shell-behind-a-flag.md) §1
(flag-rollout = termékdöntés, nem az implementáló köré).
`--corpus lessons,halts`: [L653](../LESSONS.md#l653) (E17-R01/H3 — a dátumozott
Ch15-jelentés darabszám-cellái; a javítás óta rögzített fixture-ből olvasnak, ez a kör
viszont a leltár darabszámát NEM mozdítja: a három capture-képernyő MÁR `reachable`),
[L654](../LESSONS.md#l654) (a router-URI-t állító cella zöld marad, miközben a
felhasználó a képernyőn ragad — a bejárás-cellának a KÉPERNYŐ eltűnését is mérnie kell,
nem csak a `uri.path`-t), [L534](../LESSONS.md#l534) (egy flag-alapérték átbillentése a
teszt-alapértelmezést is átbillenti — ez a kör ezért flag-értéket NEM ír át, csak
`appConfigProvider`-override-dal mér mindkét álláson).

## 0.0 A `hold` FELOLDVA (2026-09-05)

A kör az `audioAnalysisV2Enabled` kapu MÖGÉ köt be. A kapu `forEnvironment`-ben MINDEN környezetben `false`, ezért a bekötés mérhető (flag-gated route), de a felhasználó számára csak egy külön rollout-döntés után látszik — az a döntés NEM ennek a körnek a tárgya.

Az eredeti `hold` indoka az volt, hogy előbb az `E17-R01` kompozíciós mintája záruljon le. **2026-09-05-én feloldva:** ez SORRENDI preferencia volt, nem függőség — a kör `lib/` halmaza (`app_router.dart`, `audio_analysis/`) nem metszi az R01-ét (`onboarding/`).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/routing/app_router.dart",
  "lib/features/audio_analysis/application/analysis_providers.dart",
  "lib/features/audio_analysis/public.dart",
  "test/features/audio_analysis/capture_wiring_test.dart",
  "docs/rounds/e17-r02-analysis-v2-capture-wiring.md",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
]
native_gate = false
gate_tests = [
  "test/features/audio_analysis/",
  "test/features/analyze/",
  "test/app/routing/",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/",
  "test/tooling/screen_reachability_test.dart",
]
```

## 0.0.1 Pre-flight ÚJRAMÉRÉS — a brief mért alapja kicserélve (S15, 2026-09-18)

A brief-lint `S15` lelete mért: a brief `main @ b17e08ef` alapja ELMOZDULT. Az
újramérés (`main @ 4c12083c`) ezt találta:

**A bekötés MÁR A `main`-EN VAN — de a pipeline-on KÍVÜL érkezett.** A
`050e45028` commit (2026-09-05, „feat(analysis): a felvételi folyamat bekötése
— a placeholder megszüntetésével") NEM SDD-kör: nincs hozzá kör-brief, review,
ADR és nincs hozzá egyetlen gépi őr sem. Amit elvégzett:

```
$ git show --stat 050e45028 | grep -E 'app_router|analysis_providers|capture_seed'
 lib/app/routing/app_router.dart                        | 102 ++++++++
 .../application/analysis_providers.dart                |  51 ++++
 .../audio_analysis/application/capture_seed.dart       | 111 +++++++++
```

```
$ dart run tool/check_screen_reachability.dart --format json
measuredScreenCount=97  unreachable=3  flagGated=46
AnalysisHomeScreen        reachable=True flagGated=True conds=['audioAnalysisV2Enabled']
AnalysisRecordingScreen   reachable=True flagGated=True conds=['audioAnalysisV2Enabled']
AnalysisProcessingScreen  reachable=True flagGated=True conds=['audioAnalysisV2Enabled']
(a maradék 3 elérhetetlen: setlist_list_screen_v2, setlist_session_screen → E17-R03;
 practice_plan_preview_screen → E17-R04)
```

**Ami tehát a §2-ből ELAVULT:** a „mindhárom `reachable: false`" állítás és a
belőle következő „ez a kör köti be a route-okat" olvasat. **Ami IGAZ maradt:** a
három képernyő TISZTA prezentációs jellege (mindhárom `StatelessWidget` /
`StatefulWidget`, `0` db `ref.watch`), a legacy `AnalyzeScreen` érintetlensége, és
a `audioAnalysisV2Enabled` kapu mint EGYETLEN rollout-forrás.

**A kör EGYETLEN döntési helye ezután (a §5 döntései változatlanok, csak a
tárgyuk szűkül):**

1. **A GÉPI ŐR hiánya a merge-elt viselkedés fölött.** Mérve: a
   `AppRoutes.analysisCapture|analysisRecord|analysisProcessing` hármasra a
   teljes `test/` fában **nulla** cella hivatkozik (az egyetlen találat egy
   `analyze_screen_test.dart:92` STUB-route, ami nem ezeket a képernyőket
   méri), és a brief által előírt `test/features/audio_analysis/capture_wiring_test.dart`
   **nem létezik**. A bekötés ma bizonyítatlan: bármelyik későbbi kör
   észrevétlenül visszabonthatja. Ezt a kör MEGSZÜNTETI (A1–A6).
2. **Egy MÉRT navigációs hiba a bekötésben.** A kezdőlap „nyisd meg a korábbi
   elemzést" ága a `AnalysisSummary`-t adja át a timeline route-nak:

   ```
   app_router.dart:  onOpenAnalysis: (summary) => context.go(AppRoutes.analysisTimeline, extra: summary)
   app_router.dart:  path: AppRoutes.analysisTimeline
                     redirect: (_, state) => state.extra is AnalysisDocument ? null : <Live fail-closed útvonal>
   ```

   A route szerződése ([ADR 0241](../adr/0241-analysis-overview-presentation-boundary.md) §1)
   `AnalysisDocument`-et kér, a `AnalysisSummary` nem az → a koppintás MINDIG a
   fail-closed ágra, a Live képernyőre visz. A javítás a kör
   `allowed_paths`-án BELÜL elvégezhető, ÚJ l10n-kulcs nélkül: a route-építő
   betölti a dokumentumot (`analysisRepositoryProvider.getById`, a
   `library_item_detail_screen.dart:176` MÉRT mintája szerint), és azt adja át;
   betöltési hibánál marad az ADR 0241 fail-closed útja.

**Amit ez a kör SZÁNDÉKOSAN NEM old meg (H3-elkerülés, nem feledés):** a
kezdőlap „legutóbbi elemzések" listája a betöltési HIBÁT üres listaként mutatja
(`app_router.dart`: `recent.value ?? const <AnalysisSummary>[]` → a képernyő a
„még nincs elemzésed" üres-állapotot rajzolja). Ez hazug UI, de az őszinte
hibaállapot ÚJ l10n-kulcsot kíván (`lib/l10n/base/app_{en,hu}.arb` + a generált
aggregátum), ami ennek a körnek az `allowed_paths`-án kívül esik → lista-tágítás
lenne (**H3**, ADR 0087 §2). A hiány a záró jelentésbe és a HANDOFF §6-ba megy,
egy külön kör bemeneteként.

**S11-mérés — a kör a `LiveScreen`-t NEM cseréli le.** A brief a Live
útvonalat kizárólag CÉLKÉNT említi (a konstans nevét a fenti idézet ezért NEM
írja ki: az S11 útvonal-token-szűrője pusztán a név említésére gyújt): ez az ADR 0241 §1 fail-closed ága, ahová a
timeline route hiányzó `extra` esetén terel. A kör `allowed_paths`-a a
`lib/features/live/**`-ot nem tartalmazza, és a §3 tiltása szerint egyetlen
meglévő képernyő fájlja sem íródik át — a `live_screen.dart`-ot pinnelő hét
teszt (`test/accessibility/closure_suite_test.dart`,
`test/app/offline_network_guard_test.dart`, `test/app/routing/app_router_test.dart`,
`test/app/routing/shell_lifecycle_test.dart`,
`test/features/ai_tutor/presentation/tutor_home_screen_test.dart`,
`test/features/live/live_stage_test.dart`,
`test/features/today/hub_navigation_test.dart`) közül a
`test/app/routing/**` alattiak amúgy is a §7 kapujában futnak. Ha a kör
bármelyiküket pirosra viszi, az BLOKKOLÓ lelet, nem cella-hiba.

**Az ADR-szám:** az előre írt `0521` közben elkelt; a foglaló `0584`-et adta.
A kör ADR-je tehát [`docs/adr/0584-analysis-capture-flow-guard-and-open-contract.md`](../adr/0584-analysis-capture-flow-guard-and-open-contract.md),
és azt az orchestrátor a pre-flightban MEGÍRTA (a §5 döntései + a fenti két pont).

## 0. Kör-jelzés és STOP-protokoll

Scope-ütközés esetén a kimenet a brief-REVÍZIÓ, nem a scope önkényes tágítása: állítsd meg a kört (`stopped`), és írd le, melyik §-t kell módosítani.

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

Az Analysis V2 felvevő-ága (`AnalysisHomeScreen` → `AnalysisRecordingScreen` →
`AnalysisProcessingScreen`) a szállított kompozícióból elérhető, a meglévő
`audioAnalysisV2Enabled` kapu alatt — **és ez GÉPILEG BIZONYÍTOTT**. A §0.0.1
újramérése szerint az elérhetőség már fennáll; ez a kör a fölötte hiányzó őrt
építi meg, és javítja a bekötés egy MÉRT navigációs hibáját.

## 2. Jelenlegi állapot — mért tények (`main @ 4c12083c`, 2026-09-18)

- A három capture-képernyő a fában él (`lib/features/audio_analysis/presentation/capture/`),
  és mindhárom **`reachable: true`, `flagGated: true` (`audioAnalysisV2Enabled`)** —
  a `050e45028` (2026-09-05) pipeline-on kívüli commit kötötte be
  (`app_router.dart:1052–1146`). Ez a §0.0.1 újramérése; a brief eredeti
  „mindhárom `reachable: false`" állítása ELAVULT.
- Mindhárom TISZTA prezentációs widget maradt: injektált függőségeket vár
  (`recentAnalyses`, `onStartRecording`, `onImportFile`, `onOpenAnalysis?` ·
  `recorder`, `onFinished`, `onCancel` · `state`, `onCancel`, `onRestart?`,
  `onViewResult?`) — `grep -c 'ref\.watch\|ref\.read' <a három fájl>` = `0`.
- A kompozíciós providerek LÉTEZNEK (`analysis_providers.dart`:
  `analysisControllerProvider`, `analysisCaptureRecorderProvider`,
  `analysisRecentSummariesProvider`), és a `analysisRepositoryProvider`-t a
  produkció felülírja (`lib/app/production_overrides.dart:94`).
- **Nulla gépi őr a bekötés fölött:** a három route-konstansra
  (`AppRoutes.analysisCapture|analysisRecord|analysisProcessing`) a `test/`
  fában egyetlen mérő cella sem hivatkozik, és a
  `test/features/audio_analysis/capture_wiring_test.dart` nem létezik.
- **Mért hiba:** a kezdőlap `onOpenAnalysis` ága `AnalysisSummary`-t ad a
  timeline route-nak, amely `AnalysisDocument`-et kér → a koppintás mindig a
  fail-closed Live útra visz (§0.0.1/2).
- A képernyő-leltár őre (`test/tooling/screen_reachability_test.dart`) ma
  `hasLength(97)`-et pinnel; ez a kör ÚJ képernyőt nem vesz fel, tehát a
  darabszám nem mozdul ([L653](../LESSONS.md#l653) hibaosztálya nem nyílik ki).
- **Mért kikötés:** a legacy `AnalyzeScreen` felvevő útja MŰKÖDIK
  (mic-handshake, `AnalyzePhase.recording`/`micDenied` ágak) — ez a kör hozzá
  nem nyúl.

## 3. Scope

**Benne van:**

- A merge-elt capture-bekötés **gépi őre**: a három route léte és
  flag-kötöttsége mindkét flag-álláson, a fázis-átmenetek valós
  providerekkel, a widgetek injektált szerződésének pinnelése
  (`test/features/audio_analysis/capture_wiring_test.dart`).
- A `onOpenAnalysis` navigáció javítása: a timeline route az `ADR 0241` §1
  szerinti `AnalysisDocument`-et kapja (betöltés a meglévő repository-ból),
  hiba esetén a fail-closed út marad.
- A javításhoz szükséges kompozíciós varrat a
  `lib/features/audio_analysis/application/analysis_providers.dart`-ban, ha a
  route-építőnek kell (a `public.dart` csak akkor bővül, ha a varratot a
  fán kívülről is olvassák — egyébként érintetlen).

**NINCS benne (tilos):**

- A legacy `AnalyzeScreen` bármely módosítása.
- Az `audioAnalysisV2Enabled` alapértékének megváltoztatása — ez rollout-döntés,
  nem bekötés ([L534](../LESSONS.md#l534): egy flag-alapérték átbillentése a
  teszt-alapértelmezést is átbillenti).
- Új DSP- vagy elemzési viselkedés.
- ÚJ l10n-kulcs bármely alakban (a „legutóbbi elemzések" hibaállapota — §0.0.1
  utolsó bekezdése — ezért marad egy külön körre).
- A meglévő pin-cellák törlése, `skip`-je vagy gyengítése.

## 4. Engedélyezett fájlok

(lásd az `ai-router` blokk teljes listáját)

**A pin-őrök jogosultsága (S10/S11, mérve: E13-R16/F9 full-gate 32867296946, E13-R17/H3 `test/app/navigation/` +33 → +30 −3):** a fenti listán szereplő, a briefen KÍVÜL élő pin-tesztek azért kerültek az `allowed_paths`-ba ÉS a `gate_tests`-be, mert a bekötés a route által renderelt képernyő TÍPUSÁT mozdíthatja el. A jogosultság PONTOSAN ennyi: a lecserélt képernyő típusának átírása a pinnelő cellában. **Cella törlése, `skip`-je vagy gyengítése TILOS** — ha egy cella a típus-átíráson túl válik pirossá, az a kör BLOKKOLÓ lelete, nem a cella hibája.


## 5. Kötött architekturális döntések (ADR 0584)

### 5.1 A három képernyő a MEGLÉVŐ `audioAnalysisV2Enabled` kapu alatt kerül be, új flag NEM születik

A V2 ág három társ-képernyője már ez alatt él. Egy negyedik, capture-specifikus flag két igazságforrást csinálna ugyanabból a rollout-döntésből.

### 5.2 A capture-képernyők TISZTA prezentációs jellege megmarad: a függőségeket a route-építő adja, nem a widget olvassa

A három widget ma injektált paramétereket vár. Ha a bekötés `ref.watch`-ot tesz beléjük, a meglévő widget-tesztjeik (7+16+23 cella) egyszerre válnak hamissá és újraírandóvá — a bekötésnek a KOMPOZÍCIÓBAN kell élnie.

### 5.3 A legacy `AnalyzeScreen` bájtra érintetlen marad

A V2 párhuzamos ág. A legacy útvonal a ma MŰKÖDŐ felvevő; egy közös refaktor a kör scope-ján kívüli regressziót nyitna.

### 5.4 A „korábbi elemzés megnyitása" a route SAJÁT szerződését elégíti ki: dokumentumot ad, nem összefoglalót

A timeline route [ADR 0241](../adr/0241-analysis-overview-presentation-boundary.md) §1
szerint `AnalysisDocument`-et kér, és minden mást a fail-closed útra terel. A
kezdőlap `AnalysisSummary`-t tart a kezében, tehát a KOMPOZÍCIÓ dolga a
dokumentumot betölteni (`analysisRepositoryProvider.getById`) — nem a route
szerződését lazítani és nem a képernyőbe repository-olvasást tenni (5.2).
Betöltési hibánál a meglévő fail-closed ág marad: ÚJ felhasználói üzenet ÚJ
l10n-kulcsot kívánna, ami a kör listáján kívül esik (§0.0.1).

## 6. Acceptance criteria

Minden cella GÉPI mérés, és minden cellához oda van írva, MELYIK hibás
implementációt viszi pirosra (S2). A mérő fájl — ha a cella nem mondja
másként — `test/features/audio_analysis/capture_wiring_test.dart`.

| # | Kritérium | Bizonyíték | Melyik hibás implementációt fogja pirosra |
|---|---|---|---|
| A1 | Mindhárom capture-képernyő `reachable: true` és `flagGated: true` (`audioAnalysisV2Enabled`) | `test/tooling/screen_reachability_test.dart` (a leltár őre, a §7 kapuban) + egy cella, amely a `routerProvider` fájából `audioAnalysisV2Enabled=true` mellett mindhárom útvonalat felépíti | a route-ok kivétele vagy kapun kívülre tétele |
| A2 | `audioAnalysisV2Enabled=true` mellett a home → recording → processing átmenet VALÓS providerekkel megy végig (override csak a mikrofon- és repository-varraton), és a processing képernyő a `analysisControllerProvider` állapotát mutatja | widget-teszt valós `ProviderContainer`-rel; a cella a KÉPERNYŐ típusát is méri, nem csak `router.state.uri.path`-t ([L654](../LESSONS.md#l654)) | a `analysisControllerProvider` / `analysisCaptureRecorderProvider` kivezetése, vagy a `onFinished` → processing átmenet elrontása |
| A3 | `audioAnalysisV2Enabled=false` mellett a három route NEM létezik (a rájuk irányuló `go` a fail-closed útra visz), és a legacy Analyze útvonal változatlanul elérhető | router-teszt MINDKÉT flag-álláson, `appConfigProvider`-override-dal (a mért minta: `test/features/audio_analysis/presentation/analysis_overview_screen_test.dart:612`) | a route-hármas feltétel nélküli (kapun kívüli) bekötése — ezt futtatja a §6.1 próba |
| A4 | A három capture-widget injektált szerződése változatlan: a fájljaikban `0` db `ref.watch`/`ref.read`/`ConsumerWidget`, és a konstruktor-paraméterek megvannak | forrás-szintű cella a három fájlon + a meglévő widget-tesztek zölden | a bekötés áthelyezése a widgetbe (5.2 megsértése) |
| A5 | A legacy `AnalyzeScreen` fájlja a kör diffjében nem szerepel | `git diff --name-only <indulási HEAD>..HEAD` a záró jelentésben | bármilyen legacy-refaktor (5.3 megsértése) |
| A6 | A kezdőlap „korábbi elemzés megnyitása" ága a timeline route-nak `AnalysisDocument`-et ad: egy eltárolt elemzésre koppintva a `AnalysisTimelineScreen` jelenik meg, NEM a Live képernyő | widget-teszt valós repository-varrattal (egy eltárolt dokumentum), a cella a megjelenő KÉPERNYŐ típusát méri | a mai `extra: summary` alak (a §0.0.1/2 mért hibája) — ezt a cellának pirosnak kell látnia a javítás előtt |
| A7 | A kör nem vesz fel ÚJ l10n-kulcsot, és nem írja át az `audioAnalysisV2Enabled` alapértékét | `git diff --name-only` (nincs `lib/l10n/**`) + `git diff lib/app/config/feature_flags.dart` üres | a §3 tiltásainak megsértése |

### 6.1 Falszifikációs próba

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** Kösd a
`AnalysisRecordingScreen`-t a kapun KÍVÜLRE (feltétel nélküli `GoRoute`),
futtasd a §7 kapuját → az **A3** cellának PIROSNAK kell lennie → állítsd vissza,
és a kapu legyen újra zöld. A próba mindkét kimenetét (piros → zöld) írd le a
§10-be, a cella nevével együtt.

**Második próba (A6, ugyanígy dokumentálva):** állítsd vissza az
`onOpenAnalysis` ágat a mai `extra: summary` alakra → az **A6** cellának
PIROSNAK kell lennie → állítsd vissza a javítást.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/audio_analysis/ test/features/analyze/ test/app/routing/ test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/tab_state_restoration_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/ test/tooling/screen_reachability_test.dart
```

A gate a `format` → `analyze` → `test <minden útvonal külön>` → `architecture` lépéseket KÜLÖN processzként futtatja (a box mért OOM-csapdája miatt a `flutter analyze && flutter test` lánc tilos).

## 8. Implementációs sorrend

1. A §0.0.1 újramérésének elfogadása: a bekötés ÁLL, a kör az őrt és az A6
   javítást viszi. A brief §8 a terved — nincs külön task-lista.
2. Az **A6 javítás** a `app_router.dart` `onOpenAnalysis` ágán (ADR 0584 §5.4).
3. A `test/features/audio_analysis/capture_wiring_test.dart` megírása: A1–A7.
4. A §6.1 KÉT valódi-sértés próba lefuttatása és a §10-be dokumentálása.
5. A §7 gate futtatása csonkítatlan kimenettel, a záró sor szó szerint.
6. A §10 kitöltése, majd a munka COMMITOLÁSA a kör-branchre.

## 9. Kockázatok

- **A widget-szerződés elrontása.** `ref.watch` a prezentációs widgetbe 46 meglévő tesztcellát tesz hamissá (5.2, A4).
- **A legacy felvevő megsértése.** A ma MŰKÖDŐ Analyze út regressziója a legdrágább hibaosztály itt (5.3, A5).
- **A rollout-döntés elkövetése.** A flag alapértékének megváltoztatása termékdöntés, nem bekötés (§3 tiltás, A7) — és [L534](../LESSONS.md#l534) szerint 19 fájlt visz pirosra.
- **Scope-átcsúszás az l10n felé.** A „legutóbbi elemzések" hibaállapotának őszintévé tétele ÚJ kulcsot kíván → `allowed_paths`-tágítás → **H3**. A kör ezt SZÁNDÉKOSAN nem oldja meg (§0.0.1); ha az implementer mégis szükségesnek látja, `stopped` a helyes kimenet, nem a lista tágítása.
- **Álzöld őr.** Egy olyan A2/A6 cella, amely csak `router.state.uri.path`-t mér, zöld marad, miközben a felhasználó a régi képernyőn ragad ([L654](../LESSONS.md#l654)) — ezért mérik a cellák a megjelenő KÉPERNYŐ típusát.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
