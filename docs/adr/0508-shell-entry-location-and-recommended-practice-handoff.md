# ADR 0508 — A belépési hely EGY forrásból származik, és a shell ajánlott-gyakorlás átadása mindig hordoz definíció-azonosítót

- **Státusz:** elfogadva
- **Dátum:** 2026-09-04
- **Kör:** `E16-R06` (Chapter 16 — javító kör az E16-R05 mért L1/L2 leletére)
- **Kapcsolódó:** [`0275`](0275-adaptive-shell-navigation-contract.md)
  (adaptív shell navigációs szerződés, `legacyRedirects`, stage-route fogalom),
  [`0078`](0078-practice-hub-and-setup-contract.md)
  (a Setup a definíciót **id-ból** oldja fel),
  [`0276`](0276-practice-area-hub-resource-free-navigation.md)
  (a Practice Area Hub erőforrás-mentes: csak navigál),
  [`0281`](0281-onboarding-permission-primer-boundary.md)
  (az onboarding befejező ága, a permission-primer határ),
  [`0472`](0472-e2e-harness-boot-contract.md) (`bootE2eApp`, E2E harness),
  [`0002`](0002-feature-first-clean-architecture.md)
  (cross-feature import CSAK a cél-feature `public.dart` barreljén át)
- **Előzmény:** `docs/release/full-app-verification.md` **A3 = NEM teljesül**
  (E16-R05, mérve 2026-09-04) — L1 és L2 lelet

## Kontextus

Az `E16-R05` zárókör gépi bejárással (`test/e2e/full_app_walkthrough_test.dart`)
mérte, hogy a szállított `FeatureFlags.forEnvironment(development,
accountEnabled: false)` BE-készlettel a core út végigjárható-e a termék SAJÁT
navigációjával. A verdikt **negatív** volt, és a bejárás **két teszt-oldali
`router.go` hidat** kényszerült beépíteni, hogy egyáltalán eljusson az
állomásokig. A két hidat okozó lelet a `main @ baf2f61d` fán mérve:

**L2 — az onboarding mindig `/live`-ra fejez be.**
`OnboardingScreen._completeFinish` (`lib/features/onboarding/screens/onboarding_screen.dart:106`)
feltétel nélkül `router.go(AppRoutes.live)`-ot hív, ugyanígy a first-win ág
(`:129`). A router SAJÁT belépési logikája viszont
(`lib/app/routing/app_router.dart:231`)
`final entryLocation = adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live;`
— vagyis a shell BE állapotában `/today` a belépő. A két hely **külön dönt
ugyanarról**, és az onboarding oldala nem is olvassa a flaget. Következmény:
`legacyRedirects[AppRoutes.live] = AppRoutes.practiceLive`
(`lib/app/routing/adaptive_shell_routes.dart:11`), a `/practice/live` pedig
`isStageRoute` szerint **elsődleges navigáció nélküli** stage-route — az első
belépés így egy olyan képernyőn ér véget, ahonnan a shell többi része nem
elérhető. Ezt a mai teszt-készlet nem hibaként, hanem **rögzített tényként**
írja le (`test/app/routing/onboarding_first_win_test.dart:114-134`: „still calls
`router.go(AppRoutes.live)` literally").

**L1 — a shell egyetlen ajánlott-gyakorlás CTA-ja nem ad át `id`-t.**
`PracticeAreaHubScreen` (`lib/features/practice_hub/screens/practice_area_hub_screen.dart:55`)
`context.go(AppRoutes.practiceSetup)`-ot hív **`?id=` nélkül**, miközben a
legacy Hub `_openSetup`-ja
(`lib/features/practice/presentation/screens/practice_hub_screen.dart:145-151`)
mindig `Uri(path: …, queryParameters: {'id': definition.id})`-t épít.
`PracticeSetupScreen._readArgs` (`practice_setup_screen.dart:52-57`) ezért
`PracticeSetupRequest.missing`-et kap, és a képernyő a `_RouteError` ágát
rendereli. A hiba-ág maga korrekt és lokalizált — a defekt az, hogy az adaptív
shell **egyetlen hirdetett belépője** egy pontozott gyakorlásba méréssel
zsákutca.

A két lelet közös mintája: **egy döntés két helyen születik meg** (belépési
hely), illetve **egy átadási szerződés egyik hívóoldalon hiányos** (definíció-id).

## Döntés

### D1 — A belépési hely EGY tiszta függvényből származik

A `adaptiveShellEnabled → belépési útvonal` leképezés egyetlen helyen él:
`lib/app/routing/adaptive_shell_routes.dart` egy tiszta, Flutter-független
függvényében (`entryLocationFor(bool adaptiveShellEnabled)`), és **mind** a
router (`app_router.dart:231`), **mind** az onboarding befejező ága ezt hívja.

**NEM elfogadható**: az onboardingba beírt `AppRoutes.today` konstans (akkor sem,
ha ma ugyanazt az értéket adja), és nem elfogadható a router-oldali kifejezés
érintetlenül hagyása egy második, „ugyanolyan" kifejezés mellett. A duplikátum
tilalma a döntés lényege — nem a mai értéke.

### D2 — Az onboarding MINDKÉT befejező ága a belépési helyre megy

`_completeFinish` (Skip/finish) és `_completeFirstWin` (aktivációs rövidítés)
alap-navigációja egyaránt `entryLocationFor(...)`. A first-win ág
**változatlanul** a root navigátoron, post-frame callbackben pusholja a
`LearnScreen(lesson: Lessons.firstWin)`-t — a push sorrendje és gazdája
(`onboarding_screen.dart:128-138`) nem tervezhető újra.

**NEM elfogadható**: a first-win ág `/live`-on hagyása azzal az indokkal, hogy
„úgyis push jön rá" — a push lezárása után a felhasználó pontosan azon a
navigáció nélküli stage-route-on marad, amit az L2 leír.

### D3 — Az ajánlott-gyakorlás átadása mindig hordoz definíció-azonosítót

A Practice Area Hub ajánlott CTA-ja a Setup route-ot ugyanabban az URI-alakban
nyitja meg, mint a legacy Hub `_openSetup`-ja: `?id=<definíció id>`, ahol a
definíció a katalógus **első** eleme (`practiceCatalogProvider`, a legacy Hub
Quick Start kártyájával azonos szemantika). A képernyő ehhez `ConsumerWidget`-té
válik, és a providert a **`lib/features/practice/public.dart` barrelen** át
olvassa (ADR 0002 cross-feature szabály; precedens: `app_router.dart:36`).

**NEM elfogadható**: bedrótozott id-literál (`'builtin.quarterDownstrokes.v1'`)
a hub-ban, mély import a `practice` feature belsejébe, és a Setup-oldal
felpuhítása („ha nincs id, vegye a katalógus elsejét") — a hiányzó id
**továbbra is** `_RouteError`, a szerződés a hívóoldalon teljesül.

### D4 — Üres katalógus: nincs CTA, nem néma zsákutca

Ha `practiceCatalogProvider` üres listát ad, az ajánlott-kártya **nem
renderelődik**. Az ADR 0276 erőforrás-mentessége sértetlen: a hub továbbra is
csak navigál.

**NEM elfogadható**: `?id=` nélküli navigáció „fallbackként", és nem elfogadható
egy tiltott gomb magyarázat nélkül. Új ARB-kulcs ehhez nem kell — a kártya
elhagyása a teljes, mérhető viselkedés.

### D5 — A bejárás hídjai megszűnnek, az A3 újramérve

`test/e2e/full_app_walkthrough_test.dart` két teszt-oldali navigációja
(`session.router.go(AppRoutes.today)` a Skip után, valamint a
`router.go(practiceHub)` + `router.go('${practiceSetup}?id=…')` páros) **törlésre
kerül**: a bejárás a Today Hubra és az id-t hordozó Setupra kizárólag
**tapintással** jut el. A `docs/release/full-app-verification.md` A3 szakasza az
új mérésre íródik át.

**NEM elfogadható**: a híd megtartása frissített kommentárral, és nem elfogadható
az L1/L2 szakaszok törlése a verification-dokumentumból — a leletek maradnak,
melléjük kerül a feloldás köre és a mért bizonyíték.

## Következmények

- Az adaptív shell gerince (`onboarding → Today → Practice Area Hub → Setup →
  Session`) a termék saját navigációjával válik bejárhatóvá; az A3 elfogadási
  feltétel ezzel mérhetően teljesíthető.
- A `entryLocationFor` bevezetése után a belépési hely megváltoztatása egyetlen
  fájl egyetlen függvényét érinti — a router és az onboarding nem tud egymástól
  elcsúszni.
- A `PracticeAreaHubScreen` `StatelessWidget` → `ConsumerWidget` váltása
  provider-olvasót visz egy eddig statikus képernyőbe. Az ADR 0276
  erőforrás-mentessége nem sérül: a `practiceCatalogProvider` egy const listát ad
  vissza, mikrofont/kamerát nem nyit.
- `test/app/routing/onboarding_first_win_test.dart` mai állításai a RÉGI
  viselkedést rögzítik (`/today` átmenetileg, majd `/practice/live` beállva) —
  ezek az új szerződésre íródnak át, nem a szerződés igazodik hozzájuk.
