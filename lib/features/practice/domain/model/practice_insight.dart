import 'package:meta/meta.dart';

import 'practice_validation.dart';

/// Stable session-level insight codes the [PracticeCoach] emits
/// (ADR 0084 §Döntés 7).
///
/// These are NOT free-form coaching text: every code has a documented
/// evidence threshold, and the screen reader localises the matching
/// `practiceInsight.*` ARB string. A new build that adds a code MUST keep
/// the prior codes stable — the persisted history references them by code.
abstract final class PracticeInsightCode {
  /// No strum observations were recorded at all.
  static const String noSignal = 'practice.insight.no_signal';

  /// The session was cut short — too few attempts to say anything else.
  static const String lowCompletion = 'practice.insight.low_completion';

  /// The paired-event bias is dominated by late input.
  static const String biasLate = 'practice.insight.bias_late';

  /// The paired-event bias is dominated by early input.
  static const String biasEarly = 'practice.insight.bias_early';

  /// Direction accuracy is below the documented threshold.
  static const String directionError = 'practice.insight.direction_error';

  /// Chord accuracy is below the documented threshold.
  static const String chordError = 'practice.insight.chord_error';

  /// One specific chord pair is significantly slower than the rest.
  static const String chordPairProblem = 'practice.insight.chord_pair_problem';

  /// The current tempo is too high — rhythm accuracy is below 70%.
  static const String tempoTooHigh = 'practice.insight.tempo_too_high';

  /// Reinforcement — every available dimension cleared the documented bar.
  static const String positiveReinforcement =
      'practice.insight.positive_reinforcement';

  /// Recommendation to advance to the next difficulty.
  static const String nextDifficulty = 'practice.insight.next_difficulty';

  /// The complete catalogue — guarded by `PracticeValidationCode.allCodes`.
  static const Set<String> values = {
    noSignal,
    lowCompletion,
    biasLate,
    biasEarly,
    directionError,
    chordError,
    chordPairProblem,
    tempoTooHigh,
    positiveReinforcement,
    nextDifficulty,
  };
}

/// Stable recommendation-kind codes the coach can attach to an insight.
///
/// Recommendations are part of the coach's output (ADR 0084 §Döntés 7) but
/// they never replace an insight — they're a follow-up prompt.
abstract final class PracticeRecommendationKind {
  static const String retry = 'practice.recommendation.retry';
  static const String reduceTempo = 'practice.recommendation.reduce_tempo';
  static const String enableMetronome =
      'practice.recommendation.enable_metronome';
  static const String focusDirection =
      'practice.recommendation.focus_direction';
  static const String focusChordChanges =
      'practice.recommendation.focus_chord_changes';
  static const String nextDifficulty =
      'practice.recommendation.next_difficulty';

  static const Set<String> values = {
    retry,
    reduceTempo,
    enableMetronome,
    focusDirection,
    focusChordChanges,
    nextDifficulty,
  };
}

/// One piece of session-level, evidence-backed insight.
///
/// The coach emits exactly one [PracticeInsight.code] per session (A9)
/// and up to one secondary code + an optional recommendation. Codes are
/// the only thing that crosses the storage boundary — the screen localises
/// from the ARB.
@immutable
final class PracticeInsight {
  const PracticeInsight({
    required this.code,
    this.secondaryCode,
    this.recommendationKind,
  });

  /// Primary insight code (canonical; one of [PracticeInsightCode.values]).
  final String code;

  /// Optional secondary insight code, or `null` when there is no runner-up.
  final String? secondaryCode;

  /// Optional recommendation kind, or `null` when there is no follow-up.
  final String? recommendationKind;

  bool get hasSecondary => secondaryCode != null;
  bool get hasRecommendation => recommendationKind != null;

  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (code.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'insight.code.empty',
          message: 'Insight code cannot be empty.',
        ),
      );
    }
    if (recommendationKind != null && recommendationKind!.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: 'insight.recommendationKind.empty',
          message: 'Insight recommendation kind cannot be blank.',
        ),
      );
    }
    return List<PracticeValidationFailure>.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeInsight &&
          other.code == code &&
          other.secondaryCode == secondaryCode &&
          other.recommendationKind == recommendationKind;

  @override
  int get hashCode => Object.hash(code, secondaryCode, recommendationKind);
}
