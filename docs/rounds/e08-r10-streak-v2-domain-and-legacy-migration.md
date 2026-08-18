# E08-R10 — Streak V2 domain és legacy migráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 10
- **Kör-azonosító:** `E08-R10`
- **Branch:** `<motor>/e08-r10-streak-v2-domain-and-legacy-migration`
- **Előfeltétel:** `E08-R09` merge-elve (legacy backfill)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0308` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/streak/streak_logic.dart` (83 sor) és `model/streak_data.dart` (80 sor) TÉNYLEGES mezőit és szabályait, valamint a `test/features/streak/` öt tesztfájlját — a V2 ezeket őrzi meg, nem írja felül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/streak/streak_state.dart",
  "lib/features/gamification/domain/streak/streak_policy.dart",
  "lib/features/gamification/domain/streak/streak_transition.dart",
  "lib/features/gamification/data/migration/legacy_streak_migrator.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/domain/streak_policy_test.dart",
  "docs/rounds/e08-r10-streak-v2-domain-and-legacy-migration.md",
]
gate_tests = [
  "test/features/gamification/domain/streak_policy_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Migráld a mai `StreakData` modellt verziózott, **policy-alapú** `StreakState` V2-re
— **adatvesztés nélkül**, és úgy, hogy a régi `/streak` útvonal és a régi tesztek
változatlanul működjenek.

## 2. Jelenlegi állapot — mért tények

- `lib/features/streak/streak_logic.dart` (83 sor): `freezeEveryNDays = 7`, `maxFreezes = 3`, `epochDayOf` helyi éjfélből; `applyPractice` szabályai: aznap már gyakorolt → változatlan, `gap == 1` → +1, `gap == 2` és van freeze → +1 és freeze-költés, egyébként reset 1-re.
- `lib/features/streak/model/streak_data.dart` (80 sor) mezői: `current`, `longest`, `lastPracticeDay`, `freezes`, `totalDays`.
- Tároló-kulcs: `ss.streak.state`, legacy párja `practice_streak_v1` (`storage_keys.dart` 45. és 188. sor).
- `test/features/streak/` öt tesztfájl (`streak_logic_test.dart`, `streak_provider_test.dart`, `streak_screen_test.dart`, `daily_challenge_test.dart`, `skill_reframe_test.dart`) MA zöld — ezek nem írhatók át.
- Az [`ADR 0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md) már kimondta: a pihenőnap és a türelmi idő NORMÁLIS állapot, a széria vége tényközlés.

## 3. Scope

**Benne van:** a `current` / `longest` / `freezes` / `totalDays` / `lastPracticeDay` értékek megőrzése ·
`policyVersion`, `graceState` és `plannedRestDays` mezők · **idempotens** migráció a legacy
`practice_streak_v1` kulcsból · a régi `StreakLogic` szabályainak megőrzése tesztelhető, tiszta
policyként · a qualified-day szerződés **definiálása** (a feature-hívások cseréje NEM itt) ·
visszafelé kompatibilis projekció a régi `StreakBadge` számára.

**NINCS benne (tilos):**

- **A `lib/features/streak/**` bármely fájljának módosítása** — a régi rendszer változatlanul él tovább.
- A `test/features/streak/` tesztek átírása vagy törlése — elbukásuk `blocked` jelzés, nem javítási felhatalmazás.
- A qualified-day szabály tényleges alkalmazása a feature-hívásokra — Kör 11.
- UI (Kör 12), hálózat, `docs/adr/**` (az ADR 0308-at a Claude írja).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/streak/streak_state.dart` | **ÚJ** — a verziózott V2 állapot |
| `lib/features/gamification/domain/streak/streak_policy.dart` | **ÚJ** — a tiszta, óra-mentes szabályok |
| `lib/features/gamification/domain/streak/streak_transition.dart` | **ÚJ** — az átmenet + indok-kód |
| `lib/features/gamification/data/migration/legacy_streak_migrator.dart` | **ÚJ** — az idempotens migráció |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/domain/streak_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/streak/**` (a legacy rendszer ÉRINTETLEN)

## 5. Kötött architekturális döntések (ADR 0308)

### 5.1 NULLA streak-adatvesztés — az öt legacy mező mind átjön

A `current`, `longest`, `freezes`, `totalDays` és `lastPracticeDay` értéke a
migráció után **bitre azonos**. A V2 új mezői (`policyVersion`, `graceState`,
`plannedRestDays`) alapértékkel jönnek létre.

**NEM elfogadható gyengítés:** a `longest` újraszámítása az előzményből („pontosabb lesz”).
A legacy érték a felhasználó eddigi legjobbja; egy alacsonyabb újraszámolt érték elvett
teljesítmény.

### 5.2 A policy TISZTA és ÓRA-MENTES — a „ma” a hívótól jön

A mai `StreakLogic` legfontosabb tulajdonsága, hogy nincs benne óra és nincs benne
IO: a hívó adja a mai epoch-napot, ezért kimerítően unit-tesztelhető. A V2 ezt megtartja.

**NEM elfogadható gyengítés:** `DateTime.now()` a policyben. Onnantól az időzóna- és
óraátállítás-esetek nem tesztelhetők, és a Kör 11 óra-anomália szabálya mérhetetlen.

### 5.3 A migráció IDEMPOTENS, és a legacy kulcsot NEM törli

Az újrafuttatás nem változtat az eredményen, és a `practice_streak_v1` kulcs
tartalma érintetlen marad — a régi rendszer (Kör 12-ig) tovább olvassa. A két rendszer
egy ideig párhuzamosan él; ez szándékos.

### 5.4 A régi útvonal és a régi tesztek TOVÁBB MŰKÖDNEK

A `/streak` útvonal és a `test/features/streak/` öt tesztje változatlanul zöld.
Ha bármelyik elbukik, az **`blocked` jelzés** — nem felhatalmazás a teszt átírására.
A visszafelé kompatibilis projekció a régi `StreakBadge` bemenetét adja.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A migráció után az öt legacy mező értéke VÁLTOZATLAN | `streak_policy_test.dart` — mezőnkénti egyezés |
| A2 | A migráció kétszeri futtatása azonos eredményt ad (idempotens) | `streak_policy_test.dart` |
| A3 | A legacy `practice_streak_v1` kulcs tartalma a migráció után is ép | `streak_policy_test.dart` |
| A4 | A V2 policy a mai `StreakLogic` MINDEN szabályát reprodukálja (aznap / gap 1 / gap 2 freeze-zel / nagyobb rés) | `streak_policy_test.dart` — 4 soros átmenet-mátrix |
| A5 | A policy tiszta: nincs `DateTime.now()`, nincs IO — a „ma” paraméter | `streak_policy_test.dart` + review |
| A6 | Minden átmenet indok-kóddal tér vissza | `streak_policy_test.dart` |
| A7 | A `test/features/streak/` öt tesztje VÁLTOZATLANUL zöld | a §7 gate kimenete |
| A8 | A `lib/features/streak/**` ÉRINTETLEN | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `longest` újraszámítása az előzményből | **A1** (a mezőnkénti egyezés-cella) |
| A migráció törli a legacy kulcsot | **A3** |
| `DateTime.now()` a policyben | **A5** |
| A `gap == 2` freeze-ág kimarad | **A4** (az átmenet-mátrix harmadik sora) |
| A régi teszt „hozzáigazítása” a V2-höz | **A7**/**A8** (`git diff --stat` a `streak/` fát mutatja) |
| Az átmenet néma `bool` | **A6** |

**A küszöb három kötelező cellája** (a napok közti rés (`gap = ma - lastPracticeDay`) — a széria fennmaradásának határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `gap == 0` (aznap már gyakorolt) | az állapot **változatlan** — nincs dupla számítás |
| **rajta** (a küszöbön) | `gap == 1` (tegnap gyakorolt) | a széria **+1** — ez a normál folytatás |
| a küszöb **fölött** | `gap == 2` freeze-zel → **+1** és egy freeze elköltve; `gap >= 3` VAGY `gap == 2` freeze nélkül → **reset 1-re** | a mai `StreakLogic` szabálya, változatlanul |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `gap == 2` freeze-ágat a policyből, futtasd a gate-et → az **A4**
átmenet-mátrix harmadik sorának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/domain/streak_policy_test.dart test/features/streak
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `streak_state.dart` — az öt legacy mező + `policyVersion`, `graceState`, `plannedRestDays`, verziózva.
2. `streak_transition.dart` — az átmenet és az indok-kód.
3. `streak_policy.dart` — a mai `StreakLogic` szabályai tiszta, óra-mentes alakban.
4. `legacy_streak_migrator.dart` — idempotens migráció a `practice_streak_v1` kulcsból, a legacy megőrzésével.
5. A qualified-day szerződés DEFINÍCIÓJA (alkalmazás nélkül).
6. Visszafelé kompatibilis projekció a régi `StreakBadge` számára.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a régi streak-tesztekkel EGYÜTT.

## 9. Kockázatok

- **A `longest` „pontosítása”.** A legacy érték a felhasználó legjobbja; bármilyen újraszámítás kockáztatja, hogy alacsonyabb lesz — ez elvett teljesítmény (A1).
- **Az óra behúzása a policybe.** Kényelmes, és a Kör 11 óra-anomália szabályát tesztelhetetlenné teszi (A5).
- **A régi teszt „hozzáigazítása”.** A V2 bevezetése közben a legkézenfekvőbb út a zöldhöz, és pontosan a MAI viselkedést védő hálót bontja le (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
