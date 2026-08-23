# E10-R14 — Token streaming és cancellation (Dart-oldali szerződés, fake forrással)

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 14
- **Kör-azonosító:** `E10-R14`
- **Branch:** `<motor>/e10-r14-token-streaming-and-cancellation`
- **Előfeltétel:** `E10-R12` merge-elve (a natív emitter — Kör 13 — `hold`-on van, lásd §0.0)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0429` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 2 `GenerationEvent` sealed hierarchiáját (SDD §7.6: `GenerationStarted`, `GenerationToken`, `GenerationToolDraft`, `GenerationCompleted`, `GenerationCancelled`, `GenerationFailed`, `GenerationMetricsUpdated`). Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "streaming cancellation token event order idempotent"` → **ADR 0142** (AI Tutor streaming transport protokoll, bm25#1 emb#2) — a `seq` monoton, frame-enként +1, közös számláló minden frame-típusra; ez a brief a `GenerationEvent`-re alkalmazza ugyanezt az "pontosan egy terminal event" elvet (5.1), a `TutorModelEvent`-re történő végleges leképezés pedig Kör 23 dolga.

## 0.0 Hardver/scope-korlát — miért PENDING (narrowed)

A SDD Kör 14 eredeti fájllistája a natív `LocalAiEventEmitter.kt`-t is tartalmazza — ez KIMARAD (Kör 13 `hold`-on van, lásd ott). Ez a kör a Flutter-OLDALI stream-adaptert és a generation controllert szállítja, egy a TESZT FÁJLON BELÜL definiált, LOKÁLIS fake esemény-forrással (nem a Kör 7 megosztott `FakeRuntimeAdapter`-jétől függ, mert az is `hold`-on lévő munkára épülhetne — ez a kör önálló, minimális test double-t ír). A tényleges natív emitter integrációja a Kör 13 natív munkájával együtt nyílik meg.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/platform/local_ai/local_ai_event_stream.dart",
  "lib/features/offline_ai/application/generation_controller.dart",
  "test/features/offline_ai/generation_stream_test.dart",
  "docs/rounds/e10-r14-token-streaming-and-cancellation.md",
]
gate_tests = [
  "test/features/offline_ai/generation_stream_test.dart",
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

## 1. Cél

A felhasználó az első tokeneket fokozatosan lássa, és bármikor megbízhatóan leállíthassa a generálást — a Dart-oldali kontrakt egy tesztbeli fake eseményforrással bizonyítva.

## 2. Jelenlegi állapot — mért tények

- `lib/platform/local_ai/` **nem létezik** — ez az első Flutter-oldali platform-adapter fájl EBBEN a körben (a Kör 7 `lib/platform/local_ai/local_ai_platform.dart`-ot már létrehozta a command-API-hoz — ez a kör az EVENT STREAM oldalt adja hozzá, ugyanabba a könyvtárba).
- A Kör 2 `GenerationEvent` sealed hierarchiája stabil — ez a kör NEM módosítja, csak fogyasztja.
- Az `ai_tutor` feature MÁR rendelkezik egy hasonló mintával: `TutorModelEvent` sealed hierarchia (`TutorModelDelta`, `TutorModelToolCall`, `TutorModelDone`, `TutorModelError`) a `tutor_model_event.dart`-ban — ez a kör NEM ezt a hierarchiát bővíti (a Kör 23 gateway feladata a `GenerationEvent`→`TutorModelEvent` leképezés), hanem a `GenerationEvent`-et önmagában streameli és cancel-eli.

## 3. Scope

**Benne van:** Flutter stream adapter, ami egy `Stream<GenerationEvent>`-et fogyaszt (a natív emitter helyén EBBEN a körben egy teszt-oldali fake) · kötelező event order: pontosan egy `GenerationStarted`, nulla vagy több token/metrics, PONTOSAN egy terminal event · apró token callbackek batch-elése rövid időablakban (szöveg-sorrend megőrzésével) · cancellation generation ID alapján, idempotens, p95 mérhető · listener-eltűnés és route-dispose kezelése · buffered event limit (lassú UI ne okozzon korlátlan memórianövekedést) · NINCS teljes Markdown-újraparsolás minden tokennél.

**NINCS benne (tilos):**

- A VALÓS natív `LocalAiEventEmitter.kt` — nyitott tartozás, Kör 13-mal együtt.
- A `TutorModelEvent`-re történő leképezés — ez Kör 23 dolga.
- `docs/adr/**` — az ADR 0429-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/platform/local_ai/local_ai_event_stream.dart` | ÚJ — a Flutter-oldali stream adapter |
| `lib/features/offline_ai/application/generation_controller.dart` | ÚJ — cancellation, buffering, dispose-kezelés |
| `test/features/offline_ai/generation_stream_test.dart` | a §6 cellái, SAJÁT lokális fake eseményforrással |

**Tilos zóna:** `android/**` · `lib/features/ai_tutor/**` (a `TutorModelEvent` leképezés Kör 23 dolga) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0429)

### 5.1 Pontosan egy terminal event minden generáció végén

Minden `GenerationId`-hez tartozó stream PONTOSAN egy `GenerationCompleted`, `GenerationCancelled` VAGY `GenerationFailed` eseménnyel zár — sem kettő, sem nulla.

**NEM elfogadható gyengítés:** egy implementáció, ami cancel után is ELKÜLDI a `GenerationCompleted`-et "mert a natív oldal már elküldte, mielőtt a cancel megérkezett" — a Dart-oldali controllernek KELL deduplikálnia, hogy a hívó felé csak egy terminal event jusson el.

### 5.2 A cancel idempotens — kétszeri hívás nem hibázik és nem duplikál terminal eventet

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az esemény-sorrend mindig `Started → token(0..n) → EGY terminal` | `generation_stream_test.dart` |
| A2 | Cancel indítás előtt kontrolláltan `GenerationCancelled`-et ad, natív hívás nélkül | `generation_stream_test.dart` |
| A3 | Cancel prefill/decode közben pontosan egy terminal eventet eredményez | `generation_stream_test.dart` |
| A4 | Listener dispose után a stream nem hív callback-et, nincs memory leak (fake forrás lezárva) | `generation_stream_test.dart` |
| A5 | Backpressure: lassú fogyasztó mellett a buffer korlátozott, nem nő korlátlanul | `generation_stream_test.dart` |
| A6 | Unicode karakterhatáron átnyúló token-split nem töri a szöveget | `generation_stream_test.dart` |
| A7 | Kétszeri cancel nem duplikál terminal eventet | `generation_stream_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A cancel után is átengedi a natívtól érkező `GenerationCompleted`-et | A3 (két terminal event érkezne) |
| A dispose nem törli a listenert, a fake forrás további eseményei crash-elnek | A4 |
| A buffer korlátlanul nő lassú fogyasztónál | A5 |
| A batch-elés token közepén vágja el egy multi-byte Unicode karaktert | A6 |
| A második cancel-hívás egy második `GenerationCancelled`-et küld | A7 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedd át a natív `GenerationCompleted`-et cancel után is deduplikáció nélkül, futtasd a tesztet → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/generation_stream_test.dart
```

## 8. Implementációs sorrend

1. `local_ai_event_stream.dart` — a platform-oldali stream adapter interfésze.
2. `generation_controller.dart` — cancellation, dedup, buffering, dispose.
3. Unicode-split védelem.
4. A teszt-fájlon belüli lokális fake eseményforrás.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A dupla terminal event.** A UI-t (Kör 24+) megzavarná, ha kétszer kapna "kész" jelzést (A3).
- **A memory leak dispose után.** Route-váltás közbeni generálás gyakori forgatókönyv, a nem megfelelő dispose-kezelés akkumulálódó erőforrás-szivárgást okozna (A4).
- **A natív emitter hiányának elfelejtése.** A HANDOFF-nak és a Kör 23 pre-flightjának explicit rögzítenie kell, hogy a VALÓS natív integráció még nyitott (Kör 13 mellett).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
