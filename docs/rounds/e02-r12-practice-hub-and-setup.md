# E02-R12 — Practice Hub és Setup UI

- **Státusz:** **PLANNING** (pre-flight elvégezve 2026-07-31, kód mérve: `main` @ `f2fc758`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 12"** (+ §21.1, §21.2, §22)
- **Branch:** `mm/e02-r12-practice-hub-setup`
- **Előfeltétel:** **E02-R11 merge-ölve** ✅ (`a7839d6`)
- **ADR:** **0078** — [`docs/adr/0078-practice-feature-surface-and-routing.md`](../adr/0078-practice-feature-surface-and-routing.md)
  — az orchestrátor megírta a pre-flightban. **A §5 kötött döntései onnan jönnek.**
- **Implementer motor:** **MiniMax M3** (ADR 0069 §15.6 — volumenkör: widget + ARB + teszt).

## 0.0 Revíziós napló (orchestrátor, 2026-07-31 pre-flight)

A brief 2026-07-31-én előre készült; a pre-flight minden hivatkozott szimbólumot
kimért, és **hét** állítás avultnak vagy tévesnek bizonyult. Mindegyik javítva:

| # | Eredeti brief-állítás | Mérés | Feloldás |
|---|---|---|---|
| R1 | A6: „fake **controller** hívásnaplója" | **`practiceSessionControllerProvider` NEM létezik** — az R11 szándékosan a Kör 13-ra hagyta (`practice_session_providers.dart` záró megjegyzése) | A Start egy injektálható **`PracticePrepareSink`**-be ad parancsot (ADR 0078 §5); a teszt ezt írja felül. **Nem** a controllert hívja. |
| R2 | A5: Speed Builder start/target/step + `target < start` tiltás | **`PracticeSessionConfig`-ban nincs Speed-Builder mező** („intentionally absent until its dedicated round"); a `SpeedBuilderPolicy` validátor az SDD **Kör 17**-é | A Speed Builder felülete **kikerül** ebből a körből (ADR 0078 §6). A Kör 17 briefje viszi — kötelezettségként rögzítve. |
| R3 | A4: „meter · a **PracticeSessionConfig** mezője" | **A `Meter` a `PracticeDefinition`-é** (`practice_definition.dart:44`), a configban nincs | A Setup az ütemmutatót **kijelzi**, nem állítja. A4 cella átírva. |
| R4 | A4: „loop · ki / be" | Nincs bool; **`loopCount` int, 1–32 zárt** | A4 cella átírva határértékekre (1 / 32 / 33). |
| R5 | A2: `PracticeMode.**chordChange**` | Az enum értéke **`chordChanges`** (`practice_mode.dart:6`) | Név javítva. |
| R6 | §2: „`AppRoutes` **17** útvonal-konstans", „ARB **375** kulcs" | **16** konstans; **273** kulcs (en = hu), 0 `practice*` | §2 újramérve. |
| R7 | A9: „a képernyő forrása nem tartalmazza a `DateTime.now(` mintát" | A ház mintája **injektálható `now`** + `now ?? DateTime.now()` (`progress_screen.dart:30`, `streak_screen.dart:29`), és a Daily Challenge napja kell hozzá | A9 pontosítva: a Hubon **pontosan egy** ilyen előfordulás megengedett (az injektálható alapértelmezés), a Setupon **nulla**. |

Bónusz mérés (nem hiba, megerősítés): `onException: (_, _, router) => router.go(AppRoutes.live)`
**létezik** (`app_router.dart:40`) → az A7 flag-OFF cellája a meglévő ágat méri;
`EmptyState` létezik (`lib/core/widgets/empty_state.dart:14`); `test/app/routing/`
létezik (a §9 gate-sor útvonala érvényes).

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved — nincs külön task-lista.**
**A munkádat commitold a kör-branchre** (`mm/e02-r12-practice-hub-setup`);
`done` jelzés uncommitted fájlokkal bukott kör.

## 1. Cél

A Practice Engine V2 tizenegy kör után **teljesen láthatatlan**: nincs egyetlen
képernyője sem. Ez a kör hozza létre a feature **belépési felületét** — a
Practice Hubot és a Setup képernyőt — a `practiceEngineV2Enabled` flag mögött,
**pontozó UI nélkül** (a session-képernyő a Kör 13).

A kör után egy fejlesztői buildben a felhasználó eljut a katalógustól a
konfigurált session **parancsának kiadásáig**; a session maga még nem jelenik meg.

## 2. Jelenlegi állapot (mért tények, `main` @ `f2fc758`)

- **A `lib/features/practice/` alatt nincs `presentation/` könyvtár**, egyetlen
  widget és képernyő sincs. A feature ma: `domain/` (20 modell + 2 repository +
  6 service), `application/` (10 fájl), `data/` (2 + 4 adapter + 1 label-híd).
  **`public.dart` sincs** (a `songs`, `progress`, `streak`, `chords`,
  `library`, `learn` feature-öknek van — a barrel-minta tehát adott, lásd
  `lib/features/streak/public.dart`).
- **Routing:** `lib/app/routing/app_route.dart` — `AppRoutes` **16 útvonal-
  konstanssal** és az ötelemű `shellTabs` listával (`live`, `analyze`, `learn`,
  `library`, `settings`). `app_router.dart` (**116 sor**): `ShellRoute` az öt
  tabra + a teljes képernyős route-ok, `onException: (_, _, router) =>
  router.go(AppRoutes.live)` a **40. sorban**. Guard-teszt:
  `test/tooling/route_literal_guard_test.dart` — navigációs hívásban
  route-string-literál TILOS, csak `AppRoutes` konstans.
- **Flag:** `AppConfig.flags.practiceEngineV2Enabled`
  (`lib/app/config/feature_flags.dart`) — **non-prod: true, production: false**,
  dart-define override **nincs**. A widget-oldali olvasás mintája mérve:
  `ref.watch(appConfigProvider).flags.labModeAvailable`
  (`settings_screen.dart:204`).
- **Katalógus-providerek (R04):** `practiceCatalogProvider` — a tíz beépített
  gyakorlat `PracticeDefinition`-ként; `practiceCatalogRepositoryProvider`
  felülírható tesztben. A repository szerződése: `all()`, `byId()` (**ismeretlen
  id → `null`, sosem dob**), `byMode()`, `byDifficulty()`.
- **`PracticeMode` értékei** (`practice_mode.dart`): `strumPattern`,
  **`chordChanges`**, `chordProgression`, `rhythmOnly`, `freePractice`.
- **`PracticeSessionConfig` mezői** (`practice_session_config.dart`, 206 sor) —
  `definitionId`, `definitionSnapshotVersion`, `effectiveTempo` (**`Tempo`**),
  `countInBars`, `loopCount`, `metronomeEnabled`, `accentEnabled`,
  `backingEnabled`, `scoringProfileId`, `easyVariationId?`, `inputLatency`,
  `visualLatency`, `expectedChordHintEnabled`, `sessionTimeout`, `reducedMotion`.
  Határok konstansként: `minimumCountInBars=0`, `maximumCountInBars=4`,
  `minimumLoopCount=1`, `maximumLoopCount=32`, `maximumLatency=500ms`.
  **NINCS benne `meter` és NINCS benne Speed-Builder mező.**
- **`Tempo`:** `minimumBpm = 30.0`, `maximumBpm = 300.0`, `validate()`;
  a domain **sosem clamp-el**.
- **`Meter`:** `beatsPerBar` + `beatUnit` (támogatott: 2, 4, 8) — a
  **`PracticeDefinition.meter` mezőjén** él.
- **i18n:** `lib/l10n/app_en.arb` **273 kulcs** (a `@`-metaadatok nélkül),
  `app_hu.arb` ugyanannyi. Gate: `test/core/l10n_parity_test.dart` — azonos
  kulcshalmaz **és** üres fordítás tilos. **A `practice*` prefixű kulcsok ma
  teljesen hiányoznak** (mérve: 0 találat).
- **Layout-őr:** `test/core/screen_size_guard_test.dart` — három méret
  (320×568, 412×915, 915×412), `atSize()` helper; a RenderFlex-túlcsordulás
  teszthiba. **Az új képernyőket ide fel kell venni.**
- **Widget-teszt minta:** `ProviderScope(overrides: [...preferenceOverrides(), ...])`
  + `MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales)`
  (lásd `test/features/progress/progress_screen_test.dart`).
- **a11y minta:** `test/features/chords/chord_tile_a11y_test.dart` —
  `tester.ensureSemantics()`, és a címke + akció **egy** node-on.
- **`EmptyState`:** `lib/core/widgets/empty_state.dart:14`.
- **Daily Challenge adapter (R05):**
  `practiceDefinitionFromDailyChallenge(DailyChallenge challenge, {double bpm = 80})`
  → `AppResult<PracticeDefinition>`; **pure, órát nem olvas** — a hívó adja a
  `DailyChallenge`-et. A `DailyChallenge.forDay(int epochDay)` és a
  `StreakLogic.epochDayOf(DateTime)` a `lib/features/streak/public.dart`-ból jön
  (**csak olvasás, a streak feature-t módosítani TILOS**).
- **Nincs `practiceSessionControllerProvider`** — az R11 szándékosan a Kör 13-ra
  hagyta. A Setup **nem** kérhet controllert a provider-gráfból (ADR 0078 §5).

## 3. Scope

**Benne:** két képernyő (Hub, Setup), a hozzájuk tartozó widgetek, egy setup-
controller az `application/` alatt a `PracticePrepareSink` nyelővel, a feature
barrel (`public.dart`), két új route flag mögött, ARB-kulcsok mindkét nyelven,
widget- és routing-tesztek.

**Kívül (ebben a körben TILOS):**

- **A session-képernyő, a highway, a HUD, bármilyen scoring-megjelenítés** —
  Kör 13/14.
- **A Speed Builder bármilyen felülete vagy konfigurációja** — Kör 17
  (ADR 0078 §6; a `SpeedBuilderPolicy` validátor ott születik meg).
- A Result képernyő, history-lista — Kör 18.
- A `learn`, `songs`, `streak` feature-ök bármilyen **módosítása** (olvasni
  szabad: a Daily Challenge adapter **már kész**, R05 — csak hívni kell).
- Business logic widgetben: pontozás, matcher, target-fordítás, óra.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/presentation/screens/practice_hub_screen.dart` | **ÚJ** | Hub |
| `lib/features/practice/presentation/screens/practice_setup_screen.dart` | **ÚJ** | Setup |
| `lib/features/practice/presentation/widgets/practice_mode_card.dart` | **ÚJ** | mód-kártya |
| `lib/features/practice/presentation/practice_route_args.dart` | **ÚJ** | tipizált route-argumentumok + biztonságos feloldás |
| `lib/features/practice/application/practice_setup_controller.dart` | **ÚJ** | a Setup állapota + `PracticePrepareSink` (SDD §8.1 szerinti hely) |
| `lib/features/practice/public.dart` | **ÚJ** | feature-barrel (SDD §8.1) |
| `lib/app/routing/app_route.dart` | — | **CSAK** két új konstans (`practiceHub`, `practiceSetup`) |
| `lib/app/routing/app_router.dart` | — | **CSAK** a két route regisztrációja a flag mögött |
| `lib/l10n/app_en.arb` | — | új `practice*` kulcsok |
| `lib/l10n/app_hu.arb` | — | ugyanazok magyarul (a parity-gate kötelező) |
| `test/features/practice/presentation/practice_hub_screen_test.dart` | **ÚJ** | A1–A3 |
| `test/features/practice/presentation/practice_setup_screen_test.dart` | **ÚJ** | A4–A6 |
| `test/features/practice/presentation/practice_routing_test.dart` | **ÚJ** | A7 (flag + fallback) |
| `test/features/practice/presentation/practice_presentation_guard_test.dart` | **ÚJ** | A9 (forrás-mintaőr) |
| `test/core/screen_size_guard_test.dart` | — | **CSAK** a két új képernyő felvétele a meglévő mintába |
| `docs/rounds/e02-r12-practice-hub-and-setup.md` | — | **CSAK a §10** (handoff) |

**Tilos zóna:** minden más. Nevezetesen `lib/features/practice/domain/**`,
`lib/features/practice/data/**`, `lib/features/learn/**`,
`lib/features/streak/**`, `lib/app/config/**` (a flag **értéke** nem változik),
`lib/app/home_shell.dart` (a Practice **nem** lesz shell-tab ebben a körben),
`docs/adr/**`, `docs/sdd/**`, `.github/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0078 — NEM tárgyalhatók)

Olvasd el az [ADR 0078](../adr/0078-practice-feature-surface-and-routing.md)-at;
a nyolc döntés összefoglalva:

1. **A Practice felület flag mögött van.** A két route **csak akkor**
   regisztrálódik, ha `appConfigProvider.flags.practiceEngineV2Enabled` igaz.
   Flag OFF mellett a `/practice*` a router **meglévő** `onException` szabálya
   szerint a Live-ra esik vissza — **nem** fehér képernyő, **nem** kivétel.
2. **A Practice NEM lesz shell-tab.** A `shellTabs` ötelemű marad; a Hub teljes
   képernyős route, és ez a kör **nem** ad neki belépőt más képernyőről.
3. **Tipizált route-argumentum:** `/practice/setup?id=<definitionId>` (query,
   **nem** path-szegmens — az ADR 0078 §3 indoklása szerint), a képernyő
   `byId`-vel old fel. Feloldhatatlan azonosító → lokalizált hibaállapot +
   „vissza a Hubra" út, **soha nem** kivétel és **soha nem** üres képernyő.
4. **A UI nem definiál validációs szabályt.** Minden mező-korlát a
   `PracticeSessionConfig.validate()` / `Tempo` / `PracticeSessionConfig`
   konstansaiból jön, és a Start gomb tiltása **ugyanazon** a validáción alapul.
   A UI legfeljebb *megjeleníti* a hibakódhoz tartozó lokalizált szöveget.
   Az ütemmutató és a scoring-profil **kijelzés**, nem beállítás.
5. **A Start a `PracticePrepareSink`-be ad `PreparePractice` parancsot**
   (ADR 0078 §5) — a Setup **nem** navigál a session-képernyőre (az még nem
   létezik), és **nem** hívja a nem létező session-controllert. A production
   alapértelmezésű nyelő a parancs tényeit **naplózza** (`appLoggerProvider`),
   nem no-op. A Start után a képernyő marad, lokalizált visszajelzéssel.
6. **Minden user-facing szöveg ARB-ból jön**, mindkét nyelven kitöltve. A domain
   és az application réteg **nem** tartalmaz megjelenítendő szöveget (SDD §22.3).
7. **A widget nem tartalmaz business logikát**: nincs benne pontozás, matcher,
   target-fordítás, `Stopwatch` vagy `Timer(`. A Hub „Continue" és „Recent"
   blokkjai ebben a körben **placeholder-határok** (üres állapot), mert a
   history a Kör 18-ban készül el — a placeholder **ne** hazudjon adatot.
8. **Accessibility alapok kötelezőek** már itt: minimum 48×48 dp érintőfelület,
   szemantikus címke **és akció egy node-on** minden vezérlőn, a jelentés nem
   csak színre épül.

## 6. Acceptance criteria

### A1 — A Hub a katalógusból renderel

`practiceCatalogRepositoryProvider` felülírva egy ismert, **három** definíciót
adó fake-kel → a Hub pontosan három mód-kártyát mutat, a definíciók
`displayTitle`-jével (ahol `displayTitle == null`, ott a lokalizált
`titleKey` alapján). Nulla definíció → lokalizált üres állapot (`EmptyState`),
**nem** üres `ListView`.

***Pirosra fogja:*** a beégetett kártyalista.

### A2 — Mód-szűrés

`PracticeMode` szerinti szűrés: az öt módra (`strumPattern`, **`chordChanges`**,
`chordProgression`, `rhythmOnly`, `freePractice`) **külön cella** — a szűrő
kiválasztása után csak az adott módú definíciók látszanak, és a szűrő
törlése után újra mind.

**NEM elfogadható gyengítés:** egyetlen mód tesztelése „a többi ugyanaz a kód"
indoklással — a fixture default-ja pont az a pont, ahol a hibás és a helyes
implementáció megkülönböztethetetlen. A fixture-ben **mind az öt módhoz**
legyen legalább egy definíció, és legyen legalább egy mód **két** definícióval
(hogy a szűrő ne csak „1 vagy 0" választ mérjen).

### A3 — A Hub nem hazudik adatot

- **„Continue" blokk:** **nincs** korábbi session → a blokk **nem jelenik meg**
  (nem „0 perc", nem „—"). Ebben a körben nincs history-forrás, tehát a blokk
  **soha** nem jelenik meg; a tesztnek ezt kell kipinnelnie
  (`findsNothing` a Continue kulcsára).
- **„Recent" blokk:** ugyanez.
- **Quick Start:** a katalógus **első** definícióját nyitja Setupra;
  üres katalógusnál **nem jelenik meg** (nem letiltott, hanem nincs — nincs mit
  indítani).
- **Daily Challenge belépő:** a Hub a `practiceDefinitionFromDailyChallenge`
  eredményét használja. `AppResult` **hiba** esetén a belépő **letiltott**
  állapotban jelenik meg lokalizált magyarázattal, **nem tűnik el némán**. A
  teszt ezt egy üres `pattern`-ű `DailyChallenge`-dzsel méri (az adapter mérten
  `pattern.isEmpty` → failure), injektált `now`-val.

### A4 — Setup: alapértékek és a domain-validáció egyezése

Mátrix, minden cellához külön `expect`. **A határcellák nem hagyhatók el** —
azok mérik a `<=` / `<` különbséget:

| Mező | Cella | Elvárt | Igazságforrás |
|---|---|---|---|
| BPM | 29 / **30** / **300** / 301 | tiltva / **engedve** / **engedve** / tiltva | `Tempo.minimumBpm/maximumBpm` |
| count-in ütem | −1 / **0** / 2 / **4** / 5 | tiltva / engedve / engedve / engedve / tiltva | `PracticeSessionConfig.minimum/maximumCountInBars` |
| loop | 0 / **1** / **32** / 33 | tiltva / engedve / engedve / tiltva | `PracticeSessionConfig.minimum/maximumLoopCount` |
| ütemmutató | 4/4 · 3/4 · 6/8 definíció | a Setup az **adott definíció** `meter`-ét jeleníti meg (`Meter(beatsPerBar, beatUnit)`) | `PracticeDefinition.meter` — **kijelzés** |
| metronóm | ki / be | a `PracticeSessionConfig.metronomeEnabled` követi | — |

Az alapértékek a definícióból seedelődnek: `effectiveTempo = definition.defaultTempo`,
`definitionId = definition.id`, `definitionSnapshotVersion = definition.schemaVersion`,
`scoringProfileId = definition.scoringProfile.id`.

***Pirosra fogja:*** a UI-ban külön beírt `min: 40, max: 240` típusú
slider-korlát, ami eltér a domain validációtól.

### A5 — Mód-specifikus mezők

- **Free Practice** kiválasztva → a pontozási beállítások (scoring-profil
  kijelzés, pass-küszöb megjelenítés) **nem láthatók** (SDD: „Free Practice
  hides scoring options").
- **Rhythm-only** → az akkord-kapcsolódó vezérlő (`expectedChordHintEnabled`)
  nem látszik.
- **strumPattern / chordChanges / chordProgression** → a scoring-profil kijelzés
  **látszik** (a negatív cella párja — enélkül a „mindig rejtsd el"
  implementáció is átmenne).

*(A Speed Builder felülete ebből a körből kimarad — ADR 0078 §6, Kör 17.)*

### A6 — Start csak érvényes configgal, pontosan egy parancs

- Érvénytelen konfigurációnál a Start gomb **letiltott**, és a hiba lokalizált
  szövegként látszik (a `PracticeValidationCode`-hoz kötött kulcs).
- Érvényesnél a Start pontosan **egy** `PreparePractice` parancsot ad a
  `practicePrepareSinkProvider`-en keresztül — a teszt egy hívásnaplózó
  fake-kel írja felül a providert, és **a naplózott parancs mezőit is
  ellenőrzi**: `command.definition.id`, `command.config.effectiveTempo.bpm`,
  `command.config.countInBars`, `command.config.loopCount` egyezik a UI-n
  beállítottal.
- Kétszeri gyors koppintás → **továbbra is egy** parancs a naplóban? **NEM
  követelmény** ebben a körben (nincs single-flight előírás) — a teszt ezt ne
  állítsa.

### A7 — Routing: flag, fallback, literál-tilalom

| Cella | Elvárt |
|---|---|
| flag ON, `/practice` | a Hub épül fel |
| flag ON, `/practice/setup?id=<ismert>` | a Setup a feloldott definícióval |
| flag ON, `/practice/setup?id=<ismeretlen>` | lokalizált hibaállapot + vissza-út, **nincs** kivétel |
| flag ON, `/practice/setup` (`id` **hiányzik**) | ugyanaz a lokalizált hibaállapot |
| flag OFF, `/practice` | a router `onException` szerinti fallback (Live), **nincs** kivétel |

Plusz: `test/tooling/route_literal_guard_test.dart` **zöld marad** — minden
navigáció `AppRoutes` konstanson keresztül.

### A8 — i18n parity és accessibility

- `test/core/l10n_parity_test.dart` zöld: minden új kulcs **mindkét** ARB-ben,
  üres fordítás nélkül. A magyar szövegek **valódi fordítások**, nem angol
  másolatok.
- Mindkét képernyő angolul **és** magyarul felépül (widget-teszt két locale-lal),
  és a magyar futásban legalább egy magyar szöveg meg is jelenik (`findsOneWidget`).
- `tester.ensureSemantics()` mellett minden interaktív elem **címkével és
  akcióval EGY** szemantikus node-on (a `chord_tile_a11y_test.dart` mintája).
- 200%-os szövegméret (`textScaler`) mellett **nincs** overflow.
- `test/core/screen_size_guard_test.dart` zöld a két új képernyővel (mindhárom
  meglévő méreten).

### A9 — Nincs business logic a widgetben

Külön guard-tesztfájl (`practice_presentation_guard_test.dart`), forrás-olvasó
állításokkal a két képernyőre és a mód-kártyára:

- **nem tartalmazza:** `Stopwatch`, `Timer(`, `matcher`, `scorer`;
- **nem importál** `domain/service/`-t;
- **`DateTime.now(`:** a Hub forrásában **pontosan 1** előfordulás (az
  injektálható `now ?? DateTime.now()` alapértelmezés, a ház mintája szerint —
  `progress_screen.dart:30`), a Setup forrásában **0**;
- a `practice_setup_controller.dart` **nem importál** `flutter/material.dart`-ot
  és nem hivatkozik `BuildContext`-re.

### A10 — Nulla változás a legacy úton

`git diff --stat origin/main...HEAD` a §4 listáján belül; `lib/features/learn/`
**0 sor**; `lib/features/streak/` **0 sor**; `lib/app/home_shell.dart` **0 sor**;
a `lib/app/config/feature_flags.dart` **0 sor** (a flag értéke nem változik).

## 7. Implementációs sorrend (ez a TERVED — nincs külön task-lista)

1. Olvasd el: az [ADR 0078](../adr/0078-practice-feature-surface-and-routing.md)-at,
   `practice_session_config.dart`, `practice_definition.dart`, `tempo.dart`,
   `meter.dart`, `practice_mode.dart`, `practice_catalog_controller.dart`,
   `practice_session_command.dart` (a `PreparePractice` alakja),
   `daily_challenge_practice_adapter.dart`, `app_route.dart`, `app_router.dart`,
   a `progress_screen.dart`-ot mint stílus- és `now`-horgonyt,
   a `settings_screen.dart:204` flag-olvasási mintát, és a
   `route_literal_guard_test.dart`-ot.
2. ARB-kulcsok mindkét nyelven (előbb a szövegek, hogy ne maradjon literál).
3. `public.dart` barrel + `practice_route_args.dart`.
4. `practice_setup_controller.dart` (állapot + a domain-validáció becsatolása +
   `PracticePrepareSink` és a naplózó production alapértelmezés).
5. Hub képernyő + mód-kártya, üres állapotokkal (A1–A3).
6. Setup képernyő (A4–A6).
7. Route-regisztráció a flag mögött (A7).
8. a11y + layout-őr + i18n (A8), guard-teszt (A9).
9. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A route-regisztráció közös fájl.** Az `app_router.dart`-ban **csak** a két
  új `GoRoute` és a flag-feltétel jelenhet meg; minden más sor változatlan.
- **ARB-drift.** Kulcs csak az egyik nyelvben = piros parity-gate.
- **A Hub „Continue" csábítása.** A history a Kör 18-é; ha itt bevezetsz egy
  ideiglenes tárolót, az duplikált szerződés lesz → `stopped`.
- **A 6/8 ütemmutató** a `Meter`-ben `beatsPerBar: 6, beatUnit: 8`; a Setup
  megjelenítése nem feltételezheti a 4/4-et és nem hívhatja a `ticksPerBar`-t
  érvénytelen mértéken (az mérten `StateError`-t dob).
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull` (Riverpod 3.3.2).
- **Doc-comment fegyelem:** ne állíts a kódról olyat, amit nem ellenőriztél —
  ha `const`-ot vagy `immutable`-t írsz, előbb bizonyítsd tesztben.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart test/tooling/route_literal_guard_test.dart test/app/routing/
```

**Csővezeték és `tail` nélkül**, a teljes kimenetet a §10-be. Köztes gyors
ellenőrzést szűkíthetsz (egy tesztfájl), de a ZÁRÓ gate-sort pontosan így kell
lefuttatni. A teljes suite + property gate + APK a CI-ban fut (ADR 0053) —
`gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A10
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r12-review.md`

Kiemelt figyelem: a **flag OFF** út tényleges kipróbálása (nem csak a teszt
állítása), az A4 határcellái (30/300 BPM, 0/4 count-in, 1/32 loop), hogy a Setup
**tényleg** a domain validációt hívja-e (nem egy másolt szabálykészletet), és
hogy az A6 hívásnaplója a parancs **mezőit** is méri-e.
