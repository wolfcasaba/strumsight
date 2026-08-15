# E07-R21 — Plan preview, explanation és kézi szerkesztés

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 135ef4af`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 21
- **Kör-azonosító:** `E07-R21`
- **Branch:** `<motor>/e07-r21-plan-preview-and-explanation`
- **Előfeltétel:** `E07-R20` merge-elve (setup wizard)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0264 (faktoronkénti
  indoklás), 0263 (validáció mint kapu) és 0266 (nincs automatikus aktiválás)
  rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R12
> `SkillPriority` faktor-listáját (a magyarázat ebből épül) és az R11
> `PlanValidationIssue` súlyossági szintjeit. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/presentation/screens/plan_preview_screen.dart",
  "lib/features/practice_generator/presentation/widgets/plan_day_card.dart",
  "lib/features/practice_generator/presentation/widgets/plan_block_card.dart",
  "lib/features/practice_generator/presentation/widgets/plan_reason_sheet.dart",
  "lib/features/practice_generator/presentation/controller/plan_preview_controller.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/plan_reason_sheet_test.dart",
  "docs/rounds/e07-r21-plan-preview-and-explanation.md",
]
gate_tests = [
  "test/features/practice_generator/presentation/plan_preview_screen_test.dart",
  "test/features/practice_generator/presentation/plan_reason_sheet_test.dart",
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

A generált terv teljes, átlátható előnézete **mentés és aktiválás előtt**
(SDD Ch8 Kör 21).

## 2. Jelenlegi állapot — mért tények

- Az R12 prioritásai **faktoronként** bonthatók (ADR 0264 §1) — a magyarázat
  ebből épül, nem külön szöveg-generálásból.
- Az R11 validátora `info`/`warning`/`error`/`fatal` leletet ad; `error`
  mellett a terv nem aktiválható (ADR 0263 §1).
- Az offline-first elv (SDD Ch8 §2.4): az előnézet és a magyarázat hálózat
  nélkül működik.

## 3. Scope

**Benne van:** napok és blokkok renderelése · **reason code alapján
lokalizált** magyarázat · idő-, nap-, blokk- és preferencia-szerkesztés ·
**minden szerkesztés után újravalidálás** · figyelmeztetés esetén explicit
áttekintés · aktiválás **csak** felhasználói megerősítésre.

**NINCS benne (tilos):** automatikus mentés vagy aktiválás · a validátor
megkerülése · a domain módosítása · flag `true`-ra állítása · hálózati hívás ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `presentation/screens/plan_preview_screen.dart` | **ÚJ** — az előnézet |
| `presentation/widgets/plan_day_card.dart` | **ÚJ** |
| `presentation/widgets/plan_block_card.dart` | **ÚJ** |
| `presentation/widgets/plan_reason_sheet.dart` | **ÚJ** — a magyarázat |
| `presentation/controller/plan_preview_controller.dart` | **ÚJ** — szerkesztés + újravalidálás |
| `lib/l10n/app_en.arb`, `app_hu.arb` | reason code → szöveg |
| `public.dart` | a barrel bővítése |
| `test/…/presentation/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r21-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor domain- és
application-rétege · más `lib/features/**` · `docs/adr/**` · `tools/**`.

## 5. Kötött architekturális döntések

### 5.1 NINCS rejtett automatikus mentés vagy aktiválás

A terv csak explicit felhasználói megerősítésre válik aktívvá. Az előnézetből
való kilépés nem aktivál.

**NEM elfogadható gyengítés:** „ha megnézte, nyilván akarja".

### 5.2 Minden szerkesztés UTÁN újravalidálás

A kézi módosítás ugyanazon a validátoron megy át, mint a generált terv
(ADR 0263 §1). `error` mellett az aktiválás tiltott — a kézi szerkesztés nem
kerülőút.

### 5.3 A magyarázat REASON CODE-ból lokalizált, nem szabad szöveg

A backend faktorokat és kódokat ad; a szöveg az ARB-ből jön. Így a magyarázat
két nyelven ugyanazt mondja, és offline is működik.

### 5.4 Az evidence-lap NEM állít többet, mint a confidence

Ha a becslés bizonytalan, a magyarázat ezt **kimondja** — nem sugall
bizonyosságot. Az ADR 0261 §3 UI-oldali betartása.

**NEM elfogadható gyengítés:** „a mérés szerint gyenge vagy" olyan adatból,
ami egyetlen bizonytalan mérés.

### 5.5 Az előnézet OFFLINE működik

Nincs hálózati hívás a rendereléshez vagy a magyarázathoz.

### 5.6 Figyelmeztetés esetén EXPLICIT áttekintés

`warning` szintű lelet mellett az aktiválás előtt a felhasználónak látnia
kell a figyelmeztetést — nem elrejtve egy részletek-panelben.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az előnézetből kilépés NEM aktivál és NEM ment | `plan_preview_screen_test.dart` |
| A2 | Minden szerkesztés után újravalidálás fut | ugyanott |
| A3 | `error` lelet mellett az aktiválás tiltott, kézi szerkesztés után is | ugyanott |
| A4 | `warning` mellett explicit megerősítés kell | ugyanott |
| A5 | A magyarázat reason code-ból, ARB-ből jön (hu + en) | `plan_reason_sheet_test.dart` |
| A6 | Bizonytalan becslésnél a magyarázat ezt kimondja | ugyanott |
| A7 | Az előnézet hálózat nélkül működik | ugyanott |
| A8 | Az aktiválás csak explicit megerősítésre történik | `plan_preview_screen_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Kilépéskor automatikus mentés | **A1** |
| A kézi szerkesztés kihagyja a validátort | **A3** |
| A warning egy összecsukott panelben | A4 |
| Hard-kódolt magyarázó szöveg | A5 |
| A magyarázat bizonyosságot sugall bizonytalan adatból | **A6** |
| Hálózati hívás a magyarázathoz | A7 |

**A lelet-súlyosság három kötelező cellája** (a küszöb: az aktiválhatóság):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | csak `info` lelet | aktiválható, külön megerősítés nélkül |
| rajta (a küszöbön) | `warning` lelet | aktiválható, de **explicit áttekintés** után |
| a küszöb fölött | `error` lelet | **nem aktiválható** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd a kézi
szerkesztést újravalidálás nélkül → az **A3** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/presentation/plan_preview_screen_test.dart test/features/practice_generator/presentation/plan_reason_sheet_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. ARB reason-code kulcsok (hu + en).
2. `plan_preview_controller.dart` — szerkesztés + kötelező újravalidálás.
3. `plan_day_card.dart`, `plan_block_card.dart`.
4. `plan_reason_sheet.dart` — faktorokból épített, confidence-hű magyarázat.
5. `plan_preview_screen.dart` — megerősítéshez kötött aktiválás.
6. Tesztek a §6.1 három súlyossági cellájával.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „kényelmes" automatikus mentés.** Kevesebb kattintás, és a tanuló olyan
  tervet kap, amit nem hagyott jóvá (A1).
- **A kézi szerkesztés mint kerülőút.** A felhasználó „tudja, mit csinál" —
  és érvénytelen tervet aktiválna (A3).
- **A túlbeszélő magyarázat.** Egy bizonytalan mérésből határozott ítélet:
  a felhasználó bizalmát rombolja, amikor kiderül (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
