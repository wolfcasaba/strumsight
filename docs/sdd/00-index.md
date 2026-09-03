# StrumSight SDD — Master Index

**Repository:** `wolfcasaba/strumsight`  
**Dokumentumkészlet verziója:** 1.0  
**Utolsó frissítés:** 2026-07-28

## Használati szabály

A SDD-t nem egyetlen óriási feladatként kell átadni a Codexnek. Mindig pontosan egy fejezet egy fejlesztési körét kell kijelölni. A következő kör csak az előző kör teljes Definition of Done-ja után indulhat.

## Fejezetek

| Chapter | Cím | Fejlesztési körök | Fő előfeltétel | Fájl | Zárójelentés | Státusz | Implementation progress | Dependency |
|---:|---|---:|---|---|---|---|---|---|
| 1 | Architecture & Engineering Principles | — | — | [`01-architecture-engineering-principles.md`](01-architecture-engineering-principles.md) | — | — | — | — |
| 2 | Epic 1: Core Platform & Infrastructure | 16 | Chapter 1 | [`02-epic-01-core-platform.md`](02-epic-01-core-platform.md) | [`epic-01-completion-report.md`](epic-01-completion-report.md) | lezárva (E01-R16) | ld. `epic-01-completion-report.md` (zárókör E01-R16) | ch01 |
| 3 | Epic 2: Practice Engine | 20 (lezárva E02-R20, 2026-08-01) | Chapter 2 | [`03-epic-02-practice-engine.md`](03-epic-02-practice-engine.md) | [`epic-02-completion-report.md`](epic-02-completion-report.md) | lezárva (E02-R20) | ld. `epic-02-completion-report.md` (zárókör E02-R20, 2026-08-01) | ch02 |
| 4 | Epic 3: Song Trainer | 22 — implementation evidence recorded; release blockers remain | Chapter 2; Chapter 3 contractjai | [`04-epic-03-song-trainer.md`](04-epic-03-song-trainer.md) | [`epic-03-completion-report.md`](epic-03-completion-report.md) | implementation evidence recorded (nem release approval) | ld. `epic-03-completion-report.md` — release blockerek nyitva | ch03, ch07 |
| 5 | Epic 4: AI Guitar Teacher | 24 | Chapter 2; Chapter 3 és 7 evidenciakontraktusai | [`05-epic-04-ai-guitar-teacher.md`](05-epic-04-ai-guitar-teacher.md) | — | queue-szinten lezárva (24/24 done) | ld. `program-completion-report.md` §3 (E04, 2026-09-02 mérés) | ch07 |
| 6 | Epic 5: Computer Vision | 30 | Chapter 2; kamera spike | [`06-epic-05-computer-vision.md`](06-epic-05-computer-vision.md) | — | queue-szinten lezárva (30/30 done); Vision-képességek flag-OFF, valós eszköz HORIZON-elfogadás nyitva | ld. `program-completion-report.md` §3 (E05, 2026-09-02 mérés) | ch02 |
| 7 | Epic 6: Audio Analysis 2.0 | 30 — implementation evidence recorded; rollout stays at shadow, release blockers remain | Chapter 2; meglévő Analyze/DSP baseline | [`07-epic-06-audio-analysis-2.md`](07-epic-06-audio-analysis-2.md) | [`epic-06-completion-report.md`](epic-06-completion-report.md) | queue-szinten lezárva (30/30 done); rollout shadow-n marad, release blockerek nyitva | ld. `epic-06-completion-report.md` + `program-completion-report.md` §3 (E06, 2026-09-02 mérés) — release blockerek nyitva | ch02 |
| 8 | Epic 7: AI Practice Generator | 30 | Chapter 3, 5 és 7 | [`08-epic-07-ai-practice-generator.md`](08-epic-07-ai-practice-generator.md) | — | queue-szinten lezárva (30/30 done); rollout OFF, emberi release-döntés nyitva | ld. `program-completion-report.md` §3 (E07, 2026-09-02 mérés) | ch03, ch07 |
| 9 | Epic 8: Gamification | 30 | Chapter 3 és 8 eseményei | [`09-epic-08-gamification.md`](09-epic-08-gamification.md) | — | nyitva (hold: E08-R29 integrity/CI guard kör; 29/30 done) | ld. `program-completion-report.md` §3 (E08, 2026-09-02 mérés) | ch03, ch08 |
| 10 | Epic 9: Community Platform | 32 | Chapter 2 és 9; backend migráció | [`10-epic-09-community-platform.md`](10-epic-09-community-platform.md) | — | nyitva (hold: E09-R28…R32 — privacy export/deletion, offline sync hardening, rate-limit/security, accessibility polish, integration load-eval; 27/32 done) | ld. `program-completion-report.md` §3 (E09, 2026-09-02 mérés) | ch02, ch09 |
| 11 | Epic 10: Offline AI | 32 | Chapter 5 gateway contract; Chapter 2 platform | [`11-epic-10-offline-ai.md`](11-epic-10-offline-ai.md) | — | nyitva (hold: a TELJES sáv, mind a 32 kör; programdöntés, nem mérési hiba) | ld. `11-epic-10-offline-ai.md` + `program-completion-report.md` §3 (E10, 2026-09-02 mérés) | ch02, ch05 |
| 12 | Release Roadmap, Sprint Planning & Final Integration | 36 | Chapter 1–11 specifikációja és megvalósítási állapota | [`12-release-roadmap-final-integration.md`](12-release-roadmap-final-integration.md) | — | kör-munka lezárva (36/36 done); EMBERI KAPUK NYITOTT (ld. program-completion-report.md §5) | ld. `docs/release/program-baseline.md` + `docs/release/blockers.md` (E12-R01 mérés, 2026-08-28) + `program-completion-report.md` §3, §5 (E12, 2026-09-02 mérés) | ch01–ch11 |
| 13 | UI/UX Design System & Screen Specification | 36 | cross-cutting; Chapter 1–12 felületei | [`13-chapter-13-ui-ux-design-system.md`](13-chapter-13-ui-ux-design-system.md) | — | queue-szinten lezárva (36/36 done) | ld. `program-completion-report.md` §3 (E13, 2026-09-02 mérés) | ch01, ch12 |
| 14 | Recognition Accuracy & Useful UI Recovery | 42 | Chapter 7 audio analysis; Chapter 13 UI | [`14-chapter-14-recognition-ui-recovery.md`](14-chapter-14-recognition-ui-recovery.md) | — | nyitva (1/42 done, 18 prepared nem futtatva; R20–R42 briefjei meg sem íródtak) | ld. `program-completion-report.md` §3, §4 (E14, 2026-09-02 mérés) | ch07, ch13 |

> A körszámokat a `tool/check_sdd_index.dart` méri a fejezet-fájlok kör-fejléceiből
> (`# Kör N` és `## Kör N` alak egyaránt), és ehhez a mért értékhez igazítja a
> fenti táblát — a checker teszt-párja `test/tooling/sdd_index_guard_test.dart`
> (ADR 0443 D1). A korábbi prózai mentesítés („végrehajtáskor a fájl tartalma az
> irányadó") megszűnt, mert nem tudott pirosra váltani; a Chapter 12 sorának
> egykori `42` értéke a mért `36`-ra javítva. A „Státusz" / „Implementation
> progress" / „Dependency" oszlopok bizonyítéka a linkelt zárójelentés, illetve
> Chapter 12-nél a Kör 1 (E12-R01) baseline-mérése
> ([`docs/release/program-baseline.md`](../release/program-baseline.md),
> [`docs/release/blockers.md`](../release/blockers.md)); ahol nincs ilyen
> bizonyíték, a cella ezt kimondja ahelyett, hogy találgatna.
>
> **A „Dependency" oszlop illusztráció, nem szerződés** — az ASCII „Függőségi
> kép"-hez hasonlóan ember-olvasóknak szól. A fejezetek közötti függőség
> EGYETLEN géppel ellenőrzött forrása a
> [`dependency-graph.yaml`](dependency-graph.yaml) `edges:` blokkja
> (ADR 0443 D2); a checker ma nem veti össze a két helyet, és a Chapter 12 sora
> más jelöléssel is él (`ch01–ch11` tartomány a többi sor vesszős
> felsorolásához képest), tehát ez az oszlop nem tekinthető gépi szerződésnek.
>
> **Chapter 13 és 14 (hozzáadva 2026-08-15).** Egyik sem epic: cross-cutting
> programok, ezért a kör-azonosítójuk `E13-RNN` és `E14-RNN` — a szám a
> FEJEZETET jelöli, nem egy epicet (az epicek E01–E10). Ugyanaz a minta, mint az
> `E99` governance-pszeudoepic. A Chapter 14 kutatási alapja:
> [`docs/research/recognition-research-sources.md`](../research/recognition-research-sources.md),
> a végrehajtási gyorsindító:
> [`docs/research/recognition-recovery-quick-start.md`](../research/recognition-recovery-quick-start.md).

## Függőségi kép

> A géppel ellenőrzött forrás [`dependency-graph.yaml`](dependency-graph.yaml)
> (ADR 0443 D2): a `tool/check_sdd_index.dart` ezt olvassa és méri
> körmentesnek. Az alábbi ASCII-ábra ettől kezdve illusztráció, ember
> olvasóknak — nem szerződés, és ebben a körben nem verifikált a manifest
> ellen.

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
