import 'package:meta/meta.dart';

import 'recognition_decision.dart';

/// One chord-recognition engine verdict — Flutter-independent (ADR 0505 D1).
///
/// Unlike [StrumPrediction], [decision] is constructor-received this round,
/// not derived: deriving a chord verdict without a MEASURED calibration
/// would be exactly the hazugság ADR 0505 D2 forbids. A calibrated chord
/// derivation ships in `E14-R05`/`E14-R11`.
@immutable
class ChordPrediction {
  const ChordPrediction({
    required this.label,
    required this.root,
    required this.quality,
    required this.pNoChord,
    required this.pUnknown,
    required this.calibratedConfidence,
    required this.stabilityFrames,
    required this.sourceEngine,
    required this.decision,
  });

  /// Human display label, e.g. "Am", "F#m7" — same shape as the legacy
  /// `Chord.label`.
  final String label;

  /// The chord's root pitch class, e.g. "A", "F#".
  final String root;

  /// The chord's quality suffix, e.g. "maj", "min7".
  final String quality;

  /// Raw model probability there was no chord at all — NOT a confidence
  /// (ADR 0505 D2).
  final double pNoChord;

  /// Raw model probability the chord couldn't be classified — NOT a
  /// confidence (ADR 0505 D2).
  final double pUnknown;

  /// `null` until a MEASURED calibration exists (ADR 0505 D2) — never a
  /// raw probability copied in "temporarily".
  final double? calibratedConfidence;

  /// How many consecutive frames agreed on this verdict.
  final int stabilityFrames;

  /// Which chord-recognition engine produced this verdict, e.g.
  /// `RecognitionRuntimeInfo.chordEngineNnlsViterbi`.
  final String sourceEngine;

  /// Constructor-received this round (see class doc) — the domain still
  /// owns the decision, the widget layer still only displays it.
  final RecognitionDecision decision;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'root': root,
    'quality': quality,
    'pNoChord': pNoChord,
    'pUnknown': pUnknown,
    'calibratedConfidence': calibratedConfidence,
    'stabilityFrames': stabilityFrames,
    'sourceEngine': sourceEngine,
    'decision': decision.toJson(),
  };

  /// Decodes without guessing a safe fallback — a missing required key or a
  /// wrong-typed value is a typed [ArgumentError], never a silent `null` or
  /// a partial object (ADR 0505 D6, `docs/LESSONS.md` L619).
  factory ChordPrediction.fromJson(Object? json) {
    final object = _requireObject(json, 'json');
    return ChordPrediction(
      label: _requireString(object, 'label'),
      root: _requireString(object, 'root'),
      quality: _requireString(object, 'quality'),
      pNoChord: _requireDouble(object, 'pNoChord'),
      pUnknown: _requireDouble(object, 'pUnknown'),
      calibratedConfidence: _requireNullableDouble(
        object,
        'calibratedConfidence',
      ),
      stabilityFrames: _requireInt(object, 'stabilityFrames'),
      sourceEngine: _requireString(object, 'sourceEngine'),
      decision: RecognitionDecision.fromJson(object['decision']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChordPrediction &&
          other.label == label &&
          other.root == root &&
          other.quality == quality &&
          other.pNoChord == pNoChord &&
          other.pUnknown == pUnknown &&
          other.calibratedConfidence == calibratedConfidence &&
          other.stabilityFrames == stabilityFrames &&
          other.sourceEngine == sourceEngine &&
          other.decision == decision;

  @override
  int get hashCode => Object.hash(
    label,
    root,
    quality,
    pNoChord,
    pUnknown,
    calibratedConfidence,
    stabilityFrames,
    sourceEngine,
    decision,
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

int _requireInt(Map<String, Object?> object, String field) {
  final value = object[field];
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an integer');
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
