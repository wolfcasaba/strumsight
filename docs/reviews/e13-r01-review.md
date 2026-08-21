# E13-R01 — Review

Brief: `docs/rounds/e13-r01-ui-baseline-inventory.md`
Diff: `6570b678409e..ce190827951b`
Reviewer: Codex Sol (független a Terra implementertől) · Dátum: 2026-08-21
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 4 · MINOR: 0 · NOTE: 1

Az implementer-jelzés scope-auditja `ok` volt, és a kézi audit ugyanezt adta
16 engedélyezett útvonalra. A végleges commit kötelező gate-je azonban izolált
klónban reprodukálhatóan 10 perces timeouttal piros; a handoff zöld állítása
nem támasztható alá a loggal. A dokumentációban ezen felül egy route-paraméter,
két token-adósság számlálás és két vizuálisan megfigyelt compact-overflow
hiányzik vagy pontatlan.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Nulla `lib/**` módosítás | ✅ | `git diff --name-only 6570b678..HEAD -- lib` → üres |
| A2 | Determinisztikus inventory | ✅ | `ui_inventory_test.dart`; a reviewer eltávolította a `..sort()`-ot → a teszt PIROS lett az első elemen, visszaállítás után a klón tiszta |
| A3 | Mind az 58 production screen szerepel | ✅ | `dart run tool/ui_inventory.dart` → 58 screen, 96 reusable widget/view, 16 overlay-forrás |
| A4 | Legacy ↔ cél route-map és kockázatok | ❌ | F2: a 40-ből egy current path elveszti a `:songId` paramétert |
| A5 | Token-adósság mérve | ❌ | F3: a közölt occurrence-számok nem reprodukálhatók az exact kereséssel |
| A6 | Prioritásos accessibility-leletek | ❌ | F5: a megnyitott Tuner/onboarding corpuson látható compact overflow nincs képernyőszintű leletként rögzítve |
| A7 | Screenshot nem design-jóváhagyás | ✅ | `docs/ui/README.md:3-5` |
| A8 | Hét production-state screenshot megnyitható és nem üres | ❌ | mind a hét PNG megnyílt, de F1 miatt a strukturális teszt piros; F4 miatt a corpus Ahem-blokkokkal tér el a production tipográfiától |
| A9 | Kötelező round-gate zöld | ❌ | izolált klón gate: lépés 1–3 zöld, lépés 4 timeout és exit 10 |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e13-r01-FmVelX --brief
docs/rounds/e13-r01-ui-baseline-inventory.md --base 6570b678...` →
`Legacy scope audit OK (..., 16 changed path(s), 0 generated/ignored)`.
Engedélyezett fájlokon kívüli implementer-változás nincs. A pre-flight ADR és
brief-revízió az implementer launch-HEAD (`6570b678`) része.

## Megállapítások

### F1 — BLOCKER — A kötelező screenshot-validátor 10 perc után timeoutol

- **Fájl:** `test/ui/ui_baseline_screenshot_test.dart:31-68`
- **Probléma:** a normál corpus-teszt `testWidgets` fake-async környezetében
  közvetlenül vár a `decodeImageFromList` future-re. A végleges `ce190827`
  commit izolált klónjában a teszt pontosan 10:00 után `TimeoutException`-nel
  piros. Egy eldobható `tester.runAsync(() => decodeImageFromList(bytes))`
  próba ugyanígy timeoutolt, tehát ez önmagában nem elegendő javítás.
- **Hatás:** A8/A9 és az ADR 0052 zöld kapuja nem teljesül; a handoff „zöld"
  állítása hamis bizonyíték. Az implementer logja csak a gate `exec` indítását
  tartalmazza, terminális kimenetet nem.
- **Kötelező javítás:** tartsd meg a brief szerinti `decodeImageFromList`
  tényleges dekódolást, de olyan binding/test-struktúrában hajtsd végre, amely
  determinisztikusan befejeződik. Adj explicit, rövid teszt-timeoutot vagy
  cellaszintű bizonyítást, hogy a regresszió ne 10 perc után jelezzen.
- **Ellenőrzés:** a teljes `tools/round-gate.sh test/ui/ui_inventory_test.dart
  test/ui/ui_baseline_screenshot_test.dart` terminális exit 0-val zárjon friss
  izolált klónban.
- **Státusz:** OPEN

### F2 — MAJOR — A route-map elveszíti a `songTrainerResult` path-paraméterét

- **Fájl:** `docs/ui/baseline/route-map.md:37`
- **Probléma:** a baseline `/song-trainer/result`-ot ír, miközben a kanonikus
  `AppRoutes.songTrainerResult` értéke `/song-trainer/result/:songId`
  (`lib/app/routing/app_route.dart:30`).
- **Hatás:** a migrációs térkép pont a deep-link/paraméter kockázatot rögzíti
  hibásan, így A4 nem teljesül mind a 40 route-ra.
- **Kötelező javítás:** írd át az exact current pathot és a kockázatban nevezd
  meg a `songId` path-paraméter + `SongTrainerResult` extra kettős contractot.
- **Ellenőrzés:** hasonlítsd össze gépileg vagy tételesen mind a 40
  `AppRoutes` stringet a táblázat current-route oszlopával.
- **Státusz:** OPEN

### F3 — MAJOR — A token-adósság „occurrence” számai nem reprodukálhatók

- **Fájl:** `docs/ui/baseline/token-debt.md:8-10`
- **Probléma:** az exact `rg -o 'Color\(0x[0-9A-Fa-f]+' lib/features |
  wc -l` **28** előfordulást ad, nem 26-ot; a 26 a találatot tartalmazó sorok
  száma. Az exact `rg -o 'SizedBox\(|EdgeInsets\.' lib/features | wc -l`
  **817**, nem 752. A dokumentum a mérési parancsokat sem rögzíti, ezért a
  számok jelentése nem auditálható.
- **Hatás:** A5 mért baseline-ja pontatlan; a későbbi token-migráció hamis
  kiinduló értékhez mérne.
- **Kötelező javítás:** válassz és dokumentálj exact, reprodukálható queryt
  minden számlálóhoz; az oszlopnevet igazítsd a mért egységhez (előfordulás
  vagy érintett sor), majd frissítsd a számokat.
- **Ellenőrzés:** a dokumentált parancsok kimenete egyezzen a táblával az
  aktuális HEAD-en.
- **Státusz:** OPEN

### F4 — MAJOR — A corpus nem a production tipográfiát rendereli

- **Fájl:** `test/ui/ui_baseline_screenshot_test.dart:70-150`,
  `docs/ui/README.md:9-24`, hét `docs/ui/baseline/screenshots/*.png`
- **Probléma:** mind a hét megnyitott PNG-ben a szöveg Ahem tesztfont-blokkokként
  jelenik meg. A capture Flutter widget-testje `--use-test-fonts` alatt fut,
  de nem tölti be a `pubspec.yaml`-ban deklarált Poppins/Montserrat app-fontot.
  A README ezt production-screen rasterként írja le, a tipográfiai eltérést
  nem dokumentálja.
- **Hatás:** a Chapter 13 tipográfia-, text-scale- és overflow-baseline-ja nem
  hasonlít a production UI-ra; szövegtördelési regressziókhoz félrevezető
  referencia.
- **Kötelező javítás:** a capture előtt determinisztikusan töltsd be az app
  meglévő font assetjeit (új asset/scope nélkül), regeneráld mind a hét PNG-t,
  és nyisd meg őket újra. A strukturális normál teszt ne regeneráljon képet.
- **Ellenőrzés:** manuális review-ban a hét képen olvasható production betűk
  látszanak, nem homogén Ahem téglalapok; a capture recipe továbbra is
  offline/determinisztikus.
- **Státusz:** OPEN

### F5 — MAJOR — A látható compact overflow-k nem kerültek a leletlistába

- **Fájl:** `docs/ui/baseline/accessibility-findings.md:6-13`,
  `tuner-compact-portrait.png`, `onboarding-compact-portrait.png`
- **Probléma:** a reviewer mind a hét képet megnyitotta; a Tuner és onboarding
  jobb felső sarkában render-overflow figyelmeztető sáv látható. A leletlista
  csak általánosan mondja, hogy a small-phone coverage hiányos, és azt állítja,
  hogy egyedi flow-ról nem állít hibát.
- **Hatás:** az előírt tényleges overflow-audit két közvetlenül megfigyelt,
  képernyőszintű leletet elveszít; A6 nem teljesül.
- **Kötelező javítás:** rögzítsd külön, prioritással a Tuner és onboarding
  390×844 baseline-on megfigyelt overflow-ját, a corpus fájlt mint evidence-et
  megadva. A production kódot ebben a körben továbbra se javítsd.
- **Ellenőrzés:** a dokumentum képernyőnként megnevezi mindkét leletet és a
  későbbi reprodukció viewportját.
- **Státusz:** OPEN

### F6 — NOTE — Az A2 valódi-sértés próba működik

- **Fájl:** `tool/ui_inventory.dart:14-23`, `test/ui/ui_inventory_test.dart:17`
- **Bizonyíték:** a reviewer ideiglenesen eltávolította a `..sort()`-ot. A
  célteszt az első elemen piros lett (`streak_screen.dart` az elvárt
  `ai_tutor/...` helyett); a változtatás eldobva, a review-klón tiszta.
- **Státusz:** FIXED (nincs production javítás; falszifikációs bizonyíték)

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ 1730 fájl, 0 változás |
| analyze | zöld | ✅ `No issues found` |
| `ui_inventory_test.dart` | zöld | ✅ 1 teszt; mutáció piros |
| `ui_baseline_screenshot_test.dart` | zöld | ❌ 10 perces timeout, exit 1 |
| architecture | zöld | ❌ a gate a piros céltesztnél fail-fast megállt |
| CI teljes suite + property | még nem indult | ❌ |

## Merge-döntés

Az ADR 0052 szerint merge tilos. F1–F5 javítására ugyanaz a Terra motor kap
egy javító kört; utána friss izolált klónban a teljes gate, a hét PNG manuális
review-ja és leletenkénti re-review kötelező.
