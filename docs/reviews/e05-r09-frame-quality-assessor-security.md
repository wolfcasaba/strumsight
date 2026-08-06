# E05-R09 — Security &amp; Privacy Review

Brief: `docs/rounds/e05-r09-frame-quality-assessor.md`
Branch: `codex/e05-r09-frame-quality-assessor` @ `3671358`
Base: `origin/main` @ `e16c02c`
Reviewer: security-reviewer agent (read-only) · Dátum: 2026-08-06
Trigger: brief `ai-router` block declares `risk = "high"` → dedicated security review mechanically required.
Method: full read of the 10-file diff; import/danger-grep of the four new domain files + both tests + both fixtures; confirmation the imported transitive types (`camera_coordinate_space.dart`, `vision_setup_profile.dart`) are pure Dart; `public.dart` additive-only diff check; scope audit against brief §4; secret/PII scan of added diff lines and fixtures; and — because this is a model-free *safety* layer whose whole job is to avoid false certainty — **direct execution of the real round code** as a standalone pure-Dart harness under both `--enable-asserts` (test-mode) and `--no-enable-asserts` (release-mode) to prove the §5.6 numeric guard and to probe degenerate-input paths the assert-on test suite cannot reach.

**Verdikt: PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR. 2 MINOR (reproduced, release-only, defense-in-depth; no in-scope caller) + 4 NOTE (all non-blocking).

## Severity table

| # | Severity | File:line | One-line |
|---|---|---|---|
| F1 | MINOR (defense-in-depth, reproduced) | `frame_quality_assessor.dart:66,93-97,196-197`; `quality_thresholds.dart:78-79` | Non-finite ROI coordinate → `roiCoverage = good` (false certainty). Numeric field correctly zeroed (§5.6 holds); state enum wrong. Only reachable with asserts stripped (release); tests can't cover it. |
| F2 | MINOR (robustness/DoS-on-misconfig, reproduced) | `frame_quality_assessor.dart:144-145,156-157`; `quality_thresholds.dart:22` | Runtime `downsampleFactor <= 0` → non-terminating downsample/sharpness loop = frozen thread. `const` default path is compile-time-safe. |
| N1 | NOTE (privacy-neutral, reviewed) | `frame_quality_assessor.dart:37,106,124` | In-RAM previous-frame retention for motion delta; transient, reset on degenerate, never egressed. |
| N2 | NOTE (test infra) | `frame_quality_benchmark.dart:1,42` | `dart:io` = `stderr.writeln` only; not shipped. |
| N3 | NOTE (error hygiene) | `vision_frame_quality.dart:40-47` | Error text leaks only the config version string, never pixels/PII. |
| N4 | NOTE (contract) | `public.dart:8` | `show NormalizedRect` re-export; minimal, additive, no core edit. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --name-status origin/main...HEAD` = exactly 10 files, each on the brief §4 `allowed_paths`: 4 new domain files (`quality/{frame_quality_assessor,quality_thresholds,vision_frame_quality,vision_quality_summary}.dart`), additive `lib/features/vision/public.dart`, 2 tests (`test/features/vision/domain/*`), 2 fixtures under `test/fixtures/vision/quality/` (`README.md`, `frame_quality_benchmark.dart`), and the round brief. `pubspec*` untouched (no new dependency); no binary/image/asset added (git numstat: 0 binary blobs; no image-extension files); no native manifest/gradle/podspec change.

## Non-negotiable product boundaries (AGENTS.md §5 / brief §3,§5) — all honored

- **§5.1 Raw camera frame never leaves the device / not persisted:** No network surface exists in the layer. Danger-grep across all new files for `http|dio|Socket|WebSocket|HttpClient|MethodChannel|EventChannel|Supabase|dart:ffi` → **empty** (the only `platform`/`dart:io` hits are a doc comment at `frame_quality_assessor.dart:10-12` and `stderr.writeln` in the non-shipped benchmark). Input is a caller-supplied downsampled luminance plane (`GrayscaleFrame`); it is defensively copied (`:18`) and only aggregate statistics leave the layer. The one retained buffer (`_previousSamples`, `:37`) is in-RAM, transient, and nulled on every degenerate frame (`:46,52,124`). No `File`/`openWrite`/`path_provider`/`SharedPreferences`/`SecureStore` — nothing is written to disk.
- **§5.2 Logged-out / diagnostics-off → no hidden network:** Zero network/IO added; the layer is pure computation.
- **§5.3 No secret/token/raw-frame in logs, signals, errors, commits:** No `print`/`log`/`debugPrint`/analytics anywhere. The only error path (`vision_frame_quality.dart:40-47`) emits `ArgumentError.value(thresholdsVersion, ...)` — a config version string (e.g. `vision-frame-quality-v1`), never pixel/PII data. The six public `measurements` (`:64-71`) are frame-level aggregate scalars (mean luminance, clip ratios, sharpness, motion, coverage), not reconstructible to an image. Secret-pattern scan of added diff lines (`api_key|secret|token|password|BEGIN … KEY|AKIA|ghp_|eyJ…|base64 blobs`) → **0 hits** (the single match is doc text naming the `check_secrets.dart` scanner). Fixtures are 100% synthetic in-memory generators (`_checkerboard`, `_softGradient`, `List.generate`); `README.md:3-4` affirms "No camera image, identity, or personal data is checked in" — semantically a genuine fake, no real photo/frame checked in.
- **§5.4 Cloud/community must not degrade offline base:** N/A — fully offline, no cloud/community feature.
- **§5.5 Weak confidence not shown as certain:** Enforced structurally — degenerate/empty/constant input → `notObservable` (proven below), and `hasTechnicalFeedback => overall == good` (`vision_frame_quality.dart:73`) gates technical feedback to the all-good state; `_overall` fails closed (any `notObservable` → `notObservable`; any `needsImprovement` → `needsImprovement`; `:199-221`). The one residual edge is F1 (non-finite ROI → `roiCoverage=good`), reproduced and classified MINOR because the *surfaced* cue in that scenario is still the safe `adjustFraming` (see F1).

## Brief mandatory guarantees — evidence

**§5.6 NaN/Infinity never escapes the model — PROVEN.** All six numeric fields pass through `_finiteOrZero(v) => v.isFinite ? v : 0` at the sole construction site (`vision_frame_quality.dart:34-39,75`); `double.isFinite` is false for NaN/±Infinity, so non-finite inputs become `0.0`. Reproduced by executing the real type with poisoned inputs:
`dart run evidence.dart` →
`(1) finite-guard measurements=[0.0, 0.0, 0.0, 0.0, 0.0, 0.0] allFinite=true` (inputs were `NaN`, `+Inf`, `-Inf`, `NaN`, `+Inf`, `NaN`).

**Degenerate frame → explicit `notObservable`, not `double.nan` — PROVEN.** 0-size and constant frames short-circuit to `_notObservable()` before any division (`frame_quality_assessor.dart:44-53,126-140`); the constant-image guard is `_isConstant` (`:184-185`). Reproduced:
`(2) degenerate overall=VisionMetricState.notObservable lighting=VisionLighting.notObservable allFinite=true`
`(3) constant overall=VisionMetricState.notObservable allFinite=true`.
No false stability across an observability gap: `_previousSamples` is reset on every degenerate frame, so the next `_cameraMotion` returns `null` → `stability=notObservable` (matches the handoff's RED→GREEN and the test at `frame_quality_assessor_test.dart:180-205`).

**Deterministic, total-order, exactly-one cue (§5.3) — PROVEN.** `_cue` is a fixed if-chain framing → lighting → blur → stability → roiCoverage → notObservable → none (`vision_quality_summary.dart:96-124`); no map-iteration or randomness. Reproduced with an all-failures frame:
`(7) all-bad cue run1=VisionSetupCue.adjustFraming run2=VisionSetupCue.adjustFraming exactlyOne=1`.

**Threshold "below / exactly-on / above" matrix.** Present for all six thresholds as numeric asserts (`frame_quality_assessor_test.dart:81-130`), computed values not eyeballed. Boundary semantics verified against code (`quality_thresholds.dart:60-79`): strict `<`/`>` on the limits, so "exactly on" resolves as documented.

## Findings (F-format)

### F1 — MINOR (defense-in-depth, reproduced) — Non-finite ROI coordinate yields a false `roiCoverage = good`
- **Fájl:** `frame_quality_assessor.dart:66` (`roiCoverageRatio = roi == null ? 0.0 : _area(roi)`), `:93-97` (roiCoverage state), `:196-197` (`_area`); `quality_thresholds.dart:78-79`; ROI validation at `camera_coordinate_space.dart:224-225`.
- **Failure scenario:** A future runtime caller (landmark/calibration in R12+, UI in R24) builds a `NormalizedRect` whose coordinates are computed and — through an upstream numerical error — contain `NaN`/`Infinity`. `NormalizedRect`'s bounds validation is `assert(...)`, which is **stripped in a release APK** (the project's real acceptance gate), so the rect constructs. `_area` returns `NaN`. The output field `roiCoverageRatio` is correctly zeroed by `_finiteOrZero` (§5.6 numeric guarantee holds), **but** the derived state `roiCoverage` = `good` because `hasInsufficientRoiCoverage(NaN)` = `NaN < min` = `false` — Dart/IEEE754 evaluates every `<`/`>`/`<=`/`>=` comparison against NaN as `false`, so the "insufficient" check silently fails open into the "good" branch. `framing` does not share this failure mode: it uses `roiCoverageRatio >= min`, which is *also* false for NaN, but that lands on the safe (`needsImprovement`) side of that particular ternary.
- **Reproduction:** `dart --no-enable-asserts run evidence.dart` (release simulation) → `(5) NormalizedRect(NaN) CONSTRUCTED` and `(4) hasInsufficientRoiCoverage(NaN)=false (=> roiCoverage GOOD); framing NaN>=min => false`. Under test-mode `dart --enable-asserts run` → `(5) NormalizedRect(NaN) threw _AssertionError` — i.e. **the test suite structurally cannot exercise this path.**
- **Hatás:** A public exported field (`VisionFrameQuality.roiCoverage`) asserts "coverage good" from non-finite input — a false-certainty state in a layer whose purpose is to avoid exactly that (§5.5). Muting factors: the *surfaced* cue in this scenario stays safe (`framing` → `needsImprovement` → cue `adjustFraming`, and `overall` → `needsImprovement` → `hasTechnicalFeedback=false`), so a direct reader of `roiCoverage` is the only consumer misled. Not a §5.6 violation (numeric output is finite); no in-scope caller triggers it today.
- **Javasolt javítás iránya:** In `assess`, treat a non-finite `_area(roi)` as `notObservable` (or clamp coverage into `[0,1]` before state derivation) so `roiCoverage` never reads `good` from a non-finite input — independent of asserts.
- **Ellenőrzés:** add a test constructing the assessor with a runtime (non-const) NaN-coord ROI via a release-mode/no-assert harness (or clamp at the numeric boundary and assert `roiCoverage == notObservable`).
- **Státusz:** OPEN (non-blocking; recommend fixing before a runtime ROI producer lands in R12+/R24).

### F2 — MINOR (robustness / DoS-on-misconfig, reproduced) — Runtime `downsampleFactor <= 0` hangs `assess()`
- **Fájl:** `frame_quality_assessor.dart:144-145` (`for (var y = 0; y < frame.height; y += thresholds.downsampleFactor)`) and `:156-157` (sharpness loop); config guard `quality_thresholds.dart:22` (`assert(downsampleFactor > 0)`).
- **Failure scenario:** A caller constructs a `QualityThresholds` at runtime (non-const — e.g. from a computed/remote value) with `downsampleFactor == 0`. In a release APK the `assert` is stripped, so it constructs; `assess()`'s loop advances by `0` and never terminates — the analysis/UI thread freezes.
- **Reproduction:** `dart --no-enable-asserts run hang_probe.dart` with `downsampleFactor: int.parse('0')` → process killed by `timeout` (exit 124 = non-terminating). Test-mode `dart --enable-asserts run evidence.dart` → `(6) QualityThresholds(downsampleFactor:0) threw _AssertionError`. Note: `const QualityThresholds(downsampleFactor: 0)` fails at **compile time** (const-eval runs the assert), so the `defaultV1()` (factor 4) and any const config are safe — only a non-const runtime value is dangerous.
- **Hatás:** Availability (frozen frame loop). No data/privacy/boundary impact. Lower likelihood than F1 because thresholds are developer-authored config, usually const.
- **Javasolt javítás iránya:** Hard runtime guard at use or construction (`if (downsampleFactor <= 0) …` clamp/throw) not reliant on `assert`.
- **Ellenőrzés:** a no-assert harness test that a non-const `downsampleFactor <= 0` either throws deterministically or is clamped, and `assess()` returns.
- **Státusz:** OPEN (non-blocking).

### N1–N4 — NOTE (non-blocking)
- **N1 — in-RAM previous-frame retention** (`frame_quality_assessor.dart:37,106,124`): the downsampled luminance of one prior frame is held for the motion delta, reset on every degenerate frame and via `reset()`; never persisted, logged, or transmitted. This is inherent to a motion metric and is **not** the "raw-frame persistence" brief §3 forbids. Reviewed, acceptable.
- **N2 — benchmark `dart:io`** (`frame_quality_benchmark.dart:1,42`): used only for `stderr.writeln`; lives under `test/fixtures/**`, not compiled into the release bundle. Acceptable.
- **N3 — error text** (`vision_frame_quality.dart:40-47`): leaks only the config version string, never pixel/PII.
- **N4 — `public.dart` re-export** (`:8`): `export '../../core/camera/camera_coordinate_space.dart' show NormalizedRect;` — minimal surface, additive, no core file modified.

## AI-provider / prompt-injection (ADR 0131–0136) — N/A, verified

This layer introduces **no** LLM/provider call, tool-calling, knowledge-base retrieval, or prompt construction — it is pure numeric computation over a luminance plane. Danger-grep confirms no provider/network/tool surface added. External content (the luminance bytes) is consumed strictly as **data** (array indexing + arithmetic), never interpreted as instructions. Nothing to assess for injection, allowlists, or consent-to-provider. Confirmed no such surface was smuggled in.

## OWASP-relevant spot-checks

- **Memory-safety / out-of-bounds:** `isWellFormed` guarantees `luminance.length >= width*height` (`:24-25`); loop indices are bounded (`_downsample :144-146`, `_sharpness :159,164`), so worst case is a `RangeError` throw, not an over-read/info-leak. No `dart:ffi`/native pointer.
- **Injection / unsafe interpolation:** none — no SQL/shell/eval; no string interpolation of external data.
- **Insecure storage / secrets:** no storage used (nothing sensitive to persist); no token/key/secret in code or fixtures.
- **Fail-closed defaults:** degenerate/empty/constant → `notObservable`; unavailable evidence never upgraded to technical feedback (`hasTechnicalFeedback` gate). The two exceptions (F1/F2) are the release-only assert-stripped paths above.
- **Supply chain:** no `pubspec`/asset/native change — no new dependency, permission, or asset provenance to review.
- **`public.dart` contract:** diff is 5 pure additions, 0 deletions/edits to existing exports — additive-only confirmed.

## What was verified clean (summary)

Scope = exactly the 10 declared files, all within `allowed_paths`; `public.dart` additive-only; no new dependency/asset/permission/native surface. No network/IO/secure-store/secret/AI-provider surface introduced. Fixtures are synthetic in-memory generators (no real photo/frame/PII). The §5.6 finite guard, degenerate→`notObservable`, no-false-stability-across-gaps, deterministic exactly-one cue, and the no-technical-feedback-on-unavailable rule are each proven by executing the real round code. Tests genuinely gate behavior (numeric threshold-boundary asserts, degenerate finite-measurement assert, cross-observability motion reset, complete cue-priority + same-severity determinism) — not incidental passes.

## Merge-döntés

Per ADR 0052 / brief §11: every gate green AND zero OPEN BLOCKER/MAJOR → merge. This review adds **0 BLOCKER, 0 MAJOR**. The 2 MINORs are release-only, reproduced, defense-in-depth robustness gaps with no in-scope caller (they become live when R12+/R24 wire a runtime ROI producer / non-const config) and the assert-on suite structurally cannot cover them — recommend addressing before those callers land, but they do **not** block this merge. **Security review: PASS.**
