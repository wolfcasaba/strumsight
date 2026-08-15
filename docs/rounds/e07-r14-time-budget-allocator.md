# E07-R14 — TimeBudgetAllocator és micro-plan

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ bb867ad4`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 14
- **Kör-azonosító:** `E07-R14`
- **Branch:** `<motor>/e07-r14-time-budget-allocator`
- **Előfeltétel:** `E07-R13` merge-elve (jelölt-választó)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határt az ADR 0258 §3 (inkluzív hard
  maximum, befelé kerekítés) már rögzíti.

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
  "test/property/planner_time_budget_property_test.dart",
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

**Benne van:** aktív / eltelt / pihenő / bemelegítő keret szétválasztása ·
minimum blokkhossz és kerekítési szabály · **5 perces micro-plan** politika ·
elsődleges cél minimum-garanciája · értelmetlenül rövid blokkok összevonása
vagy törlése · „ma rövidebb" / „ma hosszabb" döntés change-set okkal.

**NINCS benne (tilos):** ütemezés napokra (Kör 15) · progresszió (Kör 16) ·
a hard maximum túllépése bármilyen indokkal · Flutter, `DateTime.now()`,
`Random` · más `lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/time_budget.dart` | **ÚJ** — a négy keret |
| `domain/policy/time_allocation_policy.dart` | **ÚJ** — minimumok, kerekítés, micro-plan |
| `domain/service/time_budget_allocator.dart` | **ÚJ** — a felosztó |
| `public.dart` | a barrel bővítése |
| `test/…/allocation/*_test.dart` (2 db) | a §6 cellái |
| `test/property/planner_time_budget_property_test.dart` | **ÚJ** — összeg-pontosság |
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

### 5.2 Nincs negatív és nincs törmelék-blokk

Negatív időtartam hiba. A minimum blokkhossznál rövidebb maradék **nem lesz
külön blokk** — összevonódik vagy törlődik, okkal.

### 5.3 Az összeg kerekítés UTÁN is pontos

A blokkok aktív ideje + pihenő + bemelegítő **pontosan** a keretbe fér. Ezt
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

1. `time_budget.dart` — a négy keret, negatív érték tiltásával.
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

## 11. Review — a Claude tölti ki
