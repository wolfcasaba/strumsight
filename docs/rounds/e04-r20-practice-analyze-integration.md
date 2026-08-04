# E04-R20 — Practice és Analyze post-session integráció

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 20; §35
- **Branch:** `codex/e04-r20-practice-analyze-integration`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R08, R16, R18 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/context/adapters/practice_result_context_adapter.dart",
  "lib/features/ai_tutor/application/context/adapters/analyze_result_context_adapter.dart",
  "lib/features/ai_tutor/presentation/widgets/session_tutor_entry_card.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/application/practice_result_context_adapter_test.dart",
  "test/features/ai_tutor/application/analyze_result_context_adapter_test.dart",
  "test/features/ai_tutor/presentation/session_tutor_entry_card_test.dart",
  "docs/rounds/e04-r20-practice-analyze-integration.md",
]
gate_tests = [
  "test/features/ai_tutor/application",
  "test/features/ai_tutor/presentation",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R08/R16/R18 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 0132 privacy bővítése).
> `rg`: a Practice Result + Analyze eredmény **public** felülete
> (`lib/features/{practice,analyze}/public.dart`) — az adapter csak ezt fogyasztja,
> NEM a result-UI belsőt; a progress/streak író felület (chat-nyitástól NEM változhat).
> **ARB gen** a gate előtt. PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

A tutor összekötése a Practice/Analyze eredményekkel úgy, hogy a **deterministic
result elsődleges marad**, és a progress/streak nem torzul.

## 2. Jelenlegi állapot

- Nincs post-session tutor-belépő. A Practice Result (E02-R18) + Analyze eredmény a
  public barrelen át elérhető; R08 debrief + R16 orchestrator + R18 chat kész.
- **Progress/streak** csak tényleges practice-action után változik — chat-nyitástól SOHA.

## 3. Scope

**Benne:** Practice-result + Analyze-result context-adapter (csak public API),
`SessionTutorEntryCard` a Practice Result + Analyze eredményhez, immutable
context-snapshot-reference rögzítés kattintáskor, előre kitöltött szerkeszthető kérdés,
cloud-consent-hiány → deterministic debrief, suggested Practice action, deleted-result/
version-mismatch kezelés.

**Kívül — TILOS:** a Practice/Analyze **result-UI felülírása**, dupla progress/streak,
source-belső import, unsupported metric claimbe emelése.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../application/context/adapters/practice_result_context_adapter.dart` | ÚJ | Practice→context |
| `.../application/context/adapters/analyze_result_context_adapter.dart` | ÚJ | Analyze→context |
| `.../presentation/widgets/session_tutor_entry_card.dart` | ÚJ | belépő kártya |
| `lib/l10n/app_en.arb`, `app_hu.arb` | meglévő | stringek (additív) |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/{application,presentation}/*` | ÚJ | adapter + card tesztek |
| `docs/rounds/e04-r20-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, a Practice/Analyze **belső** contractja + result-UI,
`docs/rag`, más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A **deterministic result elsődleges** — a tutor-belépő nem írja felül az eredeti
   result-UI-t (ADR 0132). **NEM elfogadható:** a result-UI módosítása.
2. **Progress/streak csak tényleges practice-action után** változik, chat-nyitástól SOHA.
3. Cloud-consent hiányában **deterministic debrief** jelenik meg (R08).
4. **Unsupported metric nem kerül claimbe**; a context immutable snapshot-reference.

## 6. Acceptance criteria

- [ ] Practice-result entry; Analyze capability-aware entry; consent-flow (cloud/off);
      deleted-result; version-mismatch; deterministic-fallback; practice-action.
- [ ] **No streak on chat:** chat-megnyitás NEM változtat progress/streak-et — teszt;
      reviewer eldobható mutációval (chat-nyitás streak-inkrement) pirosra váltja.
- [ ] Az adapter csak public API-t fogyaszt; unsupported metric nem lesz claim.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application test/features/ai_tutor/presentation
```

Külön processzek, nincs `&&`/pipe/`tail`. ARB-nál `flutter gen-l10n` a gate előtt.
CI = orchestrátor exact-SHA.

## 8. Implementációs sorrend

1. RED no-streak-on-chat + deterministic-fallback + version-mismatch tesztek.
2. Practice/Analyze adapterek (public API).
3. entry-card + ARB.
4. `flutter gen-l10n`; gate.

## 9. Kockázatok

- Dupla progress/streak (chat-nyitás mint „aktivitás") — TILOS; csak valós action.
- Result-UI felülírás kísértése — a belépő additív, nem módosítja a source-t.

**STOP:** result-UI felülírás, dupla progress vagy unsupported-metric-claim helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r20-practice-analyze-integration-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
