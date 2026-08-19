# Epic 7 — AI Practice Generator completion report

**Status:** implementation evidence complete; rollout remains OFF pending a
separate human release decision.

## E07-R30 evaluation evidence

The evaluation corpus contains three deterministic learner profiles: starter
rhythm, chord transition, and micro strumming. The shadow harness composes the
existing evidence reducer, priority engine, candidate selector, time allocator,
weekly scheduler, validator, and real `GenerationOrchestrator`. Its activation
boundary is an in-memory no-op: all three runs reached that boundary once and
recorded zero persistent writes.

`flutter test tool/practice_plan_eval/plan_quality_report.dart` on 2026-08-19
reported 3/3 successful plans, zero hard validation violations, three no-op
activation calls, zero persistent writes, 76,782 microseconds total latency,
and a 3,735,552-byte process RSS delta. This is a development-box corpus
measurement, not an Android performance claim.

The property suite reads `PROPERTY_SEED`, defaulting to 42, and compares the
full serialized plans from repeated inputs. The golden suite rejects any hard
validation finding and checks each profile's expected executable candidate. A
real-violation probe changed one expected candidate to
`probe.invalidCandidate`; the golden suite failed against the generated
`rhythm.quarterNotes.steady`, then passed again after restoration.

## Rollout boundary

`practiceGeneratorEnabled` and `plannerAssistEnabled` remain false. This round
does not alter flags, CI workflows, local repositories, or active-plan
controllers. Shadow output is evaluation-only and cannot persist or activate a
learner-visible plan.

## Open items

- A human release gate must decide whether either feature flag can be enabled.
- The full CI suite, randomized property gate, and release APK remain required
  merge evidence and are not substituted by this local corpus run.
- A real Android-device offline flow and device-specific latency/memory baseline
  are still required before making product performance claims.
- `GenerationOrchestrator.generate()` still fuses validated generation with its
  injected activation boundary; a future production preview-confirmation flow
  needs a separately scoped activation split.
- Planner Assist has no live transport rollout in this round; deterministic
  output remains authoritative when no assisted explanation is available.
