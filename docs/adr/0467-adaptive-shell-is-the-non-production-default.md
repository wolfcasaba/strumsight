# ADR 0467 — Az adaptív shell a nem-production alapértelmezés

- **Státusz:** elfogadva (2026-08-28, E15-R02 pre-flight)
- **Kontextus:** SDD Chapter 15, Kör 2;
  [`docs/rounds/e15-r02-adaptive-shell-default-and-overflow-fixes.md`](../rounds/e15-r02-adaptive-shell-default-and-overflow-fixes.md)
- **Kapcsolódó:** [ADR 0275](0275-five-area-shell-behind-a-flag.md) (az ötterületes
  shell flag mögött, alapértelmezetten KI — „a bekapcsolás **user-döntés**"),
  [ADR 0426](0426-golden-rasterization-on-the-gate-architecture.md) (a
  raszterizáció a kapu architektúráján mérendő),
  [ADR 0446](0446-feature-flag-registry-and-emergency-kill-switch.md)
  (a flag-nyilvántartás és a kill-switch dokumentációs szerződése),
  [L180](../LESSONS.md#l180) (zsugorodás-őr: a mérő cellát átfordítjuk, nem
  töröljük), [L449](../LESSONS.md#l449) (az `indexedStack` életben tartja a
  meglátogatott brancheket → mikrofon/wakelock retenció),
  [L517](../LESSONS.md#l517) és [L524](../LESSONS.md#l524) (a `textScaler 2.0`
  keret és a PNG NÉLKÜLI variáns-mátrix valódi `lib/**` defektet mér)

## Kontextus — mért tények (E15-R02 pre-flight, `main @ e65b1738`)

1. **A shell MINDEN környezetben ki van kapcsolva.**
   `lib/app/config/feature_flags.dart:129` → `adaptiveShellEnabled: false`, a
   `forEnvironment` gyárban; dart-define felülírás szándékosan NINCS
   (ADR 0275). A csupasz konstruktor alapértéke szintén `false` (`:52`).
2. **A flag a belépési pontot vezérli.**
   `lib/app/routing/app_router.dart:215` →
   `entryLocation = adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live`,
   és a tizenegy legacy redirect (`legacyRedirects`,
   `lib/app/routing/adaptive_shell_routes.dart:10`) CSAK bekapcsolt shell
   mellett él (`app_router.dart:228`).
3. **A user 2026-08-28-án megadta a bekapcsolási döntést** („minden legyen
   migrálva, javítva, hogy lássam a valódi appot"). Az ADR 0275 §1 pontosan
   ezt a döntést tartotta fenn a usernek — tehát ez az ADR **nem írja felül**
   az ADR 0275-öt, hanem a benne fenntartott döntést rögzíti.
4. **A két mért elrendezési hiba a bekapcsolással válik felhasználó által
   elérhetővé** (`docs/ui/legacy-backlog.md` §1): a
   `live_screen.dart:477` stat-sor `Row`-ja landscape + `textScale 2.0`
   mellett 12 px (`en`) / 34 px (`hu`) túlcsordulás, a
   `permission_primer_screen.dart` véglegesen-elutasított ága pedig 297 px
   alul — utóbbi a retryable ágtól eltérően NINCS `SingleChildScrollView`-ba
   burkolva (`permission_primer_screen.dart:98-107` vs `:111-115`).
5. **A teszt-alapértelmezés is a `forEnvironment`-ből jön.** Az
   `appConfigProvider` alapértéke (`lib/app/config/app_config.dart:201-213`)
   `FeatureFlags.forEnvironment(AppEnvironment.development, …)` — tehát a
   `nonProd` átállítás MINDEN olyan widget-tesztre hat, amely nem írja felül
   az `appConfigProvider`-t. Ez a döntés legdrágább következménye (lásd D6).

## Döntés

**D1.** `FeatureFlags.forEnvironment` mostantól `adaptiveShellEnabled: nonProd`
— `development` és `lab` környezetben BE, `production` környezetben KI. A
csupasz konstruktor alapértéke változatlanul `false` marad: a kézzel
összeállított flag-halmaz továbbra is explicit opt-int kíván.

**D2.** A production ág bekapcsolása NEM része ennek a döntésnek. A GA-scope-ot
a Chapter 12 Kör 28 dönti el; addig a production felület a legacy navigáció.
A „úgyis ugyanaz a kód" érv nem elfogadható indok a production bekapcsolására.

**D3.** Dart-define felülírás továbbra sem létezik (ADR 0275 változatlan
álláspontja): a shell állapota a környezetből következik, nem build-paraméterből.

**D4.** A legacy útvonalak megmaradnak átirányításként. A `legacyRedirects`
tizenegy bejegyzése és a query/fragment megőrzése a szerződés része — mentett
mélylinkek és widget-tesztek is ezeken érkeznek. Route törlése tilos.

**D5.** A két mért túlcsordulás javítása ugyanennek a döntésnek a része, nem
külön kör: a bekapcsolás nélkül a hiba elméleti, a javítás nélkül a
bekapcsolás felhasználóhoz szállított hibát jelent.

**D6.** A mérő cellákat ÁTFORDÍTJUK, nem töröljük (L180). A négy
`_ExcludedCell` (`test/ui/goldens/e13_r36_variant_matrix_test.dart`) és a
closure-suite „A4" cellája a javítás után „NINCS túlcsordulás"-t állít; a
cella eltávolítása a hiba visszatérését észrevétlenné tenné.

**D7.** A raszter újrafelvétele KIZÁRÓLAG `tools/golden-x86.sh record` úton
történhet (ADR 0426): az aarch64 boxon felvett PNG a kapu x86 architektúráján
mindig piros (L516).

**D8.** A kill-switch dokumentációja igazat kell mondjon (ADR 0446): a
`feature_flag_registry.dart` `adaptiveShellEnabled` bejegyzésének
`killSwitchPath` szövege ma azt állítja, hogy a flag „hardcoded to `false` in
every environment" — a D1 után ez hamis. A visszavonás egyetlen helye a
`feature_flags.dart:129` sor `nonProd` → `false` átírása.

## Következmények

**Pozitív.** A felhasználó a fejlesztői és lab buildekben a valódi, ötterületes
felületet látja; a Chapter 15 további migrációs körei azon a felületen mérhetők,
amelyet szállítani fogunk. A két ismert elrendezési hiba lezárul.

**Negatív / ár.** A `nonProd` átállítás a teszt-alapértelmezést is átbillenti
(Kontextus/5): minden olyan widget-teszt, amely a valódi routert pumpálja és
`/live`-ot vár belépési pontként, viselkedésében megváltozik. Ez MÉRT, nem
becsült — a pre-flight próba számszerűsítette (lásd a kör briefjének §0.0/c
szakaszát). A production felület átmenetileg eltér a fejlesztőitől.

**Amit ez a döntés TILT.** A production bekapcsolását; a legacy route-ok
redirect nélküli elhagyását; a mérő cellák törlését vagy `skip`-jét; a golden
PNG-k aarch64 boxon való újrafelvételét; a tartalmi képernyő-migráció
beszivárgását ebbe a körbe (az a Chapter 15 további köreinek dolga).
