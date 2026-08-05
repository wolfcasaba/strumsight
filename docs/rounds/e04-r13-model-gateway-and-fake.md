# E04-R13 — TutorModelGateway és scripted fake

- **Státusz:** PLANNING (pre-flight 2026-08-05, base main @ `5d082dc`; előre megírva 2026-08-04, kód olvasva: main @ `fbe1e82`)
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

**Pre-flight lezárva 2026-08-05, base `main` @ `5d082dc` (E04-R12 merge után).**
Orchestrátor: Claude (Opus 4.8) · implementer motor: **qwen-plus**
(`qwen/qwen3.7-plus`, codex-harness, `~/.codex-kilo`, ADR 0140 nyilvántartás).

### Mért baseline (grep, nem tábla)

- `lib/features/ai_tutor/data/model_gateway/` **nem létezik** (greenfield); a
  kör öt új `data/model_gateway/*.dart`-ot és két új tesztet hoz.
- **Gateway/fake/contract-test precedens** (SDD §2 újrahasznosítás):
  `lib/features/practice/application/practice_observation_gateway.dart`
  (`abstract interface class` + `@immutable` config `validate()`-tel),
  `test/support/fake_practice_observation_gateway.dart` (broadcast
  `StreamController`, `emit`/`emitError`, disposed-guard). A tutor gateway
  ezt a mintát követi, provider-SDK típus nélkül.
- **Id/sequence szabályok** már léteznek:
  `TutorRequestId` (`domain/models/tutor_ids.dart:` `final class TutorRequestId`),
  és `TutorMessage.sequence` (`int`, `sequenceNegative`
  validációs kód — `tutor_message.dart:29,44`). A gateway a request-id-t
  ezekre a meglévő típusokra építi, nem újat vezet be.
- **Eredmény-alap:** `AppResult<T>` sealed (`Success`/`Failure`,
  `lib/core/foundation/app_result.dart`) + `AppFailure` — a health/hívás-hibák
  ezt használják, nem dobott kivételt.
- **R12 output-schema** jelen alakja: `TutorOutputSchema.v1`
  (`application/prompts/tutor_output_schema.dart`) — a gateway a nyers
  streaminget adja, a schema-illesztés NEM ennek a körnek a dolga.
- **Nincs provider-SDK függőség** a `pubspec.yaml`-ban (mérve: csak `dio` a
  backend-account réteghez) — a boundary üres, könnyen tartható.

### ADR-döntés

**Nincs ÚJ ADR.** A kör a meglévő **ADR 0131** (AI Tutor provider-boundary)
hatálya alá esik: a döntés 1. pontja már kimondja, hogy a tutor-domain és a
kliens soha nem hivatkozhat provider-SDK típusra, a model-hívás a backend-proxyn
(R14) át történik. A gateway ezt a határt implementálja, nem hoz új normatív
döntést. A pipeline-prompt „te írod meg a pre-flightban" instrukciója így
**dokumentált nem-döntés**: nincs új ADR-szám kiosztva.

### §0.0 REVÍZIÓ — engedélyezett-fájllista SZŰKÍTÉSE (autonómia §2)

A `lib/features/ai_tutor/public.dart` **kikerül** az engedélyezett listából, és a
§8 4. lépéséből törlöm az „additív export"-ot. Mért indok:

- `test/features/ai_tutor/ai_tutor_boundary_test.dart` (a scope-on KÍVÜL) azt
  invariálja, hogy `public.dart` **nulla import/export** — ha az implementer
  exportot ad hozzá, ez a listán kívüli teszt pirosra vált, a gate megbukik,
  a javítás pedig scope-sértés lenne (`stopped`).
- `HANDOFF.md` §6 kimondja: „a `public.dart` üres-boundary invariáns tovább él,
  amíg a hívó (R16/R19) nem érkezik meg" — a publikus export **R16+-ra
  halasztva**.
- A gateway a feature-en belül **közvetlen importtal** érhető el (a R12
  prompt-osztályok precedense), publikus export nélkül. Az acceptance criteria
  (§6) nem is kér exportot.

Ez tiszta **szűkítés** (tilos zóna tágítása nélkül) → ADR 0087 §2 szerint az
orchestrátor autonómiájában áll.

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
| ~~`lib/features/ai_tutor/public.dart`~~ | **KIVÉVE (§0.0 revízió)** | az üres-boundary invariáns R16+-ig él (HANDOFF §6); intra-feature import |
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
4. Gate. (Publikus export NINCS — §0.0 revízió; a gateway intra-feature importtal érhető el, `public.dart` érintetlen marad.)

## 9. Kockázatok

- A timeout-helper óra-függősége nem-determinisztikus tesztet ad — injektált óra kell.
- Provider-SDK szivárgás a data-rétegbe — a boundary a backend proxy (R14).

**STOP:** provider-SDK import, nem-determinisztikus cancel vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff

**Implementer: qwen-plus** (`qwen/qwen3.7-plus`, codex-harness). Kész: 5 új
production fájl a `lib/features/ai_tutor/data/model_gateway/` alatt + 2 új teszt
(`test/features/ai_tutor/data/`), összesen 69 zöld teszt a `test/features/ai_tutor/data`
gate-területen.

- `TutorModelGateway` — providerfüggetlen `abstract interface class`
  (`start(TutorModelRequest) → AppResult<Stream<TutorModelEvent>>`, `cancel()`,
  `health()`), **nincs Flutter UI / provider-SDK típus** (ADR 0131).
- `TutorModelRequest` — `@immutable` (requestId/sequence/conversationId/message).
- `TutorModelEvent` — `sealed`: `TutorModelDelta` / `TutorModelToolCall` /
  `TutorModelDone` / `TutorModelError`. Duplicate terminal → csak az első jut ki.
- `FakeTutorModelGateway` — scripted (`FakeGatewayDelay/Delta/ToolCall/Done/Error`),
  determinisztikus `cancel`, injektált `FakeClock`. A `withTimeouts` teszt-helper
  first-event/inactivity/total timeoutot ad (below/at/above mátrix).
- `LocalTutorModelGatewayStub` — capability-unavailable
  (`'tutor.model_gateway.unavailable'`).

Három javító körön ment át (F1 unused-import, F2 at-threshold mátrix,
F3 uncommitted production fájlok, F4 async-timing) — részletek a review §8-ban.
A gateway a feature-en belül **közvetlen importtal** érhető el; publikus export
R16+-ra halasztva (§0.0 revízió).

## 11. Review

Elkészült: [`docs/reviews/e04-r13-model-gateway-and-fake-review.md`](../reviews/e04-r13-model-gateway-and-fake-review.md)
— **APPROVED**, 0 BLOCKER/MAJOR/MINOR, 3 NOTE (follow-up a hívó körökre). A
provider-boundary/no-secret határt eldobható mutáció (secret + provider-import)
igazolta pirosra a `secrets`/`analyze` lépésen. Merge exact-SHA zöld CI után.
