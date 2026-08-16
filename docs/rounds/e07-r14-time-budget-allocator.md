# E07-R14 — TimeBudgetAllocator és micro-plan

- **Státusz:** PRE-FLIGHT REVISED (2026-08-16, `main @ 3643444a`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 14
- **Kör-azonosító:** `E07-R14`
- **Branch:** `<motor>/e07-r14-time-budget-allocator`
- **Előfeltétel:** `E07-R13` merge-elve (jelölt-választó)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [0298](../adr/0298-time-budget-allocation-contract.md)

## 0.0 Pre-flight revízió (2026-08-16)

**Mért eltérések és feloldásuk.** A brief korábbi alapja `bb867ad4` volt, a
dispatch előtti tényleges alap `3643444a`. A `weekly_availability.dart`
`DailyAvailability` modellje egy helyi `LocalDate`-hez tartozó,
`minimumMinutes <= targetMinutes <= maximumMinutes` perceket tárol; a hard
maximumot `maximumStrength == ConstraintStrength.hard` jelöli. A feature-ben
az időkeretet nem birtokolja lease vagy más lifecycle-erőforrás: a teljes
`lib/features/practice_generator` hívási láncban nincs `.acquire(...)` hívás.

Az SDD Ch8 §21.1 öt, nem négy budget-típust nevez meg:
`activePlaying`, `elapsedSession`, `rest`, `setup`, `reflection`. A felhasználó
által adott napi idő az `elapsedSession`; a többi három nem aktív reserve és
az aktív játék összege pontosan ezt adja. A korábbi „négy keret” szöveg ezért
pontatlan volt, a speciális ötperces mód pedig nem arányosan zsugorított terv:
pontosan egy primary active-playing fókuszblokkot ad, miközben a setup/reserve
idő továbbra is a teljes elapsed budget része.

**Scope-revízió.** A foglaló által kiosztott ADR 0298 és a három új teszt
ugyanazon nem triviális time-budget bemenetét építő, bare
`test/fixtures/practice_generator/allocation/` könyvtár bekerült az
engedélyezett listába. Ez a L294 szerinti megelőző scope-szűkítés; más
production contract nem változik. Az ADR rögzíti a pontos budget-identitást,
az inkluzív hard maximumot, a lefelé kerekítést és a typed change-ok okát.

**Kiszámolt küszöbcellák.** `python3 -c 'print(20-1, 20, 20+1)'` → `19 20 21`:
19 és 20 perc belefér, a 21 perces jelöltet befelé kell javítani 20-ra.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03
> `weekly_availability.dart` tényleges mezőit (helyi dátum, percek, hard
> maximum jelölése) — a §5.1 erre épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/time_budget.dart",
  "lib/features/practice_generator/domain/policy/time_allocation_policy.dart",
  "lib/features/practice_generator/domain/service/time_budget_allocator.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/allocation/time_budget_allocator_test.dart",
  "test/features/practice_generator/allocation/time_allocation_policy_test.dart",
  "test/fixtures/practice_generator/allocation",
  "test/property/planner_time_budget_property_test.dart",
  "docs/adr/0298-time-budget-allocation-contract.md",
  "docs/rounds/e07-r14-time-budget-allocator.md",
]
gate_tests = [
  "test/features/practice_generator/allocation/time_budget_allocator_test.dart",
  "test/features/practice_generator/allocation/time_allocation_policy_test.dart",
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

A napi idő **pontos**, pedagógiailag használható felosztása — 5 perctől
90 percig (SDD Ch8 Kör 14).

## 2. Jelenlegi állapot — mért tények

- Az ADR 0258 §3: a hard napi maximum **inkluzív**, és a kerekítés **befelé**
  történik.
- Az R03 elérhetősége helyi dátumhoz kötött, percekben.
- Az R09 receptjei korlátosak (nincs végtelen blokk).
- A projekt property-teszt konvenciója: `test/property/`, `PROPERTY_SEED`
  (hiányában 42), CI-ban külön HARD lépés. **Az összeg-pontosságot property
  bizonyítja.**

## 3. Scope

**Benne van:** `activePlaying` / `elapsedSession` / `rest` / `setup` /
`reflection` keret szétválasztása ·
minimum blokkhossz és kerekítési szabály · **5 perces micro-plan** politika ·
elsődleges cél minimum-garanciája · értelmetlenül rövid blokkok összevonása
vagy törlése · „ma rövidebb" / „ma hosszabb" döntés change-set okkal.

**NINCS benne (tilos):** ütemezés napokra (Kör 15) · progresszió (Kör 16) ·
a hard maximum túllépése bármilyen indokkal · Flutter, `DateTime.now()`,
`Random` · más `lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/time_budget.dart` | **ÚJ** — az öt typed budget |
| `domain/policy/time_allocation_policy.dart` | **ÚJ** — minimumok, kerekítés, micro-plan |
| `domain/service/time_budget_allocator.dart` | **ÚJ** — a felosztó |
| `public.dart` | a barrel bővítése |
| `test/…/allocation/*_test.dart` (2 db) | a §6 cellái |
| `test/fixtures/practice_generator/allocation/` | közös, paraméterezhető time-budget teszt-builderek |
| `test/property/planner_time_budget_property_test.dart` | **ÚJ** — összeg-pontosság |
| `docs/adr/0298-…md` | az öt budget és a hard-max határ szerződése |
| `docs/rounds/e07-r14-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A hard maximum SOHA nem sérül — kerekítés után sem

A kerekítés a leggyakoribb csendes túllépés forrása: három blokk felfelé
kerekítve együtt túllépi a napi maximumot. **A kerekítés befelé történik**, és
az összeg ellenőrzött (ADR 0258 §3).

**NEM elfogadható gyengítés:** „egy perc túllépés belefér". A tanuló megadott
korlátja szerződés.

### 5.1.1 Az elapsed budget öt typed részből áll

`elapsedSession == activePlaying + rest + setup + reflection` minden sikeres
allocationnál. A `TimeBudget` az öt SDD-nevű typed mennyiséget hordozza; a
warmup a `activePlaying` kategóriáján belüli tartalom, nem hatodik keret.
`setup`, `rest` és `reflection` reserve-e nem jelenhet meg aktív játékidőként.
Az ADR 0298 rögzíti ezt a határt.

### 5.2 Nincs negatív és nincs törmelék-blokk

Negatív időtartam hiba. A minimum blokkhossznál rövidebb maradék **nem lesz
külön blokk** — összevonódik vagy törlődik, okkal.

### 5.3 Az összeg kerekítés UTÁN is pontos

A teljes `elapsedSession` (`activePlaying + rest + setup + reflection`)
**pontosan** a keretbe fér. Ezt
property-teszt bizonyítja, nem néhány kézzel írt eset.

### 5.4 Az elsődleges cél MINIMUM-garanciát kap

Ha a nap egyáltalán tartalmaz gyakorlást, az elsődleges célhoz tartozó blokk
minimum-időt kap — különben a rövid napokon a fő cél kiszorulna.

### 5.5 A 5 perces micro-plan ÉRTELMES, nem arányos zsugorítás

Öt percnél nem az egész terv arányos kicsinyítése történik, hanem külön
politika: egyetlen fókuszált blokk. Az arányos zsugorítás 40 másodperces
blokkokat adna.

### 5.6 A rövidítés/hosszabbítás OKKAL jár

A „ma rövidebb" döntés `PlanChangeSet`-be kerül indoklással (ADR 0263 §4
mintájára).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A hard maximum kerekítés után sem sérül | `time_budget_allocator_test.dart` |
| A2 | 5 / 10 / 20 / 45 / 90 perces keretek mind értelmes tervet adnak | ugyanott |
| A3 | Nincs negatív és nincs minimum alatti töredékblokk | ugyanott |
| A4 | Az összeg kerekítés után is pontos | `test/property/planner_time_budget_property_test.dart` |
| A5 | Az elsődleges cél minimum-garanciát kap | `time_budget_allocator_test.dart` |
| A6 | Az 5 perces terv EGY fókuszált blokk, nem arányos zsugorítás | ugyanott |
| A7 | A rövidítés change-set okot ad | ugyanott |
| A8 | A felosztás determinisztikus | `time_allocation_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Felfelé kerekítés blokkonként | **A1** és **A4** |
| Arányos zsugorítás 5 percnél | **A6** (40 másodperces blokkok) |
| A maradék külön blokként megtartva | A3 |
| Az elsődleges cél kiszorul rövid napon | A5 |
| A rövidítés indoklás nélkül | A7 |

**A napi keret három kötelező cellája** (a határ: a hard maximum):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | hard max 20, felosztott összeg 19 | elfogadva |
| a határon | hard max 20, felosztott összeg **20** | **elfogadva** (inkluzív) |
| fölötte | a kerekítés 21-re vinné | **befelé kerekít**, az összeg 20 marad |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a kerekítést
felfelé → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/allocation/time_budget_allocator_test.dart test/features/practice_generator/allocation/time_allocation_policy_test.dart test/property/planner_time_budget_property_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `time_budget.dart` — az öt typed budget, negatív érték tiltásával.
2. `time_allocation_policy.dart` — minimumok, befelé kerekítés, micro-plan.
3. `time_budget_allocator.dart` — a felosztás, összeg-ellenőrzéssel.
4. A property-teszt az összeg pontosságára.
5. Tesztek a §6.1 három keret-cellájával és az öt keret-mérettel.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A kerekítés.** A legalattomosabb hiba: blokkonként egy-egy perc, együtt
  túllépés — és csak a felhasználó naptárában látszik (A1).
- **Az arányos micro-plan.** Egyszerű képlet, és használhatatlan
  40 másodperces blokkokat ad (A6).
- **A törmelék-blokk.** „Maradt 2 perc, tegyük be" — pedagógiailag értéktelen,
  és a napot zsúfoltnak mutatja (A3).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Módosított / új fájlok

| Útvonal | Állapot |
|---|---|
| `lib/features/practice_generator/domain/model/time_budget.dart` | **ÚJ** — az öt typed budget + `PlannedActiveSegment`. |
| `lib/features/practice_generator/domain/policy/time_allocation_policy.dart` | **ÚJ** — `TimeAllocationPolicy` + öt `PlanTemplate` (micro/small/medium/large/extraLarge). |
| `lib/features/practice_generator/domain/service/time_budget_allocator.dart` | **ÚJ** — `TimeBudgetAllocator` + `TimeBudgetAllocation` + `TimeBudgetScaling` + `TimeBudgetAllocationEvidence`. |
| `lib/features/practice_generator/public.dart` | bővítve 3 export sorral. |
| `test/features/practice_generator/allocation/time_budget_allocator_test.dart` | **ÚJ** — A1, A2, A3, A5, A6, A7. |
| `test/features/practice_generator/allocation/time_allocation_policy_test.dart` | **ÚJ** — A8 + policy-shape coverage. |
| `test/fixtures/practice_generator/allocation/allocation_fixtures.dart` | **ÚJ** — `buildAvailability` + `runAllocation` segédfüggvények. |
| `test/property/planner_time_budget_property_test.dart` | **ÚJ** — A4 (sum precision) + A3/A5/A7/A8-as spot-checks. |

### 10.2 Algoritmus (rövid)

A `TimeBudgetAllocator.allocate` a következő lépéseket hajtja végre:

1. **Hard maximum clamp.** Ha `requestedTotal > hardMaximum`, a kért összeg le
   van vágva a hard maximumra (inkluzív felső határ, ADR 0298 §2).
2. **Sablon kiválasztása.** A `policy.templateFor(total)` a teljes
   `elapsedSession` alapján választ: micro (≤5), small (6–12), medium (13–30),
   large (31–60), extraLarge (>60).
3. **Reserve-ek levonása.** A sablon rögzíti a `setupMinutes`,
   `reflectionMinutes` és a blokkok közötti `restPerGapMinutes` értékeit; ezek
   a fix tartalékok.
4. **Active felosztás.** A maradék `activeAvailable` percet a sablon
   slot-jaira osztja: minden slot a saját `minimums[i]` percét kapja
   alaphangon, a maradék pool egyenletesen oszlik, az 1-perces maradék a
   primary focus-ba kerül (priority order). Ezzel a `pool ~/ slots`-os
   lefelé kerekítés és az exact-budget repair garantálja, hogy a
   `segments.sum == activePlaying` pontosan.
5. **Safe overload.** Ha a sablon `minimums` összege nem fér bele az
   `activeAvailable`-ba, a rendszer egyetlen primary focus blokkra esik
   vissza, ami a teljes kért időt viszi — ez a fragment-policy (§5.2).
6. **Change-set.** Ha a clamp bármennyi időt levágott, a `TimeBudgetAllocation`
   egy `PlanChangeSet`-et ad `PlanChangeReason.systemAdaptation` okkal és
   `timeBudget.hardMaximumClamped` bizonyítékkal.

### 10.3 A5 cella primary-minimum értelmezése

A brief A5 cellája kimondja: „Ha a nap egyáltalán tartalmaz gyakorlást, az
elsődleges célhoz tartozó blokk minimum-időt kap". A property-teszt az
`requestedTotal >= primaryMinimumMinutes` esetre szorítkozik, mert a
§5.5-ös micro-plan a teljes napot a primary focus-ba önti (akár 1 percre
is), és ilyenkor a minimum szándékosan a fenntarthatóságnál alacsonyabb:
a `time_budget_allocator_test.dart` A5-ös cellái a 13/90 perces keretekre
szorítkoznak, ahol a minimum garantálható.

### 10.4 Valódi-sértés próba (A1/A4)

**Mért cella.** A felfelé kerekítés a `_allocateBlocks` `perSlot` változóján:
`pool ~/ slots` → `(pool + slots - 1) ~/ slots` (ceiling).

**A1 / A4 próbaeredmények (review-hoz, nem kerül commit-ba):**

- `time_budget_allocator_test.dart`:

  - A1 felső cella (`above the hard maximum is clamped down to the limit`):
    PIROS — a 25 ≥ 20 clamp esetén a felfelé kerekítés 22 percet adott a
    20-as hard maximum helyett.
  - A1 `exactly at the hard maximum is accepted as the inclusive top`: PIROS
    — a 20-as kérésre 22 percet generált.
  - A1 `below the hard maximum is accepted without scaling`: PIROS — a
    19-es kérésre 21 percet generált.
  - A1 `every segment is non-negative and the sum is exact`: PIROS — a
    90-perces keretben 92 percet mutatott (2 perccel túllépve).
  - A2 20/45/90 cellák: PIROS — mind az `elapsedSession`, mind a
    `segments.sum` assertion-ön elbukott.
  - A2 5/10 cellák: ZÖLD — az aktív 1 slot elegendő ahhoz, hogy a
    felfelé kerekítés azonos maradjon a lefelével (nincs maradék).
  - A3/A5/A6/A7/A8 cellák: ZÖLD — a fragment-policy, a primary-minimum
    és a determinizmus nem függ a kerekítés irányától.

- `planner_time_budget_property_test.dart` (`A4`):

  - PIROS trial 0-ban: 48 perces hard maximumot a felfelé kerekítés 51
    percre vitte (3 perccel túllépve). A `lessThanOrEqualTo(hardMaximum)`
    assertion elbukott; a maradék 299 trial-ra a teszt nem jutott el.

**Visszaállítás.** A `perSlot` sort visszaírtam `pool ~/ slots` (floor)
értékre — a `time_budget_allocator_test.dart` 17 / 17 cellája, a
`time_allocation_policy_test.dart` 5 / 5 cellája és a property-teszt
300 / 300 trial-ja ismét zöld.

A dokumentum megerősíti, hogy a lefelé kerekítés nem placebo: a felfelé
kerekítés konkrétan, mérhetően töri a hard maximumot — a 90 perces
keret +2 perccel, a property-teszt +3 perccel lépte azt át.

### 10.5 Gate

```bash
tools/round-gate.sh test/features/practice_generator/allocation/time_budget_allocator_test.dart test/features/practice_generator/allocation/time_allocation_policy_test.dart test/property/planner_time_budget_property_test.dart
```

A kapu előtérben, csonkítatlan kimenettel fut. Implementer-jelzés:

`tools/codex-signal.sh done "E07-R14 implementálva; célzott gate zöld; commit=<sha>"`

## 11. Review — a Claude tölti ki

