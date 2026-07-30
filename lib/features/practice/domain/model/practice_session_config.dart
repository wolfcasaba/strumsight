import 'package:meta/meta.dart';

import 'practice_validation.dart';
import 'tempo.dart';

/// Immutable user and device settings for one practice session.
///
/// Speed Builder policy is intentionally absent until its dedicated round.
@immutable
final class PracticeSessionConfig {
  const PracticeSessionConfig({
    required this.definitionId,
    required this.definitionSnapshotVersion,
    required this.effectiveTempo,
    required this.countInBars,
    required this.loopCount,
    required this.metronomeEnabled,
    required this.accentEnabled,
    required this.backingEnabled,
    required this.scoringProfileId,
    this.easyVariationId,
    required this.inputLatency,
    required this.visualLatency,
    required this.expectedChordHintEnabled,
    required this.sessionTimeout,
    required this.reducedMotion,
  });

  static const int minimumCountInBars = 0;
  static const int maximumCountInBars = 4;
  static const int minimumLoopCount = 1;
  static const int maximumLoopCount = 32;
  static const Duration maximumLatency = Duration(milliseconds: 500);

  final String definitionId;
  final int definitionSnapshotVersion;
  final Tempo effectiveTempo;
  final int countInBars;
  final int loopCount;
  final bool metronomeEnabled;
  final bool accentEnabled;
  final bool backingEnabled;
  final String scoringProfileId;
  final String? easyVariationId;
  final Duration inputLatency;
  final Duration visualLatency;
  final bool expectedChordHintEnabled;
  final Duration sessionTimeout;
  final bool reducedMotion;

  /// Returns every independent validation problem for this configuration.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (definitionId.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configDefinitionIdEmpty,
          message: 'Definition ID cannot be empty.',
        ),
      );
    }
    if (definitionSnapshotVersion <= 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configSnapshotVersionInvalid,
          message: 'Definition snapshot version must be positive.',
        ),
      );
    }
    failures.addAll(effectiveTempo.validate());
    if (countInBars < minimumCountInBars || countInBars > maximumCountInBars) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configCountInBarsOutOfRange,
          message: 'Count-in bars must be between 0 and 4.',
        ),
      );
    }
    if (loopCount < minimumLoopCount || loopCount > maximumLoopCount) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configLoopCountOutOfRange,
          message: 'Loop count must be between 1 and 32.',
        ),
      );
    }
    if (!_latencyInRange(inputLatency)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configInputLatencyOutOfRange,
          message: 'Input latency must be between 0 and 500 milliseconds.',
        ),
      );
    }
    if (!_latencyInRange(visualLatency)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configVisualLatencyOutOfRange,
          message: 'Visual latency must be between 0 and 500 milliseconds.',
        ),
      );
    }
    if (sessionTimeout <= Duration.zero) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configSessionTimeoutNonPositive,
          message: 'Session timeout must be strictly positive.',
        ),
      );
    }
    if (scoringProfileId.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.configScoringProfileIdEmpty,
          message: 'Scoring profile ID cannot be empty.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  static bool _latencyInRange(Duration value) =>
      value >= Duration.zero && value <= maximumLatency;

  /// Returns a modified value while preserving every omitted field.
  ///
  /// Set [clearEasyVariationId] to explicitly replace an existing variation
  /// with null.
  PracticeSessionConfig copyWith({
    String? definitionId,
    int? definitionSnapshotVersion,
    Tempo? effectiveTempo,
    int? countInBars,
    int? loopCount,
    bool? metronomeEnabled,
    bool? accentEnabled,
    bool? backingEnabled,
    String? scoringProfileId,
    String? easyVariationId,
    bool clearEasyVariationId = false,
    Duration? inputLatency,
    Duration? visualLatency,
    bool? expectedChordHintEnabled,
    Duration? sessionTimeout,
    bool? reducedMotion,
  }) => PracticeSessionConfig(
    definitionId: definitionId ?? this.definitionId,
    definitionSnapshotVersion:
        definitionSnapshotVersion ?? this.definitionSnapshotVersion,
    effectiveTempo: effectiveTempo ?? this.effectiveTempo,
    countInBars: countInBars ?? this.countInBars,
    loopCount: loopCount ?? this.loopCount,
    metronomeEnabled: metronomeEnabled ?? this.metronomeEnabled,
    accentEnabled: accentEnabled ?? this.accentEnabled,
    backingEnabled: backingEnabled ?? this.backingEnabled,
    scoringProfileId: scoringProfileId ?? this.scoringProfileId,
    easyVariationId: clearEasyVariationId
        ? null
        : easyVariationId ?? this.easyVariationId,
    inputLatency: inputLatency ?? this.inputLatency,
    visualLatency: visualLatency ?? this.visualLatency,
    expectedChordHintEnabled:
        expectedChordHintEnabled ?? this.expectedChordHintEnabled,
    sessionTimeout: sessionTimeout ?? this.sessionTimeout,
    reducedMotion: reducedMotion ?? this.reducedMotion,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSessionConfig &&
          other.definitionId == definitionId &&
          other.definitionSnapshotVersion == definitionSnapshotVersion &&
          other.effectiveTempo == effectiveTempo &&
          other.countInBars == countInBars &&
          other.loopCount == loopCount &&
          other.metronomeEnabled == metronomeEnabled &&
          other.accentEnabled == accentEnabled &&
          other.backingEnabled == backingEnabled &&
          other.scoringProfileId == scoringProfileId &&
          other.easyVariationId == easyVariationId &&
          other.inputLatency == inputLatency &&
          other.visualLatency == visualLatency &&
          other.expectedChordHintEnabled == expectedChordHintEnabled &&
          other.sessionTimeout == sessionTimeout &&
          other.reducedMotion == reducedMotion;

  @override
  int get hashCode => Object.hash(
    definitionId,
    definitionSnapshotVersion,
    effectiveTempo,
    countInBars,
    loopCount,
    metronomeEnabled,
    accentEnabled,
    backingEnabled,
    scoringProfileId,
    easyVariationId,
    inputLatency,
    visualLatency,
    expectedChordHintEnabled,
    sessionTimeout,
    reducedMotion,
  );
}
