import 'dart:math' as math;

import 'quality_thresholds.dart';

/// Pure deterministic DSP primitives used only by the offline quality stage.
///
/// This file deliberately owns its small FFT implementation: importing the
/// real-time Live DSP stack would create a prohibited cross-feature dependency.
final class SignalQualityMath {
  SignalQualityMath._();

  static const QualityThresholds _thresholds = QualityThresholds.standard;

  static double peakDbfs(List<double> samples) {
    var peak = 0.0;
    for (final sample in samples) {
      peak = math.max(peak, _finiteAbsolute(sample));
    }
    return _toDbfs(peak);
  }

  static double rmsDbfs(List<double> samples) {
    if (samples.isEmpty) return _thresholds.silenceFloorDbfs;
    var sumSquares = 0.0;
    for (final sample in samples) {
      final finite = _finiteSample(sample);
      sumSquares += finite * finite;
    }
    return _toDbfs(math.sqrt(sumSquares / samples.length));
  }

  static double clippedSampleRatio(List<double> samples) {
    if (samples.isEmpty) return 0;
    var clipped = 0;
    for (final sample in samples) {
      if (_finiteAbsolute(sample) >= _thresholds.clippedSampleThreshold) {
        clipped++;
      }
    }
    return clipped / samples.length;
  }

  /// A frame is silent at the inclusive documented RMS threshold.
  static bool isSilentFrame(List<double> frame) =>
      rmsDbfs(frame) <= _thresholds.silentSampleDbfs;

  static double silentRatio(List<double> samples) {
    final frames = _frames(samples);
    if (frames.isEmpty) return 1;
    final silent = frames.where(isSilentFrame).length;
    return silent / frames.length;
  }

  static double activeRegionRatio(List<double> samples) =>
      1 - silentRatio(samples);

  /// The noise-floor proxy is the nearest-rank tenth percentile of frame RMS.
  static double noiseFloorDbfs(List<double> samples) =>
      noiseFloorDbfsForFrames(_frames(samples));

  static double noiseFloorDbfsForFrames(List<List<double>> frames) {
    if (frames.isEmpty) return _thresholds.silenceFloorDbfs;
    final values = frames.map(rmsDbfs).toList()..sort();
    final rank = (values.length * 0.10).ceil().clamp(1, values.length);
    return values[rank - 1];
  }

  /// Returns one minus mean spectral flatness. Zero means noise-like; one is
  /// maximally tone-like. It is a proxy only, never a sound-source classifier.
  static double tonalness(List<double> samples) {
    final frames = _fullFrames(samples);
    if (frames.isEmpty) return 0;
    var flatnessSum = 0.0;
    for (final frame in frames) {
      flatnessSum += _spectralFlatness(frame);
    }
    return (1 - flatnessSum / frames.length).clamp(0.0, 1.0);
  }

  static List<List<double>> _frames(List<double> samples) {
    if (samples.isEmpty) return const <List<double>>[];
    final frames = <List<double>>[];
    for (
      var start = 0;
      start < samples.length;
      start += _thresholds.analysisFrameHop
    ) {
      final end = math.min(
        start + _thresholds.analysisFrameSize,
        samples.length,
      );
      frames.add(samples.sublist(start, end));
      if (end == samples.length) break;
    }
    return frames;
  }

  static List<List<double>> _fullFrames(List<double> samples) {
    final frames = <List<double>>[];
    for (
      var start = 0;
      start + _thresholds.analysisFrameSize <= samples.length;
      start += _thresholds.analysisFrameHop
    ) {
      frames.add(samples.sublist(start, start + _thresholds.analysisFrameSize));
    }
    return frames;
  }

  static double _spectralFlatness(List<double> frame) {
    final spectrum = _fft(_hannWindow(frame));
    final positiveBinCount = spectrum.length ~/ 2 + 1;
    var logMagnitudeSum = 0.0;
    var magnitudeSum = 0.0;
    for (var index = 0; index < positiveBinCount; index++) {
      final magnitude = math.max(
        math.sqrt(
          spectrum[index].real * spectrum[index].real +
              spectrum[index].imaginary * spectrum[index].imaginary,
        ),
        _thresholds.spectralMagnitudeFloor,
      );
      logMagnitudeSum += math.log(magnitude);
      magnitudeSum += magnitude;
    }
    final geometricMean = math.exp(logMagnitudeSum / positiveBinCount);
    final arithmeticMean = magnitudeSum / positiveBinCount;
    return (geometricMean / arithmeticMean).clamp(0.0, 1.0);
  }

  static List<_Complex> _fft(List<double> values) {
    final output = <_Complex>[
      for (final value in values) _Complex(_finiteSample(value), 0),
    ];
    final size = output.length;
    var reverse = 0;
    for (var index = 1; index < size; index++) {
      var bit = size >> 1;
      while ((reverse & bit) != 0) {
        reverse ^= bit;
        bit >>= 1;
      }
      reverse ^= bit;
      if (index < reverse) {
        final swap = output[index];
        output[index] = output[reverse];
        output[reverse] = swap;
      }
    }
    for (var length = 2; length <= size; length <<= 1) {
      final angle = -2 * math.pi / length;
      final step = _Complex(math.cos(angle), math.sin(angle));
      for (var offset = 0; offset < size; offset += length) {
        var factor = const _Complex(1, 0);
        final half = length ~/ 2;
        for (var index = 0; index < half; index++) {
          final even = output[offset + index];
          final odd = output[offset + index + half] * factor;
          output[offset + index] = even + odd;
          output[offset + index + half] = even - odd;
          factor = factor * step;
        }
      }
    }
    return output;
  }

  static List<double> _hannWindow(List<double> frame) {
    if (frame.length == 1) return List<double>.from(frame);
    return List<double>.generate(frame.length, (index) {
      final coefficient =
          0.5 * (1 - math.cos(2 * math.pi * index / (frame.length - 1)));
      return _finiteSample(frame[index]) * coefficient;
    });
  }

  static double _toDbfs(double amplitude) {
    if (!amplitude.isFinite || amplitude <= 0) {
      return _thresholds.silenceFloorDbfs;
    }
    final dbfs = 20 * math.log(amplitude) / math.ln10;
    return dbfs
        .clamp(_thresholds.silenceFloorDbfs, _thresholds.maximumReportDbfs)
        .toDouble();
  }

  static double _finiteSample(double value) => value.isFinite ? value : 0;

  static double _finiteAbsolute(double value) => _finiteSample(value).abs();
}

final class _Complex {
  const _Complex(this.real, this.imaginary);

  final double real;
  final double imaginary;

  _Complex operator +(_Complex other) =>
      _Complex(real + other.real, imaginary + other.imaginary);

  _Complex operator -(_Complex other) =>
      _Complex(real - other.real, imaginary - other.imaginary);

  _Complex operator *(_Complex other) => _Complex(
    real * other.real - imaginary * other.imaginary,
    real * other.imaginary + imaginary * other.real,
  );
}
