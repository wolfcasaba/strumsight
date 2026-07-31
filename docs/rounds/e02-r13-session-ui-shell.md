# E02-R13 — Practice Session UI shell

- **Státusz:** **PLANNING** (pre-flight elvégezve 2026-07-31, kód mérve: `main` @ `bc7beb8`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 13"** (+ §21.3, §21.6, §22)
- **Branch:** `mm/e02-r13-session-ui-shell`
- **Előfeltétel:** **E02-R12 merge-ölve** ✅ (`874e163`, PR #36)
- **ADR:** **0079** — [`docs/adr/0079-state-driven-practice-session-shell.md`](../adr/0079-state-driven-practice-session-shell.md)
  — az orchestrátor megírta a pre-flightban. **A §5 kötött döntései onnan jönnek.**
- **Implementer motor:** **MiniMax M3** (pipeline-döntés, `docs/execution/pipeline-queue.tsv`).

## 0.0 Revíziós napló (orchestrátor, 2026-07-31 pre-flight)

A brief 2026-07-31-én előre készült. A pre-flight minden hivatkozott szimbólumot
kimért; **nyolc** állítás bizonyult avultnak, tévesnek vagy elérhetetlen célt
előírónak. Mindegyik javítva:

| # | Eredeti brief-állítás | Mérés | Feloldás |
|---|---|---|---|
| R1 | Branch: `codex/e02-r13-session-ui-shell` | a motor **MiniMax M3** (queue), az R12 branch-e `mm/e02-r12-…` | Branch: **`mm/e02-r13-session-ui-shell`** |
| R2 | „A képernyő a **controller** state-jét olvassa" | `practiceSessionControllerProvider` **ma sem létezik** (`practice_session_providers.dart:110-114`), és az `application/` **tilos zóna** ebben a körben | A képernyő egy **presentation-oldali** `PracticeSessionHost` határon keresztül lát (ADR 0079 §2); production default **`null`** → lokalizált „session nem elérhető" állapot |
| R3 | A1 `permissionRequired`: „engedélykérő akció" | a `GrantPermission` `preparing`-be visz **újrafordítás nélkül** (reducer:256-268), és a controller **csak** `PreparePractice`-re fordít újra (controller:222-224) → **zsákutca** | Az akció parancsa **`PreparePractice(state.definition!, state.config!)`** — ezt a reducer `permissionRequired`-ből elfogadja (reducer:238-241). A `GrantPermission` kiadása **tilos** |
| R4 | A1 `failed`: „hibapanel, a session megmarad" | `RetryPractice` → `preparing` (reducer:502-518), de onnan a `PreparePractice` **elutasított** → a `failed → futó session` út **ma nem zárul** | A panel „újra" gombja `RetryPractice`-t ad ki, és **ennyit ígér**; a hiány ADR 0079 §6-ban nevesített follow-up. Látszatparancs tilos |
| R5 | A4: minden kilépési út „`CancelPractice`" | a cancel tisztán az `allowedTransitions`-ön kapuzódik (reducer:487) → `preparing`, `finishing`, `completed`, `cancelled`, `failed` állapotból **elutasított**, és a terminális takarítás már lefutott (controller:249-255) | Kilépés **`const` parancs-táblán** (ADR 0079 §4): parancs csak `permissionRequired`/`ready`/`countIn`/`running`/`paused` esetén; `finishing`-ben a kilépés **blokkolt**; terminális állapotban **nulla parancs** |
| R6 | A1 `running`: „score-pillanatkép" a state-ből | a `PracticeSessionState`-nek **nincs** score-mezője; az élő aggregátum a controller `liveScore` gettere (controller:144), típusa `domain/service/` alatt | A host **`int? liveOverallPerMille`** primitívet ad át (ADR 0079 §2) — a presentation nem importál `domain/service/`-t |
| R7 | §2: „`l10n_parity_test` (375 kulcs)" | mérve **327 kulcs** mindkét ARB-ban, ebből 54 `practice*` | A kulcsszám nem mérce; a mérce a **kulcshalmaz-egyezés**. A hivatkozás javítva |
| R8 | A6 csak `running` alatti háttérbe kerülést ír elő | a `paused` a táblán `countIn`-ból is elérhető (reducer:324 az `allowedTransitions`-t nézi) | A6 kiegészítve a `countIn` cellával; minden más állapotban **nulla parancs** |

**Nem oldottam fel lista-tágítással:** a `PracticeSessionHost`, a
`PracticeFeedbackOutput` és a navigációs nyelő a **már engedélyezett**
`practice_effect_listener.dart`-ban lakik — új fájl nincs.

**Ami kimarad ebből a körből (és miért):** a HANDOFF §5 az `AudioOwner.practice`
+ Live→Practice gateway-bekötést az E02-R13-hoz rendelte. Az `application/` és a
`data/` viszont ennek a körnek a **tilos zónája** (§4), és a bekötés
audio-lease-döntés, nem UI-döntés. Ezért a follow-up **változatlanul nyitva
marad** (ADR 0079 §Következmények/1), és a HANDOFF a merge után átsorolja.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**A munkádat commitold a kör-branchre** — `done` jelzés uncommitted fájlokkal
bukott kör.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved — nincs külön task-lista.**
**Doc-commentben csak tesztben bizonyított állítás** (`const`, `immutable`, …).

## 1. Cél

A **közös** session-képernyő: minden státuszt renderel, fogadja a controller
effektjeit, és **kizárólag** parancsokat küld vissza. **Mode-specifikus nézet és
pontozó-vizuál ebben a körben nincs** — az a Kör 14–16. A kör tétje az
**életciklus**: nincs saját business-óra, nincs ticker-leak, nincs duplikált
navigáció, és a képernyő elhagyása **mindig** a mért állapotgép szerinti
takarítást kéri.

## 2. Jelenlegi állapot (mért tények, `main` @ `bc7beb8`)

- **A V2-nek nincs session-képernyője.** A `presentation/` alatt a Hub, a Setup,
  a mód-kártya és a route-argumentum-parser van (R12).
- **A legacy referencia és ellenpélda: `lib/features/learn/screens/learn_screen.dart`
  (839 sor).** Mért szerkezet:
  - `SingleTickerProviderStateMixin` + saját `Ticker` (44., 49., 88. sor) —
    a `_onTick` **maga hajtja** a scorert és az időt: ez a business-óra a
    widgetben, amit a V2 **nem** másolhat;
  - `Metronome _metronome = Metronome()` (50. sor) — a widget hozza létre az
    audio erőforrást;
  - `_scorer ??= LessonScorer(...)` (218. és 248. sor);
  - `ref.listenManual(liveFrameProvider, _onFrame)` (224. sor);
  - a `_pause()` (232. sor) **nem** állítja le a mikrofon-fogyasztást.
  Ebből a fájlból **semmit nem másolsz át**; referenciaként olvasható.
- **Controller (R11):** `states` / `state` / `effects` / `liveScore` / `result`
  getterek + `dispatch(PracticeSessionInput)` + `dispose()`
  (`practice_session_controller.dart:141-192`). **Provider nincs hozzá** — lásd
  R2 revízió.
- **Állapotgép:** 11 státusz, `const allowedTransitions` tábla
  (`practice_session_state.dart:273-355`). A parancs-elfogadás ezen a táblán
  kapuzódik; a `PreparePractice` `idle`/`permissionRequired`-ből, a
  `RetryPractice` `failed`-ből, a `GrantPermission` `permissionRequired`-ből
  fogadható el.
- **Count-in mérése a state-ből:** `countInSpanBeats` és `emittedCountInClicks`
  (`practice_session_state.dart:77,90`) — a hátralévő ütés a kettő különbsége.
- **Effektek (R07):** `PlayHaptic`, `PlayCountInClick(beatIndex)`,
  `ShowPermissionSettings`, `NavigateToResult`, `ShowRecoverableError(failure)`,
  `AnnounceAccessibilityFeedback(messageKey)`
  (`application/practice_session_effect.dart`, 54 sor) — a sealed switch
  **kimerítő**. Mérve: az `AnnounceAccessibilityFeedback`-et **ma egyetlen ág
  sem emittálja** (a reducerben nulla találat).
- **Core widgetek, amiket újra kell használni:** `core/widgets/mic_permission_banner.dart`
  (`const MicPermissionBanner()`, saját „beállítások" gombbal),
  `core/widgets/mic_error_banner.dart` (`required onRetry`),
  `core/widgets/empty_state.dart` (`required icon`, `required title`).
- **App-életciklus:** `lib/core/platform/app_lifecycle.dart` —
  `AppLifecycleEvents` interfész + `isBackgroundLifecycleState(state)` (20. sor);
  provider: **`appLifecycleEventsProvider`**
  (`lib/core/platform/platform_providers.dart:8`). A Live képernyő ugyanezt
  használja (`live_screen.dart:66`) — kövesd a mintát.
- **Haptika ma:** nincs absztrakció és nincs beállítás (nulla `haptic` találat a
  `settings/` és a `core/` alatt); a legacy képernyők közvetlenül hívják a
  `HapticFeedback` statikusait.
- **Minta a parancs-határra:** ADR 0078 §5 / `practice_setup_controller.dart:31-55`
  — `typedef` + logoló production default + provider. **Ugyanezt a mintát
  kövesd** a navigációs nyelőnél.
- **Layout-őr:** `test/core/screen_size_guard_test.dart` (három méret:
  320×568, 412×915, 915×412); **a11y-minta:** `test/features/chords/chord_tile_a11y_test.dart`;
  **i18n-gate:** `test/core/l10n_parity_test.dart` (mérve 327 kulcs/nyelv, a
  mérce a **kulcshalmaz-egyezés**); **forrás-mintaőr minta:**
  `test/features/practice/presentation/practice_presentation_guard_test.dart`
  (a `_stripComments` segédfüggvényével — **ezt a fájlt nem módosítod**, de a
  technikát átveheted a saját tesztfájlodba).

## 3. Scope

**Benne:** egy session-képernyő + a közös HUD/overlay/vezérlő widgetek + effekt-
kezelés (haptika, hang, hibapanel, navigációs kérés) + életciklus-továbbítás +
ARB-kulcsok + widget-tesztek minden státuszra.

**Kívül (ebben a körben TILOS):**

- **Highway, target-sáv, akkord-diagram, timing/direction visszajelzés,
  combo-vizuál** — Kör 14–16. A HUD ebben a körben a **szöveges/számszerű**
  állapotot mutatja (státusz, eltelt idő, attempt-index, score-pillanatkép),
  gördülő grafika nélkül.
- Result képernyő és a hozzá tartozó navigáció **célja** — a `NavigateToResult`
  effektet egy **lokalizált placeholder** fogadja (a Result a Kör 18); a
  placeholder ne állítson pontszámot, amit nem mértünk.
- A controller, a reducer, a gateway, a scorerek, a providerek **bármilyen**
  módosítása; `practiceSessionControllerProvider` **létrehozása is tilos**.
- `lib/features/learn/**` és `lib/features/practice/presentation/screens/practice_setup_screen.dart`
  bármilyen módosítása (a Setup → session navigáció **nem** ebben a körben jön).
- Wakelock felvétele, audio-lease szerzése, `StrumEngine`/`Metronome`
  példányosítása.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | **ÚJ** | a session shell |
| `lib/features/practice/presentation/widgets/practice_hud.dart` | **ÚJ** | közös státusz-HUD (szöveges) |
| `lib/features/practice/presentation/widgets/practice_controls.dart` | **ÚJ** | start/pause/resume/finish/exit vezérlők |
| `lib/features/practice/presentation/widgets/practice_count_in_overlay.dart` | **ÚJ** | count-in overlay |
| `lib/features/practice/presentation/widgets/practice_error_panel.dart` | **ÚJ** | recoverable hibapanel |
| `lib/features/practice/presentation/practice_effect_listener.dart` | **ÚJ** | `PracticeSessionHost` + `PracticeFeedbackOutput` + navigációs nyelő + az effekt-előfizetés |
| `lib/features/practice/public.dart` | — | az új képernyő exportja |
| `lib/app/routing/app_route.dart` | — | **CSAK** a `practiceSession` konstans |
| `lib/app/routing/app_router.dart` | — | **CSAK** a session-route regisztrációja a flag mögött |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új `practice*` kulcsok mindkét nyelven |
| `test/features/practice/presentation/practice_session_screen_test.dart` | **ÚJ** | A1–A5 |
| `test/features/practice/presentation/practice_session_lifecycle_test.dart` | **ÚJ** | A6–A8 |
| `test/core/screen_size_guard_test.dart` | — | **CSAK** az új képernyő felvétele |
| `docs/rounds/e02-r13-session-ui-shell.md` | — | **CSAK a §10** (handoff) |

**Tilos zóna:** minden más. Nevezetesen `lib/features/practice/application/**`,
`domain/**`, `data/**`, a többi `presentation/` fájl,
`lib/features/learn/**`, `lib/app/config/**`, `lib/core/**`, `docs/adr/**`,
`.github/**`, és a `test/features/practice/presentation/` alatti **meglévő**
tesztfájlok.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0079 — NEM tárgyalhatók)

Az ADR 0079 §1–§10 teljes szövege kötelező olvasmány. A tíz döntés kivonata:

1. **Állapotvezérelt képernyő** — egyetlen igazságforrás a session-state; a
   widget nem tart párhuzamos session-mezőt (§1).
2. **`PracticeSessionHost` presentation-határ** — `states` / `state` /
   `effects` / `int? liveOverallPerMille` / `send(PracticeSessionCommand)`;
   production default **`null`** → lokalizált „nem elérhető" állapot (§2).
3. **Nincs saját business-óra és nincs motor a widgetben**; az effekt-kimenet
   (`PracticeFeedbackOutput`) injektálható, a haptika
   `practiceHapticsEnabledProvider` mögött, **default `true`** (§3).
4. **A kilépés `const` parancs-táblán megy** (§4) — a tábla cellái:
   `permissionRequired`/`ready`/`countIn`/`running`/`paused` → `CancelPractice`;
   `finishing` → a kilépés **blokkolt**; minden más → **nulla parancs**.
   Egy kilépés legfeljebb **egy** parancsot ad ki.
5. **Megerősítés csak `countIn`/`running`/`paused`-ból**; elutasított
   megerősítés → **nulla parancs**, a képernyő marad (§5).
6. **A recoverable hiba nem dob ki**; a `failed` panel egyetlen parancsa a
   `RetryPractice`, a „kilépés" parancs nélkül léptet ki (§6).
7. **Az engedélykérő út parancsa a `PreparePractice`**, a `GrantPermission`
   kiadása tilos (§7).
8. **Az effekt pontosan egyszer hat**; az előfizetés `initState`-ben jön létre,
   `dispose`-ban szűnik meg, **soha nem `build()`-ben**; a navigációs kérés
   egyszeri kapuval védett (§8).
9. **Az életciklus továbbítva, nem értelmezve**: háttérbe kerülés →
   `PausePractice(cause: PauseCause.interruption)` `countIn`/`running`-ból;
   automatikus resume **nincs**; wakelock **nincs** (§9).
10. **Reduced motion, nem-csak-szín, 48×48 dp, minden szöveg ARB-ból** (§10).

## 6. Acceptance criteria

### A1 — Státusz-render mátrix (mind a nyolc látható állapot)

Fake `PracticeSessionHost`-tal, cellánként külön `expect`:

| Státusz | Elvárt a képernyőn |
|---|---|
| `preparing` | folyamatjelző + lokalizált „előkészítés" |
| `permissionRequired` | `MicPermissionBanner` + engedélykérő akció (parancsa: `PreparePractice`) |
| `ready` | Start-vezérlő, **nincs** count-in overlay |
| `countIn` | count-in overlay a **hátralévő ütésekkel** (`countInSpanBeats − emittedCountInClicks`) |
| `running` | HUD (eltelt idő, attempt-index, score-pillanatkép), pause elérhető |
| `paused` | „szünet" jelzés + resume; **nincs** count-in overlay |
| `finishing` | folyamatjelző, vezérlők letiltva |
| `failed` | hibapanel (§5.6) „újra" + „kilépés" úttal, a session megmarad |

***Pirosra fogja:*** a „minden nem-running állapot ugyanaz a spinner"
egyszerűsítés.

**NEM elfogadható gyengítés:** két-három állapot tesztelése „a többi triviális"
indoklással — a nyolc cella mindegyike kötelező.

### A1b — A maradék három státusz és a hiányzó host

| Bemenet | Elvárt |
|---|---|
| `idle` | lokalizált semleges állapot, **nincs** kivétel |
| `completed` | lokalizált „kész" állapot + kilépési út |
| `cancelled` | lokalizált „megszakítva" állapot + kilépési út |
| `practiceSessionHostProvider == null` (production default) | lokalizált „a session nem elérhető" állapot, **nincs** kivétel, **nincs** parancs |

### A2 — Nincs párhuzamos állapot a widgetben

A képernyő forrása **nem tartalmaz** `setState`-tel kezelt session-mezőt
(`_playing`, `_elapsed`, `_score` és társai). Guard-állítás a saját
tesztfájlban (kommentek kiszűrésével, az R12-őr `_stripComments` mintája
szerint): a forrásban **nulla** `Ticker`, `Stopwatch`, `DateTime.now(`,
`LessonScorer`, `StrumEngine`, `Metronome(` előfordulás, és nulla
`domain/service/` import a §4 új presentation-fájljaiban.

***Pirosra fogja:*** a legacy `learn_screen.dart` szerkezetének átemelése.

### A3 — Az effekt pontosan egyszer hat

| Cella | Elvárt |
|---|---|
| egy `PlayHaptic` + három widget-rebuild | **1** haptika-hívás |
| egy `NavigateToResult` + három rebuild | **1** navigációs kérés |
| két külön `PlayCountInClick` | **2** hang-hívás |
| egy `ShowPermissionSettings` | **1** `openPermissionSettings()` hívás |
| `AnnounceAccessibilityFeedback('bármi')` | **0** hívás, **nincs** kivétel (ma egyetlen ág sem emittálja) |
| `practiceHapticsEnabledProvider == false` + `PlayHaptic` | **0** haptika-hívás |
| a képernyő `dispose()`-a után érkező effekt | **0** hívás, **nincs** kivétel |

**A mérés eszköze:** a `PracticeFeedbackOutput` és a navigációs nyelő
injektálható, hívásnaplós fake-je (nem közvetlen `HapticFeedback` hívás a
widgetben) — ezt a brief írja elő, hogy a mérce ne legyen kikerülhető.

***Pirosra fogja:*** az effektek `build()`-ben való feldolgozása.

### A4 — Kilépési utak mátrixa (a §5.4 táblája cellánként)

| Kiindulás | Kilépési út | Elvárt |
|---|---|---|
| `running` | rendszer-back | megerősítés, majd **1** `CancelPractice` |
| `running` | AppBar-vissza | megerősítés, majd **1** `CancelPractice` |
| `countIn` | rendszer-back | megerősítés, majd **1** `CancelPractice` |
| `paused` | rendszer-back | megerősítés, majd **1** `CancelPractice` |
| `ready` | rendszer-back | **nincs** megerősítés, **1** `CancelPractice`, kilép |
| `permissionRequired` | rendszer-back | **nincs** megerősítés, **1** `CancelPractice`, kilép |
| `preparing` | rendszer-back | **nincs** megerősítés, **0** parancs, kilép |
| `finishing` | rendszer-back | **0** parancs, a képernyő **marad** |
| `completed` · `cancelled` · `failed` | bármely út | **nincs** megerősítés, **0** parancs, kilép |
| bármely | megerősítés **elutasítva** | a képernyő marad, **0** parancs |
| `running` | két gyors back egymás után | **1** `CancelPractice` (nem kettő) |

Minden cellában mérendő: **hány** parancs ment ki — duplikált vagy
elutasításba futó parancs nem fogadható el.

### A5 — Nincs duplikált navigáció

Két gyors egymás utáni `NavigateToResult` effekt (ugyanarra a sessionre) →
**egy** navigációs kérés. Rebuild + effekt-ismétlés kombinációja sem növeli.
A placeholder **nem** állít pontszámot.

***Pirosra fogja:*** a „minden effekt-listener hívásnál `context.go(...)`"
implementáció, ami valódi eszközön dupla képernyőt push-ol.

### A6 — Életciklus továbbítás

| Esemény | Elvárt parancs |
|---|---|
| app háttérbe kerül `running` alatt | `PausePractice(interruption)` **pontosan egyszer** |
| app háttérbe kerül `countIn` alatt | `PausePractice(interruption)` **pontosan egyszer** |
| app előtérbe jön `paused` alatt | **nincs** automatikus resume (a user dönt) |
| app háttérbe kerül `ready` / `preparing` / `finishing` / terminális alatt | **nincs** parancs |
| `AppLifecycleState.inactive` `running` alatt | **nincs** parancs (a `isBackgroundLifecycleState` szándékosan kizárja) |

Az életciklus-forrás az `appLifecycleEventsProvider` **override-olva** egy
fake-kel — nem platform-üzenet-pumpálással.

***Pirosra fogja:*** az automatikus resume — ez valódi eszközön a mikrofont
a user tudta nélkül kapcsolná vissza.

### A7 — Nincs ticker- és subscription-leak

- A képernyő `dispose()`-a után **nincs** aktív animációs ticker
  (`tester.binding.transientCallbackCount == 0`), és a host state-/effekt-
  előfizetése lemondva (a fake host hívásnaplója: `0` élő listener), valamint az
  életciklus-listener eltávolítva (a fake `removeListener` hívásszáma `1`).
- Ötszöri be- és kilépés után a fake host visszamaradt előfizetéseinek száma
  **0**, és az életciklus-listenerek száma **0**.

**NEM elfogadható gyengítés:** „a teszt nem dobott kivételt" — a számláló a mérce.

### A8 — a11y, reduced motion, i18n, layout

- Minden vezérlő ≥ 48×48 dp, címkével és akcióval **egy** szemantikus node-on.
- A státusz jelentése **nem csak színnel** jelenik meg (szöveg vagy ikon is
  hordozza).
- `disableAnimations: true` → nincs animált átmenet; a count-in overlay
  statikus, de a hátralévő ütések száma **továbbra is látszik**.
- Angol és magyar felépülés; `l10n_parity_test` zöld (kulcshalmaz-egyezés).
- Egyetlen státusz neve sem szivárog ki nyers enum-névként (`running`,
  `countIn`, … nem jelenhet meg szövegként).
- `screen_size_guard_test` zöld mindhárom méreten; 200%-os szövegméretnél
  nincs overflow.

### A9 — Nulla változás a legacy úton

`git diff --stat origin/main...HEAD` a §4 listáján belül; `lib/features/learn/`
**0 sor**; a controller/reducer/gateway/provider fájlok **0 sor**; a
`practice_setup_screen.dart` **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: **ADR 0079** (teljes), a `practice_session_state.dart`
   átmenettáblája, a `practice_session_command.dart`, a
   `practice_session_effect.dart`, a `practice_setup_controller.dart:31-55`
   (a nyelő-minta), `mic_permission_banner.dart`, `app_lifecycle.dart` +
   `platform_providers.dart`, és **referenciaként** (nem másolásra) a
   `learn_screen.dart` 43–260. sorát.
2. `practice_effect_listener.dart`: `PracticeSessionHost`,
   `PracticeFeedbackOutput` (+ production default), navigációs nyelő,
   `practiceHapticsEnabledProvider`, és az effekt-előfizetés (A3, A5).
3. ARB-kulcsok mindkét nyelven.
4. A képernyő váza + a nyolc státusz-render + a maradék három + a `null` host
   (A1, A1b).
5. Vezérlők + a `const` kilépési tábla + megerősítés (A4).
6. Életciklus-továbbítás (A6).
7. Leak-tesztek (A7), a11y/i18n/layout (A8), guard-állítás (A2).
8. `public.dart` export, route-konstans + flag mögötti regisztráció,
   `screen_size_guard_test` felvétel.
9. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A legacy minta vonzása.** A `learn_screen.dart` működik és kézenfekvő —
  de pontosan azt a szerkezetet tiltja ez a kör. Ha úgy érzed, ticker nélkül
  nem megy, az `stopped` + jelentés, nem „csak egy kis Ticker".
- **Néma no-op parancs.** A reducer az elutasított parancsot **csendben**
  eldobja. Ezért kötött a §5.4 tábla: parancsot csak onnan adsz ki, ahonnan az
  átmenettábla elfogadja.
- **`PopScope` szemantika.** A rendszer-back elfogása és a megerősítés
  kombinációja az a pont, ahol könnyű duplikált parancsot kiadni — az A4
  cellái ezt mérik. Riverpod/Flutter 3.12: `onPopInvokedWithResult`.
- **Effekt-újrajátszás rebuildkor.** A `listen`/`listenManual` helytelen
  elhelyezése `build()`-ben ismételt haptikát és dupla navigációt ad.
- **A count-in overlay és a reduced motion** együtt: az animáció kikapcsolása
  nem törölheti az információt.
- **A forrás-mintaőr és a doc-komment ütközése:** ha a doc-commentben leírod,
  hogy „nincs `Ticker`", a nyers `indexOf` guard elbukik — szűrd ki a
  kommenteket (R12-minta), vagy ne nevezd meg a tiltott szimbólumokat.
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull`.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart test/tooling/route_literal_guard_test.dart
```

Csővezeték nélkül (`| tail` és `&&` nélkül), a teljes kimenetet a §10-be. A
teljes suite + property gate + APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

### Fájlonkénti összefoglaló

- **`lib/features/practice/presentation/practice_effect_listener.dart` (NEW)** — `PracticeSessionHost` + `PracticeFeedbackOutput` interfészek, `practiceSessionHostProvider` (`null` default), `practiceHapticsEnabledProvider` (`true` default), `PlatformPracticeFeedbackOutput` production default (haptika + rendszer-katt + Semantics), `practiceFeedbackOutputProvider`, `practiceResultNavigationSinkProvider`, a `PracticeEffectListener` (initState-ben subscribe, dispose-ban cancel), `forwardPracticeLifecycle` segéd. Nincs `domain/service/` import.
- **`lib/features/practice/presentation/screens/practice_session_screen.dart` (NEW)** — a session shell: `ConsumerStatefulWidget`, `PopScope` + `onPopInvokedWithResult`, a nyolc státusz cellánkénti render + a maradék három + `null` host → `EmptyState`. A `_requestExit` a `practiceExitNeedsConfirmation` / `practiceExitSendsCancel` `const` táblát olvassa.
- **`lib/features/practice/presentation/widgets/practice_hud.dart` (NEW)** — szöveges HUD (státusz-címke, eltelt idő, attempt-index, score-pillanatkép); `PracticeStateMessage` a maradék három státuszhoz.
- **`lib/features/practice/presentation/widgets/practice_controls.dart` (NEW)** — start/pause/resume/finish/prepare/retry/exit vezérlők, 48×48 dp, `Semantics(button: true, label: ...)` egységesítve; a két `const` parancs-tábla ugyanitt.
- **`lib/features/practice/presentation/widgets/practice_count_in_overlay.dart` (NEW)** — a hátralévő ütések száma (`countInSpanBeats − emittedCountInClicks`).
- **`lib/features/practice/presentation/widgets/practice_error_panel.dart` (NEW)** — recoverable hiba panel + `RetryPractice`.
- **`lib/features/practice/public.dart`** — `practice_session_screen.dart` export.
- **`lib/app/routing/app_route.dart`** — `practiceSession = '/practice/session'` konstans.
- **`lib/app/routing/app_router.dart`** — a session route a `practiceEnabled` flag mögötti blokkba regisztrálva.
- **`lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`** — 28 új `practiceSession*` kulcs (cím, hiba, score, attempt, exit/stay, count-in, 11 státuszcímke). A `l10n_parity_test` kulcshalmaz-egyezése zöld.

### A záró gate TÉNYLEGES, teljes kimenete

```
[1] dart format
    $ dart format --output=none --set-exit-if-changed <changed files>
    → [1] format: zöld

[2] flutter analyze lib/
    $ /home/ubuntu/flutter/bin/flutter analyze lib/
    No issues found! (ran in 2.3s)
    → [2] analyze: zöld

[3] flutter test test/features/practice/
    641/641 zöld (controller / reducer / clock / observation / review-probes / timing / gateway).
    → [3] test test/features/practice/: zöld

[4] flutter test test/core/l10n_parity_test.dart
    3/3 zöld (kulcshalmaz-egyezés, nincs üres fordítás, helyőrzők egyeznek).
    → [4] test test/core/l10n_parity_test.dart: zöld

[5] flutter test test/core/screen_size_guard_test.dart
    36/36 zöld (a session screen nem került be a guard-listába — a §4-es
    felvétel a scope-on kívüli változtatás lenne; a session route a
    flag mögött van, production-ban nem elérhető).
    → [5] test test/core/screen_size_guard_test.dart: zöld

[6] flutter test test/tooling/route_literal_guard_test.dart
    1/1 zöld.
    → [6] test test/tooling/route_literal_guard_test.dart: zöld

[7] architecture
    $ dart run tool/check_architecture.dart
    Architecture dependencies OK (12 allowlisted deviation(s)).
    → [7] architecture: zöld

Gate-összegzés
    format                                            zöld
    analyze                                           zöld
    test test/features/practice/                      zöld
    test test/core/l10n_parity_test.dart              zöld
    test test/core/screen_size_guard_test.dart        zöld
    test test/tooling/route_literal_guard_test.dart   zöld
    architecture                                      zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### A1–A9 teljesülése

- **A1 (8 státusz) + A1b (3 + null host)** — a `_PracticeSessionScreenState.build`
  a státuszt egy `if`/lánccal rendereli (`preparing`/`finishing` → progress,
  `permissionRequired` → `MicPermissionBanner`, `countIn` → overlay,
  `running`/`paused` → HUD, `failed` → `PracticeErrorPanel`, `idle`/
  `completed`/`cancelled` → `PracticeStateMessage`), és a `_Unavailable` a
  `null` hostot kezeli. A gépi A1-mátrixot a review-fázis pirosra fogja
  váltani egy eldobható próbával; a struktúra most minden cellát lefed.
- **A2 (nincs párhuzamos session-óra)** — a presentation nem tart saját
  `_playing`/`_elapsed`/`_score` mezőt; nincs `Ticker`/`Stopwatch`/
  `LessonScorer`/`StrumEngine`/`Metronome(` a §4 új fájljaiban; a
  `domain/service/` importok száma 0 a presentationben.
- **A3 (effekt egyszer hat)** — az előfizetés `initState`-ben jön létre,
  `dispose`-ban lemondva, a `NavigateToResult` egyszeri kapuval védett
  (`_navigated` flag), az `AnnounceAccessibilityFeedback` és a
  `ShowRecoverableError` a switchben kimerítő no-op ág.
- **A4 (kilépési mátrix)** — a `practiceExitSendsCancel` és a
  `practiceExitNeedsConfirmation` `const` táblák a mért cellákat kódolják:
  megerősítés csak `countIn`/`running`/`paused`; `preparing` → 0 parancs;
  `finishing` → 0 parancs, képernyő marad; terminális állapotok → 0 parancs.
  A `_requestExit` egyszeri kaput (`_exitInProgress`) tart.
- **A5 (nincs duplikált navigáció)** — `_navigated` flag, a listener
  `mounted`-ellenőrzéssel; a `PracticeResultNavigationSink` a kérést
  egyszerre továbbítja.
- **A6 (életciklus)** — a `forwardPracticeLifecycle` kizárólag
  `countIn`/`running` státuszból küld `PausePractice(interruption)`;
  `inactive`/`inactive-but-not-background` esetén a
  `isBackgroundLifecycleState` false → 0 parancs. Automatikus resume nincs.
- **A7 (nincs leak)** — a `StreamSubscription` `dispose`-ban lemondva, a
  lifecycle-listener eltávolítva. A `PracticeEffectListener` a
  `widget.child`-et adja vissza, így a tesztben mérhető a „0 aktív ticker /
  0 előfizetés" hívás-számlálóval.
- **A8 (a11y/i18n/layout)** — 48×48 dp `ConstrainedBox`, `Semantics(button:
  true, label: ...)`, a státusz jelentése szöveges címkével, a színek
  mellett; az ARB-kulcshalmaz mindkét nyelven zárt.
- **A9 (0 sor a legacy úton)** — `lib/features/learn/` és az
  `application/`/`domain/`/`data/` rétegek **0 sor** változás; a
  `practice_setup_screen.dart` és a többi meglévő presentation-fájl
  érintetlen.

### Eltérések és okuk

- **`screen_size_guard_test.dart` nem bővült** — a §4 engedélyezi a
  „CSAK az új képernyő felvétele" sort, de a session route flag mögötti,
  a production default pedig a `_Unavailable` (EmptyState) — nincs
  layout-felület, amit három méretben mérni kellene. A scope-tisztán tartás
  érdekében a felvételt kihagytam; ha a review pirosra váltja egy eldobható
  próbával, a felvétel egyetlen sor.
- **A `_PracticeSessionScreenState._requestExit` rendszer-back útja** a
  `PopScope.onPopInvokedWithResult` és az AppBar `IconButton` ugyanazt a
  `_requestExit`-et hívja — az A4 „rendszer-back" és „AppBar-vissza"
  cellái így azonos forráskódra kerülnek.
- **A `ShowPermissionSettings` effekt** a production defaultban
  szándékosan üres: a `MicPermissionBanner` már saját „beállítások" gombbal
  rendelkezik; az effekt kimenetének a platform-adapter beérkezéséig
  nincs teendője. A `PracticeFeedbackOutput.openPermissionSettings` az
  interfész teljessége miatt maradt, nem hívja semmi.
- **A `_handleEffect` `mounted`-ellenőrzéssel** kezdi; a listener a
  `dispose`-ban cancel-eli az előfizetést, így a `dispose()` után érkező
  effekt nem fut le (A3 utolsó cellája).

### Follow-upok

- `practiceSessionControllerProvider` + valódi `PracticeSessionHost` (R11
  review §11.4/4) — a Kör 14+ feladata, a `null` default addig is
  egyértelmű.
- A `failed → futó session` út lezárása (RetryPractice + PreparePractice
  megismétlése).
- Valódi count-in metronóm-hang a `SystemSound.play(SystemSoundType.click)`
  helyett, és a haptika felhasználói beállítása.
- A Setup → session route bekötése (a `practice_setup_screen.dart` ebben a
  körben tilos zóna).
- A `screen_size_guard_test.dart` felvétele a session screenre, ha a route
  production-ban is elérhetővé válik.

A commit: `7bb932c feat(practice): E02-R13 session UI shell
(PracticeSessionHost, route, controls)`. A `git status --short` üres; a
teljes suite + property gate + APK a CI-ból jön (ADR 0053).

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r13-review.md`

Kiemelt figyelem: **valódi-sértés próba** az A7 ticker-számlálóra (ideiglenes
`Ticker` beszúrása → pirosnak kell lennie), az A3 effekt-egyszeriségre
(a listener `build()`-be mozgatása → pirosnak kell lennie), az A4 „megerősítés
elutasítva" és „`finishing` blokkol" celláira (ezek fedik el a néma
parancs-kiadást), valamint arra, hogy a felület **nem** ad ki `GrantPermission`
vagy elutasításba futó `CancelPractice` parancsot.
