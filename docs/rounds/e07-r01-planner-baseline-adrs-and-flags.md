# E07-R01 — Practice Generator: baseline, ADR-ek és feature flagek

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-15, `main @ 9fe51c9d`)
- **Típus:** **epic-nyitó kör** — Epic 7 (AI Practice Generator), SDD Ch8 Kör 1
- **Kör-azonosító:** `E07-R01`
- **Branch:** `<motor>/e07-r01-planner-baseline-adrs-and-flags`
  (a prefix a driver által feloldott TÉNYLEGES implementer neve, ADR 0242 §5.2)
- **Előfeltétel:** az Epic 6 mind a 30 köre + a GOV-30c öt lépcsője merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0255`](../adr/0255-deterministic-first-practice-planning.md) és
  [`0256`](../adr/0256-practice-plan-revisions-immutable-past.md)
  — **MINDKETTŐ MÁR MEGÍRVA az orchesztrátor által, a `docs/adr/` a TILOS zónában van.**

> **Ez a kör nem ír alkalmazáslogikát.** Két feature flaget vezet be
> (alapértelmezetten OFF), és rögzíti a határokat. Semmilyen felhasználói
> viselkedés nem változik.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/app/config/feature_flags.dart",
  "test/core/architecture_dependency_test.dart",
  "test/app/config/feature_flags_test.dart",
  "docs/rounds/e07-r01-planner-baseline-adrs-and-flags.md",
]
gate_tests = [
  "test/app/config/feature_flags_test.dart",
  "test/core/architecture_dependency_test.dart",
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

Az Epic 7 (AI Practice Generator) fejlesztési határainak és rollout-kapcsolóinak
rögzítése **alkalmazáslogika módosítása nélkül** (SDD Ch8 Kör 1).

## 2. Jelenlegi állapot — mért tények

### 2.1 A `FeatureFlags` alakja és a bővítés HÁROM helye

`lib/app/config/feature_flags.dart`:

- **konstruktor** (`:12`) — három `required` (`accountEnabled`,
  `diagnosticsEnabled`, `labModeAvailable`), a többi **opcionális,
  `= false` alapértelmezéssel**;
- **`factory FeatureFlags.forEnvironment`** (`:58`) — tételesen felsorolja a
  flageket (`22` darab `Enabled: false`/`nonProd` sor);
- **`toString()`** (`:292`) — szintén tételesen sorolja.

**Mind a hármat bővíteni kell**, különben a `toString` hiányos, a gyár pedig
nem állítja be az új flageket.

### 2.2 Az új flagek NEM törnek el meglévő hívót — mérve

`grep -rn "FeatureFlags(" test/` → **51** példányosítás. Mivel az új flagek
**opcionálisak, `= false` alapértelmezéssel**, egyik hívóhely sem törik el.

### 2.3 Fogyasztó nélküli flag MEGENGEDETT — van precedens

Nincs olyan őr, amely minden flaghez fogyasztót követelne, és az
`analysisExperimentalFusionEnabled`-nek **ma sincs fogyasztója** a `lib/`-ben
(mérve: 0 találat a `feature_flags.dart`-on kívül). A két új flag tehát
állhat használat nélkül, amíg a következő körök fel nem építik a generátort.

### 2.4 Az architektúra-őr LÉTEZIK

`test/core/architecture_dependency_test.dart` (467 sor) — „contains exactly
the allowlisted dependency deviations" (`:9`), `allowlist: const {}`
belépési ponttal. A kör ezt **bővíti**, nem írja újra.

### 2.5 A legacy adapterforrások (a SDD Ch8 §3.1 alapján, mérve a kódban)

| terület | ma élő forrás |
|---|---|
| Learn | `lib/features/learn/` |
| Progress | `lib/features/progress/` |
| Streak | `lib/features/progress/` (streak-számítás) |
| Songs / Setlists | `lib/features/song_trainer/` |
| Analyze / Library | `lib/features/audio_analysis/` (V2 shadow-only) |

**Fontos korlát:** az Audio Analysis V2 lánc a GOV-30c óta **futtatható, de
minden flagje OFF**. A generátor tehát **nem építhet** élő V2 elemzésre —
legacy adapteren keresztül lát, és a SDD Ch8 §4.3 kimondja: *„A generátor
domainjét nem szabad az ideiglenes adapterhez igazítani."*

## 3. Scope

**Benne van:**

1. `practiceGeneratorEnabled` és `plannerAssistEnabled` flag bevezetése —
   konstruktor + gyár + `toString`, **mindkettő minden környezetben `false`**.
2. Teszt a két flag alapértelmezésére és a gyár viselkedésére.
3. Az architektúra-őr bővítése: a `features/practice_generator/**` **nem
   importálhat** más feature belső (nem `public.dart`) fájlját, és fordítva.
4. A §10 handoffban a baseline teszt- és buildállapot rögzítése.

**NINCS benne (tilos):**

- **Bármilyen alkalmazáslogika**, `lib/features/practice_generator/**` létrehozása,
  UI, provider, domain-típus. Azok a Kör 2-től jönnek.
- **Bármely flag `true`-ra állítása** — beleértve a két újat (A2).
- `docs/adr/**` (az ADR 0255/0256 megírva), `docs/sdd/**` (a spec forrás),
  `tools/**`, `.github/**`, bármely más `lib/features/**`.
- Új hálózati hívás (A5).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/config/feature_flags.dart` | a két flag a §2.1 három helyén |
| `test/core/architecture_dependency_test.dart` | a generátor import-határa |
| `test/app/config/feature_flags_test.dart` | a flagek alapértelmezése (létrehozandó, ha nincs) |
| `docs/rounds/e07-r01-…md` | a §10 handoff |

**Tilos zóna:** `lib/features/**` (minden feature) · `lib/app/**` a
`config/feature_flags.dart` KIVÉTELÉVEL · `docs/adr/**` · `docs/sdd/**` ·
`tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A két flag KÜLÖN kapcsoló, nem egy

- `practiceGeneratorEnabled` — maga a generátor funkció elérhetősége;
- `plannerAssistEnabled` — a **modell-segített** tervezés elérhetősége.

A SDD Ch8 §2.3 („deterministic-first") és az ADR 0255 szerint a generátornak
**modell nélkül is működnie kell**. Egyetlen közös flag ezt elrejtené: nem
lehetne a determinisztikus utat önmagában élesíteni.

**NEM elfogadható gyengítés:** a két flag összevonása vagy az egyik
származtatása a másikból.

### 5.2 Mindkét flag MINDEN környezetben `false`

A `forEnvironment` gyár több flaget `nonProd`-ra állít. **A két új flag nem
ilyen** — `false` productionben ÉS nem-productionben is, amíg a rollout
külön döntés nem születik.

**NEM elfogadható gyengítés:** `nonProd`-ra állítás „hogy fejlesztés közben
látszódjon". A Lab-mód a látszódás helye, nem a flag alapértelmezése.

### 5.3 Az import-határ MINDKÉT irányban tilt

`features/practice_generator/**` nem importálhat más feature belső fájlját,
és más feature sem importálhatja a generátor belsejét — csak a `public.dart`
barrelt (amikor az létrejön a Kör 2-ben).

### 5.4 A kör nulla alkalmazáslogikát ír

Sem `lib/features/practice_generator/` könyvtár, sem provider, sem UI. A
`git diff --stat` négy fájlnál nem lehet hosszabb.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A két flag létezik a konstruktorban, a gyárban ÉS a `toString`-ben | `feature_flags_test.dart` |
| A2 | **Mindkettő `false` MINDEN környezetben** | `feature_flags_test.dart` — production ÉS nem-production cella |
| A3 | A meglévő 51 `FeatureFlags(...)` hívóhely változatlanul fordul | `flutter analyze` + a teljes teszt-suite |
| A4 | Az architektúra-őr tiltja a generátor kétirányú belső importját | `architecture_dependency_test.dart` |
| A5 | Nincs új hálózati hívás | `git diff` — nincs `dio`/`http` érintés |
| A6 | **Nulla alkalmazáslogika**: nincs `lib/features/practice_generator/` | `git diff --stat` — legfeljebb a §4 négy fájlja |
| A7 | Egyetlen meglévő flag sem változott | `git diff` a `feature_flags.dart`-on: csak HOZZÁADÁS |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A flag csak a konstruktorba kerül be, a gyárba nem | A1 (a gyár-cella) |
| A flag kimarad a `toString`-ből | A1 |
| `nonProd`-ra állítja a gyárban | **A2** (a nem-production cella) |
| A két flaget eggyé vonja | A1 (a hiányzó név) |
| `required`-ként veszi fel (default nélkül) | A3 (az 51 hívóhely nem fordul) |
| Az import-őr csak egy irányban tilt | A4 |
| „Kezdésnek" létrehozza a generátor könyvtárát | **A6** |
| Egy meglévő flag alapértelmezését is átállítja | A7 |

**A flag-alapértelmezés három kötelező cellája** (a határ: a környezet):

| Cella | Bemenet | Elvárt |
|---|---|---|
| production | `AppEnvironment.production` | mindkét flag `false` |
| a határon | `forEnvironment` alapértelmezett hívása | mindkét flag `false` |
| nem-production | `AppEnvironment.development` (vagy staging) | mindkét flag **`false`** — NEM `nonProd` |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a gyárban
az egyik flaget `nonProd`-ra → az **A2** nem-production cellájának PIROSNAK
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/config/feature_flags_test.dart test/core/architecture_dependency_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli, és a
kör `unknown`-ba fut (L254).

## 8. Implementációs sorrend

1. A két flag a konstruktorban (opcionális, `= false`).
2. A gyár (`forEnvironment`) és a `toString` bővítése.
3. `feature_flags_test.dart` — a §6.1 három környezeti cellája.
4. Az architektúra-őr kétirányú tiltása a generátorra.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `nonProd` minta csábítása.** A gyár sok flaget `nonProd`-ra állít; a
  másolás-beillesztés automatikusan ezt hozná. Az A2 nem-production cellája
  pont ezt méri.
- **A `toString` elfelejtése.** Nem tör el semmit, de a diagnosztikai kimenet
  hiányos lesz, és a következő körök erre építenek. Az A1 méri.
- **A „kezdjük is el" késztetés.** Ez baseline-kör; a generátor könyvtárának
  létrehozása is scope-sértés (A6).
- **A generátor domainjének idomítása a legacy adapterhez.** Nem ebben a
  körben dől el, de a SDD Ch8 §4.3 tiltása már itt érvényes: az Analyze V2
  shadow-only, és a domain NEM igazodhat az ideiglenes adapterhez.

## 10. Implementation handoff — az implementer tölti ki

### Módosított fájlok

- `lib/app/config/feature_flags.dart` — hozzáadta a
  `practiceGeneratorEnabled` és `plannerAssistEnabled` opcionális, alapból
  `false` flaget a konstruktorhoz, a környezetgyárhoz, értékszemantikához és
  diagnosztikai `toString()`-hez. A gyár mindkét flaget minden környezetben
  explicit `false` értéken tartja.
- `test/app/config/feature_flags_test.dart` — új háromcellás teszt a
  konstruktor-alapértelmezésre, productionre és developmentre; a `toString()`
  jelenlétét is méri.
- `test/core/architecture_dependency_test.dart` — kétirányú regressziós próba:
  Practice Generator → Learn és Learn → Practice Generator belső importja is
  sértés.

### Végrehajtott ellenőrzések

- `dart format lib/app/config/feature_flags.dart test/app/config/feature_flags_test.dart test/core/architecture_dependency_test.dart`
  — `Formatted 3 files (0 changed)`.
- `flutter test test/app/config/feature_flags_test.dart` — 3 teszt zöld.
- `flutter test test/core/architecture_dependency_test.dart` — 16 teszt zöld.
- `tools/round-gate.sh test/app/config/feature_flags_test.dart test/core/architecture_dependency_test.dart`
  — format: zöld (`1495 files, 0 changed`); analyze: zöld (`No issues found`);
  mindkét célzott teszt, architecture, secrets és l10n is lefutott. A gate
  strukturált záróeredménye: `{"outcome":"pass","exit_code":0,"failed_step":null}`.

### Kötelező valódi-sértés próba

Átmenetileg a gyárban a `practiceGeneratorEnabled: false` értéket
`practiceGeneratorEnabled: nonProd` értékre állítottam. A
`flutter test test/app/config/feature_flags_test.dart` exit kódja 1 lett; az
`factory keeps both flags off in non-production` cella a várt `false` helyett
`Actual: <true>` hibát jelzett. Az értéket azonnal visszaállítottam explicit
`false`-ra, majd a célzott tesztek és a kör-gate újra zöldek voltak.

### Nem futtatott ellenőrzések

- Teljes `flutter test`, property gate és release APK: a kör-gate nem futtatja;
  ezek a kör-branch CI-kapui, az orchestrátor feladatai.

## 11. Review — a Claude tölti ki
