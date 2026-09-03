# E15-R10 — kör-review (Claude / Opus 5 orchestrátor)

- **Kör:** `E15-R10` — Audio Analysis és Analyze képernyők migrálása a design-rendszerre
- **Branch:** `sonnet-impl/e15-r10-analysis-migration`
- **Review-zott commit:** `8b5dcb6b` (alap: `f51c45dd`)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`), 1 alap menet
- **Brief:** `docs/rounds/e15-r10-analysis-migration.md` (a `§0.0.A` pre-flight revízióval)
- **Reviewer-eszközök:** izolált `/tmp` klón + eldobható próbatesztek a legacy
  referenciával szemben, `flutter-reviewer` és `flutter-devil-advocate`
  (a brief `risk = "high"` miatt KÖTELEZŐ)

## 1. menet — verdikt: **CHANGES REQUESTED**

### Gépi mércék (mind lefutott)

| Mérce | Eredmény |
|---|---|
| `tools/round-gate.sh` (15 teszt-útvonal), izolált klón `8b5dcb6b`-n | **20/20 ZÖLD** (format, analyze, 15 teszt, architecture, secrets, l10n) |
| `tools/scope-audit.py --base f51c45dd` | **OK** — 22 változott útvonal, mind az `allowed_paths`-on |
| Router CI (`33727860195`, head `8b5dcb6b`) | **success** |
| Full Gate (`33727881706`, head `8b5dcb6b`) | folyamatban a review írásakor |
| Munkafa tisztaság | tiszta (`git status --short` üres) |

**A zöld kapu NEM bizonyíték** — az alábbi leletek mindegyike a zöld gate ALATT
él, és eldobható próbateszttel, a kör ELŐTTI revízióval összemérve mértem ki.

---

## BLOCKER

### B1 — A nem-újrapróbálható hibák MINDEN akciógombot elveszítenek a feldolgozás-képernyőn

`lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart:107`
(`_FailureBody`, def. `:357-372`)

Az `AnalysisError` / `AnalysisInputError` ág a migráció után **egyetlen
akciógombot sem** rajzol azokra a hibákra, amelyeket a controller ténylegesen
kibocsát — az újraindítás-affordancia némán eltűnt.

**Mérve** (eldobható próba, ugyanaz a harness, két revízión):

- `8b5dcb6b`: `AnalysisProcessingScreen(state: AnalysisError(runId: 'run-1',
  failure: UnknownFailure()), onRestart: () {})` → `PROBE buttons found: 0`;
  `find.byKey(Key('analysis-processing-restart'))` → **nulla widget**.
  `AnalysisInputError(ValidationFailure(...))` → `PROBE input-error buttons: 0`.
- `f51c45dd` (csak ez a fájl visszaállítva): `PROBE buttons found: 1`, a restart
  kulcs megtalálva → **PASS**.

**Okláncolat:** `UnknownFailure`/`ValidationFailure` → `retryable = false`
(`lib/core/foundation/app_failure.dart:207`, `:238`) →
`failure_presentation.dart:126-131` `contactSupport` akciót ad →
`ss_failure_state.dart:59-67` a gombot kihagyja, mert a `_FailureBody` csak
`onRetry`-t ad át. A controller három valós úton `AnalysisError(failure:
UnknownFailure())`-t bocsát ki (`analysis_controller.dart:140`, `:148`, `:155`).

**Miért nem fogta meg a kapu:** a kör SAJÁT új cellája
(`test/features/analyze/processing_progress_test.dart:213`) `AudioFailure()`-t
választ — az EGYETLEN újrapróbálható típust —, tehát a gate a defekt FÖLÖTT
zöld. Ez a §5.1 sértése, és a §10 nem dokumentálja.

**Javítás:** a `contactSupport`/nem-újrapróbálható ág is kapjon valódi kiutat
(az `SsFailureState` megfelelő callbackje, vagy a restart-akció megtartása), és
a cella-hármas mérje MINDKÉT osztályt (`retryable = true` ÉS `false`).

---

## MAJOR

### M1 — A migrált home-képernyő a kör SAJÁT A3-küszöbén némán csonkolja a felhasználói tartalmat

`lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart:112`, `:137`

**Mérve** (próba 412×915, `textScaler 2.0`, `RenderParagraph.didExceedMaxLines`
minden `Text`-en):

- `8b5dcb6b` `en`: `[Record a performance, Capture guitar audio from the
  microphone and analyze it on this device., C · G · Am · F practice run]`;
  `hu`: 4 csonkolt, köztük `Meglévő felvétel elemzése, legfeljebb 64 MB.` és a
  legutóbbi elemzés CÍME (valódi felhasználói tartalom).
- `f51c45dd` (csak ez a fájl visszaállítva): `[]` / `[]` — a kör ELŐTT teljesen
  tördelt.

**Ok:** az `SsContentCard` `maxLines: 2` (cím) / `4` (üzenet) +
`TextOverflow.ellipsis` (`ss_content_card.dart:115-118`, `:137-139`). Az
ellipszis **elnyeli** a túlcsordulás-kivételt, ezért a kör hozzáadott A3-cellája
(`expect(tester.takeException(), isNull)`) ezt SZERKEZETILEG nem láthatja.

Ez az [L559](../LESSONS.md#l559) minta-szintű osztálya: a `takeException`-alapú
A3-mérce vak az ellipszisre. A javítás mércéje `didExceedMaxLines`-alapú cella
legyen, ne csak `takeException`.

### M2 — Három képernyő-specifikus lokalizált hibaüzenet néma összeolvadása

`analysis_processing_screen.dart:102-111`, `analysis_recording_screen.dart:452-470`

**Mérve** (`grep -rn` a `lib/**/*.dart`-on): `analysisProcessingErrorTitle`
(„Analysis failed" / „Az elemzés sikertelen"), `analysisRecordingErrorTitle`
(„Recording couldn't start" / „A felvétel nem indult el") és
`analysisRecordingErrorRetry` hívási helye a generált ARB/l10n fájlokon kívül
**nulla**. Az e képernyőkön ténylegesen előforduló kódokra
(`UnknownFailure`, `ValidationFailure`) a `failure_presentation.dart:75` a
`dsFailureUnknownTitle`-re esik vissza — a két ág innentől AZONOS szöveget
rajzol, csak widget-kulcsban különbözik.

A §5.1 ezt mért indoklással a §10-ben kimondva engedi csak; a §10.2 ma csak a
nyers `failure.code` cseréjét említi. Vagy őrizzük meg a képernyő-specifikus
címeket, vagy a §10 mondja ki mérve, miért nem őrizhetők meg.

### M3 — Ugyanez a defektosztály a felvétel-képernyőn

`analysis_recording_screen.dart:457-467` (`_ErrorBody`)

A `failure ?? const UnknownFailure()` (`retryable = false`) `contactSupport`-only
prezentációt ad, `onContactSupport` callback nélkül → a hiba-szakasz sem retry-t,
sem alternatív akciót nem rajzol.

**Miért MAJOR és nem BLOCKER:** ma csak a `_failure == null` védekező ágon
érhető el, mert a `mic_capture.dart` kizárólag `PermissionFailure`-t (máshova
irányítva), `CancelledFailure`-t és `AudioFailure`-t ad vissza, és ezek mind
`retryable = true` (`app_failure.dart:176`, `:227`). Élő úton mérve
(`FakeAudioCapture(failWith:)`): `retryable=true`, `actions=[retry:Try again]`,
**1 gomb** — tehát ma zöld, de egyetlen nem-újrapróbálható hiba hozzáadása némán
reprodukálja a B1-et.

### M4 — Az `AnalyzeScreen` idle üres állapota ÚJ interaktív vezérlőt kapott (kitalált akció)

`lib/features/analyze/screens/analyze_screen.dart:135-149`

A kör előtt az `EmptyState(icon, title)` **akció NÉLKÜLI** volt. A migrált
`SsEmptyState` kapott egy `actionLabel: l10n.analyzeRecord` + `onAction:
{_saved = false; controller.startRecording();}` párost — ami bájtazonos a
`:268-279` alatti, VÁLTOZATLAN `SsButton` viselkedésével.

Két szerződést sért egyszerre:

- **§0.0** — a kör MEGJELENÉS, nem viselkedés: új interaktív vezérlő nem
  vezethető be;
- **§0.0.A/R12** — „a komponens NEM kényszeríthető ki hamis akcióval". Az akció
  kizárólag az `SsEmptyState` `required actionLabel` kényszerét elégíti ki.

A §10.2 a *micDenied* akciót valósként dokumentálja (helyesen), az idle-ről
hallgat. Feloldás: vagy a `§0.0.A/R12` kivétel-osztálya (token-stílusú
képernyő-lokális üres állapot, akció nélkül, §10-indoklással), vagy az alsó
duplikált `SsButton` megszüntetése — de nem a kettő egymás mellett.

---

## MINOR

- **m1** — `lib/features/analyze/screens/analyze_screen.dart:138` (idle) és
  `:155` (micDenied): két AZONOS elsődleges CTA egymás fölött — az
  `SsEmptyState` saját `FilledButton`-ja (`ss_empty_state.dart:53`,
  `analyzeRecord` felirat) közvetlenül a változatlan, teljes szélességű
  `SsButton` fölött (`:270-278`, ugyanaz a felirat). Az `SsButton` saját
  doc-ja: „One screen shows one primary CTA (§5.6)". Ugyanitt a
  `title: l10n.navAnalyze` megismétli a képernyő-fejlécet (`:99`) — az
  „Analyze"/„Elemzés" kétszer jelenik meg.
- **m2** — `analysis_metric_detail_screen.dart:42-48`: az új üres állapot az
  `analysisOverviewNoDocument` kulcsot („No analysis document is available
  yet.") használja egy olyan állapotra, amit LÉTEZŐ dokumentum mellett, üres
  metrika/insight listánál ér el (`app_router.dart:650-658`), a `title`-je pedig
  szó szerint megismétli az AppBar címét. Kulcs-jelentés sodródás, amit a §3
  tilt.
- **m3** — `analyze_screen.dart:222` (`AnalyzeSkeleton`) és `:227-234`
  (`analyzeNoChords` nyers `Text`): a `§0.0.A/R12` kivétel-osztálya
  token-stílust ÉS képernyőnkénti §10-indoklást ír elő; a token-stílus megvan
  (illetve scope-on kívüli fájl), de a §10.2 kivétel-listája csak a
  `_PermissionDeniedBody`-t, az `AnalysisPermissionDenied`-et és a `micError`-t
  nevezi meg.
- **m4** — `analysis_recording_screen.dart:452-470`: az
  `analysis-recording-error-retry` kulcs a régi `FilledButton`-nal együtt
  törlődött (teszt nem hivatkozott rá, `grep` a `test/`-en → 0 találat), tehát
  nem tört el semmi, de a §10 nem említi az eltávolítást. Ugyanez a
  `Key('analysis-processing-restart')`-ra: a két hiba-ágról eltűnt
  (`analysis_processing_screen.dart:103`, `:108`), csak a cancelled/permission
  ágon él tovább (`:307`, `:343`) — néma teszt-felület-vesztés.
- **m5** — `docs/rounds/e15-r10-analysis-migration.md` §10: a `§0.0.A/R10` által
  ELŐÍRT A6-őszinteségi mondat **hiányzik**. Az előírás premisszája mérve igaz
  (`test/l10n/hardcoded_string_guard_test.dart:18-23` `_scopeDirs` = pontosan a
  négy `lib/core/design_system/` könyvtár). Tartalmilag az A6 áll: a 6 képernyő
  kézi átvizsgálása `(label|title|message|child: Text|actionLabel|tooltip): '…'`
  mintára `l10n.` nélkül **nulla** találatot adott — a §10-ből csak a kimondás
  hiányzik.
- **m6** — A3 **fázis**-fedés: mind a 6 képernyőnek van `en`+`hu` `textScaler
  2.0` cellája (lásd a „mérve rendben" listát), de az `AnalyzeScreen`-nek csak
  az **idle** fázisa mért, miközben a §10.5 a `SingleChildScrollView`
  túlcsordulás-javítást az idle-re ÉS a micDenied-re is alkalmazta
  (`analyze_screen.dart:135`, `:155`); a létező micDenied cella
  (`mic_error_parity_test.dart:79-98`) `1.0` skálán fut. A felvétel-képernyő
  `error`/`permissionDenied` törzsének sincs `2.0` cellája. Az
  [L559](../LESSONS.md#l559) testvér-példány szabálya pontosan erről szól.

---

## NOTE

- **N1 — a „14 golden újrafelvéve" állítás mérve.** `git diff --stat
  f51c45dd..8b5dcb6b -- test/ui/goldens/goldens/` → **6** PNG változott (mind
  `e13_r26_*`), a 8 `e13_r27_*` bájtazonos. Ez **nem** valótlan állítás: az
  `SsDarkTheme.data()` az `AppTheme.dark()` PLUSZ a kiterjesztések
  (`ss_theme_extensions.dart:86-92`), az `SsSpacing.space4 == 16`
  (`ss_spacing.dart:7`), és az `e13_r27` metric-detail fixture nem lép be az új
  üres ágba — a `docs/ui/migration-status.md` pontosan ezt rögzíti is. A §10.7
  „14/14 zöld" a CELLÁKRA vonatkozik, nem bájtokra. A `§0.0.A/R5` várakozása
  (mind a 14 PNG változik) tehát MÉRVE túl erős volt; a szerződés lényege (a
  goldenek a futásidejű témán, x86-on felvéve) teljesült.

  **Döntő mérés a merge-kapu SAJÁT architektúráján** (ADR 0426 — nem ezen az
  aarch64 boxon): `tools/golden-x86.sh check
  test/ui/goldens/e13_r26_screens_golden_test.dart
  test/ui/goldens/e13_r27_screens_golden_test.dart` → `00:59 +14: All tests
  passed!`, `EXIT=0`. A bájtazonosság oka is mérve: az
  `ss_theme_extensions.dart:84-91` `legacyThemeForBrightness` MAGÁT az
  `AppTheme.dark()`-ot adja vissza, és az `ss_dark_theme.dart:16-27` csak
  `copyWith(extensions: [...])` — az alap `ColorScheme`/`textTheme`/
  `scaffoldBackgroundColor` AZONOS, tehát csak az új kiterjesztéseket OLVASÓ
  widgetek változhatnak. Az L493 osztálya (lokálisan zöld, CI-ban piros) itt
  tehát nem áll fenn.
- **N3 — az export-képernyő az EGYETLEN a hatból, amelynek nincs új A2
  típus-állítása** (`analysis_export_screen_test.dart`). Nem BLOCKER, mert a
  képernyőnek nincs önálló üres/hiba állapota (a törzse a scope-on kívüli
  `ExportPreview`), de a javító körben pótolható.
- **N2 — teszt-oldali barrel-stílus.** `analysis_export_screen_test.dart:10` és
  mindkét golden-teszt közvetlenül a `themes/ss_light_theme.dart` /
  `ss_dark_theme.dart` fájlt importálja a `public.dart` helyett. A
  `test/core/architecture_dependency_test.dart` csak a `lib/`-et pásztázza,
  tehát ez **nem** ADR 0273-sértés — csak eltér a másik öt harness stílusától.

---

## Mérve rendben (a próbákat kiállta)

- **§0.0 / A4 — egyetlen kipinnelt cella sem gyengült.** A `test/` alatti diff
  minden törölt sora vagy `const MaterialApp` → `MaterialApp` átalakítás, vagy a
  golden téma-csere; nincs törölt cella, nincs `skip:`, nincs lazított matcher.
- **§0.0.A/R8 — barrel-szabály.** Mind a 6 migrált `lib/` fájl a
  `core/design_system/public.dart`-ot importálja, közvetlen belső import sehol.
- **§0.0.A/R9 — a `metric_detail` scope-korlátja.** `git diff --stat …
  lib/features/audio_analysis/presentation/widgets/` ÜRES: a `MetricCard` és az
  `InsightCard` érintetlen; a §10.2 és a `migration-status.md` rögzíti a sekély
  migrációt és a follow-upot.
- **§5.3 / A6 — nincs új beégetett felhasználói szöveg**; a `lib/l10n/**` diffje
  nulla, ami egyezik a §10.4 „nincs új ARB-kulcs" állításával.
- **Viselkedés-sodródás.** A diff a `lib/`-ben KIZÁRÓLAG a 6 képernyőt érinti;
  `application/`, `domain/`, `data/`, `providers/` fájl nem változott. Az
  `AnalysisRecordingScreen` `dispose`/`_start`/`_stop`/`_cancel`/`_finish`
  metódusai bájtazonosak a `f51c45dd`-vel → **ADR 0056 (mikrofon-életciklus)
  sértetlen**.
- **Gyanús, de mérve rendben:** az `SsButton(loading: _sharing)` továbbra is
  letiltja az `onPressed`-et (`ss_button.dart:60`), tehát az export-képernyő
  dupla-megosztás elleni védelme megmaradt; a felvétel-időzítő megtartja a
  tabuláris számjegyeket (`SsTypography.metricLarge` →
  `FontFeature.tabularFigures()`, `ss_typography.dart:81`); az
  `SsCardActionRegion` egyetlen akcióval az egész kártyát `InkWell`-be csomagolja,
  tehát az `analysis-home-record` / `analysis-home-import` /
  `analysis-home-recent-*` kulcsokra menő koppintások működnek.
- **§0.0.A/R12 API-visszaélés:** kitalált (hamis) akció NINCS — a home üres
  állapota az `onStartRecording`-ot, a micDenied az `openAppSettings`-et, a
  metric-detail a `commonClose` + `maybePop`-ot használja. A kifogás a
  DUPLIKÁCIÓ (m1), nem a kitalálás.

### A két reviewer állításai, amiket MÉRVE megcáfoltam (nem lelet)

- **„86/96, 89.583%"** — függetlenül újraszámolva a `tool/ui_inventory.dart`
  SAJÁT képernyő-szabályával: HEAD `migrated=86 total=96 pct=89.583`, alap
  `f51c45dd` `migrated=80 total=96`. Mind a 6 képernyőben **nulla** maradék
  `AppColors`/`AppPalette`/`app_theme` hivatkozás → a §6.1 utolsó sora
  ténylegesen teljesül, nem csak az import.
- **A3 locale-fedés** — mind a 6 képernyőnek VAN committolt `en` ÉS `hu`
  `textScaler 2.0` cellája `expect(tester.takeException(), isNull)`-lal:
  `recording_state_test.dart:302-347` (home + recording), `processing_progress_test.dart:229-258`,
  `analysis_overview_screen_test.dart:556-608` (metric detail),
  `analysis_export_screen_test.dart:189-208` (`en`, korábbról) + `:212-233`
  (`hu`, új), `mic_error_parity_test.dart:100-125` (analyze). Egyetlen képernyő
  és egyetlen locale sem hiányzik — a fenntartás a FÁZIS-fedés (m6), nem a
  locale.
- **§6.1 valódi-sértés próba** — a §10.6 dokumentálja, és a leírt kimenet a
  repóval EGYBEVÁG: a megnevezett cella
  (`AnalysisRecordingScreen — A5 no orphan microphone …`) szó szerint létezik
  (`test/features/analyze/analyze_cleanup_test.dart:29`), és a leírt bukási mód
  is illeszkedik a kódra. A próba bizonyított, nem csak állított.
- **Az export-képernyő `SsButton(loading:)` cseréje** — MINDKÉT reviewer
  megpróbálta megtörni; tartja: `ss_button.dart:58-60`
  `effectiveOnPressed = loading ? null : onPressed`, tehát a dupla-megosztás
  elleni védelem megmaradt.

## Nyitott mérési hézag (a javító körnek is szól)

- Az `AnalyzeScreen` `done` fázisa `textScaler 2.0`-n (a Save / New-recording
  gombsor, `analyze_screen.dart:344-370`) nem volt renderelhető a próbában
  (`ProviderException`, a körtől független). Az M1 ugyanezt a
  `Flexible`+ellipszis mintát mérte ki némán csonkolónak máshol.
- Nem mértem: a szemantika-fa diffje (az `SsFailureState` `ListTile`/`Semantics`
  cseréje a home-képernyőn), és a teljes CI-suite / property gate.

## Javító kör — kötelező leletlista

1. **B1** (BLOCKER) — nem-újrapróbálható hiba akciógombja a feldolgozás-képernyőn.
2. **M1** (MAJOR) — `SsContentCard` ellipszis-csonkolás `textScaler 2.0`-n;
   a mérce `didExceedMaxLines`-alapú legyen.
3. **M2** (MAJOR) — a három elveszett lokalizált hibaszöveg: megőrzés VAGY mért
   §10-indoklás.
4. **M3** (MAJOR) — ugyanez a hiba-affordancia a felvétel-képernyőn.
5. **M4** (MAJOR) — az `AnalyzeScreen` idle üres állapotának ÚJ, kitalált akciója.
6. **m1–m6** (MINOR) — dupla CTA / duplikált cím, `analysisOverviewNoDocument`
   kulcs-jelentés sodródás, a §10 kivétel-listájának kiegészítése, a törölt
   retry-/restart-kulcsok rögzítése, a hiányzó A6-őszinteségi mondat, az A3
   fázis-fedés.

---

# 2. menet — a javító kör ellenőrzése

- **Review-zott commit:** `bdaf0490` (javító kör), majd az upstream-szinkron
  utáni **merge SHA `1c561597`** (`Merge origin/main`, ADR 0086 §2 / §0.3)
- **Javító commitok:** `70f60c9e` (B1+M3), `bda784cc` (M1), `34d5c0cf` (M4+m1+m2),
  `bdaf0490` (§10.8/§10.9 dokumentálás)

## Leletenkénti zárás

| Lelet | Állapot | A zárás MÉRT bizonyítéka |
|---|---|---|
| **B1** (BLOCKER) | **ZÁRVA** | `analysis_processing_screen.dart:385-387`: `onRetry: presentation.retryable ? onRestart : null`, ÉS `if (!presentation.retryable && onRestart != null)` ág explicit újraindítás-gombbal — a nem-újrapróbálható hiba többé nem zsákutca. A `Key('analysis-processing-restart')` mindhárom ágon elérhető (m4). |
| **M1** (MAJOR) | **ZÁRVA** | `SsContentCard` → `_UntruncatedContentCard` az `analysis_home_screen.dart`-ban; a változás VIZUÁLIS, ezért a két `home_compact*` golden újra lett véve az x86 merge-kapun (`golden-x86.sh record`, majd FÜGGETLEN `check` → `+14: All tests passed!`). |
| **M2** (MAJOR) | **ZÁRVA — mért indoklással, nem visszaállítással** | A §10.8 kimondja: az `SsFailurePresentation.from()` `factory`, a `title`/`message` a `failure.code`-ból jön (`failure_presentation.dart:59-96`), és hívói oldalról nem írható felül a `lib/core/design_system/**` módosítása nélkül — ami a kör `allowed_paths`-án KÍVÜL van. A §10 önmagát is helyesbíti: a §10.2 eredeti indoklása a FELVÉTEL-képernyőre mérve pontatlan volt. Ez pontosan a §5.1 által megkövetelt „mondd ki mérve" út. |
| **M3** (MAJOR) | **ZÁRVA** | `analysis_recording_screen.dart:474-477` — a B1-gyel szimmetrikus javítás; az `analysisRecordingErrorRetry` kulcs visszakötve. |
| **M4** (MAJOR) | **ZÁRVA — és ez volt a CI PIROS gyökéroka** | Az idle `SsEmptyState` kitalált akciója eltávolítva; az `analyze_screen.dart:135-136` doc-commentje kimondja, miért. **Független bizonyíték:** a `test/features/analyze/analyze_screen_test.dart:38` cella (ami a kör célzott kapuján KÍVÜL van) az alap menetben PIROS volt — `Found 2 widgets with text "Record"` —, a javítás után a saját izolált klónomban **ZÖLD**. |
| **m1, m2, m3, m4, m5, m6, N3** | **ZÁRVA** | m2: a kulcs-sodródás feloldva meglévő kulcsokkal (`analysisOverviewUnavailable`, `analysisOverviewNotApplicable`) — új ARB-kulcs nem kellett. m5: az A6-őszinteségi mondat bekerült. m6: az `AnalyzeScreen` micDenied és a felvétel-képernyő hiba-ágai megkapták a `2.0` cellát. |

## Az orchestrátor SAJÁT mérése a merge SHA-n (`1c561597`)

A célzott gate-et a `test/features/analyze/analyze_screen_test.dart` cellával
**KIBŐVÍTVE** futtattam (ez fogta meg az M4-et a teljes CI-ban):

```
[1] format … ZÖLD          [11] analyze_screen_test.dart … ZÖLD  ← a CI-piros cella
[2] analyze … ZÖLD         [12]–[18] a többi teszt … ZÖLD
[3]–[10] tesztek … ZÖLD    [19] architecture … ZÖLD
[20] secrets … PIROS
```

**19/20 zöld.** Az EGYETLEN piros lépés a `secrets`, és a találata **nem ennek a
körnek a munkája**.

## A kör munkáján KÍVÜLI blokkoló (halt-ok)

```
Secret scan failed (4236 file(s) scanned, 1 finding(s)).
- tools/tests/test_authenticated_git_fetch.py:34: provider token literal
```

Mérve, három egymástól független futáson:

1. a merge SHA (`1c561597`) teljes CI-ja — `full-gate` `33733304877`
   **failure**, és a secret-lépés után MINDEN további lépés (l10n, asset, test,
   property, coverage) `skipped`, tehát a kör saját munkája meg sem lett mérve;
2. a saját izolált klónom gate-je ugyanezen a SHA-n → `secrets` PIROS;
3. **a TISZTA `origin/main` (`45d20193`) ugyanígy PIROS** — a klónt a
   kör-ághoz nem is érintve, önmagában.

A hibás sor `TOKEN = "github_pat_FIXTURE_ONLY_not_a_real_secret"` — nyilvánvaló
teszt-fixture, amiről hiányzik a scanner saját, dokumentált mentesítő markere.
A sort a **`61cd9e3e` (PR #544, „a `git fetch` HITELESÍTVE megy", ADR 0495 D5)**
hozta be a `main`-re; `git log -S'github_pat_FIXTURE_ONLY'` ezt az egy commitot
adja. Az E15-R10 csak annyit tett, hogy az ADR 0086 §2 által ELŐÍRT
upstream-szinkronnal beemelte a `main`-t.

**Miért nem javíthatja ez a kör:** a `tools/tests/test_authenticated_git_fetch.py`
az `allowed_paths`-on KÍVÜL van, és a `tools/**` a brief §4 tilos zónája; az
ADR 0087 §4 szerint a mércét nem módosíthatja az, akit mér. Ez **H3**.

## VÉGSŐ DÖNTÉS — a kör saját munkájára: **APPROVED**

0 nyitott BLOCKER, 0 nyitott MAJOR, 0 nyitott MINOR. A kör tartalmilag KÉSZ és
merge-re kész; a merge-et kizárólag a `main`-ről örökölt, körön kívüli
secret-gate defekt tartja vissza. A feloldás után a folytatás a **merge-lépésnél**
kezdődik (§0.2 `REVIEW-APPROVED`): upstream-szinkron → PR → a teljes CI-kapu ÚJRA
a friss merge SHA-n → zöld kapus squash-merge. A zöld kapu NEM lazul.
