import 'package:meta/meta.dart';

/// Closed set of Live audio-quality states (`E14-R05` fills these in;
/// this round only ships the shape). Never a source/person/skill
/// classifier — audio quality only (ADR 0224 §4 boundary, carried into
/// ADR 0505).
enum SignalQualityState {
  good,
  tooQuiet,
  tooLoud,
  clipping,
  tooNoisy,
  speechLike,
  unstable,

  /// Not enough data yet (buffer filling, session start) — a real state,
  /// never silently defaulted to [good] (ADR 0271 §1).
  unknown;

  /// The wire form used by `SignalQualitySnapshot.toJson`.
  String toJson() => name;

  /// Decodes a persisted state without guessing a safe fallback — an
  /// unrecognised name is a typed error, never a silent `null` (ADR 0505 D6).
  static SignalQualityState fromJson(Object? value) {
    if (value is! String) {
      throw ArgumentError.value(value, 'state', 'must be a string');
    }
    for (final state in SignalQualityState.values) {
      if (state.name == value) return state;
    }
    throw ArgumentError.value(value, 'state', 'is not a supported value');
  }
}

/// A Live audio-quality pillanatkép — Flutter-independent (ADR 0505 D1).
///
/// This round ships ONLY the contract: every metric is `null` and [state]
/// is [SignalQualityState.unknown] by default (see [SignalQualitySnapshot.unknown]).
/// `E14-R05` is the round that measures and fills these in with the
/// existing `signal_quality_math` primitives — no DSP math is implemented
/// here.
@immutable
class SignalQualitySnapshot {
  const SignalQualitySnapshot({
    this.state = SignalQualityState.unknown,
    this.peakDbfs,
    this.rmsDbfs,
    this.noiseFloorDbfs,
    this.clippedSampleRatio,
    this.silentRatio,
    this.activeRegionRatio,
    this.tonalness,
  });

  /// The canonical "no measurement yet" shape — every metric `null`, state
  /// [SignalQualityState.unknown]. The one place every "not measured yet"
  /// caller should build its snapshot from.
  static const unknown = SignalQualitySnapshot();

  final SignalQualityState state;

  /// Peak level in dBFS, or `null` while unmeasured.
  final double? peakDbfs;

  /// RMS level in dBFS, or `null` while unmeasured.
  final double? rmsDbfs;

  /// Noise-floor proxy in dBFS, or `null` while unmeasured.
  final double? noiseFloorDbfs;

  /// Fraction of samples at/above the clipping threshold, or `null` while
  /// unmeasured.
  final double? clippedSampleRatio;

  /// Fraction of frames classified silent, or `null` while unmeasured.
  final double? silentRatio;

  /// Fraction of frames classified active (`1 - silentRatio`), or `null`
  /// while unmeasured.
  final double? activeRegionRatio;

  /// Spectral tonalness proxy (0 noise-like .. 1 tone-like), or `null`
  /// while unmeasured.
  final double? tonalness;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.toJson(),
    'peakDbfs': peakDbfs,
    'rmsDbfs': rmsDbfs,
    'noiseFloorDbfs': noiseFloorDbfs,
    'clippedSampleRatio': clippedSampleRatio,
    'silentRatio': silentRatio,
    'activeRegionRatio': activeRegionRatio,
    'tonalness': tonalness,
  };

  /// Decodes without guessing a safe fallback — a missing required key
  /// ([state]) or a wrong-typed value is a typed [ArgumentError], never a
  /// silent `null` or a partial object (ADR 0505 D6, `docs/LESSONS.md` L619).
  /// The optional metric keys must still be PRESENT (value may be `null`).
  factory SignalQualitySnapshot.fromJson(Object? json) {
    final object = _requireObject(json, 'json');
    return SignalQualitySnapshot(
      state: SignalQualityState.fromJson(_requireKey(object, 'state')),
      peakDbfs: _requireNullableDouble(object, 'peakDbfs'),
      rmsDbfs: _requireNullableDouble(object, 'rmsDbfs'),
      noiseFloorDbfs: _requireNullableDouble(object, 'noiseFloorDbfs'),
      clippedSampleRatio: _requireNullableDouble(object, 'clippedSampleRatio'),
      silentRatio: _requireNullableDouble(object, 'silentRatio'),
      activeRegionRatio: _requireNullableDouble(object, 'activeRegionRatio'),
      tonalness: _requireNullableDouble(object, 'tonalness'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalQualitySnapshot &&
          other.state == state &&
          other.peakDbfs == peakDbfs &&
          other.rmsDbfs == rmsDbfs &&
          other.noiseFloorDbfs == noiseFloorDbfs &&
          other.clippedSampleRatio == clippedSampleRatio &&
          other.silentRatio == silentRatio &&
          other.activeRegionRatio == activeRegionRatio &&
          other.tonalness == tonalness;

  @override
  int get hashCode => Object.hash(
    state,
    peakDbfs,
    rmsDbfs,
    noiseFloorDbfs,
    clippedSampleRatio,
    silentRatio,
    activeRegionRatio,
    tonalness,
  );
}

Map<String, Object?> _requireObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw ArgumentError.value(value, field, 'must be an object');
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

double? _requireNullableDouble(Map<String, Object?> object, String field) {
  if (!object.containsKey(field)) {
    throw ArgumentError.value(null, field, 'is required (key missing)');
  }
  final value = object[field];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw ArgumentError.value(value, field, 'must be null or a number');
}
