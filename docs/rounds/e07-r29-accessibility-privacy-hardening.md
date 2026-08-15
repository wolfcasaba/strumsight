# E07-R29 — Accessibility, localization, privacy és safety hardening

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0afb9994`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 29
- **Kör-azonosító:** `E07-R29`
- **Branch:** `<motor>/e07-r29-accessibility-privacy-hardening`
- **Előfeltétel:** `E07-R28` merge-elve (assist gateway)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0260 §4 (érzékeny szöveg),
  0265 §3 (discomfort blokkol) és 0270 rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a projekt **l10n
> paritás-ellenőrzőjét** (`tools/check_l10n_parity` vagy a `test/tooling/`
> megfelelője) és a meglévő adatvédelmi dokumentumok helyét
> (`docs/privacy/`). Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/presentation/screens/plan_privacy_screen.dart",
  "lib/features/practice_generator/application/usecase/delete_practice_planning_data.dart",
  "lib/features/practice_generator/application/usecase/export_practice_planning_data.dart",
  "lib/features/practice_generator/public.dart",
  "docs/privacy/practice-planning-data.md",
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
  "docs/rounds/e07-r29-accessibility-privacy-hardening.md",
]
gate_tests = [
  "test/features/practice_generator/accessibility/planner_accessibility_test.dart",
  "test/features/practice_generator/accessibility/planner_privacy_test.dart",
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

A teljes funkció publikálás előtti hozzáférhetőségi, adatvédelmi és
biztonsági megerősítése (SDD Ch8 Kör 29).

## 2. Jelenlegi állapot — mért tények

- Az R20-R22, R26-R27 UI-köreiben már ARB-alapú szövegek vannak.
- Az ADR 0260 §4: **érzékeny szabad szöveg nem naplózható**.
- Az ADR 0265 §3: **a fájdalomjelzés blokkolja a nehezítést**.
- A flagek **OFF** — ez a kör sem kapcsol be semmit.

## 3. Scope

**Benne van:** teljes hu/en paritás · nagy betűméret és képernyőolvasó-sorrend
auditja · reduced motion és **nem szín-alapú** státuszjelölés · telemetria és
napló redakciója · kényelmetlenség-visszajelzés biztonsági folyamata ·
**teljes törlés/export** UX · a manipulatív szövegezés auditja.

**NINCS benne (tilos):** új funkció · flag `true`-ra állítása · a domain
módosítása · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/l10n/app_en.arb`, `app_hu.arb` | a paritás lezárása |
| `presentation/screens/plan_privacy_screen.dart` | **ÚJ** — törlés/export |
| `application/usecase/delete_practice_planning_data.dart` | **ÚJ** |
| `application/usecase/export_practice_planning_data.dart` | **ÚJ** |
| `docs/privacy/practice-planning-data.md` | **ÚJ** — mit tárolunk és meddig |
| `public.dart` | a barrel bővítése |
| `test/…/accessibility/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r29-…md` | a §10 handoff |

**Tilos zóna:** `lib/app/config/feature_flags.dart` · a generátor domain- és
application-logikája (a két új use case kivételével) · más `lib/features/**` ·
`docs/adr/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Érzékeny adat SEHOL nem kerül naplóba vagy telemetriába

Az ADR 0260 §4 kiterjesztése a telemetriára is. A napló azonosítót és
kategóriát írhat, tartalmat nem.

### 5.2 A fájdalomjelzés NEM indít progressziót — UI-oldalon is

Az ADR 0265 §3 felületi betartása: a kényelmetlenség jelzése után a UI nem
kínál nehezítést, és a biztonsági folyamat elérhető.

### 5.3 A státusz NEM lehet csak szín-alapú

Minden állapot (kész, kihagyott, pihenő) **szövegesen vagy ikonnal** is
jelölt. Szín-vakság mellett is használható.

### 5.4 Minden akció elérhető billentyűzettel és képernyőolvasóval

Nincs csak-érintéses vagy csak-gesztus akció.

### 5.5 A törlés TÉNYLEGES, és a policy szerinti kört törli

A „minden adat törlése" a tervet, a revíziókat és a hozzájuk kötött
evidence-et is törli a dokumentált policy szerint — nem csak elrejti.
Az export ugyanezt a kört adja ki.

### 5.6 A szövegezés NEM manipulatív

Se bűntudatkeltés, se hamis sürgetés („már 3 napja nem…"). Ez acceptance-cella
(A8), az R27 §5.5 folytatása.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Teljes hu/en ARB-paritás | l10n paritás-ellenőrző |
| A2 | Nagy betűméretnél nincs túlcsordulás a generátor képernyőin | `planner_accessibility_test.dart` |
| A3 | Minden akció elérhető képernyőolvasóval | ugyanott |
| A4 | A státusz nem csak szín-alapú | ugyanott |
| A5 | Reduced motion tiszteletben tartva | ugyanott |
| A6 | Érzékeny adat nincs naplóban/telemetriában | `planner_privacy_test.dart` |
| A7 | Törlés után a policy szerinti adat ténylegesen eltűnik | ugyanott |
| A8 | A szövegek nem manipulatívak (audit + review) | review + ARB diff |
| A9 | Fájdalomjelzés után a UI nem kínál nehezítést | `planner_accessibility_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A szabad szöveg telemetriában | **A6** |
| Csak szín jelzi a kihagyott napot | **A4** |
| A törlés csak elrejti az adatot | **A7** |
| Fix magasságú sor nagy betűméretnél | A2 |
| Csak-gesztus akció | A3 |
| Fájdalom után is felkínált nehezítés | **A9** |

**A törlés három kötelező cellája** (a küszöb: a policy szerinti kör):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | csak a terv törlése | a terv eltűnik, az evidence a policy szerint marad |
| rajta (a küszöbön) | „minden tervezési adat" | a **teljes** policy-kör törlődik |
| a küszöb fölött | más feature adata (pl. Learn-előzmény) | **érintetlen** — nem törlünk túl |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írd a tanuló
kényelmetlenség-megjegyzését a telemetriába → az **A6** cellának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/accessibility/planner_accessibility_test.dart test/features/practice_generator/accessibility/planner_privacy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. ARB-paritás lezárása (hu + en).
2. `docs/privacy/practice-planning-data.md` — mit tárolunk, meddig, mit törlünk.
3. `delete_…` és `export_…` use case-ek a dokumentált kör szerint.
4. `plan_privacy_screen.dart`.
5. Hozzáférhetőségi audit: nagy betű, semantics, nem-szín státusz, reduced motion.
6. Redakciós audit a naplón és telemetrián.
7. Tesztek a §6.1 három törlés-cellájával.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A telemetria mint kiskapu.** A naplót figyeljük, a telemetriát elfelejtjük
  — és a legérzékenyebb adat ott megy ki (A6).
- **A túl sokat törlő „mindent töröl".** Más feature adatát is elvinné (A7,
  a harmadik cella).
- **A szín-alapú státusz.** Szépen néz ki, és a felhasználók egy része nem
  látja (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
