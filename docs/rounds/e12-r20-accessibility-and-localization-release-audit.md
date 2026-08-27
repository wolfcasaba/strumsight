# E12-R20 — Accessibility és localization release audit

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 20
- **Kör-azonosító:** `E12-R20`
- **Branch:** `<motor>/e12-r20-accessibility-and-localization-release-audit`
- **Előfeltétel:** `E13-R36` és `E12-R11` merge-elve (a teljes UI és az e2e harness egyaránt bemenet)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a szerződéseket az [ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md), [ADR 0383](../adr/0383-typography-and-text-scale-contract.md) és [ADR 0424](../adr/0424-localization-resilience-contract.md) MÁR rögzíti; ez a kör AUDITÁL.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "localization parity accessibility text scale semantics audit"` → **[ADR 0383](../adr/0383-typography-and-text-scale-contract.md)** (tipográfia és text-scale szerződés) és **[ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md)** (akadálymentességi szerződés és élő régió költségvetés). Az audit ezek MÉRT kritériumait futtatja végig a core flow-n; új szerződést nem alkot.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `test/accessibility/` három tesztjét (`semantics_contract_test.dart`, `screen_reader_copy_test.dart`, `tap_target_test.dart`), a `test/l10n/` hármat (`arb_parity_test.dart`, `hardcoded_string_guard_test.dart`, `formatters_test.dart`) és a Chapter 13 sáv legutóbbi text-scale méréseit. Az audit ezekre ÉPÜL — új, párhuzamos ellenőrzőt nem ír.

## 0.0 Miért nem ír ARB-kulcsot ez a kör

A lokalizációs FORRÁS a `lib/l10n/base/` fragmentum-fa, és a Chapter 13 sáv tulajdona. Egy hiányzó fordítás itt LELET (a kivétel-nyilvántartásban vagy `stopped` jelzésként), nem javítandó munka — különben az audit a saját mércéjét írná át.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "test/accessibility/release_flow_text_scale_test.dart",
  "test/accessibility/release_flow_semantics_test.dart",
  "docs/accessibility/release-audit.md",
  "docs/accessibility/known-exceptions.yaml",
  "docs/rounds/e12-r20-accessibility-and-localization-release-audit.md",
]
gate_tests = [
  "test/accessibility/release_flow_text_scale_test.dart",
  "test/accessibility/release_flow_semantics_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/l10n/hardcoded_string_guard_test.dart",
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

**STOP-protokoll:** ha az audit P1 súlyú akadálymentességi vagy fordítási hibát talál, a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS.

## 1. Cél

Bizonyítani, hogy a core tanulási út angolul ÉS magyarul, 200%-os szövegnagyítás mellett és képernyőolvasóval végigjárható — vagy pontosan megnevezni, hol nem.

## 2. Jelenlegi állapot — mért tények

- `test/accessibility/`: `semantics_contract_test.dart`, `screen_reader_copy_test.dart`, `tap_target_test.dart` — KOMPONENS-szintű mércék.
- `test/l10n/`: `arb_parity_test.dart` (en↔hu paritás), `hardcoded_string_guard_test.dart` (beégetett szöveg őre), `formatters_test.dart`.
- `tool/ci/check_l10n_parity.dart` és `tool/gen_l10n_segments.dart` a fragmentum-alapú ARB-forrást kezelik (ADR 0424).
- **FOLYAM-szintű, teljes core úton futó text-scale és semantics mérce NINCS** — a Chapter 13 körei képernyőnként mértek (a `textScaler 2.0` golden-keret ott derített fel valódi túlcsordulásokat).
- `docs/accessibility/` **nem létezik**.
- `test/e2e/` a Kör 11 után létezik — az audit ugyanazt a determinisztikus profilt használja.

## 3. Scope

**Benne van:** `test/accessibility/release_flow_text_scale_test.dart` — a core flow (indítás → onboarding → gyakorlás → eredmény) végigjátszása `textScaler 2.0` mellett, MINDKÉT locale-on, túlcsordulás-ellenőrzéssel · `test/accessibility/release_flow_semantics_test.dart` — ugyanaz a flow képernyőolvasó-szemantikával: minden interaktív elem elérhető, a fókusz-sorrend értelmes, az állapot nem CSAK színnel jelölt · `docs/accessibility/release-audit.md` (a futtatott mércék, az eredmény, és a NEM lefedett területek) · `docs/accessibility/known-exceptions.yaml` (owner + lejárat + hatás).

**NINCS benne (tilos):**

- `lib/**` és `lib/l10n/**` bármely módosítása (a §0.0 szerint).
- Meglévő a11y/l10n teszt gyengítése vagy `skip`-je.
- Új golden-kép felvétele (a golden-fa ADR 0426 hatálya alatt).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/accessibility/release_flow_text_scale_test.dart` | ÚJ — folyam-szintű text-scale mérce |
| `test/accessibility/release_flow_semantics_test.dart` | ÚJ — folyam-szintű semantics mérce |
| `docs/accessibility/release-audit.md` | ÚJ — az audit eredménye |
| `docs/accessibility/known-exceptions.yaml` | ÚJ — kivétel-nyilvántartás |

**Tilos zóna:** `lib/**` · `test/ui/goldens/**` · `test/accessibility/` meglévő fájljai · `test/l10n/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Két kötelező szabály:

### 5.1 A mérce a FOLYAM, nem a képernyő

Az audit a valódi app-fán, egymás után látogatott képernyőkön mér. **NEM elfogadható gyengítés:** képernyőnkénti, izolált pumpolás — a Chapter 13 már azt mérte; ez a kör azt a hibaosztályt keresi, ami CSAK a folyamban jelenik meg (megőrzött állapot, fókusz-átadás, dinamikus szöveg).

### 5.2 A hiba LELET, nem javítandó munka

**NEM elfogadható gyengítés:** a talált túlcsordulás „gyors" javítása a `lib/`-ben (§0.0, STOP-eset).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A core flow `textScaler 2.0` mellett `en` locale-on túlcsordulás nélkül végigjárható | `release_flow_text_scale_test.dart` |
| A2 | Ugyanez `hu` locale-on | ugyanaz a teszt (locale-páros cella) |
| A3 | A flow minden interaktív eleme elérhető képernyőolvasóval, értelmes fókusz-sorrenddel | `release_flow_semantics_test.dart` |
| A4 | Egyetlen állapot sincs KIZÁRÓLAG színnel jelölve a flow-ban | `release_flow_semantics_test.dart` |
| A5 | A meglévő `arb_parity_test.dart` és `hardcoded_string_guard_test.dart` VÁLTOZATLANUL zöld | a §7 gate |
| A6 | Minden talált kivétel ownerrel és lejárattal szerepel a `known-exceptions.yaml`-ben | a fájl + a teszt cellája |

**Küszöb-cellahármas a szövegnagyításra** (a kötelező határ `2.0`, INKLUZÍV): a küszöb **alatt** (`1.5`) → a flow zöld; **pontosan rajta** (`2.0`) → a flow zöld — EZ a release-feltétel; a küszöb **fölött** (`2.5`) → NEM követelmény, a teszt nem méri (és nem is enged rá hivatkozni a `2.0` teljesítéseként).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A teszt csak `en` locale-on fut | A2 |
| A teszt képernyőnként pumpol, a folyam-állapot elveszik | A1 vagy A3 (a mért folyam-hiba nem jelenik meg) |
| Egy állapotjelzés csak színt kap, `Semantics` nélkül | A4 |
| A kivétel lejárat nélkül kerül a nyilvántartásba | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd a text-scale cellát `1.0`-ra, futtasd a §7 gate-et, majd vissza `2.0`-ra → a próba akkor sikeres, ha a `2.0` cella mérete/eredménye BIZONYÍTHATÓAN eltér az `1.0`-étől (különben a teszt nem is skálázott). Dokumentáld mindkét kimenetet a §10-ben.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/accessibility/release_flow_text_scale_test.dart test/accessibility/release_flow_semantics_test.dart test/l10n/arb_parity_test.dart test/l10n/hardcoded_string_guard_test.dart
```

## 8. Implementációs sorrend

1. `release_flow_text_scale_test.dart` — a folyam `en` és `hu` cellapárral.
2. `release_flow_semantics_test.dart`.
3. A leletek gyűjtése (NEM javítása).
4. `docs/accessibility/release-audit.md` + `known-exceptions.yaml`.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A locale-páros hiánya.** Egyetlen locale-on futó cella pontosan az ellenkező nyelv beégetését engedi át (a Chapter 13 mért tanulsága).
- **Nem skálázott „skálázott" teszt.** Ha a `textScaler` nem hat, a cella zöld és értéktelen — ezért méri a §6 próbája az eltérést.
- **Javítás-csábítás.** Egy talált túlcsordulás javítása ebben a körben elrejtené, mit mért az audit (§5.2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
