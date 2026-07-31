# E02-R13 — Practice Session UI shell

- **Státusz:** **PREPARED** (előre megírva 2026-07-31, kód olvasva: `main` @ `ce8fbce`)
- **SDD-kör:** [`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md) **„Kör 13"** (+ §21.3, §21.6, §22)
- **Branch:** `codex/e02-r13-session-ui-shell`
- **Előfeltétel:** **E02-R12 merge-ölve** (Hub + Setup + route-ok + ARB-alap).
- **ADR:** **0079** — `docs/adr/0079-state-driven-practice-session-shell.md`,
  **az orchestrátor írja meg a pre-flightban** a §5 tartalmával.
- **Implementer motor:** a pre-flightban a user dönt. *Ajánlás:* **Codex** —
  életciklus- és leak-érzékeny kör (ticker, subscription, back-gomb, háttérbe
  kerülés).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ)**
> 1. Olvasd újra az R11 controller publikus felületét (state-stream, effekt-
>    csatorna, command API) és az R12 route-argumentumait.
> 2. Ellenőrizd, hogy az R12 review nyitott leletei közül mi tartozik ide.
> 3. ADR-szám ütközés ellenőrzése, majd az ADR 0079 megírása.
> 4. Státusz → PLANNING, dátum/sha frissítés, brief commit a kör-branchre.

## 0. Kör-jelzés — KÖTELEZŐ (AGENTS.md §15.2)

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done    "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélküli kör = bukott kör. `gh`-t NE hívj, ne pusholj, PR-t ne nyiss.
**STOP-klauzula:** listán kívüli fájl, vagy ellentmondó előírás → `stopped`.
**A §7 a terved.**

## 1. Cél

A **közös** session-képernyő: minden státuszt renderel (`preparing`,
`permissionRequired`, `ready`, `countIn`, `running`, `paused`, `finishing`,
`failed`), fogadja a controller effektjeit, és **kizárólag** parancsokat küld
vissza. **Mode-specifikus nézet és pontozó-vizuál ebben a körben nincs** — az a
Kör 14–16. A kör tétje az **életciklus**: nincs saját business-óra, nincs ticker-
leak, nincs duplikált navigáció, és a képernyő elhagyása **mindig** cleanupot kér.

## 2. Jelenlegi állapot (mért tények, `main` @ `ce8fbce`)

- **A V2-nek nincs session-képernyője.** Az R12 után a `presentation/screens/`
  alatt a Hub és a Setup van.
- **A legacy referencia és ellenpélda: `lib/features/learn/screens/learn_screen.dart`
  (839 sor).** Mért szerkezet:
  - `SingleTickerProviderStateMixin` + saját `Ticker` (44., 49., 88. sor) —
    a `_onTick` **maga hajtja** a scorert és az időt: ez a business-óra a
    widgetben, amit a V2 **nem** másolhat (SDD Kör 13);
  - `Metronome _metronome = Metronome()` (50. sor) — a widget hozza létre az
    audio erőforrást;
  - `_scorer ??= LessonScorer(...)` (218. és 248. sor) — a widget példányosít
    scorert;
  - `ref.listenManual(liveFrameProvider, _onFrame)` (224. sor) — a widget
    iratkozik fel a detektor-folyamra;
  - a `_pause()` (232. sor) **nem** állítja le a mikrofon-fogyasztást — ez a
    HANDOFF §6.4-ben nyilvántartott, felhasználó-látható pause-rés, amit a V2
    úton a `practiceCaptureActiveByStatus` tábla (R08) és az R11 controller
    szerkezetileg zár.
  Ebből a fájlból **semmit nem másolsz át**; referenciaként olvasható.
- **Controller (R11):** state-stream + effekt-csatorna + command API; a
  capture-életciklus, az óra és a cleanup **az övé**.
- **Effektek (R07):** `PlayHaptic`, `PlayCountInClick`, `ShowPermissionSettings`,
  `NavigateToResult`, `ShowRecoverableError`, `AnnounceAccessibilityFeedback`
  (`application/practice_session_effect.dart`, 54 sor) — a sealed switch
  **kimerítő**, tehát minden effektet kezelned kell.
- **Core widgetek, amiket újra kell használni:** `core/widgets/mic_permission_banner.dart`,
  `core/widgets/mic_error_banner.dart`, `core/widgets/empty_state.dart`.
- **App-életciklus:** `lib/core/platform/app_lifecycle.dart` (69 sor) — a
  háttérbe kerülés jelzésének meglévő útja; `screen_wakelock.dart` (35 sor).
- **Layout-őr:** `test/core/screen_size_guard_test.dart`; **a11y-minta:**
  `test/features/chords/chord_tile_a11y_test.dart`; **i18n-gate:**
  `test/core/l10n_parity_test.dart` (375 kulcs, azonos kulcshalmaz kötelező).

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
  effektet ebben a körben egy **lokalizált placeholder** fogadja (a Result a
  Kör 18); a placeholder ne állítson pontszámot, amit nem mértünk.
- A controller, a reducer, a gateway, a scorerek **bármilyen** módosítása.
- `lib/features/learn/**` bármilyen módosítása.
- Új ADR, `docs/sdd/**`, `HANDOFF.md`, `.github/**`, DSP.

## 4. Engedélyezett fájlok

| Útvonal | Új? | Miért |
|---|---|---|
| `lib/features/practice/presentation/screens/practice_session_screen.dart` | **ÚJ** | a session shell |
| `lib/features/practice/presentation/widgets/practice_hud.dart` | **ÚJ** | közös státusz-HUD (szöveges) |
| `lib/features/practice/presentation/widgets/practice_controls.dart` | **ÚJ** | pause/resume/exit vezérlők |
| `lib/features/practice/presentation/widgets/practice_count_in_overlay.dart` | **ÚJ** | count-in overlay |
| `lib/features/practice/presentation/widgets/practice_error_panel.dart` | **ÚJ** | recoverable hibapanel |
| `lib/features/practice/presentation/practice_effect_listener.dart` | **ÚJ** | effekt → haptika/hang/navigációs kérés |
| `lib/features/practice/public.dart` | — | az új képernyő exportja |
| `lib/app/routing/app_route.dart` | — | **CSAK** a `practiceSession` konstans |
| `lib/app/routing/app_router.dart` | — | **CSAK** a session-route regisztrációja a flag mögött |
| `lib/l10n/app_en.arb` · `lib/l10n/app_hu.arb` | — | új `practice*` kulcsok mindkét nyelven |
| `test/features/practice/presentation/practice_session_screen_test.dart` | **ÚJ** | A1–A5 |
| `test/features/practice/presentation/practice_session_lifecycle_test.dart` | **ÚJ** | A6–A8 |
| `test/core/screen_size_guard_test.dart` | — | **CSAK** az új képernyő felvétele |
| `docs/rounds/e02-r13-session-ui-shell.md` | — | **CSAK a §10** (handoff) |

**Tilos zóna:** minden más. Nevezetesen `lib/features/practice/application/**`,
`domain/**`, `data/**`, `lib/features/learn/**`, `lib/app/config/**`,
`docs/adr/**`, `.github/**`.

**Új fájl a listán kívül = scope-sértés** → `stopped`.

## 5. Kötött döntések (ADR 0079 — NEM tárgyalhatók)

1. **A képernyő állapotvezérelt.** Az egyetlen igazságforrás a controller
   state-je; a widget **nem tart** párhuzamos session-állapotot (nincs saját
   „isPlaying" bool, nincs saját eltelt idő).
2. **Nincs saját business-óra.** `Ticker`/`Timer`/`Stopwatch` **kizárólag**
   renderelési interpolációra használható, és soha nem hajthat scorert, órát,
   státuszváltást. (A legacy `learn_screen.dart` pont az ellenkezőjét csinálja —
   ez a kör tanulsága, nem a mintája.)
3. **A widget nem példányosít motort.** Nincs `LessonScorer`, `StrumEngine`,
   `Metronome`, matcher vagy gateway a presentation rétegben. A count-in
   kattanás a `PlayCountInClick` **effekt** hatására szólal meg, egy
   injektálható hang-kimeneten keresztül.
4. **A kilépés mindig cleanupot kér.** Rendszer-back, AppBar-vissza, route-csere
   és a `PopScope` út **mind ugyanazt** a `CancelPractice`/`FinishPractice`
   parancsot adja ki; a képernyő soha nem tűnik el úgy, hogy a controller aktív
   marad.
5. **Megerősítés kell futó sessionből kilépéskor.** `running`/`countIn`/`paused`
   állapotban a kilépés lokalizált megerősítést kér; `ready`, `completed`,
   `cancelled`, `failed` állapotból megerősítés nélkül kiléphető.
6. **A recoverable hiba nem dob ki.** `ShowRecoverableError` → panel a
   képernyőn belül, „újra" és „kilépés" úttal; a session **marad**
   (SDD §21.6).
7. **Az effekt egyszer hat.** Minden effekt **pontosan egyszer** dolgozandó fel;
   újraépítés (`rebuild`) nem játszhatja le újra a haptikát és nem navigálhat
   másodszor.
8. **Reduced motion és haptika-tiltás tiszteletben tartva.** `MediaQuery`
   `disableAnimations` esetén nincs animált átmenet; a haptika kikapcsolható
   (a beállítás hiányában a default: bekapcsolva).
9. **Az életciklus továbbítva, nem értelmezve.** A háttérbe kerülés a
   controllernek szóló **parancs** (pause), nem a widget saját döntése arról,
   mi történjen az audióval.
10. **Minden szöveg ARB-ból**, mindkét nyelven; a státuszok nevei **nem**
    szivároghatnak ki nyers enum-névként a felületre.

## 6. Acceptance criteria

### A1 — Státusz-render mátrix (mind a nyolc látható állapot)

Fake controller-állapottal, cellánként külön `expect`:

| Státusz | Elvárt a képernyőn |
|---|---|
| `preparing` | folyamatjelző + lokalizált „előkészítés" |
| `permissionRequired` | `mic_permission_banner` + engedélykérő akció |
| `ready` | Start-vezérlő, **nincs** count-in overlay |
| `countIn` | count-in overlay a hátralévő ütésekkel |
| `running` | HUD (eltelt idő, attempt, score-pillanatkép), pause elérhető |
| `paused` | „szünet" jelzés + resume; **nincs** count-in overlay |
| `finishing` | folyamatjelző, vezérlők letiltva |
| `failed` | hibapanel (§5.6), a session megmarad |

***Pirosra fogja:*** a „minden nem-running állapot ugyanaz a spinner"
egyszerűsítés.

**NEM elfogadható gyengítés:** két-három állapot tesztelése „a többi triviális"
indoklással — a nyolc cella mindegyike kötelező.

### A2 — Nincs párhuzamos állapot a widgetben

A képernyő forrása **nem tartalmaz** `setState`-tel kezelt session-mezőt
(`_playing`, `_elapsed`, `_score` és társai). Guard-állítás a saját
tesztfájlban: a forrásban nincs `Ticker`, `Stopwatch`, `DateTime.now(`,
`LessonScorer`, `StrumEngine`, `Metronome(` minta.

***Pirosra fogja:*** a legacy `learn_screen.dart` szerkezetének átemelése.

### A3 — Az effekt pontosan egyszer hat

| Cella | Elvárt |
|---|---|
| egy `PlayHaptic` + három widget-rebuild | **1** haptika-hívás |
| egy `NavigateToResult` + három rebuild | **1** navigációs kérés |
| két külön `PlayCountInClick` | **2** hang-hívás |
| a képernyő `dispose()`-a után érkező effekt | **0** hívás, **nincs** kivétel |

**A mérés eszköze:** a haptika- és hang-kimenet injektálható absztrakció
hívásnaplóval (nem közvetlen `HapticFeedback` hívás a widgetben) — ezt a brief
írja elő, hogy a mérce ne legyen kikerülhető.

***Pirosra fogja:*** az effektek `build()`-ben való feldolgozása.

### A4 — Kilépési utak mátrixa

| Kiindulás | Kilépési út | Elvárt |
|---|---|---|
| `running` | rendszer-back | megerősítés, majd `CancelPractice` |
| `running` | AppBar-vissza | megerősítés, majd `CancelPractice` |
| `paused` | rendszer-back | megerősítés, majd `CancelPractice` |
| `ready` | rendszer-back | **nincs** megerősítés, kilép |
| `completed` | bármely út | **nincs** megerősítés, kilép |
| bármely | megerősítés **elutasítva** | a képernyő marad, **nincs** parancs |

Minden cellában mérendő: **hány** parancs ment ki (0 vagy pontosan 1) —
duplikált `CancelPractice` nem fogadható el.

### A5 — Nincs duplikált navigáció

Két gyors egymás utáni `NavigateToResult` effekt (ugyanarra a sessionre) →
**egy** navigációs kérés. Rebuild + effekt-ismétlés kombinációja sem növeli.

***Pirosra fogja:*** a „minden effekt-listener hívásnál `context.go(...)`"
implementáció, ami valódi eszközön dupla képernyőt push-ol.

### A6 — Életciklus továbbítás

| Esemény | Elvárt parancs |
|---|---|
| app háttérbe kerül `running` alatt | `PausePractice` **pontosan egyszer** |
| app előtérbe jön `paused` alatt | **nincs** automatikus resume (a user dönt) |
| app háttérbe kerül `ready` alatt | **nincs** parancs |

***Pirosra fogja:*** az automatikus resume — ez valódi eszközön a mikrofont
a user tudta nélkül kapcsolná vissza.

### A7 — Nincs ticker- és subscription-leak

- A képernyő `dispose()`-a után **nincs** aktív animációs ticker
  (`tester.binding.transientCallbackCount == 0`), és a controller effekt-/
  state-előfizetése lemondva (fake hívásnaplója).
- Ötszöri be- és kilépés után a fake controller `dispose` hívásszáma **5**, és a
  visszamaradt előfizetések száma **0**.

**NEM elfogadható gyengítés:** „a teszt nem dobott kivételt" — a számláló a mérce.

### A8 — a11y, reduced motion, i18n, layout

- Minden vezérlő ≥ 48×48 dp, címkével és akcióval **egy** szemantikus node-on.
- A verdict/státusz jelentése **nem csak színnel** jelenik meg (szöveg vagy ikon
  is hordozza).
- `disableAnimations: true` → nincs animált átmenet (a count-in overlay
  statikus).
- Angol és magyar felépülés; `l10n_parity_test` zöld.
- `screen_size_guard_test` zöld 320×568 és 915×412 méreten; 200%-os
  szövegméretnél nincs overflow.

### A9 — Nulla változás a legacy úton

`git diff --stat origin/main...HEAD` a §4 listáján belül; `lib/features/learn/`
**0 sor**; a controller/reducer/gateway fájlok **0 sor**.

## 7. Implementációs sorrend (ez a TERVED)

1. Olvasd el: ADR 0079, az R11 controller felülete, az effekt-készlet,
   `mic_permission_banner.dart`, `app_lifecycle.dart`, és **referenciaként**
   (nem másolásra) a `learn_screen.dart` 43–260. sorát.
2. ARB-kulcsok mindkét nyelven.
3. A képernyő váza + a nyolc státusz-render (A1).
4. Vezérlők + kilépési utak + megerősítés (A4).
5. Effekt-listener injektálható haptika/hang kimenettel (A3, A5).
6. Életciklus-továbbítás (A6).
7. Leak-tesztek (A7), a11y/i18n/layout (A8), guard-állítás (A2).
8. Záró gate (§9), majd a §10 kitöltése.

## 8. Kockázatok

- **A legacy minta vonzása.** A `learn_screen.dart` működik és kézenfekvő —
  de pontosan azt a szerkezetet tiltja ez a kör. Ha úgy érzed, ticker nélkül
  nem megy, az `stopped` + jelentés, nem „csak egy kis Ticker".
- **`PopScope` szemantika.** A rendszer-back elfogása és a megerősítés
  kombinációja az a pont, ahol könnyű duplikált parancsot kiadni — az A4
  cellái ezt mérik.
- **Effekt-újrajátszás rebuildkor.** A Riverpod `listen`/`listenManual`
  helytelen elhelyezése `build()`-ben ismételt haptikát és dupla navigációt ad.
- **A count-in overlay és a reduced motion** együtt: az animáció kikapcsolása
  nem törölheti az információt (a hátralévő ütések számát).
- **`AsyncValue.value`** (nullable), **NEM** `.valueOrNull`.

## 9. Záró gate — szó szerint ez az egyetlen hívás

```
tools/round-gate.sh test/features/practice/ test/core/l10n_parity_test.dart test/core/screen_size_guard_test.dart test/tooling/route_literal_guard_test.dart
```

Csővezeték nélkül, a teljes kimenetet a §10-be. A teljes suite + property gate +
APK a CI-ban fut (ADR 0053) — `gh`-t NE hívj.

## 10. Implementation handoff — az IMPLEMENTER tölti ki

*(Fájlonkénti összefoglaló · a záró gate TÉNYLEGES, teljes kimenete · az A1–A9
pontok teljesülése bizonyítékkal · eltérések és okuk · follow-upok.)*

## 11. Review — Claude tölti ki

Link: `docs/reviews/e02-r13-review.md`

Kiemelt figyelem: **valódi-sértés próba** az A7 ticker-számlálóra (ideiglenes
`Ticker` beszúrása → pirosnak kell lennie), az A3 effekt-egyszeriségre
(a listener `build()`-be mozgatása → pirosnak kell lennie), és az A4 „megerősítés
elutasítva" cellájára (ez az, ami néma parancs-kiadást szokott elfedni).
