# E07-R23 — PlanCompiler és Practice Engine végrehajtás

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 19b30557`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 23
- **Kör-azonosító:** `E07-R23`
- **Branch:** `<motor>/e07-r23-plan-compiler-and-execution`
- **Előfeltétel:** `E07-R22` merge-elve (Today képernyő)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0268`](../adr/0268-technical-failure-is-not-skill-failure.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a Practice Engine
> **tényleges** `public.dart` felületét (definíció-típus, session-eredmény
> alakja), mert a §5 erre épül. Olvasd újra az R08 katalógus-revízióit is.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/service/plan_compiler.dart",
  "lib/features/practice_generator/application/service/plan_execution_coordinator.dart",
  "lib/features/practice_generator/data/adapter/practice_outcome_adapter.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/execution/plan_compiler_test.dart",
  "test/features/practice_generator/execution/plan_execution_coordinator_test.dart",
  "test/fixtures/practice_generator/execution/",
  "docs/rounds/e07-r23-plan-compiler-and-execution.md",
]
gate_tests = [
  "test/features/practice_generator/execution/plan_compiler_test.dart",
  "test/features/practice_generator/execution/plan_execution_coordinator_test.dart",
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

A terv-blokkok validált Practice Engine lépéssé fordítása és az eredmény
visszacsatolása (SDD Ch8 Kör 23).

## 2. Jelenlegi állapot — mért tények

- Az R08 katalógus-pillanatképe **két revíziót** hordoz (ADR 0262 §3) — ebből
  derül ki, ha egy blokk elavult.
- Az R09 receptjei korlátosak, a sikerkritérium mérhető.
- Az ADR 0260 §3: az eredmény-dedup kulcsa a forrás outcome ID-ja.

## 3. Scope

**Benne van:** blokk → végrehajtható lépés fordítása · **revízió- és
capability-ellenőrzés indítás előtt** · a recept konfigjának átadása ·
`blockExecutionId` képzése · a session-eredmény fogadása és normalizálása ·
megszakítás, részleges és **technikai hiba** kezelése.

**NINCS benne (tilos):** a Practice Engine módosítása · a terv revíziójának
írása (Kör 26) · flag `true`-ra állítása · más feature belső importja ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/service/plan_compiler.dart` | **ÚJ** — a fordító |
| `application/service/plan_execution_coordinator.dart` | **ÚJ** — indítás + eredmény |
| `data/adapter/practice_outcome_adapter.dart` | **ÚJ** — eredmény-normalizálás |
| `public.dart` | a barrel bővítése |
| `test/…/execution/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r23-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` tartalma (a `public.dart`-jukon át
olvasható) · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**`.

## 5. Kötött architekturális döntések (ADR 0268)

### 5.1 A TECHNIKAI hiba NEM skill-hiba

Mikrofon-hiba, összeomlás, hiányzó asset, engedély-megtagadás → **nem** a
tanuló teljesítménye. Ilyen eredmény nem csökkentheti a becslést és nem
válthat ki regressziót (ADR 0265 §4).

**NEM elfogadható gyengítés:** „nem sikerült teljesíteni, tehát gyenge".

### 5.2 Az ELAVULT blokk nem indul

Ha a hivatkozott gyakorlat revíziója megváltozott vagy a capability eltűnt, a
blokk **nem indul el** — helyettesítést vagy újratervezést kér.

### 5.3 Az eredmény IDEMPOTENS

Ugyanaz a `blockExecutionId` kétszer visszatérve egyszer könyvelődik
(ADR 0260 §3 folytatása).

### 5.4 A session-konfig MEGFELEL a receptnek

Amit a tervező előírt (időtartam, tempó, ismétlés), az megy át a végrehajtóhoz
— nem „körülbelül". Eltérés esetén hiba, nem csendes igazítás.

### 5.5 A megszakított session RÉSZLEGES, nem sikertelen

A tanuló megszakítása nem kudarc: külön kimenet, ami nem büntet
(az R17 §5.2 „bizonytalan nem büntet" elvének rokona).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Technikai hiba NEM csökkenti a becslést, nem vált ki regressziót | `plan_execution_coordinator_test.dart` |
| A2 | Elavult revíziójú blokk nem indul | `plan_compiler_test.dart` |
| A3 | Hiányzó capability esetén a blokk nem indul | ugyanott |
| A4 | Az eredmény idempotens (kétszeri visszatérés) | `plan_execution_coordinator_test.dart` |
| A5 | A session-konfig pontosan a recept szerinti | `plan_compiler_test.dart` |
| A6 | A megszakított session részleges, nem sikertelen | `plan_execution_coordinator_test.dart` |
| A7 | `blockExecutionId` egyedi és visszakereshető | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A technikai hiba kudarcként könyvelve | **A1** |
| Elavult blokk elindítva | **A2** |
| Az eredmény kétszer könyvelve | A4 |
| „Körülbelüli" session-konfig | A5 |
| A megszakítás kudarcként | A6 |

**Az eredmény-típus három kötelező cellája** (a küszöb: a tanuló teljesítménye):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | **technikai** hiba (mikrofon, összeomlás) | **nem** számít teljesítménynek — a becslés változatlan |
| rajta (a küszöbön) | a tanuló **megszakította** | részleges — nem büntet |
| a küszöb fölött | végigcsinálta, mért eredménnyel | teljes értékű evidence |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** könyveld a technikai
hibát sikertelen teljesítményként → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/execution/plan_compiler_test.dart test/features/practice_generator/execution/plan_execution_coordinator_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `plan_compiler.dart` — fordítás + revízió/capability ellenőrzés.
2. `practice_outcome_adapter.dart` — az eredmény-típusok szétválasztása.
3. `plan_execution_coordinator.dart` — indítás, idempotens visszacsatolás.
4. Tesztek a §6.1 három eredmény-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A technikai hiba mint kudarc.** A legkárosabb: a tanuló azért kap
  könnyebb tervet, mert elromlott a mikrofonja (A1).
- **Az elavult blokk.** A katalógus alatta változik, és a tanuló olyat
  gyakorolna, ami már nem az (A2).
- **A „körülbelüli" konfig.** A tervező 60 BPM-et írt elő, a végrehajtó 70-et
  indít — és a mérés értelmetlenné válik (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
