# E07-R25 — Independent review

Brief: `docs/rounds/e07-r25-analysis-and-vision-evidence.md`
Diff: `origin/main...520c058d`
Reviewer: Codex / gpt-5.6-terra
Date: 2026-08-19
Verdict: APPROVED

## Summary

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The branch was first synchronised with current `origin/main` (including the
E07-R25/H5 self-heal) without conflict. The original F1 MAJOR remains closed:
the adapter itself rejects a port-supplied `notObservable` fact before building
`SkillEvidence`.

## Acceptance criteria

| # | Result | Evidence |
|---|---|---|
| A1 | ✅ | Both adapter tests serialise only derived fields; the nested Vision barrel has the constrained export list. |
| A2 | ✅ | Empty Vision input produces an empty result without an exception. |
| A3 | ✅ | Analysis/weight-policy cells bound low-confidence influence. |
| A4 | ✅ | Low signal quality emits a separate setup advisory, not a performance value. |
| A5 | ✅ | A non-allowlisted Vision metric is dropped with `metricNotAllowed`. |
| A6 | ✅ | Analysis conflict cells apply the uncertainty penalty. |
| A7 | ✅ | `notObservable` is rejected both by the default reader and at the adapter port boundary. |
| A8 | ✅ | The Vision adapter imports only `vision/domain/evidence/public.dart`; scope and architecture guards cover the boundary. |

## Scope and falsification

`python3 tools/scope-audit.py --repo /tmp/review-e07-r25-BNrTgf --brief docs/rounds/e07-r25-analysis-and-vision-evidence.md --base origin/main` returned `Legacy scope audit OK (origin/main..520c058d0086, 14 changed path(s), 1 generated/ignored)`.

I temporarily removed the adapter's `ObservationState.notObservable` gate in
the isolated clone. The Vision adapter test then failed in both F1 cells
(`expected empty, actual SkillEvidence` and `expected length 1, actual length
2`). I restored the exact gate and reran the file: **10 passed**. The isolated
clone is clean of the temporary mutation.

## Gate evidence

| Check | Result |
|---|---|
| Machine scope audit | ✅ fresh isolated-clone run |
| F1 adversarial mutation | ✅ red when broken, green after restoration |
| `flutter test …vision_evidence_adapter_test.dart` | ✅ 10 passed |
| Full local round gate | Previously green in the reviewed handoff; this session's two isolated gate processes completed after the host returned early, so their terminal output is not claimed here. |
| Full CI, property gate, Router CI | Pending exact-SHA dispatch |

## Merge decision

No review finding blocks CI dispatch. Merge remains conditional on the planned
exact-SHA workflow(s), including Router CI, succeeding.
