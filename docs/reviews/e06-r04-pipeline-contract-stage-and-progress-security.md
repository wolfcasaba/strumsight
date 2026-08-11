# E06-R04 — Security Review: Pipeline contract, stage, cancellation & progress

- **Round:** E06-R04 · branch `codex/e06-r04-pipeline-contract-stage-and-progress` · HEAD `ea8d95d9`
- **Brief risk label:** `high` (measured below — inherited from the `audio_analysis/**` path class, not from this diff's actual surface)
- **Reviewer role:** dedicated security review (AGENTS.md §15.1), READ-ONLY
- **Verdict:** **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR. Merge is **not** blocked on security grounds. (1 MINOR + 3 NOTE, all latent/forward-looking.)

## Method & measured risk

This round introduces an **unwired in-memory orchestration contract** with fake test stages only — no real DSP, no consumer. Measured the actual attack surface rather than trusting the `high` label:

- `rg "package:flutter|dart:io|dart:ui|dart:ffi"` over `engine/` + `domain/analysis_progress.dart` → **0 hits** (exit 1). A standalone repro ran under plain `dart run` (no Flutter), confirming pure-Dart.
- `rg "Dio|http|HttpClient|Socket|SecureStorage|SharedPreferences|KeyValueStore|analytics|logger|log(|print(|File(|Process."` over all 6 production files → **0 hits** (exit 1). No network, storage, log, analytics, or filesystem sink exists in this diff.
- `git diff --name-only main...HEAD` → only the 11 allowed files; **no** `pubspec.yaml` change (zero new dependencies → nil supply-chain surface), **no** touch of `lib/features/analyze/**`, `live/**`, `audio_analysis/data|presentation/**`.
- The only `static` member is `AnalysisPipeline._fatalFailure` — a pure function, **not** mutable state (§5.5 upheld). Fakes hold only instance fields.

**Consequence:** none of the five non-negotiable product boundaries (§5) are reachable in this diff — there is no audio/camera frame, no consent gate, no secret/token, no offline-degradation path, and no confidence surfaced to a user yet. The findings are contract-integrity seeds that become load-bearing when R07+ real stages and the R22 consumer wire in.

## Mandated checks — results

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Resource leak (stream/token close on every path) | **PASS** | All terminal paths funnel to one `finish()`; poll-based token has no listener to detach |
| 2 | Late-event isolation (run-ID) | **PASS** | Sole `publish` sink + per-run captured controller; residual is same-run integrity → Finding MINOR-1 |
| 3 | Error-data leak (`cause`/stacktrace) | **PASS in-diff** | `AppFailure.cause` never rendered/logged here → Finding NOTE-4 |
| 4 | DoS / unbounded wait / determinism | **Findings NOTE-2 + NOTE-3** | No stage timeout; monotonic gate self-fatals on legitimate same-phase sub-progress |
| 5 | Domain purity (no Flutter) | **PASS** | grep exit 1; repro ran under `dart run` |

**Check 1 detail (no leak):** `_execute` wraps everything in `try / on AnalysisCancelledException / catch`, and *every* exit — `complete`/`degraded` (`analysis_pipeline.dart:226`), non-degradable `failed` (`:203`), `cancelled` (`:233`), and outer-catch `UnknownFailure` (`:238`) — is a `return finish(...)`. `finish` (`:145-168`) always calls `unawaited(progressController.close())` (`:156`) and is invoked exactly once per run. It cannot throw before the close: the result-event `publish` at `:151` skips the monotonic check (result events aren't `AnalysisPhaseProgressEvent`) and the controller isn't yet closed. Cancellation is **poll-based** (`analysis_cancellation.dart`: a `bool _isCancelled` + `throwIfCancelled()`), so there is no stream listener, `Timer`, `Completer`, or subscription anywhere to leak. The cancel-matrix test asserts `isProgressClosed` on all four cells. **No leak path found.**

**Check 2 detail (isolation holds):** `publish` (`:129-143`) is the only sink; stages reach it exclusively through the `eventSink` closure — they never touch `progressController` or any static field. Each closure writes only its own captured controller, and drops any event whose `runId != _activeRunId` (`:130-133`). `_activeRunId` is null-guarded on finish (`if (_activeRunId == runId)`, `:157`) so a slow run#1 finishing after run#2 starts cannot clobber run#2's active id. The late-event test proves `droppedLateEvents == 2`. A cross-run leak is structurally impossible (a run's events can only ever reach its own captured controller).

## Findings

### MINOR-1 — A stage can inject a stage-chosen terminal result event onto the live progress stream (false-confidence seed)

- **Location:** `lib/features/audio_analysis/engine/analysis_context.dart:89-90` (`AnalysisStageContext.publishResult`) + `lib/features/audio_analysis/engine/analysis_pipeline.dart:129-143` (`publish` — result events bypass the monotonic gate).
- **Violated rule:** product-boundary §5.5 (weak/uncertain state must not surface as a certain statement) — *indirectly and latently*; contract-integrity of the terminal-event channel.
- **Failure scenario (reproduced):** A future in-process stage calls `context.publishResult(AnalysisCompletionStatus.complete)` during its own active run. It passes the run-ID gate (same run) and, because result events skip the phase-monotonic check, is `add`ed straight onto the live stream:
  ```
  stream event: AnalysisRunResultEvent(completion=complete)   <- injected by the stage, FIRST event
  stream event: AnalysisPhaseProgressEvent(phase=preparing)
  stream event: AnalysisRunResultEvent(completion=complete)   <- the pipeline's real one at finish()
  terminal result events on stream = 2
  ```
  The injected `AnalysisCompletionStatus` is a stage-controlled literal, fully decoupled from the pipeline's own `finish()` computation — so a stage can emit `complete` while the pipeline's actual outcome is `degraded`/`failed`/`cancelled`. An R22 consumer that treats a stream `AnalysisRunResultEvent` as the authoritative "done" signal would render a premature/false `complete` (potentially over an empty or degraded document).
- **Reachability / why MINOR not MAJOR:** `analysis_context.dart` is **not** exported by `public.dart`, so `publishResult` is reachable only by first-party stages inside the feature, not by untrusted input or cross-feature callers. No consumer exists yet, and **no stage in this round's diff calls it** (the fake stages only call `reportProgress`) — it is currently dead, speculative surface.
- **Fix direction:** make the pipeline the sole authority for terminal events — drop/deny stage-emitted `AnalysisRunResultEvent`s at `publish`, or remove `publishResult` from the stage-facing context entirely (if isolate-backed stages in R22 genuinely need it, tag pipeline-authoritative terminal events distinctly so a consumer can tell them apart).
- **Disposition (orchestrator, 2026-08-11):** deferred as a tracked follow-up rather than a same-round fix. Rationale: zero behavioral impact today (unused by every stage in this diff, not cross-feature-exported), and the correct fix is a design choice that belongs with whichever round first gives a stage a real reason to call it (R07 DSP wiring or R22 isolate consumer) rather than removing/redesigning speculative surface in a contract-only round. Tracked in `HANDOFF.md` §3 — **mandatory pre-flight check for R07**: either remove `publishResult` if still unused, or harden `publish()` to reject/flag stage-originated terminal events before any real stage is allowed to call it.

### NOTE-2 — Strict monotonic gate fatally rejects the intra-phase `completedUnits` sub-progress it is meant to carry (correctness-adjacent; availability)

- **Location:** `analysis_pipeline.dart:134-141` (strict `event.phase.index <= latestPhase.index` → `StateError`) vs. `domain/analysis_progress.dart:24-45` (`AnalysisPhaseProgressEvent` carries `completedUnits/totalUnits` for sub-work) + outer catch `analysis_pipeline.dart:237-243`.
- **Failure scenario (reproduced):** A stage reports intra-phase progress twice — `context.reportProgress(completedUnits: 1, totalUnits: 3)` then `(2, 3)` — the documented purpose of those fields (brief OD-01). The second event has the same phase index → `StateError('...strictly monotonic')` → caught by the outer handler → the *whole run* completes as `failed` with `UnknownFailure`.
- **Why NOTE, not MAJOR:** the pipeline is faithfully implementing the brief's own acceptance criterion #2 ("a publikált fázisok... szigorúan monoton fázisindexszel") literally, across every published event — this is a tension between that criterion and OD-01's `completedUnits/totalUnits` field, not a coding defect. No stage in this round exercises repeated same-phase reporting, so it is not caught by this round's own falsification matrix (§6.1 does not list this cell). Primarily a correctness/availability contradiction, not a security boundary breach.
- **Fix direction:** allow repeated same-phase events when they carry monotonically non-decreasing `completedUnits` (compare `<` on phase index, and enforce unit-monotonicity within a phase), or document that `completedUnits` is single-shot and drop the pair from the OD-01 default. Belongs to the first round that actually emits sub-phase progress.

### NOTE-3 — No timeout/backstop on `await stage.run(...)` (forward-looking DoS)

- **Location:** `analysis_pipeline.dart:184`.
- **Failure scenario:** cancellation is cooperative only; a future stage that hangs (or never calls `throwIfCancelled()`) makes the pipeline hang forever — the `result` Future never completes and the progress stream never closes, even if the caller cancels.
- **Why NOTE (accepted for a contract round):** the round deliberately chose a cooperative-token contract (brief §5.2) and deferred the isolate-runner to R22; fake stages don't hang. Track for the real-stage/isolate rounds to add a per-stage deadline or isolate-kill backstop.

### NOTE-4 — `UnknownFailure.cause` carries the raw stage error + stacktrace (safe in-diff)

- **Location:** `analysis_pipeline.dart:241` (`UnknownFailure(cause: error, stackTrace: stackTrace)`); convention in `core/foundation/app_failure.dart:91-100`.
- **Assessment:** the raw error object and stacktrace are retained on `AppFailure.cause`, which is diagnostic-only — `AppFailure.toString()` omits it and the pipeline never renders or logs it (no sink exists in this diff). The degradable-path warning (`analysis_pipeline.dart:209-219`) carries only `stageId` + the stable `failureCode`, never `cause`. **No leak in this round.** Forward-looking: a future consumer that reads and renders/logs `result.failure.cause` would leak a raw stage exception (which in R07+ could embed a file path or audio metadata) — the never-render convention is the only protection and must be preserved through the redacting logger when the pipeline is wired.

## Positive observations

- Run-IDs are synthetic sequential counters (`analysis-run-<n>`), **not** timestamps/UUIDs/device-ids — zero PII even if they ever reach provenance or logs; predictability is irrelevant since the run-ID is only an in-instance late-event filter, never an auth/correlation token.
- `AnalysisPipelineResult`, `stageOutputs`, `warnings`, and `unavailableCapabilities` are all wrapped `unmodifiable` (`analysis_pipeline.dart:39-43`); no `toJson`/`toString` override that could serialize the in-memory envelope.
- Duplicate/empty stage IDs and >9 stages fail closed at construction with `ArgumentError` (`analysis_pipeline.dart:65-79`) — no silent "last wins."
- `public.dart` widens only by `domain/analysis_progress.dart` (runId + phase enum + int units — no sensitive types) and `engine/analysis_cancellation.dart`; the engine implementation (`pipeline`/`context`/`stage`) stays feature-private.

## Verdict

**PASS.** No CRITICAL, BLOCKER, or MAJOR finding. No secret/token/audio/camera egress, no consent bypass, no path traversal/RCE, no network or storage sink, no new dependency, domain purity intact, and every stream/token path releases deterministically. The single MINOR and three NOTEs are latent seeds to carry into the wiring rounds (MINOR-1 → mandatory R07 pre-flight check; NOTE-2 → first real sub-progress-emitting round; NOTE-3 → R22 isolate-runner; NOTE-4 → when a logger/UI first reads `failure.cause`). Merge is not blocked on security grounds.
