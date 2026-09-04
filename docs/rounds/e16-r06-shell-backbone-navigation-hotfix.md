# E16-R06 — A shell gerince a termék saját navigációjával járható (L1/L2 javító kör, A3 újramérés)

- **Státusz:** READY (kód mérve: `main @ baf2f61d`, 2026-09-04)
- **Típus:** Chapter 16 javító kör — az `E16-R05` zárókör mért L1/L2 leletére
- **Kör-azonosító:** `E16-R06`
- **Branch:** `<motor>/e16-r06-shell-backbone-navigation-hotfix`
- **Előfeltétel:** `E16-R05` merge-elve (`474a6b00`) — az általa írt
  `docs/release/full-app-verification.md` és `test/e2e/full_app_walkthrough_test.dart`
  ennek a körnek a bemenete.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0508` — **a Claude MÁR megírta**
  (`docs/adr/0508-shell-entry-location-and-recommended-practice-handoff.md`);
  a `docs/adr/` a TILOS zónában van, a kör nem hoz létre és nem szerkeszt ADR-t.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/app/routing/app_router.dart` `entryLocation` sorát (ma `:231`) és a
> `lib/features/onboarding/screens/onboarding_screen.dart` `_completeFinish` /
> `_completeFirstWin` ágát (ma `:102-140`) — a sorszámok driftelhetnek, a
> KÖTELEZETTSÉG a viselkedésre szól, nem a sorszámra. Ellenőrizd azt is, hogy a
> `test/ui/goldens/e15_r13_full_variant_matrix_test.dart` `_practiceAreaHubScreen`
> helyettesítője (`:1431`) `ProviderScope` alatt pumpál-e — ha nem, az a
> `ConsumerWidget` váltás után piros lesz, és §0.0 revíziót igényel (a fájl
> NINCS az engedélyezett listán).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/routing/adaptive_shell_routes.dart",
  "lib/app/routing/app_router.dart",
  "lib/features/onboarding/screens/onboarding_screen.dart",
  "lib/features/practice_hub/screens/practice_area_hub_screen.dart",
  "test/app/routing/shell_entry_location_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/navigation/",
  "test/features/onboarding/",
  "test/features/practice_hub/practice_area_hub_cta_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e13_r17_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/e2e/full_app_walkthrough_test.dart",
  "docs/release/full-app-verification.md",
  "docs/rounds/e16-r06-shell-backbone-navigation-hotfix.md",
]
gate_tests = [
  "test/app/routing/shell_entry_location_test.dart",
  "test/app/routing/onboarding_first_win_test.dart",
  "test/app/routing/app_router_test.dart",
  "test/app/navigation/",
  "test/features/onboarding/",
  "test/features/practice_hub/practice_area_hub_cta_test.dart",
  "test/features/today/hub_navigation_test.dart",
  "test/accessibility/closure_suite_test.dart",
  "test/core/screen_size_guard_test.dart",
  "test/ui/goldens/e13_r16_screens_golden_test.dart",
  "test/ui/goldens/e13_r17_screens_golden_test.dart",
  "test/ui/goldens/e15_r13_full_variant_matrix_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "test/e2e/full_app_walkthrough_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Kötött scope-mérések a brief-lint leletei nyomán (KÖTELEZŐ így)

**M1 — a kör EGYETLEN destination buildert sem köt át (S10/S11 hamis riasztás
elleni mérés).** Az `app_router.dart`-ban a kör kizárólag a `:231` sor
`entryLocation` KIFEJEZÉSÉT cseréli függvényhívásra. Sem a shell öt
destinationjének buildere, sem a tizenegy alútvonal-adapter, sem a
`legacyRedirects` célja nem változik. A §2-ben CITÁLT, de NEM módosított
képernyők (`live_screen.dart`, `today_hub_screen.dart`,
`practice_hub_screen.dart`, `practice_setup_screen.dart`) a **tilos zónában**
maradnak — a hivatkozás mérési forrás, nem tulajdonlás.

**M2 — a ténylegesen átírt két képernyőt pinnelő tesztek felkerültek MINDKÉT
listára** (`allowed_paths` + `gate_tests`), mert a kör valóban hozzájuk nyúl:
az `onboarding_screen.dart` befejező ága más útvonalra navigál, a
`practice_area_hub_screen.dart` pedig `StatelessWidget` → `ConsumerWidget`
váltáson megy át. Ez a lista-tágítás **az orchestrátor pre-flight döntése**, a
kör indítása ELŐTT — nem a kör futása közben (ADR 0087 §2). Mért indok:
`E14-R05` ugyanezen a hibaosztályon H3-mal állt meg 2026-09-04-én
(`.pipeline/chain.log`), és `E13-R17` `test/app/navigation/` +33 → +30 -3.

**M3 — a jogosultság PONTOSAN a viselkedésváltozás átvezetése.** A felvett
tesztfájlokban kizárólag az az állítás írható át, amely a RÉGI belépési helyet
vagy a RÉGI (id nélküli) CTA-viselkedést rögzíti, illetve amelyhez
`ProviderScope`-burkolás kell a `ConsumerWidget` váltás miatt. **Cella
törlése, `skip`-je, `reason` nélküli lazítása vagy egész teszt kikommentelése
TILOS** — az ilyen diff review-BLOCKER. A golden **baseline-képek**
(`test/ui/goldens/goldens/**.png`) és a `test/fixtures/ui/**` a tilos zónában
maradnak: piros golden → `stopped`, nem baseline-újraírás.

**M4 — pre-flight újramérés (orchestrátor, 2026-09-04, `main @ ddb4c769`).**
A §2 mért állításai és a fejléc pre-flight kérdései ÚJRA mérve, indítás előtt:

| Állítás | Mért eredmény |
|---|---|
| `app_router.dart:231` `final entryLocation = adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live;` | **változatlan, a sorszám is stimmel**; a flag forrása `:222-225`, a felhasználási helyek `:234`, `:236`, `:241` |
| `onboarding_screen.dart` `_completeFinish` → `(widget.onDone ?? () => router!.go(AppRoutes.live))();` | **változatlan**; a `_completeFirstWin` szintén `router!.go(AppRoutes.live)` + post-frame `LearnScreen` push |
| `practice_area_hub_screen.dart` — `StatelessWidget`, `onPressed: () => context.go(AppRoutes.practiceSetup)`, kulcs `ValueKey('practice-hub-recommended-cta')` | **változatlan**, `?id=` nélkül |
| `practiceCatalogProvider` a `lib/features/practice/public.dart` barrelben | **exportálva** (`public.dart:18`); a `practiceCatalogRepositoryProvider`-ből `watch`-ol, tehát a repository-override automatikusan átköti |
| beépített katalógus első eleme | `id: 'builtin.quarterDownstrokes.v1'` — **változatlan** |
| **`e15_r13_full_variant_matrix_test.dart:1431` `_practiceAreaHubScreen()` `ProviderScope` alatt pumpál-e?** | **IGEN.** A fájl EGYETLEN `pumpWidget` hívása a `_pumpCell` helper (`:3668-3669`), és az `ProviderScope(overrides: overridesBuilder(), …)`-ba burkol. Ugyanígy `ProviderScope` alatt pumpál az `e13_r17` `_pump` (`:34-36`, a `PracticeAreaHubScreen` cellája `:77`), az `e13_r16` (`:49`) és az `ui_baseline_screenshot_test` (`:148`, `:178`, `:196`). **A `ConsumerWidget` váltás mind a négy golden-fájlban biztonságos → a §4 „kizárólag `ProviderScope`-burkolás" jogosultságra várhatóan nem lesz szükség; ha egy cella mégis pirosra vált, az §0.0 M3 szerint kezelendő.** |

**M5 — a brief-lint S11 lelete MÉRVE tárgytalan.** A lint a
`live_screen.dart`, `today_hub_screen.dart`, `practice_hub_screen.dart` és
`practice_setup_screen.dart` briefen kívüli pinjeit sorolta fel. Ezt a négy
képernyőt a kör **nem cseréli le és nem is szerkeszti** — egyik sincs az
`allowed_paths`-on, és az M1 kimondja, hogy a §2-beli hivatkozásuk mérési
forrás, nem tulajdonlás. A lint saját kifutó ága („ha a kör a képernyőt
bizonyíthatóan nem cseréli le, a §0.0 mondja ki ezt a mérést") ezzel teljesül.
A ténylegesen átírt két képernyő (`onboarding_screen.dart`,
`practice_area_hub_screen.dart`) pinjei az M2 szerint MINDKÉT listán rajta
vannak.

**M6 — az ADR 0508 MÁR merge-elve van** (`fbcf5aa8`, #572), tehát a kör
pre-flightja ADR-t nem ír és nem szerkeszt: a `docs/adr/**` tilos zóna marad
(egy merge-elt ADR módosítása H1 lenne). A `tools/gateguard-scan.py` a briefre
**„nincs ütközés a MÉRCE-őr védett listájával"** eredményt adta.

## 1. Cél

Az `E16-R05` gépi bejárása **negatív A3-verdiktet** mért: a „BE" besorolású
capabilityk core útja a termék SAJÁT navigációjával nem járható végig, mert a
bejárás két teszt-oldali `router.go` hidat kényszerül használni. A két hidat két
nevesített lelet okozza (L1, L2). Ez a kör **kijavítja mindkettőt**, **eltávolítja
a két hidat**, és ezzel az A3-at mérhetően pozitívra fordítja — nem egy új
mérőeszközzel, hanem a MÁR MEGLÉVŐ, `E16-R05` által írt bejárással.

## 2. Jelenlegi állapot (mérve: `main @ baf2f61d`)

**L2 — az onboarding mindig `/live`-ra fejez be.**

- `lib/features/onboarding/screens/onboarding_screen.dart:106` —
  `(widget.onDone ?? () => router!.go(AppRoutes.live))();` a Skip/finish ágon
  (`_completeFinish`).
- Ugyanezen fájl `:129` — `_completeFirstWin` szintén `router!.go(AppRoutes.live)`,
  majd post-frame callbackben a root navigátorra pusholja a
  `LearnScreen(lesson: Lessons.firstWin)`-t (`:130-138`).
- `lib/app/routing/app_router.dart:231` — a router SAJÁT belépési logikája
  `final entryLocation = adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live;`,
  a flag forrása `ref.read(appConfigProvider).flags.adaptiveShellEnabled`
  (`:222-225`). Az onboarding ezt a flaget **nem olvassa**.
- `lib/app/routing/adaptive_shell_routes.dart:11` —
  `AppRoutes.live: AppRoutes.practiceLive` a `legacyRedirects`-ben; a
  `/practice/live` `isStageRoute` szerint elsődleges navigáció nélküli
  (`:39-40`). Az első belépés tehát a shell nélküli stage-route-on ér véget.
- `test/app/routing/onboarding_first_win_test.dart:114-134` — a mai teszt a RÉGI
  viselkedést rögzíti: kommentben kimondja, hogy a képernyő „still calls
  `router.go(AppRoutes.live)` literally", és két állítást tesz —
  `AppRoutes.today` közvetlenül a tap után (`:121`), majd `AppRoutes.practiceLive`
  a beállt állapotban (`:134`).

**L1 — a shell egyetlen ajánlott-gyakorlás CTA-ja nem ad át `id`-t.**

- `lib/features/practice_hub/screens/practice_area_hub_screen.dart:55` —
  `onPressed: () => context.go(AppRoutes.practiceSetup)`, `?id=` **nélkül**; a
  gomb kulcsa `const ValueKey('practice-hub-recommended-cta')`. A képernyő ma
  `StatelessWidget` (`:23`), providert nem olvas.
- `lib/features/practice/presentation/screens/practice_hub_screen.dart:145-151` —
  a legacy Hub `_openSetup`-ja ezzel szemben mindig
  `Uri(path: AppRoutes.practiceSetup, queryParameters: {'id': definition.id})`-t
  épít; a Quick Start kártya forrása `catalog.first` (`:96-98`).
- `lib/features/practice/presentation/screens/practice_setup_screen.dart:52-57`
  (`_readArgs`) → `parsePracticeSetupArgs(id)`; hiányzó kulcs →
  `PracticeSetupRequest.missing` (`practice_route_args.dart:14-23`) → a képernyő
  a `_RouteError` ágát rendereli (`practice_setup_screen.dart:84-90`).
- `lib/features/practice/application/practice_catalog_controller.dart:20` —
  `practiceCatalogProvider` (sima `Provider<List<PracticeDefinition>>`), a
  `practiceCatalogRepositoryProvider`-ből; **exportálva** a
  `lib/features/practice/public.dart:17-18` barrelben. Precedens a cross-feature
  olvasásra: `lib/app/routing/app_router.dart:36`.
- A beépített katalógus első eleme
  `lib/features/practice/data/builtin_practice_catalog.dart:38` —
  `id: 'builtin.quarterDownstrokes.v1'`; ugyanez a
  `test/support/e2e_harness.dart:50` `e2eQuickStartDefinitionId` konstans értéke.

**A két teszt-oldali híd, amit ez a kör megszüntet.**

- `test/e2e/full_app_walkthrough_test.dart:106` — `session.router.go(AppRoutes.today)`
  a Skip után (a fölötte lévő komment az L2-t írja le).
- Ugyanott `:168-170` — `session.router.go(AppRoutes.practiceHub)` +
  `session.router.go('${AppRoutes.practiceSetup}?id=$e2eQuickStartDefinitionId')`
  (a fölötte lévő komment az L1-et írja le, és rögzíti a go_router
  query-only-navigáció csapdáját: azonos path + azonos page esetén nincs
  rebuild, ezért kellett a `/practice`-re való visszapattanás).
- `:147-158` — a Setup-állomás ma azt állítja, hogy a `_RouteError` cím
  **látszik** (`find.text(l10n.practiceRouteErrorTitle), findsOneWidget`).

**Ami MÁR kész, és nem e kör dolga:** a `_RouteError` ág maga (helyes és
lokalizált), a `legacyRedirects` tábla, az `isStageRoute` szerződés, a
`PracticeSetupScreen` id-feloldása, a `full_app_walkthrough_test.dart` többi
állomása, és a `docs/release/full-app-verification.md` L3/L4/L5 leletei
(más gazda, más kör).

### 2.1 Visszakeresett előzmény (ADR 0312 / ADR 0331)

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "onboarding
belépési hely adaptív shell entry location navigáció CTA id átadás"`:

- **[ADR 0275](../adr/0275-five-area-shell-behind-a-flag.md)** — az ötterületes
  shell flag mögött, adapterekkel; a legacy route-ok redirect nélküli elhagyása
  TILOS. Ez a kör a redirect-táblához nem nyúl, csak a belépési HELYET javítja.
- **[ADR 0467](../adr/0467-adaptive-shell-is-the-non-production-default.md)** —
  az adaptív shell a nem-production alapértelmezés; ezért mér a §6.1 mátrix a
  flag MINDKÉT állására, nem csak a mai defaultra.
- **[ADR 0059](../adr/0059-central-route-catalogue-and-validated-navigation.md)**
  — a központi route-katalógus mért gyökéroka pontosan az volt, hogy „a működést
  egyedül az tartotta össze, hogy az onboarding képernyő kézzel navigált". Az L2
  ennek a maradéka: az onboarding ma is kézzel dönt a belépési helyről, a
  routertől függetlenül. A D1 ezt zárja le.
- **`docs/LESSONS.md` L593** — a briefen kívül élő teszt, amely egy képernyő
  típusát pinneli, H3-at okoz; ezért a §0.0 M2 lista-tágítás.
- **`docs/LESSONS.md` L05/L09** — a gate futtatható artefaktum, `&&` és `| tail`
  tilos.

### 2.2 Amit a kör NEM javít (a másik három lelet)

L3 (Library harness-határ), L4 (Profile V1/V2 napló-szétválás), L5
(`practiceHistoryV2ListProvider` cache-invalidáció) **kívül van** ezen a körön.
A `full-app-verification.md` ezen szakaszai **változatlanul maradnak**.

## 3. Scope

**Benne:**

- `entryLocationFor(bool)` tiszta függvény az `adaptive_shell_routes.dart`-ban,
  és a router átállítása rá (ADR 0508 D1).
- Az onboarding mindkét befejező ága erre a függvényre navigál (D2).
- A Practice Area Hub ajánlott CTA-ja `?id=<katalógus első elemének id-je>`
  URI-t nyit (D3), üres katalógusnál a kártya nem renderelődik (D4).
- A bejárás két hídjának törlése + tapintásos út, valamint a
  `full-app-verification.md` A3 szakaszának újraírása a mért eredményre (D5).
- A régi viselkedést rögzítő `onboarding_first_win_test.dart` állítások átírása.

**Kívül (ebben a körben TILOS):**

- `PracticeSetupScreen` bármilyen felpuhítása (id nélküli belépés
  „kitalálása") — a `_RouteError` ág marad.
- Új ARB/l10n kulcs, l10n fájl szerkesztése.
- A `legacyRedirects` tábla és az `isStageRoute` szerződés módosítása.
- A legacy `practice_hub_screen.dart` bármilyen érintése.
- Bármilyen golden-baseline vagy `test/fixtures/ui/**` frissítés (ha egy golden
  pirosra vált, az **`stopped`** és jelentés — nem baseline-újraírás).
- DSP/ML paraméter, modell-bináris (AGENTS.md §9).
- `docs/adr/**`, `docs/LESSONS.md`, `HANDOFF.md`, `docs/execution/pipeline-queue.tsv`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/app/routing/adaptive_shell_routes.dart` | `entryLocationFor` — a belépési hely EGYETLEN forrása (D1) |
| `lib/app/routing/app_router.dart` | **kizárólag** a `:231` `entryLocation` kifejezés cseréje a függvényhívásra; más változtatás scope-sértés |
| `lib/features/onboarding/screens/onboarding_screen.dart` | L2 javítása mindkét befejező ágon (D2) |
| `lib/features/practice_hub/screens/practice_area_hub_screen.dart` | L1 javítása: `ConsumerWidget` + id-t hordozó URI (D3/D4) |
| `test/app/routing/shell_entry_location_test.dart` | **ÚJ** — a 2×2 belépési mátrix (§6.1) |
| `test/app/routing/onboarding_first_win_test.dart` | a régi viselkedést rögzítő állítások átírása az új szerződésre |
| `test/features/practice_hub/practice_area_hub_cta_test.dart` | **ÚJ** — a CTA URI-mátrixa katalógus-override-okkal |
| `test/e2e/full_app_walkthrough_test.dart` | a két híd törlése, tapintásos út, a Setup-állomás állításának megfordítása |
| `test/app/routing/app_router_test.dart`, `test/app/navigation/` (3 őr), `test/features/onboarding/` (4 teszt), `test/features/today/hub_navigation_test.dart`, `test/accessibility/closure_suite_test.dart`, `test/core/screen_size_guard_test.dart` | **§0.0 M2/M3** — a két átírt képernyőt PINNELŐ, briefen kívül élő őrök; a jogosultság kizárólag a régi belépési hely / régi CTA-viselkedés átvezetése |
| `test/ui/goldens/e13_r16_screens_golden_test.dart`, `test/ui/goldens/e13_r17_screens_golden_test.dart`, `test/ui/goldens/e15_r13_full_variant_matrix_test.dart`, `test/ui/ui_baseline_screenshot_test.dart` | **§0.0 M3** — kizárólag `ProviderScope`-burkolás, ha a `ConsumerWidget` váltás megköveteli; a baseline-KÉPEK tilosak |
| `docs/release/full-app-verification.md` | az A3 szakasz + L1/L2 feloldásának rögzítése (D5) |
| `docs/rounds/e16-r06-shell-backbone-navigation-hotfix.md` | §0.0 revíziók, §10 handoff |

**Tilos zóna:** minden más `lib/**` (kiemelten `lib/features/live/**`,
`lib/features/today/**`, `lib/features/practice/**`, `lib/l10n/**`), minden más
`test/**` (kiemelten `test/ui/goldens/goldens/**.png`, `test/fixtures/ui/**`,
`test/support/e2e_harness.dart`), `docs/adr/**`, `docs/LESSONS.md`,
`HANDOFF.md`, `docs/execution/**`, `tools/**`, `tool/**`, `.github/**`.

> **ÚJ fájl létrehozása is scope-sértés, ha nincs a listán — akkor is, ha „csak
> teszt".** A fenti két új tesztfájl az EGYETLEN engedélyezett új fájl.

> **KÖTELEZŐ pre-flight a listára (ADR 0321):**
> ```bash
> tools/gateguard-scan.py --brief docs/rounds/e16-r06-shell-backbone-navigation-hotfix.md
> ```

## 5. Kötött architekturális döntések (ADR 0508)

A kör nem tervezheti újra az alábbiakat. Az ADR teljes szövege:
`docs/adr/0508-shell-entry-location-and-recommended-practice-handoff.md`.

### 5.1 A belépési hely EGY tiszta függvényből származik (D1)

`lib/app/routing/adaptive_shell_routes.dart` kap egy Flutter-független,
mellékhatás-mentes `String entryLocationFor(bool adaptiveShellEnabled)`
függvényt (BE → `AppRoutes.today`, KI → `AppRoutes.live`), és **mind** az
`app_router.dart:231`, **mind** az onboarding befejező ága ezt hívja.

**NEM elfogadható:** az onboardingba írt `AppRoutes.today` konstans (akkor sem,
ha ma ugyanazt adja); a router-oldali kifejezés meghagyása egy második,
„ugyanolyan" kifejezés mellett; a leképezés `Map`-be emelése egy harmadik
helyre. A duplikátum tilalma a döntés, nem a mai érték.

### 5.2 Az onboarding MINDKÉT befejező ága a belépési helyre megy (D2)

`_completeFinish` és `_completeFirstWin` alap-navigációja egyaránt
`entryLocationFor(...)`. A flag forrása **ugyanaz**, amit a router olvas:
`ref.read(appConfigProvider).flags.adaptiveShellEnabled`. A first-win
`LearnScreen` push (root navigátor, post-frame callback, `onboarding_screen.dart:130-138`)
**változatlan** — sem a sorrend, sem a gazda nem tervezhető újra.

**NEM elfogadható:** a first-win ág `/live`-on hagyása azzal, hogy „úgyis push
jön rá"; a `widget.onDone` / `widget.onFirstWin` injektált callbackek
szemantikájának megváltoztatása (ha meg vannak adva, továbbra is ŐK futnak,
router-navigáció nélkül).

### 5.3 Az átadás mindig hordoz definíció-azonosítót (D3)

A CTA a legacy `_openSetup`-pal **azonos URI-alakot** épít
(`Uri(path: AppRoutes.practiceSetup, queryParameters: {'id': …})`), a katalógus
**első** elemének id-jével. A `PracticeAreaHubScreen` `ConsumerWidget` lesz, és
a `practiceCatalogProvider`-t a `lib/features/practice/public.dart` **barrelen**
át olvassa.

**NEM elfogadható:** bedrótozott id-literál a hub-ban; mély import a `practice`
feature belsejébe (architecture-kapu); a Setup-oldal felpuhítása; a `ValueKey`
(`'practice-hub-recommended-cta'`) megváltoztatása vagy elvesztése.

### 5.4 Üres katalógus: nincs CTA (D4)

Üres `practiceCatalogProvider` esetén az ajánlott-kártya **nem renderelődik**
(sem cím, sem üzenet, sem gomb). Új ARB-kulcs ehhez nem kell.

**NEM elfogadható:** `?id=` nélküli navigáció fallbackként; magyarázat nélküli
tiltott gomb; `catalog.firstOrNull!` típusú futásidejű dobás.

### 5.5 A hidak megszűnnek, az A3 újramérve (D5)

A bejárás a Today Hubra és az id-t hordozó Setupra **kizárólag tapintással** jut
el. A `full-app-verification.md` A3 szakasza az új mérésre íródik át; az L1/L2
szakaszok **megmaradnak**, melléjük kerül a feloldás köre (`E16-R06`) és a mért
bizonyíték.

**NEM elfogadható:** bármely híd megtartása frissített kommentárral; az L1/L2
szakaszok törlése; az A3 „részben teljesül" jellegű átfogalmazása mérés nélkül.

## 6. Acceptance criteria

- [ ] **A1 — Egy forrás.** `entryLocationFor` létezik az
      `adaptive_shell_routes.dart`-ban, és
      `grep -n "adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live" lib/`
      **pontosan egy** találatot ad (magát a függvénytörzset). Az `app_router.dart`
      és az `onboarding_screen.dart` egyaránt a függvényt hívja.
- [ ] **A2 — Belépési mátrix (2×2).** `test/app/routing/shell_entry_location_test.dart`
      a `adaptiveShellEnabled ∈ {true, false}` × befejező ág `∈ {Skip/finish,
      first-win}` **mind a négy** celláját méri, valódi routeren (nem a függvény
      közvetlen hívásával): shell BE → a beállt útvonal `AppRoutes.today`;
      shell KI → a beállt útvonal `AppRoutes.live` (illetve annak nem-redirectelt
      alakja a KI konfigurációban). A cellák a **beállt** (`pumpAndSettle` utáni)
      útvonalra mérnek, mert a redirect-tábla második kiértékelése az, ami az
      L2-t ténylegesen okozta.
- [ ] **A3 — A first-win push sértetlen.** A first-win cellákban a
      `LearnScreen` továbbra is felépül, és `learn.lesson.id == Lessons.firstWin.id`.
      A `onboarding_first_win_test.dart` átírt állításai ezt a párost mérik:
      belépési hely **és** push, nem csak az egyiket.
- [ ] **A4 — CTA URI-mátrix.** `test/features/practice_hub/practice_area_hub_cta_test.dart`
      három cellát mér a `practiceCatalogRepositoryProvider` (vagy
      `practiceCatalogProvider`) override-jával:
      (a) **beépített katalógus** → a CTA tapintása után a router URI-ja
      `/practice/setup?id=builtin.quarterDownstrokes.v1`;
      (b) **override-olt katalógus más első elemmel** (pl. `id: 'test.first.v1'`)
      → az URI `?id=test.first.v1` — ez a cella az, ami a bedrótozott id-t megöli;
      (c) **üres katalógus** → az ajánlott-kártya CTA-ja
      (`ValueKey('practice-hub-recommended-cta')`) `findsNothing`, és a
      `practiceAreaHubRecommendedTitle` sem jelenik meg.
- [ ] **A5 — A Setup a valódi űrlapot rendereli.** A CTA tapintása után
      `find.text(l10n.practiceRouteErrorTitle)` **`findsNothing`**, és a Setup
      Start CTA-ja (`l10n.practiceSetupStart`) megtalálható. A „hibaképernyő
      látszik" állítás megfordítása kötelező — nem elég a régi állítás törlése.
- [ ] **A6 — Nulla teszt-oldali híd a gerincen.**
      `grep -n "session.router.go\|router.go(" test/e2e/full_app_walkthrough_test.dart`
      a bejárás gerincén (onboarding → Today → Practice Area Hub → Setup →
      Session) **0 találatot** ad; a §2-ben felsorolt három `router.go` sor
      törölve. A bejárás minden lépése `tester.tap` / `scrollUntilVisible`.
      **NEM elfogadható** a híd „helper függvénybe" költöztetése — a mérce a
      navigáció FORRÁSA (a termék widgetje), nem a hívás helye.
- [ ] **A7 — A bejárás zöld, ugyanazokkal az állomásokkal.** A
      `full_app_walkthrough_test.dart` `walked` halmaza változatlanul a kilenc
      `E16-R05`-ben rögzített képernyőosztályt tartalmazza (a lista nem szűkül),
      és a teszt zöld. Az `restartE2eApp` lépés (L5 miatt szükséges) **marad**.
- [ ] **A8 — A verifikációs dokumentum újraírva.**
      `docs/release/full-app-verification.md` A3 szakasza a MÉRT új eredményt
      közli, hivatkozva erre a körre; az L1 és L2 szakasz megmarad, mindkettő
      „Kör: `E16-R06`" jelöléssel és a feloldás egy mondatos leírásával; az
      L3/L4/L5 szakaszok bájtra változatlanok.
- [ ] **A9 — Nincs golden-elmozdulás.** A §7 gate golden-cellái zöldek
      **baseline-újraírás nélkül** (`git status test/ui/goldens/goldens/` üres).
      Ha egy golden pirosra vált, az EGYETLEN megengedett javítás a
      `ProviderScope`-burkolás a golden teszt `.dart` fájljában (§0.0 M3);
      képi eltérésnél → **`stopped`** és jelentés.
- [ ] **A10 — A gate zöld** a §7 artefaktum-hívással, csonkítatlan kimenettel.

### 6.1 Mérce-mátrix — melyik hibás implementációt fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `_completeFinish` marad `AppRoutes.live` | A2 „shell BE × Skip/finish" cellája + A6/A7 (a bejárás a Today Hubot nem találja) |
| `_completeFinish` fixen `AppRoutes.today`-t kap (flag figyelmen kívül) | A2 „shell KI × Skip/finish" cellája |
| `_completeFirstWin` marad `AppRoutes.live` | A2 „shell BE × first-win" cellája |
| A first-win push kiesik vagy nem post-frame | A3 (`LearnScreen` nem épül fel / a `lesson.id` nem egyezik) |
| `entryLocationFor` bevezetve, de az `app_router.dart` megtartja a saját kifejezését | A1 grep-cellája (2 találat) |
| A CTA `?id=` nélkül navigál | A4/a + A5 (a `_RouteError` cím megjelenik) |
| A CTA bedrótozott `'builtin.quarterDownstrokes.v1'`-et ad át | A4/b (override-olt katalógus, `test.first.v1`) |
| A CTA a katalógus utolsó/tetszőleges elemét adja át | A4/b (a várt id nem egyezik) |
| Üres katalógusnál is renderel CTA-t (vagy dob) | A4/c |
| A Setup felpuhítva („nincs id → első elem") | A4/c-hez tartozó Setup-ág marad zöld, DE az A4/b cellája továbbra is a hub URI-ját méri; ezen felül a §5.3 tiltása scope-sértés → review BLOCKER |
| A híd helper függvénybe költöztetve | A6 (a grep a fájl egészére fut) |
| Az L1/L2 szakasz törölve a verification-dokumentumból | A8 |

**A mátrix a származtatott mennyiségre mér:** minden cellában a **beállt router
URI** (`router.state.uri`) az ellenőrzött érték, nem a hívott konstans — az L2
pontosan azért maradt észrevétlen, mert a hívás pillanatában `/today` látszott,
és csak a második redirect-kiértékelés után lett `/practice/live`
(`onboarding_first_win_test.dart:121` vs `:134`).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/routing/shell_entry_location_test.dart test/app/routing/onboarding_first_win_test.dart test/app/routing/app_router_test.dart test/app/navigation/ test/features/onboarding/ test/features/practice_hub/practice_area_hub_cta_test.dart test/features/today/hub_navigation_test.dart test/accessibility/closure_suite_test.dart test/core/screen_size_guard_test.dart test/ui/goldens/e13_r16_screens_golden_test.dart test/ui/goldens/e13_r17_screens_golden_test.dart test/ui/goldens/e15_r13_full_variant_matrix_test.dart test/ui/ui_baseline_screenshot_test.dart test/e2e/full_app_walkthrough_test.dart
```

A parancs **szó szerint tükrözi a `gate_tests` listát** (S12: a metaadatot a
scope-audit olvassa, a kaput a parancssor futtatja — a kettő szétcsúszása néma).
Külön processzben futó `format` → `analyze` → célzott tesztek (útvonalanként
külön hívás a scripten belül) → `architecture` (AGENTS.md §12). `&&` láncolás és
`| tail` **tilos** (L05/L09).

CI-dispatch / PR / merge **Claude-oldal** — a kör ne hívjon `gh`-t.

### 7.1 Falszifikációs cella (KÖTELEZŐ, §10-ben dokumentálva)

Két eldobható mutáció, szó szerinti kimenettel:

1. A CTA URI-építéséből vedd ki a `queryParameters` sort (id nélküli navigáció)
   → **A4/a és A5 cellája PIROS** → állítsd vissza → **ZÖLD**.
2. Az `entryLocationFor` hívását az onboardingban cseréld fix
   `AppRoutes.today`-re → **A2 „shell KI" cellája PIROS** → állítsd vissza →
   **ZÖLD**.

## 8. Implementációs sorrend

1. `entryLocationFor` + az `app_router.dart` átállítása; `shell_entry_location_test.dart`
   megírása (RED → GREEN).
2. Az onboarding két ágának átállítása; `onboarding_first_win_test.dart`
   állításainak átírása.
3. A Practice Area Hub `ConsumerWidget` váltása + id-t hordozó URI + üres-katalógus ág;
   `practice_area_hub_cta_test.dart` (RED → GREEN).
4. A `full_app_walkthrough_test.dart` három híd-sorának törlése, a Setup-állomás
   állításának megfordítása, a bejárás tapintásos úttá alakítása.
5. A §7 gate golden- és pin-cellái (`test/ui/**`, `test/app/navigation/`,
   `test/features/onboarding/`) — ha piros, §0.0 M3 szerint járj el.
6. `docs/release/full-app-verification.md` A3 + L1/L2 frissítése a MÉRT
   kimenettel.
7. §7 gate, §7.1 falszifikáció, §10 handoff.

## 9. Kockázatok

- **A golden-tesztek `const PracticeAreaHubScreen()`-t építenek**
  (`test/ui/goldens/e13_r17_screens_golden_test.dart:77`,
  `test/ui/goldens/e15_r13_full_variant_matrix_test.dart:1431`). Az elsőnél a
  `_pump` helper `ProviderScope`-ot ad (`:34-36`), tehát a `ConsumerWidget`
  váltás ott biztonságos; a másodikat a pre-flightban KELL ellenőrizni. Mindkét
  fájl **tilos zóna** — ha pirosak, az `stopped`, nem javítás.
- **go_router query-only navigáció.** Azonos path + azonos page esetén nincs
  rebuild (ezt az `E16-R05` mérte és kommentelte a `:160-167` sorokban). A javítás
  után a CTA `/practice`-ról egyenesen az id-t hordozó URI-ra megy, tehát a
  csapda nem áll fenn — de ha a bejárás mégis stale `_RouteError`-t lát, az
  **nem** a híd visszaállításával oldandó meg, hanem `stopped`-dal.
- **`test/fixtures/ui/e15_r13_completion_report_baseline.json`** rögzíti a
  `PracticeAreaHubScreen` bejegyzést (`:468-473`), de csak `className` /
  `reachable` / `flagGated` / `migrated` mezőkkel — az ős-osztály váltása nem
  érinti. Ha mégis piros, az `stopped` (tilos zóna).
- **Az `onboarding_first_win_test.dart` átírása** a legérzékenyebb pont: a
  meglévő kommentek a RÉGI viselkedés indoklását tartalmazzák. Az átírás
  kötelezően az ÚJ szerződést írja le; kommentárban maradó „still calls
  `router.go(AppRoutes.live)`" mondat review-lelet.
- **A `widget.onDone` / `widget.onFirstWin` injektált callbackek**: több teszt
  ezeken keresztül figyeli az onboarding végét. A router-navigáció csak akkor
  fut, ha a callback `null` — ez a mai szemantika, és marad.

## 10. Implementation handoff — a Codex tölti ki

*(üres)*

## 11. Review — a Claude tölti ki

*(üres)*
