# E99-R11 — Independent security review

Brief: `docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md`  
Diff: `d4341eb..f1afd6ee7c72dc98dbfc81acaba1ca50563755ac`  
Reviewer: Codex (independent isolated-clone review) · Date: 2026-08-15  
Verdict: CHANGES REQUIRED

## Summary

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 0

The diff stays within the brief's allow-list; it adds no networking, raw-audio
export, microphone/camera ownership, provider wiring, or logging path. The
required local gate passed in a fresh `/tmp` clone. However, the new public
`stagePhases` constructor argument is retained by reference after its
validation. A caller can mutate it after construction, invalidating the
non-decreasing and complete-map guarantees during a run.

## Acceptance and product-boundary evidence

| Item | Status | Evidence |
|---|---|---|
| A1–A8 | ✅ except F1 durability gap | required round gate passed; source/tests inspected in isolated clone |
| A9: V2 provider remains fail-closed | ✅ | no `application/**` path in `d4341eb..HEAD`; `analysis_providers.dart:213-216` still throws `StateError` |
| A10: nine-phase enum unchanged | ✅ | no `domain/analysis_progress.dart` path in the diff |
| Raw audio / network / mic / camera / secret boundary | ✅ | changed production files contain no `Dio`, HTTP/socket, mic/camera, preference, or print/debug logging use; no provider wiring changed |

## Scope audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r11-security --brief docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md --base d4341eb`

Result: `Legacy scope audit OK (d4341eb..f1afd6ee7c72, 6 changed path(s), 0 generated/ignored)`.

## Findings

### F1 — MAJOR — Validated phase map remains mutable after construction

- **File:** `lib/features/audio_analysis/engine/analysis_pipeline.dart:66,111,202`
- **Problem:** `_stagePhases` retains the caller-provided `Map` rather than an
  immutable defensive copy. The constructor validates completeness and
  non-decreasing order only once. A caller can subsequently remove an ID or
  regress a phase; the latter makes a run fail with the runtime monotonicity
  `StateError`, and a removed mapping can re-enable the positional fallback
  (including `RangeError` beyond phase index 8).
- **Impact:** The new composition contract can be invalidated after validation,
  producing a failed analysis run instead of the checked, deterministic
  phase-map behavior. This violates the project's immutable-state rule and
  undermines the safety guard that prevents user-visible progress regression.
- **Measured reproduction:** a disposable isolated-clone test constructed two
  stages with two `computingMetrics` entries, changed the second entry to
  `preprocessing` after `AnalysisPipeline` construction, then asserted a
  complete run. It failed: `Expected: AnalysisCompletionStatus.complete;
  Actual: AnalysisCompletionStatus.failed`.
- **Required fix:** retain a defensive immutable copy, e.g.
  `_stagePhases = stagePhases == null ? null : Map<String, AnalysisProgressPhase>.unmodifiable(stagePhases)`, and add a permanent regression test that mutates the input map after construction and proves the pipeline still uses the validated mapping.
- **Verification:** run the disposable regression as a committed test plus the
  required `tools/round-gate.sh` command.
- **Status:** OPEN.

## Gate evidence

| Check | Result |
|---|---|
| Required round gate | ✅ exit 0: `tools/round-gate.sh test/features/audio_analysis/engine/full_pipeline_composition_test.dart test/features/audio_analysis/engine/analysis_pipeline_test.dart test/features/audio_analysis/engine/stages/analysis_stage_phases_test.dart` |
| A7 targeted test after probe cleanup | ✅ `flutter test test/features/audio_analysis/engine/analysis_pipeline_test.dart --plain-name 'A7 — two stages sharing the same mapped phase do not throw'` |
| Disposable F1 probe | ❌ correctly failed, proving the finding; probe removed and clone returned clean |
| Diff whitespace / clone cleanliness after probe cleanup | ✅ `git diff --check`; `git status --short` empty |

## Merge decision

Merge is prohibited while F1 is open. Re-run this independent review in a new
isolated clone after the fix.
