---
id: 120
topic: GitHub Milestones & Issues — M01–M11, issue-elnevezés ([E01-R01]), backlog-generálási folyamat
tags: [governance, github, milestones, issues]
status: active
depends_on: [122]
canonical_target: docs/governance/01-github-milestones-and-issues.md
verify: milestone-ok és issue-k léteznek GitHubon
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# GitHub Milestones and Issue Backlog Plan

## Milestone-ok

| Milestone | SDD | Befejezési kapu |
|---|---|---|
| M01 Core Platform | Chapter 2 | 16 kör + completion report |
| M02 Practice Engine | Chapter 3 | 20 kör |
| M03 Song Trainer | Chapter 4 | 22 kör |
| M04 AI Guitar Teacher | Chapter 5 | 24 kör |
| M05 Computer Vision | Chapter 6 | 30 kör |
| M06 Audio Analysis 2.0 | Chapter 7 | 30 kör |
| M07 AI Practice Generator | Chapter 8 | 30 kör |
| M08 Gamification | Chapter 9 | 30 kör |
| M09 Community Platform | Chapter 10 | 32 kör |
| M10 Offline AI | Chapter 11 | 32 kör |
| M11 Final Integration & Release | Chapter 12 | a fájlban szereplő 42 kör |

## Issue elnevezés

```text
[E01-R01] Repository baseline és Codex szabályrendszer
[E07-R12] <kör címe>
[INT-R04] Branch protection, CODEOWNERS és merge policy
```

## Issue body

Használd a `templates/ISSUE_TEMPLATE.md` fájlt. Minden issue tartalmazza:

- requirement ID;
- SDD relatív link és heading;
- cél/nem-cél;
- acceptance criteria;
- tesztparancs;
- dependency;
- risk/privacy/security;
- Definition of Ready.

## Issue generálási folyamat

1. Milestone létrehozása.
2. A traceability matrix sorai alapján issue-k létrehozása.
3. Címkék és dependency linkek.
4. Csak a következő 1–2 sprint issue-jai kerüljenek `Ready` státuszba.
5. Távoli epicek maradjanak `Backlog`, hogy az aktuális implementációból származó tanulságok beépülhessenek.

## Parent epic issue

Minden milestone kapjon parent Epic issue-t:

- cél;
- fejezetlink;
- körök checklistje;
- kockázatok;
- release gate;
- completion report link.

## Automatizálás

A GitHub Issue-k automatikus tömeges létrehozása csak dry-run és owner review után történjen. Ne nyiss több száz issue-t ellenőrzés nélkül.

---
