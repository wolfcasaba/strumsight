# E99-R11 — Independent security review

Brief: `docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md`
Diff: `d4341eb..39068df6449df59309d4a79b44b7e60866441181`
Reviewer: Codex (independent fresh-clone re-review) · Date: 2026-08-15
Verdict: APPROVED

## Summary

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

The F1 fix is correct. `AnalysisPipeline` now makes an immutable defensive
copy of a supplied phase map, and its committed regression test proves that
mutating the caller-owned map after construction cannot alter the previously
validated pipeline. The scope remains clean and the changed production code
does not add networking, raw-audio export, microphone/camera ownership,
provider wiring, secrets, or logging.

## Scope audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r11-security-r2 --brief docs/rounds/e99-r11-gov-30c-3-progress-phase-decoupling.md --base d4341eb`

Result: `Legacy scope audit OK (d4341eb..39068df6449d, 8 changed path(s), 2 generated/ignored)`.
The two ignored paths are review-generated reports.

## Finding closure

### F1 — MAJOR — Validated phase map remained mutable after construction

- **Previous status:** OPEN at `f1afd6e`.
- **Fix:** `39068df` stores
  `Map<String, AnalysisProgressPhase>.unmodifiable(stagePhases)` in
  `lib/features/audio_analysis/engine/analysis_pipeline.dart:66-68`.
- **Regression evidence:** committed test `F1 — mutating the caller-owned
  stagePhases map after construction does not affect a previously validated
  pipeline` in `test/features/audio_analysis/engine/analysis_pipeline_test.dart`
  mutates the caller map from `computingMetrics` to `preprocessing` after
  construction, then verifies a complete run with two `computingMetrics`
  events. It passed in this independent clone.
- **Status:** FIXED (`39068df`).

## Gate evidence

| Check | Result |
|---|---|
| F1 targeted regression | ✅ `flutter test test/features/audio_analysis/engine/analysis_pipeline_test.dart --plain-name 'F1 — mutating the caller-owned stagePhases map after construction does not affect a previously validated pipeline'` |
| Required round gate | ✅ exit 0 after the documented `tools/prepare-flutter-generated.sh` restored ignored l10n output: `tools/round-gate.sh test/features/audio_analysis/engine/full_pipeline_composition_test.dart test/features/audio_analysis/engine/analysis_pipeline_test.dart test/features/audio_analysis/engine/stages/analysis_stage_phases_test.dart` |
| Initial pristine-clone gate attempt | ⚠️ stopped at analysis only because ignored `lib/l10n/app_localizations.dart` was absent; this is an environment prerequisite, not a diff failure |
| Product-boundary scan | ✅ no changed production-file reference to HTTP/socket, Dio, microphone, camera, preference, or print/debug logging; `application/**` remains unchanged and `analysisV2RunnerProvider` still throws `StateError` |

## Merge decision

Security review APPROVED. No unresolved security finding remains from this
review.
