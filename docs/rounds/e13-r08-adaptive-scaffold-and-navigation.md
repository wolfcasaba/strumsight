# E13-R08 — Adaptive scaffold és primary navigation

- **Státusz:** READY (pre-flight lemérve 2026-08-23, kód olvasva: `main @ fc15de44`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 8
- **Kör-azonosító:** `E13-R08`
- **Branch:** `sonnet-impl/e13-r08-adaptive-scaffold-and-navigation`
- **Előfeltétel:** `E13-R07` merge-elve (ikonográfia) + az R01 route-térképe
- **Brief szerzője:** Claude (Opus 5) · **§0.0 revízió:** Claude (Opus 5), 2026-08-23
- **ADR:** [`0275`](../adr/0275-five-area-shell-behind-a-flag.md) — **MÁR LÉTEZIK
  ÉS MERGE-ELVE VAN** (`a4fdfec2`). Ez a kör nem ír új ADR-t, lásd §0.0 D1.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/layouts/ss_adaptive_scaffold.dart",
  "lib/core/design_system/public.dart",
  "lib/app/routing/",
  "lib/app/home_shell.dart",
  "lib/app/config/feature_flags.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
  "docs/rounds/e13-r08-adaptive-scaffold-and-navigation.md",
]
gate_tests = [
  "test/app/navigation/adaptive_scaffold_test.dart",
  "test/app/navigation/legacy_route_redirect_test.dart",
  "test/app/navigation/tab_state_restoration_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör az alkalmazás EGYETLEN routing-hatóságát
(`lib/app/routing/app_router.dart`, ma 46 `AppRoutes` konstans és 45 regisztrált
`GoRoute`) és a globális `FeatureFlags` értékobjektumot írja át. Nem
adatvédelmi/hálózati kockázat: a `high` a **hatókör-kockázat** — egy elrontott
redirect vagy egy kihagyott flag-bővülési pont NEM egy képernyőt, hanem az
összes belépési pontot (és minden kívülről érkező deep linket) teszi
elérhetetlenné, miközben a fordítás és az analyze zöld marad. A router
`high_risk_path_fragments` listájából egyetlen töredék sem illeszkedik — a
`high` tudatos, nem automatikus besorolás.

## 0. Kör-jelzés és STOP-protokoll

**A kör-jelzés KÖTELEZŐ, jelzés nélkül a futásod bukott.** A munkád végén
pontosan egy lezáró jelzést írj:

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll (scope-ütközés).** Ha a munkához a §4 engedélyezett listáján
KÍVÜLI fájlt kellene módosítanod vagy létrehoznod: **ne tedd meg**. Írj
`stopped` jelzést, a `summary`-ben nevezd meg a fájlt és azt, mi kényszerítene
rá. A lista tágítása nem a te hatáskörödben van. Ez különösen érinti a
`lib/l10n/**`-t (lásd §0.0 D10) és a `docs/adr/**`-t.

**A munkádat commitold a branchre** (`sonnet-impl/e13-r08-adaptive-scaffold-and-navigation`).

**A §8 a terved — nincs külön task-lista.** Doc-commentben csak tesztben
bizonyított állítás szerepeljen (`const`, `immutable`, „nem indít mikrofont").

---

## 0.0 Pre-flight revízió (Claude, 2026-08-23) — MÉRT eltérések

Az előre megírt brief (2026-08-15, `93a6c19a`) mért állításai elavultak.
Az alábbi tizenhárom pont a **mai** `main @ fc15de44` mérése. Ahol a §2–§9
ennek ellentmondana, **ez a szakasz az erősebb**.

### D1 — Az ADR 0275 MÁR MEG VAN ÍRVA és MERGE-ELVE

```
$ ls docs/adr/0275*
docs/adr/0275-five-area-shell-behind-a-flag.md
$ git log --oneline -1 -- docs/adr/0275-five-area-shell-behind-a-flag.md
a4fdfec2 docs(ch13): E13-R07..R13 briefek + ADR 0275-0279
```

A pipeline „előre kiosztott ADR: 0275 — a Claude írja meg a pre-flightban"
sora **elavult**: az ADR öt döntése (flag mögött KI · legacy adapterek ·
egyetlen legacy link sem törik · aciklikus redirect-térkép · Stage alatt nincs
primary nav) már a fán van. **Ez a kör tehát nem ír ADR-t**, és nem oszt új
számot egy merge-elt döntés fölé (ADR 0087 §4). A `docs/adr/**` végig TILOS
zóna marad. A §0.0 alábbi pontjai **mérések**, amelyek az ADR 0275 döntéseit
gépileg ellenőrizhetővé teszik — nem új architekturális döntések.

### D2 — A `FeatureFlags` HAT helyen bővül, nem háromban

A §2 és a §8.2 „három bővülési pont (konstruktor, `forEnvironment`,
`toString()`) és az `==`" állítása **mérve hibás**. A mai fájl
(`lib/app/config/feature_flags.dart`, 437 sor) hat helyen sorolja fel
egyenként a flageket:

| # | Bővülési pont | Horgony (sor) | Az utolsó mai flag ott |
|---|---|---|---|
| 1 | `const FeatureFlags({…})` konstruktor-paraméter | 12 | 51 |
| 2 | `factory FeatureFlags.forEnvironment` | 68 | 122 |
| 3 | `final bool <flag>;` mező-deklaráció | — | 279 |
| 4 | `bool operator ==` | 291 | 339 |
| 5 | `int get hashCode` | 342 | 384 |
| 6 | `String toString()` | 393 | 436 |

```
$ grep -n "  const FeatureFlags\|  factory FeatureFlags.forEnvironment\|bool operator ==\|int get hashCode\|String toString()" lib/app/config/feature_flags.dart
12:  const FeatureFlags({
68:  factory FeatureFlags.forEnvironment(
291:  bool operator ==(Object other) =>
342:  int get hashCode {
393:  String toString() =>
```

A `hashCode` **nem** sima `Object.hash` — a mai alak egy `legacyHash` +
`additionalBits` szerkezet (`Object.hashAll(<Object?>[legacyHash,
...additionalBits])`, 386–390. sor), mert az `Object.hash` 20 argumentumnál
elakad. Az új flag az `additionalBits` listába megy.

**Kihagyott hely = néma hiba:** a `==`/`hashCode` kihagyása két különböző
flag-halmazt egyenlőnek mutat (a Riverpod így NEM építi újra a routert), a
`toString()` kihagyása a diagnosztikát hazudtatja meg. Ezért a §6 A1 cellája
**mind a hat pontot** méri, nem csak a default értéket.

**A flag neve kötött:** `adaptiveShellEnabled`. Defaultból `false`, a
`forEnvironment` **minden** környezetben `false`-t ad (production is,
non-prod is — a bekapcsolás user-döntés, lásd ADR 0275 §1), és **nincs**
`bool.fromEnvironment` override.

### D3 — Az `SsBreakpoints` MÁR LÉTEZIK — ne definiálj új literálokat

```
$ cat lib/core/design_system/foundations/ss_breakpoints.dart
abstract final class SsBreakpoints {
  static const double compactMax = 599;
  static const double mediumMax = 839;
  static const double expandedMin = 840;
  static const double wideMin = 1200;
}
```

Exportálva a `lib/core/design_system/public.dart`-ból. Az `SsAdaptiveScaffold`
resolvere **ezekből a tokenekből** számoljon; `600`/`840`/`1200` mágikus
literál a production kódban tilos (a review MAJOR-nak veszi). A négy mód:
`compact` · `medium` · `expanded` · `wide`.

### D4 — Architekturális határ: a design system NEM ismerhet feature-t

`test/core/architecture_dependency_test.dart` §`design system boundaries
(E13-R02)` (735. sor) két gépi őrt futtat:

1. **`lib/core/design_system/**` egyetlen fájlja sem tartalmazhat
   `features/`-t tartalmazó import URI-t.**
2. **`lib/` minden más production fájlja csak `design_system/public.dart`-on
   át érheti el a design systemet** — `lib/app/home_shell.dart` tehát
   `package:strumsight/core/design_system/public.dart`-ot (vagy a relatív
   `../core/design_system/public.dart`-ot) importáljon, **soha nem**
   `…/layouts/ss_adaptive_scaffold.dart`-ot közvetlenül.

Következmény: az `SsAdaptiveScaffold` **tiszta layout-primitív** — nem ismer
route-ot, `GoRouter`-t, feature-t, `AppLocalizations`-t. Mindent adatként kap
(destination-lista, kiválasztott index, callback, body, `showPrimaryNavigation`).
A bekötés a `lib/app/` oldalon él.

### D5 — Az A2 legacy halmaza: a Ch13 §7.5 TIZENKÉT route-ja

A `docs/ui/baseline/route-map.md` negyven sort listáz, az ADR 0275 kontextusa
és a Ch13 §7.5 viszont **tizenkettőt** nevez meg — az ADR 0275 §3 kötelezettsége
erre a tizenkettőre szól, tehát **az A2 mércéje ez a tizenkettő**. Mérve: mind a
tizenkettő **feltétel nélkül** regisztrált ma (egyik sincs flag mögött), tehát
mind tesztelhető flag-zsonglőrködés nélkül:

```
$ for r in live analyze learn library settings tuner metronome progress streak songs setlists chords; do
    grep -n "path: AppRoutes.$r," lib/app/routing/app_router.dart | head -1; done
216 / 218 / 222 / 226 / 230 / 235 / 237 / 246 / 244 / 249 / 251 / 255   (mind megvan)
```

A cél-útvonalak az R01 `route-map.md` „Chapter 13 target" oszlopából, kötötten:

| # | Legacy route | Cél (kötött) |
|---|---|---|
| 1 | `/live` | `/practice/live` |
| 2 | `/analyze` | `/practice/analyze` |
| 3 | `/learn` | `/practice/learn` |
| 4 | `/library` | `/profile/library` |
| 5 | `/settings` | `/profile/settings` |
| 6 | `/tuner` | `/practice/tuner` |
| 7 | `/metronome` | `/practice/metronome` |
| 8 | `/progress` | `/profile/progress` |
| 9 | `/streak` | `/profile/rewards` |
| 10 | `/setlists` | `/songs/setlists` |
| 11 | `/chords` | `/practice/chords` |
| — | `/songs` | **`/songs` — identitás, NEM a térkép eleme** |

**Két kötött feloldás:**

- Az `/analyze` sorát a route-map „`/practice/analyze` **vagy**
  `/profile/library`" alakban hagyta nyitva. **Kötött választás:
  `/practice/analyze`** (a Ch13 §7.5 is ezt sorolja elsőként).
- A `/songs` önmagára képződne. Az ADR 0275 §4 (és a §5.3) tiltja az
  önmagára mutató élt, ezért a `/songs` **nem kerül be a redirect-térképbe**:
  a flag bekapcsolásakor egyszerűen **ő maga lesz a Songs destination**.

### D6 — A redirect célja MUSZÁJ hogy regisztrált legyen, különben VÉGTELEN HUROK

Mért csapda: a router `onException: (_, _, router) => router.go(AppRoutes.live)`
(`app_router.dart:210`). Ha a flag BE van kapcsolva és `/live` →
`/practice/live`-ra irányít, DE `/practice/live` nincs regisztrálva, akkor:
`/practice/live` → exception → `go('/live')` → redirect → `/practice/live` → …
**Ez pontosan az A5 hibaosztálya, és a `flutter analyze` nem látja.**

Ezért a kör a flag BE állapotában regisztrálja az **öt destinationt** és a
**tizenegy cél-alútvonalat**, mind **legacy képernyő-adapterként** (ADR 0275 §2 —
meglévő widget, új UI NÉLKÜL):

| Destination | Adapter-képernyő (meglévő) | Alútvonalak |
|---|---|---|
| `/today` | `LiveScreen` (nincs Today képernyő, lásd D11) | — |
| `/practice` | `PracticeHubScreen` | `/practice/live`, `/practice/analyze`, `/practice/learn`, `/practice/tuner`, `/practice/metronome`, `/practice/chords` |
| `/songs` | `SongListScreen` | `/songs/setlists` |
| `/coach` | `TutorHomeScreen` | — |
| `/profile` | `SettingsScreen` | `/profile/library`, `/profile/settings`, `/profile/progress`, `/profile/rewards` |

**Útvonal-ütközés (mérve):** `/practice` és `/songs` MA IS regisztrált
(`/practice` a `practiceEngineV2Enabled` mögött, `/songs` feltétel nélkül).
A `go_router` a duplikált path-ra **nem hibázik**, hanem az elsőt választja —
néma hiba. Ezért: **a flag BE állapotában minden path pontosan egyszer
regisztrált**; a régi `/practice` és `/songs` regisztráció ilyenkor kimarad
(a destination veszi át). Ezt az A1 cellája méri.

**A `/practice/setup|session|result` és a `/song-trainer/**` NEM része a
térképnek** — más path-ok, nincs ütközés, maradnak ahol vannak.

### D7 — Az A5 aciklikusság mércéje: a képhalmaz és az értelmezési tartomány DISZJUNKT

Az „aciklikus" önmagában gyenge mérce (egy `A→B→C` lánc aciklikus, de a
`redirectLimit`-et fogyasztja és nehezen auditálható). A kötött, erősebb
szerződés a `lib/app/routing/` oldalon egy `Map<String, String>`
(`legacyRedirects`) fölött:

1. **egyetlen kulcs sem képződik önmagára** — `k != v` minden élre;
2. **`values` ∩ `keys` = ∅** — a cél soha nem forrás, tehát a térkép
   **egylépéses**, és ebből a hurokmentesség következik (nem csak sejthető);
3. **minden érték regisztrált útvonal**, ha a flag BE (a D6 csapda ellen);
4. **a kulcshalmaz pontosan a D5 tizenegy legacy route-ja** — kipinnelt,
   rendezett lista, hogy a néma bővülés/szűkülés is piros legyen.

### D8 — Deep-link megőrzés: a query és a fragment MARAD

A D5 tizenegy legacy route egyikének sincs path-paramétere, tehát a
„paraméter-megőrzés" **mérhető alakja**: a redirect **változatlanul viszi
tovább a query stringet és a fragmentet**. Kötött cella (A2):

```
/library?tab=sessions&sort=recent#top   →   /profile/library?tab=sessions&sort=recent#top
```

A redirect a `GoRouterState.uri`-ból építkezzen (`uri.replace(path: target)`),
**ne** puszta string-konstansra ugorjon — az utóbbi némán eldobná a query-t, és
pontosan ezt a hibás implementációt kell az A2 cellájának pirosra váltania.

### D9 — Tab-állapot: `StatefulShellRoute.indexedStack` (go_router 17.3.0)

```
$ python3 -c "…pubspec.lock…"   → go_router version: 17.3.0
```

A verzió támogatja a `StatefulShellRoute.indexedStack`-et — **ez a kötött API**
az A3-hoz (branchenként külön `Navigator`, a stack tabváltáskor megmarad).
A mai `ShellRoute` ezt NEM tudja (a `HomeShell` doc-commentje mérve ki is
mondja: „switching tabs disposes the previous screen"). A tabváltás
`navigationShell.goBranch(index)`-szel történjen, **ne** `context.go(...)`-gal —
az utóbbi eldobná a branch-stacket, és pontosan ez az A3 hibás implementációja.

**A flag KI ágán a mai `ShellRoute` és a mai `HomeShell` viselkedés
VÁLTOZATLAN marad** (A7).

### D10 — `lib/l10n/**` a listán KÍVÜL van → nincs új ARB kulcs

A mérce (`.github/actions/flutter-gates/action.yml:32`) a
`tool/ci/check_l10n_parity.dart` — en/hu kulcs-paritást ellenőriz. Új kulcs
tehát nem bukna gépileg, DE a `lib/l10n/**` nincs az engedélyezett listán, és
a lista tágítása nem az orchestrátor hatásköre (ADR 0087 §2). **Az öt
destination címkéje ezért MEGLÉVŐ `AppLocalizations` kulcsokat használ**
(mérve, mind létezik en+hu oldalon):

| Destination | Kötött ARB kulcs | en érték |
|---|---|---|
| Today | `todayPlanTitle` | `Today` |
| Practice | `practiceHubTitle` | `Practice hub` |
| Songs | `songLibraryTitle` | `Song library` |
| Coach | `aiTutorHomeTitle` | `AI Tutor` |
| Profile | `tutorProfileTitle` | `Tutor profile` |

**Hardcode-olt felirat tilos** (a projekt állandó szabálya). A címke SZÖVEGE
nem acceptance-kritérium — az a mérce, hogy minden destination-felirat
`AppLocalizations`-on át jön. A nem tökéletes szóválasztás tudatos és
ideiglenes: a flag defaultból KI, tehát felhasználó nem látja. Írj a bekötés
mellé egy `// TODO(E13-R16): dedicated nav ARB keys once l10n is in scope`
kommentet.

### D11 — Nincs Today/Coach/Profile képernyő — az adapter meglévőt mutat

```
$ ls -d lib/features/today lib/features/coach lib/features/profile
ls: cannot access … : No such file or directory
```

Az ADR 0275 §2 kifejezetten ezt írja elő: „az öt destination első körben
legacy képernyő-adaptereket mutat". **Új képernyőt írni tilos** (a
`lib/features/**` amúgy is tiltott zóna). A D6 táblázat adapter-oszlopa kötött.

### D12 — Minden útvonal `AppRoutes` konstans (meglévő gépi őr)

`test/tooling/route_literal_guard_test.dart` tiltja a route-string literált a
`lib/` alatt (`.go('/…')`, `.push('/…')`, …), az ADR 0059 §1 pedig azt is,
hogy path-literál az `app_route.dart`-on kívül szerepeljen. **Az öt
destination, a tizenegy cél-alútvonal és a Stage-halmaz minden eleme
`AppRoutes` `static const`** legyen.

### D13 — A Stage-halmaz mérhető definíciója (ma egyetlen stage route sincs)

Mérve: a `newLiveStageEnabled` flag létezik, de **semmi nem használja**
(`grep -rn "newLiveStage" lib/` csak a `feature_flags.dart` hat sorát adja), és
`SsStageScaffold` sincs — az a **Kör 9** tárgya. A Ch13 §7.4 az „aktív audio-,
practice-, song- vagy vision-session" alatt tiltja a primary navigationt.

**Kötött, szűk halmaz** — a ma regisztrált session-felületek:

```
AppRoutes.practiceSession       '/practice/session'
AppRoutes.songTrainerSession    '/song-trainer/session/:songId'
AppRoutes.visionSession         '/vision/session'
```

A `/practice/live`, `/tuner`, `/metronome` **NEM** stage ebben a körben: az
onboarding utáni belépési pont a `/live`, ami a flag BE ágán `/practice/live`-ra
megy — ha ez elrejtené a navigationt, a felhasználó navigáció nélküli
képernyőn indulna. A Live/Tuner/Metronome Stage-esítése a Kör 9 dolga.

**Anti-vakuum (L403).** A három session-route MA a shellen KÍVÜL van
regisztrálva, tehát „nincs rajta bottom nav" trivativan igaz lenne — egy ilyen
cella semmit sem mér. Ezért az A4 mércéje **két rétegű**:

1. **tiszta predikátum** — `bool isStageRoute(String location)` a
   `lib/app/routing/`-ban, a kipinnelt halmaz fölött (a `:songId`
   path-paraméteres alakot is fel kell ismernie egy konkrét URL-en, pl.
   `/song-trainer/session/abc`);
2. **a shell widget** — az `SsAdaptiveScaffold`-ot / az új shellt **közvetlenül**
   egy stage-location-nel felpumpálva NINCS `NavigationBar` és NINCS
   `NavigationRail` a fában; egy nem-stage locationnel PONTOSAN EGY van.

### D14 — Javító kör (2026-08-23, review MAJOR-1): erőforrás-birtokló képernyő NEM mehet shell-branchbe

**Mért hiba** (`docs/reviews/e13-r08-review.md` §5–6, reviewer-próba):
a `StatefulShellRoute.indexedStack` — helyesen, az A3 miatt — életben tartja a
meglátogatott branchek navigátorát. A `LiveScreen` viszont erőforrást birtokol
(`live_screen.dart:58–62` wakelock `enable()`, `:165` `ref.watch(liveFrameProvider)`
= `StreamProvider.autoDispose`, `:90–108` `dispose()` → `disable()`), ezért
tabváltás után **nem szabadul fel**:

```
PROBE offstage LiveScreen instances after tab switch: 2
PROBE wakelock.isHeld after tab switch: true (enableCalls=2, disableCalls=0)
```

A legacy referencia ugyanazzal a próbával ZÖLD (`/live` → `/analyze` után
`findsNothing`, `isHeld == false`) — az invariáns valós, a `home_shell.dart`
doc-commentje ki is mondja. A Ch13 §7.4 előírása: „mikrofon/kamera ownership
route lifecycle-hoz kötött".

**A javítás nem lehet a `LiveScreen` módosítása** — a `lib/features/**` tiltott
zóna. A kötött szerződés ezért szerkezeti:

1. **`/today` adaptere erőforrás-mentes képernyő:** `ProgressScreen`
   (mérve: sem wakelock, sem stream-provider, sem engine). Ez szünteti meg a
   **kettőzést** (két `LiveScreen` két branchben).
2. **`/practice/live` kikerül a shell-branchből**, és a session-route-okhoz
   hasonlóan **top-level** `GoRoute` lesz — így a mai mount/dispose szemantika
   érvényben marad, a mikrofon és a wakelock elszabadul.
3. **`AppRoutes.practiceLive` bekerül az `isStageRoute` halmazába** (a D13
   halmaza így négyelemű). Ez a Ch13 §7.4-gyel egyező: az aktív audio-session
   Stage, tehát nincs rajta primary navigation. **A D13 korábbi indoklása —
   „a belépési pont ide esne, a felhasználó nav nélkül ragadna" — a 4. ponttal
   megszűnik.**
4. **A flag BE ágán a belépési pont `/today`:** az `initialLocation`
   `adaptiveShellEnabled` esetén `AppRoutes.today`, és az `onboardingRedirect`
   kapjon **opcionális, alapértelmezett** `home` paramétert
   (`String home = AppRoutes.live`), amit a router a flag szerint ad át. Az
   opcionális default miatt a **módosítatlan** `test/app/routing/route_guards_test.dart`
   hét hívása változatlanul zöld marad (mérve: mind a két kötelező paramétert
   adja meg csak).
5. **`/live` → `/practice/live` redirect VÁLTOZATLAN** (D5). Aki régi Live
   deep linket követ, a Live Stage-en köt ki, navigáció nélkül — ez a Ch13
   §7.4 szerinti helyes viselkedés. A Stage-ből kivezető transport (pause /
   finish / back-confirmation) **a Kör 9 `SsStageScaffold`-jának a dolga**,
   nem ezé a köré; a flag defaultból KI, tehát ez nem éles hiány.

**Új kötelező cella (A8), a `test/app/navigation/`-ben.** A reviewer
próbájának két piros cellája emelendő át, a legacy referenciával EGYÜTT:

| Cella | Elvárt |
|---|---|
| legacy referencia (flag KI) | `/live` → `/analyze` után `LiveScreen` `findsNothing`, `wakelock.isHeld == false` |
| flag BE, `/practice/live` → tabváltás | offstage `LiveScreen` példány **0**, `wakelock.isHeld == false` |
| flag BE, teljes shell-bejárás | a `LiveScreen` egyetlen branchben SEM marad mountolva (`skipOffstage: false`) |

A `FakeScreenWakelock` (`test/support/fake_audio.dart:151`) `isHeld` /
`enableCalls` / `disableCalls` mezői adják a mércét; a
`fakeAudioOverrides(wakelock: …)` átadja.

### D15 — Javító kör (review MINOR-1): a shell nem kerülheti meg más feature rollout-flagjét

A `StatefulShellRoute` egésze csak az `adaptiveShellEnabled`-tól függ, ezért a
flag bekapcsolása ma elérhetővé teszi a `PracticeHubScreen`-t
`practiceEngineV2Enabled == false` mellett is, és a `TutorHomeScreen`-t
`aiTutorEnabled == false` mellett is (bizonyíték: a
`tab_state_restoration_test.dart` flag-halmaza csak `adaptiveShellEnabled`-et
állít, és mégis `/practice`-re navigál). Egy **navigációs** flag nem billenthet
át két **termék-rollout** kaput.

**Kötött javítás:** a `practiceHub` branch-route kapjon `if (practiceEnabled)`,
a `coachHome` branch-route `if (aiTutorEnabled)` őrt. A destination maga
maradhat a nav-sávban (a branch üres-route esete kerülendő — ha a route kiesik,
a destination is essen ki, vagy mutasson erőforrás-mentes helyettesítőt; a
legszűkebb, teszttel lefedett változatot válaszd). A hozzá tartozó cella:
`adaptiveShellEnabled: true` + `practiceEngineV2Enabled: false` mellett a
`/practice` **nem** ad `PracticeHubScreen`-t.

---

## 1. Cél

A Today–Practice–Songs–Coach–Profile célarchitektúra bevezetése **flag mögött**,
compact bottom navigationnel és medium/expanded raillel (SDD Ch13 Kör 8).

## 2. Jelenlegi állapot — mért tények (2026-08-23, `fc15de44`)

- `lib/app/routing/` három fájl: `app_route.dart` (46 konstans),
  `app_router.dart` (550 sor, 45 `GoRoute`), `route_guards.dart` (tiszta
  függvények: `onboardingRedirect`, `mayLeaveEditor`).
- A mai shell egy `ShellRoute` az `AppRoutes.shellTabs` öt legacy tabja fölött
  (`live, analyze, learn, library, settings`); a `HomeShell` tabváltáskor
  **eldobja** az előző képernyőt.
- `go_router` **17.3.0** → `StatefulShellRoute.indexedStack` elérhető (D9).
- `FeatureFlags`: **hat** bővülési pont (D2), 57 teszt- és 3 lib-hívóhely;
  a hívóhelyek opcionális `= false` defaulttal nem törnek el.
- `SsBreakpoints` már létezik és exportált (D3); `layouts/` könyvtár **nincs**.
- `test/app/navigation/` **nem létezik** — a kör hozza létre.
- A design system R02–R07 rétegei készen állnak.

## 3. Scope

**Benne van:** `SsAdaptiveScaffold` layout-resolver (compact / medium /
expanded / wide) · az öt cél-destination **flag mögött**, legacy
képernyő-adapterekkel (D6) · NavigationRail medium/expanded módban · a
tizenegy legacy route **redirect-térképe deep-link megőrzéssel** (D5, D8) ·
billentyű- és fókusz-viselkedés expanded módban · a Stage-halmazon a primary
navigation elrejtése (D13).

**NINCS benne (tilos):** a legacy képernyők tartalmi átírása (Kör 16–35) · a
flag **bekapcsolása** alapértelmezetten (user-döntés) · új képernyő (D11) ·
új ARB kulcs (D10) · `SsStageScaffold` (Kör 9) · `lib/features/**` ·
`lib/core/theme/**` · `lib/l10n/**` · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/design_system/layouts/ss_adaptive_scaffold.dart` | **ÚJ** — a breakpoint-resolver (tiszta primitív, D4) |
| `lib/core/design_system/public.dart` | az export bővítése |
| `lib/app/routing/` | az öt destination, a cél-alútvonalak, a redirect-térkép, `isStageRoute` |
| `lib/app/home_shell.dart` | a shell bekötése |
| `lib/app/config/feature_flags.dart` | **egyetlen** új flag (`adaptiveShellEnabled`), defaultból KI, mind a HAT ponton (D2) |
| `test/app/navigation/adaptive_scaffold_test.dart` | **ÚJ** — A1, A4, A6 |
| `test/app/navigation/legacy_route_redirect_test.dart` | **ÚJ** — A2, A5 |
| `test/app/navigation/tab_state_restoration_test.dart` | **ÚJ** — A3 |
| `docs/rounds/e13-r08-…md` | a §10 handoff |

**Tilos zóna (minden más, kiemelten):** `lib/features/**` · `lib/core/theme/**` ·
`lib/l10n/**` · `test/app/routing/**` (a meglévő cellák A7-mércék, NEM
igazíthatók a kódhoz) · `test/core/architecture_dependency_test.dart` ·
`test/tooling/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

> Ha a `test/app/routing/app_router_test.dart` vagy a
> `test/core/architecture_dependency_test.dart` **pirosra vált**, az a kódod
> hibája (A7 / D4), nem a tesztté. Javítsd a kódot, vagy `stopped`.

## 5. Kötött architekturális döntések (ADR 0275)

### 5.1 Az új shell FLAG mögött, alapértelmezetten KIKAPCSOLVA

A flag neve `adaptiveShellEnabled`, mind a hat bővülési ponton (D2), a
`forEnvironment` minden környezetben `false`-t ad, dart-define override nincs.

**NEM elfogadható gyengítés:** az új shell alapértelmezett bekapcsolása „hogy
látszódjon a munka". Az 51 képernyő navigációját kockáztatná egyetlen körben.

### 5.2 EGYETLEN legacy link sem törhet el

A D5 tizenegy route-ja redirectel, a D8 szerint query- és fragment-megőrzéssel;
a `/songs` identitás. Ez acceptance-cella (A2), nem törekvés.

**NEM elfogadható gyengítés:** „ez a route úgysem használt". A megosztott és a
könyvjelzőzött linkek kívül esnek a kódon — nem mérhető, hogy használt-e.

### 5.3 Nincs route-hurok

A D7 négy szerződése gépi cella (A5), nem szemrevételezés. A D6 csapdája
(nem regisztrált cél → `onException` → `/live` → oda-vissza) ugyanide tartozik.

### 5.4 A kiválasztott tab állapota megmarad

`StatefulShellRoute.indexedStack` + `goBranch` (D9).

### 5.5 Stage route alatt NINCS primary navigation

A D13 kipinnelt halmaza, két rétegű mércével (predikátum + shell-widget).

### 5.6 A legacy képernyők ADAPTERREL kapcsolódnak

A D6 táblázat adapter-oszlopa kötött. Új képernyő tilos (D11).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az öt célterület + a tizenegy cél-alútvonal elérhető a flag BE állapotában, minden path pontosan egyszer regisztrált; a flag defaultból **KI**, és mind a HAT bővülési pont hordozza | `adaptive_scaffold_test.dart` |
| A2 | A D5 tizenegy legacy route-ja redirectel, a query + fragment megmarad (D8) | `legacy_route_redirect_test.dart` |
| A3 | A kiválasztott tab stackje megmarad tabváltás és visszatérés után | `tab_state_restoration_test.dart` |
| A4 | A D13 Stage-halmazán nincs primary navigation — predikátum ÉS shell-widget szinten | `adaptive_scaffold_test.dart` |
| A5 | A redirect-térkép teljesíti a D7 négy szerződését | `legacy_route_redirect_test.dart` |
| A6 | Minden breakpointon a helyes navigációs forma jelenik meg (§6.2 hat cellája) | `adaptive_scaffold_test.dart` |
| A7 | A flag KI állapotában a mai navigáció változatlan | a teljes suite zöld, kiemelten a MÓDOSÍTATLAN `test/app/routing/*` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| # | Hibás implementáció | PIROSRA vált | Az őr fajtája |
|---|---|---|---|
| 1 | A flag defaultból BE | **A1** + A7 | unit-cella a `FeatureFlags()` defaultján |
| 2 | Az új flag kimarad a `==`/`hashCode`-ból | **A1** | unit: két, csak ebben a flagben eltérő példány `==`/`hashCode` NEM egyezhet |
| 3 | Az új flag kimarad a `toString()`-ből | **A1** | unit: `toString()` tartalmazza a `adaptiveShellEnabled:` darabot |
| 4 | Kimarad egy legacy redirect | **A2** | unit: a kipinnelt 11-es kulcshalmaz + útvonalankénti navigációs cella |
| 5 | A redirect string-konstansra ugrik (query eldobva) | **A2** | widget/router: `/library?tab=sessions&sort=recent#top` → a cél URI-nak azonos query+fragmentje van |
| 6 | Egy redirect célja nincs regisztrálva (D6 hurok) | **A5** + A2 | router: a célra navigálva a várt adapter-képernyő jelenik meg, NEM a `/live` |
| 7 | `A → B → A` vagy `A → A` él | **A5** | unit: `k != v` ÉS `values ∩ keys == ∅` |
| 8 | Tabváltáskor a stack elvész (`context.go` a `goBranch` helyett) | **A3** | widget: push alútvonalra → tabváltás → vissza → még mindig az alútvonalon |
| 9 | Stage-en látszik a bottom nav | **A4** | predikátum-unit + shell-widget: `NavigationBar`/`NavigationRail` `findsNothing` |
| 10 | A resolver mágikus `600`-at használ a token helyett | **A6** | a §6.2 cellái a `SsBreakpoints` tokenekből számolt szélességeken futnak |
| 11 | Duplikált path-regisztráció (`/practice`, `/songs`) | **A1** | a várt adapter-képernyő típusa a flag BE ágán |
| 12 | `SsAdaptiveScaffold` feature-t importál | build-piros | `test/core/architecture_dependency_test.dart` (meglévő, D4) |
| 13 | Route-string literál a `lib/`-ben | build-piros | `test/tooling/route_literal_guard_test.dart` (meglévő, D12) |

### 6.2 A breakpoint kötelező cellái (három küszöb → hat cella)

A küszöbök a `SsBreakpoints` tokenekből, `python3`-mal kiszámolva:

```
$ python3 -c "
compact_max, medium_max, expanded_min, wide_min = 599, 839, 840, 1200
cells = [(compact_max,'compact'), (compact_max+1,'medium'),
         (medium_max,'medium'),   (expanded_min,'expanded'),
         (wide_min-1,'expanded'), (wide_min,'wide')]
for w,m in cells: print(f'{w} dp -> {m}')
assert compact_max+1 == 600 and expanded_min == medium_max+1"
599 dp -> compact
600 dp -> medium
839 dp -> medium
840 dp -> expanded
1199 dp -> expanded
1200 dp -> wide
```

| Cella | Bemenet (dp) | Elvárt mód | Elvárt navigációs forma |
|---|---:|---|---|
| küszöb alatt | **599** | `compact` | `NavigationBar` (bottom), rail NINCS |
| küszöbön | **600** | `medium` | `NavigationRail`, bottom bar NINCS |
| küszöb alatt | **839** | `medium` | `NavigationRail` |
| küszöbön | **840** | `expanded` | `NavigationRail` kiterjesztett címkékkel |
| küszöb alatt | **1199** | `expanded` | `NavigationRail` kiterjesztett címkékkel |
| küszöbön | **1200** | `wide` | `NavigationRail` (a wide extra tartalom-szélesség szabálya a Kör 10+ dolga) |

A `599 → compact` / `600 → medium` páros a kötelező „alatta / rajta" hármas
harmadik tagja a `840` (fölötte, más módra vált).

### 6.3 Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva)

Két próbát futtass, mindkettőt a §10-be írva (parancs + a piros cella neve +
visszaállítás):

1. **A2:** vedd ki a `/setlists` bejegyzést a `legacyRedirects` térképből →
   az A2 cellájának PIROSNAK kell lennie → állítsd vissza.
2. **A4 (anti-vakuum, L403):** a shell `showPrimaryNavigation` döntését
   fordítsd meg (mindig mutasson navigationt) → az A4 **shell-widget**
   cellájának PIROSNAK kell lennie → állítsd vissza. Ha csak a predikátum-cella
   pirosodik, a widget-cella vakuum — javítsd a cellát.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

A gate `architecture` lépése futtatja a D4 és D12 meglévő őreit is. A teljes
suite (A7) a CI-ben fut.

## 8. Implementációs sorrend

1. **`ss_adaptive_scaffold.dart`** — a négy módú resolver a `SsBreakpoints`
   tokenekből (D3), tiszta primitív feature-import nélkül (D4), a
   `showPrimaryNavigation` kapcsolóval. A §6.2 hat cellája.
2. **`feature_flags.dart`** — `adaptiveShellEnabled`, mind a **HAT** bővülési
   ponton (D2), defaultból KI, `forEnvironment`-ben mindenhol `false`.
3. **`app_route.dart`** — az öt destination, a tizenegy cél-alútvonal és a
   Stage-halmaz `static const` konstansai (D12).
4. **`app_router.dart` / `lib/app/routing/`** — a flag BE ágán
   `StatefulShellRoute.indexedStack` az öt branchcsel (D9), az adapterek a D6
   táblázat szerint, a duplikált regisztráció kizárásával; a flag KI ágán a mai
   `ShellRoute` VÁLTOZATLAN (A7).
5. **`legacyRedirects` + a redirect-logika** — a D5 tizenegy éle, a D8
   query/fragment-megőrzésével (`uri.replace(path: …)`), a D7 négy szerződésével.
6. **`isStageRoute` + a shell bekötése** (D13) — a `home_shell.dart` a
   `public.dart`-on át importál (D4), a címkék a D10 kulcsaiból.
7. **Tab-állapot megőrzés** (`goBranch`) + a `tab_state_restoration_test.dart`.
8. A §6.3 **két** valódi-sértés próbája, a §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A flag bekapcsolásának kísértése.** Az új shell látványos, és 51 képernyő
  navigációját viszi magával (A1).
- **A nem regisztrált redirect-cél végtelen hurka** (D6) — a `flutter analyze`
  nem látja, csak a router-cella.
- **A query-eldobó redirect** (D8): a törött deep-link csak a felhasználónál
  derül ki.
- **A flagek HAT helyes bővülése** (D2). Egy kihagyott hely némán régi értéket
  ad, a `==`/`hashCode` kihagyása pedig meg is akadályozza a router újraépítését.
- **A `context.go` a `goBranch` helyett** (D9): a tab-stack némán elvész.
- **Vakuum-cella a Stage-mércén** (D13, L403): a session route-ok ma a shellen
  kívül vannak, ezért a naiv cella semmit sem mér.

## 9.1 Visszakeresett előzmények (ADR 0312, kötelező)

```
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "adaptív scaffold, primary navigation, go_router shell, feature flag mögötti navigáció"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "redirect loop, deep-link paraméter megőrzés, tab stack state restoration widget teszt"
node tools/knowledge-rag.mjs --top 5 "adaptive scaffold navigation rail app_router.dart home_shell.dart feature flag"
```

| Találat | Miért releváns | Hol épült be |
|---|---|---|
| [`adr/0275`](../adr/0275-five-area-shell-behind-a-flag.md) (`bm25#1 emb#1`) | a kör öt kötött döntése — **már merge-elve** | D1, §5 |
| [`adr/0059`](../adr/0059-central-route-catalogue-and-validated-navigation.md) (`bm25#14 emb#4`) | egy katalógus (`AppRoutes`), tiszta+**idempotens** guardok zárják ki a redirect-loopot | D7, D12 |
| [`adr/0078`](../adr/0078-practice-feature-surface-and-routing.md) (`bm25#6 emb#9`) | a flag mögötti route-regisztráció bevett mintája | D6 |
| `lessons/L409` (E08-R30, `emb#2`) | egy „route-élesítő" brief hallgatólagosan feltételezi, hogy a képernyők adathoz kötöttek — **mérd a példányosítást, ne a screen létezését** | D6 adapter-tábla, D11 |
| `lessons/L403` (E08-R23, `bm25#11 emb#4`) | a valódi-sértés próba a rossz szinten mérve átenged — **anti-vakuum** | D13, §6.3/2 |
| `lessons/L366` (E08-R12, `emb#1`) | rétegenként eltérő architektúra-határ; a design system saját őre | D4 |
| `lessons/L22` (E02-R13, `emb#3`) | a UI-kör hibái a **cellák KÖZÖTT** élnek (kombinált forrás, többszöri belépés) | §6.1 13 sora |

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5, `medium` effort).

### Amit építettem

- **`lib/core/design_system/layouts/ss_adaptive_scaffold.dart`** (ÚJ) — az
  `SsAdaptiveLayoutMode` enum (compact/medium/expanded/wide),
  `SsAdaptiveDestination` (data-only), és az `SsAdaptiveScaffold` widget. A
  `modeForWidth(double)` static resolver kizárólag `SsBreakpoints`
  tokenekből számol (nincs `600`/`840`/`1200` literál). Compact →
  `NavigationBar`; medium → nem-extended `NavigationRail`
  (`labelType: selected`); expanded/wide → extended `NavigationRail`
  (`labelType: none`, `extended: true`). `showPrimaryNavigation: false` →
  puszta `Scaffold(body: body)`, se bar, se rail. Nem importál
  route/feature/l10n típust (D4). Exportálva a `public.dart`-ból.
- **`lib/app/config/feature_flags.dart`** — `adaptiveShellEnabled` mind a
  HAT bővülési ponton (D2): konstruktor-paraméter (`= false`),
  `forEnvironment` (mindig `false`, nincs dart-define), mező, `==`,
  `hashCode` (az `additionalBits` listába), `toString()`.
- **`lib/app/routing/app_route.dart`** — három új destination-konstans
  (`today`, `coachHome`, `profileHome`; a `practiceHub`/`songs` meglévő
  konstansokat újrahasznosítja a Practice/Songs destination), tizenegy új
  cél-alútvonal konstans (D5/D6 tábla szerint), és az
  `adaptiveShellDestinations` lista.
- **`lib/app/routing/adaptive_shell_routes.dart`** (ÚJ) — a `legacyRedirects`
  `Map<String,String>` (D5, a D7 négy szerződésével — `k != v`, `values ∩
  keys = ∅`, a kulcshalmaz pontosan a pinnelt 11), és az `isStageRoute(String)`
  tiszta predikátum a D13 kipinnelt halmazán (a Song Trainer session
  path-paramétert a `songTrainerSession` konstansból származtatott prefixből
  ismeri fel, nem duplikált stringgel).
- **`lib/app/routing/app_router.dart`** — a redirect callback előbb az
  onboarding-redirectet nézi, utána (csak ha `adaptiveShellEnabled`) a
  `legacyRedirects`-et, `state.uri.replace(path: target)`-tel (D8, megőrzi a
  query-t és a fragmentet). A flag BE ágán egy
  `StatefulShellRoute.indexedStack` öt branch-csel (D6 tábla szerinti
  adapter-képernyők), a `legacyRedirects.values` mindegyike regisztrált cél
  (D6 hurok-csapda ellen). A legacy `/practice` és `/songs` regisztráció
  `!adaptiveShellEnabled` mögé kerül, hogy ne legyen duplikált path (D6). A
  duplikáció-kizárás megbízhatóságát **szándékosan** nem a deklarációs
  sorrendre bíztam: az új `StatefulShellRoute`-ot a `practiceEnabled` és a
  `songs` feltételes blokkok UTÁN helyeztem el a `routes` listában, hogy ha
  valaki a jövőben elfelejtené a `!adaptiveShellEnabled` őrt, az elsőként
  regisztrált (legacy, shell nélküli) route győzzön a go_router
  first-match szemantikájával — ez tette megfigyelhetővé a §6.3/1 próbát is.
- **`lib/app/home_shell.dart`** — a meglévő `HomeShell` VÁLTOZATLAN (A7). Új
  `AdaptiveHomeShell` widget: `public.dart`-on át importál (D4),
  `navigationShell.currentIndex`/`goBranch` köti be (D9, nem
  `context.go`), `showPrimaryNavigation: !isStageRoute(location)` (D13), az
  öt címke a D10 öt meglévő ARB kulcsából (`todayPlanTitle`,
  `practiceHubTitle`, `songLibraryTitle`, `aiTutorHomeTitle`,
  `tutorProfileTitle`), a kötött `// TODO(E13-R16): dedicated nav ARB keys…`
  komment mellette.

### A §6.3 két valódi-sértés próbája

**1. A2 (legacy redirect kihagyása).** A `/setlists` bejegyzést kivettem a
`legacyRedirects`-ből (`adaptive_shell_routes.dart`), majd lefuttattam:

```bash
flutter test test/app/navigation/legacy_route_redirect_test.dart
```

Eredmény: **PIROS**, 4 cella bukott — `all eleven legacy routes resolve to
their target adapter` (a `/setlists` `/setlists`-en ragadt `/songs/setlists`
helyett), a két D8 query/fragment teszt (mindkettő a redirect-célt méri), és
a `contract 4` / `pinned map matches production` D7-cellák (a kulcshalmaz
szűkült). Ezután visszaállítottam a bejegyzést, `flutter test
test/app/navigation/legacy_route_redirect_test.dart` újra **ZÖLD**.

**2. A4 (anti-vakuum, L403).** A `lib/app/home_shell.dart`
`AdaptiveHomeShell.build()`-jében a `showPrimaryNavigation:
!isStageRoute(location)` sort `showPrimaryNavigation: true`-ra cseréltem
(mindig mutasson navigationt), majd:

```bash
flutter test test/app/navigation/adaptive_scaffold_test.dart
```

Eredmény: **PIROS** — kifejezetten a `AdaptiveHomeShell itself (the
production shell widget, not a re-implementation of its wiring) hides
navigation at a stage location and shows exactly one otherwise` cella
bukott (`NavigationRail` jelent meg egy stage-locationnél, ahol nem
szabadna). Ez a cella egy **elkülönített** `GoRouter` +
`StatefulShellRoute.indexedStack` teszt-harnesst épít, ami a VALÓDI
`AdaptiveHomeShell` osztályt húzza fel egy stage-route branch-csel — nem a
`home_shell.dart` kifejezését másolja be a tesztbe (az első verzióm ezt
tette, és emiatt nem vette észre a mutációt; ez maga volt egy vakuum-cella,
amit a próba futtatása közben találtam meg és javítottam). Visszaállítottam
az eredeti sort, a teszt újra **ZÖLD**.

### Döntések, amiket a §0.0 nem kötött meg

- **A `StatefulShellRoute` deklarációs helye** a `routes` listában: a
  `practiceEnabled`/`songTrainerEnabled` blokkok UTÁN, NEM közvetlenül a
  legacy `ShellRoute` után (ahogy elsőre írtam). Indoklás fent (duplikáció
  megfigyelhetősége).
- **NavigationRail `labelType`:** medium módban `selected` (a kiválasztott
  címke látszik), expanded/wide módban `none` + `extended: true` (a rail
  saját maga rajzolja ki a címkéket, mert `extended: true` mellett a
  Flutter-keret megköveteli a `none` `labelType`-ot).
- **Ikonok:** Material `Icons.*` (today/fitness_center/library_music/
  smart_toy/person), mert az acceptance-mátrix nem köti az ikonkészletet —
  a `lucide_icons_flutter`/`ss_icons` bevezetése tartalmi döntés, később.

### Gate

```bash
tools/round-gate.sh test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart
```

MINDEN GATE ZÖLD (format, analyze, mindhárom teszt külön, architecture,
secrets, l10n). `test/app/routing/*` és
`test/core/architecture_dependency_test.dart` külön futtatva is zöld (A7,
D4) — lásd a fenti transzkriptumot.

### Javító kör (review) — MAJOR-1 és MINOR-1

A `docs/reviews/e13-r08-review.md` és a brief §0.0 D14/D15 szerint, ugyanabban
a munkapéldányban, ugyanazon a branchen.

**MAJOR-1 (mikrofon/wakelock retenció + kettőzés) — D14 öt pontja mind:**

1. **`/today` adaptere `ProgressScreen`** (`app_router.dart`, `today` branch) —
   nem `LiveScreen`. Ez szünteti meg a kettőzést (két `LiveScreen` két
   branchben).
2. **`/practice/live` kikerült a shell-branchből**, top-level `GoRoute` lett
   (`app_router.dart`, a `StatefulShellRoute` elé, a session-route-okhoz
   hasonló mintában), `if (adaptiveShellEnabled)` őrrel — a `practiceEnabled`-
   től függetlenül regisztrált, mert ő a `/live` redirect célja (D5/D6). A
   `LiveScreen`-nek nincs saját `Scaffold`-ja (a legacy `HomeShell` adta
   eddig) — a route builder ezért `Scaffold(body: LiveScreen())`-et ad vissza;
   enélkül a `StreakBadge` (`live_screen.dart:201`) `InkWell`-je
   „No Material widget found" kivétellel bukott (ezt a gate első futása
   PIROSRA is váltotta, l. a §10 alatti transzkriptum-hiány — javítva, majd a
   gate újra futtatva zöldre).
3. **`AppRoutes.practiceLive` bekerült az `isStageRoute` halmazába**
   (`adaptive_shell_routes.dart`) — négyelemű lett.
4. **A belépési pont flag BE ágán `/today`:** `entryLocation =
   adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live`, ez lett a
   `GoRouter.initialLocation` ÉS a `redirect` callback `onboardingRedirect`
   hívásának `home:` paramétere. Az `onboardingRedirect` (`route_guards.dart`)
   kapott egy opcionális, `AppRoutes.live` alapértelmezésű `home` paramétert —
   a **módosítatlan** `test/app/routing/route_guards_test.dart` zöld maradt
   (ellenőrizve, l. lent).
5. **A `/live` → `/practice/live` redirect változatlan** (`legacyRedirects`
   térkép nem módosult).

**Új A8 cella** (`test/app/navigation/adaptive_scaffold_test.dart`, `A8 —
resource-owning screens release on destination switch` csoport, három cella):
legacy referencia (flag KI, `/live` → `/analyze`, `LiveScreen findsNothing` +
`wakelock.isHeld == false`) ZÖLD; flag BE, `/practice/live` → `/today`
tabváltás: `find.byType(LiveScreen, skipOffstage: false)` **0** példány,
`wakelock.isHeld == false`, `disableCalls >= 1`; flag BE, teljes öt-branch
bejárás (`today/practiceHub/songs/coachHome/profileHome`): `LiveScreen`
`skipOffstage: false` mellett is **findsNothing** egyetlen branchben sem. A
`FakeScreenWakelock`-ot a `_pumpAdaptiveRouter` helper új `wakelock` paramétere
adja át (`fakeAudioOverrides(wakelock: wakelock)`).

**MINOR-1 (a shell megkerülte a `practiceEngineV2Enabled`/`aiTutorEnabled`
rollout-flageket) — D15:**

- A `practiceHub` `GoRoute` a Practice branchen belül `if (practiceEnabled)`
  őrt kapott; a branch többi al-útvonala (analyze/learn/tuner/metronome/
  chords) feltétel nélkül marad, tehát a branch sosem üres.
- A Coach branch EGÉSZE `if (aiTutorEnabled)` őrt kapott (`app_router.dart`,
  `branches` lista) — a `coachHome` az egyetlen útvonala, tehát csak a
  route-ot őrizni üres branch-et hagyott volna. A `AdaptiveHomeShell` kapott
  egy `showCoachDestination` konstruktor-paramétert (`home_shell.dart`),
  amit az `app_router.dart` `aiTutorEnabled`-del táplál — index-szinkronban
  tartja a `destinations` listát a feltételesen bővülő `branches` listával.
- Két új cella (`adaptive_scaffold_test.dart`, `A1` csoport): `/practice`
  nem ad `PracticeHubScreen`-t `practiceEngineV2Enabled: false` mellett;
  `/coach` nem ad `TutorHomeScreen`-t `aiTutorEnabled: false` mellett.
- A `tab_state_restoration_test.dart` flag-halmaza kapott egy explicit
  `practiceEngineV2Enabled: true`-t (korábban hallgatólagosan a konstruktor-
  defaultra — `false` — támaszkodott, miközben mégis `PracticeHubScreen`-t
  várt; ez volt a MINOR-1 saját bizonyítéka a reviewtől).

**Érintett meglévő cellák frissítve** (a szerkezeti változás miatt, a mércét
igazítva a kódhoz, nem fordítva): az A1 „five destinations" cella most
`ProgressScreen`-t vár `/today`-nál, és `practiceEngineV2Enabled: true` +
`aiTutorEnabled: true`-t állít (mert a `/practice`/`/coach` úti célja immár
saját flaget kér); az A4 `isStageRoute` predikátum-cella megfordítva
`AppRoutes.practiceLive`-ra (`isTrue`, nem `isFalse`).

### Kötelező záró ellenőrzés (javító kör)

```bash
tools/round-gate.sh test/app/navigation/adaptive_scaffold_test.dart test/app/navigation/legacy_route_redirect_test.dart test/app/navigation/tab_state_restoration_test.dart
```

MINDEN GATE ZÖLD (format, analyze, mindhárom teszt külön — 21+8+1 cella —,
architecture, secrets, l10n). `flutter test test/app/routing` is lefutott
külön (D14/4 érinti az onboarding-redirectet): alapértelmezett
párhuzamossággal a `route_guards_test.dart` sorai a compact reporter
kimenetében nem jelentek meg (ismert reporter-limitáció sok fájl egyidejű
futtatásánál — nem tesztbukás: az exit code mindkét futásnál 0, „All tests
passed!"), ezért `--concurrency=1`-gyel újra lefuttatva a mind a négy fájl
(`shell_lifecycle_test.dart`, `app_router_test.dart`,
`onboarding_first_win_test.dart`, `route_guards_test.dart`, összesen 29 cella)
soronként megjelent és **ZÖLD** — a `route_guards_test.dart` a D14/4 opcionális
`home` paraméter mellett is módosítatlanul zöld maradt.

**Javító kör 2 (MINOR-2) — `onException` a kiszámolt `entryLocation`-re
menjen, ne fixen `/live`-ra:** az `app_router.dart:213` `onException: (_, _,
router) => router.go(AppRoutes.live)` egysoros cserével `entryLocation`-re
vált. Flag KI ágon `entryLocation == AppRoutes.live`, tehát bitre azonos
viselkedés (A7-biztos); flag BE ágon `/today`-re köt ki, ahol van primary
navigation. Új `A7` csoport (`adaptive_scaffold_test.dart`, az `A1` csoport
után, három cella): flag KI ismeretlen URL → `/live` (változatlan); flag BE
ismeretlen URL → `/today` + van `NavigationBar`/`NavigationRail`; flag BE +
`practiceEngineV2Enabled: false`, `/practice` → `/today`, nem
`/practice/live`. Gate újra lefuttatva (lásd §3 parancs), mindhárom teszt-fájl
zöld (24+8+1 cella), `flutter test test/app/routing` is zöld (29 cella).

## 11. Review — a Claude tölti ki
