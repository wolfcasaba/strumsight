# E12-R20 — Accessibility & localization release audit

**Status:** DONE — audit complete, two `lib/**` defect classes found and
recorded (not fixed; `lib/**` is this round's tilos zona, brief §4/§0.0).
Measured on this box 2026-09-01, `main @ f54ee8c7` plus this round's own two
new test files.

**Scope (brief §1):** prove the core learning path — boot → onboarding
(Skip) → practice hub (Quick start) → practice setup (Start) → practice
session (Start → running → Finish → completed) → result — is walkable in
English AND Hungarian, at 200% text scale, and with a screen reader, or name
precisely where it is not. This round audits an existing app; it does not
change `lib/**` or `lib/l10n/**` (brief §3).

## 1. What ran

| Test file | Acceptance | What it drives |
| --- | --- | --- |
| `test/accessibility/release_flow_text_scale_test.dart` | A1, A2, §6 threshold-cell-triple, §6 valódi-sértés próba | The full core flow, both locales, `textScale ∈ {1.5, 2.0}`, mandatory phone viewport 412x915, `FlutterError.onError` overflow/exception capture |
| `test/accessibility/release_flow_semantics_test.dart` | A3, A4 | The full core flow up to `running`, then to the result route, both locales, `tester.semantics.simulatedAccessibilityTraversal()` reachability + focus-order + colour-independence checks |

Both files write their OWN locale-aware flow walker rather than reusing
`test/support/e2e_harness.dart`'s `walkOnboardingViaSkip`/
`runFirstPracticeSession` — those helpers match hardcoded English literals
(`find.text('Skip')`, `'Quick start'`, …) and the harness file itself is
outside this round's allowed-files list (brief §4, pre-flight §0.0.A/R2).
Every string in the new walkers comes from
`lookupAppLocalizations(Locale(code))` — the same delegate
`lib/core/i18n/locale_provider.dart` resolves through in production.

Neither file weakens, skips, or duplicates the three existing
`test/accessibility/*` component-level tests or the three `test/l10n/*`
tests — this audit adds FLOW-level coverage those didn't have (brief §5.1);
`arb_parity_test.dart` and `hardcoded_string_guard_test.dart` stay green,
unmodified (A5, verified by the §7 gate).

## 2. Result per acceptance criterion

| # | Criterion | Result |
| --- | --- | --- |
| A1 | Core flow, `textScale 2.0`, `en`, no overflow | **PASS with 1 recorded exception** — `setup-scoring-profile-overflow` (43px, `practice_setup_screen.dart:418`), tolerated by a dated `_KnownOverflow` entry |
| A2 | Same, `hu` | **PASS with 2 recorded exceptions** — the same `setup-scoring-profile-overflow` (43px, locale-independent) PLUS `feedback-combo-row-overflow-hu` (65px, `practice_feedback.dart:89`, Hungarian-only) |
| A3 | Every interactive element reachable via the REAL simulated accessibility traversal, sensible focus order | **PASS with 1 recorded exception class** — `switch-row-split-semantics-node` (3 occurrences per locale on Practice Setup); the primary CTA path (Quick start → Start practice → Start → Pause/Finish/Exit, in that reading order) is fully reachable and correctly labeled in both locales |
| A4 | No state communicated by colour alone | **PASS** — the session readiness row (`PracticeReadinessRow`) exposes its weak-signal/degraded-capability state as one of 4 fully-localised text labels, verified present in the traversal for both locales |
| A5 | `arb_parity_test.dart` / `hardcoded_string_guard_test.dart` unchanged and green | **PASS** — §7 gate |
| A6 | Every found exception has an owner + expiry | **PASS — machine-checked**, not eyeballed: `release_flow_semantics_test.dart`'s `"A6 — known-exceptions.yaml is a machine-checked registry"` group (a fail-closed hand-rolled reader, no `package:yaml` on this tree) parses `docs/accessibility/known-exceptions.yaml`'s 3 entries and asserts (1) every entry carries a non-empty `id`/`owner`/`expiry`/`severity`/`file`/`measured_on`/`source_test`, (2) `expiry: unscheduled` — all 3 entries — is only legal together with a dated `review_by:` (all 3 now carry `review_by: "2026-12-01"`, resolving the review's "lejárat nélkül" finding), and (3) the YAML `id` set and both test files' tolerance mirrors (`knownOverflows` in `release_flow_text_scale_test.dart`, `switchRowSplitSemanticsId` here) cover each other exactly — no orphan entry either direction |

None of the three findings are judged **P1** (release-blocking): the two
overflow defects clip a SECONDARY label (a non-localised scoring-profile id;
a combo counter) rather than the primary content or any control, and the
`SsSwitchRow` reachability split affects three OPTIONAL practice-setup
toggles, not the primary CTA. The STOP-protocol (brief §0) is therefore not
invoked — this file, `known-exceptions.yaml`, and the two new test files ARE
the round's complete, documented output.

## 3. The three findings (detail in `known-exceptions.yaml`)

1. **`setup-scoring-profile-overflow`** — `_ScoringProfileReadout`
   (`practice_setup_screen.dart:418`) puts an un-`Expanded` `Text(profileId)`
   next to an `Expanded` label in a `Row`; at `textScale 2.0` it overflows by
   43px on the right, identically in `en` and `hu` (the id itself never
   localises — the label growing is what starves it of space).
2. **`feedback-combo-row-overflow-hu`** — the combo-count `Row`
   (`practice_feedback.dart:89`) has neither `Text` child wrapped in
   `Expanded`/`Flexible`; the Hungarian `practiceFeedbackComboLabel`
   translation is long enough to overflow by 65px at `textScale 2.0`, where
   the shorter English "Combo" does not.
3. **`switch-row-split-semantics-node`** — `SsSwitchRow` (a shared
   design-system component, not Practice-specific) produces TWO adjacent
   accessibility-traversal stops per row instead of one: an outer,
   full-width node owned by its `InkWell` that carries the `tap` action but
   NO label, and an inner `MergeSemantics` node that carries the label
   (`"Metronome"`/`"Accent on count 1"`/`"Show chord hint"` in `en`) and the
   switch's toggled state but NO `tap` action. A screen-reader user landing
   on the outer node hears nothing before double-tapping it. Measured both
   directly (an isolated `SsSwitchRow` pumped alone) and in the full flow
   (Practice Setup, 3 instances, both locales). This is the kind of gap
   `docs/LESSONS.md` L460 names: the pre-existing
   `semantics_contract_test.dart`/`screen_reader_copy_test.dart` component
   tests use `find.bySemanticsLabel(...)` presence checks, which are
   satisfied by the INNER node and so never noticed the OUTER node is
   silent — only a full traversal walk (`simulatedAccessibilityTraversal`)
   surfaces the split.

None of the three were fixed — `lib/**` is this round's tilos zona. Fixing
finding 3 would require re-shaping `SsSwitchRow`'s semantics wiring (a
shared component, used elsewhere too — e.g. `SettingsScreen`, per
`test/accessibility/tap_target_test.dart`), which is design-system-round
scope, not this audit's.

## 4. §6 "Valódi-sértés próba" (mandatory falsification check)

Per brief §6: proves the `textScaleFactorTestValue` switch this round's
tests rely on actually reaches `StrumSightApp`'s tree (root:
`MaterialApp.router`, `lib/app/strumsight_app.dart:31`) — a `MediaQuery`
wrapper placed ABOVE the pumped tree would be inert here (§0.0.A/R4), and an
inert switch would make every "no overflow" cell above vacuously green.

Method: boot the SAME app (`bootE2eApp`, `en` locale, fresh onboarding) at
`textScale 1.0`, measure the rendered height of the onboarding "Skip" label
(`tester.getSize(find.text(l10n.onboardSkip))`); repeat at `textScale 2.0`;
assert the second height is strictly greater than the first. This is now a
permanent cell in `release_flow_text_scale_test.dart` (not a one-off manual
step), so it re-verifies on every gate run, not just this round.

**Measured on this box (2026-09-01, phone viewport 412x915, `en` locale):**

| textScale | Rendered height of `l10n.onboardSkip` |
| --- | --- |
| 1.0 | 20.0px |
| 2.0 | 40.0px |

The two heights differ (2× — matching the scale factor exactly, since a
single-line `Text` at a fixed font size scales linearly), which is the
proof: had `MaterialApp.router` ignored the platform dispatcher's test
value, both would have measured identically at 20.0px, and every A1/A2 cell
above would not have been testing what it claims to.

## 5. What this audit does NOT cover

- **The detailed `PracticeResultScreen`.** The router's `AppRoutes.practiceResult`
  route always builds `PracticeResultFallback` (`lib/app/routing/app_router.dart:346-348`)
  — a static icon+title+body message with no interactive control — and that
  is the "eredmény" landing state both new test files walk to and measure.
  The content-rich `PracticeResultScreen` (score, per-metric breakdown,
  next-step actions) is a DIFFERENT screen, reached only via an explicit
  `Navigator.push` carrying a `PracticeHistoryEntry` — e.g. from
  `PracticeHistoryScreen`'s row tap, not from the practice-session
  round-trip this audit drives. Neither this round's text-scale cells nor
  its semantics cells measure `PracticeResultScreen` at all; it was not
  audited at `textScale 2.0`, in `hu`, or with a screen reader.
- **Screen-reader announcement TIMING** (ADR 0280's live-region budget) —
  already covered by `test/accessibility/semantics_contract_test.dart`'s A1
  group; this round's flow walk does not re-measure it.
- **Any screen outside the core flow** (Settings, Tuner, Live, Vision,
  Song Trainer, …) — Chapter 13's `e13_r36_variant_matrix_test.dart` and
  `closure_suite_test.dart` cover a risk-based screen set at `textScale`
  1.0/2.0 in isolation; this round is additive (flow-level only), not a
  re-audit of those screens.
- **`textScale` above 2.0** — deliberately out of scope per brief §6's
  threshold-cell-triple: 2.0 is the inclusive release threshold, and a
  passing 2.5 cell would not be evidence for it, so no 2.5 cell exists here.
- **`SsSwitchRow` outside Practice Setup** — the finding in §3.3 above is
  measured at the 3 Practice-Setup call sites this flow reaches; other call
  sites (e.g. `SettingsScreen`) were not independently re-measured this
  round, though the defect is structural to the shared component and would
  be expected to reproduce there too.
- **TalkBack/VoiceOver on a real device** — every measurement here is
  Flutter's own simulated semantics tree
  (`tester.semantics.simulatedAccessibilityTraversal()`), which the API
  documentation itself notes can diverge from real platform behaviour at
  the edges (e.g. how a scrollable's last item is announced); it is not a
  substitute for the user's real-device APK acceptance test (AGENTS.md /
  HORIZON conventions).

## 6. §10 implementation handoff

See `docs/rounds/e12-r20-accessibility-and-localization-release-audit.md`
§10 for the round-brief-format summary (gate result, files touched, the
valódi-sértés próba numbers repeated for the record).
