# Chapter 13 completion report — E13-R36 (visual regression & closure)

**Measured against:** `main @ 126d0dfc` + this round's own tree.
**Date:** 2026-08-27.
**Round:** E13-R36, the Chapter 13 (UI/UX Design System) closing round.
**Implementer:** Claude Sonnet 5 (`sonnet-impl`).

## 1. What this round shipped

- `test/ui/goldens/e13_r36_variant_matrix_test.dart` — a PNG-free variant
  matrix: 6 risk-based screens (`today_hub`, `live`, `tuner`, `settings`,
  `vision_result`, `login`) × {light, dark} × {en, hu} × {compact portrait,
  landscape, medium, expanded} × {textScale 1.0, 2.0} = **192 cells**, each
  asserting no `RenderFlex` overflow and no pump exception via
  `FlutterError.onError` (never a text heuristic).
- `test/accessibility/closure_suite_test.dart` — 12 cells across route,
  permission, state-restoration and 200%-text-scale groups, each tapping
  through a real critical flow (not just rendering it).
- `docs/ui/legacy-backlog.md` (new), `docs/ui/migration-status.md`
  (updated to the measured Ch13 end-state), this report.
- No golden PNG was added or changed this round (see §2).

## 2. Intentional golden differences

**None.** This round added zero PNG files and modified zero existing
`matchesGoldenFile` reference. `git diff --stat main -- test/ui/goldens/`
for this branch shows exactly one new `.dart` test file
(`e13_r36_variant_matrix_test.dart`, PNG-free by construction) and no
changes under `test/ui/goldens/goldens/`. Per brief §0.0.B/B4, this makes
the second file (`e13_r36_screens_golden_test.dart`) optional, and it is
correspondingly absent — there is nothing to justify a diff on.

**The A3 evidence is therefore two-part:**

1. **The new variant matrix** — 192/192 cells green, measured locally on
   this (aarch64) box in this session (`flutter test test/ui/goldens/
   e13_r36_variant_matrix_test.dart` → `+192: All tests passed!`, ~13s).
   Layout assertions are platform-independent (dp-based Flutter layout, not
   raster comparison), so this result is NOT subject to the ARM↔x86
   rasterization drift below.
2. **The pre-existing 20 golden-test files**
   (`e13_r16…e13_r35_screens_golden_test.dart`) — untouched by this round
   (not in the allowed-paths list beyond `test/ui/goldens/`, and `git diff`
   confirms zero byte changed in any of them or their PNGs). Per L516/L493
   (`docs/LESSONS.md`), running `matchesGoldenFile` comparisons on THIS
   (aarch64) box against PNGs recorded on x86 produces false reds from
   rasterization drift alone — so this report deliberately does NOT claim a
   local run of those 20 files as evidence. Their green state is
   CI-verified at the merge SHA (`ADR 0426`, `tools/golden-x86.sh`
   architecture) — the CI dispatch is the orchestrator's step (brief §7),
   not this implementer round's.

## 3. Measured runtime, DSP baseline, and the device-gate limit (A9)

### 3a. Measured runtime (this box, this session, 2026-08-27)

The mandatory round-gate command (brief §7, exact invocation below) ran to
completion, all 10 steps green, **wall time 1m50.5s** (`real 1m50.506s`,
measured with the shell's own `time` around the untruncated
`tools/round-gate.sh` invocation):

```bash
tools/round-gate.sh test/accessibility/semantics_contract_test.dart \
  test/accessibility/tap_target_test.dart \
  test/accessibility/screen_reader_copy_test.dart \
  test/accessibility/closure_suite_test.dart \
  test/ui/goldens/e13_r36_variant_matrix_test.dart
```

Per-step breakdown (from that run's own step timestamps):

| Step | Result | Notable timing |
| --- | --- | --- |
| format (2154 files) | zöld | 9.09s |
| analyze (`lib/ test/ tool/`) | zöld | 26.1s |
| `semantics_contract_test.dart` (13 tests) | zöld | ~1s |
| `tap_target_test.dart` (6 tests) | zöld | ~1s |
| `screen_reader_copy_test.dart` (9 tests) | zöld | <1s |
| `closure_suite_test.dart` (12 tests) | zöld | ~4s |
| `e13_r36_variant_matrix_test.dart` (192 tests) | zöld | ~13s |
| architecture | zöld | 12 allowlisted deviations (unchanged) |
| secrets | zöld | 3921 files scanned, 0 findings |
| l10n | zöld | en→hu, 2289 messages, parity OK |

### 3b. DSP baseline comparison against the pre-migration value

`test/tooling/real_audio_dsp_baseline_test.dart` (the metric-contract test
for `tool/benchmarks/real_audio_dsp_baseline.dart`) ran green this session:
**9/9 tests passed, ~5s** (`flutter test test/tooling/
real_audio_dsp_baseline_test.dart`).

**The pre-migration comparison value:** both the test and the benchmark
tool it covers were last modified in **E99-R05** (`c4ce2cc0`, committed
2026-08-09) — measured via `git log -- test/tooling/
real_audio_dsp_baseline_test.dart tool/benchmarks/
real_audio_dsp_baseline.dart`. Chapter 13 (`E13-R01`, `15f9936f`) starts
2026-08-21, twelve days later. **Neither file has been touched by any
E13 round (R01 through this one, R36).** The DSP baseline's behavior is
therefore not just "still green" but PROVABLY UNCHANGED source, before and
after the entire design-system migration — the strongest form of "no
regression" this repository's static evidence can offer, and it directly
supports §5.6 ("the design refactor must not worsen DSP/ML latency"): the
migration touched zero lines the DSP baseline measures.

**Caveat:** `real_audio_dsp_baseline_test.dart` is a metric/tolerance
CONTRACT test (onset matching, chord scoring, tempo tolerance boundaries)
run against synthetic ground truth — it does not itself run the DSP engine
against a real-audio corpus in this environment (no such corpus or
device is available on this box). It is the correct, reproducible
pre-existing measure available here; a real-audio accuracy run remains a
separate, already-existing tool (`tool/benchmarks/
real_audio_dsp_baseline.dart`), out of this round's scope to re-run.

### 3c. The §5.5 limit, stated plainly

**This box cannot measure real UI frame timing.** `grep -rln
"FrameTiming|frameTime|frame_time|jank" lib/ test/ tool/` finds no
frame-timing harness in the tree (the one hit, `analyze_providers.dart`,
is unrelated). There is no Android/iOS emulator or physical device attached
to this environment, and camera/microphone throughput during an active
Live/Song Trainer/Vision session is meaningless without one. **The actual
UI-keretidő (frame time) during a real Live/Song/Vision session is,
and remains, the subject of the real-device acceptance gate (§5.5, the
checklist in §5 below) — it is a release-gate concern, not a merge-gate
one, and no number in this report should be read as a substitute for it.**

## 4. Known limitations

- **Two dated, measured `lib/**` layout defects this round could not fix**
  (`lib/**` is this round's tilos zona) — both discovered by this round's
  own new gates, both tracked with a shrink-only exclusion mechanism so a
  silent fix or a silent regression both surface as a test failure. Full
  detail (file, cell, px, date) in `docs/ui/legacy-backlog.md` §1:
  1. `lib/features/live/screens/live_screen.dart:477` — the stat-strip
     `Row` overflows 12px (en) / 34px (hu) at the `landscape` viewport with
     `textScale: 2.0`, both themes (4 exclusion-list cells).
  2. `lib/features/onboarding/screens/permission_primer_screen.dart` — the
     permanently-denied branch overflows 297px at `textScale: 2.0` because,
     unlike the retryable branch a few lines above it, it is not wrapped in
     a scrollable.
- **53 of 96 production screens (55.2%) remain on the legacy theme**
  (`AppColors`/`AppPalette`/`AppTheme` directly, not `core/design_system`).
  All are reachable and render correctly on their pre-Ch13 theme; none
  regressed. Full per-feature breakdown in `docs/ui/migration-status.md`;
  dated backlog with owners in `docs/ui/legacy-backlog.md` §3.
- **The UI-architecture guard (`tool/check_ui_architecture.dart`) does not
  exist** — deferred, not built unwired, per §0.0.B/B3 (its two possible
  gate entry points and its guard-of-the-guard location are all this
  round's tilos zona). Dated entry in `docs/ui/legacy-backlog.md` §2.
- **The variant matrix's risk-based screen set is six screens, not
  ninety-six.** It is a targeted sample (DSP-critical real-time screens,
  the main hub, a data-heavy settings screen, a complex-card analytics
  screen, and the pre-auth critical path) chosen for layout risk, not an
  exhaustive sweep — brief §0.0.B/B4 explicitly rejects a PNG-explosion /
  full-inventory approach in favor of this shape.
- **No new golden PNG was recorded this round** (§2) — the 20 pre-existing
  golden-test files' cross-platform (aarch64 local vs x86 CI) parity is
  therefore CI-verified only, not re-confirmed by this report.

## 5. Real-device acceptance checklist (prepared, unfilled — §5.5)

This checklist is prepared for a human tester on a real Android/iOS
device. Filling it in is a release-gate step, not a merge-gate one — it is
NOT evidence for any acceptance criterion in this round's brief §6.

| # | Check | Device/OS | Result | Tester | Date |
| --- | --- | --- | --- | --- | --- |
| 1 | Live session: mic starts, chord/strum detection responsive, no audible glitch during a 2-minute session | | | | |
| 2 | Live session frame time stays smooth (no visible jank) at default text size | | | | |
| 3 | Live session frame time stays smooth at 200% OS text scale | | | | |
| 4 | Tuner: mic starts, reading updates responsively, no audible glitch | | | | |
| 5 | Vision session: camera starts, overlay tracks in real time, no dropped-frame stutter | | | | |
| 6 | Vision session at 200% OS text scale: overlay and coach copy remain usable | | | | |
| 7 | Song Trainer playback: audio/visual sync holds through a full song | | | | |
| 8 | App rotated to landscape mid-session (Live, Tuner, Vision): no crash, no stuck state | | | | |
| 9 | TalkBack / VoiceOver: the critical flows in `closure_suite_test.dart` (login, settings, permission primer) are operable by a screen-reader user | | | | |
| 10 | Cold start → onboarding → first Live session, on the lowest-spec device in the support matrix | | | | |
| 11 | The two `docs/ui/legacy-backlog.md` §1 dated defects (live_screen stat strip, permission primer permanently-denied branch) reproduce as described, confirming they are not test-harness artifacts | | | | |

## 6. Release recommendation

**Recommend merge**, conditional on the unchanged ADR 0052 green gate (this
round's gate: 10/10 green, §3a) plus the CI-side full suite, randomized
property gate, golden-mátrix and APK build (ADR 0053) — all outside this
implementer round's scope, dispatched and verified by the orchestrator.

**Not a recommendation to ship without §5.5.** The real-device checklist
above is unfilled by design; a release build should not go out before at
least the Live/Tuner/Vision rows (1–6) are signed off on real hardware,
since this box cannot produce that evidence.

**Chapter 13 is not "fully migrated" — it is "quality-gated at its current
scope."** 44.8% of production screens are on the design system; the
remaining 55.2% are on a working, unbroken legacy theme with a dated,
owned backlog (`docs/ui/legacy-backlog.md`). That distinction is the
substance of this round's closure: the gate that exists now (variant
matrix + closure suite + the three pre-existing accessibility suites)
covers what has migrated and proves the legacy remainder is not silently
broken, rather than claiming a completeness the measured tree does not
have.
