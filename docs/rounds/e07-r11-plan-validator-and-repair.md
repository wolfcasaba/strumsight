# E07-R11 — PlanValidator és deterministic repair

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ ba834de8`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 11
- **Kör-azonosító:** `E07-R11`
- **Branch:** `<motor>/e07-r11-plan-validator-and-repair`
- **Előfeltétel:** `E07-R10` merge-elve (terv-domain)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0263`](../adr/0263-bounded-deterministic-plan-repair.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R10 tényleges
> terv-modelljét és a `PlanChangeSet` alakját (a repair ebbe naplóz), valamint
> az R03 hard/soft korlát-modelljét. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/plan_validation_issue.dart",
  "lib/features/practice_generator/domain/service/plan_validator.dart",
  "lib/features/practice_generator/domain/service/plan_repairer.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/validation/plan_validator_test.dart",
  "test/features/practice_generator/validation/plan_repairer_test.dart",
  "test/property/planner_repair_property_test.dart",
  "docs/rounds/e07-r11-plan-validator-and-repair.md",
]
gate_tests = [
  "test/features/practice_generator/validation/plan_validator_test.dart",
  "test/features/practice_generator/validation/plan_repairer_test.dart",
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

Minden generált és kézzel szerkesztett terv **teljes invariáns-ellenőrzése**,
és korlátos, determinisztikus javítás (SDD Ch8 Kör 11).

## 2. Jelenlegi állapot — mért tények

- Az R03 hard/soft korlát-modellje (ADR 0258): a hard **nem sérthető**.
- Az R10 terv-domainje: revíziók, `completed` múlt, `PlanChangeSet`.
- A projekt property-teszt konvenciója: `test/property/` a `PROPERTY_SEED`
  env-et olvassa (hiányában 42), a CI külön HARD lépést futtat véletlen
  seeddel. **Ez a kör property-tesztet ad** — a repair terminálását fuzz-zal
  kell bizonyítani.

## 3. Scope

**Benne van:** a teljes hard invariáns-lista · `info`/`warning`/`error`/`fatal`
súlyosság · **korlátos, determinisztikus** repair · a repair change setbe
naplózva, **okkal** · hiányzó asset, capability, hangolás és hard-avoid
kezelése · a befejezett múlt módosításának tiltása.

**NINCS benne (tilos):** tervező-algoritmus (Kör 12-től) · repository ·
UI · a hard korlát fellazítása · Flutter, `DateTime.now()`, `Random` (a
property-teszt seedje injektált) · más `lib/features/**`, `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/plan_validation_issue.dart` | **ÚJ** — lelet + súlyosság |
| `domain/service/plan_validator.dart` | **ÚJ** — az invariánsok |
| `domain/service/plan_repairer.dart` | **ÚJ** — korlátos javítás |
| `public.dart` | a barrel bővítése |
| `test/…/validation/*_test.dart` (2 db) | a §6 cellái |
| `test/property/planner_repair_property_test.dart` | **ÚJ** — terminálás fuzz-zal |
| `docs/rounds/e07-r11-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0263)

### 5.1 `error`/`fatal` mellett a terv NEM aktiválható

A validáció eredménye kapu, nem tanács. Hibás terv nem kerülhet végrehajtásra.

### 5.2 A repair TERMINÁL — kimondott iterációs korláttal

A javítás lépésszáma felülről korlátos. Ha a korláton belül nem sikerül,
a repair **feladja** és a hibát jelenti — nem ciklizál.

**NEM elfogadható gyengítés:** „konvergálni fog" feltevés korlát nélkül. A
terminálást a property-teszt bizonyítja, nem az érvelés.

### 5.3 A repair SOHA nem növeli az időt a hard maximum fölé

Egy javítás nem oldhat meg problémát azzal, hogy több időt ír be, mint amit a
tanuló megadott (ADR 0258 §3).

### 5.4 Minden repair-lépés OKKAL naplózott

A `PlanChangeSet`-be strukturáltan bekerül, mit és **miért** változtatott.
Ok nélküli változtatás tilos — enélkül a terv magyarázhatatlanná válik
(ADR 0255 kimondott célja).

### 5.5 A repair DETERMINISZTIKUS

Ugyanaz a hibás terv ugyanazt a javított tervet adja. Nincs `Random`, nincs
óra-olvasás, és a lépések sorrendje rögzített.

### 5.6 A befejezett múltat a repair SEM módosíthatja

Az ADR 0256 §1 a repairre is érvényes: a javítás a jövőt rendezi át.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `error`/`fatal` lelet mellett a terv nem aktiválható | `plan_validator_test.dart` |
| A2 | A repair terminál minden bemenetre | `test/property/planner_repair_property_test.dart` |
| A3 | A repair nem lépi túl a hard időmaximumot | `plan_repairer_test.dart` |
| A4 | Minden repair-lépésnek van OKA a change setben | ugyanott |
| A5 | Ugyanaz a hibás terv → ugyanaz a javított terv | ugyanott |
| A6 | A repair nem módosítja a `completed` múltat | ugyanott |
| A7 | Hard-avoid sértés `error`, nem `warning` | `plan_validator_test.dart` |
| A8 | Hiányzó asset / capability / hangolás detektált | ugyanott |
| A9 | A terhelés-sorrend (load sequencing) invariáns ellenőrzött | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A repair korlát nélkül iterál | **A2** (a fuzz nem terminál) |
| A repair időt ad hozzá a hard max fölé | **A3** |
| Ok nélküli változtatás | A4 |
| `Random` a repairben | A5 |
| A repair a `completed` napot rendezi át | **A6** |
| Hard-avoid csak `warning` | A7 |
| `error` mellett is aktiválható terv | **A1** |

**A súlyosság három kötelező cellája** (a határ: az aktiválhatóság):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | csak `info`/`warning` lelet | a terv **aktiválható** |
| a határon | pontosan egy `error` | **nem aktiválható** |
| fölötte | `fatal` lelet | nem aktiválható, és a repair sem próbálkozik |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a repair
iterációs korlátját → az **A2** property-cellának PIROSNAK (vagy timeoutosnak)
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/validation/plan_validator_test.dart test/features/practice_generator/validation/plan_repairer_test.dart test/property/planner_repair_property_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `plan_validation_issue.dart` — lelet + négy súlyossági szint.
2. `plan_validator.dart` — a teljes hard invariáns-lista.
3. `plan_repairer.dart` — korlátos, determinisztikus, okkal naplózó javítás.
4. A property-teszt a terminálásra (`PROPERTY_SEED` konvencióval).
5. Tesztek a §6.1 három súlyossági cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nem termináló repair.** A „konvergálni fog" feltevés a legveszélyesebb:
  éles adaton fagyást okoz. Ezt csak fuzz bizonyítja (A2).
- **Az idő-hozzáadás mint javítás.** A legegyszerűbb megoldás sok problémára,
  és pont a tanuló megadott korlátját sérti (A3).
- **A repair mint csendes szerkesztő.** Ok nélkül változtatva a terv
  magyarázhatatlan lesz, és a felhasználó bizalma vész el (A4).
- **A `completed` átrendezése.** Egy „takarítás" a múltba nyúlna (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
