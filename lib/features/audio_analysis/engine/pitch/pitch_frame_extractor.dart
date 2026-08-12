import 'dart:math' as math;

import 'package:strumsight/core/audio/dsp/sliding_framer.dart';
import 'package:strumsight/core/audio/dsp/yin_pitch_detector.dart';

import '../../domain/pitch/pitch_frame.dart';

/// Reuses the shared YIN primitive to produce V2 pitch evidence.
///
/// The provisional 2048/512 framing is the R17 OD-02 fallback because the
/// shared pitch-observation configuration has no framing parameters yet.
final class PitchFrameExtractor {
  PitchFrameExtractor({
    this.windowSize = defaultWindowSize,
    this.hopSize = defaultHopSize,
    this.minimumFrequencyHz = 60,
    this.maximumFrequencyHz = 5000,
  }) {
    if (windowSize <= 0 || hopSize <= 0 || hopSize > windowSize) {
      throw ArgumentError(
        'Pitch frame window and hop must be positive and ordered.',
      );
    }
    if (!minimumFrequencyHz.isFinite ||
        minimumFrequencyHz <= 0 ||
        !maximumFrequencyHz.isFinite ||
        maximumFrequencyHz < minimumFrequencyHz) {
      throw ArgumentError('Pitch frequency bounds must be finite and ordered.');
    }
  }

  static const int defaultWindowSize = 2048;
  static const int defaultHopSize = 512;

  final int windowSize;
  final int hopSize;
  final double minimumFrequencyHz;
  final double maximumFrequencyHz;

  List<PitchFrame> extract({
    required List<double> samples,
    required int sampleRate,
  }) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    final detector = YinPitchDetector(
      sampleRate: sampleRate,
      bufferSize: windowSize,
      minFrequency: minimumFrequencyHz,
    );
    final framer = SlidingFramer(window: windowSize, hop: hopSize);
    final frames = <PitchFrame>[];
    var frameIndex = 0;
    for (final frame in framer.add(samples)) {
      final time = Duration(
        microseconds:
            frameIndex * hopSize * Duration.microsecondsPerSecond ~/ sampleRate,
      );
      frameIndex += 1;
      final frequencyHz = detector.detect(frame);
      if (frequencyHz == null ||
          !frequencyHz.isFinite ||
          frequencyHz < minimumFrequencyHz ||
          frequencyHz > maximumFrequencyHz) {
        frames.add(PitchFrame(time: time, confidence: 0));
        continue;
      }
      final midi = 69 + 12 * math.log(frequencyHz / 440) / math.ln2;
      frames.add(
        PitchFrame(
          time: time,
          frequencyHz: frequencyHz,
          midiNote: midi.round().clamp(0, 127),
          confidence: detector.clarity,
        ),
      );
    }
    return List<PitchFrame>.unmodifiable(frames);
  }
}
