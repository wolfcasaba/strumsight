# E04-R09 — PracticePlanDraft, validator és compiler

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 9; §35
- **Branch:** `codex/e04-r09-practice-plan-draft-validator-compiler`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R03 + E04-R04 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/practice_plan_draft.dart",
  "lib/features/ai_tutor/domain/models/practice_plan_block.dart",
  "lib/features/ai_tutor/domain/services/practice_plan_validator.dart",
  "lib/features/ai_tutor/application/planning/practice_plan_compiler.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/practice_plan_validator_test.dart",
  "test/features/ai_tutor/application/practice_plan_compiler_test.dart",
  "docs/rounds/e04-r09-practice-plan-draft-validator-compiler.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R03/R04 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0133 tool-confirmation
> bővítése). `rg`: a Practice + Song Trainer **public** compiler/definition felülete
> (`lib/features/{practice,song_trainer}/public.dart`) — a compiler csak publikus
> API-ra épít. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

AI által **javasolható**, de teljesen **validált és végrehajtható** gyakorlási terv
domain — invalid draft soha nem indíthat navigációt.

## 2. Jelenlegi állapot

- Nincs tutor practice-plan domain (SDD §3.2/9); a Practice/Song compiler a
  `public.dart`-on át elérhető (E02-R06 target-compiler, E03-R19 song-compiler).
- R03 után van user avoid-lista/goal, R04 után skill-becslés — a validáció bemenete.

## 3. Scope

**Benne:** `PracticePlanDraft` + `PracticePlanBlock`, támogatott block-type allowlist,
idő/tempo/tuning/skill/capability-validáció, determinisztikus template-generátor
(5/10/20/30 perc), Practice + Song Trainer compiler-adapter, invalid-draft-nem-indít
kapu, stabil validációs kódok, user-edit utáni újravalidálás, offline-runnable jelzés.

**Kívül — TILOS:** UI (R19), cloud, tényleges launch (R11), source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/practice_plan_draft.dart` | ÚJ | plan modell |
| `.../domain/models/practice_plan_block.dart` | ÚJ | block modell + allowlist |
| `.../domain/services/practice_plan_validator.dart` | ÚJ | pure validator |
| `.../application/planning/practice_plan_compiler.dart` | ÚJ | Practice/Song adapter |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/{domain,application}/*` | ÚJ | validator/compiler tesztek |
| `docs/rounds/e04-r09-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Invalid draft nem fordítható/indítható** — a compiler csak validált tervet
   ad tovább (ADR 0133). **NEM elfogadható:** „figyelmeztetéssel mégis indít".
2. A validator **pure**; a block-type **allowlist** zárt.
3. A plan teljes ideje **egzakt** a kért időkeretre; a compiler-parity a Practice/Song
   compilerrel bit-stabil.
4. Az offline-runnable jelzés **pontos** (minden asset lokális ⇒ true).

## 6. Acceptance criteria

- [ ] **Duration mátrix:** 5/10/20/30 perc → a blokkok összege pontosan a keret
      (alatta/rajta/fölötte cellák, géppel számítva).
- [ ] Unsupported block / tempo out-of-range / missing song / tuning mismatch /
      user-avoid → **invalid**, stabil kóddal; **invalid draft cannot launch** teszt.
- [ ] Compiler-parity a Practice + Song adapterrel; user-edit után újravalidál.
- [ ] Offline-runnable jelzés pontos (asset-hiány → false).

A reviewer az invalid-draft-kaput eldobható mutációval (invalid mégis compile-ol)
pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED duration-mátrix + invalid-launch + parity tesztek.
2. Draft/block modellek + allowlist.
3. Pure validator + compiler-adapterek.
4. Additív export; gate.

Javasolt commit: `feat(ai-tutor-plans): add validated practice plan generation contracts`.

## 9. Kockázatok

- A compiler csábítható source-belső típusra — csak public API; kívülre esés `stopped`.
- Duration-kerekítés: egész-perc blokk-összeg egzakt a kerettel (E02-R06 egyszeri-
  kerekítés minta).

**STOP:** invalid-launch, source-belső import vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r09-practice-plan-draft-validator-compiler-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
