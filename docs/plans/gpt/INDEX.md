# GPT plan corpus — index

> Feltöltve: **2026-07-28** (Codex Execution Pack, 58 fájlos manifest → 23 chunk itt).
> Triage a HANDOFF (r205) + dsp chunk 001–018 ellen: lásd lent. Frissítsd minden chunk-változással egy commitban.

## Chunkok

| id | topic | status | depends_on | round / as_built |
|----|-------|--------|------------|------------------|
| 101 | AGENTS.md ágens-szabályrendszer | active | — | → E01-R01 hozza létre a gyökérben |
| 102 | Codex Start Here | active | 101, 103 | |
| 103 | SDD Master Index (12 fejezet, függőségi gráf) | active | — | → E01-R01: docs/sdd/ |
| 104 | SDD Ch1 — Architecture & Engineering Principles | active | 101 | |
| 105 | SDD Ch2 / **Epic 1** — Core Platform (16 kör) | active | 104 | **ITT KEZDÜNK: E01-R01** |
| 106 | SDD Ch3 / Epic 2 — Practice Engine (20 kör) | active | 105 | |
| 107 | SDD Ch4 / Epic 3 — Song Trainer (22 kör) | active | 105, 106 | |
| 108 | SDD Ch5 / Epic 4 — AI Guitar Teacher (24 kör) | active | 105, 106, 110 | |
| 109 | SDD Ch6 / Epic 5 — Computer Vision (30 kör) | active | 105, 106 | |
| 110 | SDD Ch7 / Epic 6 — Audio Analysis 2.0 (30 kör) | active | 105 + dsp 001–018 | |
| 111 | SDD Ch9 / Epic 8 — Gamification (30 kör) | active | 106 (+ hiányzó Ch8) | |
| 112 | Implementation Order (fázis A–E, első 12 kör) | active | 103 | |
| 113 | Codex Playbook | active | 101 | |
| 114 | Definition of Ready | active | — | |
| 115 | Definition of Done | active | — | |
| 116 | Branch/Commit/PR szabályok | active | — | ⚠ lásd triage P1 |
| 117 | Risk Register (R-001..R-022) | active | — | |
| 118 | Environment Setup | active | — | ✓ Flutter 3.44.2 a boxon igazolva |
| 119 | Testing Guide | active | — | |
| 120 | GitHub Milestones & Issues (M01–M11) | active | 122 | |
| 121 | Release Checklist | active | — | |
| 122 | Requirements Traceability Matrix | active | 103 | körönként frissítendő |
| 123 | Execution Pack MANIFEST | active | — | |

## Triage-eredmény (2026-07-28, HANDOFF r205 + dsp corpus ellen)

**Igazolt tények** — a terv szerzője pontosan ismerte a repót:

- Flutter a boxon **3.44.2** = a terv előírása. ✓
- GitHub remote már `wolfcasaba/strumsight` — a repo-név rendben; a Dart package viszont
  még `music_theory` → **E01-R02 valós munka** (rename + Android/iOS azonosítók).
- A terv fájlszámai (~165 forrás / 159 teszt) egyeznek a valósággal (168 dart fájl).
- Ch2 §3.4 "azonosított adósságok" listája pontos (create_all, debug signing, cross-feature importok…).

**Megerősített tanulságok** (a terv NEM ütközik a mért igazsággal, hanem kodifikálja):

- R-001 (synth→real gap) = a **r199 verdikt** (synth-ML 36% < DSP 56% valós audión). A Ch7
  real-audio evaluation gate-je pont az `ml/chords/eval_real_sessions.py` harness irányát írja elő.
- "Külön parancsok, ne `&&`" = a CLAUDE.md OOM-tanulsága, szó szerint átvéve.
- Mic autoDispose (Ch2 Kör 9.5) — a r185 C1 regression guard már védi; a kör erre ÉPÍT, nem újraírja.

**Részben már kész** (az érintett körök baseline-audittal indulnak, nem nulláról):

- Lab mode flag + perzisztencia (r197) → Ch2 feature-flags körének inputja.
- Property gate + `PROPERTY_SEED` CI (HORIZON) → a terv property-követelménye már él.
- Backend rate limiter, JWT auth, diagnostics upload → Ch2 Kör 13 hardeningje ezekre épül.

**⚠ Nyitott döntések (P1 — user):**

1. **Workflow-váltás (116):** a terv branch-per-round + PR + védett main + review-t ír elő; eddig
   az autonóm körök közvetlenül main-re commitoltak. Döntés kell: átállunk-e a codex/eXX-rYY
   branch-modellre (ajánlott: igen, de review-er nélkül a "legalább 1 review" szabály lazítandó).
2. **E01-R02 rename:** az Android application ID csere a telepített appot ÚJ appként jeleníti meg
   (a terv dokumentálja). Store-release előtt OK — de a user Lab-telepítéseit érinti; jelezni.
3. **Hiányzó fejezetek feltöltése** (lásd lent) — Ch8/10/11/12 nélkül a Fázis C–E nem indítható.

## Hiányzó dokumentumok (a manifest 58 fájljából még nincs feltöltve)

- `docs/sdd/08-epic-07-ai-practice-generator.md` (Ch8) — a 111 (gamification) függősége!
- `docs/sdd/10-epic-09-community-platform.md` (Ch10)
- `docs/sdd/11-epic-10-offline-ai.md` (Ch11)
- `docs/sdd/12-release-roadmap-final-integration.md` (Ch12, 42 kör)
- `docs/execution/08-codex-round-prompt-template.md`, `09-document-authority-and-migration.md`
- `docs/development/01–06, 08` (local/android/backend/ml setup, env vars, secrets, troubleshooting)
- `docs/governance/02, 03, 05–13` (labels, board, device matrix, security, licence, UX, fixtures, business, privacy)
- `templates/*` (ADR, ISSUE, PR, HANDOFF, EPIC report, release notes), `README.md`, `VALIDATION_REPORT.md`
- `.github/ISSUE_TEMPLATE/codex-sdd-round.md`, `.github/PULL_REQUEST_TEMPLATE.md`

## Elhelyezési terv

E01-R01 létrehozza a kanonikus helyeket (`AGENTS.md`, `docs/sdd/`, `docs/execution/`…) — akkor
ezek a chunkok a kanonikus fájl MÁSOLATÁVÁ válnak és a frontmatter `as_built:` mezője a repo-beli
útvonalra mutat. A RAG-korpusz (status-életciklussal) itt marad a kereshetőség miatt.
