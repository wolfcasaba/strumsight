# E01-R11 — Routing és alkalmazás-shell stabilizálása

Státusz: PLANNING
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 11 — Routing és alkalmazás-shell stabilizálása"
Branch: `codex/epic-01-round-11-routing`
Brief szerzője: Claude · Implementáció: Codex

**Revízió R1 (2026-07-29).** Az első indítás a brief §5 megállási szabálya szerint
**megállt, nulla kóddiffel**: a kötelező reaktív redirect (§5.4) ütközött az
onboarding first-win vezérlésével, és a javítás nem fért bele az engedélyezett
fájllistába. A megállás helyes volt — a hiba tervezői, nem implementációs. Ez a
revízió feloldja az ütközést: bővül a 4. szekció (onboarding képernyő + egy új
regressziós teszt), és új kötött döntés került az 5. szekcióba (**5.8**), új
kritérium a 6.-ba, új lépés a 8.-ba, új kockázat a 9.-be. A többi változatlan.
A megállás bizonyítéka a §10-ben rögzítendő.

## 1. Cél

A navigáció ma szétszórt string-literálokból és egy ellenőrizetlen `as` castból áll,
a redirect pedig nem reaktív. A kör kimenete egy **központi route-katalógus**
(`AppRoutes`), **argumentum-validáció kontrollált visszairányítással** (nincs több
`state.extra as AnalyzedSession`), **reaktív, loopmentes onboarding-redirect** és az
első valódi **router- és shell-lifecycle tesztkészlet**. Azért most, mert a Chapter 2
hátralévő körei (12–16: backend, CI, végső regresszió) és minden későbbi epic új
képernyőket akaszt erre a shellre — a route-réteget azelőtt kell megszilárdítani,
hogy a felület tovább nőne.

## 2. Jelenlegi állapot

Elolvasott kód (`main` @ `7033fed`):

- **`lib/app/router.dart`** — egyetlen `routerProvider`, 17 `GoRoute` inline
  string-pathokkal, egy `ShellRoute` az öt tabhoz, plusz teljes képernyős
  route-ok (`/tuner`, `/metronome`, `/calibrate`, `/streak`, `/progress`,
  `/songs`, `/setlists`, `/chords`, `/login`, `/library/session`).
  - `redirect` **`ref.read(onboardingSeenProvider)`**-ot hív, és nincs
    `refreshListenable` → a redirect NEM értékelődik újra, amikor az onboarding
    állapota változik; ma csak azért működik, mert az `OnboardingScreen` kézzel
    `context.go('/live')`-et hív (`onboarding_screen.dart:66,89`).
  - `/library/session` buildere: **`state.extra as AnalyzedSession`** — deep link
    vagy `extra` nélküli navigáció esetén ez `TypeError`.
  - Nincs `errorBuilder` / `onException` → ismeretlen path a go_router default
    hibaképernyőjén köt ki.
- **`lib/app/home_shell.dart`** — a tab-lista újra literál
  (`static const _tabs = ['/live', '/analyze', '/learn', '/library', '/settings']`),
  az aktív index `startsWith`-szel számolódik.
- **14 navigációs hívóhely** literál pathtal a feature-ökben (`context.go` /
  `context.push`), lásd a 4. szekció tábláját.
- **`lib/app/strumsight_app.dart:11,22`** az egyetlen importáló
  (`import 'router.dart'` + `ref.watch(routerProvider)`).
- **Mic-lifecycle:** a `LiveScreen.dispose()` NEM állítja le a motort; a mic
  felszabadítása a `liveFrameProvider` (`StreamProvider.autoDispose`)
  `ref.onDispose(engine.stop)`-ján keresztül történik, amikor a Live képernyő
  lekerül a fáról (`lib/features/live/providers/live_providers.dart:11–24`).
  Ez a viselkedés **helyes és megtartandó** — ma viszont semmilyen teszt nem
  bizonyítja a shellen keresztül.
- **Auth:** nincs védett route. A `/login` a Settingsből nyílik és sikeres
  bejelentkezéskor `context.pop()`-pal záródik (`login_screen.dart:54`); az app
  kijelentkezve teljes értékű (`AGENTS.md` §5 termékhatár).
- **Tesztek:** `test/` alatt **nulla** találat `routerProvider` / `GoRouter` /
  `HomeShell` névre — a kör előtt nincs router-teszt.
- **Architecture guard** (`tool/check_architecture.dart`): a `lib/app/` nem
  feature, így a feature-importjai nem sértik a `public.dart` szabályt; a guardot
  ez a kör nem módosítja.
- **Onboarding-befejezés sorrendje (R1 revízió — a megállás oka).**
  `OnboardingController.complete()` (`lib/features/onboarding/onboarding_provider.dart:30–36`)
  **előbb** állítja `state = true`-ra a providert, és **utána** await-eli a
  perzisztálást. Az `OnboardingScreen` mindkét kilépési útja
  (`_finish()` :54–67, `_firstWin()` :72–101) a `complete()` **után**
  `if (!mounted) return`-nel őrzi a navigációt, és a `context`-et az await
  után használja. Amint a redirect reaktívvá válik, a `state = true` azonnal
  elindítja a `/welcome` → `/live` váltást, ami a még futó tárolás-írás alatt
  unmountolja a képernyőt → a `mounted` őr **elnyeli** a first-win lecke
  megnyitását (`Lessons.firstWin`). Ez pontosan az az aktivációs útvonal, amit
  az r155/r156 körök kétszer javítottak (a kód kommentjei ott vannak), és amire
  az injektált `onDone`/`onFirstWin` callbackes tesztek **vakok** — a hibát csak
  a default útvonal mutatja meg. Baseline (Codex mérés, 2026-07-29, `8c9189e`):
  `test/app` 26 zöld, `test/tooling` 8 zöld, `test/features/live` 160 zöld +
  2 skipped, `test/features/library` 12 zöld.

## 3. Scope

**Benne:**

- `AppRoutes` katalógus: minden ma létező path egy helyen, konstansként.
- Az összes `context.go` / `context.push` literál lecserélése a konstansokra
  (viselkedés-azonos, path-string változatlan).
- `route_guards.dart`: az onboarding-redirect **tiszta, widgetfa nélkül
  tesztelhető függvényként**, idempotencia-garanciával (nincs loop).
- Reaktív redirect: `refreshListenable` az `onboardingSeenProvider`-ből,
  `ref.onDispose`-zal felszabadítva.
- `/library/session` argumentum-validáció: rossz/hiányzó `extra` → **kontrollált
  visszairányítás** a `/library`-re (nincs `as` cast, nincs `TypeError`).
- Ismeretlen path kezelése kontrolláltan (`onException` → `/live`).
- Router- és shell-tesztek (5. és 6. szekció).
- Route-literál guard teszt: `context.go('/...')` / `context.push('/...')`
  literál a `lib/` alatt (az `app_route.dart`-on kívül) piros.

**Kívül (ebben a körben TILOS):**

- **Auth-gate / védett route bevezetése.** Az app kijelentkezve teljes értékű
  (`AGENTS.md` §5); az SDD §11.3 „bejelentkezés utáni rossz route / logout utáni
  védett route" pontja ebben a termékben **nem alkalmazható** — ezt a
  handoffban rögzíteni kell, nem megvalósítani.
- Named route-ok (`GoRoute(name:)`), `go_router_builder`, típusos route-osztályok.
- `StatefulShellRoute` bevezetése / tabonkénti state-megőrzés. A mai
  „tabváltás disposeolja az előző képernyőt" viselkedés **szándékos**, mert ez
  szabadítja fel a mikrofont — megváltoztatni ebben a körben tilos.
- Bármilyen DSP-, engine-, storage- vagy backend-változtatás.
- Új képernyő, új user-facing szöveg, ARB-módosítás.
- A `lib/features/**` fájlokban bármi az egysoros navigációs konstans-cserén túl.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `lib/app/routing/app_route.dart` | ÚJ — `AppRoutes` katalógus |
| `lib/app/routing/app_router.dart` | ÚJ — ide költözik a `routerProvider` (a `GoRouter` felépítése) |
| `lib/app/routing/route_guards.dart` | ÚJ — tiszta redirect/guard függvények |
| `lib/app/router.dart` | **TÖRLENDŐ** (tartalma az `app_router.dart`-ba költözik) |
| `lib/app/strumsight_app.dart` | csak az import útvonal cseréje (`routing/app_router.dart`) |
| `lib/app/home_shell.dart` | a `_tabs` literálok → `AppRoutes` konstansok |
| `lib/features/live/screens/live_screen.dart` | 2 nav-hívás (`/tuner`, `/metronome`) → konstans |
| `lib/features/library/screens/library_screen.dart` | 1 nav-hívás (`/library/session`) → konstans |
| `lib/features/learn/screens/lesson_list_screen.dart` | 2 nav-hívás (`/songs`, `/chords`) → konstans |
| `lib/features/settings/screens/settings_screen.dart` | 3 nav-hívás (`/progress`, `/calibrate`, `/login`) → konstans |
| `lib/features/streak/screens/streak_screen.dart` | 2 nav-hívás (`/progress`, `/live`) → konstans |
| `lib/features/streak/widgets/streak_badge.dart` | 1 nav-hívás (`/streak`) → konstans |
| `lib/features/onboarding/screens/onboarding_screen.dart` | 2 nav-hívás (`/live`) → konstans **+ (R1) a `_finish()` / `_firstWin()` navigációs sorrendje az 5.8 szerint** |
| `test/app/routing/app_router_test.dart` | ÚJ — router-viselkedés |
| `test/app/routing/route_guards_test.dart` | ÚJ — guard unit tesztek |
| `test/app/routing/shell_lifecycle_test.dart` | ÚJ — tab-navigáció + mic release |
| `test/tooling/route_literal_guard_test.dart` | ÚJ — route-literál guard |
| `test/app/routing/onboarding_first_win_test.dart` | ÚJ (R1) — késleltetett preference-írás melletti first-win regresszió |
| `docs/rounds/e01-r11-routing-and-app-shell.md` | **csak a 10. szekció** (Implementation handoff) |

**Tilos zóna:** `lib/core/**`, `lib/features/**` minden más fájlja és a felsorolt
fájlokban minden, ami nem a navigációs literál cseréje — **egyetlen kivétel (R1):
`onboarding_screen.dart` `_finish()` / `_firstWin()` metódusai az 5.8 szerint**.
Kiemelten tilos marad **`lib/features/onboarding/onboarding_provider.dart`**
(a `complete()` sorrendje NEM változhat, indoklás az 5.8-ban); `tool/`, `backend/`,
`ml/`, `.github/`, `pubspec.yaml`, `lib/l10n/**`, `docs/**` (a fenti egy fájl 10.
szekcióján kívül), `HANDOFF.md`, RTM, ADR-ek — ezek Claude-oldal.

Ha egy meglévő teszt a változástól elbukik: **NE írd át a tesztet** a zöldért.
Állj meg és jelentsd — a teszt a mai viselkedést rögzíti, és ez a kör
viselkedés-azonos refaktor.

## 5. Kötött architekturális döntések

Ezektől külön ADR nélkül nem lehet eltérni. Előre kiosztott ADR-szám: **`0059`**
(`docs/adr/0059-*.md`) — az ADR-t **Claude írja**, a Codex ne hozzon létre
`docs/adr/` fájlt.

1. **`AppRoutes`** — `abstract final class AppRoutes` csak `static const String`
   tagokkal. A path-értékek **karakterre azonosak** a maiakkal (`/live`,
   `/analyze`, `/learn`, `/library`, `/settings`, `/welcome`, `/tuner`,
   `/metronome`, `/calibrate`, `/streak`, `/progress`, `/songs`, `/setlists`,
   `/chords`, `/login`, `/library/session`). Path-átnevezés ebben a körben nincs.
   A shell tab-sorrendje is innen jön (`AppRoutes.shellTabs`), hogy a
   `HomeShell` és a router ne tudjon szétcsúszni.
2. **Guardok tiszta függvények.** A redirect-logika `route_guards.dart`-ban
   `BuildContext` és `Ref` nélkül tesztelhető, pl.
   `String? onboardingRedirect({required bool seen, required String location})`.
   Az `app_router.dart` `redirect:` callbackje ezt hívja — döntési logika a
   callbackben nem marad.
3. **Idempotencia.** A guard eredményére újra alkalmazva a guardot `null`-t kell
   kapni (`onboardingRedirect(seen: s, location: g!) == null`). Ez a
   redirect-loop objektív, tesztelhető kizárása.
4. **Reaktivitás.** A `GoRouter` `refreshListenable`-t kap, amit a
   `routerProvider` `ref.listen(onboardingSeenProvider, ...)`-ból táplál
   (pl. egy privát `ChangeNotifier`/`ValueNotifier`). A listenable **kötelezően**
   `ref.onDispose`-ban `dispose()`-olva. Riverpod 3, kézzel írt provider, NINCS
   codegen. Az `OnboardingScreen` meglévő `context.go` hívása maradhat — a
   reaktív redirect a védőháló, nem a csere.
5. **Argumentum-validáció.** A `/library/session` route `redirect:`-je
   `state.extra is! AnalyzedSession` esetén `AppRoutes.library`-t ad vissza; a
   builder ezután **típusellenőrzött** ágon kap `AnalyzedSession`-t.
   `as` cast az egész `lib/app/routing/` alatt nem maradhat. Az `AnalyzedSession`
   a `lib/features/library/public.dart`-ból importálandó (R10 contract), nem a
   `model/analyzed_session.dart`-ból.
6. **Ismeretlen path.** `GoRouter(onException: ...)` → kontrollált
   `router.go(AppRoutes.live)`. Nincs saját hibaképernyő és nincs új ARB-kulcs
   (a „kontrollált error route VAGY biztonságos visszairányítás" közül az SDD
   engedte visszairányítást választjuk — kisebb felület, nulla lokalizációs adósság).
7. **A mic-lifecycle mechanizmusa változatlan.** A mikrofont továbbra is a
   `liveFrameProvider` `autoDispose`-a szabadítja fel. A kör ehhez **tesztet**
   ad, nem új mechanizmust.
8. **(R1) Az onboarding kilépési útjai unmount-tűrőek lesznek.** A reaktív
   redirect marad (az SDD §11.3 ezt kéri), a `complete()` sorrendje **nem
   változik** — a state optimista felvillantása szándékos (`onboarding_provider.dart`
   az R06 storage-contract területe, és egy elbukó írás után a felhasználó nem
   ragadhat be az onboardingba). Helyette az `OnboardingScreen` alkalmazkodik:
   - `_finish()` és `_firstWin()` **az első `await` ELŐTT** elkapja a
     navigációs objektumokat (`GoRouter.of(context)`, a first-winnél
     `Navigator.of(context, rootNavigator: true)`) lokális változóba;
   - az await-ek után a kód **nem nyúl `context`-hez**, és a navigációt
     **nem őrzi `mounted`** — a redirect okozta unmount nem nyelheti el;
   - az injektált `widget.onDone` / `widget.onFirstWin` továbbra is meghívódik
     (a meglévő tesztek erre építenek), szintén `mounted`-őr nélkül;
   - a `_finishing` re-entrancia-őr és a postFrame-es lecke-push
     (r156 tanulság) **változatlan marad**;
   - `context.go(...)` helyett az elkapott `router.go(AppRoutes.live)` hívódik.
   Ezen a két metóduson kívül az `onboarding_screen.dart` nem módosulhat
   (nincs UI-, szöveg- vagy állapotváltozás).

## 6. Acceptance criteria

- [ ] `lib/app/router.dart` nincs többé; a `routerProvider`
      `lib/app/routing/app_router.dart`-ban van, az app változatlanul indul.
- [ ] Nulla `context.go('/…')` / `context.push('/…')` **string-literál** a `lib/`
      alatt az `app_route.dart`-on kívül — ezt a
      `test/tooling/route_literal_guard_test.dart` kényszeríti ki, és a guardot a
      handoff szerint **valódi sértéssel is ki kell próbálni** (ideiglenesen
      visszaírt literál → a teszt piros → visszaállítás).
- [ ] Nulla kontrollálatlan cast a route-rétegben: `grep -n " as " lib/app/routing/`
      nem ad route-argumentum castot.
- [ ] `route_guards_test.dart`: első indítás (`seen=false`) bármely pathról
      `/welcome`-ra megy; `seen=true` + `/welcome` → `/live`; `seen=true` +
      bármely más path → `null`; és **idempotencia**: minden fenti esetben a
      visszakapott célra újra futtatva a guard `null`-t ad.
- [ ] `app_router_test.dart`: (a) `seen=false` indulás a `/welcome`-on áll meg;
      (b) az onboarding befejezése (a provider `true`-ra váltása) után a router
      **`context.go` nélkül is** elhagyja a `/welcome`-ot (reaktív redirect);
      (c) `/library/session` `extra` NÉLKÜL → a `/library` látszik, nincs dobott
      kivétel; (d) `/library/session` érvényes `AnalyzedSession`-nel → a
      `SessionDetailScreen` látszik; (e) ismeretlen path (`/nope`) → `/live`,
      nincs kivétel; (f) `/login` elérhető és `pop` után a hívó képernyőn vagyunk.
- [ ] `shell_lifecycle_test.dart`: Live → Settings tabváltás után a Live motor
      **leállt** (a `liveFrameProvider` autoDispose-a lefutott — fake engine
      `stop()` hívásának megfigyelésével, `test/support/fake_engines.dart`
      mintájára), és Live → Tuner → vissza után a shell ugyanazon a tabon áll.
- [ ] **(R1) `onboarding_first_win_test.dart`** — a default útvonalon (injektált
      `onDone`/`onFirstWin` **NÉLKÜL**), valódi `routerProvider`-rel,
      `seen=false` indulásból: a first-win CTA megnyomása után a
      `Lessons.firstWin` lecke képernyője **megjelenik**, ÉS a router a
      `/live`-en áll. A tesztnek **késleltetett** preference-írást kell
      használnia (a teszt fájlban definiált privát `KeyValueStore` dekorátor,
      ami a `writeBool`-t egy `Future.delayed`-del engedi vissza) — a
      megosztott `test/core/storage/in_memory_key_value_store.dart` **nem
      módosítható**. A tesztnek a mai (nem reaktív) kódon is értelmesnek kell
      lennie, az 5.8 nélkül viszont **piros** — ezt a §10-ben bizonyítsd
      (ideiglenesen visszaállított `mounted`-őr → piros → visszaállítás).
- [ ] **(R1)** `flutter test test/features/onboarding` változatlanul zöld
      (a két meglévő teszt egyike sem módosult).
- [ ] `lib/l10n/**`, `pubspec.yaml`, `tool/**` és `lib/core/**` diffje **üres**;
      `lib/features/onboarding/onboarding_provider.dart` diffje **üres**.
- [ ] `git diff --stat main...` kizárólag a 4. szekció tábláját tartalmazza.
- [ ] Egyetlen meglévő teszt sem lett átírva, kikapcsolva vagy lazítva.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12 — soha ne láncold `&&`-del):

```bash
~/flutter/bin/flutter gen-l10n
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/app
~/flutter/bin/flutter test test/tooling
~/flutter/bin/flutter test test/features/live
~/flutter/bin/flutter test test/features/library
~/flutter/bin/flutter test test/features/onboarding
```

A teljes suite + property gate + APK a CI-ban ([ADR 0053](../adr/0053-ci-full-test-suite.md)).
**A CI-dispatch, a PR-nyitás és a merge Claude-oldal** (user-szabály 2026-07-29) —
a Codex ne hívjon `gh`-t.

## 8. Implementációs sorrend

1. `lib/app/routing/app_route.dart` — `AppRoutes` + `shellTabs`.
2. `lib/app/routing/route_guards.dart` — tiszta `onboardingRedirect`
   (+ idempotencia dokumentálva a doc commentben).
3. `test/app/routing/route_guards_test.dart` — a guard tesztjei ELŐBB, mint az
   `app_router.dart` (a guard tiszta függvény, TDD-vel olcsó).
4. `lib/app/routing/app_router.dart` — a mai `router.dart` átemelése a
   konstansokra, `refreshListenable`, `/library/session` redirect-validáció,
   `onException`. `lib/app/router.dart` törlése, `strumsight_app.dart` import.
5. `lib/app/home_shell.dart` — `AppRoutes.shellTabs`.
6. A 7 feature-fájl navigációs literáljainak cseréje (semmi más), majd
   **(R1)** az `onboarding_screen.dart` `_finish()` / `_firstWin()` átalakítása
   az 5.8 szerint + `test/app/routing/onboarding_first_win_test.dart`
   (a teszt ELŐBB, hogy a piros → zöld átmenet bizonyítható legyen).
7. `test/app/routing/app_router_test.dart`, `shell_lifecycle_test.dart`.
8. `test/tooling/route_literal_guard_test.dart` + a guard valódi sértéssel
   való kipróbálása.
9. Format → analyze → célzott tesztek (külön hívásokként), majd a 10. szekció
   kitöltése.

## 9. Kockázatok

- **Redirect-loop.** A reaktív `refreshListenable` minden redirectet újra
  kiértékel; ha a guard nem idempotens, végtelen loop lesz. Ezért kötelező az
  idempotencia-teszt (5.3), és ezért nem kerül döntési logika a callbackbe.
- **Túlnyúló refaktor.** A „route-réteg" csábít a `StatefulShellRoute`-ra és a
  named route-okra — mindkettő scope-on kívül (3. szekció), és a
  `StatefulShellRoute` konkrétan **elrontaná a mikrofon felszabadítását**.
- **Widgetteszt-környezet.** A router-tesztek valódi képernyőket építenek
  (mic, wakelock, storage). Használd a meglévő `test/support/` fake-eket és a
  `ProviderScope(overrides: …)` mintát; ha egy képernyő a teszt-környezetben
  plugint hívna, a Live/Tuner ágat fake engine-nel kell megkerülni — **nem** a
  production kód „teszt-tudatossá" tételével.
- **`onboardingSeenProvider` defaultja `true`** (a widgettesztek átugorják az
  onboardingot). A `seen=false` ágat expliciten felül kell írni a tesztben.
- **(R1) A first-win útvonal load-bearing és kétszer elrontott** (r155, r156).
  A veszély nem a kód, hanem a **teszt-vakság**: az injektált callbackes tesztek
  akkor is zöldek, ha a default útvonal néma. Ezért kötelező a callback nélküli,
  késleltetett írású regressziós teszt, és ezért kell bizonyítani, hogy a teszt
  az 5.8 nélkül piros. Ha a `Navigator`/`GoRouter` await előtti elkapása a
  teszt-környezetben nem működik, az **megállási pont** — ne kerüld meg a
  `complete()` sorrendjének átírásával.
- **(R1) Friss klón = hiányzó generált lokalizáció.** A `test/app` futtatása
  előtt `~/flutter/bin/flutter gen-l10n` kell (a generált
  `app_localizations*.dart` gitignore-olt). Ez nem kódhiba.

## 10. Implementation handoff — a Codex tölti ki

### Fájlonkénti összefoglaló

- `lib/app/routing/app_route.dart` — új, teljes `AppRoutes` path-katalógus és
  az öt shell-tab egyetlen sorrendi forrása (`shellTabs`).
- `lib/app/routing/route_guards.dart` — tiszta, `BuildContext`/`Ref` nélküli,
  idempotens `onboardingRedirect`.
- `lib/app/routing/app_router.dart` — ide költözött a `routerProvider`; a
  provider-változás `ChangeNotifier`-en frissíti a redirectet, a router és a
  notifier a provider `ref.onDispose` callbackjében felszabadul, a session-extra
  validált, az ismeretlen path `/live`-ra áll helyre.
- `lib/app/router.dart` — törölve; kontrollálatlan `AnalyzedSession` casttal
  együtt megszűnt.
- `lib/app/strumsight_app.dart` — az új routermodul importját használja.
- `lib/app/home_shell.dart` — tabfelismerés és tabváltás
  `AppRoutes.shellTabs`-ból dolgozik.
- `lib/features/live/screens/live_screen.dart` — Tuner és Metronome hívóhely
  `AppRoutes` konstansra cserélve.
- `lib/features/library/screens/library_screen.dart` — session-detail hívóhely
  `AppRoutes.librarySession`-t használ.
- `lib/features/learn/screens/lesson_list_screen.dart` — Songs és Chords
  hívóhely `AppRoutes` konstansra cserélve.
- `lib/features/settings/screens/settings_screen.dart` — Progress, Calibrate és
  Login hívóhely `AppRoutes` konstansra cserélve.
- `lib/features/streak/screens/streak_screen.dart` — Progress és Live hívóhely
  `AppRoutes` konstansra cserélve.
- `lib/features/streak/widgets/streak_badge.dart` — Streak hívóhely
  `AppRoutes.streak`-et használ.
- `lib/features/onboarding/screens/onboarding_screen.dart` — a két Live
  navigáció `AppRoutes`-ot használ; `_finish()` és `_firstWin()` a default
  routert/root navigatort az első await előtt, csak a default callbackágban
  kapja el, majd unmount után is végigviszi a navigációt. Az injektált callbackes
  `MaterialApp`-tesztek ezért változatlanul működnek.
- `test/app/routing/route_guards_test.dart` — unseen/seen döntési tábla és
  redirect-idempotencia.
- `test/app/routing/app_router_test.dart` — első indítás, callback nélküli
  reaktív redirect, hibás/érvényes session-extra, ismeretlen path és valódi
  Settings → Login → sikeres pop, valamint a provider tulajdonolta router
  felszabadítása.
- `test/app/routing/shell_lifecycle_test.dart` — Live → Settings mic release és
  Live → Tuner → back tab-megőrzés fake engine-ekkel.
- `test/app/routing/onboarding_first_win_test.dart` — callback nélküli,
  két másodperccel késleltetett `KeyValueStore.writeBool` melletti first-win
  regresszió valódi `routerProvider`-rel.
- `test/tooling/route_literal_guard_test.dart` — a `lib/` alatti közvetlen
  `context.go('/…')` / `context.push('/…')` literálokat fájl:sor pontossággal
  tiltja.

### Futtatott parancsok és tényleges eredmények

- `~/flutter/bin/flutter gen-l10n` — exit 0; az `l10n.yaml` beállításait
  használta, tracked l10n-diff nem keletkezett.
- `~/flutter/bin/dart format --output=none --set-exit-if-changed lib test` —
  exit 0, `Formatted 445 files (0 changed)`.
- `~/flutter/bin/flutter analyze lib/ test/` — a végső futás exit 0,
  `No issues found!`. Az első futás egyetlen
  `unused_element_parameter` warningot talált a regressziós teszt fölösleges
  opcionális `delay` paraméterén; egy javítási kísérlet után lett zöld.
- `~/flutter/bin/flutter test test/app` — exit 0, 39 teszt zöld.
- `~/flutter/bin/flutter test test/tooling` — exit 0, 9 teszt zöld.
- `~/flutter/bin/flutter test test/features/live` — exit 0, 160 teszt zöld,
  2 meglévő teszt skipped.
- `~/flutter/bin/flutter test test/features/library` — exit 0, 12 teszt zöld.
- `~/flutter/bin/flutter test test/features/onboarding` — exit 0, 7 teszt
  zöld; a két meglévő tesztfájl változatlan.
- Guard TDD: az első `route_guards_test.dart` futás a null stubon 3/3 várt
  assertionnel piros; a minimális döntési logika után 3/3 zöld.
- Router TDD: a régi viselkedést megtartó átköltöztetésen 3 teszt zöld és
  pontosan 3 új szerződés piros volt (reaktív redirect, hiányzó extra
  `TypeError`, ismeretlen path); implementáció után 6/6 zöld. A belső
  diff-audit által talált provider-lifecycle hiány reprodukáló tesztje először
  6+1 állásban a várt módon piros volt (a dispose utáni `router.go` nem dobott),
  majd a `GoRouter` providerhez kötött felszabadítása után 7/7 zöld.
- First-win TDD: a késleltetett írású teszt a régi `mounted`-őrrel 0/1 piros
  (`LearnScreen` nem volt a fában), az 5.8 implementáció után 1/1 zöld.
- Belső read-only újra-review: a router-lifecycle javítása után nem maradt
  BLOCKER, MAJOR vagy MINOR megállapítás.
- `git diff --check` — exit 0.
- `rg -n "context\\.(go|push)\\(\\s*['\\\"]" lib` — nincs találat.
- `grep -R -n " as " lib/app/routing` — route-argumentum cast nincs; egyetlen
  szöveges találat az `app_route.dart` doc commentjének angol „as” szava.
- A `7033fed` (`origin/main` merge-base) ellen futtatott tiloszóna-diff
  (`lib/core`, `lib/l10n`, `pubspec.yaml`, `tool`, `backend`, `ml`, `.github`,
  `HANDOFF.md`, ADR/RTM, `onboarding_provider.dart`) exit 0 és üres; meglévő
  tesztfájl módosítása szintén nincs.

### Negatív bizonyítások

- Route-literál guard: ideiglenesen
  `streak_badge.dart`-ban `context.push('/streak')` került vissza. A teszt
  exit 1-gyel bukott, tényleges találat:
  `Actual: ['lib/features/streak/widgets/streak_badge.dart:27']`. A konstans
  visszaállítása után 1/1 zöld.
- First-win regresszió: a kész kódba ideiglenesen visszatett
  `if (!mounted) return;` mellett a router már `/live`-on állt és az onboarding
  unmountolt, de a végső `tester.widget<LearnScreen>` `Bad state: No element`
  hibával bukott. Az őr eltávolítása után 1/1 zöld.

### Eltérések és nem futtatott ellenőrzések

- Az első, R1 előtti indítás helyesen megállt nulla kóddiffel, mert a reaktív
  redirect és a first-win útvonal az akkori engedélyezett fájllistán belül nem
  volt összeegyeztethető. Az R1 §5.8 és a kibővített fájllista ezt feloldotta;
  újabb architekturális eltérés nem merült fel.
- A brief szó szerinti `git diff --stat main...` parancsa ebben az egylokális-
  branches klónban nem futtatható (`main` lokális ref nincs, csak
  `origin/main`). A scope-audit a kanonikus `origin/main` merge-base
  `7033fed` ellen futott; commit után a review-hoz az ekvivalens
  `git diff --stat origin/main...HEAD` használható.
- Teljes `flutter test`, randomizált property gate és release APK lokálisan
  nem futott: ADR 0052/0053 és az explicit user-utasítás szerint ezek a
  Claude-oldali branch-CI feladatai. `gh`, PR-nyitás és merge nem történt.
- Backend/ML gate nem futott, mert backend-, ML- vagy DSP-változás nincs.
- Valódi device/real-audio gate nem futott; a mic-mechanizmus nem változott,
  a kör a meglévő autoDispose útvonalat determinisztikus fake engine-nel védi.

### SDD §11.3 auth-státusz és follow-up

- Auth-gate/védett route továbbra sincs és ebben a termékben a „login után
  rossz route” / „logout után védett route-on maradás” pont nem alkalmazható:
  kijelentkezve az offline alapapp teljes értékű. A meglévő `/login` route
  elérhetőségét és sikeres auth utáni Settingsre `pop`-ot a routerteszt lefedi.
- Nyitott product/code follow-up nincs. Következő folyamatlépés: Claude
  független review-ja, branch-CI, PR és zöld-kapus merge. A következő SDD-kör
  ezután, új sessionben: **E01-R12 — Backend konfiguráció és
  adatbázis-migráció**.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r11-review.md`
