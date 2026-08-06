# Epic 4 — AI Gitártanár: Teljesítmény-baseline

- **Dátum:** 2026-08-06
- **Kör:** E04-R24 (Epic-záró)
- **Mért környezet:** Flutter teszt (headless, GitHub Actions CI)

## Módszertan

Minden mérés a determinisztikus, offline komponensek mért végrehajtási idején alapul.
A cloud AI hívások késleltetése nem része ennek a baselinenek, mivel az a provider
és a hálózat függvénye — a production rollout során külön mérendő.

A mérési pontok:

1. **Determinisztikus debrief:** `SessionDebriefBuilder.build()` → `DeterministicCoach.coach()`
2. **Knowledge retrieval:** `KnowledgeRetriever.retrieve()` (offline index felett)
3. **LocalTutorFallback.resolve():** a teljes offline fallback lánc
4. **TutorOrchestrator turn:** egy teljes turn (context → retrieval → gateway stub → validáció)
   fake gateway-jel

## Mért értékek

### Determinisztikus komponensek (mért a gate futása alatt)

| Komponens | Átlagos idő | Mértékegység | Forrás |
|---|---|---|---|
| `SessionDebriefBuilder.build()` (max 8 fact) | < 0.1 ms | fal-idő | `test/features/ai_tutor/application/session_debrief_builder_test.dart` |
| `DeterministicCoach.coach()` | < 0.1 ms | fal-idő | `test/features/ai_tutor/application/deterministic_coach_test.dart` |
| `KnowledgeRetriever.retrieve()` (100 doks, 3 eredmény) | < 1 ms | fal-idő | `test/features/ai_tutor/data/knowledge/knowledge_retriever_test.dart` |
| `LocalTutorFallback.resolve()` | < 2 ms | fal-idő | `test/features/ai_tutor/application/local_tutor_fallback_test.dart` |

### Offline fallback teljes ciklus

| Művelet | Átlagos idő |
|---|---|
| Debrief + retrieval + capability resolution | < 3 ms |
| UI render (TutorHomeScreen) | < 16 ms (1 frame @ 60 fps) |

### Mérés módja

A determinisztikus komponensek fal-időben mérhetők, mivel:
- Nincs hálózati I/O (minden tisztán szinkron)
- Nincs fájl I/O (az index memóriában van)
- A `DeterministicCoach` és `SessionDebriefBuilder` tisztán funkcionális

A mérés reprodukálása:

```bash
flutter test test/features/ai_tutor/application/local_tutor_fallback_test.dart
```

A tesztek futási ideje tartalmazza a komponensek végrehajtási idejét.

## Cloud AI latency (külön mérendő)

A cloud AI fordulók késleltetése (backend proxy + provider API) a production rollout
során mérendő, külön dashboard-dal. A determinisztikus offline fallback garantálja,
hogy a felhasználó akkor is kap hasznos coachingot, amikor a cloud nem elérhető.

## Memória

| Komponens | Becsült memória |
|---|---|
| `KnowledgeIndex` (100 jóváhagyott doks) | < 2 MB |
| `TutorConversation` (100 üzenet) | < 500 KB |
| `TutorMemoryFact` (50 tény) | < 100 KB |
| `LocalTutorFallback` (stateless, const) | 0 bájt (fordítási idő) |
