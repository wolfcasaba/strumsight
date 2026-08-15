# E13-R07 — Ikonográfia és gitárglyph készlet

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 7
- **Kör-azonosító:** `E13-R07`
- **Branch:** `<motor>/e13-r07-iconography-and-guitar-glyphs`
- **Előfeltétel:** `E13-R06` merge-elve (motion)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a Ch13 §9.7 ikon-szabályai adottak.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg, hány **funkcionális emoji**
> maradt a production UI-ban (`grep` a `lib/features/**`-ben), mert a §6 A6
> cellája erre a mért számra hivatkozik. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/design_system/icons/ss_icons.dart",
  "lib/core/design_system/icons/ss_guitar_glyphs.dart",
  "lib/core/design_system/icons/ss_icon.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "assets/icons/",
  "pubspec.yaml",
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
  motion-réteget; ikon-réteg még nincs.
- A `lucide_icons_flutter` a projektben van, és a CLAUDE.md mért figyelmeztetése
  szerint **az ikonnevek csak fordításkor bukhatnak** — ezért kell katalógus.
- A Ch13 §9.7 felsorolja a kötelező gitár-glyph készletet (down/up strum,
  alternate picking, palm mute, bend, vibrato, hammer-on, pull-off, slide,
  capo, metronome, tuning peg, fretboard, loop A-B).

## 3. Scope

**Benne van:** `SsIcons` katalógus (Material Symbols + saját glyph mapping) ·
a gitár-glyph készlet · alap 24 dp / Stage 32–48 dp méretszabályok · outline és
filled variáns **állapot-redundanciához** · hiányzó glyph fallback ·
Component Catalog ikon-galéria · a funkcionális emoji felmérése a production
UI-ban (**leletként**, nem javításként).

**NINCS benne (tilos):** `lib/features/**` módosítása (az emoji cseréje a
képernyő-migrációs körök dolga) · `lib/core/theme/**` · új ikon-csomag
felvétele (a win32-szabály és a plugin-készlet stabilitása miatt) ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `icons/ss_icons.dart` | **ÚJ** — a névkatalógus |
| `icons/ss_guitar_glyphs.dart` | **ÚJ** — a gitár-glyph készlet |
| `icons/ss_icon.dart` | **ÚJ** — a méret/semantics API |
| `documentation/component_catalog_screen.dart` | ikon-galéria |
| `public.dart` | az export bővítése |
| `assets/icons/` | a vektoros glyph-ek |
| `pubspec.yaml` | **kizárólag** az asset-bejegyzés — függőség NEM |
| `test/…/icons/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r07-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · **új
`dependencies:` bejegyzés a `pubspec.yaml`-ben**.

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

### 5.3 A hiányzó glyph LÁTHATÓAN esik vissza, nem néma üres helyre

Ha egy név nem oldható fel, a fallback látható, és a hiba tesztben kiderül —
nem üres doboz jelenik meg a felületen.

**NEM elfogadható gyengítés:** `SizedBox.shrink()` fallbackként. Az néma
információvesztés, amit senki nem vesz észre.

### 5.4 Nincs ÚJ ikon-függőség

Az asset-alapú glyph nem hoz plugin-kockázatot. Új csomag felvétele a
win32-major szabály (CLAUDE.md) miatt külön kör.

### 5.5 A saját glyph-ek egységes stroke- és optikai mérettel

Vegyes vonalvastagság mellett a készlet ad hoc gyűjteménynek látszik.

### 5.6 A funkcionális emoji FELMÉRVE, nem javítva

A production UI-ban maradt funkcionális emoji leletként rögzül a §10-ben; a
csere a képernyő-migrációs körök (Kör 16–35) dolga.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A strum-irány saját glyph-fel, nem nyílkarakterrel jelenik meg | `ss_icons_test.dart` |
| A2 | Minden interaktív ikonnak van semantics labelje és tooltipje | `icon_semantics_test.dart` |
| A3 | A dekoratív ikon KI van zárva a semanticsből | ugyanott |
| A4 | Hiányzó glyph esetén látható fallback, nem üres hely | `ss_icons_test.dart` |
| A5 | A méretszabályok (24 dp alap, Stage 32–48 dp) érvényesülnek | ugyanott |
| A6 | A funkcionális emoji felmérve és a §10-ben rögzítve | review |
| A7 | Nincs ÚJ `dependencies:` bejegyzés | `git diff pubspec.yaml` |
| A8 | A készlet mindhárom témában rendereli az összes glyph-et | `ss_icons_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `Text('↓')` a strum-irányra | **A1** |
| Ikonos gomb label nélkül | **A2** |
| A dekoratív ikon a semantics fában | A3 |
| `SizedBox.shrink()` fallbackként | **A4** |
| Stage-en is 24 dp | A5 |
| Új ikon-csomag felvétele | **A7** |

**A méret három kötelező cellája** (a küszöb: a Stage-méret alsó határa,
**32 dp**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 24 dp Stage kontextusban | **elutasítva** — a cella PIROS |
| rajta (a küszöbön) | **32 dp** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 48 dp | elfogadva |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd el az egyik
interaktív ikon semantics labeljét → az **A2** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/icons/ss_icons_test.dart test/core/design_system/icons/icon_semantics_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_icons.dart` — a névkatalógus (a fordítás-idejű névhiba ellen).
2. `assets/icons/` + `ss_guitar_glyphs.dart` — a Ch13 §9.7 készlete.
3. `ss_icon.dart` — méret + semantics API, dekoratív/interaktív
   megkülönböztetéssel.
4. A fallback látható ága + a hozzá tartozó cella.
5. Component Catalog ikon-galéria mindhárom témában.
6. A funkcionális emoji felmérése → §10.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nyílkarakter kényelme.** Nulla asset-munkával kész, és pont a termék
  megkülönböztető jelzését teszi olvashatatlanná (A1).
- **A néma fallback.** Az üres doboz nem tűnik hibának, ezért sokáig életben
  marad (A4).
- **Az „egy csomag megoldaná".** Új plugin a win32-major szabályba ütközhet
  (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
