# E10-R23 — LocalTutorModelGateway implementáció

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 23
- **Kör-azonosító:** `E10-R23`
- **Branch:** `<motor>/e10-r23-local-tutor-model-gateway`
- **Előfeltétel:** `E10-R22` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0437` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart` PONTOS interfészét és a `local_tutor_model_gateway_stub.dart` MA bekötött placeholder-jét (`tutor_providers.dart:350`). Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** **ADR 0131** (ai-tutor-provider-boundary, a `TutorModelGateway` szerződés forrása) — közvetlen precedens; a §0.0 saját grounding-kutatása (nem külön RAG-lekérdezés) azonosította a pontos csere-célpontot (`LocalTutorModelGatewayStub`).

## 0.0 Pre-flight kiegészítés — ez a kör EGY MEGLÉVŐ STUB-OT cserél, nem egy üres helyre ír

**Ez a legfontosabb ténybeli korrekció az egész Epic 10 batch-ben.** A `TutorModelGateway` interfész (`start(TutorModelRequest) → Future<AppResult<Stream<TutorModelEvent>>>`, `cancel()`, `health()`) MÁR LÉTEZIK, [ADR 0131](../adr/0131-ai-tutor-provider-boundary.md) alatt. A produkciós DI-ben MA egy PLACEHOLDER van bekötve:

```dart
// lib/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_stub.dart:21
final class LocalTutorModelGatewayStub implements TutorModelGateway {
  // MINDIG AppResult.failure(UnknownFailure(code: 'tutor.model_gateway.unavailable'))
}
// bekötve: lib/features/ai_tutor/presentation/providers/tutor_providers.dart:350
//   gatewayForAttempt: (_) => LocalTutorModelGatewayStub()
```

**Ez a kör a `LocalTutorModelGatewayStub`-ot CSERÉLI le egy valódi `LocalTutorModelGateway`-re**, ugyanabban a könyvtárban (`lib/features/ai_tutor/data/model_gateway/local_tutor_model_gateway.dart`), és frissíti a `tutor_providers.dart:350` bekötést. A `TutorModelEvent` sealed hierarchia (`TutorModelDelta`, `TutorModelToolCall`, `TutorModelDone`, `TutorModelError`) MÁR LÉTEZIK — ez a kör a Kör 2 `GenerationEvent`-jét erre a MEGLÉVŐ hierarchiára képezi le, nem talál ki új eseménytípusokat.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/data/model_gateway/local_tutor_model_gateway.dart",
  "lib/features/ai_tutor/presentation/providers/tutor_providers.dart",
  "lib/features/offline_ai/application/local_ai_application_service.dart",
  "test/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_contract_test.dart",
  "docs/rounds/e10-r23-local-tutor-model-gateway.md",
]
gate_tests = [
  "test/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_contract_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör a produkciós DI-bekötést (`tutor_providers.dart`) módosítja — ez a Chapter 5 ai_tutor feature ÉLES viselkedését érinti, még akkor is, ha a `localAiRuntimeEnabled` flag miatt production-ben inaktív marad.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A `TutorModelGateway` MEGLÉVŐ, változatlan interfészének helyi implementációja, ami összeköti a context/retrieval/runtime/output-validation rétegeket — a `LocalTutorModelGatewayStub` helyén.

## 2. Jelenlegi állapot — mért tények

- Lásd §0.0 — a pontos csere-célpont.
- A Kör 16 context budgeter, Kör 20 hibrid retrieval, Kör 21 prompt assembler, Kör 22 tool-adapter mind ennek a gateway-nek a bemenő rétegei.
- A Kör 12 `LocalAiResourceCoordinator` adja a `acquireGenerationLease`-t, amit a gateway KÖTELEZŐEN hív minden `start()` előtt.
- A Kör 7 (`hold`) adja a VALÓS `LocalGenerationRuntime` implementációt — amíg az `hold`-on van, ez a kör a Kör 7 `FakeRuntimeAdapter`-jét (vagy egy helyi contract-fake-et, ha a 7 még nincs meg) használja a contract teszthez.

## 3. Scope

**Benne van:** `LocalTutorModelGateway` (implementálja `TutorModelGateway`-t) · pipeline sorrend: capability → resource lease → context snapshot → retrieval → budget → prompt → generate → validate → provenance → release · a `GenerationEvent`→`TutorModelEvent` leképezés (Delta/ToolCall/Done/Error) · a gateway CSAK public context adaptert olvas, más feature belső providerét NEM · minden exit pathon lease-release · failure esetén deterministic fallback handoff metadata · `tutor_providers.dart` bekötés-csere.

**NINCS benne (tilos):**

- A `TutorModelGateway` interfész módosítása.
- A `TutorModelEvent` hierarchia bővítése új eseménytípussal.
- `docs/adr/**` — az ADR 0437-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/ai_tutor/data/model_gateway/local_tutor_model_gateway.dart` | ÚJ — a `LocalTutorModelGatewayStub` cseréje |
| `lib/features/ai_tutor/presentation/providers/tutor_providers.dart` | a bekötés frissítése (`gatewayForAttempt`) |
| `lib/features/offline_ai/application/local_ai_application_service.dart` | ÚJ — a helyi pipeline orchesztrátora |
| `test/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_contract_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart`, `remote_tutor_model_gateway.dart`, `tutor_model_event.dart` (MEGLÉVŐ, nem módosítható) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0437)

### 5.1 A gateway csak PUBLIC context adaptert olvas, más feature belső providerét sosem

A pipeline `context snapshot` lépése a MEGLÉVŐ `tutor_context_snapshot.dart`-ot (Chapter 5) használja — a gateway nem importál közvetlenül `practice`/`song_trainer`/`gamification` belső providert.

**NEM elfogadható gyengítés:** egy "gyorsítás" céljából közvetlenül importált feature-belső state, megkerülve a context-snapshot absztrakciót.

### 5.2 Minden exit pathon (siker, hiba, cancel, exception) a resource lease felszabadul

**NEM elfogadható gyengítés:** egy `try`-blokk, aminek valamelyik `return`/`throw` ága elfelejt release-t hívni — lásd Kör 12 §5.2 ugyanezen elve, itt a HÍVÓ oldalon védve.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Happy-path: `start()` egy teljes `TutorModelDelta*→TutorModelDone` sorozatot ad | `local_tutor_model_gateway_contract_test.dart` |
| A2 | Retrieval-hiba esetén a gateway deterministic fallback metaadatot ad, nem crash-el | `local_tutor_model_gateway_contract_test.dart` |
| A3 | Context-overflow (Kör 16 `ContextOverflowFailure`) kontrolláltan `TutorModelError`-ra map-elt | `local_tutor_model_gateway_contract_test.dart` |
| A4 | Runtime-hiba `TutorModelError`-ra map-elt, a lease felszabadul | `local_tutor_model_gateway_contract_test.dart` |
| A5 | `cancel()` a folyamatban lévő generálást leállítja, a lease felszabadul | `local_tutor_model_gateway_contract_test.dart` |
| A6 | Tool-draft válasz `TutorModelToolCall`-ra map-elt (Kör 22 kimenete) | `local_tutor_model_gateway_contract_test.dart` |
| A7 | Minden exit pathon (siker/hiba/cancel/exception) a lease pontosan egyszer szabadul fel | `local_tutor_model_gateway_contract_test.dart` |
| A8 | A gateway nem importál `practice`/`song_trainer`/`gamification` belső (nem `public.dart`) fájlt | `test/tooling/architecture_dependency_offline_ai_test.dart` (bővítve) |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy exception-ág elfelejti hívni a lease-release-t | A7 |
| A gateway közvetlenül importálja a `PracticeSessionController`-t a context helyett | A8 |
| A cancel nem szabadítja fel a lease-t | A5/A7 |
| A tool-draft válasz `TutorModelDelta`-ként megy át `TutorModelToolCall` helyett | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a lease-release hívást a runtime-hiba ágból, futtasd a kontrakt tesztet → az **A7** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_contract_test.dart
```

## 8. Implementációs sorrend

1. `local_ai_application_service.dart` — a pipeline orchesztrátora (capability→lease→context→retrieval→budget→prompt→generate→validate→provenance→release).
2. `local_tutor_model_gateway.dart` — a `TutorModelGateway` implementációja, `GenerationEvent`→`TutorModelEvent` leképezéssel.
3. `tutor_providers.dart` bekötés-csere (a `localAiRuntimeEnabled` flag mögé kapcsolva, NEM feltétel nélkül).
4. Kontrakt teszt fake/stub runtime adapterrel.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A produkciós DI-bekötés hibás módosítása.** Mivel ez a kör MEGLÉVŐ, éles kódot módosít (`tutor_providers.dart`), egy hibás csere a teljes ai_tutor feature-t törhetné — a flag-mögé-kötés (5.1-hez kapcsolódó biztonsági háló) ezt mérsékli.
- **A lease-szivárgás.** A legvalószínűbb, ismétlődő hibaosztály (A7).
- **A feature-határ átlépése.** Egy "gyors" közvetlen import más feature belsejéből törné a Chapter 1 architektúra-elvet (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
