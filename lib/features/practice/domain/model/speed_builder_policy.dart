import 'package:meta/meta.dart';

import 'practice_validation.dart';
import 'tempo.dart';

/// Stable machine-readable validation codes for Speed Builder configuration.
abstract final class SpeedBuilderValidationCode {
  static const String startBpmInvalid = 'speedBuilder.startBpm.invalid';
  static const String targetBpmInvalid = 'speedBuilder.targetBpm.invalid';
  static const String targetBeforeStart = 'speedBuilder.targetBpm.beforeStart';
  static const String stepBpmOutOfRange = 'speedBuilder.stepBpm.outOfRange';
  static const String maxAttemptsOutOfRange =
      'speedBuilder.maxAttempts.outOfRange';
  static const String requiredPassesNonPositive =
      'speedBuilder.requiredConsecutivePasses.nonPositive';
  static const String reduceFailsNonPositive =
      'speedBuilder.reduceAfterConsecutiveFails.nonPositive';
}

/// Immutable configuration for one Speed Builder session.
@immutable
final class SpeedBuilderPolicy {
  const SpeedBuilderPolicy({
    required this.startBpm,
    required this.targetBpm,
    required this.stepBpm,
    this.requiredConsecutivePasses = 2,
    this.maxAttempts = 20,
    this.reduceAfterConsecutiveFails = 2,
  });

  final Tempo startBpm;
  final Tempo targetBpm;
  final double stepBpm;
  final int requiredConsecutivePasses;
  final int maxAttempts;
  final int reduceAfterConsecutiveFails;

  /// Returns every independent configuration problem.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (startBpm.validate().isNotEmpty || startBpm.bpm <= 0) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.startBpmInvalid,
          message: 'Speed Builder start BPM must be a valid positive tempo.',
        ),
      );
    }
    if (targetBpm.validate().isNotEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.targetBpmInvalid,
          message: 'Speed Builder target BPM must be a valid tempo.',
        ),
      );
    }
    if (targetBpm.bpm < startBpm.bpm) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.targetBeforeStart,
          message: 'Target BPM cannot be lower than start BPM.',
        ),
      );
    }
    if (!stepBpm.isFinite || stepBpm < 1 || stepBpm > 20) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.stepBpmOutOfRange,
          message: 'Speed Builder step must be between 1 and 20 BPM.',
        ),
      );
    }
    if (maxAttempts < 1 || maxAttempts > 100) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.maxAttemptsOutOfRange,
          message: 'Speed Builder max attempts must be between 1 and 100.',
        ),
      );
    }
    if (requiredConsecutivePasses < 1) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.requiredPassesNonPositive,
          message: 'Required consecutive passes must be positive.',
        ),
      );
    }
    if (reduceAfterConsecutiveFails < 1) {
      failures.add(
        const PracticeValidationFailure(
          code: SpeedBuilderValidationCode.reduceFailsNonPositive,
          message: 'Consecutive fails before reduction must be positive.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeedBuilderPolicy &&
          other.startBpm == startBpm &&
          other.targetBpm == targetBpm &&
          other.stepBpm == stepBpm &&
          other.requiredConsecutivePasses == requiredConsecutivePasses &&
          other.maxAttempts == maxAttempts &&
          other.reduceAfterConsecutiveFails == reduceAfterConsecutiveFails;

  @override
  int get hashCode => Object.hash(
    startBpm,
    targetBpm,
    stepBpm,
    requiredConsecutivePasses,
    maxAttempts,
    reduceAfterConsecutiveFails,
  );
}
