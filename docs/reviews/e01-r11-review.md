# E01-R11 — Review

Brief: `docs/rounds/e01-r11-routing-and-app-shell.md` (R1 revízió)
Diff: `git diff main...codex/epic-01-round-11-routing` (`a38745a`)
Reviewer: Claude · Dátum: 2026-07-29
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 3

A kör azt szállította, amit a brief kért, és a legkockázatosabb pontján — az
onboarding first-win útvonalán — a teszt **valóban reprodukálja a race-t**,
nem csak a végállapotot ellenőrzi. A kör első futása helyesen megállt egy
tervezői ütközésnél (lásd a brief R1 revíziójegyzetét); a második futás a
revideált szerződés szerint dolgozott.

## Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Áll |
|---|---|---|---|
| 1 | `router.dart` megszűnt, `routerProvider` a `routing/app_router.dart`-ban | diff: `lib/app/router.dart` −69, `app_router.dart` +116; `strumsight_app.dart` import 1 sor | ✅ |
| 2 | Nulla `context.go/push('/…')` literál a `lib/` alatt | `test/tooling/route_literal_guard_test.dart` zöld; **valódi sértéssel kipróbálva** (ideiglenes `lib/app/_guard_probe.dart` `context.go('/live')`-vel → a teszt PIROS, próba törölve) | ✅ |
| 3 | Nincs kontrollálatlan cast a route-rétegben | `grep -n " as " lib/app/routing/` → egyetlen találat egy doc-comment szövegében, kód nem | ✅ |
| 4 | Guard-tesztek: seen/unseen + **idempotencia** | `route_guards_test.dart` 3 esete, köztük „every redirect target is stable when evaluated again" | ✅ |
| 5 | Router-tesztek (a–f) | `app_router_test.dart` 7 esete: first launch → welcome; provider-váltás `context.go` NÉLKÜL elhagyja a welcome-ot; `extra` nélküli session → library; érvényes session → detail; ismeretlen path → live; login pop; **container dispose → router+notifier dispose** | ✅ |
| 6 | Shell lifecycle: Live → Settings után a motor leállt | `shell_lifecycle_test.dart`: `stopCalls` nő a tabváltás után („the mic must not stay hot after leaving Live"), és Tuner → vissza ugyanazon a tabon áll | ✅ |
| 7 | **(R1)** first-win a default úton, késleltetett írással | `onboarding_first_win_test.dart`: injektált callback NÉLKÜL, valódi `routerProvider`-rel, saját `_DelayedBoolWriteStore` dekorátorral (2s `writeBool`); a teszt **expliciten állítja, hogy a képernyő már unmountolt és az írás MÉG NEM fejeződött be** (`boolWriteCompleted isFalse`, `OnboardingScreen findsNothing`), és utána nyílik meg a `Lessons.firstWin` lecke | ✅ |
| 8 | **(R1)** `test/features/onboarding` változatlanul zöld, meglévő teszt nem módosult | diff: `test/features/onboarding/**` érintetlen | ✅ |
| 9 | `lib/l10n/**`, `pubspec.yaml`, `tool/**`, `lib/core/**`, `onboarding_provider.dart` diffje üres | `git diff --stat` | ✅ |
| 10 | A diff csak a brief 4. szekciójának fájljait tartalmazza | 19 fájl, mind a listán (a brief `docs/rounds/…md` a §10 handoff) | ✅ |

## Scope

`git diff --stat origin/main...HEAD` — 19 fájl, +1137/−95. Minden útvonal az
engedélyezett listán van; tilos zóna nem sérült. A `CODEX_ROUND_PROMPT.md`
szándékosan untracked maradt.

## Architektúra és termékhatárok

- A `lib/app/` nem feature, így a feature-screen importok nem sértik a
  `public.dart` szabályt; az `AnalyzedSession` viszont helyesen a
  `features/library/public.dart`-ból jön (R10 contract, brief §5.5).
- Lifecycle: a mikrofon-felszabadítás mechanizmusa változatlan
  (`liveFrameProvider` autoDispose) — a kör tesztet adott hozzá, nem új utat.
  Az `app_router.dart` a routert ÉS a refresh-notifiert is felszabadítja
  `ref.onDispose`-ban; a korábbi kód a routert egyáltalán nem disposeolta.
- Nyers audio, hálózat, secret: nem érintett.

## Megállapítások

### MINOR-1 — a route-literál guard nem fogja a `router.go('/…')` alakot

`test/tooling/route_literal_guard_test.dart` regexe csak a
`context.go|push('/…')` alakra illeszkedik. **Mérve:** egy ideiglenes
`router.go('/live')` literált tartalmazó fájllal a guard **zöld marad**
(ugyanaz a próba `context.go`-val piros). Ez pont az a hívásforma, amit ez a
kör vezetett be az `onboarding_screen.dart`-ban (`router!.go(AppRoutes.live)`),
tehát a guard a saját új mintájára vak.

A brief betűjének megfelel (a kritérium a két `context.*` alakot kérte), ezért
nem blokkol. Javasolt javítás egy soron: a receiver elhagyása és a további
navigációs metódusok bevonása —
`\.\s*(?:go|push|replace|pushReplacement|goNamed)\s*\(\s*['"]/`, a katalógus
fájl kizárásával. Follow-up: E01-R14 (Flutter CI és release pipeline), amely
úgyis a guard/CI réteget viszi.

### NOTE-1 — az SDD §11.3 auth-vonatkozású pontja nem alkalmazható

Nincs védett route; az app kijelentkezve teljes értékű (`AGENTS.md` §5). A kör
ezt helyesen dokumentálta és nem épített auth-gate-et. A `/login` elérhetőségét
és a pop-visszatérést teszt fedi.

### NOTE-2 — `_finish()` / `_firstWin()` navigációs elkapása feltételes

A `GoRouter.of(context)` / `Navigator.of(context)` csak akkor kerül elkapásra,
ha nincs injektált callback. Ez szándékos és helyes: a callbackes tesztek
router nélküli fában is pumpolhatják a képernyőt. A `router!` / `navigator!`
non-null állítás pontosan ugyanazon feltétel mellett fut, tehát biztonságos.

### NOTE-3 — a `redirect` `ref.read`-et használ `ref.watch` helyett

Szándékos: a reaktivitást a `refreshListenable` adja, a `ref.watch` egy
`Provider`-ben a router újraépítését okozná (és eldobná a navigációs stacket).

## Gate-bizonyíték (függetlenül újrafuttatva ezen a boxon)

| Gate | Eredmény |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 445 fájl, 0 változott |
| `flutter analyze lib/ test/` | No issues found (6.4s) |
| `flutter test test/app/routing test/tooling` | 22/22 zöld |
| Guard valódi sértéssel | `context.go('/live')` injektálva → PIROS; visszaállítva → zöld |
| CI (teljes suite + property gate + release APK) | [run 30481963720](https://github.com/wolfcasaba/strumsight/actions/runs/30481963720) **success**, 9m5s, `a38745a`-n |

A CI-run a review alatt futott, az `a38745a` commiton — ugyanazon a shán, amit
ez a jelentés átnézett.

## Verdikt

**APPROVED.** BLOCKER és MAJOR nincs; a MINOR-1 nem blokkol és follow-upként
az E01-R14-be megy. A merge az ADR 0052 zöld-kapus szabálya szerint mehet.
