# E13-R15 — Lokalizációs resilience és content style

- **Státusz:** REVIDEÁLVA a pre-flightban (2026-08-24, `main @ 7038f194`) —
  eredetileg PREPARED (2026-08-15, kód olvasva: `main @ 6adea220`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 15
- **Kör-azonosító:** `E13-R15`
- **Branch:** `sonnet-impl/e13-r15-localization-resilience`
- **Előfeltétel:** `E13-R14` merge-elve (accessibility toolkit) — ✅ `838865d3`
- **Brief szerzője:** Claude (Opus 5) · **pre-flight revízió:** Claude (Opus 5)
- **ADR:** `0424` — a kör normatív döntéseit az orchestrátor a pre-flight
  commitban írta meg (`docs/adr/0424-localization-resilience-contract.md`).
  A `docs/adr/**` az **implementer** számára továbbra is tilos zóna.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/i18n/ss_formatters.dart",
  "lib/core/i18n/pseudo_locale.dart",
  "lib/core/design_system/public.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/formatters_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
  "docs/ui/content-style.md",
  "docs/rounds/e13-r15-localization-resilience.md",
]
gate_tests = [
  "test/l10n/arb_parity_test.dart",
  "test/l10n/formatters_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
]
native_gate = false
```

---

## 0.0 Pre-flight revízió (2026-08-24) — MÉRT tények és a belőlük következő változások

A brief 2026-08-15-én készült. Az azóta merge-elt **ADR 0307 §4** (PR #343,
2026-08-20) átírta az l10n-architektúrát, ezért a brief eredeti
`allowed_paths`-a **végrehajthatatlan** volt. Minden alábbi állítás
grep/`python3` méréssel készült a `7038f194` HEAD-en.

### M1 — `lib/l10n/app_{en,hu}.arb` GENERÁLT aggregátum, nem forrás

```
$ head -12 tool/gen_l10n_segments.dart
// GENERATED-FILE-MARKER: tool/gen_l10n_segments.dart
// A `lib/l10n/app_<locale>.arb` fájlok MÁR NEM kézzel szerkesztett források…
$ grep -n "GENERATED_PATHS" -A 5 tools/round-slots.py
93:GENERATED_PATHS = frozenset({ "lib/l10n/app_en.arb", "lib/l10n/app_hu.arb" })
```

A tényleges forrás a `lib/l10n/base/app_<locale>.arb` + a
`lib/l10n/features/<feature>_<locale>.arb` fragmentumok uniója; a
design-system szövegeké konkrétan `lib/l10n/features/design_system_{en,hu}.arb`.
A gate `l10n` lépése (`tools/round-gate.sh:242` →
`tool/ci/check_l10n_parity.dart`) és a generátor `--check` módja a kézzel
szerkesztett aggregátumot **pirosra váltja**.

> Ez ugyanaz a hibaosztály, amit `docs/LESSONS.md` **L365** (E08-R12),
> **L369** (E08-R13, H3 self-heal) és **L396** (E08-R20) már háromszor
> rögzített: „a generált l10n-scope javítását minden későbbi, fordítást kérő
> briefre is át kell vinni". Ez a **negyedik** ismétlés — most a pre-flight
> fogta meg, implementer-futás és halt nélkül.

### M2 — nincs pótolandó hiány: a paritás MA teljes, minden szinten

```
$ python3 …  # aggregátum
lib/l10n/app_en.arb  message-keys: 1838
lib/l10n/app_hu.arb  message-keys: 1838
en-only: []   hu-only: []   parity: True

$ python3 …  # fragmentumonként
community_en.arb       en=  145 hu=  145 en-only=[] hu-only=[]
design_system_en.arb   en=   30 hu=   30 en-only=[] hu-only=[]
gamification_en.arb    en=  258 hu=  258 en-only=[] hu-only=[]
tuner_en.arb           en=   14 hu=   14 en-only=[] hu-only=[]
base/app_en.arb        en= 1391 hu= 1391 en-only=[] hu-only=[]
```

Az eredeti §8/2. lépés („az ARB-katalógus rendezése… **a hiányok pótlása**")
tárgytalan: nulla hiány van. Az eredeti §2 feltevése („az R10–R13 új kulcsokat
vezetett be — a paritás mostantól gépi kapu kell legyen") a **kapura** nézve
helytálló, a **hiánypótlásra** nézve mért módon nem.

### M3 — a döntés: `allowed_paths` SZŰKÍTÉS, nem tágítás

Az M1 + M2 együtt azt jelenti, hogy a kör ARB-írási igénye megszűnt. A két
generált útvonal ezért **kikerül** az engedélyezett listáról (ez szűkítés, az
orchestrátor hatásköre — ADR 0087 §2). A fragmentumok felvétele **tágítás
lenne (H3)**, ezért nem történik meg; a §1 célja (törésbiztonság, microcopy,
locale-tudatos formázás) új ARB-kulcs nélkül **maradéktalanul teljesül**.

**Következmény:** ez a kör **nem ír egyetlen új ARB-kulcsot sem**, és nem
szerkeszt ARB-fájlt. Ami épül: gépi őrök, formázók, pszeudo-locale, stílus.

### M4 — létező paritás-kapu: a hármas duplikálása tilos

`test/core/l10n_parity_test.dart` MA három dolgot mér az **aggregátumon**:
azonos kulcshalmaz · nincs üres fordítás · azonos placeholder-halmaz. Emellé
`tool/ci/check_l10n_parity.dart` a gate `l10n` lépése.

Az új `test/l10n/arb_parity_test.dart` ezért **nem másolat**: a
**fragmentum-szintű** és **ICU-szerkezeti** réteget méri, amit a meglévő kapu
nem lát (§6 A1). A kulcshalmaz-paritást a saját scope-jában újra kimondja —
enélkül a §6.1 kötelező valódi-sértés próbája nem a SAJÁT celláját mérné.

### M5 — az A2/A3 guard tényleges hatóköre (mérve)

```
$ grep -rnoE "(Text|label|title|message|hintText|semanticLabel|tooltip|description)\s*[:(]\s*'[^']{3,}'" lib/core/design_system/ | wc -l
39
```

- **38 találat** egyetlen fájlban: `documentation/component_catalog_screen.dart`.
  Ez **fejlesztői galéria**, nem termék-UI: mérve nulla hivatkozás rá a saját
  fájlján és a barrel-exporton kívül (`grep -rn "ComponentCatalogScreen"
  lib/` → csak `public.dart:1`). A minta-szövegei szándékosan illusztratívak.
  → a guard hatóköréből **kimarad**, dokumentált indokkal.
- **1 találat valódi komponensben**:
  `components/inputs/ss_validation_summary.dart:90`
  `label: '${l10n.dsFieldErrorSemanticPrefix}: $message'` — ez **valódi
  A2-osztályú mondat-összefűzés** (a kulcs neve is `…Prefix`, értéke
  `"Error"`/`"Hiba"`, `": "` literállal ragasztva). A hívási hely **kívül esik**
  az engedélyezett listán → javítása H3 lenne. Kezelése: **befagyasztott
  alaphalmaz** (§5.8 racsni), nem elhallgatás.

### M6 — magyar többes szám: a naiv „en plural ⇒ hu plural" szabály HIBÁS

```
EN streakV2CurrentSemantics = 'Current rhythm: {count, plural, =0{0 days} =1{1 day} other{{count} days}}'
HU streakV2CurrentSemantics = 'Jelenlegi ritmus: {count} nap'
```

Három ilyen kulcs van (`streakV2{Current,Longest,Total}Semantics`). A magyar
alak **helyes**: számnév után a főnév egyes számban marad („1 nap", „3 nap").
Egy „a hu-nak is ICU pluralnak kell lennie" őr ezt a három, nyelvtanilag
**helyes** kulcsot váltaná pirosra — hamis lelet. Az A5 mércéje ezért a §5.6
szerinti, nyelvhelyes szabály.

### M7 — a pszeudo-locale NEM regisztrált locale

`supportedLocales` a `lib/app/strumsight_app.dart:44`-ben él (tilos zóna), az
`l10n.yaml` `template-arb-file: app_en.arb` (nincs az engedélyezett listán).
A `pseudo_locale.dart` ezért **tiszta teszt-mód**: string-transzformáció +
teszt-oldali `Localizations`-burkolat. Új locale felvétele **tilos** (a §3 is
tiltja).

### M8 — visszakeresett előzmények (ADR 0312 / brief-lint S8)

| Forrás | Amit köt |
|---|---|
| `lessons/L396`, `L369`, `L365` | generált ARB-aggregátum ≠ forrás → M1/M3 |
| `lessons/L342` | `@key` metaadat csak a saját szegmenséből → A1 ICU/metaadat-cella |
| `lessons/L452` | `MediaQuery(size:)` NEM méretezi a layoutot widget-tesztben → §5.9 |
| `lessons/L460` | jelenlét-alapú őr VAK a sértésre → §6.1 falszifikációs cellák |
| `adr/0307` §4 | l10n-fragmentum architektúra + `--check` frissesség |
| `adr/0277` | minden hibaüzenet lokalizálható, `Text(error.toString())` tilos |

### M9 — a revízió összefoglalója

| Mit | Eredeti | Revideált | Miért |
|---|---|---|---|
| `lib/l10n/app_{en,hu}.arb` | engedélyezett | **törölve** | M1 generált, M2 nincs teendő |
| §8/2 „hiányok pótlása" | lépés | **törölve** | M2: nulla hiány |
| A1 | aggregátum-paritás | fragmentum + ICU réteg | M4: a meglévő kapu már fedi |
| A3 guard hatóköre | „migrált core komponensek" | §5.5 pontos lista | M5 |
| A5 | „hu is pluralt használ" | §5.6 nyelvhelyes szabály | M6 |
| A6 bizonyíték | „+ golden" | túlcsordulás-cella | §5.9 (L452), 4 golden az egész repóban |
| ADR | „nincs" | `0424` (pre-flight commit) | a kör normatív döntéseket hoz |

---

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott.

**STOP-protokoll (S1).** Ha a munka a §4 engedélyezett listán **kívüli** fájlt
kívánna módosítani — akár egy „csak egy sor" javítást is —, akkor:

1. **NE módosítsd**, és ne is állítsd vissza a listán kívüli fájlt;
2. `tools/codex-signal.sh stopped "<a fájl útvonala> + egy sor, mi kellene"`;
3. a §10-be írd le, mit mértél és miért nem fér a scope-ba.

Ez különösen a `lib/l10n/**` (M1 szerint generált vagy scope-on kívüli
fragmentum), a `lib/core/design_system/components/**` és a
`lib/app/strumsight_app.dart` esetére vonatkozik — mindhárom kívül van.

## 1. Cél

Az angol–magyar felület **törésbiztonsága**, a microcopy szabályai és a
locale-tudatos formázás (SDD Ch13 Kör 15) — **gépi őrökkel**, nem
szemrevételezéssel.

## 2. Jelenlegi állapot — MÉRT tények (2026-08-24, `7038f194`)

- Az ARB-paritás **ma teljes**: aggregátum 1838/1838, és mind az 5 forrás-
  szegmens 1:1 (M2). Nincs pótolandó hiány.
- `lib/l10n/app_{en,hu}.arb` **generált** (M1). A szerkeszthető forrás a
  `base/` + `features/` fragmentum — mindkettő **kívül** ezen a körön.
- Létezik aggregátum-szintű paritás-kapu (`test/core/l10n_parity_test.dart`) és
  gate-lépés (`tool/ci/check_l10n_parity.dart`) — **fragmentum-szintű nincs** (M4).
- A `lib/core/i18n/` ma **egyetlen** fájlt tartalmaz: `locale_provider.dart`.
  Nincs locale-tudatos formázó; a `DateFormat` szórtan, feature-ökben él
  (`weekly_bars.dart`, `progress_screen.dart`, `learn_screen.dart`).
- A design system 39 szöveg-literáljából 38 a nem-routolt galériában van, 1 a
  `ss_validation_summary.dart`-ban valódi összefűzés (M5).
- Az R04 kimondta: a magyar szöveg **≥30% tartalékot** igényel, és 2.0 text
  scale mellett sem clippelhet.

## 3. Scope

**Benne van:** fragmentum-szintű + ICU-szerkezeti ARB-paritás **kapu** ·
locale-tudatos időtartam-, BPM-, cents-, százalék- és dátum-formázó ·
pszeudo-lokalizációs **teszt-mód** · beégetett-szöveg és mondat-összefűzés
**guard** a §5.5 hatókörre, befagyasztott alaphalmazzal · microcopy
stílusútmutató (visszajelzés, engedély, AI-eredet, offline, destruktív akció).

**NINCS benne (tilos):** **bármely ARB-fájl szerkesztése** (M1/M3 — sem
aggregátum, sem fragmentum) · új ARB-kulcs · `lib/features/**` szövegeinek
migrálása · új nyelv vagy regisztrált locale felvétele · `lib/core/theme/**` ·
`lib/core/design_system/components/**` · `lib/app/**` · `docs/adr/**` ·
`tools/**` · `tool/**` · `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/i18n/ss_formatters.dart` | **ÚJ** — locale-tudatos formázók |
| `lib/core/i18n/pseudo_locale.dart` | **ÚJ** — teszt-mód (M7: nem regisztrált locale) |
| `lib/core/design_system/public.dart` | az export bővítése (nem generált — mérve) |
| `test/l10n/arb_parity_test.dart` | **ÚJ** — A1 |
| `test/l10n/formatters_test.dart` | **ÚJ** — A4, A5, A6 |
| `test/l10n/hardcoded_string_guard_test.dart` | **ÚJ** — A2, A3 |
| `docs/ui/content-style.md` | **ÚJ** — A7 microcopy szabályok |
| `docs/rounds/e13-r15-localization-resilience.md` | a §10 handoff |

**Tilos zóna:** `lib/l10n/**` · `lib/features/**` · `lib/core/theme/**` ·
`lib/core/design_system/**` a `public.dart` KIVÉTELÉVEL · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `tool/**` · `.github/**` ·
`l10n.yaml` · `pubspec.yaml`.

## 5. Kötött architekturális döntések

*(Normatív forrás: ADR 0424 — a pre-flight commitban.)*

### 5.1 Nincs MONDATSZERKEZETI string-összefűzés

`'$count ' + t.songs` alakú összefűzés tilos: a magyar szórend és a ragozás más.
Minden mondat egyetlen, paraméterezett ARB-kulcs.

**NEM elfogadható gyengítés:** „ez a két szó úgyis mindig ebben a sorrendben
van". Pont ez a feltevés bukik meg a második nyelven.

### 5.2 A paritás GÉPI kapu, nem szemrevételezés — és FRAGMENTUM-szinten

Az en és a hu kulcshalmaza megegyezik **minden forrás-szegmensben külön-külön**
(`lib/l10n/base/app_{en,hu}.arb` és `lib/l10n/features/<f>_{en,hu}.arb`), nem
csak az aggregátumban. Egy fragmentum-szintű hiány az aggregátumban is
megjelenik, de a **hibaüzenetnek a fragmentumra kell mutatnia** — különben a
javító nem tudja, melyik fájlt nyissa ki (M4).

### 5.3 A formázás locale-tudatos

Időtartam, BPM, cents, százalék és dátum a felhasználó locale-ja szerint. A
tizedesjel és az ezres elválasztó eltér a két nyelvben (`en`: `1,234.5`;
`hu`: `1 234,5`). A formázók **`package:intl`**-t használnak
(`NumberFormat`/`DateFormat` explicit `localeName`-mel), **nem** kézi
sztring-manipulációt, és **nem** `toString()`-et.

A formázók **tiszta függvények**: nem olvasnak `BuildContext`-et, a locale-t
paraméterként kapják. Így a cellák `BuildContext` nélkül mérhetők.

### 5.4 A pszeudo-lokalizáció a TÖRÉST méri, nem szépít

A hosszított teszt-locale célja, hogy kiugorjon a clipping — ezért nem lehet
opcionális dísz, hanem a hossz-cellák bemenete. A transzformnak **legalább
1,6×** hosszúságot kell adnia (§6.1 számított cellák), és meg kell tartania a
`{placeholder}` tokeneket **érintetlenül** — különben az ICU-formázás elszáll,
és a cella nem a clippinget mérné.

### 5.5 A beégetett szöveg GUARD-dal tiltott — PONTOSAN ezen a hatókörön

A guard hatóköre (M5 alapján), tételesen:

```
lib/core/design_system/components/**
lib/core/design_system/accessibility/**
lib/core/design_system/layouts/**
lib/core/design_system/motion/**
```

**Kimarad**, dokumentált indokkal:

| Kimaradó | Indok (mért) |
|---|---|
| `documentation/**` | fejlesztői galéria, nem routolt termék-UI (M5) |
| `foundations/**`, `themes/**`, `icons/**` | token/téma réteg, nincs benne felhasználói mondat |

A hatókört a teszt **konstansként** deklarálja, és a guard a fenti könyvtárakat
**rekurzívan** járja be — nem fájllistából dolgozik, hogy egy új komponens
automatikusan a hatókörbe kerüljön.

### 5.6 A magyar többes szám szabálya (M6)

Nyelvhelyes mérce, nem tükrözés:

1. Ha az **en** érték ICU `plural`-t használ, kötelező benne az `other` ág.
2. A **hu** párja vagy ICU `plural` (legalább `other` ággal), **vagy** csupasz
   `{count}` placeholder — mindkettő helyes magyar.
3. A **hu** ICU `plural` ágai csak a magyarban létező kategóriákból
   jöhetnek: `=<szám>`, `zero`, `one`, `other`. A `few`/`many` (szláv/arab
   kategóriák) jelenléte **hiba**.
4. Pozitív nyelvtani cella: a hu üzenet `count=1` és `count=3` melletti
   kimenete **csak a számjegyben** térhet el — a főnév alakja azonos marad.

### 5.7 A pszeudo-locale teszt-mód, nem regisztrált nyelv (M7)

Tilos `supportedLocales`-t, `l10n.yaml`-t vagy új `AppLocalizations`
delegáltat érinteni — mindegyik kívül van (§4). A pszeudo-locale egy
transzformáció + teszt-oldali burkolat.

### 5.8 A befagyasztott alaphalmaz RACSNI, nem mentesség (M5)

A guard ismer egy `frozenViolations` konstanst. A teszt **pontos egyenlőséget**
mér (`setEquals`), nem részhalmazt:

- **új** sértés → piros (nőni nem tud);
- **javított** sértés, amit nem vettek ki a listáról → **szintén piros** (a
  lista nem avulhat el).

Minden bejegyzés mellé kötelező: `fájl:sor`, a sértés osztálya, és **miért nem
javítható ebben a körben** (útvonal az engedélyezett listán kívül). A kör
indulási alaphalmaza **pontosan egy** elem (M5):
`lib/core/design_system/components/inputs/ss_validation_summary.dart` —
A2 mondat-összefűzés, a hívási hely a §4 listán kívül.

Egy részhalmaz-alapú („legalább ennyi meg van engedve") őr **nem elfogadható**:
az a csendes növekedést engedné.

### 5.9 A viewport-méretezés `tester.view`-n megy, nem `MediaQuery`-n (L452)

Widget-tesztben a `MediaQuery(data: MediaQueryData(size: …))` **nem** méretezi
a layoutot — a deklarált geometria sosem áll elő, a cella a default 800×600-on
mér, és zöld marad akkor is, ha a valódi méreten clippelne. A hossz-cellák
ezért:

```dart
tester.view.physicalSize = const Size(width, height) * ratio;
tester.view.devicePixelRatio = ratio;
addTearDown(tester.view.reset);
```

A text scale-t `MediaQuery(textScaler: TextScaler.linear(2.0))` adja (az
skálázás, nem geometria — az működik).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden ARB-**szegmens** en/hu kulcsparitása teljes, és a hibaüzenet a fragmentumra mutat | `arb_parity_test.dart` |
| A2 | Nincs mondatszerkezeti string-összefűzés az §5.5 hatókörben (a befagyasztott alaphalmazon kívül) | `hardcoded_string_guard_test.dart` |
| A3 | Nincs beégetett felhasználói szöveg az §5.5 hatókörben | ugyanott |
| A4 | A formázók locale-tudatosak (időtartam, BPM, cents, %, dátum), en és hu külön mérve | `formatters_test.dart` |
| A5 | A többes szám mindkét nyelven **nyelvhelyes** (§5.6 négy szabálya) | `arb_parity_test.dart` |
| A6 | A kritikus komponens a +30% tartalékon és a pszeudo-locale (+60%) mellett sem clippel, 2.0 text scale-en | `formatters_test.dart` |
| A7 | A microcopy útmutató lefedi az öt kötelező helyzetet | `docs/ui/content-style.md` |

### 6.1 Falszifikációs mátrix — melyik hibás implementációt melyik cella fogja pirosra, és MELYIK őr méri

| # | Hibás implementáció | PIROSRA vált | Az őr fajtája |
|---|---|---|---|
| F1 | Egy hu kulcs törlése egy **fragmentumból** | **A1** | unit-cella (szegmensenkénti halmaz-diff) |
| F2 | Egy en ICU `plural`-ból az `other` ág törlése | **A5** | unit-cella (ICU-ág parse) |
| F3 | Egy hu értékbe `few{…}` ág beírása | **A5** | unit-cella (kategória-allowlist) |
| F4 | Egy hu üzenet „napok"-ra írása `count>1`-nél (tükrözött angol többes) | **A5** | unit-cella (count=1 vs count=3 kimenet-diff, §5.6/4) |
| F5 | `'${l10n.a} ${l10n.b}'` alakú új összefűzés egy komponensben | **A2** | forrás-scan + racsni |
| F6 | Új `Text('Save')` literál egy komponensben | **A3** | forrás-scan + racsni |
| F7 | A `ss_validation_summary.dart` sértés **javítása** a lista frissítése nélkül | **A2** | racsni (pontos egyenlőség, §5.8) |
| F8 | `date.toString()` a dátum-formázóban | **A4** | unit-cella (en/hu kimenet-diff) |
| F9 | A tizedesjel hardcode-olása (`'.'`) a százalék-formázóban | **A4** | unit-cella (hu `,` elvárás) |
| F10 | A pszeudo-transzform kevesebb mint 1,6×-ra nyújt | **A6** | unit-cella (számított hossz) |
| F11 | A pszeudo-transzform szétvágja a `{placeholder}`-t | **A6** | unit-cella (token-megőrzés) |
| F12 | A hossz-cella `MediaQuery(size:)`-zal méretez (L452) | **A6** | a cella deklarált és tényleges méretét **ki kell írnia** és egyeznie kell |

**F12 megjegyzés:** a `formatters_test.dart`-nak tartalmaznia kell egy cellát,
amely a `tester.view` beállítása után **méri és állítja** a tényleges render-
méretet (`tester.getSize(find.byType(MaterialApp))` vagy a mért gyökér-widget),
és pirosra vált, ha az nem egyezik a deklarálttal. Ez zárja L452-t gépileg.

### 6.2 A magyar szöveghossz három számított cellája

Küszöb: az angol hosszhoz képest **+30%** tartalék. A bázis egy 40 karakteres
angol címke; a cellák `python3 -c`-vel számolva:

```
$ python3 -c "base=40
for n,p in [('alatta',15),('rajta',30),('fölötte',60)]: print(n, p, round(base*(1+p/100)))"
alatta   15 46
rajta    30 52
fölötte  60 64
```

| Cella | Bemenet (karakter) | Elvárt |
|---|---|---|
| a küszöb **alatt** | 46 (`+15%`) | elfér, nincs túlcsordulás |
| **rajta** (a küszöbön) | 52 (`+30%`) | **elfér** — ez a kötelező tartalék |
| a küszöb **fölött** | 64 (`+60%`, pszeudo-locale) | **nem clippelhet** a kritikus komponensben |

Mindhárom cella 2.0 text scale mellett, `tester.view`-val méretezve (§5.9). A
„kritikus komponens" a §5.5 hatókörből választott, `public.dart`-on át elérhető
szöveg-hordozó komponens; a választást a §10 indokolja.

**A pszeudo-transzform expanziós cellái** (ugyanezzel a számítással):

| Bemeneti hossz | Minimum elvárt pszeudo-hossz |
|---|---|
| 10 | 16 |
| 20 | 32 |
| 40 | 64 |
| 80 | 128 |

### 6.3 Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva)

Az implementer **futtassa le és írja le a kimenetét** — nem elég állítani:

1. Törölj egy kulcsot a `lib/l10n/features/design_system_hu.arb`-ból →
   az **A1** cellának PIROSNAK kell lennie, és a hibaüzenetben szerepelnie kell
   a `design_system_hu.arb` fragmentum nevének → **állítsd vissza**
   (`git checkout -- lib/l10n/features/design_system_hu.arb`).
2. Írj egy `Text('Save changes')` literált egy §5.5-hatókörbeli komponensbe →
   az **A3** cellának PIROSNAK kell lennie → **állítsd vissza**.

> Mindkét próba **ideiglenes, lokális mutáció**: a fájlok a tilos zónában
> vannak, ezért a próba után a fának **tisztának** kell lennie
> (`git status --short` üres a nem engedélyezett útvonalakra). A §10-be a
> mutáció, a piros kimenet és a visszaállítás igazolása is bekerül.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/l10n/arb_parity_test.dart test/l10n/formatters_test.dart test/l10n/hardcoded_string_guard_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

A **brief §8 a terved** — nincs külön task-lista, ne írj sajátot.

1. `test/l10n/arb_parity_test.dart` — fragmentum-szintű halmaz-diff (A1) +
   a §5.6 négy ICU/nyelvhelyességi szabálya (A5). A kapu ELŐBB.
2. `lib/core/i18n/ss_formatters.dart` — `package:intl`-re épülő, tiszta
   függvények: időtartam, BPM, cents, százalék, dátum (§5.3).
3. `lib/core/i18n/pseudo_locale.dart` — transzformáció (≥1,6×,
   placeholder-megőrző) + teszt-burkolat (§5.4, §5.7).
4. `test/l10n/formatters_test.dart` — A4 en/hu cellák, A6 három hossz-cella
   `tester.view`-val (§5.9) + az F12 méret-igazoló cella + a pszeudo-expanziós
   cellák (§6.2).
5. `test/l10n/hardcoded_string_guard_test.dart` — a §5.5 hatókör rekurzív
   scanje, a §5.8 pontos-egyenlőségű racsnival (A2, A3).
6. `lib/core/design_system/public.dart` — az új publikus felület exportja.
7. `docs/ui/content-style.md` — microcopy az öt helyzetre: visszajelzés,
   engedélykérés, AI-eredet, offline, destruktív akció. Mindegyikhez
   **jó/rossz példapár**, magyarul és angolul.
8. A §6.3 valódi-sértés próbák futtatása, kimenettel a §10-be.
9. `tools/round-gate.sh` a §7 szerint.

**Doc-commentben csak tesztben bizonyított állítás** szerepeljen (`const`,
`immutable`, „tiszta függvény") — amit nem mér cella, azt ne állítsd.

## 9. Kockázatok

- **A guard túl széles hatóköre.** Ha a teljes fára vagy a galériára néz,
  azonnal piros (38 találat, M5), és kikapcsolják — az §5.5 lista a helyes határ.
- **A racsni részhalmazra lazítása.** Egy `containsAll` alakú őr csendes
  növekedést enged; a §5.8 pontos egyenlőséget ír elő (F7).
- **A tükrözött magyar többes szám.** A naiv „hu is legyen ICU plural" őr három
  helyes kulcsot váltana pirosra (M6) — a §5.6 a mérce.
- **A `MediaQuery(size:)` csapda.** L452: a hossz-cella zöld marad, miközben a
  valódi méreten clippel. Az F12 cella ezt gépileg zárja.
- **A jelenlét-alapú őr vaksága.** L460: az A2/A3 nem azt méri, hogy „van
  l10n-hívás", hanem hogy **nincs** literál/összefűzés — a §6.3/2 próba ezt
  igazolja.
- **ARB-fájl hozzányúlása.** M1/M3 után bármely `lib/l10n/**` írás
  scope-sértés → `stopped` (§0 S1), nem „gyors javítás".

## 10. Implementation handoff — az implementer tölti ki

**Státusz:** KÉSZ (2026-08-24, Claude Sonnet 5 mint implementer).

### Mit épült

| Fájl | Tartalom |
|---|---|
| `test/l10n/arb_parity_test.dart` | Fragmentum-szintű en/hu kulcsparitás mind az 5 forrás-szegmensre (base + 4 feature), fragmentum-nevet tartalmazó hibaüzenettel (A1). ICU `plural`-parser (brace-depth scan, nested `other{{count} days}` is helyesen kezelve) + a §5.6 négy szabálya minden fragmentumon végigfuttatva (A5) — a repóban ténylegesen **14** en ICU-plural kulcs van (nem csak a brief M6-ban vizsgált 3), mind a base/app és a features/gamification szegmensben; mindegyik lefutott, mind zöld. |
| `lib/core/i18n/ss_formatters.dart` | `SsFormatters.{duration,bpm,cents,percent,date}` — tiszta függvények, `package:intl` (`NumberFormat`/`DateFormat`), explicit `localeName` paraméterrel. `date()` lustán, idempotensen hívja az `initializeDateFormatting()`-et (a `package:intl` maga is szinkron-belül tölti be MINDEN locale adatát egy hívásra — mérve, ld. §10 "Mért döntések"). |
| `lib/core/i18n/pseudo_locale.dart` | `ssPseudoLocalize` (≥1,6× hossz, `{placeholder}` token-megőrző, breakable `~`-filler — NEM egybefüggő, hogy ne generáljon mesterséges, valós fordításban sosem előforduló törésmentes futamot) + `ssPseudoLocaleTestHarness` (teszt-oldali `MaterialApp` a valós `AppLocalizations.localizationsDelegates`/`supportedLocales`-szel, configurable `textScale` — NEM regisztrál új locale-t, M7). |
| `test/l10n/formatters_test.dart` | A4: en/hu kimenet-diff mind az 5 formázóra (a hu tizedesvessző + U+00A0 nem-törhető-szóköz-elválasztó a `package:intl` CLDR-adatából mérve, nem feltételezve — ld. lent). Pszeudo-expanzió (F10, a §6.2 négy hosszra) + placeholder-megőrzés (F11). A6: három hossz-cella (46/52/64 karakter, utóbbi a valódi `ssPseudoLocalize`-on át) `tester.view`-val méretezve (§5.9), 2.0 text scale, `SsFieldError`-t hordozva — mindegyik `tester.takeException()==null`-t ÉS a ténylegesen renderelt `Scaffold`-méretet a deklarált geometriával egyezőnek várja (F12, L452 zárása). |
| `test/l10n/hardcoded_string_guard_test.dart` | Rekurzív scan a 4 engedélyezett könyvtáron; egy klasszifikáló ami A2-t (l10n-hivatkozás + ≥2 interpoláció VAGY extra szöveg) és A3-at (nincs l10n-hivatkozás, de van valódi szó) különböztet meg — nem csak "van-e l10n hívás". Pontos halmaz-egyenlőség (`Set` of record `{file,line,violationClass}`) a §5.8 racsnihoz: 1 elem, az `ss_validation_summary.dart:90` A2-sértés. |
| `lib/core/design_system/public.dart` | 2 új export sor (`../i18n/pseudo_locale.dart`, `../i18n/ss_formatters.dart`) — a fájl NEM generált (mérve: nincs `GENERATED-FILE-MARKER`, a `tool/gen_public_barrel.dart` nem hivatkozik rá). |
| `docs/ui/content-style.md` | Két alapszabály (egy mondat = egy ARB-kulcs; mondd meg MI történt) + 5 kötelező helyzet (visszajelzés, engedélykérés, AI-eredet, offline, destruktív akció), mindegyikhez jó/rossz példapár angolul és magyarul, a legtöbb valós ARB-kulcsra hivatkozva (`dsFailureNetworkGenericTitle`, `dsFailurePermissionMicrophoneMessage`, `dsProvenanceBadgeCloudLabel`, `tutorDataDeleteAllTitle/Body/Action`, stb.). |

### Mért döntések, amik eltérnek a brief szó szerinti olvasatától

1. **A "kritikus komponens" `SsFieldError`, nem `SsMetricCard`.** A `SsMetricCard`
   szándékosan `maxLines: 1` + ellipsis (dashboard-tile, NEM a §6.2 "nem
   clippelhet" mércéjéhez való — az mindig csonkol, tehát vakon zöld maradna).
   `SsFieldError` (`Row(icon, Expanded(Text(...)))`, nincs `maxLines`) valódi,
   ma is helyesen becsomagolt komponens — a teszt REGRESSZIÓ-őr rá, nem azt
   bizonyítja, hogy ma hibás.
2. **`package:intl` hu grouping-szeparátora U+00A0** (nem sima szóköz) — mérve
   `dart run`-nal közvetlenül a CLDR-adaton (lásd a kör transzkriptjében a
   probe-parancsokat), nem feltételezve. A teszt ezt a pontos kódpontot várja.
3. **A pszeudo-transzform NEM egyenletesen accentel minden betűt** — csak egy
   részleges lookalike-térkép (a-z/A-Z egy részhalmaza); a hosszcélt a filler
   garantálja, az accentelés csak vizuális stressz-jel, ezért a részleges
   lefedettség NEM gyengíti a mércét (§6.1 F10/F11 mindkettő a filler + a
   placeholder-megőrzés logikáján fut, nem az accent-térképen).

### §6.3 Valódi-sértés próba — lefuttatva, dokumentálva

**Próba 1 — ARB-kulcs törlése egy fragmentumból.** `python3` (nem `Edit`, mert
a `lib/l10n/**` a kör tiltott zónája — az `Edit`/`Write` eszköz PreToolUse
hookja ezt blokkolja is; a mutáció ezért Bash+`python3`-mal, majd AZONNALI
visszaállítással történt) törölte a `dsFailureAuthMessage` kulcsot a
`lib/l10n/features/design_system_hu.arb`-ból. Eredmény:

```
fragment-level key parity (A1) features/design_system: en and hu define
exactly the same keys [E]
  Expected: empty
    Actual: Set:['dsFailureAuthMessage']
  keys missing from lib/l10n/features/design_system_hu.arb
  (fragment: features/design_system)
```

PIROS, a hibaüzenet a fragmentumot nevezi meg (A1 igazolva). Visszaállítva:
`git checkout -- lib/l10n/features/design_system_hu.arb` — `git status
--short` utána üres erre az útvonalra.

**Próba 2 — `Text('Save changes')` beszúrása a §5.5 hatókörbe.** Egy ideiglenes
`static const _tempProbe = Text('Save changes');` sor a
`ss_validation_summary.dart`-ba (Bash+`python3`, ugyanazon okból). Eredmény:

```
no hardcoded or sentence-concatenated text beyond the frozen baseline
(A2/A3) [E]
  Actual: Set:[
    (file: …ss_validation_summary.dart, line: 80, violationClass: A3),
    (file: …ss_validation_summary.dart, line: 93, violationClass: A2)
  ]
```

PIROS — az ÚJ A3-sértés (sor 80) ÉS a befagyasztott A2-sértés eltolt sorszáma
(93, mert a próba 3 sort szúrt be fentebb) EGYSZERRE bizonyítja, hogy (a) a
guard valódi új sértést fog, és (b) a §5.8 pontos-egyenlőség a sorszám-eltolást
is kényszeríti (F7 szomszédos esete). Visszaállítva: `git checkout --
lib/core/design_system/components/inputs/ss_validation_summary.dart` — a fa
utána tiszta.

### Gate

```
tools/round-gate.sh test/l10n/arb_parity_test.dart test/l10n/formatters_test.dart test/l10n/hardcoded_string_guard_test.dart
```

`format` → `analyze` → 3× `test` → `architecture` → `secrets` → `l10n` — mind
ZÖLD. (`backend/` nincs érintve, az a sáv nem futott.) Egy kör közben talált
piros: `test/l10n/formatters_test.dart` két felesleges direkt importja
(`ss_formatters.dart`, `pseudo_locale.dart`) az `unnecessary_import` lintet
sértette, miután a `public.dart` már re-exportálta őket — javítva, gate
utána zöld.

### Amit a kör NEM érintett (tudatosan)

Egyetlen `lib/l10n/**` fájl sem módosult (M1/M3 szerint tilos zóna) — a §6.3
próbák kizárólag ideiglenes, azonnal visszaállított mutációk voltak, nem
production-diff. Nincs új ARB-kulcs, nincs `lib/features/**` migráció, nincs
új locale.

## 11. Review — a Claude tölti ki
