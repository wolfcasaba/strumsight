import 'dart:math' as math;

/// Maps the onset frame's linear RMS to the Live screen's 0..1 input-level
/// meter on a **dBFS scale with meter ballistics** (E18-R01 emulator F10).
///
/// The previous mapping was `rms * 8` clamped to 0..1: full scale at
/// −18 dBFS and zero below −32 dBFS — a 14 dB window that every normal
/// recording level overshoots and every quiet one undershoots, so the meter
/// sat at 0 % or 100 % whatever the gain (measured at 100/60/30/10 % mic
/// gain: always 100 %). A level meter is a logarithmic instrument: this one
/// spans [floorDbfs] → [ceilingDbfs] linearly in dB, which puts the weak-
/// signal threshold (`SsSignalQualityIndicator.defaultWeakThreshold`, 0.12)
/// at ≈ −40 dBFS — the same "quiet" line the signal-quality analyzer draws
/// (`LiveQualityThresholds.quietRmsDbfs`).
///
/// Ballistics: instant attack, exponential release ([releasePerFrame] per
/// emitted frame, ~15 Hz) so a strum's 23 ms RMS burst stays readable
/// between strokes instead of flickering. Pure Dart, no DSP-decision input
/// is touched — the meter is display only.
final class InputLevelMeter {
  InputLevelMeter({
    this.floorDbfs = defaultFloorDbfs,
    this.ceilingDbfs = defaultCeilingDbfs,
    this.releasePerFrame = defaultReleasePerFrame,
  }) : assert(ceilingDbfs > floorDbfs),
       assert(releasePerFrame >= 0 && releasePerFrame < 1);

  /// Reads 0 at and below this level (digital near-silence).
  static const double defaultFloorDbfs = -45.0;

  /// Reads 1 at and above this level (a hot, near-clipping input).
  static const double defaultCeilingDbfs = -6.0;

  /// Per-frame release multiplier: 0.7 ≈ 530 ms from full scale to 5 % at
  /// the ~15 Hz emit cadence.
  static const double defaultReleasePerFrame = 0.7;

  final double floorDbfs;
  final double ceilingDbfs;
  final double releasePerFrame;

  double _level = 0;

  /// The meter's current reading, 0..1.
  double get level => _level;

  /// Instantaneous 0..1 reading for a linear [rms] (no ballistics).
  double instantaneous(double rms) {
    if (rms <= 0) return 0;
    final dbfs = 20 * math.log(rms) / math.ln10;
    return ((dbfs - floorDbfs) / (ceilingDbfs - floorDbfs)).clamp(0.0, 1.0);
  }

  /// Feed one emitted frame's [rms]; returns the new reading.
  double update(double rms) {
    final instant = instantaneous(rms);
    final released = _level * releasePerFrame;
    _level = instant > released ? instant : released;
    if (_level < 0.001) _level = 0;
    return _level;
  }

  void reset() => _level = 0;
}
