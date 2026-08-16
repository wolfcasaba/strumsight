/// Typed harder/easier adjustment rule for one [ExercisePrescription]
/// (SDD Ch8 Kör 9 scope, ADR 0294).
///
/// This round only *types* the rule — a plan-assembly round applies it to a
/// learner's next attempt (SDD Ch8 Kör 10+). No Flutter, clock, or random
/// dependency belongs here.
library;

/// Whether a [ProgressionStep] makes the next attempt harder or easier.
enum ProgressionDirection {
  advance('advance'),
  regress('regress');

  const ProgressionDirection(this.code);

  final String code;

  static ProgressionDirection fromCode(String? code) => _decodeEnumCode(
    code: code,
    values: values,
    codeOf: (value) => value.code,
    typeName: 'ProgressionDirection',
  );
}

/// One typed adjustment to the next attempt's prescribed repetition target.
///
/// The sign of [repetitionTargetDelta] must agree with [direction]: an
/// [ProgressionDirection.advance] step is a positive delta, a
/// [ProgressionDirection.regress] step is a negative delta. There is no
/// implicit zero-delta "no-op" step.
final class ProgressionStep {
  ProgressionStep({required this.direction, required int repetitionTargetDelta})
    : repetitionTargetDelta = _requireNonZero(
        repetitionTargetDelta,
        'repetitionTargetDelta',
      ) {
    if (direction == ProgressionDirection.advance &&
        this.repetitionTargetDelta <= 0) {
      throw ArgumentError.value(
        repetitionTargetDelta,
        'repetitionTargetDelta',
        'an advance step requires a positive delta',
      );
    }
    if (direction == ProgressionDirection.regress &&
        this.repetitionTargetDelta >= 0) {
      throw ArgumentError.value(
        repetitionTargetDelta,
        'repetitionTargetDelta',
        'a regress step requires a negative delta',
      );
    }
  }

  final ProgressionDirection direction;
  final int repetitionTargetDelta;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'direction': direction.code,
    'repetitionTargetDelta': repetitionTargetDelta,
  };

  static ProgressionStep fromJson(Map<String, dynamic> json) {
    final directionCode = json['direction'];
    final deltaRaw = json['repetitionTargetDelta'];
    if (directionCode is! String) {
      throw ArgumentError.value(
        directionCode,
        'direction',
        'ProgressionStep JSON requires a String direction',
      );
    }
    if (deltaRaw is! num) {
      throw ArgumentError.value(
        deltaRaw,
        'repetitionTargetDelta',
        'ProgressionStep JSON requires a numeric repetitionTargetDelta',
      );
    }
    return ProgressionStep(
      direction: ProgressionDirection.fromCode(directionCode),
      repetitionTargetDelta: deltaRaw.round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressionStep &&
          other.direction == direction &&
          other.repetitionTargetDelta == repetitionTargetDelta;

  @override
  int get hashCode => Object.hash(direction, repetitionTargetDelta);
}

/// The success/failure progression pair for one [ExercisePrescription].
final class ProgressionRule {
  ProgressionRule({required this.onSuccess, required this.onFailure}) {
    if (onSuccess.direction != ProgressionDirection.advance) {
      throw ArgumentError.value(
        onSuccess,
        'onSuccess',
        'the on-success step must be an advance step',
      );
    }
    if (onFailure.direction != ProgressionDirection.regress) {
      throw ArgumentError.value(
        onFailure,
        'onFailure',
        'the on-failure step must be a regress step',
      );
    }
  }

  final ProgressionStep onSuccess;
  final ProgressionStep onFailure;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'onSuccess': onSuccess.toJson(),
    'onFailure': onFailure.toJson(),
  };

  static ProgressionRule fromJson(Map<String, dynamic> json) {
    final onSuccessRaw = json['onSuccess'];
    final onFailureRaw = json['onFailure'];
    if (onSuccessRaw is! Map || onFailureRaw is! Map) {
      throw ArgumentError.value(
        json,
        'ProgressionRule',
        'ProgressionRule JSON requires onSuccess and onFailure objects',
      );
    }
    return ProgressionRule(
      onSuccess: ProgressionStep.fromJson(
        Map<String, dynamic>.from(onSuccessRaw),
      ),
      onFailure: ProgressionStep.fromJson(
        Map<String, dynamic>.from(onFailureRaw),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressionRule &&
          other.onSuccess == onSuccess &&
          other.onFailure == onFailure;

  @override
  int get hashCode => Object.hash(onSuccess, onFailure);
}

int _requireNonZero(int value, String name) {
  if (value == 0) {
    throw ArgumentError.value(value, name, 'must not be zero');
  }
  return value;
}

T _decodeEnumCode<T extends Enum>({
  required String? code,
  required List<T> values,
  required String Function(T value) codeOf,
  required String typeName,
}) {
  if (code == null || code.trim().isEmpty) {
    throw ArgumentError.value(code, 'code', '$typeName code must not be empty');
  }
  for (final value in values) {
    if (codeOf(value) == code) return value;
  }
  throw ArgumentError.value(code, 'code', 'Unknown $typeName code: $code');
}
