# E13-R11 — Action, input és form komponenskészlet

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 11
- **Kör-azonosító:** `E13-R11`
- **Branch:** `<motor>/e13-r11-actions-and-forms`
- **Előfeltétel:** `E13-R10` merge-elve (aszinkron állapotok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a normatív forrás a Ch13 **§11.2 + §13.1 +
  §14** (a brief eredeti „§9.11" hivatkozása nem létező szakasz, lásd §0.0/D1).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R05 `SsSpacing` és
> az R07 `SsIcon` TÉNYLEGES API-ját — a gomb- és mezőméretek ezekből jönnek,
> nem új konstansokból. Eltérésnél §0.0 revízió.
>
> ✅ **A pre-flight LEFUTOTT** (2026-08-24, `main @ 8f88fc39`) — az eredménye a
> **§0.0** nyolc pontja (D1–D8). Az implementer azt a szakaszt a §5-tel azonos
> súllyal olvassa: a **D2** (ARB-fragmentum) és a **D3** (katalógus-teszt)
> figyelmen kívül hagyása determinisztikusan piros gate-et ad.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/design_system/components/actions/ss_button.dart",
  "lib/core/design_system/components/actions/ss_icon_button.dart",
  "lib/core/design_system/components/inputs/ss_text_field.dart",
  "lib/core/design_system/components/inputs/ss_switch_row.dart",
  "lib/core/design_system/components/inputs/ss_choice.dart",
  "lib/core/design_system/components/inputs/ss_value_slider.dart",
  "lib/core/design_system/components/inputs/ss_validation_summary.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "lib/l10n/features/design_system_en.arb",
  "lib/l10n/features/design_system_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/core/design_system/forms/ss_button_test.dart",
  "test/core/design_system/forms/ss_inputs_test.dart",
  "test/property/design_system/slider_numeric_sync_test.dart",
  "docs/rounds/e13-r11-actions-and-forms.md",
]
gate_tests = [
  "test/core/design_system/forms/ss_button_test.dart",
  "test/core/design_system/forms/ss_inputs_test.dart",
  "test/property/design_system/slider_numeric_sync_test.dart",
  "test/core/design_system/component_catalog_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió — MÉRVE 2026-08-24, `main @ 8f88fc39`

A brief 2026-08-15-én készült (`main @ 93a6c19a`). Az alábbi hét pont a
tényleges kódon mérve tér el a brief szövegétől; a lista **szűkítés + két
generált-forrás felvétele**, nem hatókör-tágítás (D2 indoklása lent).

### D1 — ADR: ez a kör NEM ír ADR-t

A sor-fájl ADR-oszlopa `nincs` (`docs/execution/pipeline-queue.tsv:426`), és a
Ch13 ADR-jei (0273–0282) az `a4fdfec2` commitban ELŐRE meg lettek írva és
merge-elve. Ugyanez a minta futott az E13-R08 (0275), E13-R09 (0276) és
E13-R10 (0277) körökön — az E13-R10 a foglalótól kapott `0416`-ot
felhasználatlanul hagyta. Ezért **ADR-számot nem foglalunk**, és a
`docs/adr/**` TILOS zóna marad.

**A brief §9.11-hivatkozása elavult** (E07-R21/H2 hibaosztály: a glossza mást
mond, mint a hivatkozott forrás). Mérve: a Ch13 §9 a **§9.8-cal ér véget**
(`grep -n "^#\{2,4\} 9" docs/sdd/13-chapter-13-ui-ux-design-system.md` →
9.1…9.8), §9.11 **nem létezik**. A kör tényleges normatív forrásai:

| Szakasz | Mit köt |
|---|---|
| **§11.2 Action és input** (780–811. sor) | a komponenslista |
| **§13.1 Minimum** (936–949. sor) | 48×48 dp cél, logikus fókuszsorrend, 200% text scale, külső billentyűzet, **„nem csak színnel jelzett állapot"** (= az A5 gyökere) |
| **§14 Lokalizáció** (975–992. sor) | minden user-facing string ARB-ba |
| **§10 Mappastruktúra** (733–779. sor) | `components/actions/`, `components/inputs/`, `test/core/design_system/forms/` |

### D2 — Az ARB-aggregátum GENERÁLT; a kézzel írt forrás a fragmentum (ADR 0307 §4)

**Ez a brief így, változatlanul, determinisztikusan haltot adott volna.** A
`lib/l10n/app_{en,hu}.arb` 2026-08-20 óta **nem kézzel szerkesztett forrás**:
a `lib/l10n/base/app_<locale>.arb` + `lib/l10n/features/<név>_<locale>.arb`
determinisztikus uniója, amit a `tool/gen_l10n_segments.dart` ír
(`tool/gen_l10n_segments.dart:1-21`). A brief `allowed_paths`-a KIZÁRÓLAG az
aggregátumot sorolta fel — pontosan az a felállás, ami az **E08-R12/H6**-ot
adta: az aggregátumba írt kulcsokra a `--check` PIROS, a `--write` pedig
eldobja őket, mert egyetlen forrás-fragmentum sem tartalmazza. Ez a hibaosztály
**ötször** mért: `lessons/L365` (E08-R12, H6), `lessons/L369` (E08-R13, H3),
`lessons/L396` (E08-R20, `stopped`), és az E09-R21 kétszer. Gépi őre van:
`tools/tests/test_e08_r12_l10n_scope.py`, `test_e08_r13_l10n_scope.py`.

**Feloldás (az E13-R10 merge-elt mintája, `b11ab2ed`):**

- **Kézzel szerkesztett forrás:** `lib/l10n/features/design_system_{en,hu}.arb`
  — MÁR LÉTEZIK, az E13-R10 hozta létre (20-20 kulcs, `dsFailure*` prefix). Az
  új kulcsok (`kulcs` + `@kulcs` EGYÜTT, ugyanabból a fragmentumból — L342)
  ide mennek. Nyilvántartásba vétel nem kell: a generátor a könyvtárat
  globbolja (`listSegmentFiles`, `_<locale>.arb` végződés).
- **Az aggregátum MARAD az engedélyezett listán:** a `tools/scope-audit.py`-nak
  nincs generated-path kivétele, tehát a `--write` által átírt aggregátum
  enélkül `scope_audit=VIOLATION` lenne.
- **KÖTELEZŐ lépés a gate ELŐTT:** `dart run tool/gen_l10n_segments.dart --write`.
  Enélkül a `tools/round-gate.sh` `l10n` lépése (242–243. sor →
  `tool/ci/check_l10n_parity.dart`) „az aggregátum elavult" hibával piros.

### D3 — A Component Catalog MEGLÉVŐ tesztje nem szerkeszthető, ezért bekerül a gate-be

A `test/core/design_system/component_catalog_test.dart` **nincs** az
engedélyezett listán (nem is kerül rá: ez a mérce, nem a célfájl), viszont a
katalógusra három EXACT-COUNT állítást tesz az egész fán:

| Sor | Állítás |
|---|---|
| `component_catalog_test.dart:50` | `find.byType(SsCard)` → **pontosan 1** |
| `:51-54` | `SsCard` alatt `Material` → **pontosan 1** |
| `:78` | `find.byType(DecoratedBox)` → **pontosan 1** (mindkét témán) |

Az E13-R10 ezen MÉRT: az eredetileg tervezett `SsSkeleton`-demót el kellett
hagynia, mert az `SsSkeleton` maga is `DecoratedBox`-ot rendel, és ez a MEGLÉVŐ
zöld tesztet pirosra váltotta (E13-R10 §10). A jelen kör gombjai és mezői
(`Material`, `InputDecorator`, `Container(decoration:)`) ugyanebbe futnak bele.

**A csapda, amiért ez ide kerül:** ez a teszt a brief eredeti `gate_tests`
listáján NEM szerepelt, tehát a `round-gate.sh` NEM futtatta volna — a törés
csak a CI teljes suite-jában bukott volna ki, a kör-gate végig zölden. Ezért a
`gate_tests` **negyedik elemként** megkapja. A fájl továbbra sem szerkeszthető:
ha a katalógus-bővítés pirosra váltja, a **bővítést** kell visszavenni, nem a
tesztet átírni (§0 STOP-protokoll).

**Lokalizáció a katalógusban:** `AppLocalizations.of(context)` ott ELSZÁLL — a
teszt `localizationsDelegates` NÉLKÜLI `MaterialApp`-ban rendereli. A meglévő
minta a szinkron `lookupAppLocalizations(const Locale('en'))`
(`component_catalog_screen.dart:196`).

### D4 — 48 dp és 2.0 text scale MÁR nevesített konstans

A brief pre-flight-figyelmeztetése („a méretek az R05/R07-ből jönnek, nem új
konstansokból") mérve helytálló, de a pontos forrás nem az `SsSpacing`:

```
lib/core/design_system/foundations/ss_semantics.dart
  SsSemantics.minimumInteractiveDimension = 48
  SsSemantics.maximumTextScale = 2.0
```

Az A4 és az A6 **ezekre** hivatkozzon, ne új literálra. (`SsSpacing.space12`
szintén 48, de az egy SPACING-token — érintési célként hivatkozni fogalmi hiba.)
A §6.1 három cellájának 44 / 48 / 56 dp értéke teszt-BEMENET, nem token.

### D5 — Az `SsIcon` kétfaktoros: az `SsIconButton` a `decorative` ágat használja

Mérve (`lib/core/design_system/icons/ss_icon.dart:16-46, 100-115`): az
`SsIcon.interactive` kötelezően nem üres `semanticLabel`+`tooltip` párt kér
(különben `ArgumentError`), és **maga csomagolja** `Tooltip` +
`Semantics(label:, image: true, excludeSemantics: true)` fába.

Ha az `SsIconButton` ezt a gyárat teszi a SAJÁT gomb-semanticsába, egy
`image` semantics-csomópont kerül a `button` csomópont BELSEJÉBE, és a tooltip
duplikálódik. **Ezért:** az `SsIconButton` a glyphet `SsIcon.decorative`-val
rajzolja, a `tooltip`-et és a `Semantics(button: true, label: …)`-t maga
birtokolja. Ezt az A5 melletti önálló cella mérje (a gomb semantics-fájában
`image` flag NEM lehet).

### D6 — A property-teszt új alkönyvtára ELÉRHETŐ (mérve, nem feltételezve)

A `test/property/design_system/` lenne az ELSŐ alkönyvtár a `test/property/`
alatt (ma mind a 30+ property-teszt lapos). Mérve, hogy a randomizált HARD
lépés eléri: `.github/actions/flutter-gates/action.yml:45` →
`flutter test test/property` (könyvtár = rekurzív), és
`tools/round-pipeline.sh:2639` ugyanígy. **Nincs** lapos `test/property/*.dart`
glob a fában. Az útvonal tehát marad.

Seed-konvenció (a meglévő 30+ teszt mintája):
`final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;`

### D7 — Widget-tesztben a viewportot CSAK a `tester.view` méretezi

- **L452 (E13-R09):** a `MediaQuery(data: MediaQueryData(size: …))` wrapper
  **INERT a layoutra** — a deklarált geometria sosem áll elő, a cella a default
  800×600-on mér. Az A4/A6 celláihoz `tester.view.physicalSize` +
  `devicePixelRatio`, `addTearDown(tester.view.reset)`-tel.
- **L453 (E13-R09):** a 2.0 text scale VALÓDI törést ad — `Row`-ban álló `Text`
  `Flexible` nélkül 661 px-t csordult túl. Az A6 szűk (360 dp) VALÓDI
  felületen mérjen, ne tágon.

### D8 — Visszakeresett előzmény (ADR 0312 / brief-lint S8)

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr` + teljes korpusz.
A kör mércéjét kötő leletek:

| Forrás | Amit köt |
|---|---|
| `lessons/L446` (E13-R07) | egy KONSTRUKTORBAN számolt mezőt mérő cella nem őrzi a mező FELHASZNÁLÁSÁT — az A3 property a tényleges vezérlő-utat járja be oda-vissza, ne egy közös tiszta függvényt |
| `lessons/L436` (E09-R15) | randomizált tesztben a csak az EGYIK ágon írt változó melletti `assert` a seed szerencséjéből zöld — MINDEN iteráció állítson |
| `lessons/L403` (E08-R23) | a valódi-sértés próba widget-TÍPUS szinten átengedi a tartalmi sértést — a próba a VISELKEDÉST mérje |
| `lessons/L142` (E04-R24) | %-küszöbös, kis mintás property HARD-seeden boundary-flaky — az A3 EXAKT invariánst mérjen, ne arányt |
| `lessons/L92` (E03-R16/H2) | a generátor precondition-jét indexszel őrizd, ne karakterkóddal |
| `lessons/L365`, `L369`, `L396` | a D2 l10n-hibaosztály |
| `lessons/L09`, `L05`, `L254` | a §7 gate-hívás alakja |
| `adr/0307 §4`, `adr/0411 §4-§6` | D2, illetve D5 |

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Gombok, mezők, választók, csúszkák és validáció egységes, **hozzáférhető**
implementációja (SDD Ch13 Kör 11).

## 2. Jelenlegi állapot — mért tények

- Az R03–R07 letette a színt, tipográfiát, geometriát, motiont és ikonokat —
  ez a kör kizárólag interakciót ad hozzá.
- A `PROPERTY_SEED` konvenció él: a `test/property/` seed nélkül 42-vel fut,
  a CI külön HARD lépésben véletlen seeddel (CLAUDE.md, HORIZON).
- A tempó a termék központi paramétere — a csúszka melletti pontos érték
  megadása nem kényelmi kérdés.

## 3. Scope

**Benne van:** primary / secondary / tertiary / destructive / icon gomb-variánsok
loading, disabled és focus állapottal · szöveg- és keresőmező, kapcsoló-sor,
rádió-sor, választó chip, szegmentált vezérlő · csúszka **pontos numerikus
bevitellel** párosítva (tempó, időtartam) · közös validációs összegzés és
mező-szintű hibaüzenet · billentyűzet, autofill, IME-akció és fókusz-bejárás ·
az „egy képernyő egy primary CTA" szabály és Stage Mode-beli kivétele.

**NINCS benne (tilos):** `lib/features/**` átállítása · a meglévő űrlapok
migrációja · `lib/core/theme/**` · új plugin · `docs/adr/**`, `tools/**`,
`.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `actions/ss_button.dart`, `ss_icon_button.dart` | **ÚJ** — a gomb-variánsok |
| `inputs/ss_text_field.dart` | **ÚJ** — mező tartós labellel |
| `inputs/ss_switch_row.dart` | **ÚJ** — teljes sor érinthető |
| `inputs/ss_choice.dart` | **ÚJ** — rádió / chip / szegmens |
| `inputs/ss_value_slider.dart` | **ÚJ** — csúszka + pontos érték |
| `inputs/ss_validation_summary.dart` | **ÚJ** |
| `documentation/component_catalog_screen.dart` | állapot-mátrix (**D3 korlátaival**) |
| `public.dart` | az export bővítése |
| `lib/l10n/features/design_system_{en,hu}.arb` | **a validációs szövegek KÉZZEL írt forrása** (D2) |
| `lib/l10n/app_{en,hu}.arb` | a `--write` által GENERÁLT aggregátum — kézzel NEM szerkeszthető (D2) |
| `test/…/forms/*_test.dart` (2) | a §6 cellái |
| `test/property/design_system/slider_numeric_sync_test.dart` | a szinkron-property |
| `docs/rounds/e13-r11-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Minden mezőnek TARTÓS labelje van

A placeholder nem label: gépelés közben eltűnik, és a felhasználó elveszti a
kontextust. Képernyőolvasóval pedig nincs mihez kötni a mezőt.

**NEM elfogadható gyengítés:** csak `hintText` „mert letisztultabb". Az a
mezőt azonosíthatatlanná teszi felolvasóval.

### 5.2 A loading gomb NEM ugrik méretben, és NEM enged dupla beküldést

A méret a leghosszabb állapothoz igazodik; a betöltés alatti második koppintás
nem indít újabb műveletet.

**NEM elfogadható gyengítés:** a felirat kicserélése spinnerre a méret
rögzítése nélkül. Ugráló elrendezést és véletlen dupla beküldést ad.

### 5.3 A csúszka mellett MINDIG megadható a pontos érték

Tempónál és időtartamnál a csúszka egyedül nem elég pontos. A két bevitel
**mindig szinkronban** van — ezt randomizált property méri, nem egy fixture.

**NEM elfogadható gyengítés:** csak csúszka, „úgyis elég közel lehet állítani".
120 helyett 118 BPM a gyakorláson mérhető különbség.

### 5.4 A kapcsoló TELJES sora érinthető

A 48 dp-s érintési cél a soron, nem csak a kapcsolón. Kis célpont mellett a
beállítás megbízhatatlanul kapcsol.

### 5.5 A destruktív gomb vizuálisan ÉS semanticsban elkülönül

Nem elég a piros szín: a semantics is jelzi a destruktív jelleget.

### 5.6 Egy képernyő — egy primary CTA

A kivétel a Stage Mode (transport), és ezt a dokumentáció kimondja.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden mezőnek tartós labelje van (nem csak hint) | `ss_inputs_test.dart` |
| A2 | A loading gomb mérete változatlan, és nem enged dupla beküldést | `ss_button_test.dart` |
| A3 | A csúszka és a numerikus bevitel MINDIG szinkronban van | `slider_numeric_sync_test.dart` (randomizált) |
| A4 | A kapcsoló teljes sora érinthető (≥ 48 dp) | `ss_inputs_test.dart` |
| A5 | A destruktív gomb semanticsban is elkülönül | `ss_button_test.dart` |
| A6 | `SsSemantics.maximumTextScale` (2.0) mellett nincs túlcsordulás, **360 dp-s valódi viewporton** (D7) | `ss_inputs_test.dart` |
| A7 | A fókusz-bejárás sorrendje a vizuális sorrendet követi | ugyanott |
| A8 | Minden új szöveg a **fragmentumban** születik (en + hu), és az aggregátum a `--write` kimenete (D2) | a gate `l10n` lépése + `git diff --stat lib/l10n/` |
| A9 | Az `SsIconButton` semantics-fája **gomb**, nem kép: nincs benne `image` flag, és a tooltip egyszer szerepel (D5) | `ss_button_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak `hintText`, label nélkül | **A1** |
| A gomb felirata spinnerre cserélve, méret nem rögzítve | **A2** |
| A második koppintás is beküld | A2 |
| A numerikus bevitel kerekítése eltér a csúszkáétól | **A3** |
| Csak a kapcsoló érinthető, a sor nem | A4 |
| A destruktív gomb csak piros (Ch13 §13.1: „nem csak színnel jelzett állapot") | A5 |
| Az `SsIconButton` `SsIcon.interactive`-ot ágyaz a saját gomb-semanticsába | **A9** |
| Az új kulcs csak az aggregátumba kerül, fragmentum nélkül | **A8** — a gate `l10n` lépése (D2) |
| A katalógus-bővítés egy második `DecoratedBox`-ot vagy `SsCard`-ot ad | a MEGLÉVŐ `component_catalog_test.dart`, a §7 negyedik útvonala (D3) |

**Az érintési cél három kötelező cellája** (a küszöb: **48 dp**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 44 dp magas sor | **elutasítva** — a cella PIROS |
| rajta (a küszöbön) | **48 dp** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 56 dp | elfogadva |

**Randomizált property (KÖTELEZŐ):** a `slider_numeric_sync_test.dart` a
`PROPERTY_SEED` env-et olvassa (hiányában 42). Tetszőleges érvényes értékre
igaz, hogy a csúszkán beállított és a mezőbe írt érték ugyanazt az állapotot
adja — oda-vissza. Három mért megkötés (§0.0/D8):

- **A tényleges vezérlő-utat járja be**, ne egy közös tiszta kerekítő
  függvényt: egy konstruktorban számolt mezőt mérő cella nem őrzi a mező
  FELHASZNÁLÁSÁT, a végrehajtási út hardkódolhat helyette sajátot
  (`lessons/L446`). A property a widget/notifier API-ján keresztül állítson
  értéket mindkét irányban.
- **Minden iteráció állítson.** Csak az egyik ágon írt változó melletti
  feltétlen `expect` a seed szerencséjéből zöld (`lessons/L436`).
- **EXAKT invariáns, nem arány.** A %-küszöbös, kis mintás property a HARD
  seeden boundary-flaky (`lessons/L142`) — itt a szinkron egzakt, tehát
  „minden próbán igaz" a helyes alak.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kerekítsd a numerikus
bevitelt máshogy, mint a csúszkát → az **A3** property-nek PIROSNAK kell lennie
→ állítsd vissza. A próba a **VISELKEDÉST** mutálja, ne csak a widget típusát
vagy kulcsát: a típus-szintű próba átengedi a tartalmi invariáns-sértést
(`lessons/L403`). A §10-be a mutáció, a mért PIROS kimenet és a visszaállítás
igazolása kerül.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/forms/ss_button_test.dart test/core/design_system/forms/ss_inputs_test.dart test/property/design_system/slider_numeric_sync_test.dart test/core/design_system/component_catalog_test.dart
```

A negyedik útvonal a MEGLÉVŐ, **nem szerkeszthető** katalógus-teszt (D3): a
katalógus-bővítés exact-count regresszióját a kör-gate-nek kell megfognia, nem
a CI-nak. **A gate előtt KÖTELEZŐ** (D2):

```bash
dart run tool/gen_l10n_segments.dart --write
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_button.dart` — variánsok, méret-stabil loading, dupla-beküldés zár.
2. `ss_icon_button.dart` — tooltip + semantics a gombon, glyph
   `SsIcon.decorative`-val (**D5**).
3. `ss_text_field.dart` — tartós label, IME, autofill.
4. `ss_switch_row.dart`, `ss_choice.dart` — teljes soros érintési cél
   (`SsSemantics.minimumInteractiveDimension`, **D4**).
5. `ss_value_slider.dart` + a randomizált szinkron-property (**D6**, **D7**).
6. `ss_validation_summary.dart` + ARB: az új kulcsok (`kulcs` + `@kulcs`
   EGYÜTT) a **fragmentumba** — `lib/l10n/features/design_system_{en,hu}.arb`
   (**D2**), majd `public.dart` export.
7. **`dart run tool/gen_l10n_segments.dart --write`** — az aggregátum
   regenerálása. KÖTELEZŐ, a gate ELŐTT (**D2**).
8. Component Catalog állapot-mátrix — a **D3** exact-count korlátaival; ha a
   bővítés a katalógus-tesztet pirosra váltja, a bővítést vedd vissza.
9. A valódi-sértés próba, §10-be dokumentálva.
10. `tools/round-gate.sh` a §7 szerint (négy útvonal).

## 9. Kockázatok

- **A placeholder mint label.** Letisztultabbnak látszik, és felolvasóval
  azonosíthatatlan mezőt ad (A1).
- **A kerekítési eltérés.** Fix fixture-rel láthatatlan, randomizált
  property-vel azonnal kiderül (A3) — a projekt már mérte, hogy a fixture
  default csendesen kiválaszt egy megkülönböztethetetlen pontot.
- **A méretugró loading gomb.** Apróságnak tűnik, és véletlen dupla
  beküldéshez vezet (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
