/// The four ways the rhythm pillar is practised, in teaching order.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §3.
/// The order is itself pedagogy — each step adds exactly one thing to get wrong:
///
///   1. [mutedStrokes] — the left hand damps, so there is no chord to miss and a
///      direction error cannot be mistaken for a fingering error. Every source
///      checked recommends isolating the right hand first.
///   2. [silentGrid] — the arrow row and the metronome, nothing damped. Adds
///      reading and keeping time to the motion.
///   3. [withChord] — hold a shape and play the pattern. The first mode where
///      chord and direction are scored together; the real thing.
///   4. [listenAndRepeat] — the app plays a pattern, the learner plays it back.
///      Adds the ear, and deliberately takes the arrow row away, so a learner
///      cannot pass the whole pillar by reading alone.
///
/// Pure Dart: no Flutter (AGENTS.md §6/§10).
library;

import '../../practice_generator/public.dart' show ExerciseCapability;

/// One practice mode of the rhythm pillar.
enum RhythmMode {
  mutedStrokes(
    code: 'rhythm.mutedStrokes',
    scoresChord: false,
    showsArrowRow: true,
    needsMetronome: true,
    demonstratesFirst: false,
  ),
  silentGrid(
    code: 'rhythm.silentGrid',
    scoresChord: false,
    showsArrowRow: true,
    needsMetronome: true,
    demonstratesFirst: false,
  ),
  withChord(
    code: 'rhythm.withChord',
    scoresChord: true,
    showsArrowRow: true,
    needsMetronome: true,
    demonstratesFirst: false,
  ),
  listenAndRepeat(
    code: 'rhythm.listenAndRepeat',
    scoresChord: false,
    showsArrowRow: false,
    needsMetronome: false,
    demonstratesFirst: true,
  );

  const RhythmMode({
    required this.code,
    required this.scoresChord,
    required this.showsArrowRow,
    required this.needsMetronome,
    required this.demonstratesFirst,
  });

  /// Stable persisted identity. Never the enum index: inserting a mode would
  /// silently relabel every stored attempt.
  final String code;

  /// Whether the chord is scored alongside the direction. Only [withChord] is,
  /// and the muted modes CANNOT be — a damped string has no chord to name.
  final bool scoresChord;

  /// Whether the notation is on screen. False for [listenAndRepeat], on purpose.
  final bool showsArrowRow;

  final bool needsMetronome;

  /// Whether the app plays the pattern before the learner does.
  final bool demonstratesFirst;

  /// The position of this mode in the teaching order, 1-based.
  ///
  /// Derived from declaration order, which the tests pin. Exposed as a number
  /// because "step 2 of 4" is what a learner is shown, and because comparing
  /// modes by `index` at call sites would spread that assumption around.
  int get step => index + 1;

  /// What the device must support for this mode's outcome to be measurable.
  ///
  /// Direction scoring and a microphone are required by all four: the pillar
  /// measures strumming, and a mode whose outcome cannot be measured must be
  /// reported as unavailable rather than scored on nothing
  /// (`mission_availability.dart`).
  List<ExerciseCapability> get requiredCapabilities => [
    ExerciseCapability.requiresMicrophone,
    ExerciseCapability.supportsDirectionScoring,
    ExerciseCapability.supportsOffline,
    if (scoresChord) ExerciseCapability.supportsChordScoring,
  ];

  /// Parses a persisted [code], or null when it is unknown.
  ///
  /// Null rather than a default: silently resolving an unknown code to
  /// [mutedStrokes] would turn a data error into a learner practising the wrong
  /// exercise.
  static RhythmMode? fromCode(String code) {
    for (final mode in values) {
      if (mode.code == code) return mode;
    }
    return null;
  }
}
