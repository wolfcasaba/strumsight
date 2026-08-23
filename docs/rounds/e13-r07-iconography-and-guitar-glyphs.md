# E13-R07 — Ikonográfia és gitárglyph készlet

- **Státusz:** READY (pre-flight lefuttatva 2026-08-23, kód mérve: `main @ 667792b6`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 7
- **Kör-azonosító:** `E13-R07`
- **Branch:** `sonnet-impl/e13-r07-iconography-and-guitar-glyphs`
- **Előfeltétel:** `E13-R06` merge-elve (motion) — ✅ `011d1c47`
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`0411`](../adr/0411-iconography-and-guitar-glyph-contract.md) — az
  orchestrátor írta a pre-flightban, a kör indítása ELŐTT commitolva. A
  `docs/adr/**` az implementernek TILOS zóna marad.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/design_system/icons/ss_icons.dart",
  "lib/core/design_system/icons/ss_guitar_glyphs.dart",
  "lib/core/design_system/icons/ss_icon.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/icons/ss_icons_test.dart",
  "test/core/design_system/icons/icon_semantics_test.dart",
  "docs/rounds/e13-r07-iconography-and-guitar-glyphs.md",
]
gate_tests = [
  "test/core/design_system/icons/ss_icons_test.dart",
  "test/core/design_system/icons/icon_semantics_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (orchestrátor, 2026-08-23) — MÉRT javítások

A brief 2026-08-15-én készült; az alábbi állításai a mai fán MÉRVE nem álltak.
A javítás a kör saját, még nem merge-elt artefaktumát érinti, tehát az
orchestrátor hatásköre (ADR 0087 §2). A lista SZŰKÜLT, nem tágult.

### D1 — A Ch13 ikon-szakasza a §9.8, nem a §9.7

Mérve: `docs/sdd/13-chapter-13-ui-ux-design-system.md:686` = `## 9.7 Motion
tokenek` (az E13-R06 tárgya), `:703` = `## 9.8 Ikonográfia`. A tizennégy
glyph-név a 711–726. sorban áll. A brief minden `§9.7` hivatkozása **§9.8**-ra
javítva.

### D2 — A `lucide_icons_flutter` NINCS a projektben

Mérve: `grep -n lucide pubspec.yaml` → nincs találat; a teljes
`dependencies:` blokkban nem szerepel. Egyetlen említése egy doc-comment
(`lib/features/community/presentation/widgets/reaction_bar.dart:99`), amely
épp azt rögzíti, hogy NEM függ tőle. A névkatalógus indoka ettől NEM szűnik
meg — a Material `Icons.*` konstansok ugyanígy csak fordításkor bukhatnak —,
de a §2 lucide-ra hivatkozó mondata javítva.

### D3 — `assets/icons/` + „vektoros glyph" + „nincs új függőség" EGYÜTT nem teljesíthető → a lista SZŰKÜL

Mérve: a `flutter_svg` sehol nincs a fában (`pubspec.yaml`, `pubspec.lock`,
`lib/`), és a Flutter beépítetten nem rendereli az SVG-t. Új ikon-csomag
felvételét viszont az §5.4 és az **A7** tiltja. Ikon-font (.ttf) bináris
artefaktum, amit ez a lánc nem tud reprodukálhatóan előállítani és
review-zni.

A fa mért, függőségmentes vektor-útja a `CustomPainter`: tíz production fájl
használja, közte a `lib/features/live/widgets/strum_arrow.dart`, amely már ma
is FESTETT — nem karakteres — strum-jelet ad semantics labellel.

**Következmény:** a `assets/icons/` és a `pubspec.yaml` **kikerül** az
engedélyezett fájllistából. A tizennégy glyph pure-Dart `CustomPainter`. Az
**A7** ezzel gépi bizonyítékot kap: a `pubspec.yaml` bármely érintése
`scope_audit=VIOLATION`. Rögzítve: [ADR 0411](../adr/0411-iconography-and-guitar-glyph-contract.md) §1.

### D4 — A fájlnév `ss_guitar_glyphs.dart` marad

A Ch13 §10 célstruktúra `icons/guitar_glyphs.dart`-ot ír, az `allowed_paths`
viszont `ss_guitar_glyphs.dart`-ot. A gépi scope-audit az `allowed_paths`
ellen mér, és az `ss_` prefix a design system MINDEN mai fájljának
konvenciója — ezért az `allowed_paths` alakja az operatív. Nem eltérés, csak
rögzítés.

### D5 — A5: a méretküszöb PINNELT szerződése

A „24 dp Stage kontextusban → elutasítva" cella önmagában nem operatív. A kör
szerződése (ADR 0411 §5):

- `SsIconSize.base = 24`, `SsIconSize.stageMin = 32`, `SsIconSize.stageMax = 48`;
- a Stage-tartomány MINDKÉT vége **inkluzív**;
- a predikátum (pl. `SsIconSize.isValidForStage(double)`) a tartományon kívül
  **hamis**;
- a **tényleges widget-úton** a Stage-kontextusban kért, tartományon kívüli
  méret NEM jut át: a renderelt méret a legközelebbi érvényes Stage-értékre
  áll be. Puszta `assert` NEM elég — release buildben nem fut.

**Miért így (`docs/LESSONS.md` L381):** a küszöbcellák idealizált bemenettel
mind zöldek maradhatnak, miközben a valódi út hibás. Ezért a három cella
mellé **legalább egy cella a valódi widget-úton** is kötelező.

### D6 — A2/A3: a semantics cellának a SZÖVEGET kell mérnie, nem a widget-típust

`docs/LESSONS.md` **L403** (E08-R23): egy „valódi-sértés próba", amely csak a
widget TÍPUSÁT/kulcsát nézi, átengedi a tartalmi (felirat) invariáns-sértést.
Ezért az **A2** cellája a tényleges semantics label SZTRINGJÉT és a tooltip
SZTRINGJÉT hasonlítja a hívó által adott értékhez (üres string sem elég), az
**A3** pedig azt méri, hogy a dekoratív ikon labelje a fában **nincs jelen**.

### D7 — A6: a felmérés MÉRT alapvonala (a §10 innen indul)

Az orchestrátor a `main @ 667792b6`-on lemérte; az implementer ezt
REPRODUKÁLJA és a §10-be írja (eltérésnél a mért értéket írja, nem ezt):

```bash
# emoji-piktogramok, comment-sorok nélkül
grep -rcP "^(?!\s*(//|\*|/\*)).*[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}]" lib/features/ --include=*.dart | grep -v ':0$'
# nyílkarakterek (U+2190–21FF), comment-sorok nélkül
grep -rcP "^(?!\s*(//|\*|/\*)).*[\x{2190}-\x{21FF}]" lib/features/ --include=*.dart | grep -v ':0$'
```

Mért alapvonal (`main @ 667792b6`):

| Kategória | Előfordulás | Fájl |
|---|---|---|
| emoji-piktogram | **16** | **5** |
| nyílkarakter (`↓`/`↑`/…) | **25** | **13** |

A nyílkarakteres fájlok között ott van a `share_content.dart` (6),
`feed_card_registry.dart` (3), `strum_card.dart` (3) — vagyis a
strum-irány MA több helyen tényleg puszta karakterként megy ki. Ez a §5.1
indoklásának mért alátámasztása, **de a javítás NEM ennek a körnek a dolga**
(§5.6): a `lib/features/**` tilos zóna marad.

### D8 — Visszakeresés (ADR 0312, brief-lint S8)

`node tools/knowledge-rag.mjs --corpus lessons,halts,adr` és teljes korpusz,
2026-08-23. Releváns előzmény:

- **`lessons/L403`** — a widget-típus szintjén mérő valódi-sértés próba
  átengedi a tartalmi sértést → **D6**.
- **`lessons/L381`** — a küszöbcellák idealizált bemenettel zöldek
  maradhatnak a hibás valódi út mellett → **D5**.
- **`lessons/L387`** — egy design-system integráció scope-ja a meglévő
  kompatibilitási teszteket is magában foglalja → a `public.dart` bővítése
  után a **teljes** CI-suite a mérce, nem csak a két célzott fájl.
- **`adr/0273`** — egy token-forrás: a design system olvas, nem másol → az
  ikon-réteg sem vezet be új színt vagy méretet a tokeneken kívül.
- **`adr/0381` §3** — a widget nem találhat ki saját overlay-színt → ugyanez
  az elv köti a stroke-vastagságot is (ADR 0411 §2).

### D9 — Az ADR 0411 megírva és a kör ELŐTT commitolva

Az eredeti brief „nincs ADR"-t írt, mert a Ch13 §9.7-re hivatkozott; a valódi
§9.8 viszont nem dönt a megvalósítás módjáról (festett vs. asset), és a **D3**
mérés önálló, tartós normatív döntést kívánt. A `reserve-adr` foglalta szám:
**0411**. Az ADR az orchestrátor pre-flight commitjában van, tehát az
implementer diffjében NEM szerepelhet.

### D10 — Az ADR 0087 §1 két mérési szabálya

- **Elérhetetlen cél-státusz:** nincs olyan acceptance-cella, amely meglévő
  állapotgép-státuszra hivatkozna — az ikon-réteg ÚJ, állapotgép nélküli. A
  méret-„elutasítás" ezért a **D5** szerint pinnelt, nem egy meglévő enumra
  mutató elvárás.
- **Erőforrás-tulajdonlás:** a kör nem rendel lease-t, lockot, handle-t vagy
  subscriptiont réteghez — a diff sem `.acquire(`, sem stream-előfizetés
  útvonalat nem érint. Nem alkalmazható.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Egységes ikon-API és **hozzáférhető** gitárspecifikus glyph-készlet
(SDD Ch13 Kör 7).

## 2. Jelenlegi állapot — mért tények

- Az R02–R06 letette a foundation, szín-, tipográfia-, felület- és
  motion-réteget; ikon-réteg még nincs. A `lib/core/design_system/icons/`
  könyvtár ma NEM létezik (mérve).
- **A `lucide_icons_flutter` NINCS a fában** (D2). Az ikonnév-kockázat viszont
  él: a Material `Icons.*` konstansok is csak fordításkor bukhatnak — ezért
  kell névkatalógus.
- **Nincs SVG-renderer** (D3): a `flutter_svg` sehol nincs a fában, és a
  Flutter beépítetten nem rendereli az SVG-t. A fa mért, függőségmentes
  vektor-útja a `CustomPainter` (10 production fájl).
- A Ch13 **§9.8** (a fájl 703–726. sora) felsorolja a kötelező gitár-glyph
  készletet — tizennégy név: `downstrum`, `upstrum`, `alternatePicking`,
  `palmMute`, `bend`, `vibrato`, `hammerOn`, `pullOff`, `slide`, `capo`,
  `metronome`, `tuningPeg`, `fretboard`, `loopAB`.
- A design system rétege ma `AppLocalizations`-mentes; ez a kör sem vezet be
  l10n-függést (ADR 0411 §4).

## 3. Scope

**Benne van:** `SsIcons` katalógus (Material Symbols + saját glyph mapping) ·
a tizennégy elemű gitár-glyph készlet **festett (`CustomPainter`) vektorként** ·
alap 24 dp / Stage 32–48 dp méretszabályok · outline és filled variáns
**állapot-redundanciához** · hiányzó glyph LÁTHATÓ fallback · Component Catalog
ikon-galéria mindhárom témában · a funkcionális emoji felmérése a production
UI-ban (**leletként**, nem javításként).

**NINCS benne (tilos):** `lib/features/**` módosítása (az emoji/nyílkarakter
cseréje a képernyő-migrációs körök dolga) · `lib/core/theme/**` · **a
`pubspec.yaml` bármely érintése** (sem függőség, sem asset — D3) ·
`assets/**` · `docs/adr/**`, `docs/sdd/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `icons/ss_icons.dart` | **ÚJ** — a névkatalógus |
| `icons/ss_guitar_glyphs.dart` | **ÚJ** — a festett gitár-glyph készlet |
| `icons/ss_icon.dart` | **ÚJ** — a méret/semantics API |
| `documentation/component_catalog_screen.dart` | ikon-galéria |
| `public.dart` | az export bővítése |
| `test/…/icons/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r07-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
**`pubspec.yaml`** · **`assets/**`** · `docs/adr/**` · `docs/sdd/**` ·
`tools/**` · `.github/**`.

> A `pubspec.yaml` és az `assets/` a D3 mérés után KIKERÜLT a listáról. Ez a
> lista SZŰKÍTÉSE, nem tágítása — és egyben az **A7** gépi bizonyítéka: a
> `pubspec.yaml` bármely érintése `scope_audit=VIOLATION`.

## 5. Kötött architekturális döntések

### 5.1 A strum-irány NEM csak nyílkarakter

Ez a termék központi jelzése. A le/fel strumnak saját, gitárra utaló glyph-je
van; a puszta `↓`/`↑` karakter nem elég — kis méretben és képernyőolvasóval is
azonosíthatónak kell lennie.

**NEM elfogadható gyengítés:** `Text('↓')` a strum-jelzésre. Kis méretben
összekeverhető, és a semantics „lefelé mutató nyíl"-at olvas.

### 5.2 Az interaktív ikonnak semantics label és tooltip KELL

Csak ikonos gomb felirat nélkül nem elfogadható. A dekoratív ikon viszont
**ki van zárva** a semantics fából, hogy ne zajosítsa a felolvasást.

A label és a tooltip **hívó-oldali**, nem üres szöveg: a design system nem
lokalizál, `AppLocalizations`-t nem importál (ADR 0411 §4). A cellának a
tényleges SZTRINGET kell mérnie, nem a widget típusát (D6, `LESSONS` L403).

### 5.3 A hiányzó glyph LÁTHATÓAN esik vissza, nem néma üres helyre

Ha egy név nem oldható fel, a fallback látható, és a hiba tesztben kiderül —
nem üres doboz jelenik meg a felületen.

**NEM elfogadható gyengítés:** `SizedBox.shrink()` fallbackként. Az néma
információvesztés, amit senki nem vesz észre.

### 5.4 Nincs ÚJ ikon-függőség ÉS nincs asset — a glyph FESTETT

Új csomag felvétele a win32-major szabály (CLAUDE.md) miatt külön kör. Mivel a
`flutter_svg` sincs a fában (D3), a tizennégy glyph pure-Dart `CustomPainter`.
A `pubspec.yaml` és az `assets/` érintetlen marad — mindkettő tilos zóna.

### 5.5 A saját glyph-ek egységes stroke- és optikai mérettel

Vegyes vonalvastagság mellett a készlet ad hoc gyűjteménynek látszik.

**Gépi alak (ADR 0411 §2):** minden glyph ugyanabból a NEVESÍTETT
stroke-arányból számolja a vonalvastagságát, a kért dp-méretből. Painter nem
találhat ki saját vonalvastagságot; ez cellával falszifikálható.

### 5.6 A funkcionális emoji FELMÉRVE, nem javítva

A production UI-ban maradt funkcionális emoji leletként rögzül a §10-ben; a
csere a képernyő-migrációs körök (Kör 16–35) dolga.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A strum-irány saját, FESTETT glyph-fel, nem nyílkarakterrel jelenik meg | `ss_icons_test.dart` |
| A2 | Minden interaktív ikonnak van NEM ÜRES semantics labelje és tooltipje — a cella a SZTRINGET méri | `icon_semantics_test.dart` |
| A3 | A dekoratív ikon KI van zárva a semanticsből (a labelje NINCS a fában) | ugyanott |
| A4 | Hiányzó glyph esetén LÁTHATÓ (nem nulla kiterjedésű) fallback, és `isFallback` igaz | `ss_icons_test.dart` |
| A5 | A méretszabályok (24 dp alap, Stage 32–48 dp inkluzív) a VALÓDI widget-úton is érvényesülnek | ugyanott |
| A6 | A funkcionális emoji + nyílkarakter felmérve és a §10-ben rögzítve | review |
| A7 | A `pubspec.yaml` ÉRINTETLEN (sem `dependencies:`, sem asset) | `git diff --exit-code pubspec.yaml` + `scope_audit` |
| A8 | A készlet mind a 14 glyph-et rendereli mindhárom témában, kivétel nélkül | `ss_icons_test.dart` |
| A9 | Minden glyph ugyanabból a nevesített stroke-arányból számol | `ss_icons_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `Text('↓')` a strum-irányra | **A1** |
| Ikonos gomb label nélkül VAGY üres (`''`) labellel | **A2** |
| A dekoratív ikon labelje a semantics fában | A3 |
| `SizedBox.shrink()` fallbackként | **A4** |
| Stage-en is 24 dp (csak `assert`, release-ben átmegy) | **A5** |
| `pubspec.yaml` bővítése (csomag VAGY asset) | **A7** + `scope_audit` |
| Egy glyph saját, kézzel írt `strokeWidth`-tel | **A9** |
| Egy glyph hiányzik a galériából / kivételt dob egy témában | **A8** |

**A méret három kötelező cellája** (a küszöb: a Stage-méret alsó határa,
**32 dp**; a `python3 -c` számolás triviális, mert a küszöb egész dp):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | **24 dp** Stage kontextusban | **elutasítva**: a predikátum hamis, ÉS a valódi widget-úton renderelt méret **32**, nem 24 |
| rajta (a küszöbön) | **32 dp** | **elfogadva** (a határ inkluzív), renderelt méret 32 |
| a küszöb fölött | **48 dp** | elfogadva (a felső határ is inkluzív), renderelt méret 48 |

> A három cella közül **legalább egy** a valódi widget-úton fusson, ne csak a
> predikátumon (D5, `LESSONS` L381). A puszta `assert` NEM teljesíti az A5-öt:
> release buildben nem fut.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd el az egyik
interaktív ikon semantics labeljét → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza. A §10-be a próba PONTOS kimenetét írd (melyik teszt bukott,
milyen üzenettel), ne csak azt, hogy „elvégeztem".

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/icons/ss_icons_test.dart test/core/design_system/icons/icon_semantics_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_icons.dart` — a névkatalógus (a fordítás-idejű névhiba ellen) + a
   `SsIconSize` tokenek a **D5** szerződéssel.
2. `ss_guitar_glyphs.dart` — a Ch13 **§9.8** tizennégy glyph-je `CustomPainter`
   festéssel, EGY nevesített stroke-arányból (A9). **Nincs asset, nincs
   `pubspec.yaml`-érintés.**
3. `ss_icon.dart` — méret + semantics API, dekoratív/interaktív
   megkülönböztetéssel; a label és a tooltip hívó-oldali, nem üres.
4. A fallback látható ága (`isFallback` lekérdezhető) + a hozzá tartozó cella.
5. Component Catalog ikon-galéria mindhárom témában, mind a 14 glyph-fel.
6. `public.dart` export-bővítés.
7. A funkcionális emoji + nyílkarakter felmérése a **D7** parancsokkal → §10.
8. A valódi-sértés próba, §10-be dokumentálva a PONTOS bukás-kimenettel.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nyílkarakter kényelme.** Nulla asset-munkával kész, és pont a termék
  megkülönböztető jelzését teszi olvashatatlanná (A1).
- **A néma fallback.** Az üres doboz nem tűnik hibának, ezért sokáig életben
  marad (A4).
- **Az „egy csomag megoldaná".** Új plugin a win32-major szabályba ütközhet
  (A7).

## 10. Implementation handoff — az implementer tölti ki

### Létrehozott/módosított fájlok

- **`lib/core/design_system/icons/ss_icons.dart`** (ÚJ) — `SsGuitarGlyphName`
  enum (a tizennégy Ch13 §9.8 név, fordítás-idejű névhiba-védelem), `SsIconSize`
  (24/32/48 dp, D5 szerződés: `isValidForStage`, `resolveForStage`),
  `SsIconResolution` lezárt hierarchia (`SsResolvedGuitarGlyph` /
  `SsResolvedMaterialIcon` / `SsFallbackIcon`, `isFallback` lekérdezhető), és
  `SsIcons` katalógus (`resolveByName`: gitár-glyph → Material Symbols alias →
  látható fallback).
- **`lib/core/design_system/icons/ss_guitar_glyphs.dart`** (ÚJ) —
  `kSsGuitarGlyphStrokeRatio` (a NEVESÍTETT, egyetlen stroke-arány),
  `SsGuitarGlyphs.strokeWidthFor` (az egyetlen számítási hely, A9), és
  `SsGuitarGlyphPainter` — EGY `CustomPainter` osztály mind a 14 glyph-hez
  (switch a névre), így szerkezetileg kizárt, hogy egy glyph saját
  `strokeWidth`-et találjon ki. A `downstrum`/`upstrum` a `strum_arrow.dart`
  mintáját követi (szár + töltött nyílhegy), festve, nem karakterrel.
- **`lib/core/design_system/icons/ss_icon.dart`** (ÚJ) — `SsIcon` widget két
  factory-val: `.decorative` (const, `ExcludeSemantics`, se label, se
  tooltip) és `.interactive` (nem const — `_requireNonEmpty` validál —,
  `Semantics(label:, excludeSemantics: true)` + `Tooltip(excludeFromSemantics:
  true)`, mindkét sztring hívó-oldali, üresre `ArgumentError`). A Stage-méret
  a VALÓDI widget-úton `SsIconSize.resolveForStage`-en megy át a
  `CustomPaint`-ba kerülés előtt. Hiányzó név esetén `_SsIconFallbackPainter`
  (bekeretezett X, nem nulla méret) renderelődik.
- **`lib/core/design_system/documentation/component_catalog_screen.dart`** —
  egy `Wrap` hozzáadva a meglévő téma-váltós katalógushoz, amely mind a 14
  `SsGuitarGlyphName` értéket `SsIcon.decorative`-ként rendereli (A8 —
  ugyanez a felület adja a widget-tesztben is a „mindhárom témában" bizonyítékot).
- **`lib/core/design_system/public.dart`** — a három ÚJ ikon-fájl export-ja
  hozzáadva (ábécésorrendben az `icons/` blokk).
- **`test/core/design_system/icons/ss_icons_test.dart`** (ÚJ) — A1, A4, A5,
  A8, A9 cellák (lásd lent a mérce-mátrix leképezést).
- **`test/core/design_system/icons/icon_semantics_test.dart`** (ÚJ) — A2, A3
  cellák.

### A6 — a funkcionális emoji + nyílkarakter felmérése (lelet, NEM javítás)

A D7 parancsait a mai fán (`sonnet-impl/e13-r07-iconography-and-guitar-glyphs`,
az orchestrátor `main @ 667792b6` pre-flight mérése után, az implementer
körében a `lib/features/**`-hez nem nyúlva) reprodukálva:

```bash
grep -rcP "^(?!\s*(//|\*|/\*)).*[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}]" lib/features/ --include=*.dart | grep -v ':0$'
grep -rcP "^(?!\s*(//|\*|/\*)).*[\x{2190}-\x{21FF}]" lib/features/ --include=*.dart | grep -v ':0$'
```

| Kategória | Előfordulás | Fájl |
|---|---|---|
| emoji-piktogram | **16** | **5** |
| nyílkarakter (`↓`/`↑`/…) | **25** | **13** |

Emoji fájlonként: `share/widgets/wrapped_card.dart` (1),
`share/share_content.dart` (9), `learn/screens/learn_screen.dart` (1),
`community/presentation/widgets/reaction_bar.dart` (4),
`ai_tutor/presentation/widgets/tutor_message_bubble.dart` (1).

Nyílkarakter fájlonként: `streak/daily_challenge.dart` (1),
`share/screens/strum_reel_screen.dart` (2), `share/widgets/wrapped_card.dart`
(2), `share/widgets/strum_card.dart` (3), `share/share_content.dart` (6),
`learn/screens/learn_screen.dart` (2), `learn/widgets/lesson_score_card.dart`
(1), `gamification/domain/quests/challenge_definition.dart` (1),
`practice/presentation/widgets/chord_change_breakdown.dart` (1),
`community/presentation/widgets/feed_card_registry.dart` (3),
`song_trainer/data/migration/legacy_song_adapter.dart` (1),
`live/widgets/strum_arrow.dart` (1),
`live/engine/dsp/strum_direction_classifier.dart` (1).

A mért érték pontosan egyezik az orchestrátor D7 alapvonalával (16/5, 25/13) —
a `lib/features/**` a kör alatt változatlan maradt. A csere a
képernyő-migrációs körök (Ch13 Kör 16–35) dolga.

### Valódi-sértés próba (A2)

`lib/core/design_system/icons/ss_icon.dart`-ban az interaktív ág
`Semantics(label: label, ...)` sorát ideiglenesen `Semantics(label: '', ...)`-re
cserélve, majd `flutter test test/core/design_system/icons/icon_semantics_test.dart`
lefuttatva — az **A2** cella a vártnak megfelelően PIROSRA váltott:

```
00:00 +0: interactive icon semantics (A2) — the caller-supplied strings exposes the caller-supplied semantic label and tooltip verbatim
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞═══════════════════════════
The following TestFailure was thrown running a test:
Expected: exactly one matching candidate
  Actual: _ElementPredicateWidgetFinder:<Found 0 widgets with a semantics label named "Play the down
strum": []>
   Which: means none were found but one was expected
...
00:00 +0 -1: interactive icon semantics (A2) — the caller-supplied strings exposes the caller-supplied semantic label and tooltip verbatim [E]
  Test failed. See exception logs above.
```

A másik három teszt (két üres-string `ArgumentError` cella + az A3 dekoratív
cella) továbbra is zöld maradt, mert egyik sem méri az interaktív labelt — ez
megerősíti, hogy a próba pontosan az A2 cellát találta el, nem egy szélesebb
törést. A sort ezután visszaállítva (`label: label`), a teszt újra zöld:
`00:00 +4: All tests passed!` (lásd a §11 gate-futást ugyanerre az
eredményre).

### Gate

```
tools/round-gate.sh test/core/design_system/icons/ss_icons_test.dart test/core/design_system/icons/icon_semantics_test.dart
```

Mind a hét lépés (`format`, `analyze`, a két célzott `test`, `architecture`,
`secrets`, `l10n`) **ZÖLD**. Kiegészítő, nem kötelező ellenőrzésként lefutott
a `test/core/design_system/component_catalog_test.dart` is (L387 — a
`public.dart` bővítése a meglévő kompatibilitási tesztet is érinti):
mind a nyolc teszt zöld, a katalógus-galéria hozzáadása nem törte a meglévő
smoke-tesztet.

### A következő köröknek

- A `SsIcon.byName`-szerű dinamikus feloldás (`SsIcons.resolveByName`) ma csak
  hat Material-aliast ismer (`play`, `pause`, `settings`, `close`, `check`,
  `info`) — bővítendő, ha egy jövőbeli kör több Material ikonra hivatkozna
  névvel.
- A `lib/features/live/widgets/strum_arrow.dart` és az új
  `SsGuitarGlyphPainter` downstrum/upstrum ága két, egymástól független
  megvalósítás (ADR 0411 „Következmények" — szándékos, az összevonás a
  képernyő-migrációs körök dolga).
- Az A6 lelet (16 emoji / 5 fájl, 25 nyíl / 13 fájl) a Ch13 Kör 16–35
  kiindulópontja — egyik érintett fájlhoz sem nyúlt ez a kör.

## 11. Review — a Claude tölti ki
