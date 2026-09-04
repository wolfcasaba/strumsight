import 'package:meta/meta.dart';

import '../../model/recognition_runtime_info.dart';
import 'chord_prediction.dart';
import 'signal_quality_snapshot.dart';
import 'strum_prediction.dart';

/// The versioned, Flutter-independent felismerési szerződés (SDD Ch14 Kör 4,
/// ADR 0505): the chord- and direction-confidence are carried SEPARATELY
/// ([chord]/[strum]), so the UI can distinguish a confident, an uncertain,
/// a provisional and a rejected recognition instead of the old binary
/// latch. `LiveFrameAdapter` translates this to/from the legacy `LiveFrame`
/// so the 22 existing callers stay untouched (ADR 0505 D5).
@immutable
class RecognitionFrame {
  const RecognitionFrame({
    required this.frameTimeSec,
    required this.runtimeInfo,
    this.strum,
    this.chord,
    this.signalQuality = SignalQualitySnapshot.unknown,
    this.schemaVersion = currentSchemaVersion,
  });

  /// The only schema version this build understands (ADR 0505 D6). An
  /// unknown `schemaVersion` in [fromJson] is a typed error, never a
  /// "best effort" partial read.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;

  /// This frame's emit instant on the engine's own sample clock (seconds).
  final double frameTimeSec;

  /// The latest strum-direction verdict, or `null` before the engine has
  /// produced one.
  final StrumPrediction? strum;

  /// The latest chord verdict, or `null` before the engine has produced one.
  final ChordPrediction? chord;

  /// The Live audio-quality pillanatkép — `SignalQualitySnapshot.unknown`
  /// until `E14-R05` fills it in.
  final SignalQualitySnapshot signalQuality;

  /// Which model/engine combination produced this frame (`E14-R03`) —
  /// referenced here, not redefined.
  final RecognitionRuntimeInfo runtimeInfo;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'frameTimeSec': frameTimeSec,
    'strum': strum?.toJson(),
    'chord': chord?.toJson(),
    'signalQuality': signalQuality.toJson(),
    'runtimeInfo': runtimeInfo.toJson(),
  };

  /// Decodes without guessing a safe fallback — a missing required key, a
  /// wrong-typed value, or an unknown [schemaVersion] is a typed
  /// [ArgumentError], never a silent `null` or a partial object (ADR 0505
  /// D6, `docs/LESSONS.md` L619). [strum]/[chord] are optional keys (their
  /// value may be `null`); every other key is required.
  factory RecognitionFrame.fromJson(Object? json) {
    final object = _requireObject(json, 'json');
    final schemaVersion = _requireInt(object, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'is not a supported RecognitionFrame schema version',
      );
    }
    return RecognitionFrame(
      schemaVersion: schemaVersion,
      frameTimeSec: _requireDouble(object, 'frameTimeSec'),
      strum: _requireKey(object, 'strum') == null
          ? null
          : StrumPrediction.fromJson(object['strum']),
      chord: _requireKey(object, 'chord') == null
          ? null
          : ChordPrediction.fromJson(object['chord']),
      signalQuality: SignalQualitySnapshot.fromJson(
        _requireKey(object, 'signalQuality'),
      ),
      runtimeInfo: RecognitionRuntimeInfo.fromJson(
        _requireObject(_requireKey(object, 'runtimeInfo'), 'runtimeInfo'),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecognitionFrame &&
          other.schemaVersion == schemaVersion &&
          other.frameTimeSec == frameTimeSec &&
          other.strum == strum &&
          other.chord == chord &&
          other.signalQuality == signalQuality &&
          other.runtimeInfo == runtimeInfo;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    frameTimeSec,
    strum,
    chord,
    signalQuality,
    runtimeInfo,
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

/// Requires the KEY to be present and returns its raw value — distinct from
/// treating a missing key the same as an explicit `null` (the L619 fail-open
/// class this round guards against).
Object? _requireKey(Map<String, Object?> object, String field) {
  if (!object.containsKey(field)) {
    throw ArgumentError.value(null, field, 'is required (key missing)');
  }
  return object[field];
}
