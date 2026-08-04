# E04-R16 — Tutor orchestration state machine és output validator

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 16; §20; §35
- **Branch:** `codex/e04-r16-orchestration-state-machine`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R05, R07, R10, R11, R12, R13 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/controller/tutor_state.dart",
  "lib/features/ai_tutor/application/controller/tutor_command.dart",
  "lib/features/ai_tutor/application/controller/tutor_effect.dart",
  "lib/features/ai_tutor/application/orchestration/tutor_orchestrator.dart",
  "lib/features/ai_tutor/application/orchestration/tutor_output_validator.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/application/tutor_orchestrator_test.dart",
  "test/features/ai_tutor/application/tutor_output_validator_test.dart",
  "docs/rounds/e04-r16-orchestration-state-machine.md",
]
gate_tests = [
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + az öt+egy előfeltétel-kör merge-je;
> olvasd újra `AGENTS.md`, Chapter 1/5 (**§20 state machine**), `HANDOFF.md`. Nincs
> ÚJ ADR (R01 0131–0134 bővítése). `rg`: az R05/R07/R10/R11/R12/R13 public
> felülete — az orchestrator csak ezeket köti össze. PREPARED→PLANNING, brief commit
> az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

A teljes turn-pipeline **determinisztikus, tesztelhető** összekapcsolása UI nélkül —
context → retrieval → prompt → gateway → tool → validator, kontrollált repair/fallbackkel.

## 2. Jelenlegi állapot

- Minden építőelem kész (R05 context, R07 retrieval, R10 tools, R11 actions, R12 prompt,
  R13 gateway); **orchestration nincs**.
- A Practice controller state/command/effect minta (E02-R13+) a precedens.

## 3. Scope

**Benne:** state/command/effect, `TutorOrchestrator` (a lépések összekötése),
`TutorOutputValidator` (claim-schema + action-schema), legfeljebb **egy** repair-request
majd deterministic fallback, cancel utáni late-event no-op, egy aktív turn/conversation,
request-id korreláció, részletes transition-tesztek a scripted fake-kel.

**Kívül — TILOS:** UI (R18), valódi cloud, source-belső import.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/controller/tutor_state.dart` | ÚJ | állapot |
| `.../application/controller/tutor_command.dart` | ÚJ | parancs |
| `.../application/controller/tutor_effect.dart` | ÚJ | effect |
| `.../application/orchestration/tutor_orchestrator.dart` | ÚJ | pipeline |
| `.../application/orchestration/tutor_output_validator.dart` | ÚJ | claim/action schema |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/application/*` | ÚJ | transition + validator tesztek |
| `docs/rounds/e04-r16-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Rossz outputnál **legfeljebb EGY** repair-request, majd **deterministic fallback**
   (ADR 0132 grounding). **NEM elfogadható:** korlátlan repair-loop.
2. **Cancel után a late event nem módosítja a state-et**; egy conversationben egy aktív turn.
3. Minden effect **request-id-vel korrelált**; minden terminal útvonal **lezár** (nincs
   végtelen loop).
4. A validator claim- és action-schemát is ellenőriz (hallucinált metric blokkolt — R23-mal együtt).

## 6. Acceptance criteria

- [ ] happy path; retrieval-empty; tool-call; **repair success**; **repair failure →
      fallback**; cancel; late-delta no-op; concurrent-send (egy aktív turn); consent-revoked;
      usage-limit — mind scripted fake-kel, determinisztikusan.
- [ ] **Nincs végtelen loop**, minden terminal path lezár — teszt; reviewer eldobható
      mutációval (repair-cap eltávolítása) pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED transition-mátrix (happy/repair/fallback/cancel/concurrent) tesztek.
2. state/command/effect.
3. orchestrator + output-validator.
4. Additív export; gate.

## 9. Kockázatok

- Repair-loop-elfajulás — hard cap 1, utána fallback.
- Late-event race cancel után — a state-gépnek ignorálnia kell (request-id).

**STOP:** korlátlan repair, cancel utáni state-mutáció vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r16-orchestration-state-machine-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
