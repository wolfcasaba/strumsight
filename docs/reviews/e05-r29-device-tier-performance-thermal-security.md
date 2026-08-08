# E05-R29 — Device tier, performance & thermal hardening — Security/Privacy Review

- **Reviewer:** Claude (dedicated security/privacy reviewer, read-only)
- **Round:** E05-R29 · branch `codex/e05-r29-device-tier-performance-thermal`
- **Base:** `origin/main` @ `9b9dccc9` · **pre-flight docs commit** `216adfef` · **Head:** `afc49557`
- **Router declaration:** `risk = "high"`, `native_gate = false` — reviewed with full rigor regardless of the low intrinsic surface.
- **Method:** static semantic review + measured greps (import graph, sink scan, consumer scan, full-round native/manifest scan). Did not re-run `flutter analyze`/`flutter test` (OOM-prone on this box per CLAUDE.md L05; the exact-SHA green gate is documented in brief §10 and CI is the machine authority per ADR 0053) — the independent code-review pass separately re-ran the full gate in an isolated clone.

## Verdict: **PASS**

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 0 |
| NOTE | 3 (all forward-looking; none blocks merge) |

No secret leak, no consent bypass, no path-traversal/RCE, and no non-negotiable product-boundary (AGENTS.md §5) violation is reproducible in this diff. The three NOTEs are advisory for the future consumer-wiring round and are not findings against this round.

## Scope reviewed

11 files in `216adfef..afc49557` (impl) + the pre-flight ADR/brief in `9b9dccc9..216adfef`. Five new production files under `lib/features/vision/{domain,application,data}/performance/`, 5 additive lines in `lib/features/vision/public.dart`, 3 new test files, 2 PENDING rows in `docs/manual-testing/vision-performance-benchmark.md`, the brief, and new ADR 0196.

## Findings

None at CRITICAL / BLOCKER / MAJOR / MINOR.

## Evidence of checks (empty-report-is-evidence)

**Check 1 — No raw sensor/biometric capture — PASS.** Every field of `VisionPerformanceSummary` (`vision_performance_summary.dart` ~L98–133) is an aggregate: `tier` (`VisionDeviceTier?`), `appliedSteps` (`List<VisionDegradationStep>`), `droppedFrameRatio` (`double`), `freshness` (`VisionFreshnessDistribution` = 3 ints), `degradationTimestamps` (`List<Duration>` — relative), `thermalSource` (enum), `isAvailable` (bool), `unavailableReason` (`String?`). `VisionPerformanceMonitor` (~L40–95) stores only counters + freshness aggregates; `recordProcessedFrame({required int freshnessMs})` takes an `int`, not a frame; `recordDroppedFrame()` only increments. The single transitive external type, `VisionDeviceTier`, is `enum { basic, mid, flagship }` (`data/landmarks/hand_landmark_provider.dart:125`) — zero coordinates/pixels/IDs. Grep for `model|deviceName|manufacturer|serial|imei|androidId|identifierForVendor` across all new perf code returned only a code *comment* stating the input is "a measured processing time, not a device make or model." Consistent with the ADR 0178/0183 privacy-by-default pattern.

**Check 2 — No network/storage reach — PASS.** Authoritative import scan of all 5 new files: they reach only `hand_landmark_provider.dart show VisionDeviceTier` plus each other. No `dart:io`, `dio`, `http`, `KeyValueStore`, `SharedPreferences`, `SecureStorage`, `File`, `Directory`, `MethodChannel`, `Platform.`. No serialization/logging sink exists (see Check 6 method). No `pubspec.yaml` change in the full round diff.

**Check 3 — No new plugin/permission surface — PASS.** `git diff --name-only 9b9dccc9..afc49557 | grep -Ei 'android/|ios/|pubspec|gradle|plist|Manifest|\.kt|\.java|\.swift|native'` → NONE. `native_gate = false` upheld. `ThermalStateAdapter` deliberately makes no platform-plugin call (ADR 0196 Döntés 6); its platform branch is dead this round and always falls to the heuristic.

**Check 4 — Barrel export safety — PASS (pre-existing wide-barrel risk untouched).** The 5 new export lines (`public.dart:4,5,40,57,58`) point only to the new perf files, which carry aggregates + the already-public `VisionDeviceTier`. The new files use `import … show VisionDeviceTier`; **imports are not re-exported**, so no new raw landmark/geometry/pixel type enters the surface. `hand_landmark_provider.dart` (defining `VisionDeviceTier`) is already fully exported at `public.dart:64`, so value-exposing that enum adds nothing. The known wide-barrel exposure (L190 / e05-r26-…-security MINOR-1: raw landmarks at `public.dart:26–32`, providers at `:64–69`, `NormalizedPoint/Rect` at `:70–71`) is **not touched and not worsened**. Because this round's own code uses only aggregate types and there is no demonstrated data-in-output leak, this is not even a MINOR this round.

**Check 5 — Determinism / no hidden side channels — PASS.** No `DateTime.now()`, `Random`, `Timer`, `Stopwatch`, `clock`, or global mutable state in any new file. `VisionDegradationPolicy.decide()` (`vision_degradation_policy.dart`) is a pure function of `(currentStep, snapshot)`; the class is `const`; caller owns the step state (the hysteresis test threads it externally). `VisionDeviceTierClassifier.classify()`, `DeviceTierBenchmark.evaluate()`, and `ThermalStateAdapter.evaluate()` are pure — determinism is explicitly asserted in tests (`classify(input) == classify(input)`; adapter `first == second`). `VisionPerformanceMonitor` is stateful but caller-owned/session-local, not static/global.

**Check 6 — Secrets/credentials — PASS.** Diff scan for `apiKey|token|secret|password|Bearer|Authorization|credential|private_key|BEGIN` → none. No fixtures with key-like content (the new code contains only numeric thresholds, e.g. 33/66 ms, FPS ints). Sink scan `grep -nE 'toJson|toMap|toAuditMap|serialize|toString|print\(|debugPrint|developer\.log|log\(|stderr|stdout|part '` over the 5 files → NONE, so there is no channel that could emit a secret or aggregate. The manual-testing doc adds 2 PENDING soak rows naming target devices "Pixel 6a" / "Samsung Galaxy A54" — these are hand-authored test-plan *target* devices in a planning doc, not runtime-captured identifiers and not in any code path; benign.

**Check 7 — Prompt-injection / untrusted-input surface — PASS (confirmed N/A, not assumed).** No import of any AI/provider/LLM module, no `Dio`/HTTP, no user-authored text. The only free-form strings (`unavailableReason` on `VisionPerformanceSummary` and `DeviceTierBenchmarkResult`) are fed only fixed constants in-round (`'benchmark-failed'`, `'invalid-frame-processing-time'`) and flow to no sink. No user-facing string interpolation into a sensitive sink exists.

**Product boundaries (AGENTS.md §5):** (1) nothing leaves the device — no network at all, and no frame is even retained; (2) no hidden network request in any state — no network code; (3) nothing reaches a log/signal/error/commit — no logging/serialization, error strings are fixed constants; (4) offline base experience preserved — the unsupported-device path yields `VisionPerformanceSummary.unavailable` and explicitly keeps the rest of the app unchanged (ADR 0196 §6); (5) weak confidence not shown as certain — nothing is surfaced (unwired), and `thermalSource` is deliberately labeled `platform` vs `heuristic` precisely so a future consumer cannot present a heuristic guess as an authoritative platform reading (§5.5-positive design).

## NOTES (forward-looking; not merge-blocking)

- **NOTE-1 — free-form `unavailableReason` strings.** `VisionPerformanceSummary.unavailable(String)` (`vision_performance_summary.dart:118`) and `DeviceTierBenchmarkResult.unavailable(String)` are unbounded `String?`. In-round they carry only fixed constants and reach no sink. When the consumer-wiring round adds a real benchmark runner / exception handling, avoid piping `e.toString()`, a file path, or device info into these, especially if the summary ever becomes serialized or logged. No sink exists today → NOTE only.
- **NOTE-2 — assert-guarded input DTOs (release-strip).** `VisionPerformanceSnapshot`, `VisionThermalHeuristicInput`, `VisionThermalDecision`, and `VisionFreshnessDistribution` validate ranges via `assert` (stripped in release). This is **not** a security issue here: every invariant-critical/boundary validation uses a real `throw ArgumentError` — classifier on `<= 0` (`vision_device_tier.dart`), monitor on negative freshness, `VisionPerformanceSummary.available` on ratio outside `[0,1]`, adapter on platform-load outside `0..100` — and the heuristic `.clamp(0,100)`s load at runtime regardless of asserts. A degenerate fps in the policy switch fails **safe** (maps to a more-severe degrade step; never leaks, never surfaces false confidence). Flagging only so the consumer round keeps runtime guards on any value that becomes user-visible (§5.5).
- **NOTE-3 — domain→data import (architecture, not security).** `domain/performance/{vision_device_tier,vision_performance_summary}.dart` import from `data/landmarks/hand_landmark_provider.dart`. ADR 0196 Kontextus 2 measured that this violates no machine architecture rule (`sharedDomainMustRemainFrameworkIndependent` scopes only `core/music/`, `core/audio/codec/`, `features/practice/domain/` — not `vision/domain/`) and follows the `pose_landmark_provider.dart:17-18` precedent. Narrowed by `show VisionDeviceTier` (a data-free enum) → no transitive raw-media exposure. Intentional and documented; noted only for the correctness/architecture reviewer's completeness (see also the independent code review's F3, same observation from the architecture angle).

## Independent-verification checklist

The five new production files import only the coordinate-free `VisionDeviceTier` enum + each other; there are zero external consumers (new types are not referenced outside the round's own files); no serialization/log/network sink exists; the full round adds no `android/`/`ios/`/`pubspec`/native file; the barrel additions do not widen the raw-media surface. Merge is unblocked from a security/privacy standpoint under the unchanged ADR 0052 green gate + exact-SHA CI.

## Merge-döntés (security lens)

**PASS.** No CRITICAL/BLOCKER/MAJOR/MINOR. Nothing in this round changes the app's network, storage, permission, or logging surface — it is a pure in-memory domain/application addition, currently unwired to any real consumer. Combined with the independent code review's APPROVED verdict, there is no security objection to merge once CI is green on the final pushed SHA.
