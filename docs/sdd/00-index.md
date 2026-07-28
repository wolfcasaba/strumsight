# StrumSight SDD — Master Index

**Repository:** `wolfcasaba/strumsight`  
**Dokumentumkészlet verziója:** 1.0  
**Utolsó frissítés:** 2026-07-28

## Használati szabály

A SDD-t nem egyetlen óriási feladatként kell átadni a Codexnek. Mindig pontosan egy fejezet egy fejlesztési körét kell kijelölni. A következő kör csak az előző kör teljes Definition of Done-ja után indulhat.

## Fejezetek

| Chapter | Cím | Fejlesztési körök | Fő előfeltétel | Fájl |
|---:|---|---:|---|---|
| 1 | Architecture & Engineering Principles | — | — | [`01-architecture-engineering-principles.md`](01-architecture-engineering-principles.md) |
| 2 | Epic 1: Core Platform & Infrastructure | 16 | Chapter 1 | [`02-epic-01-core-platform.md`](02-epic-01-core-platform.md) |
| 3 | Epic 2: Practice Engine | 20 | Chapter 2 | [`03-epic-02-practice-engine.md`](03-epic-02-practice-engine.md) |
| 4 | Epic 3: Song Trainer | 22 | Chapter 2; Chapter 3 contractjai | [`04-epic-03-song-trainer.md`](04-epic-03-song-trainer.md) |
| 5 | Epic 4: AI Guitar Teacher | 24 | Chapter 2; Chapter 3 és 7 evidenciakontraktusai | [`05-epic-04-ai-guitar-teacher.md`](05-epic-04-ai-guitar-teacher.md) |
| 6 | Epic 5: Computer Vision | 30 | Chapter 2; kamera spike | [`06-epic-05-computer-vision.md`](06-epic-05-computer-vision.md) |
| 7 | Epic 6: Audio Analysis 2.0 | 30 | Chapter 2; meglévő Analyze/DSP baseline | [`07-epic-06-audio-analysis-2.md`](07-epic-06-audio-analysis-2.md) |
| 8 | Epic 7: AI Practice Generator | 30 | Chapter 3, 5 és 7 | [`08-epic-07-ai-practice-generator.md`](08-epic-07-ai-practice-generator.md) |
| 9 | Epic 8: Gamification | 30 | Chapter 3 és 8 eseményei | [`09-epic-08-gamification.md`](09-epic-08-gamification.md) |
| 10 | Epic 9: Community Platform | 32 | Chapter 2 és 9; backend migráció | [`10-epic-09-community-platform.md`](10-epic-09-community-platform.md) |
| 11 | Epic 10: Offline AI | 32 | Chapter 5 gateway contract; Chapter 2 platform | [`11-epic-10-offline-ai.md`](11-epic-10-offline-ai.md) |
| 12 | Release Roadmap, Sprint Planning & Final Integration | 42 | Chapter 1–11 specifikációja és megvalósítási állapota | [`12-release-roadmap-final-integration.md`](12-release-roadmap-final-integration.md) |

> A körszámokat a tényleges Markdown-fejezetekből számoltuk. A Chapter 12 jelenlegi dokumentuma 42 integrációs kört tartalmaz; végrehajtáskor a fájl tartalma az irányadó.

## Függőségi kép

```text
Chapter 1  Architecture principles
    ↓
Chapter 2  Core platform
    ├──▶ Chapter 3  Practice Engine
    │       ├──▶ Chapter 4  Song Trainer
    │       ├──▶ Chapter 8  Practice Generator
    │       └──▶ Chapter 9  Gamification
    ├──▶ Chapter 7  Audio Analysis 2.0
    │       ├──▶ Chapter 5  AI Guitar Teacher
    │       └──▶ Chapter 8  Practice Generator
    ├──▶ Chapter 6  Computer Vision
    │       └──▶ Chapter 5 / 7 evidence integration
    ├──▶ Chapter 10 Community Platform
    └──▶ Chapter 11 Offline AI

Chapter 12 integrates and releases all completed capabilities.
```

## Ajánlott végrehajtási sorrend

1. Chapter 2 teljesen.
2. Chapter 3 teljesen.
3. Chapter 7 alap- és contractkörei; majd a teljes Chapter 7.
4. Chapter 4.
5. Chapter 5, a cloud gateway és tool contractok kialakításával.
6. Chapter 6 mérési spike és fokozatos vision képességek.
7. Chapter 8.
8. Chapter 9.
9. Chapter 10 csak a backend production alapok után.
10. Chapter 11 a Chapter 5 stabil gateway contractjára.
11. Chapter 12 folyamatosan használható governance keretként, de a végső GA-körök csak az előző fejezetek lezárása után.

Részletes sorrend: [`../execution/01-implementation-order.md`](../execution/01-implementation-order.md).

## Kötelező kísérő dokumentumok

- [`../../AGENTS.md`](../../AGENTS.md)
- [`../../CODEX_START_HERE.md`](../../CODEX_START_HERE.md)
- [`../execution/02-codex-playbook.md`](../execution/02-codex-playbook.md)
- [`../execution/03-definition-of-ready.md`](../execution/03-definition-of-ready.md)
- [`../execution/04-definition-of-done.md`](../execution/04-definition-of-done.md)
- [`../execution/06-requirements-traceability-matrix.md`](../execution/06-requirements-traceability-matrix.md)
- [`../execution/07-risk-register.md`](../execution/07-risk-register.md)
