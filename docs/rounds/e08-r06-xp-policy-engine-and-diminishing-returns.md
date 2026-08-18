# E08-R06 — XP policy engine és csökkenő hozam

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 6
- **Kör-azonosító:** `E08-R06`
- **Branch:** `<motor>/e08-r06-xp-policy-engine-and-diminishing-returns`
- **Előfeltétel:** `E08-R05` merge-elve (eligibility policy)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0304` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R05 `reward_eligibility_policy.dart` négy kapujának TÉNYLEGES szignatúráját — az XP-motor csak jogosult komponensre számol; és az R03 `reward_ledger_entry.dart` XP-komponens mezőit. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/rewards/experience_points.dart",
  "lib/features/gamification/application/reward_policy_engine.dart",
  "lib/features/gamification/infrastructure/default_reward_policy.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/reward_policy_engine_test.dart",
  "docs/rounds/e08-r06-xp-policy-engine-and-diminishing-returns.md",
]
gate_tests = [
  "test/features/gamification/application/reward_policy_engine_test.dart",
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

Implementáld a verziózott, **magyarázható** és farmolás-álló XP-számítást: base,
duration, quality, improvement és diversity komponensekkel, napi és gyakorlat-specifikus
csökkenő hozammal.

## 2. Jelenlegi állapot — mért tények

- Az R05 szállította a négy jogosultsági kaput indok-kóddal; az R03 a főkönyvet, amely XP-komponenseket és policy-verziót tárol.
- `experience_points.dart` és a policy-motor **nem létezik** — ez a kör hozza létre.
- Az `ADR 0290` §2 kimondja: a felület NEM számol jutalmat — a számítás kizárólag itt, az application-rétegben történik.
- Az `ADR 0289` kimondja: az XP a részvételt méri, nem a tudást — ezért az XP soha nem lehet elsajátítottság-forrás.

## 3. Scope

**Benne van:** a base / duration / quality / improvement / diversity komponensek · napi és
gyakorlat-specifikus csökkenő hozam · az ismétlés-XP korlátozása a gyakorlási előzmény
korlátozása NÉLKÜL · szülő-gyermek események kezelése a dupla jutalom ellen · a
plafon-csökkentés okának rögzítése a nyugtában · balance-konfiguráció + policy-verzió.

**NINCS benne (tilos):**

- A jogosultság eldöntése — Kör 5. Ez a motor csak jogosult komponensre számol.
- Szintgörbe és profil-projekció — Kör 7.
- Bármely UI: a felület nem számol jutalmat (ADR 0290 §2).
- Az XP felhasználása elsajátítottság kimondására (ADR 0289) — abszolút tilos.
- `docs/adr/**` — az ADR 0304-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/rewards/experience_points.dart` | **ÚJ** — az XP-érték és komponensei |
| `lib/features/gamification/application/reward_policy_engine.dart` | **ÚJ** — a számítás interfésze |
| `lib/features/gamification/infrastructure/default_reward_policy.dart` | **ÚJ** — a balance-konfiguráció és az alapértelmezett policy |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/reward_policy_engine_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0304)

### 5.1 Minden XP MAGYARÁZHATÓ — komponensenként lebontva

Az eredmény nem egyetlen szám: komponensenkénti bontás, amelyből a felület meg
tudja mondani, **miért** annyi. A plafon miatti csökkentés külön, okkal együtt szerepel.

**NEM elfogadható gyengítés:** a komponensek összevonása egyetlen `totalXp`-be a
„felület úgyis csak az összeget mutatja” indoklással. A nyugta a Kör 22 celebration
felületének bemenete, és a főkönyv auditálhatóságának feltétele.

### 5.2 A csökkenő hozam az ISMÉTLÉST korlátozza, nem a gyakorlást

Az ötödik ugyanolyan gyakorlat kevesebb XP-t ad — de a gyakorlás maga nem tiltott,
és az előzmény nem csonkul. A plafon az XP-re vonatkozik, nem a felhasználó tevékenységére.

**NEM elfogadható gyengítés:** a napi plafon elérése után az esemény eldobása vagy a
naplózás leállítása. Az adat megmarad; csak a jutalom csökken, rögzített okkal.

### 5.3 Szülő-gyermek esemény: a jutalom EGYSZER jár

Ha egy összefoglaló (szülő) esemény és a részesemények (gyermek) is beérkeznek,
a jutalom nem adódik össze. A motor a kapcsolatot explicit `parentEventId` alapján kezeli.

**NEM elfogadható gyengítés:** időbeli közelség alapú heurisztika a szülő-gyermek
felismerésére — az nemdeterminisztikus és az R05 §5.4 determinizmus-döntését sérti.

### 5.4 MINDEN szám EGYETLEN konfigurációból

A komponens-súlyok, a napi plafon és a csökkenő hozam paraméterei egyetlen
balance-konfigurációban élnek. A Kör 29 szimulációja ezt fogja variálni; a metódusokba
égetett számok ott mérhetetlenné tennék a rendszert.

### 5.5 A policy-verzió a nyugta és a főkönyv része

Minden kiszámított jutalom hordozza a policy-verziót, és az a főkönyvbe kerül.
Egy későbbi balance-váltás így nem teszi visszamenőleg értelmezhetetlenné a régi
bejegyzéseket.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az eredmény komponensenként lebontott (base / duration / quality / improvement / diversity) | `reward_policy_engine_test.dart` — komponens-mátrix |
| A2 | Kezdő session (első alkalom, gyenge teljesítmény) kap **base XP-t** | `reward_policy_engine_test.dart` — az ADR 0290 cellája |
| A3 | Az ismételt ugyanolyan gyakorlat XP-je csökken, de az esemény **nem vész el** | `reward_policy_engine_test.dart` — ismétlés-sorozat |
| A4 | A napi plafon elérése után a csökkentés OKA rögzül a nyugtában | `reward_policy_engine_test.dart` |
| A5 | Szülő + gyermek esemény együtt EGYSZERES jutalmat ad | `reward_policy_engine_test.dart` |
| A6 | A számítás determinisztikus: azonos bemenetre 100 futtatás azonos eredmény | `reward_policy_engine_test.dart` |
| A7 | A jutalom hordozza a policy-verziót | `reward_policy_engine_test.dart` |
| A8 | MINDEN küszöb és súly egyetlen konfigurációból jön (a konfiguráció módosítása átüt) | `reward_policy_engine_test.dart` — konfiguráció-variálás |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A komponensek összevonva egyetlen `totalXp`-be | **A1** (a bontás nem kérdezhető le) és **A4** |
| A napi plafon fölött az esemény eldobódik | **A3** (az esemény elvész) |
| A szülő-gyermek felismerés időbeli heurisztikával | **A5** és **A6** (a determinizmus-cella szór) |
| A súlyok a metódusokba égetve | **A8** (a konfiguráció módosítása nem üt át) |
| A kezdő gyenge session nulla XP-t kap | **A2** |
| A jutalom nem hordozza a policy-verziót | **A7** |

**A küszöb három kötelező cellája** (a napi XP-plafon (`dailyXpCap`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | a napi összeg `dailyXpCap - 1` XP-nél tart, és jön 1 XP | a teljes 1 XP jóváírva, **nincs** csökkentési ok a nyugtában |
| **rajta** (a küszöbön) | a napi összeg pontosan `dailyXpCap` | a plafon ELÉRVE — a további esemény csökkentett XP-t kap, a nyugta **rögzíti az okot**; az esemény maga NEM vész el |
| a küszöb **fölött** | a napi összeg már `dailyXpCap` fölött van (korábbi bejegyzésekből) | a további esemény a csökkentett sávban marad, ok rögzítve; az előzmény érintetlen |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd úgy a plafon-ágat, hogy a plafon fölötti esemény eldobódjon a naplózás előtt,
futtasd a gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/reward_policy_engine_test.dart
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

1. `experience_points.dart` — az XP-érték komponensenkénti bontással és csökkentési okkal.
2. A balance-konfiguráció alakja: súlyok, napi plafon, csökkenő hozam paraméterei — EGY helyen.
3. `reward_policy_engine.dart` — az interfész: jogosult komponensekből XP.
4. `default_reward_policy.dart` — a determinisztikus alapértelmezett számítás.
5. Csökkenő hozam: gyakorlat-specifikus és napi, az esemény megőrzésével.
6. Szülő-gyermek kezelés explicit `parentEventId` alapján.
7. A policy-verzió beépítése; a `public.dart` export-sorai.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az esemény eldobása a plafon fölött.** Kényelmes optimalizáció, és a felhasználó gyakorlási előzményét csonkítja — a jutalomréteg beleszól a termék magjába (A3).
- **Az időbeli szülő-gyermek heurisztika.** Működni látszik a tesztadaton, és nemdeterminisztikus a valóságban (A5/A6).
- **A komponensek összevonása.** A Kör 22 celebration-felülete és a főkönyv auditálhatósága is a bontásra épül (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
