import 'package:meta/meta.dart';

import '../../live/public.dart';

/// A single device+mic-route specific snapshot from an automatic
/// audio-setup run (ADR 0519). This is INPUT to the decision layer — it
/// never overwrites a shipping DSP/ML constant and carries no classifier
/// threshold (D1).
///
/// [micRouteId] and [sampleRateHz] are the environment the profile was
/// captured under; [isStaleFor] is how a reader decides the profile no
/// longer describes today's environment (D3).
@immutable
class AudioProfile {
  const AudioProfile({
    required this.schemaVersion,
    required this.micRouteId,
    required this.sampleRateHz,
    required this.suggestedInputGainDb,
    required this.inputLatencyMsAtCapture,
    required this.visualLatencyMsAtCapture,
    required this.qualityExpectation,
    required this.confidenceProfile,
    required this.recordedAt,
  });

  /// The schema version this build writes and reads natively. Bump this and
  /// add a migration branch in [decode] whenever the shape changes — an
  /// unrecognised version is a typed [ArgumentError], never a default
  /// profile or a silent `null` (ADR 0519 D5).
  static const int currentSchemaVersion = 1;

  /// The only supported legacy version [decode] migrates forward from.
  static const int _legacySchemaVersionV0 = 0;

  final int schemaVersion;

  /// The mic-route identifier active when this profile was captured (the
  /// platform's current audio-route descriptor). Opaque to this layer —
  /// used only for equality against the live route in [isStaleFor].
  final String micRouteId;

  /// The sample rate (Hz) active when this profile was captured.
  final int sampleRateHz;

  /// A heuristic input-gain suggestion in dB, derived from the run's
  /// strum/chord peak levels — informational only, never applied to any
  /// DSP/ML constant (D1).
  final double suggestedInputGainDb;

  /// The Settings input/visual latency values (ms) in effect when this run
  /// was captured — carried alongside them, never replacing them (D1; see
  /// `lib/features/settings/providers/input_latency_provider.dart` and
  /// `visual_latency_provider.dart`, which this profile does not import or
  /// override).
  final int inputLatencyMsAtCapture;
  final int visualLatencyMsAtCapture;

  /// The overall [SignalQualityState] the run measured. A `success` outcome
  /// is only ever built with [SignalQualityState.good] here (D2).
  final SignalQualityState qualityExpectation;

  /// Fraction (0.0–1.0) of the run's steps that read
  /// [SignalQualityState.good] — the user's own confidence profile from
  /// this run, never a classifier threshold (D1).
  final double confidenceProfile;

  final DateTime recordedAt;

  /// True when [currentMicRouteId] or [currentSampleRateHz] differs from
  /// the environment this profile was captured under (D3) — a stale
  /// profile must never be handed back as valid by a reader.
  bool isStaleFor({
    required String currentMicRouteId,
    required int currentSampleRateHz,
  }) => currentMicRouteId != micRouteId || currentSampleRateHz != sampleRateHz;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': currentSchemaVersion,
    'micRouteId': micRouteId,
    'sampleRateHz': sampleRateHz,
    'suggestedInputGainDb': suggestedInputGainDb,
    'inputLatencyMsAtCapture': inputLatencyMsAtCapture,
    'visualLatencyMsAtCapture': visualLatencyMsAtCapture,
    'qualityExpectation': qualityExpectation.toJson(),
    'confidenceProfile': confidenceProfile,
    'recordedAt': recordedAt.toIso8601String(),
  };

  /// Decodes a persisted blob, migrating the supported legacy schema
  /// forward first. An unrecognised `schemaVersion` is a typed
  /// [ArgumentError] — never a default profile, never `null` (D5).
  factory AudioProfile.decode(Object? raw) {
    final object = _requireObject(raw);
    final version = _requireInt(object, 'schemaVersion');
    if (version == currentSchemaVersion) {
      return _decodeCurrent(object);
    }
    if (version == _legacySchemaVersionV0) {
      return _decodeCurrent(_migrateV0ToV1(object));
    }
    throw ArgumentError.value(
      version,
      'schemaVersion',
      'is not a supported value',
    );
  }

  static AudioProfile _decodeCurrent(Map<String, Object?> object) {
    return AudioProfile(
      schemaVersion: currentSchemaVersion,
      micRouteId: _requireString(object, 'micRouteId'),
      sampleRateHz: _requireInt(object, 'sampleRateHz'),
      suggestedInputGainDb: _requireDouble(object, 'suggestedInputGainDb'),
      inputLatencyMsAtCapture: _requireInt(object, 'inputLatencyMsAtCapture'),
      visualLatencyMsAtCapture: _requireInt(object, 'visualLatencyMsAtCapture'),
      qualityExpectation: SignalQualityState.fromJson(
        _requireKey(object, 'qualityExpectation'),
      ),
      confidenceProfile: _requireDouble(object, 'confidenceProfile'),
      recordedAt: DateTime.parse(_requireString(object, 'recordedAt')),
    );
  }

  /// Renames the legacy (pre-shipping prototype) v0 field names onto the
  /// current shape and converts its epoch-ms timestamp to ISO-8601 — no
  /// field is dropped (L70: a missing field on migration is real data
  /// loss, not acceptable normalisation).
  static Map<String, Object?> _migrateV0ToV1(Map<String, Object?> legacy) {
    final recordedAtMs = _requireInt(legacy, 'recordedAtEpochMs');
    return <String, Object?>{
      'schemaVersion': currentSchemaVersion,
      'micRouteId': _requireString(legacy, 'route'),
      'sampleRateHz': _requireInt(legacy, 'sampleRate'),
      'suggestedInputGainDb': _requireDouble(legacy, 'gainDb'),
      'inputLatencyMsAtCapture': _requireInt(legacy, 'inputLatencyMs'),
      'visualLatencyMsAtCapture': _requireInt(legacy, 'visualLatencyMs'),
      'qualityExpectation': _requireKey(legacy, 'quality'),
      'confidenceProfile': _requireDouble(legacy, 'confidence'),
      'recordedAt': DateTime.fromMillisecondsSinceEpoch(
        recordedAtMs,
        isUtc: true,
      ).toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioProfile &&
          other.schemaVersion == schemaVersion &&
          other.micRouteId == micRouteId &&
          other.sampleRateHz == sampleRateHz &&
          other.suggestedInputGainDb == suggestedInputGainDb &&
          other.inputLatencyMsAtCapture == inputLatencyMsAtCapture &&
          other.visualLatencyMsAtCapture == visualLatencyMsAtCapture &&
          other.qualityExpectation == qualityExpectation &&
          other.confidenceProfile == confidenceProfile &&
          other.recordedAt == recordedAt;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    micRouteId,
    sampleRateHz,
    suggestedInputGainDb,
    inputLatencyMsAtCapture,
    visualLatencyMsAtCapture,
    qualityExpectation,
    confidenceProfile,
    recordedAt,
  );
}

Map<String, Object?> _requireObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw ArgumentError.value(value, 'json', 'must be an object');
}

/// Requires the KEY to be present and returns its raw value — distinct from
/// treating a missing key the same as an explicit `null`.
Object? _requireKey(Map<String, Object?> object, String field) {
  if (!object.containsKey(field)) {
    throw ArgumentError.value(null, field, 'is required (key missing)');
  }
  return object[field];
}

String _requireString(Map<String, Object?> object, String field) {
  final value = _requireKey(object, field);
  if (value is String) return value;
  throw ArgumentError.value(value, field, 'must be a string');
}

int _requireInt(Map<String, Object?> object, String field) {
  final value = _requireKey(object, field);
  if (value is int) return value;
  throw ArgumentError.value(value, field, 'must be an int');
}

double _requireDouble(Map<String, Object?> object, String field) {
  final value = _requireKey(object, field);
  if (value is num) return value.toDouble();
  throw ArgumentError.value(value, field, 'must be a number');
}
