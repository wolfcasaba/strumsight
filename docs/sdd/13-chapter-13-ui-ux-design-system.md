# StrumSight Software Design Document

## Chapter 13 — UI/UX Design System & Screen Specification

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész, cross-cutting UI/UX specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Elsődleges kliens:** Flutter, Android-first  
**Másodlagos célplatformok:** iOS, tablet, foldable és desktop-width Flutter layout  
**Design alap:** dark-first Material 3, Copper Stage vizuális identitás  
**Alapértelmezett nyelvek:** angol és magyar  
**Állapotkezelés:** Riverpod  
**Navigáció:** GoRouter  
**Kapcsolódó fejezetek:** Chapter 1–12; különösen Core Platform, Practice Engine, Song Trainer, AI Guitar Teacher, Computer Vision, Audio Analysis 2.0, AI Practice Generator, Gamification, Community és Offline AI  
**Végrehajtó:** Project Owner + Codex; vizuális és valós eszközös elfogadásnál manuális QA szükséges  
**Codex-fejlesztési körök száma:** 36  
**Képernyő-specifikációk száma:** 65  
**Végrehajtási alapelv:** token-first design system, adaptive layout, accessibility by default, incremental migration, evidence-driven visual acceptance

---

# 1. A fejezet célja

A Chapter 13 célja, hogy a StrumSight teljes felületét egyetlen koherens, implementálható és tesztelhető UI/UX rendszerbe rendezze. A dokumentum nem pusztán látványtervet ad. Meghatározza:

- a StrumSight vizuális identitását és design tokenjeit;
- a navigációs és információs architektúrát;
- a compact, medium és expanded layout szabályait;
- a gyakorlás közbeni **Stage Mode** viselkedését;
- a tanulási, elemzési, AI-, vision-, community- és settings felületek közös szerződéseit;
- a komponenskatalógust és annak állapotait;
- a loading, empty, offline, degraded, permission, error és blocked állapotokat;
- a nagy szöveg, képernyőolvasó, reduced motion, high contrast és színlátási eltérések támogatását;
- a képernyőnkénti célokat, adatokat, fő műveleteket, layoutot és elfogadási feltételeket;
- a golden-, widget-, navigation-, semantics- és valós eszköztesztelést;
- a meglévő UI fokozatos migrációját anélkül, hogy a működő audio-, DSP-, ML- vagy storage-funkciókat egyetlen nagy újraírással veszélyeztetnénk.

A fejezet sikerének mércéje nem az, hogy minden képernyő „szépnek” tűnik. A siker az, hogy a StrumSight:

- játék közben messziről is olvasható;
- egy kézzel, gyorsan és hibabiztosan kezelhető;
- kezdőként egyszerű, haladóként részletes;
- világosan megkülönbözteti a mért tényt, becslést és AI-javaslatot;
- hálózati vagy modellhiba esetén is használható marad;
- nem kényszeríti a felhasználót felesleges account- vagy community-lépésekre;
- minden fontos állapotot nemcsak színnel, hanem formával, ikonnal és szöveggel is közöl;
- nagy kijelzőn nem egyszerűen széthúzza a telefonos layoutot, hanem többpaneles, feladathoz illő felületet ad;
- a Codex számára kis, ellenőrizhető fejlesztési körökben implementálható.

---

# 2. Jelenlegi állapot és megtartandó alapok

A repository jelenlegi felülete már rendelkezik használható vizuális és technikai alapokkal:

- dark-first Material 3 téma;
- `AppColors`, `AppPalette` és `AppTheme` alapú theme-réteg;
- rézszínű StrumSight brand accent;
- külön confidence-színek;
- Poppins és Montserrat font assetek;
- GoRouter alapú route-rendszer;
- Riverpod provider-alapú képernyőállapotok;
- Live, Tuner, Analyze, Learn, Library, Settings és további feature képernyők;
- angol és magyar lokalizáció;
- valós idejű akkord- és strum-direction kijelzés;
- meglévő UX-polish backlog és több regressziós teszt.

A jelenlegi kanonikus színalapok:

```text
Brand copper       #D98A46
Brand secondary    #E0A44A
Brand dark         #B26A2E

Dark background    #111013
Dark surface       #191719
Dark ink           #E9E5DE
Dark muted         #948D82
Dark track         #22201F
Dark border        #2E2A28

Light background   #F3F0E9
Light surface      #FFFFFF
Light ink           #1C1A17
Light muted         #6A645B
Light track         #EDE8DF
Light border        #D8D2C6

Confidence high    #3ED598
Confidence medium  #F2B33D
Confidence low     #6E7480
Danger              #E5533C
```

Ezeket nem kell önkényesen lecserélni. A Chapter 13 feladata, hogy névvel ellátott szemantikai tokenekké, kontrasztvizsgálattal védett theme-rendszerré és újrahasznosítható komponensekké fejlessze őket.

## 2.1 Jelenlegi navigáció

A jelenlegi compact bottom navigation fő területei:

```text
Live | Analyze | Learn | Library | Settings
```

A célállapot:

```text
Today | Practice | Songs | Coach | Profile
```

A migráció fokozatos. A meglévő route-ok és deep linkek nem törölhetők azonnal. A régi route-ok átmeneti aliasokon vagy redirecteken keresztül működjenek, amíg a hozzájuk kapcsolódó új hubok el nem készülnek.

## 2.2 Megtartandó viselkedések

- A Live képernyő elhagyása felszabadítja a mikrofont.
- A Tuner és a Live nem birtokolhatja egyszerre a mikrofont.
- A confidence jelentése nem függhet kizárólag színtől.
- A hangfeldolgozás alapértelmezetten helyi.
- A logged-out app teljes core funkciója működik.
- A magyar és angol szövegek layoutja tesztelt.
- A DSP- és ML-eredmények formátuma UI-refaktor miatt nem változhat meg.

---

# 3. Hatókör

## 3.1 A fejezet része

- teljes design token rendszer;
- dark, warm-light és high-contrast témák;
- tipográfia, spacing, radius, elevation, border és motion;
- ikonográfia és gitárspecifikus szimbólumok;
- adaptive scaffold és navigáció;
- Stage Mode;
- közös input-, action-, feedback-, data- és overlay-komponensek;
- képernyőállapot-szerződés;
- 65 képernyő részletes specifikációja;
- responsive és adaptive layout;
- accessibility;
- lokalizációs és szöveghossz-szabályok;
- privacy-, cloud-, local AI- és sync-jelölések;
- grafikonok és confidence-megjelenítés;
- golden és visual regression stratégia;
- design system dokumentáció;
- legacy képernyők fokozatos migrációja.

## 3.2 Nem része

- végleges marketing weboldal;
- store screenshot kampány;
- teljes brand book nyomdai anyagokkal;
- 3D gitármodell;
- fotó- vagy videóprodukció;
- fizetési és subscription checkout flow, amíg külön monetization SDD nem készül;
- minden platform natív pixel-perfect utánzása;
- a DSP, ML, backend vagy domain logika funkcionális újraírása;
- teljes Figma projekt létrehozása ebben a dokumentumban.

## 3.3 Későbbi vagy külön validálandó scope

- smartwatch companion;
- TV/kivetítő Stage Mode;
- AR szemüveges kiterjesztés;
- desktop DAW plugin;
- teljes notation editor;
- live multiplayer jam;
- haptikus wearable integráció.

---

# 4. UX alapelvek

## 4.1 A gitáros keze foglalt

A StrumSight elsődleges használati helyzete nem a klasszikus „telefon a kézben” mobilhasználat. A telefon gyakran állványon, asztalon vagy erősítőn van. Ezért:

- a kritikus Stage Mode információ legalább karnyújtásnyi távolságból olvasható;
- a fő gombok érintési célja legalább 48×48 dp;
- a stop és pause műveletek nem bújhatnak overflow menübe;
- fontos visszajelzés hanggal vagy haptikával is támogatható;
- egy időben egyetlen elsődleges javítás jelenjen meg;
- a felhasználónak ne kelljen gyorsan mozgó apró elemeket követnie.

## 4.2 Progresszív részletezés

Minden eredmény három szinten jelenjen meg:

1. **Azonnali összefoglaló:** mit csinált jól, és mi az egyetlen következő javítás.
2. **Fő mérőszámok:** timing, chord accuracy, consistency, technique vagy más releváns dimenziók.
3. **Részletes elemzés:** timeline, heatmap, trend, confidence és eseménylista.

A kezdő nem kaphat olyan adatsűrűséget, amely elrejti a következő gyakorlati lépést.

## 4.3 Bizonyosság őszinte kommunikációja

A felület különböztesse meg:

- **mért tény:** közvetlenül és megbízhatóan érzékelt adat;
- **becslés:** algoritmikus eredmény confidence értékkel;
- **AI-javaslat:** magyarázat vagy ajánlás, amely nem diagnózis;
- **ismeretlen:** nincs elegendő jel vagy bizonyíték.

Alacsony confidence esetén a UI ne használjon kategorikus hibanyelvet.

## 4.4 Offline-first és graceful degradation

- Az offline mód nem hibaállapot.
- A cloud funkciók külön online rétegként jelennek meg.
- Local AI, cloud AI és deterministic fallback vizuálisan megkülönböztetett.
- Sync pending állapot nem blokkolja a helyi gyakorlást.
- Modell- vagy hálózati hiba esetén a felhasználó kapjon működő alternatívát.

## 4.5 Nincs dark pattern

Tilos:

- accountot kényszeríteni core funkcióhoz;
- streak elvesztésével fenyegetni;
- a „nem kérem” műveletet elrejteni;
- marketing consentet funkcionális consenttel összekötni;
- AI- vagy community-funkciót automatikusan bekapcsolni;
- véletlen törléshez homályos megfogalmazást használni.

## 4.6 Zeneileg releváns mozgás

Animáció csak akkor használható, ha:

- segíti a ritmus érzékelését;
- megerősít egy állapotváltozást;
- jelzi a navigációs hierarchiát;
- visszajelzést ad egy sikeres műveletről.

A beat animáció audio clockból származzon, ne független UI timerből.

---

# 5. Használati környezetek

| Környezet | Jellemző | UI következmény |
|---|---|---|
| Telefon kézben | rövid beállítás, böngészés | normál compact navigáció |
| Telefon állványon | játék, gyakorlás | Stage Mode, nagy elemek |
| Landscape telefon | Song Trainer, Live | széles beat- és timeline-layout |
| Tablet | lecke, elemzés, editor | list-detail és supporting pane |
| Foldable | félbehajtott állvány mód | hinge-aware pane elrendezés |
| Desktop-width | tartalomkezelés, részletes elemzés | NavigationRail + több panel |
| Gyenge fény | esti gyakorlás | Dark Studio alapértelmezés |
| Erős nappali fény | szabadtér, világos szoba | Warm Light téma |
| Képernyőolvasó | látássérült használat | teljes semantics, sorrend és címkék |
| Nagy szöveg | accessibility text scale | törésbiztos layout, nincs clipping |
| Zajos környezet | bizonytalan audio | signal-quality és degraded state |
| Offline | utazás, pince, próbahely | core működés, sync queue |

---

# 6. Vizuális identitás — Copper Stage

A StrumSight célzott hangulata:

> **Prémium digitális gitárstúdió, amely játék közben háttérbe húzódik, tanuláskor vezet, elemzéskor professzionális adatot ad, AI használatakor pedig világosan jelzi a bizonyosságot és a végrehajtható következő lépést.**

## 6.1 Négy UI-mód

### Stage Mode

Használat:

- Live;
- Tuner;
- Metronome;
- Practice Session;
- Song Trainer;
- Speed Builder;
- aktív Vision Coach.

Jellemző:

- minimális chrome;
- nagy, középre rendezett zenei jel;
- sötét háttér;
- magas kontraszt;
- egyetlen elsődleges feedback;
- közvetlen pause/finish kontroll;
- bottom navigation elrejtve.

### Learning Path Mode

Használat:

- tanulási útvonal;
- lecke;
- gyakorlási terv;
- chord library;
- skill progression.

Jellemző:

- egyértelmű sorrend;
- prerequisite és mastery;
- becsült idő;
- következő lépés;
- rövid magyarázat;
- kártya- és útvonalalapú struktúra.

### Studio Analytics Mode

Használat:

- Practice Result;
- Audio Analysis;
- Progress;
- Session Comparison;
- Song Result.

Jellemző:

- summary-first;
- drill-down;
- confidence-aware grafikon;
- összehasonlítható skálák;
- nem büntető nyelvezet;
- exportálható insight.

### Coach Mode

Használat:

- AI Tutor;
- session debrief;
- Vision Coach;
- plan explanation;
- remediation action.

Jellemző:

- „Mit érzékelt?”;
- „Mi lehet az oka?”;
- „Mit csinálj most?”;
- végrehajtható action card;
- local/cloud/fallback provenance;
- tool action előtt megerősítés.

---

# 7. Cél információs architektúra

## 7.1 Compact primary navigation

```text
Today | Practice | Songs | Coach | Profile
```

### Today

- napi terv;
- folytatás;
- daily goal;
- legutóbbi insight;
- streak;
- egyetlen elsődleges CTA.

### Practice

- Live;
- Tuner;
- Metronome;
- Chord Trainer;
- Rhythm Trainer;
- Scale Trainer;
- Speed Builder;
- Technique/Vision Coach;
- practice history.

### Songs

- saját és importált dalok;
- Song Trainer;
- setlistek;
- nehéz részek;
- folytatás;
- import és editor.

### Coach

- AI Tutor;
- session debrief;
- Practice Generator;
- Vision Coach;
- offline model status;
- korábbi javaslatok.

### Profile

- progress;
- skills;
- achievements;
- quests;
- community;
- account;
- settings;
- privacy és data controls.

## 7.2 Medium layout

600–839 logical px közötti szélességnél:

- bottom navigation helyett NavigationRail;
- a fő tartalom maximum olvasható szélességet kap;
- szükség esetén modal helyett side sheet;
- Stage Mode továbbra is teljes képernyős.

## 7.3 Expanded layout

840 logical px felett:

- NavigationRail vagy compact drawer;
- list-detail;
- supporting pane;
- Song Trainerben notation + feedback;
- Analysisban summary + timeline/inspector;
- Communityben feed + detail;
- Settingsben kategórialista + detail;
- route megőrzi a kiválasztott elemet.

## 7.4 Stage Mode navigáció

Aktív audio-, practice-, song- vagy vision-session alatt:

- primary navigation elrejtve;
- rendszer back művelet megerősítést kér, ha adatvesztés lehetséges;
- pause és finish látható;
- Home vagy más tabra ugrás nem történhet véletlenül;
- mikrofon/kamera ownership route lifecycle-hoz kötött.

## 7.5 Legacy route migráció

A következő régi route-ok átmenetileg megmaradnak:

```text
/live
/analyze
/learn
/library
/settings
/tuner
/metronome
/progress
/streak
/songs
/setlists
/chords
```

A target hubok elkészülése után:

- `/live` → `/practice/live`;
- `/analyze` → `/practice/analyze` vagy `/library/analysis`;
- `/learn` → `/practice/learn`;
- `/library` → `/profile/library` vagy egységes Library;
- `/settings` → `/profile/settings`.

A redirect nem szakíthatja meg a deep linket vagy a teszteket. A régi route eltávolítása csak külön deprecation release után történhet.

---

# 8. Breakpoint és layout szabályok

```dart
abstract final class SsBreakpoints {
  static const double compactMax = 599;
  static const double mediumMax = 839;
  static const double expandedMin = 840;
  static const double wideMin = 1200;
}
```

A breakpoint önmagában nem elég. A layout figyelembe veszi:

- orientation;
- text scale;
- safe area;
- keyboard;
- display cutout;
- foldable hinge;
- pointer/keyboard input;
- reduced motion;
- high contrast;
- rendelkezésre álló magasság.

## 8.1 Tartalomszélesség

| Felület | Max szélesség |
|---|---:|
| Auth és egyszerű form | 480 dp |
| Olvasási tartalom | 720 dp |
| Dashboard | 1200 dp |
| Analysis/Song multi-pane | teljes rendelkezésre álló, min pane szabályokkal |
| Stage Mode | teljes viewport |

## 8.2 Spacing grid

4 dp alapgrid:

```text
space0   0
space1   4
space2   8
space3   12
space4   16
space5   20
space6   24
space8   32
space10  40
space12  48
space16  64
```

Képernyőszintű alapoldalmargó:

- compact: 16 dp;
- medium: 24 dp;
- expanded: 32 dp;
- Stage Mode: 16–24 dp, safe area szerint.

---

# 9. Design token rendszer

## 9.1 Tokenrétegek

```text
Primitive tokens
    → Semantic tokens
        → Component tokens
            → Screen composition
```

Tilos widgetben közvetlen hex színt, tetszőleges radius- vagy spacing értéket megadni, kivéve dokumentált, feature-specifikus adatvizualizációs esetet.

## 9.2 Szemantikai színtokenek

```dart
final class SsColorScheme extends ThemeExtension<SsColorScheme> {
  const SsColorScheme({
    required this.brand,
    required this.brandStrong,
    required this.onBrand,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.confidenceHigh,
    required this.confidenceMedium,
    required this.confidenceLow,
    required this.offline,
    required this.localAi,
    required this.cloudAi,
    required this.syncPending,
  });

  // fields...
}
```

### Állapotszín-szabályok

- `danger` csak valódi hibára vagy destruktív műveletre;
- alacsony confidence nem automatikusan danger;
- offline nem danger;
- sync pending nem warning, ha normális offline queue;
- local AI és cloud AI ne csak színnel különbözzön;
- success nem használható kizárólag score színezésére;
- disabled elem szövege is maradjon olvasható.

## 9.3 Témák

### Dark Studio

- alapértelmezett;
- sötét, meleg-neutral surface;
- réz brand;
- alacsony glare;
- Stage Mode prioritás.

### Warm Light

- törtfehér háttér;
- sötét ink;
- réz brand megtartása;
- nappali olvashatóság;
- grafikonok kontrasztja külön validálandó.

### High Contrast

- erősebb border;
- minimális áttetszőség;
- nagyobb fókuszgyűrű;
- shape/pattern redundancia;
- dekoratív blur és glow kikapcsolva;
- confidence állapot szöveges címkével.

## 9.4 Tipográfia

Poppins:

- display chord;
- fő képernyőcím;
- CTA;
- marketing/brand heading;
- nagy score.

Montserrat:

- BPM;
- idő;
- százalék;
- mérőszám;
- timeline;
- technikai címke.

Javasolt scale:

| Token | Font | Méret/line height | Használat |
|---|---|---|---|
| `displayChord` | Poppins 800 | 80/88 compact, adaptive max 128 | aktuális akkord |
| `displayScore` | Poppins 800 | 56/64 | összpontszám |
| `headlineLarge` | Poppins 700 | 32/40 | főcím |
| `headlineMedium` | Poppins 700 | 26/34 | szekció |
| `titleLarge` | Poppins 600 | 22/30 | kártyacím |
| `titleMedium` | Poppins 600 | 18/26 | elemcím |
| `bodyLarge` | Poppins 400 | 16/24 | fő törzsszöveg |
| `bodyMedium` | Poppins 400 | 14/22 | másodlagos szöveg |
| `labelLarge` | Poppins 600 | 14/20 | gomb |
| `metricLarge` | Montserrat 600 | 28/34 | BPM, score |
| `metricMedium` | Montserrat 600 | 18/24 | érték |
| `metricSmall` | Montserrat 500 | 12/18 | timeline |

Szabályok:

- 200% text scaling mellett nincs clipping;
- fontos adat nem kerül csak tooltipbe;
- nagy akkordnév dinamikusan skálázódik;
- all caps csak rövid technikai címkéhez;
- hosszú magyar szöveghez legalább 30% tartalék;
- számokhoz tabular figures használata javasolt.

## 9.5 Radius

```text
radiusXs    6
radiusSm    10
radiusMd    16
radiusLg    20
radiusXl    28
radiusPill  999
```

- input: `radiusSm`;
- normál kártya: `radiusMd`;
- kiemelt hero card: `radiusLg`;
- modal bottom sheet felső sarka: `radiusXl`;
- chip és badge: pill.

## 9.6 Elevation és surface

Sötét témában az elevationt főként:

- surface lightness;
- border;
- rövid shadow;
- minimális brand glow

jelzi.

Tilos minden kártyát erős árnyékkal kiemelni.

## 9.7 Motion tokenek

```text
instant       0–80 ms
fast          120 ms
standard      200 ms
emphasized    300 ms
celebration   max 700 ms
```

- route transition: 200–300 ms;
- chord change: rövid crossfade/scale;
- beat pulse audio clockból;
- hiba esetén nincs agresszív shake;
- reduced motion mellett scale/parallax kikapcsol;
- végtelen dekoratív animáció tiltott.

## 9.8 Ikonográfia

- egységes stroke;
- 24 dp alap;
- 32–48 dp Stage Mode;
- Material Symbols alap + saját gitárglyph készlet;
- ikonhoz mindig semantics label, ha interaktív;
- production felületen emoji helyett ikon.

Saját glyph szükséges:

```text
downstrum
upstrum
alternatePicking
palmMute
bend
vibrato
hammerOn
pullOff
slide
capo
metronome
tuningPeg
fretboard
loopAB
```

---

# 10. Cél design-system mappastruktúra

```text
lib/core/design_system/
├── foundations/
│   ├── ss_breakpoints.dart
│   ├── ss_colors.dart
│   ├── ss_typography.dart
│   ├── ss_spacing.dart
│   ├── ss_radius.dart
│   ├── ss_elevation.dart
│   ├── ss_motion.dart
│   └── ss_semantics.dart
├── themes/
│   ├── ss_dark_theme.dart
│   ├── ss_light_theme.dart
│   ├── ss_high_contrast_theme.dart
│   └── ss_theme_extensions.dart
├── icons/
│   ├── ss_icons.dart
│   └── guitar_glyphs.dart
├── components/
│   ├── actions/
│   ├── cards/
│   ├── feedback/
│   ├── inputs/
│   ├── navigation/
│   ├── overlays/
│   ├── music/
│   ├── analytics/
│   ├── ai/
│   └── community/
├── layouts/
│   ├── ss_adaptive_scaffold.dart
│   ├── ss_stage_scaffold.dart
│   ├── ss_list_detail.dart
│   ├── ss_supporting_pane.dart
│   └── ss_constrained_content.dart
├── documentation/
│   └── component_catalog_screen.dart
└── public.dart
```

A meglévő `lib/core/theme/` nem törlendő az első körben. Az új design system kompatibilitási exporton keresztül használhatja, majd fokozatosan átveszi a felelősségét.

---

# 11. Kötelező közös komponensek

## 11.1 Layout és navigáció

- `SsAdaptiveScaffold`
- `SsStageScaffold`
- `SsConstrainedContent`
- `SsListDetail`
- `SsSupportingPane`
- `SsPrimaryNavigation`
- `SsSectionHeader`
- `SsScreenHeader`
- `SsStickyActionBar`

## 11.2 Action és input

- `SsPrimaryButton`
- `SsSecondaryButton`
- `SsTertiaryButton`
- `SsDestructiveButton`
- `SsIconButton`
- `SsSegmentedControl`
- `SsChoiceChip`
- `SsTextField`
- `SsSearchField`
- `SsSlider`
- `SsStepper`
- `SsSwitchRow`
- `SsRadioRow`
- `SsDurationPicker`
- `SsTempoPicker`

## 11.3 Feedback és állapot

- `SsLoadingState`
- `SsSkeleton`
- `SsEmptyState`
- `SsErrorState`
- `SsOfflineBanner`
- `SsSyncPendingBadge`
- `SsPermissionState`
- `SsDegradedModeBanner`
- `SsInlineMessage`
- `SsSnackbar`
- `SsProgressIndicator`
- `SsConfidenceBadge`
- `SsSignalQualityIndicator`

## 11.4 Zenei komponensek

- `SsChordHero`
- `SsStrumGlyph`
- `SsBeatGrid`
- `SsTempoDisplay`
- `SsTunerGauge`
- `SsChordDiagram`
- `SsFretboard`
- `SsTabViewport`
- `SsNotationViewport`
- `SsPlayhead`
- `SsLoopRange`
- `SsWaveform`
- `SsSessionTransport`

## 11.5 Analytics komponensek

- `SsScoreRing`
- `SsMetricCard`
- `SsTrendChip`
- `SsTimeline`
- `SsHeatmap`
- `SsConfidenceLegend`
- `SsComparisonChart`
- `SsInsightCard`

## 11.6 AI és Vision komponensek

- `SsAiModeBadge`
- `SsEvidenceCard`
- `SsCoachActionCard`
- `SsToolConfirmationSheet`
- `SsStreamingMessage`
- `SsModelStatusCard`
- `SsVisionOverlay`
- `SsCalibrationFrame`
- `SsTechniqueCue`

## 11.7 Community komponensek

- `SsProfileHeader`
- `SsPostCard`
- `SsReactionBar`
- `SsCommentComposer`
- `SsChallengeCard`
- `SsLeaderboardRow`
- `SsModerationActionSheet`
- `SsPrivacyAudiencePicker`

---

# 12. Képernyőállapot-szerződés

Minden aszinkron képernyő explicit állapotmodellt használjon.

```dart
sealed class ScreenState<T> {
  const ScreenState();
}

final class ScreenLoading<T> extends ScreenState<T> {}
final class ScreenContent<T> extends ScreenState<T> {
  const ScreenContent(this.value);
  final T value;
}
final class ScreenEmpty<T> extends ScreenState<T> {}
final class ScreenOffline<T> extends ScreenState<T> {
  const ScreenOffline({this.cachedValue});
  final T? cachedValue;
}
final class ScreenSyncPending<T> extends ScreenState<T> {
  const ScreenSyncPending(this.value);
  final T value;
}
final class ScreenDegraded<T> extends ScreenState<T> {
  const ScreenDegraded(this.value, this.reason);
  final T value;
  final String reason;
}
final class ScreenPermissionRequired<T> extends ScreenState<T> {}
final class ScreenFailure<T> extends ScreenState<T> {
  const ScreenFailure(this.failure);
  final AppFailure failure;
}
final class ScreenBlocked<T> extends ScreenState<T> {
  const ScreenBlocked(this.reason);
  final String reason;
}
```

## 12.1 Állapotmegjelenítési szabályok

- Loading alatt ne ugorjon a layout indokolatlanul.
- Empty state tartalmazzon következő értelmes lépést.
- Offline state ne legyen piros.
- Cached content esetén az adat maradjon látható.
- Permission state magyarázza el, miért szükséges az engedély.
- Permanently denied esetén legyen „Open settings”.
- Failure állapotban ne jelenjen meg nyers exception.
- Retry csak retryable hibánál.
- Blocked state mondja meg a feloldás feltételét.
- Degraded state mutassa, melyik funkció csökkentett pontosságú.

---

# 13. Accessibility követelmények

## 13.1 Minimum

- interaktív cél legalább 48×48 dp;
- WCAG AA célkontraszt;
- teljes TalkBack/VoiceOver semantics;
- logikus fókuszsorrend;
- 200% text scale;
- landscape;
- reduced motion;
- high contrast;
- external keyboard fókusz;
- nem csak színnel jelzett állapot;
- grafikonokhoz szöveges összefoglaló.

## 13.2 Zenei semantics

Példák:

```text
“Current chord: A minor. Confidence high.”
“Down strum on beat two.”
“Timing: eighteen milliseconds late, rated good.”
“Tuner: E two, twelve cents flat.”
“Practice paused. Six minutes completed.”
```

A beat grid egyenkénti fókuszálása csak részletes módban legyen lehetséges; normál módon összefoglaló semantics szükséges, hogy a képernyőolvasó ne olvasson fel több száz eseményt.

## 13.3 Haptika és hang

- haptika kikapcsolható;
- metronóm hangereje külön;
- accessibility cue nem ütközhet a gitárhang mérésével;
- Tuner „in tune” haptika opcionális;
- success és error haptika ne legyen azonos;
- haptika nem lehet egyetlen visszajelzési csatorna.

---

# 14. Lokalizáció és tartalomtervezés

- Minden user-facing string ARB fájlba kerül.
- Tilos stringet összefűzni nyelvtani mondatként.
- A szám-, dátum-, idő- és százalékformátum locale-aware.
- Magyar szövegnél hosszabb címekre fel kell készülni.
- Angol rövidítés mellé magyar magyarázat szükséges, ha a célcsoport kezdő.
- „AI szerint” helyett pontos provenance: „Helyi AI”, „Felhő AI”, „Szabályalapú javaslat”.
- Hibaüzenet szerkezete:
  1. mi történt;
  2. mi maradt biztonságban;
  3. mi a következő lépés.
- A UI nem szégyeníti a tanulót.
- Streak nyelvezete együttérző.
- Alacsony score helyett „fejlesztendő terület” és konkrét következő feladat.

---

# 15. Privacy, AI és sync jelölések

## 15.1 Kötelező badge-ek

```text
On device
Local AI
Cloud AI
Offline
Sync pending
Shared
Private
Public
Friends
Low confidence
```

Minden badge ikon + szöveg kombinációt használjon.

## 15.2 Mikrofon és kamera

Aktív capture esetén:

- állandó, jól látható indikátor;
- egyértelmű stop;
- háttérbe kerüléskor leállás;
- consent scope;
- nyers audio/video tárolásának státusza;
- diagnosztikai feltöltés külön megerősítéssel.

## 15.3 AI action

AI által javasolt művelet nem hajtható végre automatikusan, ha:

- adatot töröl;
- public tartalmat hoz létre;
- üzenetet vagy kommentet küld;
- modellt tölt le mobilhálózaton;
- kamerát vagy mikrofont indít;
- gyakorlási tervet felülír;
- account- vagy privacy-beállítást módosít.

---

# 16. Adatvizualizációs szabályok

- Azonos metric azonos skálát és irányt használ.
- A score definíciója info sheetből elérhető.
- Confidence overlay külön jelenik meg.
- Bizonytalan szakasz szürke/pattern jelölést kap.
- Grafikonhoz rövid text summary.
- Piros csak valódi hibára, nem egyszerűen gyenge score-ra.
- Trend minimum elegendő adatpont után jelenik meg.
- Hiányzó adatot nem szabad nullaként ábrázolni.
- Comparison chart csak összehasonlítható sessionök között.
- Zoom és pan gesture nem blokkolhatja a rendszer back gesture-t.
- Exportált kép tartalmazza a metric nevét, dátumot és units értéket, érzékeny adat nélkül.

---

# 17. Analitika és observability

UI analytics kizárólag adatvédelmi döntés és consent szerint.

Engedélyezett eseménytípusok:

- screen view;
- primary CTA;
- session start/pause/finish;
- permission result;
- empty-state action;
- recoverable error category;
- feature flag exposure;
- layout class;
- accessibility setting aggregate, kizárólag anonimizált és engedélyezett formában.

Tilos:

- nyers audio;
- prompt teljes szövege;
- chat tartalma;
- e-mail;
- JWT;
- pontos kamera frame;
- teljes community draft;
- érzékeny beállítás.

Minden képernyő-specifikációban az analytics esemény neve stabil, snake_case formátumú.

---

# 18. Tesztelési stratégia

## 18.1 Golden matrix

Minimum theme:

- Dark Studio;
- Warm Light;
- High Contrast.

Minimum layout:

- compact portrait;
- compact landscape;
- medium;
- expanded.

Minimum locale:

- `en`;
- `hu`.

Minimum text scale:

- 1.0;
- 1.3;
- 2.0 kritikus képernyőkön.

Nem szükséges minden kombinációból minden képernyőre golden. Kockázatalapú matrix szükséges, de a következő képernyők teljes matrixot kapnak:

- Today;
- Live Stage;
- Practice Session;
- Song Trainer;
- Analysis Overview;
- Tutor Conversation;
- Vision Coach;
- Settings/Privacy.

## 18.2 Widget tesztek

- minden állapot branch;
- primary action;
- destructive confirmation;
- route argument;
- semantics;
- keyboard;
- overflow;
- loading→content race;
- offline cached state;
- permission denied;
- retry.

## 18.3 Valós eszközteszt

- kis Android telefon;
- középkategóriás Android;
- nagy kijelzős Android;
- tablet vagy emulator;
- foldable emulator;
- legalább egy iOS eszköz, amikor az iOS build elérhető;
- sötét és világos környezet;
- landscape;
- Bluetooth audio nem támogatott vagy korlátozott esetének jelzése;
- thermal és battery hosszabb session alatt.

## 18.4 Visual acceptance

Minden migrált képernyőhöz szükséges:

- referencia screenshot;
- golden;
- accessibility checklist;
- interaction recording a kritikus flow-ról;
- product owner jóváhagyás;
- dokumentált eltérés, ha a platform miatt szükséges.

---

# 19. Képernyő-specifikációk

A következő 65 specifikáció a célállapotot rögzíti. Egy képernyő csak akkor tekinthető implementáltnak, ha nemcsak a content state, hanem az összes releváns loading, empty, offline, permission, degraded, failure és accessibility állapot is elkészült.

A route-ok célroute-ok. A meglévő route-ok átmeneti aliasai a migráció során megmaradhatnak.

## UI-01 — Launch & Bootstrap

**Route/célroute:** `/launch`  
**UI-mód:** System  
**Feature owner:** App/Core Platform

### Cél
Az alkalmazás indulásának rövid, stabil felülete. Inicializálja a konfigurációt, storage migrációt, theme-et, locale-t és route döntést anélkül, hogy hamis előrehaladást mutatna.

### Belépési pontok
- alkalmazás hidegindítása
- process újraindítása rendszer általi kilövés után
- deep link indítás

### Elsődleges művelet
- **Automatikus továbblépés a megfelelő kezdőroute-ra**

### Másodlagos műveletek
- Diagnosztikai részletek megnyitása csak development/lab buildben

### Compact layout
Teljes képernyős canvas, középen StrumSight logomark és rövid progress állapot. Nincs interaktív CTA normál induláskor. A rendszer splash után legfeljebb egy stabil layout jelenjen meg.

### Medium/expanded layout
Ugyanaz a fókuszált kompozíció, legfeljebb 480 dp széles középső panellel. Nem jelenik meg fölösleges multi-pane.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsInlineMessage`
- `SsAiModeBadge`

### Állapotok
- bootstrap in progress
- storage migration in progress
- deep-link resolution
- recoverable configuration failure
- fatal safe-mode handoff

### Adatkontraktus
- AppConfig
- storage schema version
- onboarding status
- auth/session status
- incoming deep link

### Accessibility
- A progress állapot rövid, nem ismétlődő live region.
- A logó nem kap fölösleges fókuszt.
- Reduce motion mellett nincs pulzáló animáció.

### Privacy és biztonság
Az indulási képernyő nem jelenít meg személyes adatot és nem küld telemetriát consent döntés előtt.

### Analitika
- `launch_completed`

### Elfogadási feltételek
- [ ] Nincs fehér vagy theme-eltéréses villanás.
- [ ] Induláskor nem történik account request, ha account disabled vagy a felhasználó kijelentkezett.
- [ ] A deep link a bootstrap befejezése után pontosan egyszer kerül feldolgozásra.
- [ ] Hiba esetén a Recovery képernyőre jut, nem marad végtelen loaderen.

## UI-02 — Recovery & Safe Mode

**Route/célroute:** `/recovery`  
**UI-mód:** System  
**Feature owner:** App/Core Platform

### Cél
Kontrollált helyreállítás konfigurációs, storage-migrációs vagy kritikus bootstrap hiba után. Megmutatja, mi maradt biztonságban és milyen visszafordítható lépések érhetők el.

### Belépési pontok
- UI-01 fatal vagy recoverable failure
- explicit safe-mode indítás development támogatással

### Elsődleges művelet
- **Újrapróbálás**

### Másodlagos műveletek
- Indítás helyi safe mode-ban
- Diagnosztikai jelentés exportálása
- Adat-visszaállítási útmutató

### Compact layout
Középre rendezett error panel, rövid cím, emberi magyarázat, adatbiztonsági mondat és maximum két azonnali CTA. Technikai részletek lenyithatók.

### Medium/expanded layout
Kétoszlopos panel: balra felhasználói helyreállítás, jobbra csak engedélyezett buildben diagnosztikai információ. Productionben a technikai részletek redaktáltak.

### Kötelező komponensek
- `SsErrorState`
- `SsPrimaryButton`
- `SsSecondaryButton`
- `SsInlineMessage`

### Állapotok
- retryable bootstrap failure
- storage migration blocked
- configuration invalid
- safe mode active
- export success/failure

### Adatkontraktus
- AppFailure code
- retryable flag
- migration checkpoint
- safe-mode capability

### Accessibility
- A hiba címe fókuszt kap.
- A technikai részletek alapból összecsukottak.
- A gombcímkék konkrétak, nem csak „OK”.

### Privacy és biztonság
A diagnosztikai export explicit művelet; token, e-mail, nyers audio és prompt nem kerülhet bele.

### Analitika
- `recovery_action_selected`

### Elfogadási feltételek
- [ ] Nyers stack trace nem jelenik meg productionben.
- [ ] A safe mode nem töröl felhasználói adatot.
- [ ] Retry nem indíthat párhuzamos bootstrap folyamatot.
- [ ] A felhasználó mindig tudja, mely funkciók korlátozottak.

## UI-03 — Onboarding — Value & Privacy

**Route/célroute:** `/onboarding/value`  
**UI-mód:** Learning  
**Feature owner:** Onboarding

### Cél
Röviden elmagyarázza a StrumSight értékét, offline működését és adatkezelési alapját anélkül, hogy engedélyt kérne a felhasználói kontextus előtt.

### Belépési pontok
- első indítás
- onboarding újraindítása Settingsből

### Elsődleges művelet
- **Folytatás**

### Másodlagos műveletek
- Adatvédelem részletei
- Kihagyás csak akkor, ha a termékflow engedi

### Compact layout
Legfeljebb három lap vagy egy görgethető történet: See what you strum; on-device audio; személyre szabott gyakorlás. Az elsődleges CTA sticky safe-area felett.

### Medium/expanded layout
Bal oldalon rövid vizuális bemutató, jobb oldalon szöveg és CTA. A panelek sorrendje képernyőolvasón lineáris.

### Kötelező komponensek
- `SsConstrainedContent`
- `SsPrimaryButton`
- `SsSectionHeader`
- `SsPrivacyAudiencePicker`

### Állapotok
- first page
- subsequent page
- privacy details open
- resume after interruption

### Adatkontraktus
- onboarding version
- locale
- theme
- analytics consent eligibility

### Accessibility
- A lapozás nem az egyetlen navigációs mód; látható Next gomb.
- Illusztrációk alt textje csak akkor értelmes, ha információt adnak.
- Text scale 2.0 mellett nincs fix magasság.

### Privacy és biztonság
Consent nem előre kipipált. Account és community opcionális rétegként jelenik meg.

### Analitika
- `onboarding_value_viewed`

### Elfogadási feltételek
- [ ] Az offline/on-device állítás világos.
- [ ] Nem indul mikrofon vagy kamera.
- [ ] A felhasználó visszatérhet az előző lépésre.
- [ ] Az onboarding verziózott és megszakítás után folytatható.

## UI-04 — Onboarding — First Win & Microphone Primer

**Route/célroute:** `/onboarding/first-win`  
**UI-mód:** Stage + Learning  
**Feature owner:** Onboarding / Live

### Cél
Kontextust ad a mikrofonengedélyhez, majd egy rövid első sikerélményben megmutatja az akkord- és strum-direction felismerést.

### Belépési pontok
- UI-03 folytatás
- Practice Hub első Live indítása engedély nélkül

### Elsődleges művelet
- **Mikrofon engedélyezése és próba indítása**

### Másodlagos műveletek
- Most kihagyom
- Miért szükséges?

### Compact layout
Engedélykérés előtt statikus magyarázó panel. Engedély után mini Stage Mode: egy akkord, egy strum glyph, jelminőség és 30–60 másodperces cél.

### Medium/expanded layout
Középen Stage panel, jobb oldali supporting pane-ben rövid beállítási tippek. A kamera nem része ennek a flow-nak.

### Kötelező komponensek
- `SsPermissionState`
- `SsChordHero`
- `SsStrumGlyph`
- `SsSignalQualityIndicator`
- `SsStageScaffold`

### Állapotok
- permission not requested
- denied
- permanently denied
- capture starting
- listening
- first detection
- timeout/no signal
- success

### Adatkontraktus
- MicrophonePermissionState
- AudioSessionLease
- LiveFrame
- signal quality
- first-win completion

### Accessibility
- A rendszer permission dialog előtt a képernyő elmagyarázza a célt.
- Az akkord és irány szövegesen is felolvasódik.
- A gyorsan változó frame-ek nem spamlik a live regiont.

### Privacy és biztonság
A hang nem hagyja el az eszközt. Nyers audio nem kerül mentésre ebben a flow-ban.

### Analitika
- `onboarding_first_win_completed`

### Elfogadási feltételek
- [ ] Engedély megtagadása nem blokkolja az app többi részét.
- [ ] Permanently denied esetén Open Settings CTA.
- [ ] A mikrofon a flow elhagyásakor felszabadul.
- [ ] Nincs hamis „siker”, ha nincs elég signal confidence.

## UI-05 — Today Hub

**Route/célroute:** `/today`  
**UI-mód:** Learning  
**Feature owner:** Home / Practice Generator

### Cél
A napi irányítóközpont: egyetlen ajánlott következő lépést, napi tervet, folytatható munkát és rövid fejlődési visszajelzést ad.

### Belépési pontok
- primary navigation Today tab
- app start onboarding után
- notification deep link

### Elsődleges művelet
- **Mai gyakorlás indítása vagy folytatása**

### Másodlagos műveletek
- Terv megtekintése
- Legutóbbi eredmény
- Napi cél módosítása

### Compact layout
Üdvözlés, napi cél progress, kiemelt Continue/Start card, mai feladatlista, rövid Coach insight. Egyetlen erős copper CTA. A kártyák prioritás szerint, nem végtelen feedként jelennek meg.

### Medium/expanded layout
Bal oldalon napi terv és CTA, jobb oldali supporting pane-ben progress, streak és legutóbbi insight. Maximum két egyenrangú pane.

### Kötelező komponensek
- `SsAdaptiveScaffold`
- `SsProgressIndicator`
- `SsCoachActionCard`
- `SsInsightCard`
- `SsMetricCard`

### Állapotok
- new user
- plan ready
- session in progress
- day completed
- offline plan
- sync pending
- generator unavailable
- empty/no plan

### Adatkontraktus
- DailyPracticePlan
- daily goal
- streak snapshot
- last session summary
- recommendation provenance

### Accessibility
- A fő CTA az első tartalmi fókusz.
- Progress százalék szövegesen is elérhető.
- A feladatlista logikus sorrendben olvasható.

### Privacy és biztonság
A személyre szabás forrása jelölhető; cloud AI hiányában local/deterministic terv jelenik meg.

### Analitika
- `today_primary_cta`

### Elfogadási feltételek
- [ ] A képernyő 5 másodpercen belül érthető következő lépést ad.
- [ ] Offline cached plan teljesen használható.
- [ ] Nincs több mint egy primary button.
- [ ] Elvégzett nap után nem kelt bűntudatot, hanem recapet mutat.

## UI-06 — Practice Hub

**Route/célroute:** `/practice`  
**UI-mód:** Learning  
**Feature owner:** Practice

### Cél
Minden gyakorlási eszköz rendezett belépési pontja, a legfontosabb folytatással és célalapú kategóriákkal.

### Belépési pontok
- primary navigation Practice tab
- Today secondary action
- Coach remediation action

### Elsődleges művelet
- **Ajánlott gyakorlat indítása**

### Másodlagos műveletek
- Live megnyitása
- Tuner
- Metronome
- Gyakorlattípus böngészése
- Előzmények

### Compact layout
Kiemelt ajánlás felül, majd cél szerinti szekciók: Warm-up, Chords, Rhythm, Scales, Technique, Tools. Tuner és Metronome quick actionként, de nem versenyeznek a primary CTA-val.

### Medium/expanded layout
Bal oldali kategórialista, középen gyakorlatkatalógus, jobb oldalon kiválasztott elem előnézet. Stage feature csak indítás után.

### Kötelező komponensek
- `SsAdaptiveScaffold`
- `SsSearchField`
- `SsChoiceChip`
- `SsCoachActionCard`
- `SsSectionHeader`

### Állapotok
- recommended available
- no recommendation
- offline
- filter active
- search empty
- feature unavailable by device capability

### Adatkontraktus
- PracticeCatalog
- recommendation
- capability profile
- recent exercises
- favorites

### Accessibility
- A tool ikonokhoz szövegcímke.
- A kategóriák heading semanticsot kapnak.
- A filter állapot bejelenthető.

### Privacy és biztonság
A feature-kártyák egyértelműen jelzik, melyik igényel mikrofont, kamerát vagy hálózatot.

### Analitika
- `practice_hub_exercise_selected`

### Elfogadási feltételek
- [ ] A Live, Tuner és Metronome legfeljebb két érintésből elérhető.
- [ ] Gyenge eszközön nem támogatott vision feature magyarázott disabled állapotot kap.
- [ ] Search és filter együtt működik.
- [ ] A hub nem indít mikrofont.

## UI-07 — Profile Hub

**Route/célroute:** `/profile`  
**UI-mód:** Learning + Community  
**Feature owner:** Profile

### Cél
A személyes fejlődés, jutalmak, közösségi identitás, account, settings és privacy összefogó felülete.

### Belépési pontok
- primary navigation Profile tab
- community public profile owner action
- settings shortcut

### Elsődleges művelet
- **Fejlődés megtekintése**

### Másodlagos műveletek
- Achievements
- Community profil
- Settings
- Privacy & Data
- Account

### Compact layout
Profilfejléc helyi névvel/avatar nélkül is működik. Progress summary, skill highlights, reward summary, majd account/community/settings listák. Logged-out állapotban nem mutat hibát.

### Medium/expanded layout
Bal oldali profil és navigáció, jobb oldali aktuális detail. Account és community külön opcionális blokk.

### Kötelező komponensek
- `SsProfileHeader`
- `SsMetricCard`
- `SsTrendChip`
- `SsSectionHeader`
- `SsOfflineBanner`

### Állapotok
- local-only profile
- signed in
- community enabled/disabled
- sync pending
- profile loading
- account failure

### Adatkontraktus
- LocalLearnerProfile
- ProgressSummary
- GamificationSummary
- AccountState
- CommunityProfileSummary

### Accessibility
- Avatar dekoratív, ha nincs informatív tartalma.
- A progress kártyák értékei felolvasva egységgel együtt jelennek meg.
- A listák explicit címkések.

### Privacy és biztonság
A local profile és public community profile külön entitásként jelenik meg. A public audience státusz látható.

### Analitika
- `profile_section_opened`

### Elfogadási feltételek
- [ ] Core progress account nélkül elérhető.
- [ ] Community hiánya nem foglal el zavaró üres területet.
- [ ] Settings és Privacy egyértelműen megtalálható.
- [ ] Sync hiba nem rejti el a helyi adatokat.

## UI-08 — Live Stage

**Route/célroute:** `/practice/live`  
**UI-mód:** Stage  
**Feature owner:** Live

### Cél
Valós időben, messziről olvashatóan mutatja az aktuális akkordot, strum-directiont, beat helyzetet, BPM-et, confidence-t és jelminőséget.

### Belépési pontok
- Practice Hub Live
- Today quick start
- onboarding first win
- Coach listen-again action

### Elsődleges művelet
- **Listening indítása / Pause / Finish az állapottól függően**

### Másodlagos műveletek
- Tuner shortcut csak leállított állapotban
- Confidence részletek
- Input beállítás

### Compact layout
Teljes képernyős sötét StageScaffold. Fent session státusz és idő; középen `SsChordHero`; alatta `SsStrumGlyph`; beat grid és egyetlen feedback sor; alul nagy pause/finish transport.

### Medium/expanded layout
Landscape-ben akkord és strum bal oldali hero panel, beat/timeline jobb oldalon. Supporting feedback pane csak elég hely esetén. Nincs primary nav.

### Kötelező komponensek
- `SsStageScaffold`
- `SsChordHero`
- `SsStrumGlyph`
- `SsBeatGrid`
- `SsTempoDisplay`
- `SsSignalQualityIndicator`
- `SsSessionTransport`
- `SsConfidenceBadge`

### Állapotok
- idle
- requesting permission
- starting
- listening
- low signal
- no chord
- degraded
- paused
- finishing
- failure

### Adatkontraktus
- LiveFrame
- AudioOwner
- elapsed duration
- tempo estimate
- signal quality
- confidence threshold

### Accessibility
- Az aktuális akkord throttled live regionben jelenik meg.
- A down/up irány ikon + forma + szöveg.
- A transport gombok legalább 56 dp magasak Stage Mode-ban.
- Reduce motion mellett nincs scale pulse.

### Privacy és biztonság
Állandó on-device microphone badge. Nyers audio mentés csak külön Analyze/diagnostics flow-ban, explicit beállítással.

### Analitika
- `live_session_finished`

### Elfogadási feltételek
- [ ] Karnyújtásnyi távolságból olvasható.
- [ ] A bottom navigation rejtett.
- [ ] A mikrofon route leave, pause és background esetén felszabadul.
- [ ] Alacsony confidence nem jelenik meg biztos találatként.
- [ ] Landscape layout nem vágja le a beat gridet.

## UI-09 — Tuner

**Route/célroute:** `/practice/tuner`  
**UI-mód:** Stage  
**Feature owner:** Tuner

### Cél
Gyors, stabil hangolás note, octave, cents és in-tune visszajelzéssel, alternatív tuning támogatással.

### Belépési pontok
- Practice Hub
- Live paused shortcut
- Song/Practice setup tuning warning

### Elsődleges művelet
- **Hangolás indítása / leállítása**

### Másodlagos műveletek
- Tuning kiválasztása
- Reference tone
- A4 referencia

### Compact layout
Nagy note név középen, cents gauge, flat/sharp irány, string target és tuning selector. A legfontosabb állapot: in tune. Nincs fölösleges grafikon.

### Medium/expanded layout
Bal oldali nagy tuner gauge, jobb oldali string list és reference controls. Landscape-ben a gauge nem nyúlik olvashatatlanra.

### Kötelező komponensek
- `SsStageScaffold`
- `SsTunerGauge`
- `SsSignalQualityIndicator`
- `SsChoiceChip`
- `SsSessionTransport`

### Állapotok
- idle
- permission required
- listening
- no pitch
- unstable pitch
- in tune
- reference tone playing
- failure

### Adatkontraktus
- PitchEstimate
- TuningDefinition
- reference frequency
- selected string
- signal quality

### Accessibility
- Cents érték iránnyal együtt felolvasva: flat/sharp.
- In-tune opcionális haptika.
- Gauge mellett szöveges érték mindig látható.

### Privacy és biztonság
A tuner teljesen on-device; hangot nem ment és nem küld.

### Analitika
- `tuner_session_completed`

### Elfogadási feltételek
- [ ] A note és cents legalább 10 Hz UI frissítéssel stabil, de nem villog.
- [ ] A microphone ownership kizárólagos.
- [ ] Reference tone nem marad aktív route leave után.
- [ ] Alternatív tuning stringjei lokalizálhatóan jelennek meg.

## UI-10 — Metronome

**Route/célroute:** `/practice/metronome`  
**UI-mód:** Stage  
**Feature owner:** Metronome

### Cél
Önálló, pontos tempógyakorló felület BPM, meter, accent, subdivision és tap tempo beállítással.

### Belépési pontok
- Practice Hub
- Practice setup
- Song Trainer tools

### Elsődleges művelet
- **Metronóm indítása / megállítása**

### Másodlagos műveletek
- Tap tempo
- BPM módosítás
- Subdivision
- Accent pattern
- Preset mentése

### Compact layout
Nagy BPM kijelzés, beat indicator, play/stop, plus/minus és tap tempo. Advanced kontrollok bottom sheetben, hogy a fő felület ne legyen zsúfolt.

### Medium/expanded layout
Középen BPM és transport, jobb oldalon meter/subdivision/accent panel. Billentyűzet shortcut támogatás desktop-width esetén.

### Kötelező komponensek
- `SsStageScaffold`
- `SsTempoDisplay`
- `SsBeatGrid`
- `SsTempoPicker`
- `SsSegmentedControl`
- `SsSessionTransport`

### Állapotok
- stopped
- playing
- tempo editing
- tap collecting
- audio output failure
- background handling

### Adatkontraktus
- MetronomeSettings
- audio clock
- beat index
- preset list

### Accessibility
- A beat vizuális jel mellett opcionális haptika.
- BPM módosítható gombbal és szerkeszthető mezővel.
- Motion csökkentésekor a beat flash egyszerű opacity váltás.

### Privacy és biztonság
Nincs adatvédelmi különbség; preset csak helyben tárolódik, ha sync nincs engedélyezve.

### Analitika
- `metronome_started`

### Elfogadási feltételek
- [ ] A vizuális beat az audio clockhoz kötött.
- [ ] Tap tempo outliereket kezel.
- [ ] Stop route leave-kor determinisztikus.
- [ ] A fő kontrollok egy kézzel elérhetők.

## UI-11 — Chord Library

**Route/célroute:** `/practice/chords`  
**UI-mód:** Learning  
**Feature owner:** Chords

### Cél
Akkordok keresése, szűrése, kedvencek és nehézségi/tuning/capo kontextus szerinti böngészése.

### Belépési pontok
- Practice Hub
- Lesson
- Tutor chord action
- Song chord link

### Elsődleges művelet
- **Akkord megnyitása**

### Másodlagos műveletek
- Keresés
- Szűrés
- Kedvenc
- Gyakorlás indítása

### Compact layout
Sticky search, filter chip sor, recent/favorites és alfabetikus lista vagy grid. Minden kártyán akkordnév és egyszerű diagram-előnézet.

### Medium/expanded layout
Bal oldalon filter és lista, jobb oldalon kiválasztott Chord Detail. A kiválasztás route-ban marad.

### Kötelező komponensek
- `SsSearchField`
- `SsChoiceChip`
- `SsChordDiagram`
- `SsListDetail`
- `SsEmptyState`

### Állapotok
- content
- searching
- no results
- favorites empty
- offline
- invalid filter

### Adatkontraktus
- ChordDefinition
- ChordFilter
- favorites
- recent chords
- tuning/capo context

### Accessibility
- A diagramnak szöveges fingering leírása van.
- Search result count bejelenthető.
- Grid helyett listanézet elérhető nagy szövegnél.

### Privacy és biztonság
Nincs különleges adatkezelés. Favorites sync csak account és sync engedéllyel.

### Analitika
- `chord_library_chord_opened`

### Elfogadási feltételek
- [ ] Search diakritika- és enharmonic-aware, ahol értelmezhető.
- [ ] Kedvencek offline működnek.
- [ ] A filterek törölhetők egy művelettel.
- [ ] A diagram nem az egyetlen információforrás.

## UI-12 — Chord Detail

**Route/célroute:** `/practice/chords/:chordId`  
**UI-mód:** Learning  
**Feature owner:** Chords

### Cél
Egy akkord teljes, kezdőbarát bemutatása diagrammal, fingeringgel, megszólalási tippekkel, variációkkal és azonnali gyakorlással.

### Belépési pontok
- Chord Library
- Lesson
- Song overview
- Tutor action

### Elsődleges művelet
- **Akkord gyakorlása**

### Másodlagos műveletek
- Hangminta
- Kedvenc
- Variáció választása
- AI tanár megkérdezése

### Compact layout
Nagy akkordnév, diagram, string-by-string fingering, rövid tippek, variációk horizontális listában. Sticky primary CTA.

### Medium/expanded layout
Bal oldalon diagram és hangminta, jobb oldalon fingering, variációk, elmélet és kapcsolódó leckék.

### Kötelező komponensek
- `SsChordDiagram`
- `SsFretboard`
- `SsPrimaryButton`
- `SsAiModeBadge`
- `SsSectionHeader`

### Állapotok
- content
- audio sample loading/failure
- unsupported tuning
- variation selected
- favorite pending

### Adatkontraktus
- ChordDefinition
- ChordVoicing
- tuning
- capo
- audio sample asset
- related lessons

### Accessibility
- Fret/string pozíciók szöveges listában.
- Audio sample külön play/stop címkével.
- Balkezes nézet a tartalmat is tükrözi, nem csak a képet.

### Privacy és biztonság
A Tutor megnyitása előtt jelzi, hogy local vagy cloud mód lesz elérhető.

### Analitika
- `chord_detail_practice_started`

### Elfogadási feltételek
- [ ] Balkezes és jobbkezes diagram helyes.
- [ ] Capo/tuning kontextus látható.
- [ ] Hangminta leáll route leave-kor.
- [ ] A practice CTA megfelelő gyakorlatot parametrizál.

## UI-13 — Learning Path

**Route/célroute:** `/practice/learn`  
**UI-mód:** Learning  
**Feature owner:** Learn

### Cél
Egymásra épülő leckék és skill prerequisite-ek áttekintése, világos jelenlegi pozícióval és következő lépéssel.

### Belépési pontok
- Practice Hub
- Today plan lesson
- Profile skill detail

### Elsődleges művelet
- **Aktuális lecke folytatása**

### Másodlagos műveletek
- Útvonal váltása
- Korábbi lecke újragyakorlása
- Skill részletek

### Compact layout
Vertikális path: completed, current, available, locked node-ok. Minden node cím, mastery, idő és prerequisite státusz. Nem túlzottan játékos.

### Medium/expanded layout
Bal oldali path/kurzus lista, középen vizuális útvonal, jobb oldalon kiválasztott lecke előnézet.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsTrendChip`
- `SsCoachActionCard`
- `SsListDetail`
- `SsInlineMessage`

### Állapotok
- new path
- in progress
- completed
- locked
- offline content missing
- migration from legacy progress

### Adatkontraktus
- LearningPath
- LessonProgress
- SkillGraph
- content availability
- recommended next lesson

### Accessibility
- A vizuális path lineáris listaként is értelmezhető.
- Locked ok felolvasva.
- Mastery nem csak csillaggal jelenik meg.

### Privacy és biztonság
A tanulási progress helyi adat; cloud sync állapota külön jelzett.

### Analitika
- `learning_path_lesson_selected`

### Elfogadási feltételek
- [ ] A felhasználó látja, miért zárt egy lecke.
- [ ] A current node egyértelmű.
- [ ] Offline hiányzó asset külön letöltési állapotot kap.
- [ ] Legacy progress nem vész el.

## UI-14 — Lesson Detail

**Route/célroute:** `/practice/learn/:lessonId`  
**UI-mód:** Learning  
**Feature owner:** Learn

### Cél
Lecke céljának, előfeltételeinek, lépéseinek és várható eredményének áttekintése a session indítása előtt.

### Belépési pontok
- Learning Path
- Today plan
- Tutor ajánlás

### Elsődleges művelet
- **Lecke indítása vagy folytatása**

### Másodlagos műveletek
- Tartalom letöltése
- Előfeltétel megnyitása
- AI magyarázat

### Compact layout
Hero cím, rövid cél, 3–6 lesson step, becsült idő, szükséges eszközök/engedélyek, mastery feltétel. CTA sticky.

### Medium/expanded layout
Bal oldalon lesson outline, középen kiválasztott tartalom, jobb oldalon prerequisite és progress summary.

### Kötelező komponensek
- `SsSectionHeader`
- `SsProgressIndicator`
- `SsAiModeBadge`
- `SsPrimaryButton`
- `SsOfflineBanner`

### Állapotok
- ready
- resume
- locked
- content downloading
- offline unavailable
- completed
- content version changed

### Adatkontraktus
- LessonDefinition
- LessonProgress
- ContentPackageStatus
- prerequisites
- capability requirements

### Accessibility
- A step lista ordered semantics.
- Videó vagy animáció mellett szöveges alternatíva.
- Becsült idő lokalizált.

### Privacy és biztonság
Mikrofon/kamera csak a lesson megfelelő lépésénél, külön kontextusban indul.

### Analitika
- `lesson_started`

### Elfogadási feltételek
- [ ] A session előtt világos, kell-e mikrofon/kamera.
- [ ] Offline asset állapot egyértelmű.
- [ ] Content update nem nullázza a progress-t.
- [ ] Locked lecke nem indítható kerülő route-tal.

## UI-15 — Practice Plan Setup

**Route/célroute:** `/coach/plan/setup`  
**UI-mód:** Coach + Learning  
**Feature owner:** AI Practice Generator

### Cél
A felhasználó céljainak, elérhető idejének, gyakoriságának, szintjének és korlátainak összegyűjtése strukturált, szerkeszthető formában.

### Belépési pontok
- Coach Home
- Today no-plan state
- Profile goal settings

### Elsődleges művelet
- **Terv készítése**

### Másodlagos műveletek
- Cél hozzáadása
- Időbeosztás módosítása
- Később

### Compact layout
Lépésenkénti form: goal, weekly availability, session length, focus, constraints. Progress indicator és visszalépés. Szabad szöveg csak opcionális.

### Medium/expanded layout
Bal oldali stepper, jobb oldali aktuális form és összefoglaló. A végső preview generálás előtt látható.

### Kötelező komponensek
- `SsStepper`
- `SsChoiceChip`
- `SsDurationPicker`
- `SsRadioRow`
- `SsTextField`
- `SsPrimaryButton`

### Állapotok
- new
- editing existing
- validation failure
- offline deterministic generation available
- cloud enhancement available
- generation blocked

### Adatkontraktus
- PracticeGoal
- ScheduleConstraints
- LearnerProfile
- device capabilities
- generation mode

### Accessibility
- A stepper aktuális lépést és összes lépésszámot közöl.
- Minden inputnak tartós labelje van.
- Hiba a mező mellett és összefoglalóban is megjelenik.

### Privacy és biztonság
A szabad szöveg cloud AI felé küldése külön provenance és consent szerint történik; local/deterministic alternatíva elérhető.

### Analitika
- `practice_plan_setup_completed`

### Elfogadási feltételek
- [ ] A terv készíthető account nélkül.
- [ ] A default értékek módosíthatók.
- [ ] Nem kér irreleváns személyes adatot.
- [ ] Generálás előtt minden constraint összefoglalva látható.

## UI-16 — Weekly Practice Plan

**Route/célroute:** `/coach/plan`  
**UI-mód:** Learning + Coach  
**Feature owner:** AI Practice Generator

### Cél
A teljes heti terv átlátható megjelenítése, módosítása, regenerálása és a döntések magyarázata.

### Belépési pontok
- Today plan details
- Coach Home
- Practice Plan Setup completion

### Elsődleges művelet
- **Mai session indítása**

### Másodlagos műveletek
- Nap megnyitása
- Terv szerkesztése
- Regenerálás
- Miért ezt kaptam?
- Szünetnap jelölése

### Compact layout
Heti nap-chip sor, kiválasztott nap session blokkjai, heti fókusz és progress. Regenerálás overflow/secondary action, nem primary.

### Medium/expanded layout
Bal oldalon hét és napok, középen napi blokklista, jobb oldalon rationale és workload summary.

### Kötelező komponensek
- `SsAdaptiveScaffold`
- `SsProgressIndicator`
- `SsCoachActionCard`
- `SsAiModeBadge`
- `SsToolConfirmationSheet`

### Állapotok
- plan ready
- day completed
- missed day
- rest day
- offline
- regenerating
- conflict with completed work
- sync pending

### Adatkontraktus
- WeeklyPracticePlan
- DailyPlan
- PlanRationale
- completion evidence
- timezone
- plan version

### Accessibility
- A hét nem kizárólag horizontális swipe-pal navigálható.
- A rest/missed/completed állapot szöveges.
- Drag reorder alternatív move up/down gombokkal.

### Privacy és biztonság
A plan rationale nem fed fel érzékeny nyers chat- vagy audioadatot.

### Analitika
- `weekly_plan_action`

### Elfogadási feltételek
- [ ] Már elvégzett sessiont regenerálás nem töröl.
- [ ] Kihagyott nap után együttérző reschedule.
- [ ] Offline plan teljesen megnyitható.
- [ ] A felhasználó látja a javaslat okát és provenance-ét.

## UI-17 — Today Plan Detail

**Route/célroute:** `/today/plan`  
**UI-mód:** Learning  
**Feature owner:** AI Practice Generator / Today

### Cél
A mai gyakorlat teljes, de könnyen áttekinthető lebontása, időbecsléssel, fókuszpontokkal és elvégezhető blokkokkal.

### Belépési pontok
- Today Hub
- Weekly Plan kiválasztott napja
- notification deep link

### Elsődleges művelet
- **Mai gyakorlás indítása**

### Másodlagos műveletek
- Blokk megnyitása
- Rövidített session
- Átütemezés
- Terv indoklása

### Compact layout
Felül napi cél és teljes idő, alatta sorrendezett session blokkok. Minden blokk típust, időt, fókuszt és readiness állapotot mutat. A primary CTA sticky.

### Medium/expanded layout
Középen blokklista, jobb oldali supporting pane-ben kiválasztott blokk részletei és rationale. A teljes nap összideje mindig látható.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsCoachActionCard`
- `SsDurationPicker`
- `SsAiModeBadge`
- `SsStickyActionBar`

### Állapotok
- ready
- partially completed
- completed
- shortened
- offline
- content missing
- schedule conflict

### Adatkontraktus
- DailyPlan
- PracticeBlock
- completion state
- content availability
- rationale

### Accessibility
- A blokkok ordered listként olvashatók.
- Időtartam egységgel felolvasva.
- A completed állapot ikon + szöveg.

### Privacy és biztonság
A rationale forrása local/cloud/deterministic badge-dzsel jelzett.

### Analitika
- `today_plan_started`

### Elfogadási feltételek
- [ ] A felhasználó tud rövidített tervet kérni adatvesztés nélkül.
- [ ] Hiányzó content nem blokkolja a többi blokkot.
- [ ] A megmaradt idő újraszámolódik.
- [ ] Az indítás a megfelelő első nem kész blokkra visz.

## UI-18 — Practice Session Setup

**Route/célroute:** `/practice/session/setup`  
**UI-mód:** Learning  
**Feature owner:** Practice Engine

### Cél
Egy gyakorlat paramétereinek végső beállítása: tempó, időtartam, nehézség, tuning, input és feedback mód.

### Belépési pontok
- Practice Hub exercise
- Today Plan block
- Lesson
- Tutor remediation action

### Elsődleges művelet
- **Session indítása**

### Másodlagos műveletek
- Preset mentése
- Tuner megnyitása
- Metronóm beállítása
- Vision hozzáadása

### Compact layout
Gyakorlat összefoglaló, 3–5 legfontosabb paraméter, readiness checklist, majd primary CTA. Advanced beállítások összecsukva.

### Medium/expanded layout
Bal oldalon exercise preview, jobb oldalon paraméterpanel és readiness. Vision preview csak capability esetén.

### Kötelező komponensek
- `SsTempoPicker`
- `SsDurationPicker`
- `SsSegmentedControl`
- `SsSwitchRow`
- `SsPermissionState`
- `SsPrimaryButton`

### Állapotok
- ready
- permission required
- wrong tuning warning
- device capability degraded
- content unavailable
- validation failure

### Adatkontraktus
- PracticeDefinition
- PracticeSessionConfig
- TuningState
- PermissionState
- CapabilityProfile

### Accessibility
- Slider mellett szerkeszthető számérték.
- A readiness checklist nem csak színnel jelöl.
- A disabled Vision okát felolvassa.

### Privacy és biztonság
Vision és nyers recording opt-in; alapértelmezésként csak szükséges audio feature aktív.

### Analitika
- `practice_session_setup_started`

### Elfogadási feltételek
- [ ] A defaultok a gyakorlatból származnak, de szerkeszthetők.
- [ ] Indítás előtt a szükséges engedélyek tiszták.
- [ ] A tuning warningból közvetlen Tuner nyitható.
- [ ] A session config serializálható és reprodukálható.

## UI-19 — Practice Session

**Route/célroute:** `/practice/session/:sessionId`  
**UI-mód:** Stage  
**Feature owner:** Practice Engine

### Cél
Valós idejű, feladatspecifikus gyakorlás score-ral, beat/target visszajelzéssel, egyszerű korrekcióval és biztonságos lifecycle-lal.

### Belépési pontok
- UI-18 indítás
- Today Plan start
- resume interrupted session, ha támogatott

### Elsődleges művelet
- **Pause / Finish**

### Másodlagos műveletek
- Tempo csökkentése
- Szakasz újra
- Feedback részletek
- Metronóm toggle

### Compact layout
StageScaffold: felső státusz, középen gyakorlat targetje, alatta beat/accuracy feedback és egyetlen coach cue. Transport fixen alul.

### Medium/expanded layout
Landscape/expanded nézetben target balra, timing/beat jobbra, rövid history strip alul. Nem jelenik meg teljes dashboard.

### Kötelező komponensek
- `SsStageScaffold`
- `SsBeatGrid`
- `SsChordHero`
- `SsMetricCard`
- `SsTechniqueCue`
- `SsSessionTransport`
- `SsSignalQualityIndicator`

### Állapotok
- count-in
- active
- low signal
- target missed
- target achieved
- paused
- recovering
- backgrounded
- finishing
- failure

### Adatkontraktus
- PracticeSessionState
- PracticeObservation
- target sequence
- score snapshot
- signal quality
- elapsed time

### Accessibility
- A gyors score nem live region; csak lényeges cue kerül felolvasásra.
- Pause/Finish mindig fókuszálható.
- Visual beathez opcionális hang/haptika.

### Privacy és biztonság
A képernyő állandóan jelzi, hogy recording mentés történik-e. Alapértelmezésként csak strukturált eredmény tárolódik.

### Analitika
- `practice_session_finished`

### Elfogadási feltételek
- [ ] A session state machine minden lifecycle útvonalon konzisztens.
- [ ] A UI nem blokkolja a DSP isolate-ot.
- [ ] Feedback nem változik frame-enként zavaróan.
- [ ] Route leave adatvesztési megerősítést kér.
- [ ] Session végén pontosan egy result keletkezik.

## UI-20 — Practice Pause & Recovery

**Route/célroute:** `/practice/session/:sessionId/pause`  
**UI-mód:** Stage Overlay  
**Feature owner:** Practice Engine

### Cél
Biztonságos megállítás, rövid recovery, paramétermódosítás és session befejezés anélkül, hogy elveszne a már elvégzett munka.

### Belépési pontok
- Practice Session pause
- audio interruption
- app resume interrupted session

### Elsődleges művelet
- **Folytatás**

### Másodlagos műveletek
- Tempó módosítása
- Utolsó rész újra
- Session befejezése
- Mentés és kilépés

### Compact layout
Teljes Stage fölötti opaque/scrim pause panel. Látható elapsed, completed blocks és recovery tip. Destruktív kilépés külön confirmation.

### Medium/expanded layout
Középső pause card, opcionális jobb oldali paraméterpanel. A háttér adata nem interaktív.

### Kötelező komponensek
- `SsStageScaffold`
- `SsToolConfirmationSheet`
- `SsTempoPicker`
- `SsInlineMessage`
- `SsSessionTransport`

### Állapotok
- user paused
- system interruption
- audio focus lost
- resume available
- resume unavailable
- saving

### Adatkontraktus
- PracticeSessionCheckpoint
- pause reason
- audio ownership
- modifiable config

### Accessibility
- Pause megnyitásakor fókusz a címre kerül.
- A háttér semantics elrejtett.
- Destruktív action explicit.

### Privacy és biztonság
A pause alatt kamera preview nem marad aktív, ha nincs rá szükség.

### Analitika
- `practice_pause_action`

### Elfogadási feltételek
- [ ] Pause felszabadítja vagy kontrolláltan tartja az audio erőforrást az architektúra szerint.
- [ ] Folytatás nem duplikál eseményt.
- [ ] Tempóváltozás verziózott session event.
- [ ] Kilépés előtt a mentési következmény világos.

## UI-21 — Practice Result

**Route/célroute:** `/practice/session/:sessionId/result`  
**UI-mód:** Studio Analytics  
**Feature owner:** Practice Engine / Analysis

### Cél
A session azonnali, motiváló és bizonyítékalapú összefoglalója egy fő insighttal és következő akcióval.

### Belépési pontok
- Practice Session finish
- history result deep link

### Elsődleges művelet
- **Ajánlott javítógyakorlat indítása vagy Folytatás a tervben**

### Másodlagos műveletek
- Részletes elemzés
- AI tanár
- Megosztás
- Jegyzet hozzáadása

### Compact layout
Nagy overall score vagy outcome label, rövid pozitív visszajelzés, 3–5 metric, egy fő insight, következő action. Confetti csak külön achievement esetén és reduced-motion aware.

### Medium/expanded layout
Bal oldalon summary és metric, jobb oldalon insight/evidence és next actions. Timeline csak linkként vagy supporting preview-ként.

### Kötelező komponensek
- `SsScoreRing`
- `SsMetricCard`
- `SsInsightCard`
- `SsCoachActionCard`
- `SsConfidenceLegend`
- `SsPrimaryButton`

### Állapotok
- complete
- partial
- low confidence
- insufficient signal
- saving
- sync pending
- analysis enhancement pending

### Adatkontraktus
- PracticeResult
- MetricScore
- EvidenceReference
- NextAction
- reward summary

### Accessibility
- A score mellett szöveges minősítés.
- Grafikon helyett summary.
- Achievement animáció kihagyható.

### Privacy és biztonság
Megosztás előtt külön preview és audience választás. AI action provenance látható.

### Analitika
- `practice_result_primary_action`

### Elfogadási feltételek
- [ ] A result nem büntető nyelvezetű.
- [ ] Alacsony confidence esetén nem generál kategorikus hibát.
- [ ] A következő action közvetlenül végrehajtható.
- [ ] A result mentése idempotens.

## UI-22 — Practice History

**Route/célroute:** `/practice/history`  
**UI-mód:** Studio Analytics  
**Feature owner:** Practice / Progress

### Cél
Korábbi sessionök szűrhető, offline elérhető listája trend- és folytatási lehetőséggel.

### Belépési pontok
- Practice Hub
- Profile Progress
- Today last result

### Elsődleges művelet
- **Session megnyitása**

### Másodlagos műveletek
- Szűrés
- Keresés
- Összehasonlítás
- Export

### Compact layout
Dátum szerint csoportosított lista, session type, duration, key metric, sync badge. Filter sheet a fejlécből.

### Medium/expanded layout
Bal oldali filter/list, jobb oldali kiválasztott session preview. Multi-select compare csak kompatibilis sessionöknél.

### Kötelező komponensek
- `SsSearchField`
- `SsChoiceChip`
- `SsListDetail`
- `SsSyncPendingBadge`
- `SsEmptyState`

### Állapotok
- content
- empty
- filtered empty
- offline cached
- sync pending
- corrupt record isolated
- loading older

### Adatkontraktus
- PracticeSessionSummary
- filters
- pagination cursor
- sync status
- compatibility for compare

### Accessibility
- A list item teljes összefoglalót kap.
- Filter count közölt.
- Infinite scroll mellett alternatív load more.

### Privacy és biztonság
Export explicit, és alapból nem tartalmaz személyes/account adatot.

### Analitika
- `practice_history_session_opened`

### Elfogadási feltételek
- [ ] Sérült rekord nem törli a listát.
- [ ] Offline session megnyitható.
- [ ] Compare csak összehasonlítható típusoknál aktív.
- [ ] A lista stabil scroll positiont tart.

## UI-23 — Speed Builder

**Route/célroute:** `/practice/speed-builder`  
**UI-mód:** Stage + Learning  
**Feature owner:** Practice Engine

### Cél
Fokozatos tempóemelés sikerfeltételekkel, visszaléptetéssel és fáradásérzékeny, nem büntető progresszióval.

### Belépési pontok
- Practice Hub
- Practice Result next action
- Tutor

### Elsődleges művelet
- **Speed Builder indítása**

### Másodlagos műveletek
- Kezdő BPM
- Cél BPM
- Lépésméret
- Sikerfeltétel
- Preset

### Compact layout
Setup állapotban egyszerű paraméterkártya; aktív állapotban Stage Mode BPM hero, current streak, target és pass/repeat cue.

### Medium/expanded layout
Aktív módban balra target/tab, jobbra BPM ladder és aktuális mérőszám. Setup és result ugyanazon route state machine szerint.

### Kötelező komponensek
- `SsTempoPicker`
- `SsProgressIndicator`
- `SsStageScaffold`
- `SsBeatGrid`
- `SsMetricCard`
- `SsSessionTransport`

### Állapotok
- setup
- count-in
- active
- level passed
- repeat
- step down
- fatigue stop suggested
- paused
- result

### Adatkontraktus
- SpeedBuilderConfig
- tempo ladder
- attempt result
- fatigue heuristic
- best stable BPM

### Accessibility
- A ladder szövegesen is olvasható.
- BPM-változás bejelenthető, de nem minden beat.
- Stop suggestion nem csak színnel.

### Privacy és biztonság
Nincs különleges adatkezelés; eredmény helyi progress része.

### Analitika
- `speed_builder_completed`

### Elfogadási feltételek
- [ ] A tempó csak sikerfeltétel teljesülésekor nő.
- [ ] Visszaléptetés megőrzi a teljesített szinteket.
- [ ] A session bármikor biztonságosan leállítható.
- [ ] Az eredmény best stable BPM-et, nem csak max BPM-et mutat.

## UI-24 — Song Library

**Route/célroute:** `/songs`  
**UI-mód:** Learning  
**Feature owner:** Song Trainer

### Cél
Helyi, importált és elérhető dalok böngészése folytatási, nehézségi és readiness információval.

### Belépési pontok
- primary navigation Songs tab
- Today song block
- Profile favorites

### Elsődleges művelet
- **Dal folytatása vagy megnyitása**

### Másodlagos műveletek
- Import
- Keresés
- Szűrés
- Setlistek
- Kedvencek

### Compact layout
Continue card, majd song list cover-art nélkül is erős tipográfiával. Minden elem cím, előadó, progress, source, tuning és offline readiness.

### Medium/expanded layout
Bal oldali filter/list, középen song overview preview, jobb oldali recent practice vagy readiness. Cover art opcionális.

### Kötelező komponensek
- `SsSearchField`
- `SsChoiceChip`
- `SsListDetail`
- `SsProgressIndicator`
- `SsOfflineBanner`

### Állapotok
- content
- empty
- import in progress
- offline asset missing
- filtered empty
- unsupported source
- sync pending

### Adatkontraktus
- SongSummary
- SongSource
- progress
- asset readiness
- tuning
- favorites

### Accessibility
- Album art dekoratív, a cím/előadó szöveges.
- Progress és readiness felolvasva.
- List/grid választás megőrzött.

### Privacy és biztonság
Cloud/community forrás külön badge-et kap; privát import alapból nem publikus.

### Analitika
- `song_library_song_opened`

### Elfogadási feltételek
- [ ] A local songs offline elérhetők.
- [ ] A source/licence státusz látható.
- [ ] Import legfeljebb egy elsődleges belépési ponttal.
- [ ] Hiányzó backing track nem rejti el a notationt.

## UI-25 — Song Overview

**Route/célroute:** `/songs/:songId`  
**UI-mód:** Learning  
**Feature owner:** Song Trainer

### Cél
Egy dal readiness, szekciók, progress, tuning, backing track és gyakorlási ajánlásainak áttekintése.

### Belépési pontok
- Song Library
- Today
- Setlist
- Community shared song

### Elsődleges művelet
- **Dal gyakorlása vagy folytatása**

### Másodlagos műveletek
- Szakasz választása
- Trainer setup
- Editor
- Setlisthez adás
- Megosztás

### Compact layout
Cím/előadó, progress, tuning/capo, asset status, section list és nehéz részek. Primary CTA sticky.

### Medium/expanded layout
Bal oldalon metadata és section list, középen notation preview, jobb oldalon progress/insight/readiness.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsTabViewport`
- `SsOfflineBanner`
- `SsInsightCard`
- `SsPrimaryButton`

### Állapotok
- ready
- partial assets
- unsupported elements
- offline
- content update available
- community source revoked

### Adatkontraktus
- SongDocument
- SongAssetStatus
- SongProgress
- section difficulty
- rights/source metadata

### Accessibility
- A notation preview mellett text summary.
- A section list headingeket használ.
- Tuning/capo explicit.

### Privacy és biztonság
Megosztott vagy importált dal licence/source információja látható; private user asset nem kerül automatikusan cloudba.

### Analitika
- `song_overview_practice_started`

### Elfogadási feltételek
- [ ] A felhasználó indítás előtt látja a hiányzó assetet.
- [ ] Szakasz direkt indítható.
- [ ] Unsupported notation elem nem omlasztja össze a képernyőt.
- [ ] Community source visszavonásakor a jogszerű helyi tartalom státusza tiszta.

## UI-26 — Song Import

**Route/célroute:** `/songs/import`  
**UI-mód:** System + Learning  
**Feature owner:** Song Trainer

### Cél
Fájl vagy támogatott forrás kiválasztása, formátumfelismerés, biztonságos helyi másolás és importfolyamat indítása.

### Belépési pontok
- Song Library import
- system share/open-with
- empty state

### Elsődleges művelet
- **Fájl kiválasztása**

### Másodlagos műveletek
- Támogatott formátumok
- Korábbi import folytatása
- Minta dal

### Compact layout
Drop/select card, támogatott MusicXML/MXL/MIDI és validált Guitar Pro státusz, privacy rövid leírás. Import progress külön full-screen state.

### Medium/expanded layout
Bal oldalon source választás, jobb oldalon formátum és korlátozás. Drag-and-drop desktop-width esetén.

### Kötelező komponensek
- `SsEmptyState`
- `SsProgressIndicator`
- `SsInlineMessage`
- `SsPrimaryButton`
- `SsPermissionState`

### Állapotok
- idle
- picking
- copying
- detecting
- parsing
- cancelled
- unsupported
- too large
- failure

### Adatkontraktus
- ImportSource
- file metadata
- format detection
- size limit
- parse progress

### Accessibility
- Drag-and-drop mellett file picker.
- Progress érték és lépés felolvasva.
- Hibák konkrét formátum- és javítási információval.

### Privacy és biztonság
A fájl alapból helyben marad. Cloud/community feltöltés teljesen külön flow.

### Analitika
- `song_import_started`

### Elfogadási feltételek
- [ ] Import megszakítható.
- [ ] Eredeti fájl nem módosul.
- [ ] Túl nagy vagy veszélyes input korán elutasított.
- [ ] A temp fájl hiba után törlődik.
- [ ] Nincs path traversal.

## UI-27 — Import Preview & Mapping

**Route/célroute:** `/songs/import/preview/:importId`  
**UI-mód:** Learning  
**Feature owner:** Song Trainer

### Cél
A parse eredményének ellenőrzése, track/part választás, tempo/tuning mapping és figyelmeztetések kezelése mentés előtt.

### Belépési pontok
- Song Import sikeres parse

### Elsődleges művelet
- **Dal mentése**

### Másodlagos műveletek
- Track választás
- Mapping javítása
- Vissza az importhoz
- Unsupported elemek listája

### Compact layout
Metadata form, selected track, section/measure summary, warning list és egyszerű notation preview. Save csak valid state-ben.

### Medium/expanded layout
Bal oldalon track és mapping, középen preview, jobb oldalon warning/unsupported inspector.

### Kötelező komponensek
- `SsSegmentedControl`
- `SsTextField`
- `SsTabViewport`
- `SsInlineMessage`
- `SsStickyActionBar`

### Állapotok
- valid
- warnings
- blocking errors
- multiple tracks
- mapping edited
- saving

### Adatkontraktus
- ImportedSongDraft
- TrackCandidate
- ImportWarning
- mapping
- source checksum

### Accessibility
- Warning severity ikon + szöveg.
- Preview helyett struktúrált measure summary.
- Form hibák fókuszálhatók.

### Privacy és biztonság
A preview nem tölti fel a fájlt. A source path nem jelenik meg publikus metadata részeként.

### Analitika
- `song_import_saved`

### Elfogadási feltételek
- [ ] A mentés előtt a kiválasztott track egyértelmű.
- [ ] Warning nem rejtett.
- [ ] Blocking error nem kerülhető meg.
- [ ] Az import source és mapping reprodukálható.

## UI-28 — Song Editor

**Route/célroute:** `/songs/:songId/edit`  
**UI-mód:** Studio  
**Feature owner:** Song Trainer

### Cél
Dal metadata, szekciók, loop pontok, egyszerű akkord/tab események és trainer-beállítások biztonságos szerkesztése.

### Belépési pontok
- Song Overview
- Import Preview after save
- Library action

### Elsődleges művelet
- **Változtatások mentése**

### Másodlagos műveletek
- Undo
- Redo
- Preview
- Szekció hozzáadása
- Másolat készítése

### Compact layout
A teljes notation editor helyett strukturált form és section list. Egy szerkesztési terület egyszerre. Sticky save bar és unsaved indicator.

### Medium/expanded layout
Három panel: section/track outline, central editor/notation, property inspector. Keyboard shortcut és pointer support.

### Kötelező komponensek
- `SsListDetail`
- `SsTabViewport`
- `SsTextField`
- `SsSegmentedControl`
- `SsStickyActionBar`
- `SsToolConfirmationSheet`

### Állapotok
- clean
- dirty
- autosaving draft
- validation failure
- conflict
- source read-only
- save success/failure

### Adatkontraktus
- SongDraft
- edit history
- validation issues
- source permissions
- version

### Accessibility
- Minden drag művelethez gombos alternatíva.
- Keyboard focus jól látható.
- Undo/redo állapot felolvasott.

### Privacy és biztonság
Szerkesztett dal alapból privát. Public/community publish külön confirmation és jognyilatkozat.

### Analitika
- `song_editor_saved`

### Elfogadási feltételek
- [ ] A read-only source nem írható felül, csak másolat készíthető.
- [ ] Unsaved leave confirmation működik.
- [ ] Undo/redo determinisztikus.
- [ ] Mentési hiba nem veszíti el a draftot.

## UI-29 — Song Trainer Setup

**Route/célroute:** `/songs/:songId/train/setup`  
**UI-mód:** Learning  
**Feature owner:** Song Trainer

### Cél
Szakasz, sebesség, count-in, backing track, metronóm, scoring és loop beállítása a dal gyakorlása előtt.

### Belépési pontok
- Song Overview primary action
- Practice Result remediation
- Setlist song action

### Elsődleges művelet
- **Trainer indítása**

### Másodlagos műveletek
- Tuner
- Loop kiválasztása
- Backing track mix
- Scoring mód
- Practice preset

### Compact layout
Song/section summary, speed slider + numeric value, loop, audio mix és readiness. Advanced scoring összecsukva.

### Medium/expanded layout
Bal oldalon section/notation preview, jobb oldalon setup controls. A loop vizuálisan a preview-n is kijelölhető.

### Kötelező komponensek
- `SsTempoPicker`
- `SsLoopRange`
- `SsSwitchRow`
- `SsSlider`
- `SsPermissionState`
- `SsPrimaryButton`

### Állapotok
- ready
- asset missing
- wrong tuning
- permission required
- scoring unavailable
- degraded device mode

### Adatkontraktus
- SongTrainerConfig
- section
- tempo scale
- backing track status
- scoring capability
- tuning

### Accessibility
- Sliderhez pontos százalék input.
- Loop start/end szövegesen.
- Readiness state összefoglalva.

### Privacy és biztonság
Backing track és helyi dal asset nem kerül hálózatra.

### Analitika
- `song_trainer_setup_started`

### Elfogadási feltételek
- [ ] A speed változás nem módosítja az eredeti daladatot.
- [ ] Loop valid és legalább minimum hosszú.
- [ ] Scoring hiányában playback-only mód elérhető.
- [ ] Tuning warning egyértelmű.

## UI-30 — Song Trainer

**Route/célroute:** `/songs/:songId/train`  
**UI-mód:** Stage  
**Feature owner:** Song Trainer

### Cél
Notation/tab követés, playhead, count-in, loop, tempo és valós idejű scoring egy fókuszált játékfelületen.

### Belépési pontok
- Song Trainer Setup
- resume paused trainer

### Elsődleges művelet
- **Pause / Finish**

### Másodlagos műveletek
- Loop toggle
- Speed
- Mix
- Szakasz újra
- Feedback

### Compact layout
Landscape preferált, de portrait támogatott. Notation/tab viewport a fő terület, playhead középen vagy vezetett módon; alul transport; felül tempo/section/status. Feedback csak rövid overlay.

### Medium/expanded layout
Central notation nagy területen, jobb supporting pane-ben következő ütem és feedback; alul waveform/section navigator. Nincs primary nav.

### Kötelező komponensek
- `SsStageScaffold`
- `SsTabViewport`
- `SsNotationViewport`
- `SsPlayhead`
- `SsLoopRange`
- `SsSessionTransport`
- `SsConfidenceBadge`

### Állapotok
- count-in
- playing
- looping
- low signal
- playback-only
- paused
- seeking
- finishing
- audio failure

### Adatkontraktus
- SongPlaybackState
- SongScoreFrame
- current measure
- loop
- tempo scale
- audio sync offset

### Accessibility
- A notation vizuális tartalomhoz következő akkord/ütem szöveges summary.
- Transport keyboard shortcut expanded módban.
- Playhead motion reduced-motion mellett is követhető.

### Privacy és biztonság
On-device scoring badge. Nyers performance recording csak külön bekapcsolás esetén.

### Analitika
- `song_trainer_finished`

### Elfogadási feltételek
- [ ] Audio, playhead és scoring dokumentált tolerancián belül szinkron.
- [ ] Loop határ gap nélkül vagy dokumentált minimális gap-pel.
- [ ] Pause után pontos helyről folytat.
- [ ] Orientation change nem nulláz sessiont.
- [ ] Playback-only mód nem mutat hamis score-t.

## UI-31 — Song Result

**Route/célroute:** `/songs/:songId/result/:sessionId`  
**UI-mód:** Studio Analytics  
**Feature owner:** Song Trainer / Analysis

### Cél
Dal- és szekciószintű teljesítmény összefoglalása, nehéz részek azonosítása és célzott újragyakorlás.

### Belépési pontok
- Song Trainer finish
- Song Overview history

### Elsődleges művelet
- **Legnehezebb szakasz gyakorlása**

### Másodlagos műveletek
- Teljes dal újra
- Részletes timeline
- AI debrief
- Megosztás

### Compact layout
Overall outcome, section breakdown, top difficult section, timing/chord/rhythm metric és next action.

### Medium/expanded layout
Bal summary, középen section heatmap/timeline, jobb insight és action. Szekcióra kattintva detail.

### Kötelező komponensek
- `SsScoreRing`
- `SsHeatmap`
- `SsMetricCard`
- `SsInsightCard`
- `SsCoachActionCard`

### Állapotok
- complete
- partial
- playback-only
- low confidence
- analysis pending
- sync pending

### Adatkontraktus
- SongPracticeResult
- SectionResult
- EvidenceReference
- analysis status
- best previous

### Accessibility
- A heatmaphez section-by-section szöveges lista.
- Best previous összehasonlítás egységgel.
- Low confidence állapot kimondott.

### Privacy és biztonság
Megosztás külön preview; szerzői jog által védett notation vagy backing track nem kerül automatikusan exportba.

### Analitika
- `song_result_remediation_started`

### Elfogadási feltételek
- [ ] A top difficult section confidence alapján szűrt.
- [ ] Playback-only session nem kap pontszámot.
- [ ] A remediation loop előre kitöltött.
- [ ] Result visszakereshető a Song Overviewból.

## UI-32 — Setlist List

**Route/célroute:** `/songs/setlists`  
**UI-mód:** Learning  
**Feature owner:** Song Trainer

### Cél
Setlistek létrehozása, rendezése és próba/előadás readiness áttekintése.

### Belépési pontok
- Songs Hub
- Song Overview add to setlist
- Profile Library

### Elsődleges művelet
- **Setlist megnyitása**

### Másodlagos műveletek
- Új setlist
- Import/export metadata
- Rendezés

### Compact layout
Setlist kártyák dal- és teljes időszámmal, readiness mutatóval és legutóbbi használattal. Empty state új setlist CTA-val.

### Medium/expanded layout
Bal oldalon setlist lista, jobb oldalon kiválasztott setlist preview és readiness.

### Kötelező komponensek
- `SsListDetail`
- `SsProgressIndicator`
- `SsEmptyState`
- `SsPrimaryButton`

### Állapotok
- content
- empty
- sync pending
- missing songs
- read-only shared setlist

### Adatkontraktus
- SetlistSummary
- song count
- estimated duration
- readiness
- source/ownership

### Accessibility
- A readiness szöveges.
- Setlist drag reorderhez alternatív action.
- A dalhiány száma felolvasott.

### Privacy és biztonság
Public/shared setlist státusza jól látható; privát az alapértelmezés.

### Analitika
- `setlist_opened`

### Elfogadási feltételek
- [ ] Setlist offline működik.
- [ ] Hiányzó dal nem omlasztja össze a listát.
- [ ] Read-only shared setlist másolható.
- [ ] A sorrend determinisztikusan mentett.

## UI-33 — Setlist Detail & Run

**Route/célroute:** `/songs/setlists/:setlistId`  
**UI-mód:** Learning + Stage  
**Feature owner:** Song Trainer

### Cél
A setlist sorrendjének, tuningváltásainak, readinessének és folyamatos próba/előadás sessionjének kezelése.

### Belépési pontok
- Setlist List
- shared setlist copy
- recent setlist

### Elsődleges művelet
- **Setlist session indítása**

### Másodlagos műveletek
- Dal megnyitása
- Sorrend szerkesztése
- Tuningváltások
- Másolat
- Megosztás

### Compact layout
Detail állapotban song order, duration, tuning-change warning és readiness. Run állapotban minimal Stage list: current song, next song, transition countdown, skip/finish.

### Medium/expanded layout
Detailben list + song preview; Run módban current song central, next/notes supporting pane. Primary nav rejtett.

### Kötelező komponensek
- `SsListDetail`
- `SsProgressIndicator`
- `SsStageScaffold`
- `SsSessionTransport`
- `SsInlineMessage`

### Állapotok
- detail
- editing
- ready
- missing asset
- run active
- transition
- paused
- completed

### Adatkontraktus
- Setlist
- SetlistRunState
- song readiness
- tuning transitions
- notes

### Accessibility
- Sorrend számozva.
- Transition countdown felolvasása opcionális.
- Skip és Finish jól elkülönül.

### Privacy és biztonság
Setlist notes megosztás előtt preview-zandók; alapból privátak.

### Analitika
- `setlist_run_finished`

### Elfogadási feltételek
- [ ] A run folytatható app interruption után, ha checkpoint támogatott.
- [ ] Tuningváltás előre jelzett.
- [ ] Skip nem törli a dal progressét.
- [ ] Missing asset run előtt látható.

## UI-34 — Analyze Home

**Route/célroute:** `/practice/analyze`  
**UI-mód:** Studio Analytics  
**Feature owner:** Audio Analysis

### Cél
Új felvétel indítása, meglévő fájl kiválasztása és korábbi elemzések gyors elérése.

### Belépési pontok
- Practice Hub
- legacy `/analyze` redirect
- Coach analyze action

### Elsődleges művelet
- **Új elemzés indítása**

### Másodlagos műveletek
- Audiofájl kiválasztása
- Legutóbbi elemzés
- Elemzési módok
- Adatvédelmi részletek

### Compact layout
Kiemelt record card, file import secondary, recent analyses és rövid magyarázat arról, mit mér az app. Nincs hamis real-time ígéret.

### Medium/expanded layout
Bal oldalon input módok, középen recent analysis, jobb oldalon capability és privacy summary.

### Kötelező komponensek
- `SsPrimaryButton`
- `SsSectionHeader`
- `SsPrivacyAudiencePicker`
- `SsListDetail`
- `SsEmptyState`

### Állapotok
- ready
- permission required
- no previous analyses
- unsupported file capability
- storage low

### Adatkontraktus
- AnalysisModeCatalog
- recent analyses
- permission
- storage capacity
- device capability

### Accessibility
- A record és file import külön, egyértelmű címke.
- A mérhető metrikák szöveges listája.
- Storage warning nem csak színnel.

### Privacy és biztonság
Az audio alapból helyi. Nyers felvétel megtartása külön beállítás, nem implicit.

### Analitika
- `analyze_input_mode_selected`

### Elfogadási feltételek
- [ ] A felhasználó tudja, mentődik-e nyers audio.
- [ ] Account nélkül használható.
- [ ] A file import támogatott formátumokat mutat.
- [ ] Alacsony tárhely esetén nincs veszélyes recording indítás.

## UI-35 — Analysis Recording & Input

**Route/célroute:** `/practice/analyze/record`  
**UI-mód:** Stage  
**Feature owner:** Audio Analysis

### Cél
Kontrollált audiofelvétel vagy fájl-előkészítés jelminőség-, idő- és tárhelyvisszajelzéssel.

### Belépési pontok
- Analyze Home record
- Practice/Coach action requiring analysis

### Elsődleges művelet
- **Felvétel indítása / leállítása**

### Másodlagos műveletek
- Input beállítás
- Jelteszt
- Felvétel elvetése

### Compact layout
StageScaffold: recording indicator, elapsed, waveform/level, signal quality, storage estimate és stop. Az elemzés még nem jelenít score-t.

### Medium/expanded layout
Waveform és level central, jobb oldalon input metadata és signal checks. Nincs szerkesztés recording közben.

### Kötelező komponensek
- `SsStageScaffold`
- `SsWaveform`
- `SsSignalQualityIndicator`
- `SsSessionTransport`
- `SsInlineMessage`

### Állapotok
- ready
- permission required
- count-in
- recording
- silence
- clipping
- storage low
- stopping
- saved
- failure

### Adatkontraktus
- RecordingState
- input format
- signal metrics
- elapsed
- estimated size
- audio file reference

### Accessibility
- Recording state assertive, de nem ismétlődő.
- Waveformhoz level summary.
- Stop mindig elérhető.

### Privacy és biztonság
Nyers audio retention döntés látható; diagnosztikai feltöltés nem része ennek a képernyőnek.

### Analitika
- `analysis_recording_completed`

### Elfogadási feltételek
- [ ] Microphone indicator állandó.
- [ ] Clipping és silence külön jelzett.
- [ ] Stop után a file atomikusan lezárt.
- [ ] Hiba után temp file takarított.
- [ ] Background esetén kontrollált stop/checkpoint.

## UI-36 — Analysis Processing

**Route/célroute:** `/practice/analyze/:analysisId/processing`  
**UI-mód:** System  
**Feature owner:** Audio Analysis

### Cél
A többlépcsős helyi elemzés valós progressét, megszakíthatóságát és erőforrásállapotát mutatja.

### Belépési pontok
- Recording saved
- audio file selected
- reprocess action

### Elsődleges művelet
- **Háttérben folytatás vagy Megszakítás, a platform támogatása szerint**

### Másodlagos műveletek
- Részletek
- Eredeti felvétel megtartása
- Battery saver mód

### Compact layout
Lépésnév, determinate/indeterminate progress, rövid magyarázat, thermal/battery degraded jelzés és cancel. Nem használ hamis százalékot.

### Medium/expanded layout
Bal summary, jobb oldalon stage-by-stage log user-friendly formában. Lab buildben részletes benchmark.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsDegradedModeBanner`
- `SsInlineMessage`
- `SsSecondaryButton`

### Állapotok
- queued
- decoding
- feature extraction
- inference
- post-processing
- saving
- paused by system
- cancelled
- failure
- complete

### Adatkontraktus
- AnalysisJobState
- stage progress
- thermal status
- battery status
- checkpoint
- estimated remaining only if reliable

### Accessibility
- Progress frissítés ritkított live region.
- Cancel következménye világos.
- A stage-ek ordered listként olvashatók.

### Privacy és biztonság
Az elemzés helyi státusza badge-dzsel jelzett. Cloud feldolgozás nincs implicit fallbackként.

### Analitika
- `analysis_processing_outcome`

### Elfogadási feltételek
- [ ] A progress nem lép vissza indokolatlanul.
- [ ] Cancel idempotens.
- [ ] Thermal degrade megőrzi az adatintegritást.
- [ ] App újraindítás után checkpointból folytat vagy egyértelműen újrakezdhető.

## UI-37 — Analysis Overview

**Route/célroute:** `/library/analysis/:analysisId`  
**UI-mód:** Studio Analytics  
**Feature owner:** Audio Analysis

### Cél
Summary-first elemzési eredmény timing-, rhythm-, dynamics-, pitch/chord- és signal-quality dimenziókkal.

### Belépési pontok
- Analysis Processing complete
- Unified Library
- Practice/Song result deep link

### Elsődleges művelet
- **Legfontosabb hibás szakasz gyakorlása**

### Másodlagos műveletek
- Timeline
- Metric részletek
- Összehasonlítás
- AI debrief
- Megosztás

### Compact layout
Overall outcome, signal-quality banner, 4–5 metric card, one key insight és primary action. Low-confidence metric halványítás helyett explicit badge.

### Medium/expanded layout
Bal summary, középen metric grid, jobb insight/evidence. Timeline preview alul vagy külön route.

### Kötelező komponensek
- `SsScoreRing`
- `SsMetricCard`
- `SsInsightCard`
- `SsConfidenceLegend`
- `SsSignalQualityIndicator`
- `SsCoachActionCard`

### Állapotok
- complete
- partial metrics
- low signal
- unsupported metric
- enhancement pending
- corrupt analysis

### Adatkontraktus
- AnalysisResultV2
- MetricResult
- SignalQualityReport
- EvidenceReference
- AnalysisVersion

### Accessibility
- Metric kártyák label + value + trend + confidence.
- Grafikonokhoz summary.
- Overall score hiányában nem mutat 0-t.

### Privacy és biztonság
A raw audio retention és local processing státusz info sheetből elérhető.

### Analitika
- `analysis_overview_action`

### Elfogadási feltételek
- [ ] A signal quality minden következtetés előtt látható.
- [ ] Hiányzó metric „not available”, nem 0.
- [ ] A key insight evidence linkkel rendelkezik.
- [ ] A result verziója és dátuma elérhető.

## UI-38 — Analysis Timeline

**Route/célroute:** `/library/analysis/:analysisId/timeline`  
**UI-mód:** Studio Analytics  
**Feature owner:** Audio Analysis

### Cél
Időalapú hibák, beat/tempo, chord/pitch, dynamics és confidence vizsgálata zoomolható, szűrhető timeline-on.

### Belépési pontok
- Analysis Overview
- Song Result
- Practice Result

### Elsődleges művelet
- **Kijelölt szakasz loop gyakorlása**

### Másodlagos műveletek
- Metric overlay
- Lejátszás
- Zoom
- Marker
- Export snippet summary

### Compact layout
Felső transport, középen egy fő timeline sáv és kiválasztható metric tabok; részlet bottom sheetben. Nem jelenik meg egyszerre minden overlay.

### Medium/expanded layout
Többsávos timeline, bal legend, jobb event inspector. Cursor/playhead és selection szinkron.

### Kötelező komponensek
- `SsTimeline`
- `SsWaveform`
- `SsPlayhead`
- `SsLoopRange`
- `SsConfidenceLegend`
- `SsSessionTransport`

### Állapotok
- ready
- audio unavailable
- metric unavailable
- selection active
- playing
- loading detail
- large file virtualized

### Adatkontraktus
- AnalysisTimeline
- TimelineEvent
- audio reference
- metric overlays
- selection
- confidence

### Accessibility
- Idővonalhoz eseménylista alternatíva.
- Zoom gombok és keyboard shortcut.
- Selection start/end szöveges.

### Privacy és biztonság
Audio lejátszás helyi. Export csak strukturált summaryt ad alapból, nem nyers hangot.

### Analitika
- `analysis_timeline_selection_practiced`

### Elfogadási feltételek
- [ ] Nagy timeline virtualizált.
- [ ] Playhead és audio szinkron.
- [ ] Metric overlay kikapcsolható.
- [ ] Selection loop közvetlen Practice/Song konfigurációt hoz létre.
- [ ] System back gesture nem ütközik a pan gesture-rel.

## UI-39 — Metric Detail & Session Compare

**Route/célroute:** `/progress/metric/:metricId`  
**UI-mód:** Studio Analytics  
**Feature owner:** Progress / Audio Analysis

### Cél
Egy készség vagy metric definíciójának, trendjének, evidence-ének és kompatibilis session-összehasonlításának bemutatása.

### Belépési pontok
- Analysis Overview metric
- Progress Dashboard
- Skill Detail

### Elsődleges művelet
- **Kapcsolódó gyakorlat indítása**

### Másodlagos műveletek
- Időtáv
- Sessionök kiválasztása
- Definíció
- Export

### Compact layout
Metric definition, current range, trend chart, best/recent, evidence list. Compare legfeljebb 2–3 sessionnel.

### Medium/expanded layout
Bal filter/időtáv, középen chart, jobb session inspector és recommended action.

### Kötelező komponensek
- `SsComparisonChart`
- `SsTrendChip`
- `SsMetricCard`
- `SsInsightCard`
- `SsChoiceChip`

### Állapotok
- insufficient data
- trend available
- compare active
- incompatible sessions
- low confidence
- offline

### Adatkontraktus
- MetricDefinition
- MetricSeries
- ComparableSession
- confidence
- normalization version

### Accessibility
- Chart summary és adatpontlista.
- Trend iránya szöveges.
- Session selection checkbox semantics.

### Privacy és biztonság
Exportban pseudonymous/local azonosítók; public megosztás külön flow.

### Analitika
- `metric_detail_practice_started`

### Elfogadási feltételek
- [ ] Trend csak minimum adatpont után.
- [ ] Eltérő metric version nem összehasonlítható figyelmeztetés nélkül.
- [ ] Hiányzó adat nem null.
- [ ] A recommended action metrichez kötött.

## UI-40 — Unified Library

**Route/célroute:** `/profile/library`  
**UI-mód:** Studio  
**Feature owner:** Library

### Cél
Sessionök, elemzések, dalok, tervek, exportok és mentett tartalmak egységes, típusbiztos könyvtára.

### Belépési pontok
- Profile Hub
- legacy `/library` redirect
- Analyze/Song/Practice history

### Elsődleges művelet
- **Elem megnyitása**

### Másodlagos műveletek
- Keresés
- Típusfilter
- Rendezés
- Import
- Storage kezelése

### Compact layout
Search + type chips, recent items, dátum szerinti lista. Itemenként type icon, title, timestamp, local/cloud/sync state.

### Medium/expanded layout
Bal filter és kategória, középen item list, jobb preview. Storage usage supporting panel.

### Kötelező komponensek
- `SsSearchField`
- `SsChoiceChip`
- `SsListDetail`
- `SsSyncPendingBadge`
- `SsOfflineBanner`
- `SsEmptyState`

### Állapotok
- content
- empty
- filtered empty
- offline
- sync pending
- corrupt item isolated
- storage near limit

### Adatkontraktus
- LibraryItem union
- filters
- storage usage
- sync status
- pagination

### Accessibility
- Item type szöveges.
- Preview nem zavarja a listafókuszt.
- Storage usage számszerű.

### Privacy és biztonság
Cloud és local példány státusza jól látható. Storage management megmutatja, mi törlődik és mi marad cloudban.

### Analitika
- `library_item_opened`

### Elfogadási feltételek
- [ ] Eltérő item típusok route-ja típusbiztos.
- [ ] Corrupt item izolált.
- [ ] Offline local tartalom megnyitható.
- [ ] Törlés nem történik swipe véletlennel confirmation nélkül.

## UI-41 — Session Detail

**Route/célroute:** `/profile/library/session/:sessionId`  
**UI-mód:** Studio Analytics  
**Feature owner:** Library / Practice / Analysis

### Cél
Egy mentett session metadata, result, notes, source és elérhető műveletek egységes bemutatása.

### Belépési pontok
- Unified Library
- Practice History
- Song Overview history

### Elsődleges művelet
- **Session eredmény megnyitása vagy újragyakorlás**

### Másodlagos műveletek
- Átnevezés
- Jegyzet
- Export
- Törlés
- Compare

### Compact layout
Session title, date/duration/type, summary, notes, source és action list. Destruktív törlés alul külön szekció.

### Medium/expanded layout
Bal metadata és action, középen result preview, jobb notes/provenance.

### Kötelező komponensek
- `SsMetricCard`
- `SsInlineMessage`
- `SsToolConfirmationSheet`
- `SsSyncPendingBadge`
- `SsSectionHeader`

### Állapotok
- ready
- raw audio missing
- analysis pending
- sync conflict
- corrupt metadata
- delete pending

### Adatkontraktus
- SessionRecord
- result reference
- raw asset status
- notes
- sync version

### Accessibility
- Metadata definition list.
- Törlés pontos tárgyat nevez meg.
- Notes field label és character count.

### Privacy és biztonság
Export és törlés külön megerősítés. Nyers audio státusz és retention látható.

### Analitika
- `session_detail_action`

### Elfogadási feltételek
- [ ] Átnevezés nem változtat az ID-n.
- [ ] Törlés dependencyt és cloud következményt felsorol.
- [ ] Missing raw audio mellett result megmarad.
- [ ] Compare csak kompatibilis sessionnel.

## UI-42 — Coach Home

**Route/célroute:** `/coach`  
**UI-mód:** Coach  
**Feature owner:** AI Guitar Teacher

### Cél
Az AI Tutor, practice plan, debrief, Vision Coach és offline AI egyértelmű, provenance-aware kezdőfelülete.

### Belépési pontok
- primary navigation Coach tab
- Today insight
- Practice/Song result action

### Elsődleges művelet
- **AI tanár megnyitása vagy legfontosabb coach action**

### Másodlagos műveletek
- Mai terv
- Utolsó debrief
- Vision Coach
- Offline AI modellek
- Korábbi beszélgetések

### Compact layout
Kiemelt coach recommendation, rövid mode badge, quick actions és recent advice. Nem chat feedként indul.

### Medium/expanded layout
Bal oldali coach navigation, középen recommendation/conversation preview, jobb oldalon learner context és model status.

### Kötelező komponensek
- `SsCoachActionCard`
- `SsAiModeBadge`
- `SsModelStatusCard`
- `SsInsightCard`
- `SsAdaptiveScaffold`

### Állapotok
- local AI ready
- cloud AI ready
- deterministic fallback
- model missing
- offline
- no learner evidence
- error

### Adatkontraktus
- TutorCapability
- CoachRecommendation
- LearnerContextSummary
- recent conversations
- model status

### Accessibility
- AI mode badge felolvasva.
- Recommendation action konkrét.
- A model hiba nem blokkolja a deterministic segítséget.

### Privacy és biztonság
A cloud mód előtt adatkezelési státusz elérhető; conversation history törölhető.

### Analitika
- `coach_home_action`

### Elfogadási feltételek
- [ ] A felhasználó mindig látja, milyen AI mód válaszol.
- [ ] Account nélkül legalább deterministic/local funkció elérhető.
- [ ] A recommendation evidence-re hivatkozik.
- [ ] Nincs automatikus microphone/camera indítás.

## UI-43 — Tutor Conversation

**Route/célroute:** `/coach/tutor/:conversationId?`  
**UI-mód:** Coach  
**Feature owner:** AI Guitar Teacher

### Cél
Rövid, gitárspecifikus, evidence-alapú beszélgetés, végrehajtható action cardokkal és biztonságos tool confirmationnel.

### Belépési pontok
- Coach Home
- Practice/Song/Analysis result
- Chord Detail
- Vision Result

### Elsődleges művelet
- **Üzenet küldése vagy javasolt action végrehajtása**

### Másodlagos műveletek
- Voice input, ha külön engedélyezett
- Evidence megnyitása
- Mode váltás
- Beszélgetés törlése

### Compact layout
Message list, sticky composer, AI mode header. AI válasz három része: observation, possible cause, next action. Action card külön a prose-tól.

### Medium/expanded layout
Bal conversation list, középen chat, jobb evidence/context panel. Tool confirmation side sheet.

### Kötelező komponensek
- `SsStreamingMessage`
- `SsAiModeBadge`
- `SsEvidenceCard`
- `SsCoachActionCard`
- `SsToolConfirmationSheet`
- `SsTextField`

### Állapotok
- new
- streaming
- cancelled
- local
- cloud
- fallback
- tool confirmation
- tool result
- offline
- failure

### Adatkontraktus
- TutorMessage
- TutorEvidence
- TutorAction
- TutorMode
- conversation memory policy

### Accessibility
- Streaming text nem olvasódik tokenenként; kész bekezdésenként update.
- Composer tartós label.
- Action card billentyűzettel elérhető.

### Privacy és biztonság
A chat tartalma nem kerül analyticsbe. Cloud küldés előtt a context minimizált és a mód látható.

### Analitika
- `tutor_action_confirmed`

### Elfogadási feltételek
- [ ] Prompt injectionből származó tool action nem fut automatikusan.
- [ ] A felhasználó megszakíthatja a streaminget.
- [ ] Evidence hiányában a válasz ezt kimondja.
- [ ] Local/cloud provenance minden válasznál vagy session headerben egyértelmű.
- [ ] Destruktív/public action confirmationt kér.

## UI-44 — Session Debrief & Plan Preview

**Route/célroute:** `/coach/debrief/:sessionId`  
**UI-mód:** Coach + Studio Analytics  
**Feature owner:** AI Guitar Teacher / Practice Generator

### Cél
Egy session evidence-ének emberi magyarázata és a javasolt következő gyakorlat vagy tervmódosítás előnézete.

### Belépési pontok
- Practice Result
- Song Result
- Analysis Overview
- Coach Home recent debrief

### Elsődleges művelet
- **Javasolt gyakorlat indítása vagy tervmódosítás elfogadása**

### Másodlagos műveletek
- Evidence
- Másik javaslat
- Terv változásainak összehasonlítása
- Elutasítás oka

### Compact layout
Debrief summary, 1–3 evidence card, next action, plan diff. A hosszú AI magyarázat összecsukható.

### Medium/expanded layout
Bal result/evidence, középen debrief, jobb plan diff és action. A plan módosítás nem automatikus.

### Kötelező komponensek
- `SsEvidenceCard`
- `SsInsightCard`
- `SsCoachActionCard`
- `SsAiModeBadge`
- `SsToolConfirmationSheet`

### Állapotok
- generating
- ready
- low evidence
- fallback
- plan diff available
- accepted
- rejected
- failure

### Adatkontraktus
- SessionDebrief
- EvidenceReference
- PlanChangeProposal
- TutorMode
- confidence

### Accessibility
- Evidence és következtetés külön heading.
- Plan diff hozzáadás/eltávolítás szöveges.
- Accept/reject nem csak ikon.

### Privacy és biztonság
Csak a szükséges strukturált session evidence kerül AI contextbe; raw audio nem implicit.

### Analitika
- `debrief_plan_decision`

### Elfogadási feltételek
- [ ] A debrief nem állít többet az evidence-nél.
- [ ] Plan change explicit elfogadás nélkül nem ír.
- [ ] Elutasítás nem büntet.
- [ ] Fallback módban is adható biztonságos következő lépés.

## UI-45 — Vision Setup & Calibration

**Route/célroute:** `/coach/vision/setup`  
**UI-mód:** Coach  
**Feature owner:** Computer Vision

### Cél
Kameraengedély, telefonelhelyezés, megvilágítás, gitár/kezek láthatósága és koordinátakalibráció biztonságos beállítása.

### Belépési pontok
- Coach Home Vision
- Practice Setup Vision toggle
- Lesson technique step

### Elsődleges művelet
- **Kalibráció indítása**

### Másodlagos műveletek
- Kamera váltás
- Elhelyezési útmutató
- Vision kihagyása
- Privacy részletek

### Compact layout
Permission primer, álló/landscape setup illustration, live preview csak engedély után, calibration frame és readiness checklist.

### Medium/expanded layout
Bal live preview, jobb lépéslista és quality metrics. Foldable stand mode külön layout.

### Kötelező komponensek
- `SsPermissionState`
- `SsCalibrationFrame`
- `SsSignalQualityIndicator`
- `SsPrimaryButton`
- `SsInlineMessage`

### Állapotok
- permission not requested
- denied
- permanently denied
- preview
- poor lighting
- guitar not visible
- hands not visible
- calibrating
- ready
- unsupported device

### Adatkontraktus
- CameraPermissionState
- VisionCapability
- CalibrationQuality
- camera selection
- orientation

### Accessibility
- A vizuális elhelyezéshez szöveges és hangos útmutató.
- Readiness checklist felolvasott.
- Kamera preview nem az egyetlen információ.

### Privacy és biztonság
Alapértelmezésként frame nem mentődik és nem hagyja el az eszközt. Ezt a képernyő egyértelműen közli.

### Analitika
- `vision_calibration_completed`

### Elfogadási feltételek
- [ ] Camera csak explicit action után indul.
- [ ] Unsupported eszközön alternatív audio-only flow.
- [ ] Kalibráció validity tárolható, de új setupnál ellenőrzött.
- [ ] Route leave felszabadítja a kamerát.

## UI-46 — Vision Coach

**Route/célroute:** `/coach/vision/session/:sessionId`  
**UI-mód:** Stage + Coach  
**Feature owner:** Computer Vision

### Cél
Élő technikai coaching egyetlen prioritásos cue-val, visszafogott overlay-jel és opcionális audio–vision szinkronnal.

### Belépési pontok
- Vision Setup ready
- Practice Session with Vision
- Lesson technique step

### Elsődleges művelet
- **Pause / Finish**

### Másodlagos műveletek
- Cue elrejtése
- Példa megtekintése
- Overlay részletesség
- Audio-only mód

### Compact layout
Live preview nagy területen, egyetlen kiemelt body/hand region, alul rövid technique cue és transport. Teljes skeleton alapból rejtett.

### Medium/expanded layout
Preview central, jobb oldalon current cue, confidence és improvement; debug skeleton csak Lab módban.

### Kötelező komponensek
- `SsStageScaffold`
- `SsVisionOverlay`
- `SsTechniqueCue`
- `SsSignalQualityIndicator`
- `SsSessionTransport`
- `SsConfidenceBadge`

### Állapotok
- count-in
- tracking
- low light
- occlusion
- lost tracking
- thermal degrade
- audio-only fallback
- paused
- finishing

### Adatkontraktus
- VisionFrameResult
- TechniqueCue
- TrackingQuality
- thermal state
- audio sync status

### Accessibility
- Technique cue text + opcionális hang/haptika.
- Overlay színe mellett shape és label.
- Preview dekoratív semantics, cue a fő információ.

### Privacy és biztonság
Állandó camera/mic badge. Frame mentés nincs, kivéve külön, explicit diagnostics consent.

### Analitika
- `vision_session_finished`

### Elfogadási feltételek
- [ ] Egyszerre legfeljebb egy prioritásos cue.
- [ ] Low confidence cue nem kategorikus.
- [ ] Thermal degrade csökkenti FPS-t, nem omlaszt.
- [ ] Kamera és mikrofon ownership kontrollált.
- [ ] Debug overlay productionben nem elérhető.

## UI-47 — Vision Result

**Route/célroute:** `/coach/vision/result/:sessionId`  
**UI-mód:** Studio Analytics + Coach  
**Feature owner:** Computer Vision

### Cél
Technikai megfigyelések, javulás és konkrét korrekció összefoglalása confidence és frame-mentés nélküli evidence mellett.

### Belépési pontok
- Vision Coach finish
- Practice Result vision section

### Elsődleges művelet
- **Javítógyakorlat indítása**

### Másodlagos műveletek
- Cue részletek
- Újrakalibrálás
- AI debrief
- Adatkezelés megtekintése

### Compact layout
Session quality, 1–3 technique metric, fő cue, improvement trend és action. Nem mutat ítélkező „rossz tartás” címkét.

### Medium/expanded layout
Bal quality/metric, középen cue timeline schematic, jobb remediation.

### Kötelező komponensek
- `SsMetricCard`
- `SsInsightCard`
- `SsConfidenceLegend`
- `SsCoachActionCard`
- `SsSignalQualityIndicator`

### Állapotok
- complete
- partial
- low tracking quality
- audio-only segment
- insufficient evidence
- analysis pending

### Adatkontraktus
- VisionSessionResult
- TechniqueMetric
- TrackingQualitySummary
- EvidenceReference
- calibration version

### Accessibility
- Minden technique metric text summary.
- Nincs kizárólag vizuális skeleton evidence.
- Action konkrét lépéssel.

### Privacy és biztonság
A képernyő jelzi, hogy frame nem került tárolásra; ha diagnostics történt, külön audit trail.

### Analitika
- `vision_result_remediation_started`

### Elfogadási feltételek
- [ ] A result külön kezeli a tracking qualityt és technique score-t.
- [ ] Insufficient evidence nem jelenít score-t.
- [ ] Remediation a megfelelő technique practice-t nyitja.
- [ ] Frame hiánya mellett is auditálható strukturált evidence.

## UI-48 — Offline AI Model Manager

**Route/célroute:** `/profile/settings/offline-ai`  
**UI-mód:** System + Coach  
**Feature owner:** Offline AI

### Cél
Helyi modellek kompatibilitásának, méretének, letöltésének, aktiválásának, rollbackjének és tárhelyének kezelése.

### Belépési pontok
- Coach Home model status
- Settings
- model missing state

### Elsődleges művelet
- **Ajánlott modell letöltése vagy aktiválása**

### Másodlagos műveletek
- Részletek
- Szüneteltetés
- Folytatás
- Törlés
- Rollback
- Wi‑Fi only

### Compact layout
Device capability summary, recommended model card, installed/download list, storage usage és local privacy magyarázat.

### Medium/expanded layout
Bal model list, középen selected model details/benchmark, jobb storage és download policy.

### Kötelező komponensek
- `SsModelStatusCard`
- `SsProgressIndicator`
- `SsOfflineBanner`
- `SsToolConfirmationSheet`
- `SsSwitchRow`

### Állapotok
- no model
- compatible model available
- downloading
- paused
- verifying
- activating
- active
- rollback available
- incompatible
- low storage
- failure

### Adatkontraktus
- ModelManifest
- ModelInstallState
- DeviceCapability
- download policy
- signature/checksum status

### Accessibility
- Download progress és méret felolvasva.
- Model tier magyarázott, nem csak számozott.
- Törlés pontos storage következményt ad.

### Privacy és biztonság
A local AI egyértelműen on-device. Model download nem tartalmaz felhasználói adatot.

### Analitika
- `offline_model_action`

### Elfogadási feltételek
- [ ] Aláírás/checksum nélkül modell nem aktiválható.
- [ ] Letöltés folytatható.
- [ ] Aktív modell törlése confirmationt kér és fallbacket biztosít.
- [ ] Gyenge eszközre nem ajánl túl nagy modellt.
- [ ] Mobilnet policy tiszteletben tartott.

## UI-49 — Progress Dashboard

**Route/célroute:** `/profile/progress`  
**UI-mód:** Studio Analytics  
**Feature owner:** Progress

### Cél
A tanuló hosszú távú fejlődésének egyszerű, nem manipuláló összefoglalása skill, idő, consistency és goal dimenziókban.

### Belépési pontok
- Profile Hub
- Today progress card
- Practice History

### Elsődleges művelet
- **Kiemelt skill részleteinek megnyitása**

### Másodlagos műveletek
- Időtáv
- Cél módosítása
- Session history
- Export

### Compact layout
Heti/monthly summary, practice time, consistency, top improving skill, focus area és skill grid. Nincs túlzott dashboard-sűrűség.

### Medium/expanded layout
Bal timeframe/filter, középen trends és skill grid, jobb goal/insight panel.

### Kötelező komponensek
- `SsMetricCard`
- `SsComparisonChart`
- `SsTrendChip`
- `SsInsightCard`
- `SsChoiceChip`

### Állapotok
- new user/insufficient data
- trend available
- offline
- sync pending
- metric version migration

### Adatkontraktus
- ProgressSummary
- SkillProgress
- PracticeTimeSeries
- GoalProgress
- metric versions

### Accessibility
- Chart summary és skill lista.
- Trend irány + mérték szöveges.
- Időtávváltás billentyűzettel.

### Privacy és biztonság
A progress alapból privát. Community megosztás külön aggregált snapshotból történik.

### Analitika
- `progress_skill_opened`

### Elfogadási feltételek
- [ ] Új usernél értelmes empty state.
- [ ] Practice time és quality nem keveredik egy score-ba magyarázat nélkül.
- [ ] Metric migration nem törli a korábbi adatot.
- [ ] Offline adatok teljesen láthatók.

## UI-50 — Skill Detail

**Route/célroute:** `/profile/progress/skills/:skillId`  
**UI-mód:** Studio Analytics + Learning  
**Feature owner:** Progress / Learn

### Cél
Egy készség mastery állapotának, bizonyítékainak, prerequisite-jeinek, trendjének és következő gyakorlásának bemutatása.

### Belépési pontok
- Progress Dashboard
- Learning Path
- Tutor debrief

### Elsődleges művelet
- **Ajánlott skill gyakorlat indítása**

### Másodlagos műveletek
- Evidence session
- Prerequisite
- Időtáv
- AI magyarázat

### Compact layout
Skill cím és mastery level, trend, evidence count, prerequisite map simplified, top next action.

### Medium/expanded layout
Bal skill graph, középen trend/evidence, jobb recommended lessons/practices.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsComparisonChart`
- `SsEvidenceCard`
- `SsCoachActionCard`
- `SsAiModeBadge`

### Állapotok
- unstarted
- developing
- stable
- mastered
- stale evidence
- insufficient evidence
- version migrated

### Adatkontraktus
- SkillDefinition
- SkillMastery
- SkillEvidence
- prerequisites
- recommended actions

### Accessibility
- Skill graph lineáris prerequisite listként.
- Mastery szóval és definícióval.
- Evidence date és source felolvasott.

### Privacy és biztonság
A skill evidence részletes sessionadatot nem tesz publická.

### Analitika
- `skill_detail_practice_started`

### Elfogadási feltételek
- [ ] Mastery nem kizárólag XP-ből származik.
- [ ] Evidence link visszavezet a sessionhöz.
- [ ] Stale evidence jelzett.
- [ ] Ajánlás dependencyt tiszteletben tart.

## UI-51 — Gamification Hub & Streak

**Route/célroute:** `/profile/rewards`  
**UI-mód:** Learning  
**Feature owner:** Gamification

### Cél
XP, level, streak, napi/ heti quest és jutalmak áttekintése úgy, hogy a rendszer támogassa, ne büntesse a gyakorlást.

### Belépési pontok
- Profile Hub
- Today streak card
- reward notification

### Elsődleges művelet
- **Aktuális quest folytatása**

### Másodlagos műveletek
- Streak részletek
- Achievementek
- Reward inbox
- Szabályok

### Compact layout
Level/XP summary, compassionate streak card, active quests és recent rewards. A streak megszakadása nem veszélyjelzés.

### Medium/expanded layout
Bal progression, középen quests/rewards, jobb streak calendar és szabálymagyarázat.

### Kötelező komponensek
- `SsProgressIndicator`
- `SsChallengeCard`
- `SsInlineMessage`
- `SsSectionHeader`
- `SsCoachActionCard`

### Állapotok
- new user
- active streak
- rest day protected
- streak paused
- streak ended
- reward pending
- offline ledger

### Adatkontraktus
- GamificationProfile
- StreakState
- QuestList
- RewardInbox
- ledger sync status

### Accessibility
- XP progress számszerű.
- Calendarhoz dátumlista.
- Reward animáció reduced-motion aware.

### Privacy és biztonság
A reward és streak alapból privát; leaderboard opt-in külön.

### Analitika
- `gamification_quest_opened`

### Elfogadási feltételek
- [ ] A streak nyelvezet nem fenyegető.
- [ ] Offline reward idempotens ledgerből jön.
- [ ] Rest day és grace szabály elérhető.
- [ ] Nincs pay-to-preserve dark pattern.

## UI-52 — Achievements, Quests & Reward Inbox

**Route/célroute:** `/profile/rewards/details`  
**UI-mód:** Learning  
**Feature owner:** Gamification

### Cél
Teljesített és folyamatban lévő achievementek, questek, claimelhető jutalmak és azok auditálható forrásának kezelése.

### Belépési pontok
- Gamification Hub
- reward deep link
- Profile achievement preview

### Elsődleges művelet
- **Jutalom átvétele vagy quest folytatása**

### Másodlagos műveletek
- Kategória
- Completed filter
- Achievement részletek
- Reward history

### Compact layout
Tabok: Quests, Achievements, Inbox. Kártyán progress, feltétel, expiry csak valódi esetben és claim state.

### Medium/expanded layout
Bal kategória/filter, középen lista, jobb selected detail és ledger source.

### Kötelező komponensek
- `SsChallengeCard`
- `SsProgressIndicator`
- `SsEmptyState`
- `SsToolConfirmationSheet`
- `SsTrendChip`

### Állapotok
- active
- completed
- claimable
- claimed
- expired
- offline pending
- integrity review

### Adatkontraktus
- Quest
- Achievement
- RewardEntry
- RewardLedgerReference
- expiry

### Accessibility
- Progress feltétel szöveges.
- Claim state explicit.
- Expiry dátum locale-aware.

### Privacy és biztonság
Leaderboard/public badge share külön opt-in; reward history nem public.

### Analitika
- `reward_claimed`

### Elfogadási feltételek
- [ ] Claim idempotens.
- [ ] Offline claim duplikációt nem okoz.
- [ ] Az achievement feltétel érthető.
- [ ] Integrity review nem vádolja a felhasználót, csak státuszt közöl.

## UI-53 — Community Gate & Public Profile Setup

**Route/célroute:** `/profile/community/setup`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
A community opcionális aktiválása, public név, avatar, bio, visibility és safety alapbeállításokkal.

### Belépési pontok
- Profile Hub community card
- Community Feed first open
- shared link action

### Elsődleges művelet
- **Community profil létrehozása**

### Másodlagos műveletek
- Most nem
- Audience magyarázat
- Biztonsági beállítások

### Compact layout
Opcionális feature magyarázat, public/local profil különbség, handle mező, display name, avatar optional, default private/friends visibility.

### Medium/expanded layout
Bal preview, jobb setup form és privacy summary. Moderation/safety alapelvek külön panel.

### Kötelező komponensek
- `SsProfileHeader`
- `SsTextField`
- `SsPrivacyAudiencePicker`
- `SsPrimaryButton`
- `SsInlineMessage`

### Állapotok
- not enabled
- checking handle
- validation failure
- creating
- created
- network unavailable

### Adatkontraktus
- CommunityProfileDraft
- handle availability
- visibility
- consent version
- age/safety policy eligibility

### Accessibility
- Avatar crop alternatív skip.
- Handle hiba konkrét.
- Audience választás magyarázott.

### Privacy és biztonság
Local learner profile nem másolódik automatikusan public profilba. Bio és avatar opcionális.

### Analitika
- `community_profile_created`

### Elfogadási feltételek
- [ ] Core app használható community nélkül.
- [ ] Default visibility nem public.
- [ ] Handle check debounce és offline esetén nem hamis siker.
- [ ] Consent version mentett.
- [ ] Public preview mentés előtt látható.

## UI-54 — Community Feed

**Route/célroute:** `/community`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
Biztonságos, követett és releváns gitáros tartalom feedje, offline cache-sel és világos audience/source jelöléssel.

### Belépési pontok
- Profile community
- community notification
- public profile

### Elsődleges művelet
- **Poszt megnyitása vagy kapcsolódó challenge/practice action**

### Másodlagos műveletek
- Új poszt
- Feed filter
- Keresés
- Report/Hide

### Compact layout
Feed kártyák véges batch-ben; szerző, audience/context, text/media preview, reactions. Nincs agresszív infinite engagement design.

### Medium/expanded layout
Bal filter/navigation, középen feed, jobb selected post/detail vagy recommendations. Auto-play alapból kikapcsolt.

### Kötelező komponensek
- `SsPostCard`
- `SsReactionBar`
- `SsOfflineBanner`
- `SsEmptyState`
- `SsAdaptiveScaffold`

### Állapotok
- loading
- content
- empty following
- offline cached
- pagination
- content removed
- moderation limited
- failure

### Adatkontraktus
- FeedPage
- CommunityPostSummary
- audience
- moderation state
- cache timestamp

### Accessibility
- Media alt text/caption.
- Reaction count és state felolvasva.
- Load more alternatíva.
- Auto-play nem kötelező.

### Privacy és biztonság
Minden poszt audience badge-et kap. Analytics nem tartalmaz posztszöveget.

### Analitika
- `community_feed_post_opened`

### Elfogadási feltételek
- [ ] Offline cache timestamp látható.
- [ ] Removed content kontrollált placeholder.
- [ ] Block/mute hatás azonnali helyben.
- [ ] Feed nem blokkolja a core appot.
- [ ] Nincs raw practice audio auto-play.

## UI-55 — Community Search & Discovery

**Route/célroute:** `/community/search`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
Felhasználók, klubok, challenge-ek és megosztott gyakorlási tartalmak biztonságos keresése.

### Belépési pontok
- Community Feed search
- Profile community section
- challenge invite

### Elsődleges művelet
- **Találat megnyitása**

### Másodlagos műveletek
- Kategóriafilter
- Recent search törlése
- Safety filter

### Compact layout
Search field, category chips, recent searches local-only, result sections. Felhasználókeresés nem mutat érzékeny adatot.

### Medium/expanded layout
Bal filter, középen result list, jobb preview. Query megmarad route state-ben.

### Kötelező komponensek
- `SsSearchField`
- `SsChoiceChip`
- `SsListDetail`
- `SsEmptyState`
- `SsProfileHeader`

### Állapotok
- idle
- searching
- results
- no results
- offline unavailable
- rate limited
- blocked result hidden

### Adatkontraktus
- CommunitySearchResult union
- query
- filters
- pagination
- safety settings

### Accessibility
- Result type szöveges.
- Search result count.
- Recent search törlés külön.

### Privacy és biztonság
Recent search alapból helyi; törölhető. Kiskorú/safety policy szerinti discovery korlátok alkalmazandók.

### Analitika
- `community_search_result_opened`

### Elfogadási feltételek
- [ ] Minimum query/rate limit kezelt.
- [ ] Blocked user nem jelenik meg.
- [ ] Offline állapot nem mutat régi eredményt frissként.
- [ ] Query nem kerül nyers analyticsbe.

## UI-56 — Public Community Profile

**Route/célroute:** `/community/users/:userId`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
Másik gitáros public profiljának, megosztott badge-einek, posztjainak és biztonságos kapcsolatfelvételi műveleteinek bemutatása.

### Belépési pontok
- Feed author
- Search result
- Leaderboard
- Club member

### Elsődleges művelet
- **Követés / Követés megszüntetése**

### Másodlagos műveletek
- Challenge meghívás
- Mute
- Block
- Report
- Shared posts

### Compact layout
Profile header, bio, public skills/badges csak consent szerint, follow state, post list. Safety actions overflowban, de block/report könnyen elérhető.

### Medium/expanded layout
Bal profile, középen posts/achievements, jobb relationship és shared challenge context.

### Kötelező komponensek
- `SsProfileHeader`
- `SsPostCard`
- `SsModerationActionSheet`
- `SsChallengeCard`
- `SsInlineMessage`

### Állapotok
- public
- limited/private
- following
- blocked
- suspended
- not found
- offline cached

### Adatkontraktus
- PublicCommunityProfile
- relationship state
- public badges
- posts
- moderation status

### Accessibility
- Follow state egyértelmű.
- Avatar alt csak releváns.
- Block/report címkézett.

### Privacy és biztonság
Csak explicit public profilmezők és badge-ek láthatók. Practice history alapból nem public.

### Analitika
- `community_profile_follow_action`

### Elfogadási feltételek
- [ ] Private mező nem szivárog.
- [ ] Block azonnal elrejti a tartalmat.
- [ ] Suspended profil neutrális placeholder.
- [ ] Challenge csak jogosult relationship/policy esetén.

## UI-57 — Post Composer & Share Practice

**Route/célroute:** `/community/posts/new`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
Szöveg, biztonságos média, aggregált practice/result card vagy challenge update megosztása audience preview-val.

### Belépési pontok
- Feed new post
- Practice/Song/Analysis Share
- Profile

### Elsődleges művelet
- **Közzététel**

### Másodlagos műveletek
- Audience
- Practice card hozzáadása
- Média
- Draft mentése
- Mégse

### Compact layout
Composer, audience picker mindig látható, attachment preview, character count, safety/licence warning. Publish sticky, de disabled validationig.

### Medium/expanded layout
Bal composer, jobb live public preview és audience summary.

### Kötelező komponensek
- `SsTextField`
- `SsPrivacyAudiencePicker`
- `SsCoachActionCard`
- `SsToolConfirmationSheet`
- `SsProgressIndicator`

### Állapotok
- draft
- uploading attachment
- validation failure
- offline queued
- publishing
- published
- moderation hold
- failure

### Adatkontraktus
- CommunityPostDraft
- audience
- attachment metadata
- practice share snapshot
- idempotency key

### Accessibility
- Attachment alt text mező.
- Audience change bejelentett.
- Upload progress.

### Privacy és biztonság
Practice share aggregált és előnézhető; session raw data nem kerül bele automatikusan.

### Analitika
- `community_post_published`

### Elfogadási feltételek
- [ ] Audience mentés előtt látható.
- [ ] Offline publish queue idempotens.
- [ ] Szerzői jogi tartalom warning.
- [ ] Nyers audio/video csak explicit attachment.
- [ ] Publish után draft nem duplikálódik retrykor.

## UI-58 — Post Detail & Comments

**Route/célroute:** `/community/posts/:postId`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
Egy poszt teljes tartalma, reactions, comments, safety action és kapcsolódó practice/challenge megnyitása.

### Belépési pontok
- Feed
- notification
- public profile
- share link

### Elsődleges művelet
- **Komment küldése vagy kapcsolódó action**

### Másodlagos műveletek
- Reaction
- Reply
- Mute thread
- Report
- Delete own post

### Compact layout
Post teljes kártya, reaction bar, comment list, sticky composer. Nested reply vizuálisan maximum egy szint, további thread külön.

### Medium/expanded layout
Középen post/comments, jobb post context és moderation/action panel.

### Kötelező komponensek
- `SsPostCard`
- `SsReactionBar`
- `SsCommentComposer`
- `SsModerationActionSheet`
- `SsOfflineBanner`

### Állapotok
- content
- comments loading
- offline cached
- comment queued
- removed comment
- thread locked
- moderation hold

### Adatkontraktus
- CommunityPost
- CommentPage
- reaction state
- thread state
- permissions

### Accessibility
- Comment hierarchy felolvasva.
- Reaction toggle state.
- Composer label és send state.

### Privacy és biztonság
Komment és audience public hatása világos. Analytics nem tartalmaz komment szöveget.

### Analitika
- `community_comment_sent`

### Elfogadási feltételek
- [ ] Comment retry idempotens.
- [ ] Removed content placeholder.
- [ ] Thread lock egyértelmű.
- [ ] Block/report elérhető.
- [ ] Offline queued comment státusza látható.

## UI-59 — Community Challenges & Leaderboards

**Route/célroute:** `/community/challenges`  
**UI-mód:** Community + Gamification  
**Feature owner:** Community / Gamification

### Cél
Aszinkron, ellenőrzött challenge-ek és átlátható leaderboardok úgy, hogy a skill score, XP és részvétel ne keveredjen.

### Belépési pontok
- Community Feed
- Gamification Hub
- profile invite
- notification

### Elsődleges művelet
- **Challenge megnyitása vagy csatlakozás**

### Másodlagos műveletek
- Friends/global filter
- Leaderboard szabályok
- Saját eredmény
- Meghívás

### Compact layout
Challenge cards status és eligibility adattal, majd selected challenge leaderboard preview. A rank mellett score definíció.

### Medium/expanded layout
Bal challenge list, középen detail, jobb leaderboard és own result.

### Kötelező komponensek
- `SsChallengeCard`
- `SsLeaderboardRow`
- `SsChoiceChip`
- `SsInlineMessage`
- `SsToolConfirmationSheet`

### Állapotok
- available
- joined
- active
- submitted
- verified
- pending verification
- ended
- ineligible
- offline

### Adatkontraktus
- CommunityChallenge
- ChallengeEntry
- LeaderboardPage
- verification state
- rules version

### Accessibility
- Rank és score szöveges.
- Table headers semantics.
- Eligibility ok felolvasott.

### Privacy és biztonság
Public leaderboard név/score scope-ja előre látható; opt-in kötelező.

### Analitika
- `community_challenge_joined`

### Elfogadási feltételek
- [ ] Csatlakozás rules/consent confirmationt kér.
- [ ] Pending verification nem jelenik meg verifiedként.
- [ ] Leaderboard pagination stabil.
- [ ] Anti-cheat review neutrális nyelv.
- [ ] Offline practice később benyújtható policy szerint.

## UI-60 — Clubs & Group Detail

**Route/célroute:** `/community/clubs/:clubId?`  
**UI-mód:** Community  
**Feature owner:** Community

### Cél
Gitáros klubok felfedezése, tagság, szabályok, feed és klub challenge-ek kezelése.

### Belépési pontok
- Community Search
- Feed club link
- Profile memberships

### Elsődleges művelet
- **Klub megnyitása / Csatlakozás**

### Másodlagos műveletek
- Szabályok
- Tagok
- Klub feed
- Challenge
- Kilépés
- Report

### Compact layout
Club header, privacy/type, description, rules preview, join state, feed/challenges tabs. Private club request flow.

### Medium/expanded layout
Bal club navigation, középen selected content, jobb membership/moderation info.

### Kötelező komponensek
- `SsProfileHeader`
- `SsPostCard`
- `SsChallengeCard`
- `SsModerationActionSheet`
- `SsPrivacyAudiencePicker`

### Állapotok
- public
- private
- join requested
- member
- moderator
- banned
- archived
- offline cached

### Adatkontraktus
- Club
- MembershipState
- ClubPostPage
- ClubChallenge
- rules version

### Accessibility
- Membership state explicit.
- Rules heading structure.
- Tabs keyboard navigálhatók.

### Privacy és biztonság
Klub audience és posztláthatóság minden composerben látható.

### Analitika
- `community_club_membership_action`

### Elfogadási feltételek
- [ ] Private klub tartalma nem szivárog previewban.
- [ ] Rules elfogadás verziózott.
- [ ] Kilépés következménye világos.
- [ ] Banned/archived state neutrális és biztonságos.

## UI-61 — Notifications, Blocking & Safety Center

**Route/célroute:** `/profile/community/safety`  
**UI-mód:** Community + System  
**Feature owner:** Community / Safety

### Cél
Community értesítések, mute/block lista, report státusz, safety beállítások és tartalomkontroll kezelése.

### Belépési pontok
- Profile
- Community notification
- Moderation action
- Settings

### Elsődleges művelet
- **Értesítés megnyitása vagy safety beállítás mentése**

### Másodlagos műveletek
- Mark all read
- Blocked users
- Muted threads
- Report history
- Notification preferences

### Compact layout
Tabok Notifications és Safety. Notification list actionnal; Safetyben block/mute és preference listák.

### Medium/expanded layout
Bal kategória, középen list, jobb detail. Report státusz csak policy szerint és minimális információval.

### Kötelező komponensek
- `SsListDetail`
- `SsSwitchRow`
- `SsModerationActionSheet`
- `SsEmptyState`
- `SsInlineMessage`

### Állapotok
- notifications
- empty
- offline cached
- sync pending
- blocked list
- report submitted
- safety restriction

### Adatkontraktus
- NotificationPage
- BlockList
- MuteList
- SafetyPreferences
- ReportStatus

### Accessibility
- Unread állapot nem csak ponttal.
- Swipe actionhoz gombalternatíva.
- Switch label és leírás.

### Privacy és biztonság
Safety center érzékeny adata nem public; report tartalom analyticsből kizárt.

### Analitika
- `community_safety_action`

### Elfogadási feltételek
- [ ] Block helyben azonnal hat.
- [ ] Notification deep link biztonságosan validált.
- [ ] Mark all read idempotens.
- [ ] Report részletek nem fedik fel más felhasználó érzékeny adatait.

## UI-62 — Login & Registration

**Route/célroute:** `/profile/account/login`  
**UI-mód:** System  
**Feature owner:** Auth

### Cél
Opcionális account létrehozása vagy belépés cloud settings/community használatához, a logged-out core élmény megtartásával.

### Belépési pontok
- Profile account
- cloud sync action
- community gate

### Elsődleges művelet
- **Belépés / Regisztráció**

### Másodlagos műveletek
- Jelszó megjelenítése
- Elfelejtett jelszó, ha támogatott
- Folytatás account nélkül
- Privacy

### Compact layout
Max 480 dp form, egyértelmű tab/mode, e-mail és jelszó, inline validation, account nélküli exit. Nincs social login, amíg nem specifikált.

### Medium/expanded layout
Középre korlátozott form; opcionális bal oldali érték/privacypanel, de nem marketing túlsúly.

### Kötelező komponensek
- `SsTextField`
- `SsPrimaryButton`
- `SsSecondaryButton`
- `SsInlineMessage`
- `SsProgressIndicator`

### Állapotok
- login
- register
- validating
- submitting
- invalid credentials
- conflict
- offline
- rate limited
- success

### Adatkontraktus
- AuthFormState
- password policy
- account feature flag
- return route

### Accessibility
- Autocomplete hints.
- Password visibility state.
- Hiba summary fókuszolható.
- Keyboard action helyes.

### Privacy és biztonság
A form nem logol e-mailt/jelszót. Account előnye és opcionális jellege világos.

### Analitika
- `account_auth_outcome`

### Elfogadási feltételek
- [ ] Nyers backend hiba nem látható.
- [ ] Ismeretlen e-mail és hibás jelszó külső válasza nem árulkodó.
- [ ] Account nélkül vissza lehet térni.
- [ ] Jelszó byte-limit validáció konzisztens backenddel.
- [ ] Token secure storageba kerül.

## UI-63 — Settings

**Route/célroute:** `/profile/settings`  
**UI-mód:** System  
**Feature owner:** Settings

### Cél
Alkalmazás-, audio-, gyakorlás-, accessibility-, notification-, account- és advanced beállítások rendezett, kereshető kezelése.

### Belépési pontok
- Profile Hub
- system shortcut
- feature-specific settings link

### Elsődleges művelet
- **Beállítás módosítása; nincs globális Save, ha azonnali perzisztencia biztonságos**

### Másodlagos műveletek
- Keresés
- Reset section
- About
- Diagnostics Lab csak engedélyezett buildben

### Compact layout
Kategórialista, majd külön detail route. A fő oldal nem végtelen switchlista. Kategóriák: Appearance, Audio, Practice, Accessibility, Notifications, Account, Privacy, Offline AI, About.

### Medium/expanded layout
Bal kategórialista, jobb detail. Search találat a megfelelő settingre fókuszál.

### Kötelező komponensek
- `SsSearchField`
- `SsSwitchRow`
- `SsRadioRow`
- `SsSlider`
- `SsListDetail`
- `SsToolConfirmationSheet`

### Állapotok
- content
- search results
- setting pending
- storage failure
- restart required
- feature disabled

### Adatkontraktus
- SettingsState
- setting metadata
- restart requirement
- sync policy
- feature flags

### Accessibility
- Switch sor teljes labelje kattintható.
- Slider numeric value.
- Search result path felolvasott.
- High contrast és reduced motion itt elérhető.

### Privacy és biztonság
Privacy és analytics consent nem rejtett Advanced alatt. Diagnostics külön opt-in.

### Analitika
- `settings_changed`

### Elfogadási feltételek
- [ ] Setting write failure visszaállítja vagy jelzi az állapotot.
- [ ] Nincs közvetlen SharedPreferences a UI-ban.
- [ ] Account sync és local setting konfliktus tisztázott.
- [ ] Reset confirmation scope-ot mond.

## UI-64 — Privacy, Data & Consent Center

**Route/célroute:** `/profile/settings/privacy`  
**UI-mód:** System  
**Feature owner:** Privacy / Settings

### Cél
Az audio-, vision-, AI-, analytics-, community-, cloud sync-, export- és törlési döntések egyetlen átlátható központja.

### Belépési pontok
- Settings
- Onboarding privacy
- Coach cloud mode
- Community setup
- capture screens

### Elsődleges művelet
- **Consent vagy adatkezelési beállítás módosítása**

### Másodlagos műveletek
- Adat export
- Helyi adatok áttekintése
- Cloud adatok törlése
- Raw asset retention
- Consent history

### Compact layout
Témakörönként kártyák: On-device audio, Camera, AI, Cloud, Community, Analytics. Minden kártyán current state, rövid leírás és detail.

### Medium/expanded layout
Bal privacy kategória, középen detail, jobb data inventory és consequences.

### Kötelező komponensek
- `SsSwitchRow`
- `SsPrivacyAudiencePicker`
- `SsInlineMessage`
- `SsToolConfirmationSheet`
- `SsProgressIndicator`

### Állapotok
- local-only
- some consent enabled
- export preparing
- delete requested
- offline
- account required
- policy update required

### Adatkontraktus
- ConsentRecord
- DataInventory
- RetentionPolicy
- ExportJob
- DeletionJob
- policy version

### Accessibility
- Consent state explicit szöveggel.
- Destruktív folyamat lépései headingekkel.
- Jogi szöveg olvasható, nem kis font.

### Privacy és biztonság
Ez a képernyő maga a privacy kontrollfelület; minden action auditálható, de az audit nem tartalmaz érzékeny tartalmat.

### Analitika
- `privacy_setting_changed`

### Elfogadási feltételek
- [ ] Consent nem összecsomagolt.
- [ ] Visszavonás hatása azonnali vagy pontosan magyarázott.
- [ ] Export és delete státusz követhető.
- [ ] Local és cloud törlés külön.
- [ ] Policy update nem blokkolja az offline core-t szükségtelenül.

## UI-65 — Share Preview & Export

**Route/célroute:** `/share/preview`  
**UI-mód:** System + Community  
**Feature owner:** Share

### Cél
Practice, song, analysis, achievement vagy progress eredmény biztonságos előnézete export vagy community megosztás előtt.

### Belépési pontok
- Practice Result
- Song Result
- Analysis Overview
- Progress
- Achievement

### Elsődleges művelet
- **Megosztás vagy fájl mentése a választott cél szerint**

### Másodlagos műveletek
- Audience
- Személyes adatok elrejtése
- Kép/PDF/structured export mód
- Mégse

### Compact layout
Export preview, tartalom toggle-ok, privacy summary, target választás. Community share és system share elkülönül.

### Medium/expanded layout
Bal content controls, középen preview, jobb audience/format és privacy checklist.

### Kötelező komponensek
- `SsPrivacyAudiencePicker`
- `SsSwitchRow`
- `SsToolConfirmationSheet`
- `SsProgressIndicator`
- `SsInlineMessage`

### Állapotok
- preview
- rendering
- ready
- system share
- community queue
- cancelled
- failure

### Adatkontraktus
- SharePayload
- redaction options
- format
- audience
- render status
- idempotency key

### Accessibility
- Preview tartalma szöveges summary.
- Toggle-ok konkrét adatmezőt neveznek.
- Render progress.

### Privacy és biztonság
Megosztás előtt kötelező preview és redaction. A felhasználó explicit választja a célközönséget.

### Analitika
- `share_completed`

### Elfogadási feltételek
- [ ] Alapból minimális adat kerül megosztásra.
- [ ] Nyers audio/notation nincs automatikusan benne.
- [ ] Community audience látható.
- [ ] Retry nem duplikál posztot.
- [ ] Export fájlnév és metadata érzékeny adatot nem tartalmaz.

# 20. Referencia wireframe-ek

A wireframe-ek nem pixel-perfect terveket, hanem információs prioritást rögzítenek.

## 20.1 Today — compact

```text
┌──────────────────────────────────┐
│ Jó reggelt, Csaba         Offline│
│                                  │
│ Mai cél                  12/20 p │
│ ████████████░░░░░░░░             │
│                                  │
│ ┌──────────────────────────────┐ │
│ │ FOLYTATÁS                    │ │
│ │ Em → Am váltás               │ │
│ │ Tegnap 72% · 6 perc          │ │
│ │                              │ │
│ │ [ Mai gyakorlás indítása ]   │ │
│ └──────────────────────────────┘ │
│                                  │
│ Mai terv                         │
│ 1  Bemelegítés              3 p  │
│ 2  Akkordváltás             6 p  │
│ 3  Song section             8 p  │
│                                  │
│ Coach                            │
│ „Ma a stabil váltás a fókusz.”  │
├──────────────────────────────────┤
│ Today Practice Songs Coach Me    │
└──────────────────────────────────┘
```

## 20.2 Live Stage — portrait

```text
┌──────────────────────────────────┐
│ LIVE · ON DEVICE       02:14  ●  │
│                                  │
│                                  │
│                Am                │
│                                  │
│                 ↓                │
│             DOWNSTRUM            │
│                                  │
│       1   &   2   &   3   &   4 │
│       ●   ○   ●   ○   ●   ○     │
│                                  │
│ Timing +18 ms · Good             │
│ Signal strong · 84 BPM           │
│                                  │
│ [ Pause ]             [ Finish ] │
└──────────────────────────────────┘
```

## 20.3 Song Trainer — landscape/expanded

```text
┌───────────────┬──────────────────────────────┬──────────────────┐
│ Section list  │ TAB / notation              │ Current feedback │
│ Intro         │                              │                  │
│ Verse 1   ●   │      playhead                │ Timing +22 ms    │
│ Chorus        │                              │ Chord: G missed  │
│ Solo          │ current + upcoming measures  │ Confidence high  │
│               │                              │                  │
├───────────────┴──────────────────────────────┴──────────────────┤
│ A────loop────B     75% speed      ◀  Pause  ▶        Finish    │
└──────────────────────────────────────────────────────────────────┘
```

## 20.4 Analysis Overview — compact

```text
┌──────────────────────────────────┐
│ Analysis                         │
│ Signal quality: Good             │
│                                  │
│               82                 │
│          OVERALL RESULT          │
│                                  │
│ Timing                 86 · High │
│ Chord accuracy         79 · High │
│ Consistency            73 · Mid  │
│ Dynamics               —  N/A    │
│                                  │
│ Legfontosabb javítás             │
│ „A 3–4. ütem között sietsz.”     │
│                                  │
│ [ Hibás rész gyakorlása ]        │
│ [ Timeline ] [ AI debrief ]      │
└──────────────────────────────────┘
```

## 20.5 Tutor Conversation — expanded

```text
┌──────────────┬──────────────────────────────┬───────────────────┐
│ Conversations│ LOCAL AI                    │ Evidence          │
│ Today        │                              │ Session #184      │
│ Chord buzz   │ Mit érzékeltem?              │ Timing 68–74 sec  │
│ Rhythm       │ A G akkord 3. húrja tompa.  │ Confidence 0.82   │
│              │                              │                  │
│              │ Mi lehet az oka?             │ [Open timeline]   │
│              │ Az ujjad hozzáérhet a húrhoz.│                  │
│              │                              │                  │
│              │ Mit tegyél most?             │                  │
│              │ [3 perces javítógyakorlat]   │                  │
├──────────────┴──────────────────────────────┴───────────────────┤
│ Kérdezz a játékodról…                               [Küldés]    │
└──────────────────────────────────────────────────────────────────┘
```

## 20.6 Vision Coach — compact

```text
┌──────────────────────────────────┐
│ CAMERA · ON DEVICE          ●    │
│                                  │
│        ┌────────────────┐        │
│        │  LIVE PREVIEW  │        │
│        │      ◯ wrist   │        │
│        └────────────────┘        │
│                                  │
│ Engedd lejjebb a bal csuklódat   │
│ Confidence medium                │
│ ███████░░░  javulás              │
│                                  │
│ [ Példa ] [ Elrejtés ]           │
│ [ Pause ]             [ Finish ] │
└──────────────────────────────────┘
```

## 20.7 Community composer — compact

```text
┌──────────────────────────────────┐
│ Új poszt                  Friends│
│                                  │
│ Mit gyakoroltál ma?              │
│ ┌──────────────────────────────┐ │
│ │                              │ │
│ └──────────────────────────────┘ │
│                                  │
│ Practice card                    │
│ Rhythm session · 12 min · 82     │
│ [ Személyes adatok kezelése ]    │
│                                  │
│ Audience: Friends                │
│ Ez nem tartalmaz nyers hangot.   │
│                                  │
│ [ Közzététel ]                   │
└──────────────────────────────────┘
```

---

# 21. Keresztképernyős flow-k

## 21.1 Napi tanulási flow

```text
Today
  → Today Plan Detail
  → Practice Session Setup
  → Practice Session
  → Practice Result
  → optional Tutor Debrief
  → Today updated
```

Elvárás:

- a back stack ne duplikálja a Stage route-ot;
- result után Today új adata frissüljön;
- reward és progress idempotens eventből frissüljön;
- offline állapotban sem akad meg a flow;
- a felhasználó egyértelműen befejezheti a napot.

## 21.2 Dalgyakorlás flow

```text
Songs
  → Song Overview
  → Song Trainer Setup
  → Song Trainer
  → Song Result
  → difficult section remediation
```

Elvárás:

- section, loop és speed megmarad remediationnél;
- backing track állapot nem veszik el;
- playback-only és scored session külön result típust ad;
- route leave felszabadítja audio erőforrásokat.

## 21.3 Elemzési flow

```text
Analyze Home
  → Recording/Input
  → Processing
  → Analysis Overview
  → Timeline
  → Practice remediation
```

Elvárás:

- recording és processing külön lifecycle;
- cancel következménye világos;
- raw audio retention beállítás végig követhető;
- analysis result akkor is megmarad, ha a raw file később törlődik.

## 21.4 AI coaching flow

```text
Result / Coach Home
  → Tutor Conversation or Debrief
  → Evidence
  → Action proposal
  → Confirmation
  → Practice/Plan mutation
```

Elvárás:

- AI action nem fut automatikusan;
- provenance látható;
- offline fallback működik;
- plan mutation diffet mutat;
- tool execution eredménye visszakerül a conversationbe.

## 21.5 Vision flow

```text
Vision Setup
  → Calibration
  → Vision Coach
  → Vision Result
  → Technique remediation
```

Elvárás:

- kamera csak setup után indul;
- calibration invalidálható;
- thermal degrade jelzett;
- frame nem mentődik alapból;
- audio-only fallback elérhető.

## 21.6 Community share flow

```text
Result
  → Share Preview
  → Audience + redaction
  → Post Composer
  → Publish/Offline Queue
  → Post Detail
```

Elvárás:

- raw audio és szerzői jogi notation nincs implicit;
- audience minden lépésben látható;
- retry idempotens;
- offline queue státusza követhető;
- megosztás visszavonható policy szerint.

---

# 22. Tartalmi és microcopy szabályok

## 22.1 Feedback formula

A feedback ajánlott szerkezete:

```text
Megfigyelés → Lehetséges ok → Következő konkrét lépés
```

Példa:

```text
A második és negyedik ütésen rendszeresen 35–45 ms-ot sietsz.
Ez gyakran akkor történik, amikor a felütés után túl gyorsan indítod a kezed lefelé.
Próbáld 70 BPM-en, csak a 2. és 4. ütemet hangsúlyozva.
```

## 22.2 Tiltott nyelvezet

Kerülendő:

- „Rossz vagy ebben.”
- „Elrontottad a streakedet.”
- „Az AI biztosan tudja.”
- „Hibás kéztartás.” alacsony confidence esetén.
- „Nincs internet, ezért nem használhatod az appot.”
- „Sikertelen.” kontextus nélkül.

Helyette:

- „Ez a rész még nem stabil.”
- „Ma pihenőnapot is tarthatsz.”
- „A mérés alapján valószínű…”
- „A kamera nem látja elég biztosan a csuklódat.”
- „Offline módban a helyi funkciók tovább működnek.”
- „A mentés nem sikerült; a session helyi másolata megmaradt.”

## 22.3 CTA szabályok

Jó:

- „Mai gyakorlás indítása”
- „Hibás szakasz gyakorlása”
- „Mikrofon engedélyezése”
- „Helyi modell letöltése”
- „Tervmódosítás elfogadása”

Kerülendő:

- „OK”
- „Tovább” kontextus nélkül
- „Igen”
- „Kész” többértelmű helyzetben
- „Engedélyezés” magyarázat nélkül

---

# 23. Navigációs és state-restoration szabályok

- A tabonkénti navigációs stack megőrzendő, ahol a platform és GoRouter architektúra támogatja.
- Stage Mode route nem maradhat rejtetten aktív más tab alatt.
- Process death után csak biztonságosan checkpointolt session ajánlható fel folytatásra.
- Form draftok helyreállíthatók, de public publish nem ismételhető automatikusan.
- Deep link jogosultságot, feature flaget és auth állapotot validál.
- Hibás route argumentum error route-ra vagy biztonságos parent route-ra vezet.
- Modal és bottom sheet nem lehet kritikus adat egyetlen tárolási helye.
- A keyboard back és Android predictive back támogatandó.
- Unsaved editor/composer back action confirmationt kér.
- Back gesture és timeline/fretboard pan gesture konfliktusát edge-safe területtel kell kezelni.

---

# 24. Komponens API minőségi szabályok

Minden publikus design-system komponens:

- rendelkezik dokumentált felelősséggel;
- nem tartalmaz feature business logikát;
- theme tokeneket használ;
- tesztelhető provider nélkül, ha lehetséges;
- támogatja a disabled, loading és error állapotot, ha releváns;
- rendelkezik semantics szerződéssel;
- nem indít hálózatot, storage-ot, mikrofont vagy kamerát;
- nem példányosít saját globális controller/state objektumot;
- lehetőleg const constructort használ;
- nem fogad el nyers hex színt normál használatban;
- nem nyeli el a gesture-t szükségtelenül;
- nagy text scale mellett rugalmas.

Példa:

```dart
class SsPrimaryButton extends StatelessWidget {
  const SsPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool loading;
  final bool expand;
}
```

A `loading == true` állapot:

- megőrzi a gomb szélességét;
- megakadályozza a duplakattintást;
- nem tünteti el teljesen a label semanticsot;
- szükség esetén progress semanticsot ad.

---

# 25. Codex végrehajtási szabályok ehhez a fejezethez

Minden kör előtt:

1. Olvasd el az `AGENTS.md` fájlt.
2. Olvasd el a Chapter 13 releváns globális részeit és a migrálandó képernyő specifikációját.
3. Vizsgáld meg a meglévő képernyőt, providert és teszteket.
4. Ne változtass domain-, DSP- vagy ML-viselkedést pusztán UI-refaktor miatt.
5. Először adj hozzá vagy frissíts regressziós tesztet, ha meglévő hibát javítasz.
6. Egy körben csak az adott scope-ot valósítsd meg.
7. A golden fájlok frissítését ne fogadd el automatikusan: vizuálisan ellenőrizd az eltérést.
8. Futtasd a kötelező ellenőrzéseket külön parancsokban.
9. Frissítsd a `HANDOFF.md` fájlt.
10. Ne kezdd el a következő kört.

Kötelező alapellenőrzések minden Flutter-kör végén:

```bash
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib/ test/ tool/
flutter test
```

A golden körökben ezen felül:

```bash
flutter test --tags=golden
```

Golden frissítés csak explicit, felülvizsgált parancsként:

```bash
flutter test --update-goldens --tags=golden
```

A frissítés után a diff screenshotokat manuálisan ellenőrizni kell.

# 26. Fejlesztési körök

# Kör 1 — UI baseline inventory és screenshot corpus

## Cél
A jelenlegi StrumSight felület, route-ok, komponensek és accessibility állapot dokumentált baseline-jának létrehozása módosítás nélkül.

## Függőségek
- A repository jelenlegi `main` állapota.
- Chapter 2 Core Platform baseline szabályai.

## Fő érintett területek
- `docs/ui/baseline/`
- `tool/ui_inventory.dart`
- `test/ui/`

## Feladatok
1. Listázd az összes jelenlegi screen, route, dialog, bottom sheet és reusable widget fájlt; rendeld hozzájuk a Chapter 13 UI-azonosítót vagy jelöld legacy/temporary státusszal.
2. Készíts route-térképet a jelenlegi és célroute-okkal, beleértve a redirect és deep-link kockázatokat.
3. Rögzíts referencia screenshotot legalább a Live, Tuner, Analyze, Learn, Library, Settings és onboarding fő állapotáról compact portréban.
4. Dokumentáld a közvetlen hex színeket, hardcoded spacinget, közvetlen TextStyle-okat, duplikált button/card/empty-state mintákat és cross-feature UI importokat.
5. Futtass alap semantics, overflow és text-scale auditot; a hibákat prioritással, nem automatikus refaktorral rögzítsd.
6. Hozd létre a `docs/ui/README.md` és `docs/ui/migration-status.md` fájlokat.

## Kötelező tesztek
- A meglévő Flutter tesztcsomag változatlanul zöld.
- A route inventory script determinisztikus outputot ad.
- A baseline screenshotok megnyithatók és nem üresek.

## Elfogadási feltételek
- [ ] Alkalmazáskód viselkedése nem változott.
- [ ] Minden production képernyő szerepel az inventoryban.
- [ ] A legacy és target route mapping dokumentált.
- [ ] A kritikus accessibility és overflow hibák backlogba kerültek.

## Kockázatok és korlátok
- A screenshot corpus nem tekintendő végleges designnak; csak regressziós baseline.
- A route-ok automatikus felismerése kézi felülvizsgálatot igényel.

## Javasolt branch
`codex/ch13-r01-ui-baseline-inventory-es-screenshot-corpus`

## Javasolt commit
`chore(ui): establish interface baseline and migration inventory`

---
# Kör 2 — Design system foundation és compatibility layer

## Cél
Az új `core/design_system` alapstruktúra létrehozása úgy, hogy a meglévő `core/theme` továbbra is működjön.

## Függőségek
- Kör 1 baseline.

## Fő érintett területek
- `lib/core/design_system/`
- `lib/core/theme/`
- `test/core/design_system/`

## Feladatok
1. Hozd létre a Chapter 13-ban megadott foundation, themes, components, layouts és public export könyvtárakat.
2. Implementáld az `SsBreakpoints`, `SsSpacing`, `SsRadius`, `SsMotion` és alap semantics konstansokat.
3. Készíts kompatibilitási adaptert a meglévő `AppColors`, `AppPalette` és `AppTheme` felé; ne duplikáld a színforrást átmenetileg.
4. Hozz létre egy development-only Component Catalog route-ot feature flag mögött.
5. Dokumentáld, hogy mely token a kanonikus forrás a migráció egyes szakaszaiban.
6. Adj architekturális guardot, amely megakadályozza, hogy a design system feature business logikát importáljon.

## Kötelező tesztek
- Foundation token unit tesztek.
- Architecture dependency test.
- Component Catalog smoke test dark/light témában.

## Elfogadási feltételek
- [ ] Az új design system importálható egyetlen `public.dart` fájlból.
- [ ] Nincs funkcionális UI regresszió.
- [ ] A meglévő theme API tovább működik.
- [ ] A design system nem függ feature-től.

## Kockázatok és korlátok
- Átmeneti dupla export elnevezési ütközést okozhat; explicit prefix vagy deprecation szükséges.

## Javasolt branch
`codex/ch13-r02-design-system-foundation-es-compatibility-layer`

## Javasolt commit
`feat(ui): establish design system foundation`

---
# Kör 3 — Szemantikai színek és három téma

## Cél
A meglévő palettát Dark Studio, Warm Light és High Contrast szemantikai theme extensionné alakítani.

## Függőségek
- Kör 2 design system foundation.

## Fő érintett területek
- `lib/core/design_system/foundations/ss_colors.dart`
- `lib/core/design_system/themes/`
- `test/core/design_system/themes/`

## Feladatok
1. Implementáld az `SsColorScheme` ThemeExtensiont a dokumentált brand, surface, text, status, confidence, offline, local AI, cloud AI és sync tokenekkel.
2. Mapeld a meglévő hex színeket szemantikai tokenekre; új hex csak dokumentált kontrasztok alapján adható hozzá.
3. Készíts Dark Studio, Warm Light és High Contrast theme konfigurációt.
4. Definiáld a disabled, focus, hover, pressed és selected state overlayeket.
5. Készíts kontraszt-ellenőrző unit vagy tool scriptet a fő text/surface párokra.
6. Frissítsd a Component Catalogot theme switcherrel.

## Kötelező tesztek
- Theme serialization/equality teszt, ha releváns.
- Kontraszt script a kötelező párokra.
- Golden: alap button, card, input és status komponensek mindhárom témában.

## Elfogadási feltételek
- [ ] Normál text célkontrasztja legalább 4.5:1.
- [ ] Fontos non-text UI határ legalább 3:1, ahol alkalmazandó.
- [ ] Confidence, offline és AI mód nem csak színnel jelzett.
- [ ] Nincs hardcoded szín az új komponensekben.

## Kockázatok és korlátok
- A brand copper bizonyos light surface párokon külön `brandStrong` árnyalatot igényelhet.
- A golden diffet manuálisan ellenőrizni kell.

## Javasolt branch
`codex/ch13-r03-szemantikai-szinek-es-harom-tema`

## Javasolt commit
`feat(theme): add semantic Copper Stage color system`

---
# Kör 4 — Tipográfia és text-scale resilience

## Cél
Poppins/Montserrat alapú, hozzáférhető tipográfiai rendszer létrehozása clipping és kézi TextStyle duplikáció nélkül.

## Függőségek
- Kör 2–3.

## Fő érintett területek
- `lib/core/design_system/foundations/ss_typography.dart`
- `lib/core/design_system/themes/`
- `test/core/design_system/typography/`

## Feladatok
1. Implementáld a Chapter 13 tipográfiai scale-t ThemeExtension vagy Theme text styles formájában.
2. Állítsd be a Poppins és Montserrat szerepeket; metric style használjon tabular figures támogatást, ahol a font és Flutter API engedi.
3. Készíts adaptív `displayChord` sizing helper-t viewport és text scale alapján.
4. Adj maxLines/overflow irányelveket a komponensekhez; fontos cím nem ellipszálható kontextusvesztéssel.
5. Készíts hosszú magyar string fixture-öket és 1.0, 1.3, 2.0 text scale teszteket.
6. Dokumentáld a heading hierarchy és screen-reader heading használatot.

## Kötelező tesztek
- Golden typography specimen en/hu, 1.0 és 2.0 scale.
- Overflow widget teszt kis viewporton.
- Chord hero rövid és hosszú akkordnév teszt.

## Elfogadási feltételek
- [ ] A kritikus komponensek 200% text scale mellett nem clipelnek.
- [ ] A metric egység nem válik le értelmetlenül.
- [ ] Akkordnév Stage Mode-ban olvasható marad.
- [ ] Új képernyő nem használ ad hoc TextStyle-t.

## Kockázatok és korlátok
- A font asset hiánya golden környezetben fallbacket okozhat; teszt setupnak be kell töltenie a fontokat.

## Javasolt branch
`codex/ch13-r04-tipografia-es-text-scale-resilience`

## Javasolt commit
`feat(ui): define accessible StrumSight typography scale`

---
# Kör 5 — Spacing radius elevation és surface primitives

## Cél
Egységes geometriai és surface rendszer bevezetése, amely megszünteti a véletlenszerű méreteket és túlzott árnyékokat.

## Függőségek
- Kör 2–4.

## Fő érintett területek
- `lib/core/design_system/foundations/`
- `lib/core/design_system/components/cards/`
- `test/core/design_system/foundations/`

## Feladatok
1. Implementáld a 4 dp grid spacing tokeneket és a radius skálát.
2. Definiáld a surface elevation szinteket dark/light/high-contrast témában.
3. Készíts `SsSurface`, `SsCard`, `SsHeroCard` és `SsSection` primitiveket.
4. Adj lint/architecture ellenőrzést az új design-system scope-ban megjelenő nyers EdgeInsets/radius mintákra, ésszerű allowlisttel.
5. Dokumentáld a compact/medium/expanded screen paddinget.
6. Frissítsd a Component Catalogot surface hierarchia példákkal.

## Kötelező tesztek
- Golden surface matrix mindhárom témában.
- Token value unit test.
- Nagy text scale és nested surface widget teszt.

## Elfogadási feltételek
- [ ] Az új kártyák tokeneket használnak.
- [ ] Sötét témában elevation nem csak nagy shadow.
- [ ] High contrast téma borderrel is megkülönböztet.
- [ ] Nincs felesleges nested card-on-card struktúra a mintákban.

## Javasolt branch
`codex/ch13-r05-spacing-radius-elevation-es-surface-primitives`

## Javasolt commit
`feat(ui): standardize spacing radius and surfaces`

---
# Kör 6 — Motion rendszer és reduced motion

## Cél
Zeneileg releváns, audio-clock kompatibilis motion tokenek és reduced-motion viselkedés létrehozása.

## Függőségek
- Kör 2–5.

## Fő érintett területek
- `lib/core/design_system/foundations/ss_motion.dart`
- `lib/core/design_system/components/feedback/`
- `test/core/design_system/motion/`

## Feladatok
1. Implementáld a duration és curve tokeneket, valamint a reduced-motion resolver-t.
2. Készíts közös chord-change, content-fade, route-emphasis és success-feedback transition primitiveket.
3. Dokumentáld, mely animáció lehet audio clockhoz kötött, és tiltsd a független beat Timer használatát.
4. Implementálj motion disable/replace viselkedést accessibility setting és platform preference alapján.
5. Készíts `SsAnimatedNumber` vagy metric transition komponenst, amely reduced motion mellett azonnal vált.
6. Adj tesztet, hogy végtelen dekoratív animation controller ne maradjon route dispose után.

## Kötelező tesztek
- Reduced motion widget teszt.
- Animation lifecycle dispose teszt.
- Golden start/end state, nem törékeny köztes frame.

## Elfogadási feltételek
- [ ] Reduced motion mellett nincs scale/parallax/folyamatos pulse.
- [ ] Beat vizualizáció audio state-ből vezérelt.
- [ ] Route leave után nincs aktív controller.
- [ ] A visszajelzés animáció nélkül is érthető.

## Javasolt branch
`codex/ch13-r06-motion-rendszer-es-reduced-motion`

## Javasolt commit
`feat(ui): add musical motion and reduced motion support`

---
# Kör 7 — Ikonográfia és gitárglyph készlet

## Cél
Egységes ikon API és hozzáférhető gitárspecifikus glyph rendszer kialakítása.

## Függőségek
- Kör 2–6.

## Fő érintett területek
- `lib/core/design_system/icons/`
- `assets/icons/`
- `test/core/design_system/icons/`

## Feladatok
1. Készíts `SsIcons` katalógust Material Symbols és saját glyph mappinggel.
2. Implementáld vagy vektorosan add hozzá a down/up strum, alternate picking, palm mute, bend, vibrato, hammer-on, pull-off, slide, capo, metronome, tuning peg, fretboard és loop AB jeleket.
3. Definiáld az alap 24 dp, Stage 32–48 dp és semantics szabályokat.
4. Adj shape-filling vagy outline variánst confidence/state redundanciához, de ne keverd a jelentéseket.
5. Készíts icon galleryt a Component Catalogban.
6. Ellenőrizd, hogy production UI-ban ne maradjon funkcionális emoji.

## Kötelező tesztek
- Icon golden dark/light/high contrast.
- Semantics label teszt interaktív ikonokra.
- Missing glyph fallback teszt.

## Elfogadási feltételek
- [ ] Minden saját glyph egységes stroke/optical size.
- [ ] Strum direction nem csak nyílkarakterként jelenik meg.
- [ ] Interaktív icon buttonnak tooltipje és semantics labelje van.
- [ ] Dekoratív ikon ki van zárva a semanticsből.

## Javasolt branch
`codex/ch13-r07-ikonografia-es-gitarglyph-keszlet`

## Javasolt commit
`feat(ui): add accessible guitar iconography`

---
# Kör 8 — Adaptive scaffold és primary navigation

## Cél
Today–Practice–Songs–Coach–Profile célarchitektúra implementálása compact bottom navigationnel és medium/expanded raillel.

## Függőségek
- Kör 1 route inventory.
- Kör 2–7 design primitives.
- Chapter 2 routing stabilizáció.

## Fő érintett területek
- `lib/core/design_system/layouts/ss_adaptive_scaffold.dart`
- `lib/app/routing/`
- `lib/app/home_shell.dart`
- `test/app/navigation/`

## Feladatok
1. Implementáld az `SsAdaptiveScaffold` layout class resolverét compact, medium, expanded és wide módokra.
2. Hozd létre az öt cél primary destinationt feature flag mögött, első körben legacy screen adapterekkel.
3. Medium/expanded módban NavigationRailt vagy compact drawert használj; őrizd meg a tab stackeket.
4. Implementáld a legacy route redirect/alias mapet deep-link megőrzéssel.
5. Adj keyboard shortcut és focus behavior támogatást expanded módban.
6. Biztosítsd, hogy Stage Mode route-ok elrejtsék a primary navigationt.

## Kötelező tesztek
- Navigation widget teszt minden breakpointon.
- Legacy route redirect teszt.
- Tab state restoration teszt.
- Predictive/system back teszt, amennyire automatizálható.

## Elfogadási feltételek
- [ ] Öt célterület elérhető feature flaggel.
- [ ] Legacy link nem törik.
- [ ] Kiválasztott tab state megmarad.
- [ ] Stage route alatt nincs bottom nav.
- [ ] Nincs route loop.

## Kockázatok és korlátok
- A teljes információs architektúra egyszerre nem migrálható; adapter és flag kötelező.
- A tab-stack kezelés GoRouter verziófüggő lehet.

## Javasolt branch
`codex/ch13-r08-adaptive-scaffold-es-primary-navigation`

## Javasolt commit
`refactor(navigation): add adaptive five-area application shell`

---
# Kör 9 — StageScaffold és session transport

## Cél
A Live, Practice, Song, Tuner, Metronome és Vision aktív állapotának közös, lifecycle-semleges Stage layoutja.

## Függőségek
- Kör 3–8.
- Chapter 2 audio lifecycle.

## Fő érintett területek
- `lib/core/design_system/layouts/ss_stage_scaffold.dart`
- `lib/core/design_system/components/music/ss_session_transport.dart`
- `test/core/design_system/stage/`

## Feladatok
1. Implementáld az `SsStageScaffold` safe-area, orientation, screen-awake és primary-nav-free vizuális szerkezetét; erőforrás-kezelést ne tegyél a widgetbe.
2. Készíts `SsSessionTransport` komponenst idle, count-in, active, paused, finishing és disabled állapotokkal.
3. Definiáld a status header, hero slot, feedback slot, timeline/beat slot és bottom action slot API-ját.
4. Adj portrait, landscape és expanded layout stratégiát.
5. Implementáld az unsaved session back confirmation hookját feature callbackkel.
6. Adj high contrast és 2.0 text scale támogatást.

## Kötelező tesztek
- Stage golden portrait/landscape/tablet.
- Transport state widget tesztek.
- Back confirmation integration fake sessionnel.
- Semantics order teszt.

## Elfogadási feltételek
- [ ] A StageScaffold nem indít mikrofont/kamerát.
- [ ] Pause és Finish mindig látható.
- [ ] Landscape-ben nincs overflow.
- [ ] System back adatvesztésnél megerősít.
- [ ] Primary navigation rejtett.

## Javasolt branch
`codex/ch13-r09-stagescaffold-es-session-transport`

## Javasolt commit
`feat(ui): introduce reusable Stage Mode scaffold`

---
# Kör 10 — Aszinkron állapotkomponensek

## Cél
Loading, skeleton, empty, offline, sync pending, degraded, permission, failure és blocked állapotok közös megjelenítése.

## Függőségek
- Kör 2–9.
- Chapter 2 AppFailure és ScreenState.

## Fő érintett területek
- `lib/core/design_system/components/feedback/`
- `test/core/design_system/feedback/`

## Feladatok
1. Implementáld a Chapter 13 kötelező feedback komponenseit stabil API-val.
2. Készíts failure-code → lokalizált presentation model mappinget; a design system nyers exceptiont nem fogad.
3. Adj cached-content overlay mintát offline és sync pending állapothoz.
4. Implementáld microphone/camera notification/storage permission presentation modelleket.
5. Készíts retry, open settings, continue offline és contact support action variánsokat.
6. Dokumentáld, mikor használható full-screen state, banner, inline message vagy snackbar.

## Kötelező tesztek
- Minden state golden mindhárom témában.
- Retry visibility teszt retryable/non-retryable failure-rel.
- Permission permanently denied teszt.
- Screen reader live region teszt.

## Elfogadási feltételek
- [ ] Offline nem danger stílus.
- [ ] Cached content látható marad.
- [ ] Nyers exception nem jelenik meg.
- [ ] Empty state értelmes actiont ad.
- [ ] Permission állapot elmagyarázza a célt.

## Javasolt branch
`codex/ch13-r10-aszinkron-allapotkomponensek`

## Javasolt commit
`feat(ui): standardize asynchronous and recovery states`

---
# Kör 11 — Action input és form komponenskészlet

## Cél
Gombok, mezők, selection, slider, tempo/duration input és validation egységes, hozzáférhető implementációja.

## Függőségek
- Kör 2–10.

## Fő érintett területek
- `lib/core/design_system/components/actions/`
- `lib/core/design_system/components/inputs/`
- `test/core/design_system/forms/`

## Feladatok
1. Implementáld a primary, secondary, tertiary, destructive és icon button variánsokat loading/disabled/focus állapottal.
2. Implementáld a text/search field, switch row, radio row, choice chip és segmented control komponenseket.
3. Implementáld az exact numeric inputtal párosított slider/tempo/duration pickert.
4. Készíts közös validation summary és inline field error mintát.
5. Adj keyboard, autofill, IME action és focus traversal támogatást.
6. Dokumentáld az egy képernyőn egy primary CTA szabály kivételeit Stage Mode-ban.

## Kötelező tesztek
- Input golden és interaction tesztek.
- Keyboard navigation teszt.
- Text scale 2.0.
- Loading button double-submit teszt.
- Slider numeric sync property teszt.

## Elfogadási feltételek
- [ ] Minden inputnak tartós labelje van.
- [ ] Loading gomb nem ugrik méretben.
- [ ] Switch teljes sora érinthető.
- [ ] Slider mellett pontos érték adható.
- [ ] Destruktív button vizuálisan és semanticsban elkülönül.

## Javasolt branch
`codex/ch13-r11-action-input-es-form-komponenskeszlet`

## Javasolt commit
`feat(ui): build accessible action and form components`

---
# Kör 12 — Kártyák badge-ek insight és status komponensek

## Cél
A hubok, eredmények, AI, sync és confidence felületek újrahasznosítható információs komponenseinek kialakítása.

## Függőségek
- Kör 2–11.

## Fő érintett területek
- `lib/core/design_system/components/cards/`
- `lib/core/design_system/components/feedback/`
- `lib/core/design_system/components/ai/`

## Feladatok
1. Implementáld az `SsMetricCard`, `SsInsightCard`, `SsCoachActionCard`, `SsModelStatusCard` és általános content card primitiveket.
2. Implementáld az offline, sync pending, local AI, cloud AI, on-device, privacy audience és confidence badge-eket ikon + szöveg formában.
3. Definiáld a card action hierarchy és nested tap target szabályokat.
4. Adj compact és expanded card density variánst.
5. Készíts skeleton megfelelőket, amelyek megtartják a layout geometriát.
6. Frissítsd a Component Catalogot állapotmatrixszal.

## Kötelező tesztek
- Card/badge golden matrix.
- Nested action hit-test.
- Semantics summary teszt.
- Long Hungarian title overflow.

## Elfogadási feltételek
- [ ] Badge jelentése nem csak szín.
- [ ] Card teljes felülete csak akkor kattintható, ha egyetlen fő action van.
- [ ] Skeleton nem olvasható tartalomként.
- [ ] AI action provenance látható.

## Javasolt branch
`codex/ch13-r12-kartyak-badge-ek-insight-es-status-komponensek`

## Javasolt commit
`feat(ui): add reusable insight status and metric cards`

---
# Kör 13 — Overlay dialog bottom sheet és confirmation rendszer

## Cél
Egységes, biztonságos overlay rendszer létrehozása permission, tool action, destruktív művelet és részletpanel célokra.

## Függőségek
- Kör 10–12.

## Fő érintett területek
- `lib/core/design_system/components/overlays/`
- `test/core/design_system/overlays/`

## Feladatok
1. Implementáld a standard alert dialog, confirmation sheet, side sheet és full-screen modal mintákat.
2. Készíts `SsToolConfirmationSheet` API-t action summary, affected data, privacy/network/capture következmény és confirm/cancel elemekkel.
3. Definiáld a destruktív megerősítés tárgy-specifikus microcopy szabályait.
4. Adj modal focus trap, restore focus, keyboard escape és Android back támogatást.
5. Biztosítsd, hogy large screenen indokolt esetben side sheet, compacton bottom sheet jelenjen meg.
6. Készíts unsaved changes, delete session, publish post, download model és plan mutation mintákat.

## Kötelező tesztek
- Overlay golden compact/expanded.
- Focus trap és restore teszt.
- Back/escape teszt.
- Destructive confirmation callback pontosan egyszer.

## Elfogadási feltételek
- [ ] Confirmation nem használ homályos Igen/Nem címkét.
- [ ] A háttér semantics elrejtett.
- [ ] Cancel minden kockázatos műveletnél elérhető.
- [ ] AI tool action érintett adatot és módot mutat.

## Javasolt branch
`codex/ch13-r13-overlay-dialog-bottom-sheet-es-confirmation-rend`

## Javasolt commit
`feat(ui): standardize overlays and safe confirmations`

---
# Kör 14 — Accessibility foundation audit és semantics toolkit

## Cél
A teljes design system accessibility szerződésének automatizálása és a legkritikusabb legacy hibák javítása.

## Függőségek
- Kör 1–13.

## Fő érintett területek
- `lib/core/design_system/foundations/ss_semantics.dart`
- `test/accessibility/`
- `docs/ui/accessibility.md`

## Feladatok
1. Készíts semantics helper és audit utilityt heading, live region, metric, chord, strum, beat, tuner és chart summary célokra.
2. Adj minimum tap target ellenőrzést a kritikus komponensekre.
3. Futtass accessibility auditot a Live, Tuner, onboarding és Settings baseline képernyőkön.
4. Javítsd a fókuszsorrendet, hiányzó labelt és csak-színnel jelzett állapotot a scope képernyőkön.
5. Készíts screen-reader copy fixture-t angol és magyar nyelven.
6. Dokumentáld a manual TalkBack/VoiceOver checklistet.

## Kötelező tesztek
- Semantics tree snapshot vagy célzott matcher tesztek.
- Tap target teszt.
- Text scale 2.0 golden kritikus képernyőkön.
- Reduced motion preference teszt.

## Elfogadási feltételek
- [ ] A kritikus actionök címkézettek.
- [ ] A Live frame nem spamli a screen readert.
- [ ] A tuner cents és direction felolvasható.
- [ ] Nincs csak színnel közölt success/error/confidence.

## Kockázatok és korlátok
- Az automatizált semantics teszt nem helyettesíti a valós TalkBack/VoiceOver próbát.

## Javasolt branch
`codex/ch13-r14-accessibility-foundation-audit-es-semantics-tool`

## Javasolt commit
`fix(a11y): establish semantics and accessibility quality gates`

---
# Kör 15 — Lokalizációs resilience és content style

## Cél
Az angol–magyar UI törésbiztonságának, microcopy szabályainak és locale-aware formázásának kialakítása.

## Függőségek
- Kör 4, 10–14.

## Fő érintett területek
- `lib/l10n/`
- `test/l10n/`
- `docs/ui/content-style.md`

## Feladatok
1. Készíts Chapter 13 képernyő- és komponensstring katalógust stabil ARB kulcselnevezéssel.
2. Adj hosszú magyar, plural, date, duration, score és unit fixture-öket.
3. Javítsd a string concatenation és hardcoded user-facing string eseteket a migrált core komponensekben.
4. Implementáld a locale-aware duration, BPM, cents, percentage és dátum formázókat.
5. Készíts microcopy stílusútmutatót feedback, permission, AI provenance, offline és destructive action célokra.
6. Adj pseudo-localization vagy extra-long locale tesztmódot.

## Kötelező tesztek
- ARB parity.
- Plural és format unit teszt.
- Pseudo-locale golden hub és form képernyőn.
- No hardcoded production string guard a migrált scope-ban.

## Elfogadási feltételek
- [ ] Angol és magyar kulcsparitás zöld.
- [ ] Nincs mondatszerkezet string concatenation.
- [ ] Magyar szöveg nem clipel kritikus komponensben.
- [ ] Dátum/idő/egység locale-aware.

## Javasolt branch
`codex/ch13-r15-lokalizacios-resilience-es-content-style`

## Javasolt commit
`feat(l10n): harden localized UI content and formatting`

---
# Kör 16 — Launch recovery és onboarding migráció

## Cél
UI-01–UI-04 implementálása az új design systemmel, permission primerrel és safe-mode flow-val.

## Függőségek
- Kör 2–15.
- Chapter 2 bootstrap és permission gateway.

## Fő érintett területek
- `lib/app/bootstrap/`
- `lib/features/onboarding/`
- `lib/app/routing/`
- `test/features/onboarding/`

## Feladatok
1. Migráld a Launch/Bootstrap felületet theme-safe, villanásmentes state kezelésre.
2. Implementáld a Recovery & Safe Mode képernyőt redaktált failure presentationnel.
3. Migráld az onboarding value/privacy flow-t progresszív, visszatérhető lépésekre.
4. Implementáld a microphone primer + first-win mini Stage flow-t fake gateway és engine tesztelhetőséggel.
5. Adj onboarding version/checkpoint storage migrációt.
6. Készíts golden és route teszteket UI-01–UI-04 minden releváns állapotára.

## Kötelező tesztek
- Bootstrap routing integration.
- Permission denied/permanently denied.
- Onboarding resume.
- Golden en/hu, dark/light, compact.
- Mic release route leave.

## Elfogadási feltételek
- [ ] Nincs permission request kontextus nélkül.
- [ ] Onboarding kihagyása nem blokkol core appot, ha termékdöntés szerint engedett.
- [ ] Safe mode nem töröl adatot.
- [ ] First-win nem jelent sikert alacsony signalnál.
- [ ] Mikrofon felszabadul.

## Javasolt branch
`codex/ch13-r16-launch-recovery-es-onboarding-migracio`

## Javasolt commit
`refactor(onboarding): implement accessible first-run experience`

---
# Kör 17 — Today Practice és Profile hubok

## Cél
UI-05–UI-07 cél hubok bevezetése feature flaggel és legacy tartalmak fokozatos összefogásával.

## Függőségek
- Kör 8 adaptive navigation.
- Kör 10–15 komponensek.
- Chapter 8 plan data, Chapter 9 gamification data.

## Fő érintett területek
- `lib/features/today/`
- `lib/features/practice_hub/`
- `lib/features/profile_hub/`
- `test/features/today/`
- `test/features/profile/`

## Feladatok
1. Implementáld a Today Hub summary-first layoutját fake/repository interfészekkel.
2. Implementáld a Practice Hub katalógus- és quick-tool struktúráját capability gate-ekkel.
3. Implementáld a Profile Hub local-only, signed-in és community-enabled állapotait.
4. Készíts adaptert a meglévő Live/Analyze/Learn/Library/Settings route-okhoz.
5. Adj offline cached, no-plan, new-user, sync-pending és feature-disabled állapotokat.
6. Készíts compact, medium és expanded goldeneket.

## Kötelező tesztek
- Hub state widget tesztek.
- Navigation target tesztek.
- Offline no-network integration.
- Golden en/hu és text scale.
- Capability disabled Vision card.

## Elfogadási feltételek
- [ ] Today egyértelmű primary CTA-t ad.
- [ ] Practice eszközök két érintésen belül.
- [ ] Profile account nélkül értelmes.
- [ ] Hubok nem indítanak mikrofont/kamerát.
- [ ] Legacy route elérhető marad.

## Javasolt branch
`codex/ch13-r17-today-practice-es-profile-hubok`

## Javasolt commit
`feat(ui): add Today Practice and Profile hubs`

---
# Kör 18 — Live Stage UI migráció

## Cél
UI-08 megvalósítása az új StageScaffold, zenei komponensek és confidence/signal szerződések használatával.

## Függőségek
- Kör 9 StageScaffold.
- Kör 12 cards/badges.
- Chapter 2 audio lifecycle.
- A meglévő Live engine regressziós tesztjei.

## Fő érintett területek
- `lib/features/live/`
- `lib/core/design_system/components/music/`
- `test/features/live/`

## Feladatok
1. Készíts `SsChordHero`, `SsStrumGlyph`, `SsBeatGrid`, `SsTempoDisplay` és `SsSignalQualityIndicator` komponenseket.
2. Migráld a Live screen layoutot portrait, landscape és expanded változatra.
3. Implementáld az idle, starting, listening, low signal, no chord, degraded, paused, finishing és failure state-eket.
4. Throttle-old az accessibility announcementet; a vizuális frame frekvencia maradhat magasabb.
5. Őrizd meg a jelenlegi engine/interface és autoDispose lifecycle viselkedést.
6. Készíts screenshot/golden összehasonlítást a baseline-nal, és dokumentáld az intentional diffet.

## Kötelező tesztek
- Live widget state tesztek.
- Golden teljes theme/layout matrix.
- Mic release navigation/background.
- No DSP parity regression fixture.
- Semantics announcement throttling.

## Elfogadási feltételek
- [ ] A chord és direction messziről olvasható.
- [ ] Confidence nem csak szín.
- [ ] Nincs DSP-paraméterváltozás.
- [ ] Mikrofon minden kilépési útvonalon leáll.
- [ ] Low signal és no chord külön állapot.

## Javasolt branch
`codex/ch13-r18-live-stage-ui-migracio`

## Javasolt commit
`refactor(live): migrate real-time experience to Stage Mode`

---
# Kör 19 — Tuner és Metronome UI migráció

## Cél
UI-09–UI-10 egységes Stage komponensekkel, pontos audio-clock és accessibility viselkedéssel.

## Függőségek
- Kör 9, 11, 18.
- Meglévő Tuner/Metronome engine.

## Fő érintett területek
- `lib/features/tuner/`
- `lib/features/metronome/`
- `test/features/tuner/`
- `test/features/metronome/`

## Feladatok
1. Implementáld az `SsTunerGauge` és tuning/string selector komponenseket.
2. Migráld a Tuner idle/listening/no pitch/unstable/in tune/reference tone állapotait.
3. Migráld a Metronome fő BPM/beat/transport layoutját; advanced settings sheetbe kerül.
4. Kapcsold a beat vizualizációt az audio clock state-hez.
5. Adj landscape/expanded layoutot és keyboard shortcutot, ahol releváns.
6. Biztosítsd a route leave és audio focus cleanupot.

## Kötelező tesztek
- YIN output → UI mapping unit teszt.
- Tuner golden.
- Metronome audio/visual beat sync teszt fake clockkal.
- Route cleanup.
- Text scale/semantics.

## Elfogadási feltételek
- [ ] Cents irány szöveges.
- [ ] In-tune feedback több csatornás.
- [ ] Beat vizualizáció nem külön Timer.
- [ ] Reference tone route leave-kor leáll.
- [ ] Tap tempo outlier kezelése megmarad.

## Javasolt branch
`codex/ch13-r19-tuner-es-metronome-ui-migracio`

## Javasolt commit
`refactor(tools): migrate tuner and metronome interfaces`

---
# Kör 20 — Chord Library Learning Path és Lesson UI

## Cél
UI-11–UI-14 migrációja közös Learning Mode komponensekre, balkezes és offline tartalomtámogatással.

## Függőségek
- Kör 11–15.
- Chapter 3/korábbi Learn és Chord domain modellek.

## Fő érintett területek
- `lib/features/chords/`
- `lib/features/learn/`
- `test/features/chords/`
- `test/features/learn/`

## Feladatok
1. Migráld a Chord Library search/filter/favorites layoutját.
2. Implementáld a Chord Detail diagram, fingering, variation és practice action felületét.
3. Migráld a Learning Pathot lineáris accessibility alternatívával.
4. Implementáld a Lesson Detail readiness, prerequisite, download és progress állapotait.
5. Adj balkezes diagram/fretboard visual és text mapping tesztet.
6. Készíts content missing/offline/locked/migration state-eket.

## Kötelező tesztek
- Search/filter/favorite.
- Chord diagram golden left/right-handed.
- Learning path locked reason.
- Lesson offline asset state.
- ARB/pseudo-locale.

## Elfogadási feltételek
- [ ] A diagramnak text alternatívája van.
- [ ] Locked ok világos.
- [ ] Legacy progress megmarad.
- [ ] Offline hiányzó asset nem omlaszt.
- [ ] Practice CTA helyesen parametrizál.

## Javasolt branch
`codex/ch13-r20-chord-library-learning-path-es-lesson-ui`

## Javasolt commit
`refactor(learn): unify chord and lesson experience`

---
# Kör 21 — Practice setup és aktív session UI

## Cél
UI-18–UI-20 implementálása az új Stage, form és recovery komponensekkel.

## Függőségek
- Chapter 3 Practice Engine domain/state machine.
- Kör 9–13.

## Fő érintett területek
- `lib/features/practice/`
- `test/features/practice/session/`

## Feladatok
1. Implementáld a Practice Session Setup paraméter-, readiness- és permission felületét.
2. Implementáld a Practice Session Stage layoutot gyakorlat-specifikus slotokkal.
3. Implementáld a Pause & Recovery overlayt user/system interruption állapotokkal.
4. Kapcsold a UI-t a meglévő vagy Chapter 3 szerinti session state machine-hez; ne tárolj business state-et widgetben.
5. Adj wrong tuning, degraded capability, low signal és background recovery state-et.
6. Készíts fake clock/engine alapú determinisztikus widget és navigation teszteket.

## Kötelező tesztek
- Setup validation.
- Permission/tuning flow.
- Session state transitions.
- Back confirmation.
- Golden portrait/landscape.
- Result exactly-once navigation.

## Elfogadási feltételek
- [ ] Session indítás reprodukálható configból.
- [ ] Pause/Resume nem duplikál eventet.
- [ ] Stage feedback stabil.
- [ ] Kilépésnél adatvesztési következmény világos.
- [ ] A UI nem blokkolja a DSP-t.

## Javasolt branch
`codex/ch13-r21-practice-setup-es-aktiv-session-ui`

## Javasolt commit
`feat(practice): implement setup active and recovery interfaces`

---
# Kör 22 — Practice result history és Speed Builder UI

## Cél
UI-21–UI-23 summary-first eredmény-, history- és tempóprogressziós felületeinek megvalósítása.

## Függőségek
- Kör 21.
- Chapter 3 result és Speed Builder modellek.
- Chapter 7 Analysis metric komponensek.

## Fő érintett területek
- `lib/features/practice/results/`
- `lib/features/practice/history/`
- `lib/features/practice/speed_builder/`
- `test/features/practice/`

## Feladatok
1. Implementáld a Practice Result metric/insight/next-action layoutját confidence-aware módon.
2. Migráld a Practice History szűrhető, corrupt-record-isolating listáját.
3. Implementáld a Speed Builder setup, active és result layoutját.
4. Adj share, tutor és remediation route mappinget.
5. Integráld a reward summaryt idempotens ledger eredményből, nem UI-oldali számítással.
6. Készíts insufficient signal, partial session és offline sync state-eket.

## Kötelező tesztek
- Result low-confidence/partial.
- History corrupt record.
- Speed ladder transitions.
- Share route payload.
- Golden en/hu compact/expanded.

## Elfogadási feltételek
- [ ] Low confidence nem kategorikus.
- [ ] History offline elérhető.
- [ ] Speed Builder best stable BPM-et mutat.
- [ ] Reward nem duplikálódik újranyitáskor.
- [ ] Next action végrehajtható.

## Javasolt branch
`codex/ch13-r22-practice-result-history-es-speed-builder-ui`

## Javasolt commit
`feat(practice): complete results history and speed builder UX`

---
# Kör 23 — Song Library Overview és Setlist list UI

## Cél
UI-24–UI-25 és UI-32 alap Songs hub tartalmak implementálása offline readiness és source/licence jelöléssel.

## Függőségek
- Chapter 4 SongDocument és repository.
- Kör 8, 10–15.

## Fő érintett területek
- `lib/features/songs/library/`
- `lib/features/songs/overview/`
- `lib/features/setlists/`
- `test/features/songs/`

## Feladatok
1. Migráld a Song Libraryt continue, search, filter, source és readiness komponensekkel.
2. Implementáld a Song Overview section/progress/tuning/asset és primary practice action felületét.
3. Migráld a Setlist Listet readiness és missing-song state-ekkel.
4. Adj compact list és expanded list-detail layoutot.
5. Implementáld a community/read-only source, offline asset missing és update available állapotokat.
6. Készíts route alias tesztet a meglévő songs/setlists útvonalakról.

## Kötelező tesztek
- Song search/filter.
- Offline asset status.
- Read-only source.
- Setlist missing song.
- Golden compact/expanded.

## Elfogadási feltételek
- [ ] Local song offline elérhető.
- [ ] Source/licence státusz látható.
- [ ] Hiányzó backing track nem rejti el a többi tartalmat.
- [ ] Setlist sorrend és readiness helyes.
- [ ] Legacy route működik.

## Javasolt branch
`codex/ch13-r23-song-library-overview-es-setlist-list-ui`

## Javasolt commit
`refactor(songs): add adaptive library overview and setlists`

---
# Kör 24 — Song import preview és editor UI

## Cél
UI-26–UI-28 biztonságos import-, mapping- és strukturált szerkesztési felületének elkészítése.

## Függőségek
- Chapter 4 import pipeline.
- Kör 11–15.
- Kör 23.

## Fő érintett területek
- `lib/features/songs/import/`
- `lib/features/songs/editor/`
- `test/features/songs/import/`

## Feladatok
1. Implementáld a Song Import idle/picking/copying/detecting/parsing/cancel/failure flow-t.
2. Implementáld az Import Preview track selection, warning és blocking error felületét.
3. Implementáld a Song Editor compact structured és expanded multi-pane layoutját.
4. Adj unsaved draft, read-only source, conflict, undo/redo és save failure state-et.
5. Biztosíts drag műveletekhez billentyű/gomb alternatívát.
6. Készíts malicious/large/unsupported fixture UI integration teszteket a parser eredményeivel.

## Kötelező tesztek
- Import progress/cancel.
- Warning/blocking mapping.
- Editor unsaved leave.
- Undo/redo.
- Read-only copy.
- Accessibility keyboard flow.

## Elfogadási feltételek
- [ ] Import megszakítható és temp file takarított.
- [ ] Blocking error nem kerülhető meg.
- [ ] Draft mentési hiba után megmarad.
- [ ] Read-only forrás csak másolható.
- [ ] A preview nem publikál semmit.

## Javasolt branch
`codex/ch13-r24-song-import-preview-es-editor-ui`

## Javasolt commit
`feat(songs): build safe import preview and editor UX`

---
# Kör 25 — Song Trainer Result és Setlist Run UI

## Cél
UI-29–UI-31 és UI-33 teljes Stage/Analytics flow implementálása szinkron-, loop- és playback-only állapotokkal.

## Függőségek
- Kör 23–24.
- Chapter 4 playback/scoring state.
- Kör 9 StageScaffold.

## Fő érintett területek
- `lib/features/songs/trainer/`
- `lib/features/songs/results/`
- `lib/features/setlists/run/`
- `test/features/songs/trainer/`

## Feladatok
1. Implementáld a Song Trainer Setup section, speed, loop, backing mix és scoring readiness felületét.
2. Implementáld a Song Trainer portrait/landscape/expanded notation + playhead Stage layoutját.
3. Implementáld a Song Result section breakdown, difficult section és remediation action felületét.
4. Implementáld a Setlist Detail és continuous Run state-et tuning transitionnel.
5. Adj playback-only, low signal, asset missing, audio failure és resume state-eket.
6. Készíts fake playback clockkal audio/playhead és loop UI szinkrontesztet.

## Kötelező tesztek
- Setup validation.
- Playhead/loop fake-clock sync.
- Orientation state preservation.
- Playback-only result.
- Setlist transition.
- Golden landscape/expanded.

## Elfogadási feltételek
- [ ] Playback-only nem kap hamis score-t.
- [ ] Pause pontos helyről folytat.
- [ ] Loop vizuális és playback határ egyezik.
- [ ] Setlist tuningváltás előre jelzett.
- [ ] Stage route-ok cleanupja zöld.

## Kockázatok és korlátok
- A notation viewport teljesítménye külön profilozandó nagy dalnál.

## Javasolt branch
`codex/ch13-r25-song-trainer-result-es-setlist-run-ui`

## Javasolt commit
`feat(songs): complete trainer results and setlist run UX`

---
# Kör 26 — Analyze Home Recording és Processing UI

## Cél
UI-34–UI-36 implementálása egyértelmű raw-audio retentionnel, valós progress-szel és megszakítható elemzéssel.

## Függőségek
- Chapter 7 Analysis job/lifecycle.
- Kör 9–15.

## Fő érintett területek
- `lib/features/analyze/home/`
- `lib/features/analyze/recording/`
- `lib/features/analyze/processing/`
- `test/features/analyze/`

## Feladatok
1. Implementáld az Analyze Home input módjait és recent analysis preview-ját.
2. Migráld a recording Stage felületet signal quality, clipping, silence, storage és retention jelzéssel.
3. Implementáld a processing stage progress és thermal/battery degraded állapotot.
4. Adj cancel/checkpoint/restart recovery flow-t.
5. Kapcsold a microphone permission gateway és audio session coordinator állapotaihoz.
6. Készíts file input, unsupported format és low storage UI teszteket.

## Kötelező tesztek
- Permission/record/stop.
- Clipping/silence.
- Low storage.
- Processing stage/cancel/checkpoint.
- Golden Stage és system state.
- Mic/temp file cleanup.

## Elfogadási feltételek
- [ ] A recording indicator állandó.
- [ ] Nincs hamis százalék.
- [ ] Cancel idempotens.
- [ ] Raw audio retention végig látható.
- [ ] Hiba után nincs árva mic vagy temp file.

## Javasolt branch
`codex/ch13-r26-analyze-home-recording-es-processing-ui`

## Javasolt commit
`refactor(analyze): implement recording and processing experience`

---
# Kör 27 — Analysis Overview Timeline Metric és Compare UI

## Cél
UI-37–UI-39 teljes Studio Analytics rendszerének megvalósítása confidence-aware, virtualizált és hozzáférhető adatvizualizációval.

## Függőségek
- Kör 12 analytics komponensek.
- Chapter 7 AnalysisResultV2.
- Kör 26.

## Fő érintett területek
- `lib/features/analyze/results/`
- `lib/core/design_system/components/analytics/`
- `test/features/analyze/results/`

## Feladatok
1. Implementáld a score ring, metric card, trend, confidence legend és insight komponenseket.
2. Implementáld az Analysis Overview summary-first layoutját partial/unsupported metric állapotokkal.
3. Implementáld a virtualizált Timeline, waveform, overlay, selection és event inspector felületét.
4. Implementáld a Metric Detail és session compare kompatibilitási szabályait.
5. Adj chart text summary és event list accessibility alternatívát.
6. Készíts nagy fixture-ös performance és scroll/pan tesztet.

## Kötelező tesztek
- Metric N/A/low-confidence.
- Timeline virtualization.
- Audio/playhead sync.
- Selection → practice route.
- Compare incompatible versions.
- Chart semantics.
- Golden compact/expanded.

## Elfogadási feltételek
- [ ] Hiányzó metric nem 0.
- [ ] Timeline nagy file-nál is használható.
- [ ] Confidence látható.
- [ ] Chart summary elérhető.
- [ ] Comparison csak kompatibilis adat között.

## Javasolt branch
`codex/ch13-r27-analysis-overview-timeline-metric-es-compare-ui`

## Javasolt commit
`feat(analysis): deliver accessible Studio Analytics interface`

---
# Kör 28 — Unified Library és Session Detail UI

## Cél
UI-40–UI-41 egységes item union, storage/sync státusz és biztonságos adatkezelés megvalósítása.

## Függőségek
- Chapter 2 repository/storage migration.
- Kör 17 Profile Hub.
- Kör 22–27 result route-ok.

## Fő érintett területek
- `lib/features/library_v2/`
- `test/features/library_v2/`

## Feladatok
1. Implementáld a Unified Library search/filter/list-detail felületét type-safe item routinggal.
2. Implementáld a Session Detail metadata, result preview, notes, export, compare és delete actionjait.
3. Adj corrupt item isolation, storage near limit, local/cloud és sync conflict state-et.
4. Készíts storage management belépési pontot, de a tényleges törlési logikát repository use case végzi.
5. Migráld a legacy Library route-ot adapterrel.
6. Adj pagination, stable scroll és offline cached teszteket.

## Kötelező tesztek
- Item union routing.
- Corrupt record.
- Offline content.
- Delete confirmation.
- Rename identity.
- Sync conflict.
- Golden list-detail.

## Elfogadási feltételek
- [ ] Corrupt item nem töri a listát.
- [ ] Local tartalom offline megnyitható.
- [ ] Törlés scope-ja világos.
- [ ] Nyers asset hiánya mellett result megmarad.
- [ ] Legacy route nem törik.

## Javasolt branch
`codex/ch13-r28-unified-library-es-session-detail-ui`

## Javasolt commit
`refactor(library): unify saved content and session details`

---
# Kör 29 — Coach Home Tutor és Debrief UI

## Cél
UI-42–UI-44 provenance-aware AI coaching, streaming, evidence és tool-confirmation felületének elkészítése.

## Függőségek
- Chapter 5 AI Guitar Teacher.
- Kör 12–13 AI komponensek.
- Kör 27 evidence UI.

## Fő érintett területek
- `lib/features/coach/`
- `lib/features/tutor/`
- `test/features/tutor/`

## Feladatok
1. Implementáld a Coach Home local/cloud/fallback és model missing állapotait.
2. Implementáld a Tutor Conversation streaming message, composer, conversation list és evidence pane layoutját.
3. Implementáld a Debrief/Plan Preview observation–cause–action és plan diff struktúráját.
4. Kapcsold minden tool actiont `SsToolConfirmationSheet`-hez; public/destructive/capture action soha ne fusson közvetlenül.
5. Adj streaming cancel, network loss, local fallback és tool result state-et.
6. Készíts prompt/tool injection UI integration fixture-t, amely igazolja, hogy nincs automatikus execution.

## Kötelező tesztek
- Local/cloud/fallback.
- Streaming cancel.
- Evidence missing.
- Tool confirmation exactly-once.
- Plan diff accept/reject.
- Chat semantics.
- Golden compact/expanded.

## Elfogadási feltételek
- [ ] AI mód mindig látható.
- [ ] Streaming nem spamli a screen readert.
- [ ] Tool action confirmationt kér.
- [ ] Plan mutation explicit.
- [ ] Chat tartalma nem kerül analyticsbe.

## Javasolt branch
`codex/ch13-r29-coach-home-tutor-es-debrief-ui`

## Javasolt commit
`feat(coach): implement evidence-based tutor and debrief UX`

---
# Kör 30 — Vision Setup Coach és Result UI

## Cél
UI-45–UI-47 kamera-, kalibráció-, live cue- és result felületének megvalósítása privacy és thermal védelemmel.

## Függőségek
- Chapter 6 Computer Vision.
- Kör 9 StageScaffold.
- Kör 10 permission.
- Kör 29 coach action.

## Fő érintett területek
- `lib/features/vision/`
- `test/features/vision/`

## Feladatok
1. Implementáld a Vision Setup permission primer, placement guide, preview és calibration readiness felületét.
2. Implementáld a Vision Coach egy-cue Stage layoutot, low light/occlusion/lost tracking/thermal/audio-only state-ekkel.
3. Implementáld a Vision Result tracking quality, technique metric és remediation layoutját.
4. Biztosíts Lab-only debug skeleton flaget; productionben rejtett.
5. Adj kamera és mikrofon indicator, route cleanup és frame-retention státuszt.
6. Készíts fake frame stream és thermal state alapú determinisztikus widget teszteket.

## Kötelező tesztek
- Permission denied/permanently denied.
- Calibration readiness.
- Lost tracking/thermal degrade.
- One-cue invariant.
- Camera/mic cleanup.
- Golden portrait/landscape.

## Elfogadási feltételek
- [ ] Kamera csak explicit action után.
- [ ] Egyszerre egy prioritásos cue.
- [ ] Low confidence nem kategorikus.
- [ ] Frame alapból nem mentődik.
- [ ] Unsupported device audio-only alternatívát kap.

## Javasolt branch
`codex/ch13-r30-vision-setup-coach-es-result-ui`

## Javasolt commit
`feat(vision): deliver private adaptive coaching interface`

---
# Kör 31 — Progress Dashboard és Skill Detail UI

## Cél
UI-49–UI-50 hosszú távú, evidence-alapú fejlődési felületének kialakítása.

## Függőségek
- Chapter 3/7 progress és metric modellek.
- Kör 27 analytics komponensek.
- Kör 17 Profile Hub.

## Fő érintett területek
- `lib/features/progress_v2/`
- `test/features/progress_v2/`

## Feladatok
1. Implementáld a Progress Dashboard new-user, trend, offline és migration állapotait.
2. Implementáld a Skill Detail mastery, prerequisite, evidence és next-action felületét.
3. Adj timeframe, goal és export kontrollokat.
4. Biztosíts chart summaryt és skill graph lineáris accessibility alternatívát.
5. Kapcsold az evidence linkeket a megfelelő session route-hoz.
6. Készíts metric version migration és insufficient-data UI teszteket.

## Kötelező tesztek
- New user empty state.
- Trend minimum data.
- Metric migration.
- Skill evidence route.
- Chart semantics.
- Golden compact/expanded.

## Elfogadási feltételek
- [ ] Mastery nem XP-alapú.
- [ ] Hiányzó adat nem 0.
- [ ] Evidence auditálható.
- [ ] Offline progress látható.
- [ ] Ajánlás skill dependencyt tiszteletben tart.

## Javasolt branch
`codex/ch13-r31-progress-dashboard-es-skill-detail-ui`

## Javasolt commit
`feat(progress): add evidence-based dashboard and skill detail`

---
# Kör 32 — Gamification Hub Quest Achievement és Reward UI

## Cél
UI-51–UI-52 együttérző, idempotens jutalmazási felületének megvalósítása.

## Függőségek
- Chapter 9 Gamification ledger.
- Kör 17 Profile Hub.
- Kör 12 cards/badges.

## Fő érintett területek
- `lib/features/gamification/`
- `test/features/gamification/ui/`

## Feladatok
1. Implementáld a Gamification Hub level, XP, streak, quest és reward summary layoutját.
2. Implementáld a részletes Quests/Achievements/Inbox tabokat.
3. Adj rest day, grace, streak ended, offline ledger, pending claim és integrity review state-et.
4. Kapcsold a claim actiont idempotens use case-hez; UI ne számítson jutalmat.
5. Implementáld reduced-motion celebration és no-animation alternatívát.
6. Készíts compassionate microcopy és localization teszteket.

## Kötelező tesztek
- Offline duplicate claim.
- Streak rest/grace/end.
- Reward pending/claimed.
- Reduced motion.
- Golden en/hu.

## Elfogadási feltételek
- [ ] Nincs büntető streak nyelv.
- [ ] Claim idempotens.
- [ ] Reward forrás auditálható.
- [ ] Nincs pay-to-preserve pattern.
- [ ] Achievement feltétel érthető.

## Javasolt branch
`codex/ch13-r32-gamification-hub-quest-achievement-es-reward-ui`

## Javasolt commit
`feat(gamification): build compassionate reward experience`

---
# Kör 33 — Community profil feed search és poszt UI

## Cél
UI-53–UI-58 opcionális community onboarding, feed, discovery, profile, composer és discussion felületeinek elkészítése.

## Függőségek
- Chapter 10 Community backend/domain.
- Kör 10–15.
- Kör 17 Profile Hub.

## Fő érintett területek
- `lib/features/community/profile/`
- `lib/features/community/feed/`
- `lib/features/community/posts/`
- `test/features/community/`

## Feladatok
1. Implementáld a Community Gate/Public Profile Setup default-private flow-t.
2. Implementáld a Feed content/offline/removed/moderation state-eket.
3. Implementáld a Search/Discovery és Public Profile relationship/safety actionokat.
4. Implementáld a Post Composer audience, attachment, practice share és offline queue felületét.
5. Implementáld a Post Detail, reactions, comments és thread state-et.
6. Adj block/mute azonnali local filteringet és idempotency key vizualizáció nélküli transportját.

## Kötelező tesztek
- Community optional gate.
- Handle validation.
- Offline feed cache.
- Block/mute.
- Composer audience/redaction.
- Offline publish retry.
- Comment idempotency.
- Golden compact/expanded.

## Elfogadási feltételek
- [ ] Core app community nélkül működik.
- [ ] Default audience nem public.
- [ ] Removed content placeholder.
- [ ] Raw practice data nem implicit share.
- [ ] Block azonnal hat.
- [ ] Retry nem duplikál posztot/kommentet.

## Javasolt branch
`codex/ch13-r33-community-profil-feed-search-es-poszt-ui`

## Javasolt commit
`feat(community): implement optional profiles feed and posting UX`

---
# Kör 34 — Community challenges clubs notifications és safety UI

## Cél
UI-59–UI-61 challenge, leaderboard, club, notification és safety felületeinek implementálása.

## Függőségek
- Kör 33.
- Chapter 9/10 challenge és moderation szerződések.

## Fő érintett területek
- `lib/features/community/challenges/`
- `lib/features/community/clubs/`
- `lib/features/community/safety/`
- `test/features/community/`

## Feladatok
1. Implementáld a Challenge list/detail, join confirmation, verification és leaderboard layoutot.
2. Implementáld a Clubs public/private/join-request/member/moderator/archived state-eket.
3. Implementáld a Notifications és Safety Center list-detail felületét.
4. Adj blocked/muted list, report status és notification preference kezelést.
5. Biztosíts anti-cheat/integrity review neutrális microcopyt.
6. Készíts pagination, offline cache, deep-link validation és permission policy teszteket.

## Kötelező tesztek
- Challenge eligibility/join.
- Pending vs verified.
- Leaderboard pagination.
- Private club leakage.
- Block/mute sync.
- Notification deep link.
- Safety semantics.

## Elfogadási feltételek
- [ ] Leaderboard opt-in.
- [ ] Pending entry nem verified.
- [ ] Private club tartalom nem szivárog.
- [ ] Safety action elérhető.
- [ ] Notification link biztonságosan validált.

## Javasolt branch
`codex/ch13-r34-community-challenges-clubs-notifications-es-safe`

## Javasolt commit
`feat(community): add challenges clubs and safety center`

---
# Kör 35 — Account Settings Privacy Offline AI és Share UI

## Cél
UI-48 és UI-62–UI-65 rendszerfelületeinek egységes, biztonságos implementációja.

## Függőségek
- Chapter 2 auth/settings/storage.
- Chapter 11 Offline AI.
- Kör 11–15.
- Kör 33 community share.

## Fő érintett területek
- `lib/features/auth/`
- `lib/features/settings/`
- `lib/features/offline_ai/`
- `lib/features/share/`
- `test/features/settings/`

## Feladatok
1. Migráld a Login/Register formot opcionális account és biztonságos error presentation szerint.
2. Migráld a Settings kategória/list-detail szerkezetet és keresést.
3. Implementáld a Privacy/Data/Consent Centert inventory, export, delete és policy state-ekkel.
4. Implementáld az Offline AI Model Managert download/verify/activate/rollback/storage állapotokkal.
5. Implementáld a Share Preview redaction, format és audience felületét.
6. Adj storage/network failure, restart-required, low storage, checksum failure, export/delete job és offline queue teszteket.

## Kötelező tesztek
- Auth validation/security states.
- Settings persistence failure.
- Consent withdraw.
- Model checksum/rollback.
- Share redaction/audience.
- Golden full matrix kritikus képernyőkön.

## Elfogadási feltételek
- [ ] Account nélkül exit elérhető.
- [ ] Privacy nem rejtett.
- [ ] Modell signature nélkül nem aktiválható.
- [ ] Share alapból minimális adat.
- [ ] Destruktív data action explicit és auditálható.

## Javasolt branch
`codex/ch13-r35-account-settings-privacy-offline-ai-es-share-ui`

## Javasolt commit
`refactor(system-ui): unify account privacy models and sharing`

---
# Kör 36 — Visual regression device acceptance és migráció lezárása

## Cél
A Chapter 13 teljes UI-rendszerének minőségkapus lezárása, legacy dependencyk csökkentése és valós eszközös elfogadása.

## Függőségek
- Kör 1–35.
- Chapter 12 release gates.

## Fő érintett területek
- `test/goldens/`
- `test/accessibility/`
- `docs/ui/`
- `tool/check_ui_architecture.dart`
- `HANDOFF.md`

## Feladatok
1. Futtasd és stabilizáld a kockázatalapú golden matrixot dark/light/high-contrast, en/hu, compact/landscape/medium/expanded és kritikus text-scale kombinációkban.
2. Futtasd a teljes semantics, tap target, overflow, route, permission és state restoration tesztcsomagot.
3. Végezz valós eszköztesztet Live, Tuner, Practice, Song Trainer, Analyze, Tutor, Vision, Settings és Privacy flow-kon.
4. Mérd a UI frame time-ot aktív Live/Song/Vision sessionben; a design refaktor nem ronthatja indokolatlanul a DSP/ML latencyt.
5. Csökkentsd vagy zárd le a legacy theme/route/import allowlistet; megmaradt elemekhez adj dátumozott backlogot.
6. Készíts `docs/ui/chapter-13-completion-report.md` jelentést intentional golden diffekkel, ismert korlátokkal és release ajánlással.

## Kötelező tesztek
- `dart format --output=none --set-exit-if-changed lib test tool`
- `flutter analyze lib/ test/ tool/`
- `flutter test`
- `flutter test --tags=golden`
- Architecture/UI token guard.
- Valós eszköz checklist aláírt eredménnyel.

## Elfogadási feltételek
- [ ] Minden kritikus képernyő rendelkezik loading/empty/error/offline/permission állapottal, ahol releváns.
- [ ] A teljes golden gate zöld és a diff manuálisan elfogadott.
- [ ] Nincs ismert mic/camera lifecycle regresszió.
- [ ] 200% text scale és screen-reader kritikus flow működik.
- [ ] Legacy route-ok dokumentáltak vagy biztonságosan migráltak.
- [ ] A completion report elkészült.

## Kockázatok és korlátok
- A golden teszt platformonként eltérhet; rögzített font/render környezet szükséges.
- Valós kamera/audio teljesítmény nem igazolható kizárólag emulatoron.

## Javasolt branch
`codex/ch13-r36-visual-regression-device-acceptance-es-migracio`

## Javasolt commit
`docs(ui): close Chapter 13 design system migration`

---
# 27. Képernyőindex

| ID | Képernyő | Célroute | UI-mód | Owner |
|---|---|---|---|---|
| UI-01 | Launch & Bootstrap | `/launch` | System | App/Core Platform |
| UI-02 | Recovery & Safe Mode | `/recovery` | System | App/Core Platform |
| UI-03 | Onboarding — Value & Privacy | `/onboarding/value` | Learning | Onboarding |
| UI-04 | Onboarding — First Win & Microphone Primer | `/onboarding/first-win` | Stage + Learning | Onboarding / Live |
| UI-05 | Today Hub | `/today` | Learning | Home / Practice Generator |
| UI-06 | Practice Hub | `/practice` | Learning | Practice |
| UI-07 | Profile Hub | `/profile` | Learning + Community | Profile |
| UI-08 | Live Stage | `/practice/live` | Stage | Live |
| UI-09 | Tuner | `/practice/tuner` | Stage | Tuner |
| UI-10 | Metronome | `/practice/metronome` | Stage | Metronome |
| UI-11 | Chord Library | `/practice/chords` | Learning | Chords |
| UI-12 | Chord Detail | `/practice/chords/:chordId` | Learning | Chords |
| UI-13 | Learning Path | `/practice/learn` | Learning | Learn |
| UI-14 | Lesson Detail | `/practice/learn/:lessonId` | Learning | Learn |
| UI-15 | Practice Plan Setup | `/coach/plan/setup` | Coach + Learning | AI Practice Generator |
| UI-16 | Weekly Practice Plan | `/coach/plan` | Learning + Coach | AI Practice Generator |
| UI-17 | Today Plan Detail | `/today/plan` | Learning | AI Practice Generator / Today |
| UI-18 | Practice Session Setup | `/practice/session/setup` | Learning | Practice Engine |
| UI-19 | Practice Session | `/practice/session/:sessionId` | Stage | Practice Engine |
| UI-20 | Practice Pause & Recovery | `/practice/session/:sessionId/pause` | Stage Overlay | Practice Engine |
| UI-21 | Practice Result | `/practice/session/:sessionId/result` | Studio Analytics | Practice Engine / Analysis |
| UI-22 | Practice History | `/practice/history` | Studio Analytics | Practice / Progress |
| UI-23 | Speed Builder | `/practice/speed-builder` | Stage + Learning | Practice Engine |
| UI-24 | Song Library | `/songs` | Learning | Song Trainer |
| UI-25 | Song Overview | `/songs/:songId` | Learning | Song Trainer |
| UI-26 | Song Import | `/songs/import` | System + Learning | Song Trainer |
| UI-27 | Import Preview & Mapping | `/songs/import/preview/:importId` | Learning | Song Trainer |
| UI-28 | Song Editor | `/songs/:songId/edit` | Studio | Song Trainer |
| UI-29 | Song Trainer Setup | `/songs/:songId/train/setup` | Learning | Song Trainer |
| UI-30 | Song Trainer | `/songs/:songId/train` | Stage | Song Trainer |
| UI-31 | Song Result | `/songs/:songId/result/:sessionId` | Studio Analytics | Song Trainer / Analysis |
| UI-32 | Setlist List | `/songs/setlists` | Learning | Song Trainer |
| UI-33 | Setlist Detail & Run | `/songs/setlists/:setlistId` | Learning + Stage | Song Trainer |
| UI-34 | Analyze Home | `/practice/analyze` | Studio Analytics | Audio Analysis |
| UI-35 | Analysis Recording & Input | `/practice/analyze/record` | Stage | Audio Analysis |
| UI-36 | Analysis Processing | `/practice/analyze/:analysisId/processing` | System | Audio Analysis |
| UI-37 | Analysis Overview | `/library/analysis/:analysisId` | Studio Analytics | Audio Analysis |
| UI-38 | Analysis Timeline | `/library/analysis/:analysisId/timeline` | Studio Analytics | Audio Analysis |
| UI-39 | Metric Detail & Session Compare | `/progress/metric/:metricId` | Studio Analytics | Progress / Audio Analysis |
| UI-40 | Unified Library | `/profile/library` | Studio | Library |
| UI-41 | Session Detail | `/profile/library/session/:sessionId` | Studio Analytics | Library / Practice / Analysis |
| UI-42 | Coach Home | `/coach` | Coach | AI Guitar Teacher |
| UI-43 | Tutor Conversation | `/coach/tutor/:conversationId?` | Coach | AI Guitar Teacher |
| UI-44 | Session Debrief & Plan Preview | `/coach/debrief/:sessionId` | Coach + Studio Analytics | AI Guitar Teacher / Practice Generator |
| UI-45 | Vision Setup & Calibration | `/coach/vision/setup` | Coach | Computer Vision |
| UI-46 | Vision Coach | `/coach/vision/session/:sessionId` | Stage + Coach | Computer Vision |
| UI-47 | Vision Result | `/coach/vision/result/:sessionId` | Studio Analytics + Coach | Computer Vision |
| UI-48 | Offline AI Model Manager | `/profile/settings/offline-ai` | System + Coach | Offline AI |
| UI-49 | Progress Dashboard | `/profile/progress` | Studio Analytics | Progress |
| UI-50 | Skill Detail | `/profile/progress/skills/:skillId` | Studio Analytics + Learning | Progress / Learn |
| UI-51 | Gamification Hub & Streak | `/profile/rewards` | Learning | Gamification |
| UI-52 | Achievements, Quests & Reward Inbox | `/profile/rewards/details` | Learning | Gamification |
| UI-53 | Community Gate & Public Profile Setup | `/profile/community/setup` | Community | Community |
| UI-54 | Community Feed | `/community` | Community | Community |
| UI-55 | Community Search & Discovery | `/community/search` | Community | Community |
| UI-56 | Public Community Profile | `/community/users/:userId` | Community | Community |
| UI-57 | Post Composer & Share Practice | `/community/posts/new` | Community | Community |
| UI-58 | Post Detail & Comments | `/community/posts/:postId` | Community | Community |
| UI-59 | Community Challenges & Leaderboards | `/community/challenges` | Community + Gamification | Community / Gamification |
| UI-60 | Clubs & Group Detail | `/community/clubs/:clubId?` | Community | Community |
| UI-61 | Notifications, Blocking & Safety Center | `/profile/community/safety` | Community + System | Community / Safety |
| UI-62 | Login & Registration | `/profile/account/login` | System | Auth |
| UI-63 | Settings | `/profile/settings` | System | Settings |
| UI-64 | Privacy, Data & Consent Center | `/profile/settings/privacy` | System | Privacy / Settings |
| UI-65 | Share Preview & Export | `/share/preview` | System + Community | Share |

# 28. Legacy migrációs stratégia

## 28.1 Strangler pattern

A UI-migráció nem teljes újraírás. Minden legacy képernyő a következő sorrendben migrál:

1. Baseline screenshot és teszt.
2. Presentation state szerződés tisztázása.
3. Közös design-system komponensek bevezetése.
4. Layout migráció feature flag mögött.
5. Golden és accessibility ellenőrzés.
6. Route alias/redirect ellenőrzés.
7. Feature flag fokozatos bekapcsolása.
8. Legacy widget és import eltávolítása.
9. Allowlist csökkentése.
10. Completion report frissítése.

## 28.2 Tilos

- egyszerre minden screen új fájlstruktúrába mozgatása;
- DSP vagy ML eredmény megváltoztatása azért, hogy „jobban nézzen ki”;
- domain modellek UI-kedvéért gyengítése;
- golden fájlok vak frissítése;
- route eltávolítása deprecation nélkül;
- hardcoded UI újrakódolása teszt nélkül;
- account/community követelmény bevezetése offline core funkcióhoz;
- accessibility „későbbre” halasztása.

## 28.3 Feature flag javaslat

```text
ui.design_system_v2
ui.navigation_v2
ui.today_hub
ui.practice_hub
ui.profile_hub
ui.live_stage_v2
ui.song_trainer_v2
ui.analysis_v2
ui.coach_v2
ui.vision_v2
ui.community_v2
```

A flag:

- environment vagy remote config szerint értelmezhető;
- productionben fail-safe defaulttal rendelkezik;
- nem kerülhet per-frame ellenőrzésre;
- nem okozhat eltérő adatmodellt ugyanahhoz a sessionhöz;
- rollbackkor megőrzi a felhasználói adatot.

---

# 29. UI teljesítménykövetelmények

## 29.1 Általános

- Görgetés célérték: stabil 60 Hz, magas frissítésű eszközön platformhoz illeszkedő.
- Aktív audio/vision sessionben a UI nem blokkolhatja az input feldolgozó isolate-ot.
- Listák és timeline-ok virtualizáltak.
- Nagy képek és community média méretezett, cache-elt thumbnailt használnak.
- Skeleton nem indít extra hálózati kérést.
- Build metódusban nincs drága parser, file IO vagy inference.
- Provider watch scope minimális.
- Gyorsan változó LiveFrame csak a szükséges widgeteket építi újra.
- Chart animáció korlátozható vagy kikapcsolható.
- Route transition nem tart vissza erőforrás-felszabadítást.

## 29.2 Stage Mode

- Chord/strum visual update nem okozhat teljes screen rebuildet.
- Beat indicator audio clockhoz kötött.
- Waveform/timeline rajzolás CustomPainter vagy megfelelően optimalizált megoldás.
- Kamera overlay és preview külön compositing layerben, ahol célszerű.
- Thermal degrade esetén a UI kevesebb overlay-frissítést fogad.
- Semantics update ritkított.

## 29.3 Mérési kötelezettség

Mérendő legalább:

- cold és warm screen transition;
- Live first meaningful frame;
- Live átlagos és P95 frame time;
- Song Trainer scroll/playhead frame time;
- Analysis Timeline 10, 30 és 60 perces fixture-rel;
- Community feed image memory;
- Vision preview + overlay;
- text scale 2.0 layout build;
- theme switch;
- model manager download progress.

A Chapter 13 nem állapít meg mesterséges univerzális milliszekundum-célt minden eszközre. A Chapter 2/12 baseline-hoz képest regressziót kell mérni, és a release device tierenként kap minőségkaput.

---

# 30. Security és privacy UI checklist

- [ ] Minden capture képernyő mutat microphone/camera indikátort.
- [ ] Permission request előtt van kontextus.
- [ ] Permanently denied esetén Open Settings action.
- [ ] Local AI és Cloud AI megkülönböztetett.
- [ ] Public audience nem alapértelmezett új community profilnál.
- [ ] Share előtt preview és redaction.
- [ ] Destruktív törlés megnevezi a törlendő adatot.
- [ ] Local és cloud delete következménye külön.
- [ ] Token, e-mail, prompt és raw audio nem kerül UI analyticsbe.
- [ ] Moderation action nem fedi fel más felhasználó érzékeny adatait.
- [ ] AI tool action megerősítést kér, amikor szükséges.
- [ ] Model package signature/checksum hiba világos, de nem technikai dump.
- [ ] Offline queue nem jelenít sikeres publikus állapotot szerver visszaigazolás előtt.
- [ ] Deep link jogosultságot és audience-ot validál.
- [ ] Screenshot/share export nem tartalmaz rejtett személyes metadata-t.

---

# 31. Accessibility release checklist

- [ ] TalkBack végigjárható a Today → Practice → Result flow-n.
- [ ] TalkBack végigjárható a Songs → Trainer → Result flow-n.
- [ ] VoiceOver próba megtörtént, amikor iOS build elérhető.
- [ ] Minden interaktív cél legalább 48×48 dp vagy megfelelő semantics hit target.
- [ ] 200% text scale mellett nincs kritikus clipping.
- [ ] Compact landscape támogatott.
- [ ] High Contrast téma teljes.
- [ ] Reduced Motion teljes.
- [ ] Confidence, success, warning és error nem csak szín.
- [ ] Grafikonokhoz text summary.
- [ ] Chord diagramhoz fingering text.
- [ ] Notation/tab képernyőhöz következő ütem/akkord summary.
- [ ] Stage Mode transport fókuszsorrend helyes.
- [ ] Streaming AI nem tokenenként olvasódik fel.
- [ ] Kamera preview nem az egyetlen vision feedback.
- [ ] Keyboard focus látható expanded layoutban.
- [ ] Drag-and-drop/reorder művelethez alternatíva.
- [ ] Haptika és sound cue kikapcsolható.
- [ ] Live regionek nem spamlik a felhasználót.

---

# 32. UI Definition of Ready

Egy képernyő fejlesztése akkor kezdhető el, ha:

- [ ] A képernyő ID és route ismert.
- [ ] A domain/application adatkontraktus létezik vagy explicit mock/fake szerződés készült.
- [ ] Az elsődleges és másodlagos műveletek rögzítettek.
- [ ] Az összes releváns state felsorolt.
- [ ] A permission, privacy, offline és sync következmény tiszta.
- [ ] Compact és expanded layout leírt.
- [ ] A szükséges design-system komponens elérhető vagy az adott kör része.
- [ ] A lokalizációs stringek listája elkészíthető.
- [ ] A golden és widget tesztmatrix ismert.
- [ ] A legacy route/komponens migrációs kockázata dokumentált.
- [ ] A product owner elfogadta az információs prioritást.
- [ ] Nincs nyitott, blokkoló domain bizonytalanság.

---

# 33. UI Definition of Done

Egy képernyő csak akkor kész, ha:

## Funkció

- [ ] Minden elsődleges és másodlagos action működik.
- [ ] Route argumentum típusbiztos és validált.
- [ ] Loading/content/empty/offline/failure state elkészült, ahol releváns.
- [ ] Permission és permanently denied state elkészült, ahol releváns.
- [ ] Background/resume és back viselkedés tesztelt.
- [ ] A data mutation use case-en keresztül történik.
- [ ] Nincs duplán elküldhető művelet.

## Design system

- [ ] Nincs indokolatlan hardcoded szín, spacing, radius vagy TextStyle.
- [ ] A képernyő közös komponenseket használ.
- [ ] Dark Studio, Warm Light és High Contrast támogatott.
- [ ] Compact és legalább egy nagyobb layout támogatott.
- [ ] Reduced motion támogatott.
- [ ] A vizuális hierarchy megfelel a Chapter 13-nak.

## Accessibility

- [ ] Semantics label és heading helyes.
- [ ] Fókuszsorrend helyes.
- [ ] Tap target megfelelő.
- [ ] 200% text scale kritikus state-ben tesztelt.
- [ ] Nem csak szín kommunikál állapotot.
- [ ] Grafikon/diagram alternatíva rendelkezésre áll.
- [ ] TalkBack manuális próba a kritikus flow-ban megtörtént.

## Lokalizáció

- [ ] Minden string ARB-ben.
- [ ] `en` és `hu` parity zöld.
- [ ] Hosszú magyar szöveg nem clipel.
- [ ] Dátum, idő, mértékegység és plural locale-aware.

## Privacy és security

- [ ] Capture indikátor látható, ha releváns.
- [ ] Consent és audience világos.
- [ ] AI provenance látható.
- [ ] Destruktív/public action confirmationt kér.
- [ ] Analytics payload nem tartalmaz érzékeny tartalmat.
- [ ] Offline queue state nem félrevezető.

## Teszt és dokumentáció

- [ ] Widget tesztek zöldek.
- [ ] Navigation/state-restoration tesztek zöldek.
- [ ] Golden teszt zöld és diff felülvizsgált.
- [ ] Semantics/overflow teszt zöld.
- [ ] Valós eszközteszt megtörtént, ha mic/camera/audio/thermal érintett.
- [ ] `docs/ui/migration-status.md` frissült.
- [ ] `HANDOFF.md` frissült.
- [ ] Nincs új, indokolatlan TODO/FIXME.

---

# 34. Chapter 13 végső Definition of Done

A Chapter 13 akkor zárható le, ha:

## Foundations

- [ ] Design token rendszer kanonikus.
- [ ] Három téma elkészült.
- [ ] Tipográfia és fontok egységesek.
- [ ] Motion és reduced motion működik.
- [ ] Gitárglyph készlet elérhető.
- [ ] Component Catalog létezik.
- [ ] Hardcoded UI allowlist nem nő.

## Navigation

- [ ] Today, Practice, Songs, Coach és Profile célterület működik.
- [ ] Compact bottom navigation és expanded rail működik.
- [ ] Stage Mode elrejti a primary navigációt.
- [ ] Legacy route-ok migráltak vagy dokumentált aliasok.
- [ ] Deep link és back stack tesztelt.
- [ ] Unsaved/session back confirmation helyes.

## Components

- [ ] Layout, action, input, feedback, overlay, music, analytics, AI és community komponensek elkészültek.
- [ ] Komponensek feature business logikától függetlenek.
- [ ] Komponensek mindhárom témában és nagy text scale mellett használhatók.
- [ ] Semantics szerződés dokumentált.

## Screens

- [ ] UI-01–UI-65 állapota nyomon követett.
- [ ] Minden release-scope képernyő megfelel a saját elfogadási feltételeinek.
- [ ] Minden kritikus flow végponttól végpontig tesztelt.
- [ ] Offline és degraded flow-k működnek.
- [ ] Account/community opcionális marad.
- [ ] AI és Vision provenance/privacy világos.

## Quality

- [ ] Format és analyze zöld.
- [ ] Teljes Flutter test zöld.
- [ ] Golden gate zöld.
- [ ] Accessibility gate zöld.
- [ ] Localization parity zöld.
- [ ] Architecture/token guard zöld.
- [ ] Valós eszközteszt dokumentált.
- [ ] UI performance baseline nem romlott elfogadhatatlanul.
- [ ] Mic/camera/audio lifecycle regresszió nincs.
- [ ] Completion report elkészült.

---

# 35. A fejezet eredménye

A Chapter 13 befejezése után a StrumSight nem egymás mellé épített feature-k gyűjteménye lesz, hanem egyetlen következetes termékélmény:

- a **Today** megmondja, mit érdemes ma csinálni;
- a **Practice** gyorsan elindítja a megfelelő eszközt;
- a **Songs** strukturáltan tanít valódi dalokat;
- a **Coach** evidence alapján magyaráz és konkrét műveletet ajánl;
- a **Profile** összefogja a fejlődést, jutalmakat, communityt és beállításokat;
- a **Stage Mode** játék közben nagy, nyugodt és fókuszált;
- a **Studio Analytics** részletes, de nem terheli túl a kezdőt;
- a **Vision Coach** egyetlen releváns technikai cue-t mutat;
- a local, cloud és offline állapotok őszintén láthatók;
- az accessibility, privacy és graceful degradation nem utólagos javítás, hanem a komponensrendszer része;
- a Codex minden képernyőt kis, ellenőrizhető körökben tud implementálni.

A Chapter 13 a Chapter 1–12 keresztmetszeti UI-szerződése. Funkcionális fejezet nem írhatja felül csendben ezeket a szabályokat. Eltéréshez dokumentált ADR, mérhető indok és külön elfogadás szükséges.
