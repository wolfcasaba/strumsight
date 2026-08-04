# E04-R11 — Action proposal, validáció és confirmation service

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 11; §35
- **Branch:** `codex/e04-r11-action-proposal-and-confirmation`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/tutor_action.dart",
  "lib/features/ai_tutor/application/orchestration/tutor_action_validator.dart",
  "lib/features/ai_tutor/application/orchestration/action_confirmation_service.dart",
  "lib/features/ai_tutor/application/orchestration/fake_action_executors.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/domain/tutor_action_test.dart",
  "test/features/ai_tutor/application/action_confirmation_service_test.dart",
  "docs/rounds/e04-r11-action-proposal-and-confirmation.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R10 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 **0133**
> tool-confirmation bővítése). `rg`: a route-katalógus / `app_route.dart` mai
> alakja — a route-nevet **soha nem** nyers model-string adja. PREPARED→PLANNING,
> brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

Navigációs és állapotmódosító műveletek **kétlépcsős, felhasználó által
megerősített** rendszere — automatikus write/launch soha.

## 2. Jelenlegi állapot

- Nincs tutor action-rendszer (SDD §3.2/12). Az R10 read-only toolok csak olvasnak;
  a write/launch itt, confirmation mögött jelenik meg.
- A route-katalógus/`app_route.dart` typed route-okat definiál — a modell nem adhat
  nyers route-stringet.

## 3. Scope

**Benne:** támogatott action sealed hierarchia (source/expiry/capability/clientActionId),
proposal-validator, stale-action policy, confirmation-state + reject-flow,
profile-update/plan-save/session-launch → confirmation-kötelező, idempotens execution
clientActionId alapján, fake executorok.

**Kívül — TILOS:** UI (R19), tényleges navigáció/write végrehajtás production-ben,
nyers route-string, cloud.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/tutor_action.dart` | ÚJ | sealed action hierarchia |
| `.../application/orchestration/tutor_action_validator.dart` | ÚJ | proposal-validator |
| `.../application/orchestration/action_confirmation_service.dart` | ÚJ | kétlépcsős confirm |
| `.../application/orchestration/fake_action_executors.dart` | ÚJ | teszt-executor |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/{domain,application}/*` | ÚJ | action/confirm tesztek |
| `docs/rounds/e04-r11-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs automatikus write/launch** — profile-update/plan-save/session-launch
   kötelezően confirmation mögött (ADR 0133). **NEM elfogadható:** „biztonságosnak
   ítélt" action auto-futása.
2. A **route-név soha nem nyers model-string** — typed action + capability.
3. **Idempotens** execution clientActionId alapján; **stale action blokkolt**.
4. Az action-domain **providerfüggetlen**.

## 6. Acceptance criteria

- [ ] valid proposal; unknown action reject; **stale** (song-revision/expiry) blokkolt
      (alatta/rajta/fölötte az expiry mátrix); deleted-session; capability-lost.
- [ ] **Double confirm idempotens** (clientActionId); reject-flow tiszta.
- [ ] **Arbitrary route blocked:** nyers route-stringből nem lesz navigáció — teszt;
      reviewer eldobható mutációval (nyers string átengedése) pirosra váltja.
- [ ] profile-update preview elérhető confirm előtt.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED stale/idempotens/arbitrary-route/confirm-kötelező tesztek.
2. Action hierarchia + validator.
3. Confirmation-service + fake executorok.
4. Additív export; gate.

## 9. Kockázatok

- A nyers-route csábítás (kényelmi deep-link) — TILOS; typed action + capability.
- Idempotencia: a double-tap/retry nem duplikálhat write-ot (clientActionId).

**STOP:** auto-write, nyers route, nem-idempotens execution vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r11-action-proposal-and-confirmation-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
