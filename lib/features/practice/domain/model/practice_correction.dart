import 'package:meta/meta.dart';

/// What the player (or the app) has to change next (E14-R38, ADR 0551 D6).
///
/// Closed set, exhaustively switched by the presentation layer — a new kind
/// is a compile error at the one place that turns it into words, never a
/// silently generic "try again".
enum PracticeCorrectionKind {
  /// The app could not stand behind what it heard. The correction belongs to
  /// the RECOGNIZER, not to the player: it names the reject reason
  /// ("too quiet", "too much background noise"), which is something the
  /// player can act on without being told they played wrongly.
  recognitionUnclear,

  /// A chord target was missed or played as a different chord, and the app
  /// was confident about that. The correction names the expected chord.
  playExpectedChord,

  /// A target was missed and it carries no chord (a rhythm/strum-pattern
  /// target). The correction is the target itself — there is no chord to
  /// name, and naming one would be an invention.
  hitTheTarget,
}

/// One concrete, stateless "next fix" derived from the scoring pass.
///
/// It is a VIEW over already-computed results (matches + chord scores +
/// observations), never a piece of session state: the reducer's state
/// machine is untouched by this round, and a correction that could no longer
/// be derived simply stops being shown.
@immutable
final class PracticeCorrection {
  const PracticeCorrection._({
    required this.kind,
    required this.targetIndex,
    this.expectedChord,
    this.rejectReasonCode,
  });

  /// The recognizer abstained on [targetIndex]; [rejectReasonCode] is the
  /// stable `RecognitionRejectReason` name, or `null` when the recognizer
  /// gave no reason (then the UI states the generic "unclear" sentence
  /// rather than inventing a cause).
  factory PracticeCorrection.recognitionUnclear({
    required int targetIndex,
    required String? rejectReasonCode,
  }) => PracticeCorrection._(
    kind: PracticeCorrectionKind.recognitionUnclear,
    targetIndex: targetIndex,
    rejectReasonCode: rejectReasonCode,
  );

  /// The player has to play [expectedChord] at [targetIndex].
  factory PracticeCorrection.playExpectedChord({
    required int targetIndex,
    required String expectedChord,
  }) => PracticeCorrection._(
    kind: PracticeCorrectionKind.playExpectedChord,
    targetIndex: targetIndex,
    expectedChord: expectedChord,
  );

  /// The player missed a chord-less target at [targetIndex].
  factory PracticeCorrection.hitTheTarget({required int targetIndex}) =>
      PracticeCorrection._(
        kind: PracticeCorrectionKind.hitTheTarget,
        targetIndex: targetIndex,
      );

  final PracticeCorrectionKind kind;

  /// Which compiled target event this correction is about — so a caller can
  /// tell "the same problem again" from "a new problem".
  final int targetIndex;

  /// Set only for [PracticeCorrectionKind.playExpectedChord].
  final String? expectedChord;

  /// Set only for [PracticeCorrectionKind.recognitionUnclear].
  final String? rejectReasonCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeCorrection &&
          other.kind == kind &&
          other.targetIndex == targetIndex &&
          other.expectedChord == expectedChord &&
          other.rejectReasonCode == rejectReasonCode;

  @override
  int get hashCode =>
      Object.hash(kind, targetIndex, expectedChord, rejectReasonCode);

  @override
  String toString() =>
      'PracticeCorrection(${kind.name}, target=$targetIndex, '
      'chord=$expectedChord, reason=$rejectReasonCode)';
}
