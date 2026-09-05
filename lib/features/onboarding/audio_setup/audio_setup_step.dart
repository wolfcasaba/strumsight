import 'package:meta/meta.dart';

/// What each step of the automatic audio-setup wizard measures (SDD Ch14):
/// one silence measurement, one strong down-strum, one up-strum, the four
/// beginner-chord check, then a closing position suggestion. No screen binds
/// to this yet (ADR 0519 D8) — this is the typed shape a future round's UI
/// walks through.
enum AudioSetupStepKind {
  silence,
  strongDownStrum,
  upStrum,
  chordCheck,
  positionSuggestion,
}

/// One step of the wizard's fixed sequence.
@immutable
class AudioSetupStep {
  const AudioSetupStep({
    required this.kind,
    required this.expectedDuration,
    this.expectedChord,
  }) : assert(
         (kind == AudioSetupStepKind.chordCheck) == (expectedChord != null),
         'expectedChord must be set if and only if kind is chordCheck',
       );

  final AudioSetupStepKind kind;

  /// The step's planned share of the wizard's total run time — a design
  /// input for [totalPlannedDuration], not a live-measured value; the
  /// controller measures the real elapsed time of an actual run separately.
  final Duration expectedDuration;

  /// The chord label to check against. Non-null only for
  /// [AudioSetupStepKind.chordCheck] steps.
  final String? expectedChord;

  /// The full wizard sequence in run order (SDD Ch14): one silence
  /// measurement, one strong down-strum, one up-strum, the four
  /// beginner-chord check (E, Am, G, C), and a closing position suggestion.
  static const List<AudioSetupStep> sequence = <AudioSetupStep>[
    AudioSetupStep(
      kind: AudioSetupStepKind.silence,
      expectedDuration: Duration(seconds: 5),
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.strongDownStrum,
      expectedDuration: Duration(seconds: 5),
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.upStrum,
      expectedDuration: Duration(seconds: 5),
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.chordCheck,
      expectedDuration: Duration(seconds: 5),
      expectedChord: 'E',
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.chordCheck,
      expectedDuration: Duration(seconds: 5),
      expectedChord: 'Am',
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.chordCheck,
      expectedDuration: Duration(seconds: 5),
      expectedChord: 'G',
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.chordCheck,
      expectedDuration: Duration(seconds: 5),
      expectedChord: 'C',
    ),
    AudioSetupStep(
      kind: AudioSetupStepKind.positionSuggestion,
      expectedDuration: Duration(seconds: 5),
    ),
  ];

  /// The sequence's planned total — a design-time sum kept honest against
  /// [isAudioSetupDurationAccepted] by a test; a real run's elapsed time is
  /// a controller concern, not this static shape's.
  static Duration get totalPlannedDuration => sequence.fold(
    Duration.zero,
    (total, step) => total + step.expectedDuration,
  );
}

/// The wizard's accepted total-duration window (acceptance #1). Both bounds
/// are INCLUSIVE — measured safe on whole seconds/milliseconds (ADR 0519
/// §0.0: `30 <= 59 <= 60` / `30 <= 60 <= 60` / `30 <= 61 <= 60 == false`, no
/// floating-point edge). A run landing exactly on 60s still counts as a
/// valid quick setup; only strictly past it is rejected.
const Duration kAudioSetupMinDuration = Duration(seconds: 30);
const Duration kAudioSetupMaxDuration = Duration(seconds: 60);

/// Whether a completed run's total elapsed [total] falls inside the
/// accepted setup window.
bool isAudioSetupDurationAccepted(Duration total) =>
    total >= kAudioSetupMinDuration && total <= kAudioSetupMaxDuration;
