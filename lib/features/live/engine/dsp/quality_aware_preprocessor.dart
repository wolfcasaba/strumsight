/// Quality-aware input preprocessing for the Live DSP path (E14-R31,
/// ADR 0552).
///
/// This file ships a MECHANISM, not a tuning. It consumes the snapshot the
/// already-shipped `LiveSignalQualityAnalyzer` produces (E14-R05, ADR 0507)
/// and applies ONE conservative, reversible adaptation: a bounded, slewed
/// broadband gain that moves the input's RMS towards a target level. It
/// changes NO existing threshold — not one value in `DspConfig`, not one in
/// `LiveQualityThresholds`.
///
/// Four properties are structural here, not conventions:
///
/// 1. **Off by default, bit-identical when off.** With
///    `LivePreprocessingConfig.disabled` (the shipped state, gated by the
///    `recognitionPreprocessingEnabled` flag) [QualityAwarePreprocessor]
///    returns the caller's list INSTANCE — not a copy, not a rebuilt list —
///    so the DSP path downstream cannot even observe that the stage exists.
/// 2. **Never on `clipping`.** A clipped signal has already lost the
///    samples that were cut; boosting it amplifies the damage and cutting
///    it cannot restore it. The clipping state HOLDS the gain where it is
///    instead of reacting to it (ADR 0552 D3).
/// 3. **Never fabricates a measurement.** A `null` `rmsDbfs`/`peakDbfs` —
///    the analyzer's honest "not measured yet" — yields no level adaptation
///    at all, rather than a plausible-looking default (ADR 0271 §1).
/// 4. **Reversible and observable.** The transform is a single scalar gain
///    per chunk, reported by [QualityAwarePreprocessor.appliedGainDb]; the
///    only lossy step, the ±1.0 safety clamp, is COUNTED
///    ([QualityAwarePreprocessor.clampedSampleCount]) so it can never be a
///    silent no-op.
///
/// **Every number below is an UNMEASURED default** (ADR 0552 D6). The
/// device A/B this round would need — 5+ phones, plan §2 R31 — is human +
/// hardware work no test on this tree can stand in for. The constants are
/// stated, sourced and bounded in
/// `docs/rag/chunks/023-input-preprocessing.md`; they are safety envelopes,
/// not fitted values.
library;

import 'dart:math' as math;

import '../../domain/recognition/device_audio_profile.dart';
import '../../domain/recognition/signal_quality_snapshot.dart';

/// What the stage did to the most recent chunk.
enum LivePreprocessingAdaptation {
  /// The stage is switched off (the shipped state) — output is the input
  /// instance.
  disabled,

  /// Enabled, but nothing has been processed since construction or
  /// [QualityAwarePreprocessor.reset] — no decision has been made yet.
  identity,

  /// Enabled and the level was normalised towards
  /// [LivePreprocessingConfig.targetRmsDbfs].
  levelNormalised,

  /// Enabled, but the state is not a LEVEL state (or carries no level
  /// measurement), so only the device profile's offset could apply.
  deviceOffsetOnly,

  /// Enabled, and the input is CLIPPING: the gain is held at its current
  /// value and no new level adaptation is computed (ADR 0552 D3).
  clippingHold,
}

/// Versioned, immutable policy for [QualityAwarePreprocessor].
///
/// [LivePreprocessingConfig.disabled] is the shipped value and the
/// one-switch rollback: the `recognitionPreprocessingEnabled` feature flag
/// (ADR 0542, owned by `lib/app/config/feature_flags.dart`) chooses between
/// the two const constructors, so turning the path off is a flag flip, not
/// a release.
final class LivePreprocessingConfig {
  const LivePreprocessingConfig._({
    required this.enabled,
    required this.targetRmsDbfs,
    required this.maxBoostDb,
    required this.maxCutDb,
    required this.maxGainStepDb,
    required this.peakHeadroomDb,
  });

  /// The SHIPPED policy: the stage is inert and the DSP path sees the exact
  /// input instance.
  const LivePreprocessingConfig.disabled()
    : this._(
        enabled: false,
        targetRmsDbfs: defaultTargetRmsDbfs,
        maxBoostDb: defaultMaxBoostDb,
        maxCutDb: defaultMaxCutDb,
        maxGainStepDb: defaultMaxGainStepDb,
        peakHeadroomDb: defaultPeakHeadroomDb,
      );

  /// The enabled policy with the UNMEASURED defaults documented below.
  const LivePreprocessingConfig.standard()
    : this._(
        enabled: true,
        targetRmsDbfs: defaultTargetRmsDbfs,
        maxBoostDb: defaultMaxBoostDb,
        maxCutDb: defaultMaxCutDb,
        maxGainStepDb: defaultMaxGainStepDb,
        peakHeadroomDb: defaultPeakHeadroomDb,
      );

  /// A policy with explicit numbers — for this round's own tests and for
  /// the device A/B once someone can run it. Every bound is validated: an
  /// out-of-range sweep point fails loudly instead of quietly disabling
  /// itself.
  factory LivePreprocessingConfig.tuned({
    required double targetRmsDbfs,
    required double maxBoostDb,
    required double maxCutDb,
    required double maxGainStepDb,
    double peakHeadroomDb = defaultPeakHeadroomDb,
  }) {
    void requireRange(double value, String name, double min, double max) {
      if (!value.isFinite || value < min || value > max) {
        throw ArgumentError.value(
          value,
          name,
          'must be finite and within $min..$max',
        );
      }
    }

    requireRange(targetRmsDbfs, 'targetRmsDbfs', -60, 0);
    requireRange(maxBoostDb, 'maxBoostDb', 0, absoluteGainLimitDb);
    requireRange(maxCutDb, 'maxCutDb', 0, absoluteGainLimitDb);
    requireRange(maxGainStepDb, 'maxGainStepDb', 0.01, absoluteGainLimitDb);
    requireRange(peakHeadroomDb, 'peakHeadroomDb', 0, 24);
    return LivePreprocessingConfig._(
      enabled: true,
      targetRmsDbfs: targetRmsDbfs,
      maxBoostDb: maxBoostDb,
      maxCutDb: maxCutDb,
      maxGainStepDb: maxGainStepDb,
      peakHeadroomDb: peakHeadroomDb,
    );
  }

  /// Bumped whenever the MECHANISM changes, so a recorded measurement can
  /// name the stage that produced it. Not a tuning version.
  static const String version = 'live-preprocessing-v1';

  /// Target input RMS, in dBFS.
  ///
  /// **UNMEASURED** (ADR 0552 D6). A derivation, not a fit: the shipped
  /// quality gates call a block quiet at or below −40 dBFS RMS and loud at
  /// or above −2 dBFS PEAK (`LiveQualityThresholds.standard.quietRmsDbfs`
  /// and `.loudPeakDbfs`), so −21 dBFS is the midpoint of that usable
  /// window — 19 dB above the quiet gate and, at a typical ~12 dB guitar
  /// crest factor, still ~7 dB of peak below the loud gate. It is
  /// deliberately NOT read from `LiveQualityThresholds` at compile time:
  /// this stage must never become a back door that retunes the quality
  /// gates.
  static const double defaultTargetRmsDbfs = -21;

  /// Largest boost the stage may ever apply. **UNMEASURED** safety bound:
  /// +12 dB is a 4× amplitude scale, past which the device's own noise
  /// floor rises as fast as the guitar and the "help" is a hindrance.
  static const double defaultMaxBoostDb = 12;

  /// Largest cut the stage may ever apply. **UNMEASURED** safety bound,
  /// symmetric with [defaultMaxBoostDb].
  static const double defaultMaxCutDb = 12;

  /// Largest change of the applied gain from one chunk to the next.
  ///
  /// **UNMEASURED** (ADR 0552 D6). A gain that jumped between chunks would
  /// put a step discontinuity at the chunk boundary, and a step is exactly
  /// what the spectral-flux onset detector is built to find — a phantom
  /// strum. 1.5 dB per chunk keeps that step an order of magnitude below a
  /// real guitar attack, and at a ~23 ms mic chunk it still traverses the
  /// full ±12 dB envelope in under 200 ms.
  static const double defaultMaxGainStepDb = 1.5;

  /// Peak headroom kept below 0 dBFS when boosting. **UNMEASURED** safety
  /// bound: the stage must not CREATE clipping while fixing a quiet signal.
  static const double defaultPeakHeadroomDb = 1;

  /// The absolute envelope no policy may exceed, whatever a caller asks
  /// for. Mirrors [DeviceAudioProfile.maxInputGainOffsetDb], because the
  /// device offset and the level correction share one budget.
  static const double absoluteGainLimitDb =
      DeviceAudioProfile.maxInputGainOffsetDb;

  /// Whether the stage may transform anything at all.
  final bool enabled;

  final double targetRmsDbfs;
  final double maxBoostDb;
  final double maxCutDb;
  final double maxGainStepDb;
  final double peakHeadroomDb;

  @override
  String toString() =>
      'LivePreprocessingConfig($version, enabled: $enabled, '
      'target: ${targetRmsDbfs}dBFS, boost: +${maxBoostDb}dB, '
      'cut: -${maxCutDb}dB, step: ${maxGainStepDb}dB)';
}

/// Applies a [LivePreprocessingConfig] to the Live PCM stream.
///
/// Stateful only in the ONE scalar that has to be: the currently applied
/// gain, so the slew limit ([LivePreprocessingConfig.maxGainStepDb]) can
/// hold across chunks. [reset] returns it to 0 dB.
final class QualityAwarePreprocessor {
  QualityAwarePreprocessor({
    this.config = const LivePreprocessingConfig.disabled(),
    this.deviceProfile = const DeviceAudioProfile.identity(),
  }) {
    reset();
  }

  final LivePreprocessingConfig config;

  /// The per-device correction (E14-R14's audio-setup wizard is the
  /// intended producer). [DeviceAudioProfile.identity] — the shipped value
  /// — contributes exactly 0 dB.
  final DeviceAudioProfile deviceProfile;

  double _appliedGainDb = 0;
  int _clampedSampleCount = 0;
  LivePreprocessingAdaptation _lastAdaptation =
      LivePreprocessingAdaptation.disabled;

  /// The gain currently applied, in dB. `0` whenever the stage is a no-op.
  /// The transform is exactly invertible by applying `-appliedGainDb` while
  /// [clampedSampleCount] is 0.
  double get appliedGainDb => _appliedGainDb;

  /// How many samples the ±1.0 safety clamp touched since [reset]. The one
  /// lossy part of the stage, counted rather than swallowed: a non-zero
  /// value means the boost bound and the peak headroom disagreed with
  /// reality and someone must look.
  int get clampedSampleCount => _clampedSampleCount;

  /// What the stage did to the most recent chunk.
  LivePreprocessingAdaptation get lastAdaptation => _lastAdaptation;

  /// Transforms [chunk] using the quality [snapshot] measured on the RAW
  /// input.
  ///
  /// Returns the SAME list instance whenever the effective gain is 0 dB —
  /// which includes every disabled build — so "off ⇒ bit-identical" is
  /// identity, not merely equality.
  List<double> process(List<double> chunk, SignalQualitySnapshot snapshot) {
    if (!config.enabled) {
      _appliedGainDb = 0;
      _lastAdaptation = LivePreprocessingAdaptation.disabled;
      return chunk;
    }
    final target = _targetGainDb(snapshot);
    final step = (target - _appliedGainDb).clamp(
      -config.maxGainStepDb,
      config.maxGainStepDb,
    );
    _appliedGainDb = (_appliedGainDb + step).clamp(
      -config.maxCutDb,
      config.maxBoostDb,
    );
    // [_lastAdaptation] deliberately keeps the DECISION [_targetGainDb]
    // made, even when the resulting gain is 0 dB: "the level was normalised
    // to no change" and "this state is not a level state" are different
    // facts, and collapsing both into `identity` would throw the diagnostic
    // away. Whether anything actually changed is [appliedGainDb]'s job.
    if (_appliedGainDb == 0) return chunk;
    final gain = math.pow(10, _appliedGainDb / 20).toDouble();
    final out = List<double>.filled(chunk.length, 0);
    for (var i = 0; i < chunk.length; i++) {
      final value = chunk[i] * gain;
      if (value > 1) {
        out[i] = 1;
        _clampedSampleCount++;
      } else if (value < -1) {
        out[i] = -1;
        _clampedSampleCount++;
      } else {
        out[i] = value;
      }
    }
    return out;
  }

  /// The gain the CURRENT snapshot asks for, before slew limiting.
  ///
  /// The switch is exhaustive with no `default` arm: a future
  /// `SignalQualityState` must be given its own answer here rather than
  /// silently inheriting one.
  double _targetGainDb(SignalQualitySnapshot snapshot) {
    switch (snapshot.state) {
      case SignalQualityState.clipping:
        // D3: hold, never react. Boosting damaged samples amplifies the
        // damage; cutting them cannot un-cut them.
        _lastAdaptation = LivePreprocessingAdaptation.clippingHold;
        return _appliedGainDb;
      case SignalQualityState.tooQuiet:
      case SignalQualityState.tooLoud:
        final rms = snapshot.rmsDbfs;
        if (rms == null || !rms.isFinite) {
          // The state says the level is wrong but no level was measured.
          // Not something to guess a number for.
          _lastAdaptation = LivePreprocessingAdaptation.deviceOffsetOnly;
          return _boundedGainDb(_deviceOffsetDb(), snapshot);
        }
        _lastAdaptation = LivePreprocessingAdaptation.levelNormalised;
        return _boundedGainDb(
          (config.targetRmsDbfs - rms) + _deviceOffsetDb(),
          snapshot,
        );
      case SignalQualityState.good:
      case SignalQualityState.tooNoisy:
      case SignalQualityState.speechLike:
      case SignalQualityState.unstable:
      case SignalQualityState.unknown:
        // Level normalisation is scoped to the two LEVEL states (D2): a
        // noisy, speech-like or unstable signal is not a level problem, and
        // `unknown` means "not measured yet". Only the device profile's own
        // offset applies — 0 dB on the shipped identity profile.
        _lastAdaptation = LivePreprocessingAdaptation.deviceOffsetOnly;
        return _boundedGainDb(_deviceOffsetDb(), snapshot);
    }
  }

  double _deviceOffsetDb() => deviceProfile.inputGainOffsetDb.clamp(
    -LivePreprocessingConfig.absoluteGainLimitDb,
    LivePreprocessingConfig.absoluteGainLimitDb,
  );

  /// Applies the policy bounds AND the peak-headroom bound: the stage may
  /// never boost a signal into clipping it did not already have.
  double _boundedGainDb(double wanted, SignalQualitySnapshot snapshot) {
    if (!wanted.isFinite) return 0;
    var bounded = wanted.clamp(-config.maxCutDb, config.maxBoostDb);
    final peak = snapshot.peakDbfs;
    if (bounded > 0 && peak != null && peak.isFinite) {
      final safeBoost = -config.peakHeadroomDb - peak;
      if (safeBoost < bounded) bounded = math.max(safeBoost, 0.0);
    }
    return bounded;
  }

  /// Back to the shipped, inert state — called from `LivePipeline.reset`.
  void reset() {
    _appliedGainDb = 0;
    _clampedSampleCount = 0;
    _lastAdaptation = config.enabled
        ? LivePreprocessingAdaptation.identity
        : LivePreprocessingAdaptation.disabled;
  }
}
