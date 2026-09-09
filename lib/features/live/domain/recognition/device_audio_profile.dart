import 'package:meta/meta.dart';

/// What ONE device's audio input needs to reach the nominal recording level
/// (E14-R31, ADR 0552 D4) — a purely technical audio-route description, in
/// the same spirit as `SignalQualitySnapshot`: never a person, a room, a
/// skill or a location classifier (ADR 0224 §4 boundary).
///
/// **This file is the CONSUMER seam only.** The intended producer is the
/// audio-setup wizard (E14-R14): it measures a phone once and stores the
/// result. Nothing in this round writes a profile — the shipped value is
/// [DeviceAudioProfile.identity], which changes no sample.
///
/// Both numbers are honest about absence:
///
/// * [inputGainOffsetDb] is `0` for the identity profile, i.e. "no
///   correction is known", never "this device needs no correction".
/// * [noiseFloorDbfs] is `null` until something MEASURES it — it is never
///   defaulted to a plausible-looking dBFS value (ADR 0271 §1).
@immutable
class DeviceAudioProfile {
  const DeviceAudioProfile._({
    required this.profileId,
    required this.inputGainOffsetDb,
    required this.noiseFloorDbfs,
  });

  /// The shipped profile: no correction, no measured noise floor. A
  /// preprocessing stage handed this profile can only ever act on the live
  /// `SignalQualitySnapshot`, never on a per-device number.
  const DeviceAudioProfile.identity()
    : this._(
        profileId: identityProfileId,
        inputGainOffsetDb: 0,
        noiseFloorDbfs: null,
      );

  /// A profile produced by an actual measurement (the audio-setup wizard).
  ///
  /// Fails loudly rather than clamping: a wizard that computed a NaN or a
  /// 40 dB offset has a bug, and silently accepting it would push the bug
  /// into the DSP path where it looks like a detection regression.
  factory DeviceAudioProfile.measured({
    required String profileId,
    required double inputGainOffsetDb,
    double? noiseFloorDbfs,
  }) {
    if (profileId.trim().isEmpty) {
      throw ArgumentError.value(profileId, 'profileId', 'must not be empty');
    }
    if (!inputGainOffsetDb.isFinite ||
        inputGainOffsetDb.abs() > maxInputGainOffsetDb) {
      throw ArgumentError.value(
        inputGainOffsetDb,
        'inputGainOffsetDb',
        'must be finite and within ±$maxInputGainOffsetDb dB',
      );
    }
    if (noiseFloorDbfs != null &&
        (!noiseFloorDbfs.isFinite || noiseFloorDbfs > 0)) {
      throw ArgumentError.value(
        noiseFloorDbfs,
        'noiseFloorDbfs',
        'must be finite and at or below 0 dBFS',
      );
    }
    return DeviceAudioProfile._(
      profileId: profileId,
      inputGainOffsetDb: inputGainOffsetDb,
      noiseFloorDbfs: noiseFloorDbfs,
    );
  }

  /// The id of [DeviceAudioProfile.identity].
  static const String identityProfileId = 'identity';

  /// Hard bound on a stored per-device correction.
  ///
  /// **UNMEASURED default** (ADR 0552 D6): no device A/B exists yet (plan
  /// §2 R31 needs 5+ phones). It is a SAFETY bound, not a tuning: ±12 dB is
  /// a factor of 4 in amplitude, past which a "correction" would be
  /// amplifying the device's own noise floor as hard as the guitar. A
  /// measurement may narrow it; nothing may widen it without one.
  static const double maxInputGainOffsetDb = 12;

  /// Stable id of the measurement that produced this profile (a wizard run
  /// id, not a device fingerprint — this type must not become a way to
  /// identify a phone).
  final String profileId;

  /// Gain, in dB, to ADD to this device's captured signal to bring it to the
  /// nominal level. Positive = this device records quietly. `0` on the
  /// identity profile.
  final double inputGainOffsetDb;

  /// Measured noise floor of this device's capture path in dBFS, or `null`
  /// when nothing has measured it. Read-only context for a future
  /// noise-aware adaptation; this round only carries it.
  final double? noiseFloorDbfs;

  /// `true` when applying this profile is a no-op by construction.
  bool get isIdentity => inputGainOffsetDb == 0 && noiseFloorDbfs == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'profileId': profileId,
    'inputGainOffsetDb': inputGainOffsetDb,
    'noiseFloorDbfs': noiseFloorDbfs,
  };

  /// Decodes without guessing a safe fallback — a missing key or a
  /// wrong-typed value is a typed [ArgumentError], and the range checks of
  /// [DeviceAudioProfile.measured] apply to persisted data too
  /// (`docs/LESSONS.md` L619).
  factory DeviceAudioProfile.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw ArgumentError.value(json, 'json', 'must be an object');
    }
    for (final key in const ['profileId', 'inputGainOffsetDb']) {
      if (!json.containsKey(key)) {
        throw ArgumentError.value(null, key, 'is required (key missing)');
      }
    }
    if (!json.containsKey('noiseFloorDbfs')) {
      throw ArgumentError.value(
        null,
        'noiseFloorDbfs',
        'is required (key missing)',
      );
    }
    final profileId = json['profileId'];
    if (profileId is! String) {
      throw ArgumentError.value(profileId, 'profileId', 'must be a string');
    }
    final offset = json['inputGainOffsetDb'];
    if (offset is! num) {
      throw ArgumentError.value(
        offset,
        'inputGainOffsetDb',
        'must be a number',
      );
    }
    final floor = json['noiseFloorDbfs'];
    if (floor != null && floor is! num) {
      throw ArgumentError.value(
        floor,
        'noiseFloorDbfs',
        'must be null or a number',
      );
    }
    // No special case for [identityProfileId]: `measured` accepts the same
    // values and equality is by field, so the round trip is a fixed point.
    return DeviceAudioProfile.measured(
      profileId: profileId,
      inputGainOffsetDb: offset.toDouble(),
      noiseFloorDbfs: (floor as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeviceAudioProfile &&
          other.profileId == profileId &&
          other.inputGainOffsetDb == inputGainOffsetDb &&
          other.noiseFloorDbfs == noiseFloorDbfs;

  @override
  int get hashCode => Object.hash(profileId, inputGainOffsetDb, noiseFloorDbfs);

  @override
  String toString() =>
      'DeviceAudioProfile($profileId, ${inputGainOffsetDb}dB, '
      'floor: $noiseFloorDbfs)';
}
