---
id: 116
topic: Branch/Commit/PR szabályok — codex/eXX-rYY-slug, Conventional Commits, PR tartalom, merge policy, main protection
tags: [execution, git, branch, pr, policy]
status: active
depends_on: []
canonical_target: docs/execution/05-branch-and-pr-rules.md
verify: branch védelmi szabályok élnek GitHubon
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, 58-file manifest)
---

# Branch, Commit and Pull Request Rules

## Branch stratégia

Alapértelmezett branch: `main`.

Formátum:

```text
codex/e<epic>-r<round>-<slug>
```

Példák:

```text
codex/e01-r01-repository-baseline
codex/e03-r07-musicxml-import
codex/e10-r04-device-benchmark
release/1.0.0-rc1
hotfix/1.0.1-audio-crash
```

## Commit

Conventional Commit:

```text
<type>(<scope>): <imperative summary>
```

Típusok: `feat`, `fix`, `refactor`, `test`, `docs`, `ci`, `build`, `chore`, `perf`, `security`.

Egy commit:

- egy logikai egység;
- buildelhető vagy egyértelműen köztes, ha PR-on belül squash történik;
- nem kever unrelated formattingot;
- nem tartalmaz secretet vagy generált buildet.

## PR méret

Ideális PR egy SDD-kör. Ha egy kör nagyobb:

- bontsd contract, implementation és migration al-PR-ra;
- tartsd ugyanazon requirement ID alatt;
- dokumentáld a merge-sorrendet;
- egyik rész sem kerülhet productionba veszélyes félállapotban feature flag nélkül.

## PR cím

```text
[E01-R03] Introduce validated app bootstrap
```

## Kötelező PR tartalom

- SDD requirement és kör;
- cél és nem-cél;
- fő változások;
- migration/API hatás;
- tesztek pontos parancsokkal;
- screenshot vagy device evidence, ha UI;
- performance evidence, ha audio/AI/vision;
- privacy/security hatás;
- rollback;
- follow-up issue.

## Merge policy

Javasolt: squash merge, kivéve több értékes, önálló commitot tartalmazó migráció vagy release ág.

Tilos merge-elni:

- piros required checkkel;
- unresolved blocking review-val;
- hiányzó migrációval;
- debug signingos production release-szel;
- frissítetlen HANDOFF/traceability mellett;
- secret scan hibával.

## Main protection

- direct push tiltott;
- legalább 1 review;
- required CI;
- branch up-to-date vagy merge queue;
- force push és branch deletion korlátozott;
- release tag csak zöld, azonosított commitra.

## Hotfix

Hotfix csak production regresszióra. A hotfix:

- minimális scope;
- reprodukáló teszt;
- release branch és main back-merge;
- külön incident/postmortem hivatkozás;
- nem tartalmaz feature fejlesztést.

---
