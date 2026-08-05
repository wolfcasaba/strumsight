# E04-R16 — Tutor orchestration state machine és output validator

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-05, base `main` @ `1f75480`; előre megírva 2026-08-04)
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

**Pre-flight lezárva 2026-08-05, base `main` @ `1f75480`** (E04-R15 merge után;
az öt+egy előfeltétel-kör — R05, R07, R10, R11, R12, R13 — mind merge-elve az
`origin/main`-en, mérve). Orchestrátor: Claude (Opus 4.8) · implementer motor:
**Codex** (`gpt-5.6-terra`, örökölt kézi override, `codex-round.sh`).

### Mért baseline (grep, nem tábla — a wire-elendő publikus felületek)

Minden alábbi típus/metódus a `main`-en mérve (`lib/features/ai_tutor/`):

- **Context (R05):** `TutorContextAssembler.assemble({requiredString requestId,
  DateTime createdAt, ContextPurpose purpose, Iterable<TutorContextField> fields})`
  → `TutorContextSnapshot` (**sync**).
- **Retrieval (R07):** `KnowledgeRetriever.retrieve(KnowledgeRetrievalQuery)` →
  `List<TutorSourceRef>` (**sync**, **üres lista legális** = retrieval-empty).
- **Tools (R10):** `TutorToolRegistry.schemasForTurn(TutorToolTurnPolicy)` (sync),
  `execute(TutorToolRequest)` → `Future<AppResult<TutorToolResult>>`;
  `ReadOnlyTutorTools.registryFor({snapshot, maxOutputBytes, clock})`.
- **Actions (R11):** `TutorActionValidator.validate(proposal, context:)` →
  `TutorActionValidationResult` (sync); `ActionConfirmationService.propose(...)`
  (sync) / `confirm(...)` (`Future`); sealed `TutorAction`/`TutorActionProposal`.
- **Prompt (R12):** `TutorPromptBuilder.build(TutorPromptRequest)` →
  `Future<TutorPrompt>`; `TutorOutputSchema.v1` (`canonicalJson`, `toJson()`).
- **Gateway (R13/R15):** `TutorModelGateway.start(TutorModelRequest)` →
  `Future<AppResult<Stream<TutorModelEvent>>>`, `cancel()` (sync); terminális
  `TutorModelDone`/`TutorModelError({int sequence, String code, String message})`;
  busy → `UnknownFailure(code: 'tutor.model_gateway.busy')`.
- **Scripted fake (R13):** `FakeTutorModelGateway({required List<FakeGatewayStep>
  script, FakeClock? clock})`; lépések: `FakeGatewayDelta/ToolCall/Done/Error/Delay`;
  `FakeClock.advance(Duration)` hajtja az eseményeket. Ez a kör hajtóműve.
- **Controller-precedens (E02-R13+):** `lib/features/practice/application/` —
  sealed `PracticeSessionInput` (`Command | Signal`), sealed
  `PracticeSessionEffect`, **pure** `reducePracticeSession(state, input)` →
  `PracticeSessionTransition{state, effects, isRejected}`, controller broadcast
  `states`/`effects` streamekkel + `dispatch(...)`. A tutor-orchestrator ezt tükrözi.
- **AppResult:** `AppResult<T>` sealed (`Success`/`Failure`,
  `lib/core/foundation/app_result.dart`) — a hívás-hibák ezt használják.

### ADR-döntés

**ÚJ ADR: [0174](../adr/0174-ai-tutor-orchestration-state-machine.md)** — AI Tutor
orchestration state machine és output-validator (a pipeline-prompt „te írod meg a
pre-flightban" instrukciója szerint). A kör genuin új normatív döntéseket rögzít
(determinisztikus turn-állapotgép; repair-cap-1 → fallback; cancel utáni
late-event no-op / request-id-korreláció; validator claim+action-schema;
usage-limit/consent-revoked orchestration-rétegű modellezése), amelyeket a
meglévő 0131/0132/0141 nem fed le. Az ADR a 0131/0132/0137/0139/0141/0142
gyerek-kontextusa.

### §1.1 MÉRT hiányok feloldása (pre-flight, orchestration-rétegben)

Két acceptance-cella olyan státuszt ír elő, amelyet a MAI kód **semmilyen
inputtal nem produkál** (mérve grep-pel; a brief-lint nem fogta meg):

1. **`usage-limit`** — az `ai_tutor` rétegben **nincs** usage/rate-limit/quota/429
   fogalom (grep: nulla találat). A modellhiba egyetlen alakja terminális
   `TutorModelError(code, message)`, transport-kódokkal. **Feloldás (ADR 0174 §5):**
   az orchestrator egy **saját, orchestration-fájlban élő** kód-konstanst (pl.
   `tutor.usage_limit`) képez le külön terminális *usage-limit* útra; a scripted
   fake `FakeGatewayError('tutor.usage_limit', …)`-dzsel állítja elő. **Új
   gateway-kód/-típus NEM kerül a gateway-rétegbe (tilos zóna).**
2. **`consent-revoked`** — a `TutorConsent` **nem enum**; a revoked =
   `modelUseGranted == false` (`grantModelUse()`/`revokeModelUse()`). **Feloldás
   (ADR 0174 §5):** az orchestrator a `gateway.start(...)` ELŐTT rövidre zár egy
   terminális *consent-revoked* effektbe, ha a modellhasználat nincs engedélyezve.

Mindkét feloldás **az engedélyezett fájlokon belül** valósul meg — nincs
lista-tágítás.

### §0.0 REVÍZIÓ — `public.dart` MARAD a listán, de az export HALASZTVA (R15 precedens)

A `lib/features/ai_tutor/public.dart` **benne marad** az engedélyezett listában,
**de a §8 4. lépés „additív export"-ja R18-ra halasztva** — az implementer **nem
ad hozzá exportot**, a fájl üresen (`library;`) marad. Mért indok:

- **Slot-planner konfliktus-detektálás (tilos zóna: `tools/`).** A
  `tools/tests/test_pipeline_throughput.py::test_real_epic_four_rounds_are_correctly_rejected`
  (mérve: `main`-en zöld, a Router CI kapu része) HARDKÓDOLTAN elvárja, hogy az
  **E04-R15 és E04-R16 briefek ütközzenek**, mert mindkettő a `public.dart`-ot
  érinti („az Epic 4 körei ugyanazt a `public.dart`-ot érintik"). Ha R16
  kiveszi a `public.dart`-ot, a `paths_conflict` üresre vált, a teszt pirosra —
  és a javítása `tools/`-módosítás lenne, ami a §4 tilos zóna (a mércét nem
  módosíthatja, akit mér). A `public.dart` listán tartása tehát **helyes** a
  slot-planner céljára is: R16 a `public.dart`-ot érintő E04-családba tartozik,
  nem szabad párhuzamosan ütemezni egy másik `public.dart`-körrel.
- **A boundary-invariáns így is teljesül.** A
  `test/features/ai_tutor/ai_tutor_boundary_test.dart` (scope-on kívül) azt
  invariálja, hogy `public.dart` **üres** — ez zöld marad, mert az implementer a
  fájlt **nem érinti** (mérve: nincs a diffben; scope_audit=ok). Az `allowed_paths`
  **engedély-plafon**, nem követelmény: benne lenni és érintetlenül hagyni
  konzisztens (pontosan az E04-R15 mintája — R15 §0.0: „`public.dart` NEM
  változott … az üresen hagyás konzisztens a korábbi körökkel").
- **Miért nem export most:** R16-nak nincs publikus fogyasztója (UI = R18); az
  orchestrator a feature-en belül **közvetlen importtal** köti a komponenseket
  (R12/R13 precedens). Az export az első valódi cross-feature hívónál (R18) jön.

Ez **nem lista-tágítás** az eredetihez képest (a `main`-beli brief is listázta a
`public.dart`-ot); az egyetlen normatív finomítás az „additív export" halasztása.

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
| `lib/features/ai_tutor/public.dart` | listán, **érintetlen** | export R18-ra halasztva (§0.0) — üresen marad |
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
4. Gate (a `public.dart` export **R18-ra halasztva** — §0.0; a fájl üresen marad).

## 9. Kockázatok

- Repair-loop-elfajulás — hard cap 1, utána fallback.
- Late-event race cancel után — a state-gépnek ignorálnia kell (request-id).

**STOP:** korlátlan repair, cancel utáni state-mutáció vagy mércegyengítés helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

- `controller/tutor_state.dart`, `tutor_command.dart`, `tutor_effect.dart`:
  immutable turn-state, sealed command/signal és request-id-korrelált effect fa;
  a repair számláló state-en él.
- `orchestration/tutor_orchestrator.dart`: pure transition-mátrix + UI-mentes
  context → retrieval → prompt → gateway → tool → validator bekötés;
  consent short-circuit, usage-limit leképezés, cancel/late-event no-op és
  egyaktív-turn elutasítás.
- `orchestration/tutor_output_validator.dart`: v1 required-array, grounded
  claim és allowlistelt action-schema, valamint `TutorActionValidator` ellenőrzés.
- Tesztek: scripted fake gateway transition-mátrix (happy, retrieval-empty,
  tool, repair-success/fallback, cancel/late, concurrent, consent, usage-limit)
  és claim/action validator lefedés.

Futtatva: célzott `flutter analyze` zöld; a két új tesztfájl 11 tesztje zöld;
`git diff --check` zöld. A kötelező `tools/round-gate.sh
test/features/ai_tutor/application` format-lépése zöld, de analyze lépése a
munkapéldányból hiányzó, scope-on kívüli generált `lib/l10n/app_localizations.dart`
miatt piros (a saját source-fájlok célzott analyze-a zöld). Emiatt teljes gate
és CI-dispatch nem történt.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r16-orchestration-state-machine-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
