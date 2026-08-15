# E07-R02 — Review

**Verdict:** APPROVED

- Brief: `docs/rounds/e07-r02-typed-ids-enums-and-domain-primitives.md`
- Reviewed commit: `98af81af` (`sonnet-impl/e07-r02-typed-ids-enums-and-domain-primitives`)
- Implementer: Claude Sonnet 5 (`sonnet-impl`)
- Review clone: `/tmp/review-e07-r02.YjaEYA`

## Evidence

- The legacy scope audit passed twice: `46338f48..98af81af`, seven changed
  paths, zero generated/ignored paths.
- `git diff --check 46338f48..98af81af` passed.
- In the isolated review clone, the exact gate began cleanly: format and
  analyze passed, then `planner_ids_test.dart` (45 tests) and
  `plan_enums_test.dart` (25 tests) passed. The execution harness ended the
  streamed gate before its terminal architecture/secrets/l10n summary, so
  that full-gate result is not accepted as merge evidence and must be rerun
  after the corrective change.
- The independent A6 real-violation probe replaced the unknown-code
  `ArgumentError` with `return values.first;`. The enum suite failed five
  unknown-code tests (one per enum family); restoring the throw made all 25
  tests pass. This proves the A6 guard is effective.

## Findings

| Severity | Finding | Evidence and required correction |
|---|---|---|
| MAJOR | Typed IDs lack a JSON round-trip contract. | `lib/features/practice_generator/domain/id/planner_ids.dart:9-128` exposes only `value` and a string constructor; `planner_ids_test.dart` has no JSON round-trip cells. Ch8 §9.1 and the round's §3/§6 require JSON round-trip for IDs too. Add an explicit stable `toJson`/decode API for all six IDs and tests covering valid round-trip plus invalid decoded values. |
| MAJOR | The required injectable ID-generation seam is absent. | The round task and brief §5.5 require `String Function()` injection; `planner_ids.dart:9-128` contains no generation entry point or `String Function()` parameter. Add a small per-type generated-ID factory (or equivalent typed API) that receives the injected function, validates its output through the normal constructor, and is tested deterministically. Do not introduce an `IdGenerator` abstraction, clock, or random source. |

## Acceptance assessment

| Criterion | Status | Evidence |
|---|---|---|
| A1 | Pass | Real-domain source guard plus review grep found no Flutter/dart:ui imports. |
| A2 | Pass | Six unrelated `final class` wrappers; cross-type assignment is a compile-time error. |
| A3-A4 | Pass | Constructor validation and equality/hash tests cover all six IDs. |
| A5-A6 | Pass | Explicit code literals and decoding; independent default-fallback probe failed five cells. |
| A7 | Pass | `public.dart` exports only the two intended domain files. |
| A8 | Pass | No `DateTime.now()` or `Random` in the new domain. |
| SDD JSON / injected generation requirements | **Fail** | The two MAJOR findings above remain open. |

## Corrective re-review (`5bf55028`)

The single `sonnet-impl` corrective round closed both MAJOR findings without
expanding scope:

- Each ID now has `toJson`, `fromJson(Object?)`, and `generate(String
  Function())`; `fromJson` and `generate` both pass values through the normal
  type-specific constructor, so validation cannot be bypassed.
- The ID tests now cover six valid JSON round trips, all six non-String JSON
  rejections, six invalid decoded strings, six deterministic generated values,
  and six invalid generator outputs.
- A fresh isolated clone (`/tmp/review-e07-r02-fix.AXeofq`) passed the exact
  complete round gate: format, analyze, 60 ID tests, 25 enum tests, 17
  architecture tests, architecture, secrets, and l10n.
- The type-safety violation probe `final DayId x = PlanId('plan-1');` failed
  analysis with `invalid_assignment`, then was removed. The prior A6 default
  fallback probe remains valid and is documented above.

No BLOCKER, MAJOR, MINOR, or NOTE remains open. CI must be dispatched for the
review-report commit's exact SHA before merge.
