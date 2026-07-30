/// Stable machine-readable codes emitted by Practice domain validation.
abstract final class PracticeValidationCode {
  static const String tempoBpmNotFinite = 'tempo.bpm.notFinite';
  static const String tempoBpmOutOfRange = 'tempo.bpm.outOfRange';
  static const String meterBeatsPerBarOutOfRange =
      'meter.beatsPerBar.outOfRange';
  static const String meterBeatUnitUnsupported = 'meter.beatUnit.unsupported';
  static const String beatPositionNegative = 'beatPosition.negative';

  /// The complete validation-code catalogue for the current Practice domain.
  static const Set<String> values = {
    tempoBpmNotFinite,
    tempoBpmOutOfRange,
    meterBeatsPerBarOutOfRange,
    meterBeatUnitUnsupported,
    beatPositionNegative,
  };
}

/// One data-driven Practice domain validation problem.
///
/// [code] is stable and machine-readable. [message] is a human-readable
/// diagnostic for developers and adapters; presentation layers localize by
/// [code] instead of displaying this text directly.
final class PracticeValidationFailure {
  const PracticeValidationFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is PracticeValidationFailure &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() =>
      'PracticeValidationFailure(code: $code, message: $message)';
}
