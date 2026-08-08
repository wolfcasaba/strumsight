# E05-R29 — Review

Brief: `docs/rounds/e05-r29-device-tier-performance-thermal.md` (§0.0 pre-flight
revision read as authoritative over §1/§3/§5's original batch text where they
conflict)
Diff: full branch `git diff 9b9dccc9...afc49557` (pre-flight `216adfef` +
implementer `afc49557`); pre-flight-only `git diff 9b9dccc9...216adfef`;
implementer-only `git diff 216adfef...afc49557`
ADR: `docs/adr/0196-vision-device-tier-performance-and-thermal-contract.md`
Reviewer: Claude Sonnet 5 (independent reviewer) · Dátum: 2026-08-08
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 4

Independent re-verification performed in **two** isolated `/tmp` clones,
neither the shared `/home/ubuntu/ss-terra-e05-r29` implementer workdir:
`/tmp/review-e05-r29` (clean clone of the round branch, used for the gate
re-run) and `/tmp/review-e05-r29-mutate` (a second clone, used for reviewer
mutation/adversarial probes so they could not race the gate run). Both clones
were built from `afc49557` (the implementer's HEAD, at review time still
unpushed to `origin` — confirmed via `git status` on the implementer's own
workdir: "ahead of origin by 1 commit"), so the review measured the actual
deliverable, not a stale pre-flight-only ref.

Every claim in brief §10 "Implementation handoff" was independently
re-measured rather than trusted:

- **Gate**: re-ran `tools/round-gate.sh --result-json ... test/features/vision`
  myself, as one supervised process (no `&&`/pipe/`tail`) → `exit_code: 0`,
  all six steps green, **580/580** tests in `test/features/vision` passed
  (the round's own 26 new tests confirmed by name in the log, zero `[E]`
  markers).
- **Tier boundaries**: recomputed independently with `python3 -c` — exact
  match to the classifier and to the test file's asserted values.
- **7-stage entry thresholds**: cross-checked byte-for-byte against
  `docs/manual-testing/vision-performance-benchmark.md` §2.7 — exact match
  (12/10/5/8/6/4 FPS, 15 ms audio-latency).
- **Mutation test**: reproduced the implementer's self-reported probe myself
  (mutated `_requiredStep` so any FPS violation jumps straight to
  `visionDisabled`) in the second isolated clone → **11 failures**, exactly
  matching the brief's self-reported count → reverted via `git checkout --`,
  confirmed clean.
- **Hysteresis / anti-oscillation**: wrote and ran my own throwaway test
  (documented below, deleted before concluding) driving a
  degrade→dead-band-hold→degrade-again cycle across the overlay threshold,
  and a second test attempting to recover from `visionDisabled` to `none` in
  one `decide()` call. Both passed against the unmodified implementation.
- **Scope**: `git diff --stat` of the full branch range against the brief's
  current `allowed_paths` — clean, see below.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Tier-mátrix: alatt/rajta/fölött a 33/66 ms határokon, determinisztikus, `python3 -c` a §10-ben | ✅ | `lib/features/vision/domain/performance/vision_device_tier.dart:50-69` (`<=33→flagship`, `<=66→mid`, else `basic`); `test/features/vision/domain/vision_device_tier_test.dart:11-31` asserts 33→flagship, 34→mid, 66→mid, 67→basic. Reviewer-independent `python3` recomputation matches exactly (33→flagship, 34→mid, 66→mid, 67→basic; also checked -1/0→invalid, 1→flagship as extra edges). Determinism test present (`vision_device_tier_test.dart:33-37`). |
| 2 | Degradációs lépcső-mátrix: **7** lépcső × belépés/kilépés, belépés §2.7-ből újrafelhasznált, legenyhébb-elegendő, hiszterézis, korlátos állapotváltás-szám | ✅ | Entry constants `lib/features/vision/application/vision_degradation_policy.dart:48-54` (12/10/5/8/6/4 FPS, 15 ms) match `docs/manual-testing/vision-performance-benchmark.md` §2.7 exactly. Exit constants (13/11/6/9/7/5 FPS, 12 ms) give the documented 1-FPS / 3-ms margins (lines 56-64). Entry-matrix test (7 cases incl. a genuine 6-rung single-call jump for `handFPS=3`, `vision_degradation_policy_test.dart:8-50`) + per-stage single-step-exit test (7 cases, `:111-154`) + reviewer mutation probe (11/17 tests red when severity-matching is broken, reverted). Reviewer's own throwaway dead-band test: 10 repeated boundary-hovering calls held at one step, no flap. |
| 3 | Audio-elsőbbség teszt: romló audio-deadline → vision lépcsőz, audio-oldali paraméterek változatlanok, assert a konfiguráción | ⚠️ (satisfied but weak — see F1) | `vision_degradation_policy_test.dart:65-78` calls `decide()` and re-asserts `snapshot.audioProcessingLatencyIncreaseMs == 15`. Passes, but see F1: given `VisionPerformanceSnapshot` is an immutable value type and `decide()` is a pure stateless function, this assertion is close to tautological. Not a defect — real audio-pipeline wiring is explicitly out of this round's scope (ADR 0196 Döntés 5) and confirmed zero-touched (see Scope-audit). |
| 4 | Thermal-forrás teszt: platform elérhető/nem elérhető, mindkét ág, forrás jelölve | ✅ | `lib/features/vision/data/performance/thermal_state_adapter.dart:44-79`; tests `thermal_state_adapter_test.dart:29-46` (`uses a platform thermal state when one is supplied` → `source=platform,load=80`; `falls back to a deterministic performance heuristic` → `source=heuristic`, deterministic, `load ∈ [0,100]`). Reviewer confirmed the heuristic is *mathematically* bounded (each of the three weighted terms is individually clamped before summing: 40+30+30=100 max), not just clamped defensively. |
| 5 | Freshness/dropped monitor: szintetikus terhelésen helyes, assertált számlálók | ✅ | `lib/features/vision/domain/performance/vision_performance_summary.dart:39-90`; test `vision_device_tier_test.dart:71-84` asserts `processedFrameCount=2, droppedFrameCount=2, droppedFrameRatio=0.5, freshness=(10,20,30)`. Reviewer verified the `VisionFreshnessDistribution` constructor's `averageMs>=minimumMs && averageMs<=maximumMs` assert is mathematically guaranteed to hold for any input the monitor can produce (mean of a bounded integer set is always within [min,max] even under Dart's truncating `~/`), i.e. not just incidentally true for the one tested fixture. |
| 6 | Unsupported-eszköz teszt: benchmark-hiba → `unavailable`, többi feature érintetlen | ✅ (second half vacuous) | `lib/features/vision/data/performance/device_tier_benchmark.dart:35-51` catches `ArgumentError` narrowly (not a bare catch) and converts to `DeviceTierBenchmarkResult.unavailable('invalid-frame-processing-time')`; test `thermal_state_adapter_test.dart:10-17`. "Rest of the app unaffected" is vacuously true this round: zero callers/wiring exist yet (confirmed by scope-audit and by brief §10's own "Eltérések" section: "A landmark providerek és az audio pipeline nem lettek módosítva vagy huzalozva"). Nothing to break. |
| 7 | Valódi-sértés próba (§10): lépcső-átugrás → lépcső-mátrix PIROS → visszaállítás | ✅ | **Independently reproduced by the reviewer**, not merely trusted from the brief's self-report. Mutated `_requiredStep` (added an unconditional `handFPS < 12 → visionDisabled` short-circuit) in `/tmp/review-e05-r29-mutate`, ran `flutter test test/features/vision/application/vision_degradation_policy_test.dart` → **11 of 17 tests failed** (matches the brief's self-reported "11 hibával piros lett" exactly), reverted with `git checkout --`, confirmed `git status --porcelain` empty. |
| 8 | Benchmark-dokumentum: 10 és 30 perces soak sorok PENDING, eszközzel, mérendő számmal | ✅ | `git diff 216adfef...afc49557 -- docs/manual-testing/vision-performance-benchmark.md` shows exactly **2 added lines** (10 min / Pixel 6a, 30 min / Samsung Galaxy A54, both `PENDING`); the pre-existing 15-minute soak row is untouched context, not modified. |

## Scope-audit

`git diff --stat 9b9dccc9...afc49557` (full branch, both the reviewer's-orchestrator's
pre-flight commit `216adfef` and the implementer's `afc49557`) touches exactly
these 12 files, **all** inside the brief's current `allowed_paths` (which
already includes the ADR path added during pre-flight):

```
docs/adr/0196-vision-device-tier-performance-and-thermal-contract.md   (pre-flight only)
docs/manual-testing/vision-performance-benchmark.md
docs/rounds/e05-r29-device-tier-performance-thermal.md
lib/features/vision/application/vision_degradation_policy.dart
lib/features/vision/data/performance/device_tier_benchmark.dart
lib/features/vision/data/performance/thermal_state_adapter.dart
lib/features/vision/domain/performance/vision_device_tier.dart
lib/features/vision/domain/performance/vision_performance_summary.dart
lib/features/vision/public.dart
test/features/vision/application/vision_degradation_policy_test.dart
test/features/vision/data/thermal_state_adapter_test.dart
test/features/vision/domain/vision_device_tier_test.dart
```

Engedélyezett fájlokon kívüli változás: **nincs**.

Additional confirmations:

- `git diff --stat 216adfef...afc49557 -- docs/adr/0196-...md` is **empty** —
  the implementer's commit did not touch the ADR (pre-flight-only, as
  required).
- `git diff 9b9dccc9...afc49557 -- lib/core/audio/` is **empty**, and no
  DSP-named file appears anywhere in `git diff --stat` — the audio-priority
  "no audio pipeline touch" constraint holds across the whole branch, not
  just the implementer's commit.
- `pubspec.yaml`/`pubspec.lock` untouched, and grep for
  `thermal|battery|device_info` in `pubspec.yaml` returns nothing — the
  `ThermalStateAdapter` platform branch is genuinely unreachable except via
  injected/fake input in this round, as ADR 0196 Döntés 6 requires.
- `VisionDeviceTier` is defined **exactly once** in `lib/`
  (`hand_landmark_provider.dart:125`, unchanged, confirmed byte-identical to
  origin/main); `VisionDegradationStep` is defined **exactly once**
  (`vision_performance_summary.dart:5`). No parallel/duplicate type. `flutter
  analyze` confirms clean (0 issues) — the ambiguous-export risk the ADR
  identifies did not materialize.
- `tool/check_architecture.dart` run for real (not just read) inside the
  gate: `Architecture dependencies OK (12 allowlisted deviation(s))` — the
  same count as `origin/main`'s existing allowlist; this round added **zero**
  new allowlist entries (consistent with F3 below: the domain→data import
  trips no automated rule at all, so it never needed allowlisting).
- ADR number **0196** was genuinely free on `origin/main` at the branch base
  (`git ls-tree -r --name-only 9b9dccc9 -- docs/adr/` has no `0195`/`0196`).

## Megállapítások

### F1 — MINOR — "Audio pressure changes only the vision decision" test is a weak proxy for its own acceptance criterion

- **Fájl:** `test/features/vision/application/vision_degradation_policy_test.dart:65-78`
- **Probléma:** The test constructs a `VisionPerformanceSnapshot`, calls
  `policy.decide(...)`, and then re-asserts that the snapshot's own
  `audioProcessingLatencyIncreaseMs` field is still `15`. Since
  `VisionPerformanceSnapshot` (`vision_degradation_policy.dart:8-20`) is an
  immutable value type (all `final` fields, no setters) and
  `VisionDegradationPolicy.decide()` (`:66-89`) is a pure, stateless
  `const`-constructible function with no side effects, this assertion is
  close to tautological — it mostly re-proves Dart `final` semantics rather
  than exercising anything about "the audio pipeline itself is unaffected."
- **Hatás:** None today — this is a test-strength gap, not a behavioral bug.
  It becomes relevant risk only once a future round wires this policy to a
  real audio-latency signal and a real degraded-vision effector; at that
  point this test would give false confidence that audio-side non-mutation
  is proven when it isn't.
- **Kötelező javítás:** None required to merge this round — real
  audio-pipeline integration is explicitly out of scope here (ADR 0196
  Döntés 5, brief §3 "Kívül — TILOS: audio DSP-paraméter... módosítása").
  Recommend the future wiring round add an integration-level test that
  asserts the real audio config object (not just the input snapshot) is
  untouched across a `decide()` call.
- **Ellenőrzés:** N/A this round.
- **Státusz:** OPEN (deferred, not blocking).

### F2 — NOTE — `transitionCount` getter name could be misread as a ladder-rung count

- **Fájl:** `lib/features/vision/application/vision_degradation_policy.dart:22-39`
- **Probléma:** `VisionDegradationDecision.transitionCount` returns `changed
  ? 1 : 0` — i.e. "did the decision change," not "how many ladder rungs were
  crossed." This is accurate and well-documented in the class doc-comment
  immediately above it ("Recovery can advance by one step per evaluation;
  degradation may move directly to the least severe step that covers the
  measured violation"), and is verified correct behavior (recovery: always
  exactly one rung per call, confirmed by both the round's own 7-case test
  at `:145-154` and the reviewer's own throwaway probe; degradation: can
  legitimately cross multiple rungs in one call when severity warrants it,
  e.g. `handFPS=3` jumping straight from `none` to `qualityMonitorOnly`,
  confirmed by the entry-matrix test at `:29-32`). The getter's *name* alone,
  read without the adjacent doc-comment, could mislead a future caller
  (e.g. one bounding a UI step-animation or an oscillation counter) into
  assuming it counts rungs.
- **Hatás:** None today (only test code reads this field). Future
  misreading risk only.
- **Kötelező javítás:** None required. Consider a rename (e.g. `didChange`)
  or an inline doc-comment on the getter itself (not just the class) in a
  future touch of this file.
- **Ellenőrzés:** N/A.
- **Státusz:** OPEN (follow-up opportunity, not blocking).

### F3 — NOTE — Domain-layer file imports a data-layer file (intra-feature)

- **Fájl:** `lib/features/vision/domain/performance/vision_device_tier.dart:1-2`
- **Probléma:** A `domain/` file imports `VisionDeviceTier` from
  `data/landmarks/hand_landmark_provider.dart` (a `data/` file), which is an
  atypical dependency direction for Clean Architecture (data usually depends
  on domain, not the reverse). This is forced by a genuine pre-existing
  constraint, not sloppiness this round: the enum is a pure-Dart,
  framework-free type (confirmed: `hand_landmark_provider.dart`'s only
  imports are `dart:typed_data` and three framework-free `core`/`vision`
  files — no Flutter/Riverpod/Dio/storage-plugin import anywhere in it) that
  happens to live in a data-layer file from a prior round (R12), and this
  round is explicitly forbidden from touching that file (not in
  `allowed_paths`). I independently traced the automated
  `tool/check_architecture.dart` ruleset (not just read the ADR's claim
  about it): `sharedDomainMustRemainFrameworkIndependent` only scopes
  `core/music/`, `core/audio/codec/`, `features/practice/domain/` —
  `vision/domain/` is not covered by that rule at all; `crossFeatureImportsMustUsePublicApi`
  only fires cross-feature, and this import is intra-feature (`vision` →
  `vision`). AGENTS.md §6's prose rule ("Domain nem függ Fluttertől,
  Riverpodtól, Dio-tól vagy storage plugintól") is about framework/plugin
  purity, which this import does not violate. The alternative the brief
  originally specified (a parallel `low/mid/high` redefinition) would have
  been strictly worse — a genuine ambiguous-export compile error — and ADR
  0196 documents the reasoning with concrete grep evidence, not assertion.
- **Hatás:** None — passes every automated check (re-verified, not just
  read: `flutter analyze` 0 issues, `check_architecture.dart` 12 allowlisted
  deviations = same as `origin/main`, zero new). Purely a structural wart
  inherited from a prior round's file placement.
- **Kötelező javítás:** None required — the target file is in this round's
  forbidden zone. A future round with `hand_landmark_provider.dart` in its
  `allowed_paths` could relocate `VisionDeviceTier` to a domain file and
  invert the dependency direction.
- **Ellenőrzés:** N/A.
- **Státusz:** OPEN (follow-up opportunity, not blocking).

### F4 — NOTE — Classifier's own `ArgumentError` path has no direct test in its own test file

- **Fájl:** `test/features/vision/domain/vision_device_tier_test.dart` (whole file)
- **Probléma:** `VisionDeviceTierClassifier.classify()` throws
  `ArgumentError` for `processingTimeMs <= 0`
  (`vision_device_tier.dart:56-63`), but `vision_device_tier_test.dart` has
  no test that calls `classify()` directly with an invalid value and asserts
  the throw. The behavior IS exercised, but only indirectly, through
  `DeviceTierBenchmark.evaluate()`'s catch-and-convert wrapper, tested in a
  different file (`thermal_state_adapter_test.dart:10-17`, using `-1`).
- **Hatás:** None — the guarded behavior works and is tested, just not at
  the unit closest to where it's declared.
- **Kötelező javítás:** None required to merge. Optional: add a direct
  `expect(() => classifier.classify(const
  VisionDeviceTierBenchmarkInput(0)), throwsArgumentError)` to
  `vision_device_tier_test.dart` in a future touch.
- **Ellenőrzés:** N/A.
- **Státusz:** OPEN (minor test-organization nit, not blocking).

### F5 — NOTE — ADR 0196 citation notation could be misread as a verbatim ADR 0186 quote

- **Fájl:** `docs/adr/0196-vision-device-tier-performance-and-thermal-contract.md:32-59` (Kontextus, 2. pont)
- **Probléma:** ADR 0196 quotes "Ne definiálj párhuzamos, majdnem-azonos
  típusokat." and cites it as "(R14 §0.0 'R5')" under the heading "ADR 0186".
  I independently grepped for this exact string across `docs/adr/` — it does
  **not** appear verbatim in ADR 0186 (which paraphrases the same principle
  differently, "ÚJRAFELHASZNÁLTAK, nem újradefiniáltak", at line 106). The
  exact quoted string lives in the **round brief**,
  `docs/rounds/e05-r14-pose-provider-and-posture-baseline.md:131`. The
  underlying claim (reuse-over-parallel-redefinition is an established,
  repeatedly-applied principle, traceable to R14) is fully accurate and
  well-grounded — I verified both the brief and the ADR independently — the
  citation format itself is just compressed enough that "(R14 §0.0 'R5')"
  under an "ADR 0186" heading could be misread as claiming the quote is
  literal ADR text rather than literal brief text that the ADR formalizes.
- **Hatás:** None — no factual claim is wrong, only the precision of one
  citation's implied source.
- **Kötelező javítás:** None required.
- **Ellenőrzés:** N/A.
- **Státusz:** OPEN (documentation-precision nit, not blocking).

## Lifecycle / resource check

Not applicable this round: the five new files introduce no `Stream`,
`StreamSubscription`, `Timer`, isolate, mic, or wakelock — `VisionDegradationPolicy`,
`VisionDeviceTierClassifier`, `DeviceTierBenchmark`, and `ThermalStateAdapter`
are all stateless/`const`; `VisionPerformanceMonitor` is a plain in-memory
counter with no disposable resource. Nothing to leak on any path.

## Gate-bizonyíték ellenőrzése

Re-run by the reviewer, independently, in `/tmp/review-e05-r29` (a fresh
`git clone --branch codex/e05-r29-device-tier-performance-thermal` of the
implementer's own workdir, capturing `afc49557`), as one supervised
`tools/round-gate.sh --result-json ... test/features/vision` invocation — no
`&&`/pipe/`tail` around it (the repo's own `protect_factory_files` hook
actually enforces this mechanically: an earlier attempt to chain `rm -f
<stale-result-file> && tools/round-gate.sh ...` in one command was blocked
because the hook's naive parser treats `rm`'s "all" write-target mode as
extending past `&&`; corrected by running each command as a fully separate
Bash call, per protocol).

| Gate | Állított eredmény (brief §10) | Ellenőrizve |
|---|---|---|
| format | "változtatás nélkül kész" | ✅ reproduced: `Formatted 1212 files (0 changed)` |
| analyze | zöld | ✅ reproduced: `No issues found! (ran in 16.9s)` |
| test test/features/vision | "26 teszt zöld" (the 3 new files) | ✅ reproduced at the wider gate scope: **580/580** passed in the whole `test/features/vision` tree, the round's 26 new tests confirmed present by exact name with no `[E]` markers |
| architecture | zöld | ✅ reproduced: `Architecture dependencies OK (12 allowlisted deviation(s))` — same count as `origin/main` |
| secrets | (not claimed in §10, but part of the gate) | ✅ reproduced: `Secret scan OK (2075 file(s) scanned, 0 finding(s))` |
| l10n | (not claimed in §10, but part of the gate) | ✅ reproduced: `L10n parity OK (en → hu, 1019 message(s))` |
| overall | `exit_code: 0`, `outcome: pass` | ✅ reproduced byte-for-byte via `--result-json`: `{"command_exit_code": 0, "error_hash": null, "exit_code": 0, "failed_step": null, "outcome": "pass", "schema_version": 1}` |
| CI (Router CI on the round branch) | — | Pre-flight commit `216adfef` has a green Router CI run (`31278430327`, success, 1m53s). The implementer's commit `afc49557` was not yet pushed to `origin` at review time (local-only, "ahead of origin by 1"), so there is no CI run for it yet — the orchestrator must dispatch/confirm CI on the final pushed SHA before merge, per AGENTS.md §15.1; this review's gate re-run is the pre-CI merge-readiness evidence, not a substitute for it. |

Brief §10's claims all check out; none were overclaimed. The one thing §10
could not itself prove (and does not claim to) is the CI run on the exact
pushed SHA — flagged above as a pre-merge to-do for the orchestrator, not a
review finding against the implementation.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge
megengedett a tartalmi oldalról.

**Verdikt: APPROVED.** 0 BLOCKER, 0 MAJOR, 1 MINOR (F1, explicitly deferred to
a future real-audio-integration round per ADR 0196 Döntés 5), 4 NOTE (F2–F5,
all follow-up opportunities, none blocking). All 8 acceptance criteria hold
with direct, independently-reproduced evidence. Scope is clean. Before the
actual merge, the orchestrator still needs the green CI run on the exact
pushed SHA of `afc49557` (or whatever SHA it becomes after push) per the
unchanged ADR 0052 gate and AGENTS.md §15.1 — this was outside what a
pre-push local review can observe.
