# E16-R06 review — a viselkedés helyes és a scope tiszta, de az A2 mátrix fele mérve nem falszifikálható → CHANGES REQUESTED (egy, olcsó teszt-erősítés)

- **Kör:** `E16-R06` — A shell gerince a termék saját navigációjával járható
- **Branch:** `sonnet-impl/e16-r06-shell-backbone-navigation-hotfix`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude (Opus 5), független read-only review (ADR 0055)
- **Mért fa:** `3fd8a1d2` (implementációs commit `692062a1` + `origin/main` upstream-szinkron)
- **Dátum:** 2026-09-05

## Mérce és módszer

READ-ONLY review. A `tools/round-gate.sh`-t az **orchestrátor futtatta külön
processzben**, csonkítatlan kimenettel (`--result-json /tmp/e16r06-gate.json`,
`gate_exit=0`, 19/19 zöld) — a reviewer nem futtatott sem gate-et, sem
`flutter analyze`-t, sem `flutter test`-et; minden lelet statikus elemzésből és
teljes forrásolvasásból származik.

Amit ténylegesen elolvastam/futtattam:

- a brief teljes egészében (§0.0 M1–M6, §4, §5 D1–D5, §6 A1–A10, §6.1, §7.1, §10)
  és `docs/adr/0508-…md` teljes egészében;
- `git diff e4965711^..692062a1` (implementációs commit), `git show e4965711`
  (pre-flight brief-revízió), `git diff --name-only origin/main...HEAD`;
- teljes forrásolvasás: `lib/app/routing/adaptive_shell_routes.dart`,
  `lib/app/routing/app_router.dart:195-260` és `:495-535`,
  `lib/app/routing/route_guards.dart`,
  `lib/features/onboarding/screens/onboarding_screen.dart:100-155`,
  `lib/features/practice_hub/screens/practice_area_hub_screen.dart`, mind a négy
  érintett tesztfájl, `test/app/navigation/adaptive_scaffold_test.dart:295-340`,
  `docs/release/full-app-verification.md`;
- mért ellenőrzések: `grep -rn "adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live" lib/`
  → **1 találat**; `walked.add` régi vs. új → **bájtra azonos kilenc osztály**;
  `router.go` az e2e-ben → 3 találat, mind a gerincen KÍVÜL (`:236/:258/:293`);
  az L3–L5 szakaszok `diff`-je (66 sor) → **IDENTIKUS**; `expect(` az e2e-ben
  24 → 22 (pontosan a híd két állítása); `skip:` a négy tesztfájlban → 0 találat;
  golden/fixture érintés → 0 fájl.

## Leletek

### MAJOR-1 — Az A2 mátrix „shell KI" cellái mérve NEM falszifikálják a D2 szerződést; a §7.1 pont 2. kötelező demonstrációja teljesítetlen maradt

**Lelet:** A §10.4 állítása, hogy a briefelt 2. mutáció (`entryLocationFor(...)`
→ fix `AppRoutes.today` az onboardingban) nem visz pirosra egyetlen cellát sem,
a kódból is igazolható — **a mechanizmus-magyarázat IGAZ**. Mindkét védőháló
ellenőrizve:

`lib/app/routing/app_router.dart:238`

```dart
onException: (_, _, router) => router.go(entryLocation),
```

`lib/app/routing/app_router.dart:506` + `:520-523`

```dart
      if (adaptiveShellEnabled)
        StatefulShellRoute.indexedStack(
…
                GoRoute(
                  path: AppRoutes.today,
                  builder: (_, _) => const TodayHubScreen(),
                ),
```

KI állapotban a `/today` **nincs regisztrálva**, a mutált `router.go('/today')`
`GoException`-t dob, amit az `onException` a router SAJÁT (nem mutált)
`entryLocation`-jére terel; ezt e körtől független teszt is pinneli
(`test/app/navigation/adaptive_scaffold_test.dart:320-334`).

A mátrix **nem vákuum**: a „shell BE" cellák bizonyítottan érzékenyek (mutált
`router.go(AppRoutes.live)` → `legacyRedirects['/live'] = '/practice/live'` →
settled URI `/practice/live` ≠ `/today` → PIROS; ezt a §10.4 kontroll-mutációja
mérte is). A hézag pontosan körülhatárolható: **a „flag-vak" implementáció (fix
`/today`, a flag figyelmen kívül hagyása) — a D1/D2 duplikátum-tilalom
megsértésének legvalószínűbb jövőbeli alakja — a teljes gate mellett is zöld
marad.** A brief §6.1 sora („`_completeFinish` fixen `AppRoutes.today`-t kap →
A2 »shell KI × Skip/finish« cellája") ezzel **mérve hamis**, és a §7.1 pont 2.
nem teljesült. A D1 szerződés egyetlen automatizált őre így az A1 **kézi
grepje** marad, nem egy teszt.

Enyhítő körülmény a rekord kedvéért: a nem-elkapható regresszió
felhasználó-láthatóan jóindulatú (az `onException` a helyes célra terel), tehát
ez **teszt-erő lelet, nem viselkedési defekt**, és az implementer maga jelentette
be, helyes mechanizmus-magyarázattal és érvényes kontroll-mutációval.

**Javítás (teszt-only, `lib/**` érintése nélkül, a már engedélyezett
`test/app/routing/shell_entry_location_test.dart`-ban):** egy izolált cella-pár,
amely a védőhálókat kiiktatja, és így KIZÁRÓLAG az onboarding saját döntését
méri — csupasz `GoRouter` (`/welcome` → `OnboardingScreen`, **és** `/today`
**és** `/live` egyaránt regisztrált placeholderrel), `redirect`/`onException`
NÉLKÜL, `appConfigProvider` override-dal mindkét flag-állásra; Skip után
`expect(router.state.uri.path, entryLocationFor(flag))`. Ebben a rigben a fix
`/today` literál a KI cellát, a fix `/live` a BE cellát viszi pirosra — a §7.1
pont 2. mutációja végre elvégezhető úgy, ahogy a brief kéri. A mai négy „valódi
routeres" cella maradjon meg mellette.

### MINOR-1 — Az A4/c negatív állításai duplikált angol literálokra mérnek

**Lelet:** `test/features/practice_hub/practice_area_hub_cta_test.dart:124-130`

```dart
      expect(find.text('Recommended for you'), findsNothing);
      expect(
        find.text(
          'Jump into a practice session picked for where you are right now.',
        ),
        findsNothing,
      );
```

A literálok ma egyeznek az ARB-vel (`lib/l10n/app_en.arb:2685-2686`), de
**negatív** állításról van szó: copy-változás után mindkét `findsNothing`
triviálisan zöld marad akkor is, ha a kártya renderelődik. A cella fő állítása
(`find.byKey(_ctaKey), findsNothing`, `:123`) robusztus, ezért nem blokkoló.

**Javítás:** `final l10n = lookupAppLocalizations(const Locale('en'));`
(precedens: `test/e2e/full_app_walkthrough_test.dart:81`), és
`find.text(l10n.practiceAreaHubRecommendedTitle)` / `…RecommendedMessage`.

### MINOR-2 — A verification-dokumentum két helyen önmagának mond ellent az új A3-verdikt mellett

**Lelet:** `docs/release/full-app-verification.md:8-10` (a kör által **nem**
frissített bevezető) továbbra is „**NEM javított** leletek"-et állít, és `:282`
a „## 4. Nyitott tételek" tábla Tétel-oszlopa változatlanul a régi negatív
mérést mondja ki, miközben a Kör-oszlop már a feloldást. Az A8 betűje teljesül,
de a dokumentum egésze olvasva ellentmondásos.

**Javítás:** a `:8-10` mondat kiegészítése egy „(L1/L2 azóta `E16-R06`-ban
feloldva, l. §2)" tagmondattal, és a `:282` Tétel-cellájának múlt időbe tétele.
A fájl a §4 engedélyezett listán van.

### MINOR-3 — Az A3 „páros" mérése csak a BE flag-álláson teljes

**Lelet:** `test/app/routing/shell_entry_location_test.dart:90-98` és `:111-121`
— mindkét first-win cella kizárólag az URI-t méri. A push-t egyedül
`test/app/routing/onboarding_first_win_test.dart:141-142` méri, és az csak a BE
konfigurációban fut. A brief A3 szövege szigorúan olvasva az A2 first-win
celláira is vonatkozik. Kockázat alacsony (a post-frame push flag-független).

**Javítás:** két sor a két first-win cellába: `expect(find.byType(LearnScreen), findsOneWidget);`
+ `expect(tester.widget<LearnScreen>(…).lesson.id, Lessons.firstWin.id);`.

### NOTE-1 — Import-alak: felesleges `features/` szegmens a testvér-feature barrelre

`lib/features/practice_hub/screens/practice_area_hub_screen.dart:7` —
`import '../../../features/practice/public.dart' show practiceCatalogProvider;`
funkcionálisan helyes, barrelen át megy (D3 teljesül, mély import NINCS), az
architecture-kapu zöld. Kozmetikai, javítást nem igényel.

### NOTE-2 — A `ref.read` / `mounted` kockázat mérve NINCS jelen

Mindkét befejező ág az `await`-lánc **ELŐTT** olvassa a flaget
(`onboarding_screen.dart:107-110` és `:131-134`), await utáni
`ref.read`/`context`-használat nincs. A `widget.onDone ?? …` /
`widget.onFirstWin ?? …` szemantika bájtra változatlan; a first-win post-frame
push sorrendje és gazdája érintetlen. `AsyncValue` nincs a diffben, tehát a
`.value` csapda nem releváns.

### NOTE-3 — Teszt-gyengítés-audit: tiszta

`skip:`, kikommentelt teszt, `reason` nélküli lazítás: **0 találat** a négy
tesztfájlban. `onboarding_first_win_test.dart` teszt-száma 1 → 1; az egyetlen
érdemi változás a settled URI `AppRoutes.practiceLive` → `AppRoutes.today`. A
régi viselkedést leíró komment („still calls `router.go(AppRoutes.live)`
literally") törölve, helyére az új szerződés került. Az e2e-ben `expect(` 24 → 22:
pontosan a `practiceRouteErrorTitle` megfordított állítása és a híd utáni
duplikált `PracticeSetupScreen` állítás.

## Acceptance-táblázat (A1–A10)

| Cella | Verdikt | Bizonyíték |
|---|---|---|
| **A1** — egy forrás | ✅ | `grep -rn "adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live" lib/` → **pontosan 1** (`adaptive_shell_routes.dart:29`). Hívók: `app_router.dart:233`, `onboarding_screen.dart:108` és `:132`. Az `AppRoutes` import el is tűnt az onboardingból. |
| **A2** — belépési 2×2 | ⚠️ **részleges (MAJOR-1)** | Mind a négy cella létezik (`shell_entry_location_test.dart:81/90/100/111`), valódi `StrumSightApp` + `routerProvider` fölött, settled `router.state.uri.path`-ra mér. **De** a két KI cella a §6.1 által előírt „flag-vak fix `/today`" mutációt nem kapja el. |
| **A3** — first-win push sértetlen | ✅ (MINOR-3 fenntartással) | `onboarding_first_win_test.dart:139-142`: settled `AppRoutes.today` **és** `learn.lesson.id == Lessons.firstWin.id`. A push kódja bájtra változatlan. |
| **A4** — CTA URI-mátrix | ✅ | `practice_area_hub_cta_test.dart:80-131` három cella: (a) `?id=builtin.quarterDownstrokes.v1`, (b) override `test.first.v1`, (c) üres → `findsNothing`. `if (catalog.isNotEmpty)` a `Card` fölött; `first` csak a nem-üres ágon. `ValueKey` megvan, barrelen át olvas. |
| **A5** — Setup a valódi űrlapot rendereli | ✅ | `full_app_walkthrough_test.dart:135-141` — az állítás **megfordítva**: `practiceRouteErrorTitle` `findsNothing`; `:143-152` `practiceSetupStart` tap → `PracticeSessionScreen`. |
| **A6** — nulla híd a gerincen | ✅ | `router.go` → `:236`, `:258`, `:293` (Library/Progress/Profile, L3/L4/L5); a gerincen **0**. A grep fájl-szintű → helper-be költöztetés kizárva. |
| **A7** — ugyanazok az állomások | ✅ | `walked.add` kilenc osztály, azonos sorrendben; `restartE2eApp` megvan (`:214`). |
| **A8** — verifikációs dokumentum | ✅ (MINOR-2 fenntartással) | §2 újraírva, L1/L2 megmaradt „Kör: `E16-R06` — feloldva" jelöléssel, **L3/L4/L5 bájtra azonos** (diffből mérve). |
| **A9** — nincs golden-elmozdulás | ✅ | `git diff --name-only origin/main...HEAD -- test/ui/goldens/goldens/ test/fixtures/ui/` → **0 fájl**. |
| **A10** — gate zöld | ✅ | Orchestrátor-oldali artefaktum-futás: `tools/round-gate.sh --result-json …` 19/19 zöld, `gate_exit=0`, csonkítatlan. |

**Scope-audit:** mind a 10 megváltozott útvonal rajta van a brief §4
`allowed_paths` listáján; listán kívüli fájl **nincs**, új fájl csak a két
engedélyezett teszt. `docs/adr/**`, `docs/LESSONS.md`, `HANDOFF.md`,
`docs/execution/**`, `tools/**`, `.github/**`, `test/support/e2e_harness.dart`,
`lib/l10n/**` érintetlen. Az `app_router.dart` diffje kizárólag a `:233`
kifejezés + komment (M1 tartva). H3-osztályú lelet nincs.

## VÉGSŐ DÖNTÉS: CHANGES REQUESTED

A szállított viselkedés helyes, a D1–D5 mind teljesül, a scope makulátlan,
teszt-gyengítés nincs, a dokumentum-állítások a diffből ellenőrizve igazak, és
az implementer a §7.1 kudarcát becsületesen jelentette. A blokkoló egyetlen
tétel a **MAJOR-1**. A javítás teszt-only, ~30 sor, a már engedélyezett
fájlban. A javító körbe felvéve: MINOR-1, MINOR-2, MINOR-3. A NOTE-ok javítást
nem igényelnek.

## Javító kör után — újra-ellenőrzés

- **Javító commit:** `c7aec8c5` (+ `434c62c5` upstream-merge, tartalmilag üres a körre nézve)
- **Reviewer:** Claude (Opus 5), független read-only újra-ellenőrzés (ADR 0055)
- **Dátum:** 2026-09-05

### Mérce (mit olvastam)

READ-ONLY, statikus. A `tools/round-gate.sh`-t / `flutter analyze`-t /
`flutter test`-et a reviewer **nem futtatta** (az orchestrátor ugyanabban a
munkamásolatban futtatta — párhuzamos Flutter-futás OOM).

- `git show c7aec8c5` teljes egészében (`--stat`: **4 fájl, mind `test/**` +
  `docs/**`, `lib/**` érintetlen**);
- `test/app/routing/shell_entry_location_test.dart` **teljes** (255 sor),
  `lib/features/onboarding/screens/onboarding_screen.dart` **teljes**,
  `lib/app/routing/adaptive_shell_routes.dart` **teljes**,
  `lib/app/routing/app_route.dart`,
  `test/features/practice_hub/practice_area_hub_cta_test.dart:1-131`,
  `lib/features/practice_hub/screens/practice_area_hub_screen.dart:45-80`,
  `lib/l10n/app_en.arb:2684-2686` és `:2524`;
- a brief `§7.1`, `§10.4`, az új `§10.6`;
- mért ellenőrzések: `git diff origin/main...HEAD -- docs/release/full-app-verification.md`
  (**4 hunk**: `:8-10` bevezető, §2 törzs, L1/L2 „Kör" sorai, §4 tábla 1/2/6 sora
  — a §3 partíció-táblák és az L3/L4/L5 szakaszok **egyik hunkban sem**);
  `cmp` az L3–L5 blokkra (66 sor) az `origin/main` verziójával → **azonos**;
  `grep -c testWidgets` → **6**; `skip:` a négy tesztfájlban → **0**;
  `git status --porcelain` → **üres**.

### Leletenkénti zárás

| Lelet | Állapot | Bizonyíték (file:line + idézet) |
|---|---|---|
| **MAJOR-1** — az A2 „shell KI" cellái nem falszifikálják a D2 szerződést | **ZÁRVA** | `test/app/routing/shell_entry_location_test.dart:139-254` új `'A2 — isolated onboarding-only rig (review MAJOR-1, falszifikáció)'` csoport. A rig **mindkét védőhálót eltávolítja**: `:188-204` csupasz `GoRouter(initialLocation: AppRoutes.welcome, routes: [...])` — **nincs `redirect` és nincs `onException`**, sem a routeren, sem a három `GoRoute`-on; `/today` (`:195-198`) **és** `/live` (`:199-202`) egyaránt regisztrált `SizedBox.shrink()` placeholderrel **minden flag-álláson**, tehát mutált cél sem dob `GoException`-t. A flag override eléri a képernyőt: `:171-185` `appConfigProvider.overrideWithValue(…)` a `ProviderContainer`-en, amit `:211` `UncontrolledProviderScope(container: container, child: MaterialApp.router(…))` a router-navigátor **fölé** húz. Az állítás a **settled** URI-ra megy: `:235` `pumpAndSettle()` → `:237` `expect(router.state.uri.path, entryLocationFor(true));`, illetve `:249-251` `entryLocationFor(false)`. |
| **MINOR-1** — nyers angol literálok a negatív állításokban | **ZÁRVA** | `practice_area_hub_cta_test.dart:118` `final l10n = lookupAppLocalizations(const Locale('en'));`, `:125-126` `expect(find.text(l10n.practiceAreaHubRecommendedTitle), findsNothing);` + `…RecommendedMessage`. A kulcsok azonosak a képernyő által renderelttel (`practice_area_hub_screen.dart:53`, `:58`). Új ARB-kulcs **nincs**. |
| **MINOR-2** — a verification-dokumentum önellentmondása | **ZÁRVA** | `docs/release/full-app-verification.md:9` `…tiltott zónája; L1/L2 azóta \`E16-R06\`-ban feloldva, l. §2)…`; `:283` `… mérhetően NEM **voltak** végigjárhatók …`. Az L3/L4/L5 alszakaszok **bájtra azonosak** az `origin/main` verziójával; a §3 partíció-táblákat egyetlen hunk sem érinti. |
| **MINOR-3** — az A3 „páros" csak a BE flag-álláson teljes | **ZÁRVA** | `shell_entry_location_test.dart:103-107` (BE) és `:131-135` (KI): `expect(find.byType(LearnScreen), findsOneWidget);` + `expect(tester.widget<LearnScreen>(…).lesson.id, Lessons.firstWin.id);` — belépési hely ÉS push mindkét flag-álláson. |

**A falszifikáció végigkövetve (a MAJOR-1 döntő kérdése).** A `Skip`
(`onboarding_screen.dart:218-222`) `requestMic` nélkül hívja a `_finish`-t, tehát
a permission-checkpoint nem kerül közbe. A rig `const OnboardingScreen()`-t épít
(`:193`) → `onDone == null` → a **default** ág fut, `GoRouter.of(context)` a
csupasz routert adja. A `router.go(entryLocation)` után semmi nem szólhat bele:
nincs `refreshListenable`, nincs `redirect`, nincs `onException`, a cél
regisztrált. Egy flag-vak `final entryLocation = AppRoutes.today;` mutációnál a
KI cella settled URI-ja `/today`, az elvárás `entryLocationFor(false)` = `/live`
(`adaptive_shell_routes.dart:29`) → **PIROS**. A rig vákuum-mentes is: `:222`
`expect(router.state.uri.path, AppRoutes.welcome);` a tap ELŐTT rögzíti a
kiindulást.

**A §10.6 mutációs kimenetek hitelessége.** A három futás számai a rigből
**levezethetők**: (1) fix `/today` → `+5 -1`, egyedül az izolált KI cella bukik
(a négy valódi routeres cellát az `onException` megvédi); (2) visszaállítás →
`+6` (a fájlban pontosan 6 `testWidgets` van — mérve); (3) fix `/live` **csak a
`_completeFinish`-ben** → `+4 -2`: izolált BE cella + valódi routeres „shell BE ×
Skip/finish"; a valódi „BE × first-win" zöld marad, mert a `_completeFirstWin`
ebben a futásban nem volt mutálva — épp ez különbözteti meg a §10.4
kontroll-mérésétől. Kézzel írt kimenet ezt a különbséget nem szokta eltalálni.

**Anti-gaming audit.** `git show --stat c7aec8c5` → `lib/**` **nulla sor**. A négy
eredeti „valódi routeres" cella (`:85-137`) megvan és **erősödött** (MINOR-3);
egyetlen assertion sem lazult; `skip:`, kikommentelt teszt, `reason`-nel lazított
állítás: **0**. Golden/fixture: 0 fájl. A merge-commit (`434c62c5`) diffje az
`origin/main`-hez képest 0 sor a két érintett doksin → tisztán upstream.

### Új leletek

**NOTE-4 (nem blokkoló) — az izolált rig a first-win ágra nem terjed ki.** Az új
csoport két cellája kizárólag a `Skip/finish` ágat méri (`:226`, `:240`) — pontosan
úgy, ahogy a review előírta. Következmény: egy flag-vak `_completeFirstWin`
(`onboarding_screen.dart:126-151`) KI állapotban továbbra sem vinne pirosra
cellát. A kockázat alacsony (a két ág ugyanazt a két sort futtatja, egymás
szomszédságában, és a D1-et az A1 grep + az izolált Skip-pár együtt őrzi).
Zárása két további cella lenne ugyanabban a rigben — **javasolt jövőbeli körre,
nem e kör visszatartására.**

**NOTE-5 (kozmetikai) — az izolált cellák állítása az `entryLocationFor`-ra
hivatkozik** (`:237`/`:251`), tehát magának a függvénynek a mutációját
tautologikusan zölden hagynák. Nem hézag: a négy valódi routeres cella
**literált** állít (`:92/:102/:118/:130`), és az `app_router.dart` ugyanezt a
forrást hívja, tehát ilyen mutáció ott bukna.

**Riverpod/Flutter higiénia — tiszta.** `UncontrolledProviderScope` megvan
(`:211`), `addTearDown` a `pumpWidget(SizedBox.shrink())` + `container.dispose()`
párral (`:205-208`). A csupasz `GoRouter` nincs `dispose()`-olva — a repóban
egyetlen teszt sem `dispose()`-ol routert, és leak-tracking nincs bekapcsolva →
nem lelet. `test/support/` duplikáció nincs (a rig a meglévő
`preferenceOverrides()`-t használja újra).

### VÉGSŐ DÖNTÉS: APPROVED

Mind a négy lelet érdemben zárva. A MAJOR-1 nem kozmetikai zárás: a rig valóban
mindkét védőhálót kiiktatja, a mutáció nem tud rejtve maradni, a cella nem tud
vákuumban zöldülni, és a jelentett három mutációs futás számai a rigből
levezethetők. Teszt-gyengítés nincs, `lib/**` nem változott a javító körben, a
scope makulátlan, az L3/L4/L5 szakaszok bájtra azonosak. A NOTE-4/NOTE-5
javítást nem igényel a merge-hez; a NOTE-4 érdemes egy jövőbeli kör backlogjára.

**Orchestrátor-oldali mérce:** `tools/round-gate.sh` a javított fán
(`--result-json`, csonkítatlan) **19/19 zöld, `gate_exit=0`**.
