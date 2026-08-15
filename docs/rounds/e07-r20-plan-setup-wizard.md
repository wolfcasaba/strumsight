# E07-R20 — Plan setup wizard és input UX

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 135ef4af`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 20
- **Kör-azonosító:** `E07-R20`
- **Branch:** `<motor>/e07-r20-plan-setup-wizard`
- **Előfeltétel:** `E07-R19` merge-elve (repository)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0259 (draft) és
  0260 §4 (érzékeny szöveg nem naplózható) rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a projekt **ARB/l10n**
> mintáját (`lib/l10n/app_hu.arb`, `app_en.arb`) és a meglévő wizard-jellegű
> képernyők szerkezetét. **Minden felhasználói szöveg ARB-n át megy.**
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/presentation/screens/plan_setup_screen.dart",
  "lib/features/practice_generator/presentation/widgets/practice_goal_picker.dart",
  "lib/features/practice_generator/presentation/widgets/availability_editor.dart",
  "lib/features/practice_generator/presentation/controller/plan_setup_controller.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/availability_editor_test.dart",
  "docs/rounds/e07-r20-plan-setup-wizard.md",
]
gate_tests = [
  "test/features/practice_generator/presentation/plan_setup_screen_test.dart",
  "test/features/practice_generator/presentation/availability_editor_test.dart",
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

A generálási kérés egyszerű, **hozzáférhető** és megszakítás után folytatható
felülete (SDD Ch8 Kör 20).

## 2. Jelenlegi állapot — mért tények

- Az R04 draft-repositoryja lépésenkénti mentést tesz lehetővé (ADR 0259 §3).
- Az R03 `RequestValidator`-a azonnal jelzi a hard konfliktust.
- Az ADR 0260 §4: a **kényelmetlenségre vonatkozó szabad szöveg nem
  naplózható**.
- A `practiceGeneratorEnabled` flag **OFF** — a képernyő a flag mögött él.

## 3. Scope

**Benne van:** cél-, ütemezés-, felszerelés-, preferencia- és kényelem-lépés ·
**„nem tudom"** válaszok támogatása · lépésenkénti draft-mentés · hard
konfliktus azonnali jelzése · reduced-motion és képernyőolvasó támogatás ·
magyar és angol lokalizáció.

**NINCS benne (tilos):** a terv előnézete (Kör 21) · aktiválás · a domain vagy
a validátor módosítása · **bármely flag `true`-ra állítása** · érzékeny szöveg
naplózása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `presentation/screens/plan_setup_screen.dart` | **ÚJ** — a wizard |
| `presentation/widgets/practice_goal_picker.dart` | **ÚJ** |
| `presentation/widgets/availability_editor.dart` | **ÚJ** |
| `presentation/controller/plan_setup_controller.dart` | **ÚJ** — lépés-állapot + draft |
| `lib/l10n/app_en.arb`, `app_hu.arb` | a felhasználói szövegek |
| `public.dart` | a barrel bővítése |
| `test/…/presentation/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r20-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor **domain**
és **application** rétege · más `lib/features/**` · `docs/adr/**` · `tools/**`.

## 5. Kötött architekturális döntések

### 5.1 A „nem tudom" ELSŐOSZTÁLYÚ válasz

Minden kérdésnél megadható, és **nem** vezet kitalált alapértékhez. Az
`unknown` a domainben is önálló állapot (ADR 0261 §2) — az UI ezt tükrözi.

**NEM elfogadható gyengítés:** a „nem tudom" néma átfordítása egy default
értékre. Az a tanuló nevében hazudna a rendszernek.

### 5.2 A visszalépés NEM veszít adatot

A wizard bármely lépéséről vissza lehet lépni a korábban megadott adatok
elvesztése nélkül.

### 5.3 A hard konfliktus AZONNAL látszik

Nem a végén, összegyűjtve. A tanuló ott javíthat, ahol a hibát elkövette.

### 5.4 A kényelmetlenségi szabad szöveg SOHA nem kerül naplóba

Az ADR 0260 §4 UI-oldali betartása. A napló azonosítót írhat, tartalmat nem.

### 5.5 Minden szöveg ARB-n át megy

Magyar és angol. Hard-kódolt felhasználói szöveg tilos.

### 5.6 Nagy betűméretnél nincs túlcsordulás

A hozzáférhetőség nem opció. A teszt nagy szövegméretet is mér.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az alapfolyamat végigvihető, és a draft lépésenként mentődik | `plan_setup_screen_test.dart` |
| A2 | Az app újraindítása után a wizard folytatható | ugyanott |
| A3 | A visszalépés nem veszít adatot | ugyanott |
| A4 | A „nem tudom" NEM vezet default értékhez | ugyanott |
| A5 | A hard konfliktus azonnal látszik | ugyanott |
| A6 | Nagy betűméretnél nincs túlcsordulás | `availability_editor_test.dart` |
| A7 | Semantics (képernyőolvasó) címkék jelen vannak | ugyanott |
| A8 | Minden szöveg ARB-ből jön (hu + en) | l10n paritás-ellenőrzés |
| A9 | A kényelmetlenségi szöveg nem kerül naplóba | `plan_setup_screen_test.dart` — gyűjtő logger |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A „nem tudom" default értékre fordítva | **A4** |
| A draft csak a végén mentődik | A1/A2 |
| A visszalépés törli a lépés adatait | A3 |
| A konfliktus csak a végén jelenik meg | A5 |
| Hard-kódolt felhasználói szöveg | A8 |
| A szabad szöveg naplózva | **A9** |
| Fix magasságú sorok nagy betűméretnél | A6 |

**A wizard-állapot három kötelező cellája** (a határ: a megkezdett lépés):

| Cella | Bemenet | Elvárt |
|---|---|---|
| lépés előtt | a wizard el sem indult | nincs draft, üres állapot |
| a határon | **egy** lépés kitöltve, app újraindul | a draft visszatér, a wizard ott folytatódik |
| lépés után | minden lépés kitöltve, app újraindul | a teljes draft visszatér, generálás indítható |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** fordítsd a „nem
tudom"-ot default értékre → az **A4** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/presentation/plan_setup_screen_test.dart test/features/practice_generator/presentation/availability_editor_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. ARB-kulcsok (hu + en) — a szövegek előre.
2. `plan_setup_controller.dart` — lépés-állapot, draft-mentés lépésenként.
3. `availability_editor.dart` és `practice_goal_picker.dart`.
4. `plan_setup_screen.dart` — navigáció, azonnali konfliktus-jelzés.
5. Tesztek a §6.1 három wizard-cellájával, nagy betűmérettel és semantics-szel.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „nem tudom" elnyelése.** A legkényelmesebb UI-döntés, és a rendszer a
  tanuló nevében találna ki adatot (A4).
- **A végén mentő draft.** Egyszerűbb, és pont a megszakítás utáni
  folytathatóságot veszi el (A1).
- **A naplózott kényelmetlenség.** Hibakeresés közben kézenfekvő, és a
  legérzékenyebb adatot viszi ki (A9).
- **A hard-kódolt szöveg.** Gyorsabb fejlesztés, és a magyar lokalizáció
  hiányzik majd (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
