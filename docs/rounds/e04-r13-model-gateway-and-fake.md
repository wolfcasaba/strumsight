# E04-R13 — TutorModelGateway és scripted fake

- **Státusz:** PREPARED (előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 13; §35
- **Branch:** `codex/e04-r13-model-gateway-and-fake`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R02 + E04-R12 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart",
  "lib/features/ai_tutor/data/model_gateway/tutor_model_request.dart",
  "lib/features/ai_tutor/data/model_gateway/tutor_model_event.dart",
  "lib/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart",
  "lib/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_stub.dart",
  "lib/features/ai_tutor/public.dart",
  "test/features/ai_tutor/data/tutor_model_gateway_contract_test.dart",
  "test/features/ai_tutor/data/fake_tutor_model_gateway_test.dart",
  "docs/rounds/e04-r13-model-gateway-and-fake.md",
]
gate_tests = [
  "test/features/ai_tutor/data",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E04-R02/R12 merge; olvasd újra
> `AGENTS.md`, Chapter 1/5, `HANDOFF.md`. Nincs ÚJ ADR (R01 **0131**
> provider-boundary bővítése). `rg`: az R02 message/event id-sequence + R12
> output-schema mai alakja; a gateway **nem** ismerhet Flutter UI típust
> (domain-purity analóg). PREPARED→PLANNING, brief commit az implementer ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED — a mért §0.0-t az élesedő pre-flight tölti ki.** Nincs előre kiosztott ADR.

## 1. Cél

**Providerfüggetlen** streaming modellkapu + teljes contract-tesztkészlet, valódi
cloud-integráció nélkül (fake + local stub).

## 2. Jelenlegi állapot

- Nincs model-gateway (SDD §3.2/9). A `LivePracticeObservationGateway` (E02-R08) a
  gateway-contract + fake precedense (contract-teszt újrahasználható).
- A gateway a `data/` rétegben él, de **provider-SDK típus nélkül** (R14 backend proxy).

## 3. Scope

**Benne:** gateway-contract + event-hierarchia, request-id/sequence szabályok, scripted
fake (delay/delta/tool-call/error/cancellation), inactivity + total timeout helper,
duplicate terminal event kezelés, local-gateway stub (capability-unavailable), közös
contract-test-suite.

**Kívül — TILOS:** valódi cloud/provider-SDK, backend (R14), streaming transport (R15),
Flutter UI típus a gatewayben.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/model_gateway/tutor_model_gateway.dart` | ÚJ | contract |
| `.../data/model_gateway/tutor_model_request.dart` | ÚJ | request modell |
| `.../data/model_gateway/tutor_model_event.dart` | ÚJ | event hierarchia |
| `.../data/model_gateway/fake_tutor_model_gateway.dart` | ÚJ | scripted fake |
| `.../data/model_gateway/local_tutor_model_gateway_stub.dart` | ÚJ | local stub |
| `lib/features/ai_tutor/public.dart` | előző körökből | additív export |
| `test/features/ai_tutor/data/*` | ÚJ | contract + fake tesztek |
| `docs/rounds/e04-r13-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje, bármely provider-SDK import. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. A gateway **providerfüggetlen**; **nincs Flutter UI típus** benne (ADR 0131).
   **NEM elfogadható:** provider-specifikus mező a public contractban.
2. A fake **minden edge-case-t** tud (delay/delta/tool/error/cancel); a cancellation
   determinisztikus.
3. Duplicate terminal event **ignorált vagy kontrolláltan jelentett** (nem crash).
4. A common contract-suite **újrahasználható** bármely új gatewayre.

## 6. Acceptance criteria

- [ ] ordered events; duplicate event; **first-event / inactivity / total timeout
      mátrix** (alatta/rajta/fölötte); cancel; late event; tool-call; malformed event;
      health; local stub capability-unavailable.
- [ ] A contract-suite fake + local stubbal is zöld (újrahasználható).
- [ ] **Nincs cloud secret** a gatewayben — teszt; reviewer eldobható mutációval
      (provider-mező hozzáadása) pirosra váltja.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/data
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED contract + timeout-mátrix + cancel tesztek.
2. Contract + event + request modellek.
3. Scripted fake + local stub.
4. Additív export; gate.

## 9. Kockázatok

- A timeout-helper óra-függősége nem-determinisztikus tesztet ad — injektált óra kell.
- Provider-SDK szivárgás a data-rétegbe — a boundary a backend proxy (R14).

**STOP:** provider-SDK import, nem-determinisztikus cancel vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r13-model-gateway-and-fake-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
