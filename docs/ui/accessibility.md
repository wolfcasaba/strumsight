# Accessibility

The design system's accessibility rules (ADR 0280) are enforced by three
files under `test/accessibility/`: `semantics_contract_test.dart`,
`tap_target_test.dart`, `screen_reader_copy_test.dart`. This document is the
human-readable half of that contract — what the tests check, and, just as
important, what they cannot.

## The machine contract

- **Live region budget** (`SsLiveRegion`, `lib/core/design_system/accessibility/ss_live_region.dart`).
  The Live/Stage recognizer updates several times a second; announcing every
  update would make the screen reader unusable during the app's core flow
  (ADR 0280 §2). `SsLiveRegion.report(value, at:)` only produces a new
  announcement when the value is genuinely different from the last one
  announced AND at least `SsSemantics.liveRegionAnnouncementGap` (1000 ms,
  inclusive boundary) has passed since that announcement. A reading that
  arrives too soon is dropped, not queued — it never becomes announceable
  once the gap passes.
- **Tap targets** (`SsTapTarget.meetsMinimum`, ADR 0280 §5). Every critical
  interactive control — button, icon button, switch row, radio row, card
  dismiss control — must measure at least
  `SsSemantics.minimumInteractiveDimension` (48 dp) on both axes, as
  rendered, not merely as declared.
- **Readable tuner and strum copy** (`SsSemantics.tunerAccuracyLabel`,
  `SsSemantics.strumDirectionLabel`, ADR 0280 §5.3). The tuner's cents offset
  and the strum direction are available as text in English and Hungarian —
  not communicated by needle position, arrow glyph, or colour alone.
- **No colour-only state** (ADR 0278 §2, ADR 0280 §5.4). Success, error, and
  confidence states each carry their own readable label distinct from every
  other state of the same kind — verified at the semantics-tree level, not
  just the visual widget tree.
- **Labeled critical actions** (ADR 0280 §5.5). A destructive action's intent
  is carried in its semantics hint, merged onto the same node as its label —
  never colour alone. `SsIconButton` refuses construction without a
  non-empty label.
- **Reduced motion keeps feedback** (ADR 0274 §5.1). `SsMotionScope` collapses
  animation *duration* to zero when motion is reduced; it never gates
  semantics feedback (a live-region announcement, a state label) on that
  setting. The two are independent knobs.

## What the automated tests cannot tell you

**The automated suite is necessary, not sufficient.** It can verify that a
semantics node carries the right label, that a control measures ≥48 dp, or
that two locales produce different strings. It cannot tell you:

- whether TalkBack or VoiceOver actually SPEAKS the label in a sensible order
  relative to its siblings;
- whether the live-region cadence *feels* right to a screen-reader user
  during real, sustained Stage Mode use (the budget numbers are a starting
  point, not a substitute for listening to it);
- whether focus order matches visual/reading order on a real device;
- whether a gesture that works with TalkBack/VoiceOver's touch-exploration
  model (as opposed to a plain tap) still reaches the control.

A green `flutter test` run on these three files is evidence of a correctly
wired *contract* — it is not evidence that the app is accessible. Any screen
built on top of this toolkit still needs the manual pass below before it is
considered accessibility-reviewed.

## Manual TalkBack / VoiceOver checklist

Run this on a real device (or the platform screen-reader emulator) for any
screen that renders live or frequently-updating content, or introduces a new
critical action:

1. **Turn the screen reader on** (TalkBack on Android, VoiceOver on iOS) and
   navigate the screen using swipe-to-next / swipe-to-previous only — no
   sighted shortcuts.
2. **Reading order.** Does the spoken order match the visual/logical order?
   Flag anything that jumps unexpectedly.
3. **Every critical action is reachable and its purpose is clear from the
   spoken label alone** — including destructive actions, whose spoken hint
   should make the consequence clear before activation.
4. **Live/Stage Mode specifically:** listen through at least 30 seconds of
   continuous chord or strum recognition. Confirm announcements are spaced
   out enough to follow, and that the tuner cents / strum direction is
   spoken, not just shown.
5. **No information is colour-only.** With the screen reader's screen curtain
   or a display set to grayscale, confirm every state (success, error,
   confidence, sync status) is still distinguishable from its spoken label.
6. **Tap targets.** Using touch exploration, confirm every critical control
   is easy to land on without hunting — a target that measures 48 dp in a
   test can still feel cramped next to a dense neighbour.
7. **Reduced motion.** With the OS "reduce motion" setting on, confirm
   feedback (state changes, live announcements) still occurs — only the
   animated transition should disappear.
8. **Record the result** (pass, or the specific finding) in the round's
   handoff notes; a screen is not accessibility-reviewed until this pass has
   happened at least once.
