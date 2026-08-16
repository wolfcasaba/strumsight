# E07-R12 — Review

Brief: `docs/rounds/e07-r12-skill-priority-engine.md`  
Diff: `7560bbe3..068cd44f`  
Reviewer: Codex / gpt-5.6-terra (independent `/tmp` clone) · Dátum: 2026-08-16  
Verdikt: APPROVED — CI merge-evidence pending

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The ranking is pure and deterministic: its clock comes through `asOf`, hard
constraints are structurally absent from the candidate contract, and the
explanation is the live list of signed factors rather than generated text.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Faktorok összege a score | ✅ | `skill_priority.dart`; `priority_engine_test.dart` A1 |
| A2 | `unknown` assessment, nem maximum gap | ✅ | `priority_engine.dart`; A2 és valódi-sértés próba |
| A3 | Primary boost, discomfort safety override | ✅ | `priority_engine.dart`; izolált safety-order próba |
| A4 | Prerequisite boost | ✅ | `priority_engine_test.dart` A4 |
| A5 | Uncertainty penalty | ✅ | `priority_engine_test.dart` A5 |
| A6 | Coverage debt nő | ✅ | `priority_engine_test.dart` A6; `priority_policy_test.dart` |
| A7 | Stabil, bemeneti sorrendtől független tie-break | ✅ | `priority_policy_test.dart` A7 |
| A8 | Policy-version a kimenetben | ✅ | `priority_policy_test.dart` A8 |
| A9 | Hard constraint nincs a score-ban | ✅ | `SkillPriorityCandidate` API; `priority_engine_test.dart` A9 |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e07-r12 --brief
docs/rounds/e07-r12-skill-priority-engine.md --base
7560bbe320fb62ca69b2fe3602bc48f0ee1aed69` → **OK**, 7 changed path, 0
generated/ignored. A review-jelentés az eszköz dokumentált kivétele.

## Valódi-sértés próbák

- A `priority_engine.dart` review-klónjában az unknown assessment-ágot
  ideiglenesen `0.0`-ra cseréltem. A célzott A2 teszt exit 1-gyel zárt
  (`unknown=-0.1`, ami nem nagyobb a strong skill `0.035` score-jánál).
  Visszaállítás után a célzott gate zöld.
- Egy eldobható, primer célú safe/painful párral mért review-test igazolta,
  hogy azonos score esetén a discomfortos skill a safe után rendeződik, és
  `discomfortSafety` faktort hordoz. A tesztet merge előtt töröltem.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzött eredmény |
|---|---|
| scope audit | ✅ OK |
| format | ✅ 1564 fájl, 0 változás |
| analyze | ✅ No issues found |
| célzott tesztek | ✅ 7 + 4 teszt zöld |
| architecture | ✅ OK |
| secrets | ✅ 0 finding |
| l10n | ✅ 1276 üzenet parity |
| CI (teljes suite + property + APK/tervezett workflow) | ⏳ orchestrátor dispatch után ellenőrizendő |

## Merge-döntés

A független review nem talált nyitott BLOCKER vagy MAJOR leletet. Merge csak a
branch exact-SHA-ján zöld, a CI-tervező által előírt workflow(k) után engedett.
