# E13-R11 — Action, input és form komponenskészlet

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 93a6c19a`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 11
- **Kör-azonosító:** `E13-R11`
- **Branch:** `<motor>/e13-r11-actions-and-forms`
- **Előfeltétel:** `E13-R10` merge-elve (aszinkron állapotok)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a Ch13 §9.11 komponens-szabályai adottak.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R05 `SsSpacing` és
> az R07 `SsIcon` TÉNYLEGES API-ját — a gomb- és mezőméretek ezekből jönnek,
> nem új konstansokból. Eltérésnél §0.0 revízió.

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
| `documentation/component_catalog_screen.dart` | állapot-mátrix |
| `public.dart` | az export bővítése |
| `lib/l10n/app_{en,hu}.arb` | validációs szövegek |
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
| A6 | 2.0 text scale mellett nincs túlcsordulás | `ss_inputs_test.dart` |
| A7 | A fókusz-bejárás sorrendje a vizuális sorrendet követi | ugyanott |
| A8 | Minden új szöveg ARB-n át megy (en + hu) | `grep` a diffben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Csak `hintText`, label nélkül | **A1** |
| A gomb felirata spinnerre cserélve, méret nem rögzítve | **A2** |
| A második koppintás is beküld | A2 |
| A numerikus bevitel kerekítése eltér a csúszkáétól | **A3** |
| Csak a kapcsoló érinthető, a sor nem | A4 |
| A destruktív gomb csak piros | A5 |

**Az érintési cél három kötelező cellája** (a küszöb: **48 dp**):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 44 dp magas sor | **elutasítva** — a cella PIROS |
| rajta (a küszöbön) | **48 dp** | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 56 dp | elfogadva |

**Randomizált property (KÖTELEZŐ):** a `slider_numeric_sync_test.dart` a
`PROPERTY_SEED` env-et olvassa (hiányában 42). Tetszőleges érvényes értékre
igaz, hogy a csúszkán beállított és a mezőbe írt érték ugyanazt az állapotot
adja — oda-vissza.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kerekítsd a numerikus
bevitelt máshogy, mint a csúszkát → az **A3** property-nek PIROSNAK kell lennie
→ állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/forms/ss_button_test.dart test/core/design_system/forms/ss_inputs_test.dart test/property/design_system/slider_numeric_sync_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_button.dart` — variánsok, méret-stabil loading, dupla-beküldés zár.
2. `ss_icon_button.dart` — tooltip + semantics (az R07 szabálya szerint).
3. `ss_text_field.dart` — tartós label, IME, autofill.
4. `ss_switch_row.dart`, `ss_choice.dart` — teljes soros érintési cél.
5. `ss_value_slider.dart` + a randomizált szinkron-property.
6. `ss_validation_summary.dart` + ARB (en + hu).
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

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
