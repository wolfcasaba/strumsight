import 'package:meta/meta.dart';

import 'recognition_decision.dart';

/// One strum-direction model verdict — Flutter-independent (ADR 0505 D1),
/// so it stays const/final-immutable without `package:flutter/foundation.dart`.
@immutable
class StrumPrediction {
  const StrumPrediction({
    required this.onsetTimeSec,
    required this.verdictTimeSec,
    required this.pDown,
    required this.pUp,
    required this.pNoStrum,
    required this.calibratedConfidence,
    required this.modelId,
  });

  /// The strum's attack instant on the engine's own sample clock (seconds).
  final double onsetTimeSec;

  /// When the model produced its verdict for this strum (seconds).
  final double verdictTimeSec;

  /// Raw model probability the strum was a downstroke — NOT a confidence
  /// (ADR 0505 D2).
  final double pDown;

  /// Raw model probability the strum was an upstroke — NOT a confidence
  /// (ADR 0505 D2).
  final double pUp;

  /// Raw model probability there was no strum at all — NOT a confidence
  /// (ADR 0505 D2).
  final double pNoStrum;

  /// `null` until a MEASURED calibration exists (ADR 0505 D2) — never the
  /// raw [pDown]/[pUp] copied in "temporarily". A `null` here means the
  /// domain doesn't know, which is more information than a made-up number.
  final double? calibratedConfidence;

  /// Which strum-direction model produced this verdict.
  final String modelId;

  /// `|pDown − pUp|`, computed — never a constructor parameter, so it can
  /// never drift from [pDown]/[pUp] into an inconsistent state (ADR 0505 D4).
  double get directionMargin => (pDown - pUp).abs();

  /// The contract's default rejection-side-inclusive margin threshold
  /// (`margin <= 0.05` → [RecognitionDecision.uncertain]). This is the
  /// SHIPPED default, not a hand-tuned DSP constant — a later, measured
  /// calibration round may override it with an ADR (ADR 0505 D4).
  static const double uncertainMarginThreshold = 0.05;

  /// The ONLY derivation this round performs (ADR 0505 D3/R7): the direction
  /// verdict from [directionMargin] against [uncertainMarginThreshold],
  /// inclusive on the rejection side.
  RecognitionDecision get decision =>
      directionMargin <= uncertainMarginThreshold
      ? RecognitionDecision.uncertain
      : RecognitionDecision.confirmed;

  Map<String, Object?> toJson() => <String, Object?>{
    'onsetTimeSec': onsetTimeSec,
    'verdictTimeSec': verdictTimeSec,
    'pDown': pDown,
    'pUp': pUp,
    'pNoStrum': pNoStrum,
    'calibratedConfidence': calibratedConfidence,
    'directionMargin': directionMargin,
    'modelId': modelId,
    'decision': decision.toJson(),
  };

  /// Decodes without guessing a safe fallback — a missing required key or a
  /// wrong-typed value is a typed [ArgumentError], never a silent `null` or
  /// a partial object (ADR 0505 D6, `docs/LESSONS.md` L619). [directionMargin]
  /// and [decision] are NOT read back: they are re-derived from [pDown]/[pUp],
  /// so a round-trip stays a fixed point without trusting stale wire data.
  factory StrumPrediction.fromJson(Object? json) {
    final object = _requireObject(json, 'json');
    return StrumPrediction(
      onsetTimeSec: _requireDouble(object, 'onsetTimeSec'),
      verdictTimeSec: _requireDouble(object, 'verdictTimeSec'),
      pDown: _requireDouble(object, 'pDown'),
      pUp: _requireDouble(object, 'pUp'),
      pNoStrum: _requireDouble(object, 'pNoStrum'),
      calibratedConfidence: _requireNullableDouble(
        object,
        'calibratedConfidence',
      ),
      modelId: _requireString(object, 'modelId'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrumPrediction &&
          other.onsetTimeSec == onsetTimeSec &&
          other.verdictTimeSec == verdictTimeSec &&
          other.pDown == pDown &&
          other.pUp == pUp &&
          other.pNoStrum == pNoStrum &&
          other.calibratedConfidence == calibratedConfidence &&
          other.modelId == modelId;

  @override
  int get hashCode => Object.hash(
    onsetTimeSec,
    verdictTimeSec,
    pDown,
    pUp,
    pNoStrum,
    calibratedConfidence,
    modelId,
  );
}

Map<String, Object?> _requireObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw ArgumentError.value(value, field, 'must be an object');
}

double _requireDouble(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is num) return value.toDouble();
  throw ArgumentError.value(value, field, 'must be a number');
}

String _requireString(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

/// Requires the KEY to be present (nullable value allowed) — distinct from
/// treating a missing key the same as an explicit `null` (the L619 fail-open
/// class this round guards against).
double? _requireNullableDouble(Map<String, Object?> object, String field) {
  if (!object.containsKey(field)) {
    throw ArgumentError.value(null, field, 'is required (key missing)');
  }
  final value = object[field];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw ArgumentError.value(value, field, 'must be null or a number');
}
