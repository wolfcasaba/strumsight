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

## 10. Implementation handoff — az IMPLEMENTER tölti ki (javító kör #2)

A második javító kör a review három új MAJOR és egy MINOR leletét zárta.
Minden változás a §4 engedélyezett fájllistáján belül maradt; az ADR 0079,
a brief §1–§9, a reviewer jelentése és a tiltott application/domain/data/core
rétegek érintetlenek.

### Fájlonkénti összefoglaló

- **`lib/features/practice/presentation/practice_effect_listener.dart`** — a
  `practiceErrorOverlayProvider` legacy `StateProvider` helyett kézzel írt
  `PracticeErrorOverlayController` + `NotifierProvider.autoDispose`, ezért az
  overlay állapota az aktív képernyő figyelőihez kötött, és új belépéskor üres.
  A `ShowRecoverableError` ezen a controlleren keresztül mutatja a hibát. Az
  `AnnounceAccessibilityFeedback` ága dokumentáltan elnyeli a nyers kulcsot,
  amíg nincs ARB-backed kulcs→szöveg leképezés; a
  `PlatformPracticeFeedbackOutput.announce` production implementációja
  változatlan maradt. A `flutter_riverpod/legacy.dart` import megszűnt.
- **`lib/features/practice/presentation/screens/practice_session_screen.dart`** —
  `failed` státuszban csak a státusz-vezérelt `PracticeErrorPanel` renderelődik;
  az effekt-vezérelt `_RecoverableErrorOverlay` ebben az állapotban el van
  nyomva, így a reducer szándékos `failed` + `ShowRecoverableError`
  együttállása egyetlen hibafelületet ad.
- **`test/features/practice/presentation/practice_session_screen_test.dart`** —
  három új zárócella került be: a `failed` + `ShowRecoverableError` kombináció
  pontosan egy `PracticeErrorPanel`-t és egy hibacím-szöveget mér; a be→effekt→ki→
  újra-be ciklus ugyanabban a `ProviderScope`-ban nulla örökölt panelt és nulla
  hibacímet mér; az A2 forrásőr a teljes `lib/` alatt tiltja a legacy Riverpod
  importot. Az A3 meglévő accessibility-cellája most már közvetlenül a
  `_RecordingFeedback.announcements` listát is méri, a haptika és navigáció
  nullasága mellett.
- **`docs/rounds/e02-r13-session-ui-shell.md`** — kizárólag ez a §10 frissült a
  javító kör fájlonkénti összefoglalójával, a teljes záró gate-kimenettel, a
  négy lelet teszt-hivatkozásaival és az eltérésekkel.

### A négy lelet zárásának bizonyítéka

- **MAJOR-1 — dupla hibafelület:**
  `practice_session_screen_test.dart` / `Review regressions — recoverable errors`
  / **`failed + ShowRecoverableError renders one panel and one error title`**.
  A cella az effekt megérkezése után külön méri a
  `find.byType(PracticeErrorPanel) == 1` és a lokalizált hibacím
  `find.text(...) == 1` predikátumot.
- **MAJOR-2 — képernyők közti átszivárgás:** ugyanazon csoport
  **`leave and re-enter in the same ProviderScope shows no stale error`**
  cellája egyetlen gyökér-`ProviderScope` megtartása mellett eltávolítja, majd
  újra felépíti a session screent; a második belépés után
  `PracticeErrorPanel == 0` és hibacím-szöveg `== 0`.
- **MAJOR-3 — nyers accessibility-kulcs:** A3 / **`AnnounceAccessibilityFeedback
  ("anything") → 0 calls, no throw`**. A cella
  `fb.announcements.isEmpty`, `fb.hapticCalls == 0`, `nav.calls == 0` és
  `tester.takeException() == null` állításokat mér.
- **MINOR-1 — legacy Riverpod:** A2 / **`no flutter_riverpod legacy import
  remains under lib`** rekurzívan minden `lib/**/*.dart` fájlt mér. A promptban
  kért külön ellenőrzés, `grep -rn "flutter_riverpod/legacy" lib/`, üres
  kimenettel és 0 kilépési kóddal futott.

A TDD RED futásban mind a négy mérce a várt okból piros volt (legacy import,
1 announcement, 2 hibacím, illetve 1 visszaszivárgó hibacím). A minimális
production változtatás után a célzott screen teszt **36/36**, a változatlan
lifecycle teszt **12/12** zöld lett. A kötelező practice suite a korábbi
**686-ról 689 cellára nőtt**.

### A záró gate TÉNYLEGES, teljes, csonkítatlan kimenete

Parancs (egyetlen hívás, csővezeték és `tail` nélkül):

`tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart test/tooling/route_literal_guard_test.dart`

Az alábbi blokk a futás **1023 soros** stdout/stderr kimenete változtatás és
rövidítés nélkül:

```text

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 569 files (0 changed) in 2.06 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Analyzing 3 items...                                            
No issues found! (ran in 2.8s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/practice/
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice/

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart
00:00 +0: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter validation accepts 4/4, 3/4, and supported 6/8 meter
00:00 +1: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter validation rejects beats-per-bar values outside 1 through 16
00:00 +2: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter validation rejects unsupported beat units
00:00 +3: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter validation aggregates independent field failures
00:00 +4: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter tick arithmetic computes exact ticks per bar for supported meters
00:00 +5: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter tick arithmetic fails fast symmetrically for every invalid input field
00:00 +6: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/meter_test.dart: Meter value semantics uses both fields as its value identity
00:00 +7: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares lists structurally and hashes equal lists equally
00:00 +8: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_value_equality_test.dart: Practice value equality helpers compares maps structurally independent of insertion order
00:01 +9: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation accepts a complete valid definition
00:01 +10: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation aggregates definition fields and nested Tempo failures
00:01 +11: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects a non-positive total duration
00:01 +12: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation requires a non-empty target list only for scored modes
00:01 +13: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports decreasing positions as unsorted
00:01 +14: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate event IDs independently of positions
00:01 +15: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation reports duplicate positions without treating them as unsorted
00:01 +16: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation rejects positions at and beyond the exclusive totalBeats bound
00:01 +17: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation passes nested event failures through unchanged
00:01 +18: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation enforces exact mode-to-weight-key compatibility
00:01 +19: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition validation displayTitle accepts null and non-blank text, rejects blank
00:01 +20: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_definition_test.dart: PracticeDefinition value semantics deeply compares lists and supports Set and Map keys
00:01 +21: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion uses one final microsecond rounding step
00:01 +22: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter forward conversion exposes exact quarter-beat and meter-aware bar durations
00:01 +23: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion round-trips every 32-tick grid point over 64 quarter beats
00:01 +24: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter inverse conversion rejects negative elapsed time
00:01 +25: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid tempo
00:01 +26: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_time_converter_test.dart: BeatTimeConverter validation guards every conversion member rejects an invalid meter
00:02 +27: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/domain_purity_test.dart: practice domain has no ambient IO, nondeterminism, or app imports
00:02 +28: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/domain_purity_test.dart: purity scan ignores forbidden spellings in comments and strings
00:02 +29: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/domain_purity_test.dart: purity scan recognizes root l10n and Riverpod imports
00:02 +30: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/domain_purity_test.dart: purity scan inspects executable string interpolation bodies
00:02 +31: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels accepts null and sharp-spelled major or minor labels
00:02 +32: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: canonical practice chord labels rejects empty, no-chord, flat, extended, lowercase, and padded labels
00:02 +33: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation accepts scored events and a marker without scored attributes
00:02 +34: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation reports an empty ID with the pinned code literal
00:02 +35: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation rejects a zero duration with the pinned code literal
00:02 +36: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation requires a scored attribute on a non-marker event
00:02 +37: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation forbids scored attributes on marker events
00:02 +38: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent validation aggregates independent event failures
00:02 +39: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_test.dart: PracticeEvent value semantics supports structural equality, hashing, Set, and Map keys
00:03 +40: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions uses 480 ticks per quarter-note beat
00:03 +41: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition subdivisions represents supported fractions with exact integer equality
00:03 +42: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge converts the current half-beat grid without deviation
00:03 +43: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge round-trips every supported deterministic subdivision position
00:03 +44: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rounds one third of a beat to the nearest exact triplet tick
00:03 +45: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition legacy bridge rejects non-finite legacy input explicitly
00:03 +46: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants rejects negative data-driven positions in every runtime path
00:03 +47: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition invariants keeps the const constructor guarded in checked builds
00:03 +48: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations sorts deterministically and compareTo agrees with equality
00:03 +49: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations adds and subtracts positions exactly
00:03 +50: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/beat_position_test.dart: BeatPosition value operations has a deterministic diagnostic representation
00:04 +51: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/tempo_test.dart: Tempo validation accepts the closed 30.0 through 300.0 BPM boundaries
00:04 +52: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/tempo_test.dart: Tempo validation reports finite values outside the range without clamping
00:04 +53: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/tempo_test.dart: Tempo validation reports NaN and infinities as not finite
00:04 +54: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/tempo_test.dart: Tempo value semantics uses BPM as its value identity
00:05 +55: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode defines the complete stable code set
00:05 +56: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins target compiler validation and failure codes
00:05 +57: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_validation_test.dart: PracticeValidationCode pins the five pre-existing codes at their producing boundaries
00:05 +58: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has value semantics
00:05 +59: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_validation_test.dart: PracticeValidationFailure has a deterministic diagnostic representation
00:05 +60: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models scalar models compare structurally and hash equal values equally
00:05 +61: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate compares every list and scalar structurally
00:05 +62: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/compiled_practice_target_test.dart: Compiled practice target value models aggregate stores unmodifiable snapshots of every list
00:06 +63: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation accepts all closed range boundaries
00:06 +64: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation reports empty IDs and an invalid snapshot version
00:06 +65: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects count-in values outside zero through four
00:06 +66: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects loop counts outside one through 32
00:06 +67: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects input latency outside zero through 500 milliseconds
00:06 +68: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation rejects visual latency outside zero through 500 milliseconds
00:06 +69: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation requires a strictly positive session timeout
00:06 +70: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation passes nested Tempo failures through unchanged
00:06 +71: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig validation aggregates at least three independent failures
00:06 +72: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_config_test.dart: PracticeSessionConfig value semantics compares all fields and copyWith preserves or changes explicitly
00:07 +73: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation accepts a valid attempt and aggregates nested values
00:07 +74: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects a negative attempt index
00:07 +75: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation rejects duplicate verdict target IDs
00:07 +76: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeAttemptResult validation compares the verdict list and all other fields structurally
00:07 +77: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation accepts a valid session with canonical coaching codes
00:07 +78: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an empty session ID and attempt list
00:07 +79: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation requires attempt indexes to be strictly increasing
00:07 +80: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation continues nested validation after an attempt ordering failure
00:07 +81: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects negative active and paused durations
00:07 +82: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation rejects an unknown coaching-summary code
00:07 +83: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation aggregates attempt and highest-stable-tempo failures
00:07 +84: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult validation compares attempt and coaching lists structurally
00:07 +85: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts finalAttempt selects the greatest index independent of list order
00:07 +86: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt selects the greatest available overall score
00:07 +87: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts bestAttempt breaks score ties with the smaller index
00:07 +88: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_result_test.dart: PracticeSessionResult derived attempts derived getters return null when no attempt is comparable
00:08 +89: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation accepts available score boundaries and explicit unavailable states
00:08 +90: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation reports non-finite values without a duplicate range failure
00:08 +91: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation rejects finite values outside zero through one
00:08 +92: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: MetricValue validation requires an insufficient-data reason code
00:08 +93: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation accepts a valid metric set including signed timing bias
00:08 +94: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation passes nested metric failures through unchanged
00:08 +95: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative total target count
00:08 +96: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects resolved targets greater than total targets
00:08 +97: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects negative max combo and score points
00:08 +98: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: PracticeMetrics validation rejects a negative mean absolute offset
00:08 +99: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares every MetricValue subtype by structure and subtype
00:08 +100: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_metrics_test.dart: Practice metric value semantics compares PracticeMetrics structurally
00:09 +101: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120001 us is outside the chord window
00:09 +102: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -120000 us is inside the chord window
00:09 +103: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window -119999 us is inside the chord window
00:09 +104: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 419999 us is inside the chord window
00:09 +105: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420000 us is inside the chord window
00:09 +106: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 inclusive asymmetric window 420001 us is outside the chord window
00:09 +107: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable expected label is correct
00:09 +108: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches stable different label is wrong
00:09 +109: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches only null labels are noDetection, not wrong or insufficient
00:09 +110: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches an empty target window is insufficient data
00:09 +111: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a label below the stability threshold is insufficient data
00:09 +112: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer A3 outcome branches a target without an expected chord is not applicable
00:09 +113: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the longest stable segment wins even when it is the wrong chord
00:09 +114: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation nonconsecutive runs of the same label are not merged
00:09 +115: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unordered observations produce the same deterministic result
00:09 +116: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation available outcomes use one integer truncating division
00:09 +117: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation samples outside every window report insufficient samples
00:09 +118: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation unmatched optional chord target does not dilute the metric
00:09 +119: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_chord_scorer_test.dart: PracticeChordScorer stability and aggregation the event-score view rejects mutation
00:11 +120: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes pins every code, round-trips, and rejects unknown codes
00:11 +121: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeMode stable codes exposes the exact scored dimensions for each mode
00:11 +122: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeSource stable codes pins every code, round-trips, and rejects unknown codes
00:11 +123: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeDifficulty stable codes pins every code, round-trips, and rejects unknown codes
00:11 +124: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeScoreDimension stable codes pins every code, round-trips, and rejects unknown codes
00:11 +125: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: ExtraStrumPolicy stable codes pins every code, round-trips, and rejects unknown codes
00:11 +126: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: TimingGrade stable codes pins every code, round-trips, and rejects unknown codes
00:11 +127: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeAttemptOutcome stable codes pins every code, round-trips, and rejects unknown codes
00:11 +128: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_enums_test.dart: PracticeFinishReason stable codes pins every code, round-trips, and rejects unknown codes
00:12 +129: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 0 us is exactly 1000 per mille
00:12 +130: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 0 us is exactly 1000 per mille
00:12 +131: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 49999 us is exactly 1000 per mille
00:12 +132: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 49999 us is exactly 1000 per mille
00:12 +133: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50000 us is exactly 1000 per mille
00:12 +134: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50000 us is exactly 1000 per mille
00:12 +135: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 50001 us is exactly 800 per mille
00:12 +136: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 50001 us is exactly 800 per mille
00:12 +137: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 119999 us is exactly 800 per mille
00:12 +138: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 119999 us is exactly 800 per mille
00:12 +139: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120000 us is exactly 800 per mille
00:12 +140: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120000 us is exactly 800 per mille
00:12 +141: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 120001 us is exactly 800 per mille
00:12 +142: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 120001 us is exactly 800 per mille
00:12 +143: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 200000 us is exactly 575 per mille
00:12 +144: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 200000 us is exactly 575 per mille
00:12 +145: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 279999 us is exactly 351 per mille
00:12 +146: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 279999 us is exactly 351 per mille
00:12 +147: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix early 280000 us is exactly 350 per mille
00:12 +148: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix late 280000 us is exactly 350 per mille
00:12 +149: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer A1 boundary matrix an unmatched required target is a zero-score miss
00:12 +150: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation uses integer accumulation and one truncating mean division
00:12 +151: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation signed timing bias truncates toward zero in integer microseconds
00:12 +152: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation open unmatched optional target does not dilute the rhythm dimension
00:12 +153: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation finalized unmatched optional target does not dilute the rhythm dimension
00:12 +154: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation an empty target has no applicable rhythm metric
00:12 +155: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_timing_scorer_test.dart: PracticeTimingScorer aggregation the event-score view rejects mutation
00:12 +156: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts a valid weighted profile and an empty weight map
00:12 +157: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation accepts closed threshold endpoints and equal positive windows
00:12 +158: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation pins the legacy Learn parity profile literals
00:12 +159: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation validates the four built-in non-strum profiles and pins literals
00:12 +160: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation built-in non-strum profile weights exactly match their mode scored dimensions
00:12 +161: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation reports an empty identifier with the pinned code literal
00:12 +162: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects zero and negative windows
00:12 +163: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects perfect greater than good and good greater than match
00:12 +164: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects weight sums of 99 and 101
00:12 +165: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects a negative weight independently of the exact sum
00:12 +166: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation rejects thresholds outside the closed zero to 100 range
00:12 +167: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile validation aggregates independent failures in one call
00:12 +168: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/scoring_profile_test.dart: ScoringProfile value semantics compares the weight map structurally and hashes it by value
00:14 +169: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target legacy baseline parity ten frozen scenarios match finish and every event within 1 us
00:14 +170: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity pins all 17 lesson IDs in the measured order
00:14 +171: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity all valid 50, 75 and 100 percent tempos match within 1 us
00:14 +172: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity first-waltz explicitly measures the three-beat count-in edge
00:14 +173: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target shipped-lesson parity eighth-drive explicitly measures its closest-to-end event
00:14 +174: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants whole-bar rounding is a no-op for every pinned shipped ID
00:14 +175: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_legacy_parity_test.dart: Practice target corpus invariants eventless Analyze import keeps one positive 4/4 bar
00:15 +176: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation accepts closed confidence boundaries for both observation types
00:15 +177: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative timestamp
00:15 +178: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects a negative strum sequence
00:15 +179: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation reports non-finite confidence without a duplicate range failure
00:15 +180: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation rejects finite confidence outside zero through one
00:15 +181: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation validation uses the canonical chord-label contract including null
00:15 +182: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_observation_test.dart: PracticeObservation value semantics compares each concrete subtype structurally
00:16 +183: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure rounds a partial 4/4 definition up to a complete final bar
00:16 +184: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses three quarter beats per 3/4 count-in and bar step
00:16 +185: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure pins two count-in bars and repeated-pass bar boundaries
00:16 +186: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure gives a downbeat event and its bar boundary the same time at 90 BPM
00:16 +187: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure computes total duration from all absolute ticks at 90 BPM
00:16 +188: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure compiles the final in-range tick instead of dropping it
00:16 +189: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure uses effective tempo at 50 and 75 percent without accumulation
00:16 +190: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure excludes markers while preserving a one-event target
00:16 +191: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure projects target metadata and every scored event field
00:16 +192: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler timeline structure a marker-only scored definition compiles without scored events
00:16 +193: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops repeats every source event with absolute positions and loop indexes
00:16 +194: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops selects one source bar and rebases it before repeating
00:16 +195: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops accepts the rounded final partial bar as a whole-bar loop
00:16 +196: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops computes barIndex from ticksPerBar for multi-bar passes
00:16 +197: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:16 +198: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:16 +199: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler loops rejects invalid loop range Instance of 'PracticeLoopRange' without clamping
00:16 +200: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments matches the pinned legacy pre-roll and merges repeated labels
00:16 +201: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments uses the named 120-tick lookahead for a one-beat chord change
00:16 +202: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments returns no segments when no compiled event carries a chord
00:16 +203: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments extends one chord across the complete session timeline
00:16 +204: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler expected-chord segments carries chord changes across a repeated loop boundary
00:16 +205: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition validation wins and rejects zero totalBeats
00:16 +206: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order config validation wins before definition ID mismatch
00:16 +207: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order definition ID mismatch wins before variation mismatch
00:16 +208: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order rejects a non-matching Easy variation explicitly
00:16 +209: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order variation mismatch wins before an invalid loop range
00:16 +210: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler validation order accepts a matching non-null Easy variation ID
00:16 +211: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs compiles positive-length Free Practice without target events
00:16 +212: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_target_compiler_test.dart: PracticeTargetCompiler empty and deterministic outputs returns equal, hash-equal targets with nondecreasing event times
00:17 +213: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting does not fill an unavailable chord dimension with zero
00:17 +214: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting pins every integer overall table cell
00:17 +215: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A4 available-dimension weighting free practice has no overall score
00:17 +216: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 699 overall
00:17 +217: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 16 of 20 resolved and 700 overall
00:17 +218: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 699 overall
00:17 +219: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 17 of 20 resolved and 700 overall
00:17 +220: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 699 overall
00:17 +221: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate 18 of 20 resolved and 700 overall
00:17 +222: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate zero resolved targets is incomplete rather than failed
00:17 +223: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate unmatched optional target is excluded from completion counters
00:17 +224: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: PracticeScoreAggregator A5 completion and pass gate matched optional target is excluded from completion counters
00:17 +225: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: A6 increments combo before the fifth-hit multiplier
00:17 +226: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a wrong direction resets before the next clean hit
00:17 +227: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation a miss resets before the next clean hit
00:17 +228: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched down optional target neither increments nor resets combo
00:17 +229: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: A6 combo resets and optional isolation matched up optional target neither increments nor resets combo
00:17 +230: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_score_aggregator_test.dart: A8 every verdict and the complete attempt result are valid
00:18 +231: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts matched and unmatched consistent verdicts at score bounds
00:18 +232: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports an empty target event ID
00:18 +233: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation reports non-finite event score without a duplicate range failure
00:18 +234: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects finite event scores outside zero through one
00:18 +235: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects unmatched verdicts with observed time or matched grades
00:18 +236: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation accepts and pins all five canonical coaching codes
00:18 +237: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict validation rejects an unknown coaching code
00:18 +238: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_verdict_test.dart: PracticeVerdict value semantics compares all scalar, enum, and nullable fields
00:19 +239: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:19 +240: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity keeps every compiled event within 0.5 us of legacy time
A1b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:19 +241: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the first-strums compiled eligibility divergence
00:19 +242: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity pins the anthem-drive [5, 6] compiled midpoint divergence
00:19 +243: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_parity_test.dart: PracticeEventMatcher legacy LessonScorer parity matches every target exactly across all 51 latency scenarios
A1 parity scenarios=51 maximumDifferenceUs=0 excludedObservations=0
00:19 +244: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries pins all six cells around the 280 ms boundary
00:19 +245: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher eligibility and close boundaries exact boundary stays open and eligible after advance
00:19 +246: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher latency correction pins matching and closing for 0, 40 and 300 ms latency
00:19 +247: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking midpoint and neighboring microseconds choose the pinned target
00:19 +248: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher tie breaking equal-time targets choose the smaller list index
00:19 +249: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a wrong direction consumes the target before a correct retry
00:19 +250: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an out-of-window extra leaves every target resolution unchanged
00:19 +251: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution one observation resolves at most one of two eligible targets
00:19 +252: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution a restarted gateway sequence can match a later target
00:19 +253: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution resolved count is monotonic and terminal results never reopen
00:19 +254: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize separates required misses from unmatched optional targets
00:19 +255: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an optional target remains matchable before its window closes
00:19 +256: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution finalize is idempotent
00:19 +257: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution signed offsets keep early negative and late positive
00:19 +258: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher one-to-one resolution an empty target is safe to match, advance, and finalize
00:19 +259: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics separate matchers produce equal results and hash codes
00:19 +260: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics targetIndex alone contributes to equality
00:19 +261: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics target alone contributes to equality
00:19 +262: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics resolution alone contributes to equality
00:19 +263: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics matched observation sequence alone contributes to equality
00:19 +264: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics observedAt and timingOffset together contribute to equality
00:19 +265: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatchResult value semantics results rejects mutation
00:19 +266: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 20k targets and 1k strums stay below the cursor threshold
A6 cursor examined=43000 threshold=1344000
00:19 +267: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_event_matcher_test.dart: PracticeEventMatcher measured scaling 100k extras do not grow retained records beyond four targets
A6 memory retained=4 threshold=4
00:21 +268: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeMetricReasonCode pins the complete stable code set
00:21 +269: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched equal direction is correct and worth 1000 per mille
00:21 +270: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix matched different direction is wrong and worth zero
00:21 +271: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix unmatched directional target is wrong when signal existed
00:21 +272: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when matched
00:21 +273: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix target without direction is not applicable when unmatched
00:21 +274: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer A2 matrix directional targets with zero strum signal are insufficient data
00:21 +275: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a matched sequence has no observation mapping
00:21 +276: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation uses integer accumulation and one truncating division
00:21 +277: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation open unmatched optional direction target does not dilute the metric
00:21 +278: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation finalized unmatched optional direction target does not dilute the metric
00:21 +279: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation target-index pairing supports restarted observation sequences
00:21 +280: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation fails fast when a target mapping carries the wrong sequence
00:21 +281: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_direction_scorer_test.dart: PracticeDirectionScorer input and aggregation the event-score view rejects mutation
00:22 +282: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins the complete 16 lesson catalog plus first-win
00:22 +283: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity measures the compiled timebase guard at at most 0.5 us
A7b measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]
00:22 +284: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity matches score, combo, counters and direction across 51 scenarios
A7 parity scenarios=51 excludedGuardBandEvents=0
00:22 +285: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity pins 18 representative extrema divergence cells
A7c representativeDivergenceCells=18
00:22 +286: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_scorer_legacy_parity_test.dart: Practice scorer legacy LessonScorer parity discovers and pins every actual boundary divergence cell
A7c exhaustiveDivergenceCells=3213 fingerprint=375672841
00:22 +287: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState initial state is idle and empty
00:22 +288: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: same fields → equal
00:22 +289: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState value equality: any field change → not equal
00:22 +290: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState copyWith: explicit overrides win; cleared fields go to null
00:22 +291: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState timelinePosition: formula holds for all five anchor combinations
00:22 +292: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: PracticeSessionState isActive: true for countIn/running/paused/finishing only
00:22 +293: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) idle → preparing
00:22 +294: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) preparing → permissionRequired | ready | failed
00:22 +295: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) permissionRequired → preparing | cancelled
00:22 +296: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) ready → countIn | cancelled
00:22 +297: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) countIn → running | paused | cancelled | failed
00:22 +298: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) running → paused | finishing | cancelled | failed
00:22 +299: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) paused → countIn | running | finishing | cancelled
00:22 +300: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) finishing → completed | failed
00:22 +301: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) completed → ready | idle
00:23 +302: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) cancelled → ready | idle
00:23 +303: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) failed → preparing | idle
00:23 +304: /home/ubuntu/ss-mm-e02r13/test/features/practice/domain/practice_session_state_test.dart: allowedTransitions (SDD §11.2 verbatim) every status has a transition entry
00:24 +305: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:25 +306: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_lifecycle_test.dart: A6 — app-lifecycle forward matrix countIn + background → exactly 1 PausePractice(interruption)
00:25 +307: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:25 +308: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +309: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +310: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +311: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +312: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +313: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +314: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: hub renders a card per catalog definition with displayTitle
00:26 +315: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout controls have 48×48 dp hit area and one semantics node each
00:26 +316: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A1: empty catalog shows the localized empty state
00:26 +317: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_lifecycle_test.dart: A8 — a11y / i18n / layout countIn shows the remaining-beats number, even with reduced motion
00:26 +318: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
00:27 +319: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
00:27 +320: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by strumPattern leaves only strum-pattern cards
00:27 +321: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by chordChanges leaves only the chord-change card
00:27 +322: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A2: filtering by freePractice shows the lone free-practice card
00:27 +323: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A3: Continue/Recent blocks are absent — no placeholder data
00:27 +324: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A3: empty catalog hides the Quick Start entry, not just disables it
00:27 +325: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A3: daily-challenge failure is visible but disabled, not hidden
00:28 +326: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A3: daily-challenge success path shows the live card
00:28 +327: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_hub_screen_test.dart: A8: hungarian locale renders a hungarian title in the tree
00:28 +328: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +329: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +330: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +331: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +332: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +333: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +334: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +335: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +336: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +337: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:28 +338: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice builds the Hub
00:30 +339: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:30 +340: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix preparing shows the progress indicator
00:31 +341: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag ON, /practice/setup?id=<unknown> shows the localized error
00:31 +342: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix permissionRequired shows the CORE MicPermissionBanner
00:31 +343: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix permissionRequired shows the CORE MicPermissionBanner
00:31 +344: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice falls back to live (existing onException)
00:31 +345: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice falls back to live (existing onException)
00:31 +346: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix countIn shows the remaining beats overlay
00:31 +347: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice/setup also falls back to live
00:31 +348: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_routing_test.dart: A7: flag OFF, /practice/setup also falls back to live
00:31 +349: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix paused shows the pause label and Resume
00:31 +350: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix finishing shows progress AND disables the Exit button
00:31 +351: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1 — status render matrix failed renders the in-screen error panel with Retry
00:31 +352: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host idle renders the neutral state message
00:31 +353: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host completed renders the complete state + an exit path
00:31 +354: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host cancelled renders the cancelled state + exit path
00:32 +355: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A1b — remaining three statuses + null host null host renders the unavailable state — no exception
00:32 +356: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files all six files exist on disk
00:32 +357: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files no Ticker / Stopwatch / DateTime.now( / LessonScorer / StrumEngine / Metronome( in the new presentation files
00:32 +358: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files no `domain/service/` import in the new presentation files
00:32 +359: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A2 — no business-logic symbols in the new presentation files no flutter_riverpod legacy import remains under lib
00:32 +360: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix one PlayHaptic + three rebuilds → 1 haptic call
00:32 +361: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix one NavigateToResult + three rebuilds → 1 navigation call
00:32 +362: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix two distinct PlayCountInClick → 2 count-in click calls
00:32 +363: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix one ShowPermissionSettings → 1 openPermissionSettings call
00:32 +364: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix AnnounceAccessibilityFeedback("anything") → 0 calls, no throw
00:32 +365: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: A3 — effect single-fire matrix haptics disabled + PlayHaptic → 0 haptic calls
00:32 +366: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors failed + ShowRecoverableError renders one panel and one error title
00:32 +367: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A4 controller matrix — domain-derived limits only BPM 29 invalid, 30 valid, 300 valid, 301 invalid
00:32 +368: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors leave and re-enter in the same ProviderScope shows no stale error
00:32 +369: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors leave and re-enter in the same ProviderScope shows no stale error
00:32 +370: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors leave and re-enter in the same ProviderScope shows no stale error
00:32 +371: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_session_screen_test.dart: Review regressions — recoverable errors leave and re-enter in the same ProviderScope shows no stale error
00:32 +372: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +373: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +374: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +375: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +376: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +377: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +378: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +379: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:33 +380: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:34 +381: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:34 +382: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:34 +383: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:34 +384: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Free Practice hides the scoring profile row
00:34 +385: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility Rhythm-only hides the chord-hint control
00:34 +386: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A5 mode-specific visibility strumPattern shows the scoring profile row
00:34 +387: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape start() sends exactly one PreparePractice with the UI fields
00:34 +388: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: A6 Start command shape Start button is disabled when config is invalid
00:34 +389: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: unknown id shows the localized error state
00:35 +390: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: missing id shows the localized error state
00:35 +391: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +392: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +393: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +394: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +395: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +396: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +397: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +398: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +399: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +400: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +401: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +402: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +403: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +404: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +405: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +406: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +407: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:35 +408: /home/ubuntu/ss-mm-e02r13/test/features/practice/presentation/practice_setup_screen_test.dart: the meter readout renders the definition meter (3/4, 6/8, 4/4)
00:36 +409: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 single-bar 8-slot pattern, 1 chord
00:36 +410: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 four-bar 8-slot pattern with up-strokes
00:36 +411: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 4/4 eight-bar full-eighth pattern
00:36 +412: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events 3/4 six-slot pattern over four bars
00:36 +413: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events mixed rests pattern still expands correctly
00:36 +414: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — parity with toLesson() events empty/whitespace name falls back to null displayTitle
00:36 +415: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — definition surface IDs, source, mode, profile match the ADR contract
00:36 +416: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects empty chords
00:36 +417: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects pattern length that does not fit the meter
00:36 +418: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects a pattern with only null slots
00:36 +419: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm above the Tempo ceiling (400)
00:36 +420: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes rejects bpm below the Tempo floor (10)
00:36 +421: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: practiceDefinitionFromSong — controlled failure modes none of the failure paths throws
00:36 +422: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/song_practice_adapter_test.dart: song_practice_adapter source guard forbidden to call Song.toLesson() — source-level scan
00:36 +423: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog catalog baseline: 16 curriculum + first-win
00:36 +424: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-strums matches every event slot exactly
00:36 +425: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-chord-change matches every event slot exactly
00:36 +426: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=eighth-drive matches every event slot exactly
00:36 +427: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=fifties-doo-wop matches every event slot exactly
00:36 +428: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=two-finger-frame matches every event slot exactly
00:36 +429: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-waltz matches every event slot exactly
00:36 +430: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=down-up-groove matches every event slot exactly
00:36 +431: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=folk-pattern matches every event slot exactly
00:36 +432: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=barre-groove matches every event slot exactly
00:36 +433: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=anthem-drive matches every event slot exactly
00:36 +434: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=rising-minor matches every event slot exactly
00:36 +435: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=waltz-time matches every event slot exactly
00:36 +436: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=reggae-skank matches every event slot exactly
00:36 +437: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=funk-chop matches every event slot exactly
00:36 +438: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=blues-shuffle matches every event slot exactly
00:36 +439: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=push-and-pull matches every event slot exactly
00:36 +440: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — full parity on the shipped catalog lesson.id=first-win matches every event slot exactly
00:36 +441: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-strums easy variant mirrors simplified events
00:36 +442: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-chord-change easy variant mirrors simplified events
00:36 +443: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=eighth-drive easy variant mirrors simplified events
00:36 +444: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=fifties-doo-wop easy variant mirrors simplified events
00:36 +445: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=two-finger-frame easy variant mirrors simplified events
00:36 +446: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-waltz easy variant mirrors simplified events
00:36 +447: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=down-up-groove easy variant mirrors simplified events
00:36 +448: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=folk-pattern easy variant mirrors simplified events
00:36 +449: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=barre-groove easy variant mirrors simplified events
00:36 +450: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=anthem-drive easy variant mirrors simplified events
00:36 +451: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=rising-minor easy variant mirrors simplified events
00:36 +452: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=waltz-time easy variant mirrors simplified events
00:36 +453: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=reggae-skank easy variant mirrors simplified events
00:36 +454: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=funk-chop easy variant mirrors simplified events
00:36 +455: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=blues-shuffle easy variant mirrors simplified events
00:36 +456: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=push-and-pull easy variant mirrors simplified events
00:36 +457: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — Easy parity lesson.id=first-win easy variant mirrors simplified events
00:36 +458: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency chord labels match legacyPracticeChordLabel for every event
00:36 +459: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency twoFingerFrame chords normalize to Em / C in order
00:36 +460: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency bluesShuffle chords normalize to A / D
00:36 +461: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency every chord in every lesson definition is canonical
00:36 +462: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — displayTitle + chord consistency displayTitle carries the lesson name and falls back to null
00:36 +463: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes returns Failure for empty events list
00:36 +464: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — controlled failure modes displayTitle trims whitespace and becomes null for empty name
00:36 +465: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/lesson_practice_adapter_test.dart: practiceDefinitionFromLesson — difficulty mapping preserves beginner, intermediate and advanced tiers
00:37 +466: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism the same epoch day produces structurally equal definitions
00:37 +467: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism consecutive epoch days produce different definitions
00:37 +468: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — determinism definition ID encodes the epoch day
00:37 +469: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern longer than 8 slots is truncated to 8 events
00:37 +470: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling pattern shorter than 8 slots is preserved as-is
00:37 +471: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling every event has a null chord (strum-only)
00:37 +472: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — pattern handling event positions are eighth-note slots starting at zero
00:37 +473: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface source, mode, keys, difficulty, profile match ADR contract
00:37 +474: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — definition surface custom bpm is honored when in range
00:37 +475: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes empty pattern is rejected
00:37 +476: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes bpm out of range is rejected
00:37 +477: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes non-finite bpm is rejected
00:37 +478: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — controlled failure modes none of the failure paths throws
00:37 +479: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/daily_challenge_practice_adapter_test.dart: practiceDefinitionFromDailyChallenge — displayTitle trims whitespace and falls back to null for empty names
00:37 +480: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for null input
00:37 +481: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty and whitespace-only labels
00:37 +482: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel passes canonical labels through unchanged
00:37 +483: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel reduces 7th / minor variants to their parent majmin
00:37 +484: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel rewrites flat roots to their sharp enharmonic
00:37 +485: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel drops the slash-bass of a slash chord
00:37 +486: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for unparseable roots
00:37 +487: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel returns null for empty after slash-bass removal
00:37 +488: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel trims surrounding whitespace before parsing
00:37 +489: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/legacy_chord_label_test.dart: legacyPracticeChordLabel every non-null output is canonical
00:37 +490: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip three strums with two chord lanes produce deterministic ticks
00:37 +491: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip preserves 3/4 meter on the resulting definition
00:37 +492: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — non-empty clip unordered strums come out sorted
00:37 +493: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=0 falls back to 90 BPM
00:37 +494: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=400 falls back to 90 BPM
00:37 +495: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=NaN falls back to 90 BPM
00:38 +496: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — BPM fallbacks bpm=80 is preserved
00:38 +497: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — tick collision forward-push two strums 0.0005s apart push the second onto the next tick
00:38 +498: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list falls back to freePractice + open scoring + no events
00:38 +499: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — empty strum list all-non-finite strums are dropped, triggering empty-branch
00:38 +500: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes blank sourceId is rejected
00:38 +501: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — controlled failure modes out-of-range beatsPerBar is rejected
00:38 +502: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — in-loop timeline grow totalBeats grows by one bar when rounding lands on the bound
00:38 +503: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — t0 normalization non-zero t0 normalizes times, and last tick at bound-1 keeps totalBeats at 4.0
00:38 +504: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/adapters/analyze_practice_adapter_test.dart: practiceDefinitionFromAnalyze — definition surface source, difficulty, keys, tags match ADR contract
00:38 +505: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=0 → at=0, no log
00:38 +506: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 1: (-1,-1), timelineNow=10s → at=10s, no log
00:38 +507: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=0 → at=0, no log
00:38 +508: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 2: (-1,0.5), timelineNow=10s → at=10s, no log
00:38 +509: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=0 → at=0, no log
00:38 +510: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 3: (1.0,-1), timelineNow=10s → at=10s, no log
00:38 +511: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=0 → at=0, no log
00:38 +512: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 4: (1.0,1.0), timelineNow=10s → at=10s, no log
00:38 +513: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=0 → at=0, no log
00:38 +514: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 5: (1.0,1.10), timelineNow=10s → at=10s, no log
00:38 +515: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=0 → at=0 (clamp), no log
00:38 +516: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 6: (1.0,0.90), timelineNow=10s → at=9.9s, no log
00:38 +517: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=0 → at=0 (clamp), no log
00:38 +518: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 7: (1.0,0.5001), timelineNow=10s → at=9.5001s, no log
00:38 +519: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:38 +520: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 8: (1.0,0.50), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:38 +521: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=0 → at=0 (lag nem levont), 1 warning
00:38 +522: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2 lag-guard matrix (read on derived lag) row 9: (1.0,0.4999), timelineNow=10s → at=10s (lag nem levont), 1 warning
00:38 +523: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.0 below threshold → no observation
00:38 +524: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5499 below threshold → no observation
00:38 +525: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.55 exactly at threshold → observation emitted
00:38 +526: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=0.5501 above threshold → observation emitted
00:38 +527: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix confidence=1.0 maximum → observation emitted
00:38 +528: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.3 confidence-határ matrix below-threshold strum advances dedup so the same seq does not re-emit
00:38 +529: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) de-jitter túléli a chord observationt (R0 PRÓBA-A)
00:38 +530: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R0 PRÓBA-B, 300 ms)
00:38 +531: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.2b a lag hatóköre és a fajtánkénti padló (R2) chord change-point nem kap idegen lagot (R2, 600 ms, határ fölött)
00:38 +532: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám változatlan timelineNow mellett a nagy lagú frame után a lag nélküli frame at-ja nem kisebb
00:38 +533: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám strumSeq 5→9 ugrás → observation sequence 0,1
00:38 +534: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám két küszöb feletti strum között egy küszöb alatti → sequence 0,1
00:38 +535: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.4 monotonitás és sűrű sorszám start → 3 strum → stop → start → 1 strum: utolsó sequence=0, at nem a régi lastEmittedAt-ra clampelve
00:38 +536: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix ugyanaz a label 10 frame-en belül → pontosan 1 ChordObservation
00:38 +537: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix label-váltás C → G → új observation
00:38 +538: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix akkord → nincs akkord → label:null observation is kiadódik
00:38 +539: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix nem kanonikus label a detektorból (Em7, G/B, H) → redukció, observation validate() üres
00:38 +540: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix változatlan label, de eltelt chordStableDuration → újramintavétel
00:38 +541: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.5 chord-mintavétel matrix a Live úton a confidence mindig 1.0, és chordMinConfidence=0.99 SEM szűr chordot
00:38 +542: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus start ×2 → mindkettő Success, engine.startCalls == 1
00:38 +543: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus stop ×2 → mindkettő Success, engine.stopCalls == 1
00:38 +544: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus dispose után start/stop → Failure (gateway disposed)
00:38 +545: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord → engine.expectedChordCalls utolsó eleme a label; stop után az utolsó elem null
00:38 +546: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.6 életciklus setExpectedChord a start előtt → sikeres start után az engine megkapja a labelt
00:38 +547: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés megtagadott engedély → Failure(PermissionFailure), engine.startCalls==0
00:38 +548: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés request() után granted → engine.startCalls==1
00:38 +549: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés érvénytelen config → Failure(configurationInvalid), engine.startCalls==0
00:38 +550: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream AudioFailure(audioSessionBusy) → stream hiba ugyanaz, engine.stopCalls==1, stream nem zárul be, újabb start sikerül
00:38 +551: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés engine stream StateError → AudioFailure(practiceObservationStreamFailed)
00:38 +552: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.7 hibaleképezés a hiba után beküldött frame NEM ad observationt
00:38 +553: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem 200 érvényes, observationt adó frame feldolgozása után a logger a start/stop páron kívül nem kap bejegyzést
00:38 +554: /home/ubuntu/ss-mm-e02r13/test/features/practice/data/live_practice_observation_gateway_test.dart: §6.8 log-fegyelem tíz, tartományon kívüli lagú frame ugyanabban a másodpercben → 1 warning
00:39 +555: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: perfect session: result is non-null, scorePoints > 0, navigateToResult fired exactly once
00:39 +556: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: wrong direction: matched strum with wrong direction → directionOutcome == wrong
00:39 +557: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: chord failure: matched strum with wrong chord → chordOutcome == wrong
00:39 +558: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: pause/resume: playingElapsed freezes, pausedElapsed grows, resume reaches running
00:39 +559: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: restart: from paused → countIn with attemptIndex + 1
00:39 +560: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: cancel: user cancel → result == null, recorder.recordCalls == 0
00:39 +561: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: stream failure: observation stream error → ShowRecoverableError, session stays running
00:39 +562: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: no signal: many unmatched strums → direction+rhythm MetricInsufficientData(noSignal)
00:39 +563: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: complete cleanup: FinishPractice → finished → full resource teardown (gateway dispose, tick stop, recorder called once)
00:39 +564: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_integration_test.dart: expected chord sequence: gateway.setExpectedChord called with each segment chord in order, then null on finish
00:40 +565: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_activation_test.dart: maps every practice session status to its capture decision
00:40 +566: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_activation_test.dart: policy keys cover exactly the session status enum
00:40 +567: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_activation_test.dart: paused disables capture and closes the chunk 014 pause gap
00:41 +568: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider returns the full built-in catalog in declaration order
00:41 +569: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider is backed by the BuiltinPracticeCatalog by default
00:41 +570: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_catalog_controller_test.dart: practiceCatalogProvider rewires when practiceCatalogRepositoryProvider is overridden
00:42 +571: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping pause does not advance activeElapsed or playingElapsed
00:42 +572: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: pause / resume bookkeeping playingElapsed advances only while status == running
00:42 +573: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: daily goal — countInBars=2, 4/4, 120 BPM (§6.4) 4 beats playing + 10s pause + 2 bars resume = exact playingElapsed
00:42 +574: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: countInBars == 0 countIn → running happens immediately at active=0
00:42 +575: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause at countInDuration + 2.5 bars → resume anchors at the 2nd musical bar boundary
00:42 +576: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause EXACTLY on a bar boundary → anchor is that boundary
00:42 +577: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: resume-anchor (§5.5, §0.1) pause 1µs after a bar boundary → anchor is the SAME boundary
00:42 +578: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) resume count-in is 3 beats long, not 4
00:42 +579: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: 3/4 meter (§0.1) count-in click effects: initial count-in emits meter.beatsPerBar clicks
00:42 +580: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: RestartAttempt (§0.1) full second attempt: timelineBase=0, activeBase==activeElapsed, playingElapsed=0, wallElapsed continues
00:42 +581: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) wallElapsed > sessionTimeout → finishing + timedOut
00:42 +582: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: session timeout (§5.6, §6.4) timeout wins over completedTimeline when both conditions met
00:42 +583: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: 0.5 practice speed (§0.1) halving effectiveTempo halves the bar boundaries — playingElapsed matches real time, not timeline time
00:42 +584: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: count-in click batching (§5.7) a single big ClockAdvanced spanning the whole count-in emits all click effects in order, no duplicates
00:42 +585: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: pause during count-in (§0.1) a single PausePractice during count-in freezes countInElapsed
00:42 +586: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: double pause/resume in same bar (§0.1) two consecutive pause/resume cycles preserve the timeline
00:42 +587: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_timing_test.dart: §6.1 purity guardrails (file-content checks) reducer does not define its own beat-to-time formula (no `bpm` or `60` literal)
00:43 +588: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P1: permissionRequired + PreparationSucceeded is rejected
00:43 +589: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P1b: permissionRequired + PreparationFailed is rejected
00:43 +590: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P2: 2-bar initial count-in (4/4, 120 BPM) emits 8 clicks
00:43 +591: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P3: timeout beats completedTimeline when both conditions hold
00:43 +592: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P4: paused past sessionTimeout → finishing + timedOut
00:43 +593: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P5: second attempt timelinePosition starts at Duration.zero
00:43 +594: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: P6: timelinePosition can exceed totalDuration, status is no longer running
00:43 +595: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: R1 MAJOR-3: statusPath walks every adjacent edge through allowedTransitions
00:43 +596: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_review_probes_test.dart: StartPractice sets countInSpanBeats = countInBars * beatsPerBar (R1 MAJOR-4)
00:44 +597: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition idle → preparing → ready on PreparePractice + Succeeded
00:44 +598: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A1 — status stream emits every transition FinishPractice + tick crosses finishing → completed
00:44 +599: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix startCalls == 1 when entering countIn
00:44 +600: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix countIn → running keeps startCalls unchanged
00:44 +601: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix running → paused stops the gateway exactly once
00:44 +602: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A2 — capture-activation matrix paused → countIn (resume) restarts the gateway (startCalls == 2)
00:44 +603: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight multiple FinishPractice calls produce exactly one record()
00:44 +604: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A3 — finish single-flight finishReason maps to userFinished on FinishPractice
00:44 +605: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix completed: disposeCalls == 1, recordCalls == 1
00:44 +606: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (a) user CancelPractice: disposeCalls == 1, recordCalls == 0
00:44 +607: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix cancelled (b) gateway-start Failure: cancelled, recordCalls == 0
00:44 +608: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A4 — cleanup matrix failed (compileTarget Failure) — preparing → failed, recordCalls == 0
00:44 +609: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix permission denied during preparing → permissionRequired
00:44 +610: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix compileTarget Failure → preparing → failed (reducer-origin effect)
00:44 +611: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A5 — error matrix gateway.start() Failure → cancelled, recorder NOT called
00:44 +612: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics running → paused: strum during pause does not change liveScore
00:44 +613: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics playingElapsed freezes during paused; pausedElapsed grows
00:44 +614: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics resume continues the timeline from the bar-boundary anchor (no jump)
00:44 +615: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=0: pause/resume cycle completes
00:44 +616: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=1: pause/resume cycle completes
00:44 +617: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 4/4 × countInBars=2: pause/resume cycle completes
00:44 +618: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=0: pause/resume cycle completes
00:44 +619: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=1: pause/resume cycle completes
00:44 +620: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A6 — pause semantics Meter 3/4 × countInBars=2: pause/resume cycle completes
00:44 +621: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source gateway receives exactly the controller-provided config
00:44 +622: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 400ms chordStableDuration: 250ms-stable chord run → MetricInsufficientData(chordUnstable)
00:44 +623: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A8 — single observation-config source 180ms chordStableDuration: same 250ms run → MetricAvailable
00:44 +624: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A13 — noSignal pinned (current behaviour, NOT a fix) many unmatched strums → direction+rhythm MetricInsufficientData (noSignal); scorePoints == 0 (no matches, but signal was registered)
00:44 +625: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline 100 ticks in running with no observation → liveScore unchanged
00:44 +626: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a ChordObservation alone → liveScore unchanged
00:44 +627: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline a StrumObservation → liveScore changes (new aggregation)
00:44 +628: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A14 — scoring pass discipline FinishPractice alone does not change liveScore (the final pass updates `result`, not `liveScore`)
00:44 +629: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by user → result == null
00:44 +630: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping cancelled by gateway failure → result == null
00:44 +631: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A15 — finishReason mapping failed → result == null
00:44 +632: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A16 — finishing is observable FinishPractice + tick crosses through finishing
00:44 +633: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from countIn is rejected by the reducer
00:44 +634: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) PreparationFailed from paused is rejected by the reducer
00:44 +635: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A17 — failed is reachable ONLY from preparing (pin) gateway-start failure → cancelled, recorder NOT called (R14 contract)
00:44 +636: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_controller_test.dart: A9 — controller layer-purity guard no forbidden symbol appears in the controller source (ADR 0077 §10 / R10d / R13)
00:44 +637: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig uses the brief defaults
00:44 +638: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig has value equality
00:44 +639: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig validates every confidence and duration boundary
00:44 +640: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: PracticeObservationConfig invalid config is represented by configuration.invalid
00:44 +641: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway keeps start and stop idempotent
00:44 +642: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway records expected chord and exposes a controllable stream
00:44 +643: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway returns the injected start result
00:44 +644: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_observation_gateway_test.dart: FakePracticeObservationGateway rejects operations after dispose
00:45 +645: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: happy path: idle → preparing → ready → countIn → running → finishing → completed
00:45 +646: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: permission path: preparing → permissionRequired → preparing → ready
00:45 +647: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: pause/resume: the resume count-in actually runs
00:45 +648: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: pause during count-in is accepted
00:45 +649: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: cancel before start: ready → cancelled
00:45 +650: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: cancel during running: running → cancelled
00:45 +651: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: failure and retry: preparing → failed → preparing
00:45 +652: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: double start: the second StartPractice is rejected; state unchanged
00:45 +653: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: double finish: the second FinishPractice is rejected
00:45 +654: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: restart attempt: paused → countIn, attemptIndex +1, attemptElapsed 0
00:45 +655: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: background interruption: PausePractice(PauseCause.interruption) preserves the cause on the state
00:45 +656: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix every (status, input) pair matches the pinned table
00:45 +657: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix rejected transitions return the input state by value
00:45 +658: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: exhaustive transition matrix reducer never throws on any (status, input) pair
00:45 +659: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: rejection carries from / input / code; never throws
00:45 +660: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: StartPractice is rejected when target is null
00:45 +661: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: ChangeTempoBeforeAttempt updates config.effectiveTempo and invalidates target
00:45 +662: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer does not define its own beat-to-time formula (no bare `bpm` identifier, no `60` literal in arithmetic)
00:45 +663: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer source does not contain DateTime.now, Stopwatch, Random, print
00:45 +664: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_reducer_test.dart: §6.1 source-purity guardrails reducer / command / effect files do not import Flutter or Riverpod
00:46 +665: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock now() before any start() returns zero in every field
00:46 +666: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() places the clock in a fresh session state
00:46 +667: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:46 +668: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock active + paused == wall invariant holds after pause and resume
00:46 +669: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:46 +670: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:46 +671: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:46 +672: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: MonotonicPracticeSessionClock start() while paused is a no-op (no fields reset)
00:46 +673: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock now() before any start() returns zero in every field
00:46 +674: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() places the clock in a fresh session state
00:46 +675: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() is idempotent: repeated start() does not throw or distort
00:46 +676: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds after pause and resume
00:46 +677: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() while paused is a no-op (state-machine fields unchanged)
00:46 +678: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resume() while running is a no-op (state-machine fields unchanged)
00:46 +679: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() zeros attempt; paused unchanged; wall/active unchanged
00:46 +680: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() while paused is a no-op (no fields reset)
00:46 +681: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() grows wall by the delta while running
00:46 +682: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() while paused grows wall AND paused; active stays put
00:46 +683: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock advance() after resume resumes active growth from the resume point
00:46 +684: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() after an active session only zeros attempt
00:46 +685: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock start() after pause is a no-op (clock stays paused, fields intact)
00:46 +686: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock pause() before start() is a no-op (no fields change)
00:46 +687: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock resetAttempt() before start() is a no-op
00:46 +688: /home/ubuntu/ss-mm-e02r13/test/features/practice/application/practice_session_clock_test.dart: FakePracticeSessionClock active + paused == wall invariant holds across 200 random steps
00:46 +689: All tests passed!

    → [3] test test/features/practice/: ZÖLD

═══ [4] test test/core/l10n_parity_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/l10n_parity_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02r13/test/core/l10n_parity_test.dart
00:00 +0: (setUpAll)
00:00 +0: en and hu define exactly the same keys
00:00 +1: no locale has an empty translation
00:00 +2: hu uses the same placeholders as en
00:00 +3: (tearDownAll)
00:00 +3: All tests passed!

    → [4] test test/core/l10n_parity_test.dart: ZÖLD

═══ [5] test test/core/screen_size_guard_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/core/screen_size_guard_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02r13/test/core/screen_size_guard_test.dart
00:00 +0: small portrait (320×568) Tuner (with a live reading)
00:01 +1: small portrait (320×568) Learn home (lesson list)
00:01 +2: small portrait (320×568) Learn player (paused, with score HUD area)
00:01 +3: small portrait (320×568) Metronome
00:01 +4: small portrait (320×568) Chord library
00:02 +5: small portrait (320×568) Progress
00:02 +6: small portrait (320×568) full app tab walk (Live→Analyze→Learn→Library→Settings)
00:03 +7: small portrait (320×568) Onboarding
00:03 +8: small portrait (320×568) Streak
00:03 +9: small portrait (320×568) Song builder
00:03 +10: small portrait (320×568) Practice hub (E02-R12)
00:03 +11: small portrait (320×568) Practice setup (E02-R12)
00:04 +12: small portrait (320×568) Practice session (E02-R13, null host → unavailable)
00:04 +13: normal portrait (412×915) Tuner (with a live reading)
00:04 +14: normal portrait (412×915) Learn home (lesson list)
00:04 +15: normal portrait (412×915) Learn player (paused, with score HUD area)
00:04 +16: normal portrait (412×915) Metronome
00:04 +17: normal portrait (412×915) Chord library
00:04 +18: normal portrait (412×915) Progress
00:04 +19: normal portrait (412×915) full app tab walk (Live→Analyze→Learn→Library→Settings)
00:05 +20: normal portrait (412×915) Onboarding
00:05 +21: normal portrait (412×915) Streak
00:05 +22: normal portrait (412×915) Song builder
00:05 +23: normal portrait (412×915) Practice hub (E02-R12)
00:05 +24: normal portrait (412×915) Practice setup (E02-R12)
00:05 +25: normal portrait (412×915) Practice session (E02-R13, null host → unavailable)
00:05 +26: landscape (915×412) Tuner (with a live reading)
00:05 +27: landscape (915×412) Learn home (lesson list)
00:05 +28: landscape (915×412) Learn player (paused, with score HUD area)
00:05 +29: landscape (915×412) Metronome
00:06 +30: landscape (915×412) Chord library
00:06 +31: landscape (915×412) Progress
00:06 +32: landscape (915×412) full app tab walk (Live→Analyze→Learn→Library→Settings)
00:06 +33: landscape (915×412) Onboarding
00:06 +34: landscape (915×412) Streak
00:06 +35: landscape (915×412) Song builder
00:06 +36: landscape (915×412) Practice hub (E02-R12)
00:06 +37: landscape (915×412) Practice setup (E02-R12)
00:07 +38: landscape (915×412) Practice session (E02-R13, null host → unavailable)
00:07 +39: All tests passed!

    → [5] test test/core/screen_size_guard_test.dart: ZÖLD

═══ [6] test test/tooling/route_literal_guard_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/tooling/route_literal_guard_test.dart

Resolving dependencies...
Downloading packages...
  _fe_analyzer_shared 99.0.0 (105.0.0 available)
  analyzer 12.1.0 (14.1.0 available)
  dio 5.10.0 (5.11.0 available)
  dio_web_adapter 2.2.0 (2.2.1 available)
  flutter_local_notifications 22.0.1 (22.2.0 available)
  flutter_local_notifications_platform_interface 12.0.0 (12.1.0 available)
  flutter_riverpod 3.3.2 (3.4.2 available)
  flutter_secure_storage_darwin 0.3.2 (0.4.0 available)
  flutter_secure_storage_platform_interface 2.0.1 (2.0.2 available)
  hooks 2.0.2 (2.1.0 available)
  intl 0.20.2 (0.20.3 available)
  jni 1.0.0 (1.0.3 available)
  jni_flutter 1.0.1 (1.0.2 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.18.0 (1.19.0 available)
  objective_c 9.4.1 (9.5.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 10.2.0 (10.2.1 available)
  permission_handler 12.0.3 (13.0.0 available)
  permission_handler_android 13.0.1 (14.0.0 available)
  permission_handler_apple 9.4.10 (9.5.0 available)
  permission_handler_html 0.1.3+5 (0.1.4+0 available)
  permission_handler_platform_interface 4.3.0 (4.4.0 available)
  permission_handler_windows 0.2.1 (0.2.2 available)
  record_use 0.6.0 (1.0.0 available)
  riverpod 3.3.2 (3.4.2 available)
  share_plus 13.2.0 (13.3.0 available)
  share_plus_platform_interface 7.1.0 (7.2.0 available)
  shared_preferences_android 2.4.26 (2.4.27 available)
  synchronized 3.4.1 (3.4.1+1 available)
  test 1.31.0 (1.31.2 available)
  test_api 0.7.11 (0.7.13 available)
  test_core 0.6.17 (0.6.19 available)
  uuid 4.5.3 (4.6.0 available)
  vector_math 2.2.0 (2.4.2 available)
  wakelock_plus 1.6.1 (1.7.0 available)
  wakelock_plus_platform_interface 1.5.1 (1.6.0 available)
  xml 6.6.1 (7.0.1 available)
Got dependencies!
38 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /home/ubuntu/ss-mm-e02r13/test/tooling/route_literal_guard_test.dart
00:00 +0: navigation calls use the central AppRoutes catalogue
00:00 +1: All tests passed!

    → [6] test test/tooling/route_literal_guard_test.dart: ZÖLD

═══ [7] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Running build hooks...Running build hooks...Architecture dependencies OK (12 allowlisted deviation(s)).

    → [7] architecture: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/                               zöld
    test test/core/l10n_parity_test.dart                       zöld
    test test/core/screen_size_guard_test.dart                 zöld
    test test/tooling/route_literal_guard_test.dart            zöld
    architecture                                               zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### Eltérések és okuk

- **A lifecycle-kötést `NotifierProvider.autoDispose` adja**, nem `initState` /
  `dispose` alatti provider-módosítás. Ez a prompt által engedett képernyő-scope
  irány, és Riverpod 3-ban a lifecycle callbackből történő szinkron provider-
  módosítás debug assertiont vált ki. Az ugyanazon `ProviderScope`-os zárócella
  az auto-disposal tényleges felhasználói viselkedését méri.
- **A `PlatformPracticeFeedbackOutput.announce` változatlan.** Csak az
  `AnnounceAccessibilityFeedback` effekt dispatch-ága nyeli el a nyers kulcsot,
  pontosan a javító prompt szerint; későbbi lokalizált hívó továbbra is
  használhatja a platform implementációt.
- **Új ARB-kulcs, route-, core-, application-, domain- vagy data-változás nem
  kellett.** A javítás három Dart fájlra és erre a §10-re korlátozódott.
- **Nem futott `gh`, push, PR vagy helyi APK/full-suite.** A prompt ezeket
  kifejezetten tiltja; a teljes suite + randomized property gate + APK az
  orchestrátor CI-feladata.

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r13-review.md`

Kiemelt figyelem: **valódi-sértés próba** az A7 ticker-számlálóra (ideiglenes
`Ticker` beszúrása → pirosnak kell lennie), az A3 effekt-egyszeriségre
(a listener `build()`-be mozgatása → pirosnak kell lennie), az A4 „megerősítés
elutasítva" és „`finishing` blokkol" celláira (ezek fedik el a néma
parancs-kiadást), valamint arra, hogy a felület **nem** ad ki `GrantPermission`
vagy elutasításba futó `CancelPractice` parancsot.
