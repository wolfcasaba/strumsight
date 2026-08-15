# E13-R01 — UI baseline inventory és screenshot corpus

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 17670d4f`)
- **Típus:** **Chapter 13 program-nyitó kör** (UI/UX Design System)
- **Kör-azonosító:** `E13-R01`. Az `E13` a **FEJEZETET** jelöli, nem epicet
  (az epicek E01–E10) — mint az `E99` és az `E14`.
- **Branch:** `<motor>/e13-r01-ui-baseline-inventory`
- **Előfeltétel:** a Chapter 13 a repóban (`e90edaa2`)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a baseline-kör nem hoz architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd újra a §2 számait
> (képernyők, hex-találatok), mert az Epic 7 közben új képernyőket ad hozzá.
> A brief §2 értékei `main @ 17670d4f`-en készültek. Eltérésnél §0.0 revízió.

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
  "test/ui/ui_inventory_test.dart",
  "docs/rounds/e13-r01-ui-baseline-inventory.md",
]
gate_tests = [
  "test/ui/ui_inventory_test.dart",
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

## 2. Jelenlegi állapot — mért tények (`main @ 17670d4f`)

| mérés | érték |
|---|---|
| `lib/core/design_system/` | **nem létezik** — a Kör 2 hozza létre |
| `lib/core/theme/` | `app_colors.dart`, `app_palette.dart`, `app_theme.dart`, `theme_mode_provider.dart` |
| `*_screen.dart` a `lib/features` alatt | **51** |
| közvetlen `Color(0x…)` a feature-ökben | **9 fájl** |
| `docs/ui/` | **nem létezik** |

A Ch13 §2 kanonikus színalapjai (`#D98A46` copper, dark/light felületek,
confidence-színek) **nem cserélendők le** — a fejezet feladata, hogy
szemantikai tokenekké fejlessze őket.

## 3. Scope

**Benne van:** a képernyők, route-ok, dialógusok, bottom sheetek és
újrahasznosított widgetek inventárja · route-térkép a jelenlegi és cél-route-okkal,
redirect- és deep-link kockázatokkal · **token-adósság** felmérése (közvetlen
hex, hardkódolt spacing, közvetlen `TextStyle`, duplikált button/card/empty-state
minták, cross-feature UI-importok) · semantics-, overflow- és text-scale audit
**leletlistaként** · `docs/ui/README.md` és `migration-status.md`.

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
| `test/ui/ui_inventory_test.dart` | **ÚJ** — a generátor determinizmusa |
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
| A3 | Minden production képernyő szerepel az inventárban | a mért 51 `*_screen.dart` lefedve |
| A4 | A route-térkép tartalmazza a legacy ↔ cél párokat és a deep-link kockázatot | review |
| A5 | A token-adósság mérve (hex, spacing, TextStyle, duplikátumok, cross-feature import) | `token-debt.md` |
| A6 | Az accessibility-leletek prioritással szerepelnek | `accessibility-findings.md` |
| A7 | A dokumentum kimondja, hogy a screenshot NEM design-jóváhagyás | review |
| A8 | A meglévő teszt-suite változatlanul zöld | `tools/round-gate.sh` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Útközben javított" overflow vagy szín | **A1** |
| Könyvtár-bejárási sorrendű kimenet | **A2** |
| Az inventár kihagy képernyőket | A3 |
| A route-térkép csak a jelenlegit sorolja | A4 |
| A leletek súlyosság nélkül | A6 |
| A screenshot designként hivatkozva | A7 |

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
tools/round-gate.sh test/ui/ui_inventory_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `tool/ui_inventory.dart` — determinisztikus, rendezett kimenet.
2. `test/ui/ui_inventory_test.dart` — a determinizmus cellái.
3. `docs/ui/baseline/route-map.md` — legacy ↔ cél, kockázatokkal.
4. `docs/ui/baseline/token-debt.md` — a mért adósság.
5. `docs/ui/baseline/accessibility-findings.md` — prioritásos leletek.
6. `docs/ui/README.md` + `migration-status.md`.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „gyorsan javítom" kísértés.** Egy felmérő körben minden lelet
  javításra hív — és a baseline elveszik (A1).
- **A nem determinisztikus kimenet.** Csak a második futtatásnál derül ki,
  és minden későbbi diffet zajossá tesz (A2).
- **A screenshot félreértése.** Ha designként hivatkoznak rá, a Ch13
  célállapota összekeveredik a jelenlegivel (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
