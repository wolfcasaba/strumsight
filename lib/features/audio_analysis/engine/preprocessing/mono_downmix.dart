/// Deterministic downmix evidence for a future raw multi-channel input path.
///
/// The present preprocessing stage receives mono [PcmAnalysisInput] values and
/// deliberately does not invoke this policy. Channel averaging can cancel
/// out-of-phase material, which is reported instead of silently hidden.
final class MonoDownmix {
  const MonoDownmix.v1();

  static const double _phaseCancellationEpsilon = 0.0000001;

  MonoDownmixResult downmix(
    List<double> interleavedSamples, {
    required int channelCount,
  }) {
    if (channelCount <= 0) {
      throw ArgumentError.value(channelCount, 'channelCount');
    }
    if (interleavedSamples.length % channelCount != 0) {
      throw ArgumentError.value(
        interleavedSamples.length,
        'interleavedSamples',
        'The sample count must contain complete channel frames.',
      );
    }

    final samples = <double>[];
    var sawPhaseCancellation = false;
    var sawClipping = false;
    for (
      var start = 0;
      start < interleavedSamples.length;
      start += channelCount
    ) {
      var sum = 0.0;
      var allChannelsAudible = true;
      for (var channel = 0; channel < channelCount; channel++) {
        final value = interleavedSamples[start + channel];
        sum += value;
        if (value.abs() <= _phaseCancellationEpsilon) {
          allChannelsAudible = false;
        }
      }
      final average = sum / channelCount;
      samples.add(average);
      if (allChannelsAudible && average.abs() <= _phaseCancellationEpsilon) {
        sawPhaseCancellation = true;
      }
      if (average.abs() > 1) sawClipping = true;
    }

    return MonoDownmixResult(
      samples: samples,
      warnings: <PreprocessingWarning>[
        if (sawPhaseCancellation) PreprocessingWarning.phaseCancellation,
        if (sawClipping) PreprocessingWarning.downmixClipping,
      ],
    );
  }
}

enum PreprocessingWarning { phaseCancellation, downmixClipping }

/// Immutable output and explicit evidence from [MonoDownmix].
final class MonoDownmixResult {
  MonoDownmixResult({
    required List<double> samples,
    required Iterable<PreprocessingWarning> warnings,
  }) : samples = List<double>.unmodifiable(samples),
       warnings = List<PreprocessingWarning>.unmodifiable(warnings);

  final List<double> samples;
  final List<PreprocessingWarning> warnings;
}
