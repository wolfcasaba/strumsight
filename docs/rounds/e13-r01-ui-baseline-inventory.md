# E13-R01 — UI baseline inventory és screenshot corpus

- **Státusz:** IN PROGRESS — pre-flight mérve és commitolásra kész
  (2026-08-21, `main @ 30c78d9a`; eredeti brief: `main @ 17670d4f`)
- **Típus:** **Chapter 13 program-nyitó kör** (UI/UX Design System)
- **Kör-azonosító:** `E13-R01`. Az `E13` a **FEJEZETET** jelöli, nem epicet
  (az epicek E01–E10) — mint az `E99` és az `E14`.
- **Branch:** `<motor>/e13-r01-ui-baseline-inventory`
- **Előfeltétel:** a Chapter 13 a repóban (`e90edaa2`)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [0376](../adr/0376-ui-baseline-inventory-contract.md)
  — a baseline mérési és screenshot-corpus szerződése.

## 0.0 Pre-flight revízió (ADR 0112 self-heal, E13-R01/H3, 2026-08-21)

**Mért gyökérok — Class B brief-tartalmi ellentmondás.** A Chapter 13 Kör 1
feladata név szerint legalább a Live, Tuner, Analyze, Learn, Library, Settings
és onboarding fő állapotának compact-portrait referencia screenshotját kéri,
a kötelező teszt pedig előírja, hogy a képek megnyithatók és nem üresek
(`docs/sdd/13-chapter-13-ui-ux-design-system.md:6159–6172`). Az eredeti brief
ezzel szemben sem screenshot-fájlt, sem corpus-validáló tesztet nem engedett az
`allowed_paths`-ban, és az A1 miatt `lib/**` továbbra is helyesen tiltott. A
halt implementer-dispatch előtt történt; product diff és kör-PR nem keletkezett.

**Feloldás.** A szerződést nem szűkítjük és alkalmazáskódot nem nyitunk meg.
Az alábbi hét, név szerinti PNG és az egyetlen corpus-validáló Flutter-teszt
kerül a scope-ba. A könyvtár egésze nem engedélyezett; további screenshothoz
új brief-revízió kell.

```
docs/ui/baseline/screenshots/live-compact-portrait.png
docs/ui/baseline/screenshots/tuner-compact-portrait.png
docs/ui/baseline/screenshots/analyze-compact-portrait.png
docs/ui/baseline/screenshots/learn-compact-portrait.png
docs/ui/baseline/screenshots/library-compact-portrait.png
docs/ui/baseline/screenshots/settings-compact-portrait.png
docs/ui/baseline/screenshots/onboarding-compact-portrait.png
test/ui/ui_baseline_screenshot_test.dart
```

A teszt a hét exact fájlt enumerálja, mindegyik PNG-t
`decodeImageFromList`-tel ténylegesen dekódolja, pozitív byte- és
pixelméretet, valamint compact portrait (`width < height`) képarányt követel.
A screenshotok fix, dokumentált viewportból és offline/determinisztikus
fake-ekkel renderelt production screen-widgetekből készülnek; a teszt normál
gate-ben csak a commitolt corpus szerkezeti épségét méri. A képek tartalmát a
független review mind a hét fájl megnyitásával ellenőrzi. Ez bizonyítja az SDD
követelményét pixel-golden platformfüggés bevezetése nélkül.

**Self-heal regressziós őr:**
`tools/tests/test_e13_r01_screenshot_scope.py`. A valódi brief parserrel és
scope-audittal méri az exact 7+1 bővítést, a screenshot-teszt gate-be kerülését
és azt, hogy egy nyolcadik testvérkép továbbra is scope-sértés. A javítás előtt
4/5 cella piros volt, utána mind az öt zöld.

**Visszakeresett előzmény.** A kötelező
`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5
"E13-R01 screenshot corpus exact allowed_paths H3 brief scope"` lekérdezés
elsődleges találata az **L270**: az acceptance és az `allowed_paths` belső
ellentmondását a lint önmagában nem fogja meg, ezért pre-flightban minden
deliverable-útvonalat keresztellenőrizni kell. Az L277/L242 találatok más
topológiájú interface/fixture scope-rések, az E99-R16 H3 pedig tiltott
`.github/**` mérce-út volt; egyik sem indokol tágabb feloldást. A promptban
adott hasonló esetek közül az E07-R29/L327 exact scope-bővítési mintája illik;
az E99-R08 review-report mentesség és az E07-R25 Vision evidence contract nem.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd újra a §2 számait
> (képernyők, hex-találatok), mert az Epic 7 közben új képernyőket ad hozzá.
> A brief §2 értékei `main @ 17670d4f`-en készültek. Eltérésnél §0.0 revízió.

## 0.1 Aktuális orchestrátor pre-flight (2026-08-21, `main @ 30c78d9a`)

**Avuló tények újramérve.** A `find lib/features -type f -name
'*_screen.dart' | sort` parancs **58** production screen-fájlt ad: az eredeti
51-es baseline óta hét új képernyő került a fába. A
`rg -l 'Color\(0x[0-9A-Fa-f]+' lib/features | sort` továbbra is **9** fájlt
ad. A `lib/core/theme/` változatlanul négy fájlt tartalmaz,
`lib/core/design_system/` és `docs/ui/` továbbra sem létezik. A központi
`AppRoutes` katalógusban és az éles `GoRouter` regisztrációban egyaránt **40**
route van; a flag-gelt route-csoportok tényleges inputjai az
`app_router.dart`-ban visszakeresett nyolc `FeatureFlags` mező. A brief nem ír
elő acceptance-célstátuszt vagy erőforrás-tulajdonlás-változást, ezért az
input→státusz és `.acquire(` mérés erre a read-only baseline-körre nem
alkalmazható.

**Brief-lint és scope.** A kapott strict lint-jelentés nem tartalmaz leletet;
az aktuális briefre futtatott `python3 tools/brief-lint.py --brief
docs/rounds/e13-r01-ui-baseline-inventory.md --level strict` szintén tiszta,
a `tools/gateguard-scan.py` pedig nem talált védett mérce-útvonalat. A H3
self-heal exact hét PNG + egy validátor scope-ja változatlanul szükséges és
elégséges; `lib/**` nem nyílik meg.

**Visszakeresett előzmény.** A kötelező, először szűkített, majd teljes
korpuszos RAG-futtatás az [ADR 0059](../adr/0059-central-route-catalogue-and-validated-navigation.md)
központi route-katalógusát, az **L371** exact screenshot-corpus scope-leckét
és az E13-R01/H3 lezárt haltot hozta fel. Az index `6aad0bff` commiton állt,
azaz két committal elavult volt a `30c78d9a` HEAD-hez képest; ezért a találatok
csak előzményként szolgálnak, az aktuális számokat közvetlenül a kódból mértük.
Az ADR-számot a foglaló adta: `tools/round-slots.py reserve-adr --round
E13-R01` → **0376**.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tool/ui_inventory.dart",
  "docs/ui/README.md",
  "docs/ui/migration-status.md",
  "docs/ui/baseline/route-map.md",
  "docs/ui/baseline/token-debt.md",
  "docs/ui/baseline/accessibility-findings.md",
  "docs/ui/baseline/screenshots/live-compact-portrait.png",
  "docs/ui/baseline/screenshots/tuner-compact-portrait.png",
  "docs/ui/baseline/screenshots/analyze-compact-portrait.png",
  "docs/ui/baseline/screenshots/learn-compact-portrait.png",
  "docs/ui/baseline/screenshots/library-compact-portrait.png",
  "docs/ui/baseline/screenshots/settings-compact-portrait.png",
  "docs/ui/baseline/screenshots/onboarding-compact-portrait.png",
  "test/ui/ui_inventory_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
  "docs/rounds/e13-r01-ui-baseline-inventory.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
  "test/ui/ui_baseline_screenshot_test.dart",
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

## 1. Cél

A jelenlegi felület, route-ok, komponensek és accessibility-állapot
**dokumentált baseline-ja — módosítás nélkül** (SDD Ch13 Kör 1).

## 2. Jelenlegi állapot — mért tények (`main @ 30c78d9a`)

| mérés | érték |
|---|---|
| `lib/core/design_system/` | **nem létezik** — a Kör 2 hozza létre |
| `lib/core/theme/` | `app_colors.dart`, `app_palette.dart`, `app_theme.dart`, `theme_mode_provider.dart` |
| `*_screen.dart` a `lib/features` alatt | **58** |
| közvetlen `Color(0x…)` a feature-ökben | **9 fájl** |
| `docs/ui/` | **nem létezik** |
| `AppRoutes` / regisztrált `GoRoute` | **40 / 40** |

A Ch13 §2 kanonikus színalapjai (`#D98A46` copper, dark/light felületek,
confidence-színek) **nem cserélendők le** — a fejezet feladata, hogy
szemantikai tokenekké fejlessze őket.

## 3. Scope

**Benne van:** a képernyők, route-ok, dialógusok, bottom sheetek és
újrahasznosított widgetek inventárja · route-térkép a jelenlegi és cél-route-okkal,
redirect- és deep-link kockázatokkal · **token-adósság** felmérése (közvetlen
hex, hardkódolt spacing, közvetlen `TextStyle`, duplikált button/card/empty-state
minták, cross-feature UI-importok) · semantics-, overflow- és text-scale audit
**leletlistaként** · a §0.0 szerinti hét compact-portrait baseline screenshot és
azok szerkezeti validátora · `docs/ui/README.md` és `migration-status.md`.

**NINCS benne (tilos):**

- **Bármilyen alkalmazáskód-módosítás.** A kör felmér, nem javít (A1).
- Automatikus refaktor a talált leletekre.
- `lib/**` bármely fájlja.
- `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/ui_inventory.dart` | **ÚJ** — determinisztikus inventár-generátor |
| `docs/ui/README.md` | **ÚJ** — a design-rendszer belépője |
| `docs/ui/migration-status.md` | **ÚJ** — képernyőnkénti migrációs állapot |
| `docs/ui/baseline/route-map.md` | **ÚJ** — jelenlegi ↔ cél route-ok |
| `docs/ui/baseline/token-debt.md` | **ÚJ** — a mért token-adósság |
| `docs/ui/baseline/accessibility-findings.md` | **ÚJ** — a leletlista |
| `docs/ui/baseline/screenshots/{live,tuner,analyze,learn,library,settings,onboarding}-compact-portrait.png` | **ÚJ, hét exact fájl** — az SDD-ben név szerint kért regressziós baseline-ok |
| `test/ui/ui_inventory_test.dart` | **ÚJ** — a generátor determinizmusa |
| `test/ui/ui_baseline_screenshot_test.dart` | **ÚJ** — a hét exact PNG dekódolhatósága, nem-üressége és portrait alakja |
| `docs/rounds/e13-r01-…md` | a §10 handoff |

**Tilos zóna:** `lib/**` (MINDEN) · `docs/adr/**` · `docs/sdd/**` ·
`tools/**` · `.github/**` · `test/**` a `test/ui/` kivételével.

## 5. Kötött architekturális döntések

### 5.1 A kör NULLA alkalmazáskódot módosít

Ez felmérő kör. A talált hibákat **rögzíti**, nem javítja — a javítás a
későbbi körök dolga, hogy a baseline mérhető maradjon.

**NEM elfogadható gyengítés:** „ezt az egy overflow-t útközben javítottam".
Akkor a baseline nem a valódi kiindulást írja le.

### 5.2 Az inventár DETERMINISZTIKUS

Ugyanaz a fa ugyanazt az inventárt adja — rendezett kimenet, nem
könyvtár-bejárási sorrend. Enélkül a későbbi diffek zajosak lennének.

### 5.3 A screenshot corpus REGRESSZIÓS baseline, nem design

A Ch13 kifejezetten kimondja: a felvett képernyőképek nem a célállapotot
mutatják. A dokumentumnak ezt ki kell mondania, hogy senki ne tekintse
jóváhagyott designnak.

A corpus pontosan a §0.0-ban felsorolt hét compact-portrait főállapot. A
commitolt PNG-knek valódi production screen-widgetből, fix viewporttal és
offline/determinisztikus fake-ekkel kell készülniük; placeholder, kézzel rajzolt
mock vagy üres felület nem fogadható el. A normál CI a hordozható strukturális
invariánsokat méri, a reviewer pedig mind a hét képet ténylegesen megnyitja.

### 5.4 A route-térkép a MIGRÁCIÓ kockázatait is rögzíti

Nem elég a jelenlegi és cél-route párokat felsorolni: a deep-link és redirect
kockázatot is meg kell nevezni (a Ch13 §7.5 tizenkét legacy route-ot sorol).

### 5.5 Az accessibility-leletek PRIORITÁSSAL, nem nyers listaként

Minden lelethez tartozzon súlyosság és érintett képernyő, hogy a későbbi
körök sorrendezhessenek.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | **Nulla `lib/**` módosítás** | `git diff --stat` |
| A2 | Az inventár determinisztikus (kétszeri futtatás azonos kimenet) | `ui_inventory_test.dart` |
| A3 | Minden production képernyő szerepel az inventárban | a mért 58 `*_screen.dart` lefedve |
| A4 | A route-térkép tartalmazza a legacy ↔ cél párokat és a deep-link kockázatot | review |
| A5 | A token-adósság mérve (hex, spacing, TextStyle, duplikátumok, cross-feature import) | `token-debt.md` |
| A6 | Az accessibility-leletek prioritással szerepelnek | `accessibility-findings.md` |
| A7 | A dokumentum kimondja, hogy a screenshot NEM design-jóváhagyás | review |
| A8 | A hét név szerinti compact-portrait screenshot production screenből készült, megnyitható és nem üres | `ui_baseline_screenshot_test.dart` + mind a hét PNG manuális review-ja |
| A9 | A meglévő teszt-suite változatlanul zöld | `tools/round-gate.sh` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Útközben javított" overflow vagy szín | **A1** |
| Könyvtár-bejárási sorrendű kimenet | **A2** |
| Az inventár kihagy képernyőket | A3 |
| A route-térkép csak a jelenlegit sorolja | A4 |
| A leletek súlyosság nélkül | A6 |
| A screenshot designként hivatkozva | A7 |
| Hiányzó, üres, sérült vagy nem portrait corpus-kép | **A8** |

**Az inventár-teljesség három kötelező cellája** (a küszöb: a production képernyő):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | teszt- vagy fixture-widget | **nincs** az inventárban |
| rajta (a küszöbön) | flag mögötti, de production képernyő | **benne van**, flag-jelöléssel |
| a küszöb fölött | élő production képernyő | benne van, UI-azonosítóval vagy legacy jelöléssel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** tedd az inventár
kimenetét bejárási sorrendűvé → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/ui/ui_baseline_screenshot_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `tool/ui_inventory.dart` — determinisztikus, rendezett kimenet.
2. `test/ui/ui_inventory_test.dart` — a determinizmus cellái.
3. `test/ui/ui_baseline_screenshot_test.dart` — a hét exact production
   screen-state fix compact-portrait viewporttal; normál módban corpus-validálás.
4. A hét `docs/ui/baseline/screenshots/*-compact-portrait.png` felvétele és
   mindegyik kézi megnyitása; a viewport/fake/state recipe dokumentálása a
   `docs/ui/README.md`-ben.
5. `docs/ui/baseline/route-map.md` — legacy ↔ cél, kockázatokkal.
6. `docs/ui/baseline/token-debt.md` — a mért adósság.
7. `docs/ui/baseline/accessibility-findings.md` — prioritásos leletek.
8. `docs/ui/README.md` + `migration-status.md`.
9. A valódi-sértés próbák, §10-be dokumentálva.
10. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „gyorsan javítom" kísértés.** Egy felmérő körben minden lelet
  javításra hív — és a baseline elveszik (A1).
- **A nem determinisztikus kimenet.** Csak a második futtatásnál derül ki,
  és minden későbbi diffet zajossá tesz (A2).
- **A screenshot félreértése.** Ha designként hivatkoznak rá, a Ch13
  célállapota összekeveredik a jelenlegivel (A7).
- **A corpus látszat-teljesítése.** Egy érvényes PNG lehet üres vagy kézzel
  rajzolt mock is; ezért a strukturális A8 teszt mellett a reviewer mind a hét
  képet megnyitja, és a production-widget capture recipe-t is ellenőrzi.

## 10. Implementation handoff — az implementer tölti ki

### Fájlonkénti összefoglaló

- `tool/ui_inventory.dart` — rendezett, read-only production screen,
  reusable widget/view és overlay-forrás inventár; a 58/96/16 mért baseline-t
  Markdownként is kiadja.
- `test/ui/ui_inventory_test.dart` — kétszeri kimenet-azonosságot, a 58
  production screenet, rendezést, test-tree kizárást és immutable eredményt
  ellenőriz.
- `test/ui/ui_baseline_screenshot_test.dart` — exact hét PNG dekódolás,
  pozitív byte/pixelméret és portrait validátor; külön, opt-in capture-út a
  production screen-widgetekhez.
- `docs/ui/README.md` — corpus-használat és a 390×844, in-memory fake-es
  capture recipe; kimondja, hogy a corpus nem design-jóváhagyás.
- `docs/ui/migration-status.md` — a teljes screen-állomány legacy státusza és
  a generátor canonical inventory-hivatkozása.
- `docs/ui/baseline/route-map.md` — mind a 40 jelenlegi route célroute-ja,
  flag/redirect/deep-link kockázata.
- `docs/ui/baseline/token-debt.md` — mért hex-, spacing-, TextStyle- és
  komponensadósság.
- `docs/ui/baseline/accessibility-findings.md` — prioritásos text-scale,
  overlay-, compact-layout- és nem-szín-alapú állapot-audit backlog.
- `docs/ui/baseline/screenshots/{live,tuner,analyze,learn,library,settings,onboarding}-compact-portrait.png`
  — a hét név szerinti production-widget, compact-portrait baseline.

### Futtatott bizonyítás

- RED: az új inventory teszt a hiányzó `tool/ui_inventory.dart` importtal
  fordítási hibával állt meg; az implementáció után zöld lett.
- Screenshot capture: `flutter test --update-goldens
  --dart-define=CAPTURE_UI_BASELINE=true
  test/ui/ui_baseline_screenshot_test.dart` → 1 passed, 1 skipped. A hét PNG
  elkészült, és mind a hét fájlt kézzel megnyitottam.
- Valódi-sértés próba: a `..sort()` eltávolítása után
  `flutter test test/ui/ui_inventory_test.dart` PIROS lett: az első elem
  `streak_screen.dart` volt az elvárt rendezett `ai_tutor/...` helyett.
  A rendezés visszaállítása után a célteszt újra zöld.
- Záró gate: `tools/round-gate.sh test/ui/ui_inventory_test.dart
  test/ui/ui_baseline_screenshot_test.dart` → zöld. Az első gate-futtatás
  szándékolatlanul formázatlan `ui_inventory_test.dart` miatt a format lépésen
  megállt; `dart format` után a teljes, változatlan gate újrafutott és zölden
  zárt.

### Eltérések és nem futtatott ellenőrzések

- `lib/**` nem módosult. CI-dispatch, PR, push és APK-build nem futott: ezek
  az orchestrátor/reviewer feladatai és ezen implementer-kör scope-ján kívül
  vannak.
- A normál corpus-teszt szándékosan nem pixel-golden összehasonlítás; a
  hordozható szerkezeti invariánsokat méri. A corpus eredetét a capture-recept
  és a hét manuális megnyitás bizonyítja.

## 11. Review — a Claude tölti ki
