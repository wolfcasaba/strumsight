# E01-R11 — Routing és alkalmazás-shell stabilizálása

Státusz: PLANNING
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 11 — Routing és alkalmazás-shell stabilizálása"
Branch: `codex/epic-01-round-11-routing`
Brief szerzője: Claude · Implementáció: Codex

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
| `lib/features/onboarding/screens/onboarding_screen.dart` | 2 nav-hívás (`/live`) → konstans |
| `test/app/routing/app_router_test.dart` | ÚJ — router-viselkedés |
| `test/app/routing/route_guards_test.dart` | ÚJ — guard unit tesztek |
| `test/app/routing/shell_lifecycle_test.dart` | ÚJ — tab-navigáció + mic release |
| `test/tooling/route_literal_guard_test.dart` | ÚJ — route-literál guard |
| `docs/rounds/e01-r11-routing-and-app-shell.md` | **csak a 10. szekció** (Implementation handoff) |

**Tilos zóna:** `lib/core/**`, `lib/features/**` minden más fájlja és a felsorolt
fájlokban minden, ami nem a navigációs literál cseréje; `tool/`, `backend/`,
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
- [ ] `lib/l10n/**`, `pubspec.yaml`, `tool/**` és `lib/core/**` diffje **üres**.
- [ ] `git diff --stat main...` kizárólag a 4. szekció tábláját tartalmazza.
- [ ] Egyetlen meglévő teszt sem lett átírva, kikapcsolva vagy lazítva.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12 — soha ne láncold `&&`-del):

```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test
~/flutter/bin/flutter analyze lib/ test/
~/flutter/bin/flutter test test/app
~/flutter/bin/flutter test test/tooling
~/flutter/bin/flutter test test/features/live
~/flutter/bin/flutter test test/features/library
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
6. A 7 feature-fájl navigációs literáljainak cseréje (semmi más).
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

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + TÉNYLEGES kimenet (ne állíts sikert, ami nem futott).
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk.
- A route-literál guard valódi sértéssel való kipróbálásának kimenete.
- Az SDD §11.3 auth-vonatkozású pontjának státusza (miért nem alkalmazható).
- Follow-up issue-k.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r11-review.md`
