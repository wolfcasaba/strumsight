import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

const _sampleRate = 44100;

void main() {
  group('PitchFrameExtractor — frequency matrix (R17 §6)', () {
    const frequencies = <({String name, double hz, int midi})>[
      (name: 'E2', hz: 82.41, midi: 40),
      (name: 'A2', hz: 110.00, midi: 45),
      (name: 'D3', hz: 146.83, midi: 50),
      (name: 'G3', hz: 196.00, midi: 55),
      (name: 'B3', hz: 246.94, midi: 59),
      (name: 'E4', hz: 329.63, midi: 64),
      (name: 'A4', hz: 440.00, midi: 69),
    ];

    for (final cell in frequencies) {
      test('${cell.name} retains median frequency within ±2 cents', () {
        final frames = _extract(_sine(cell.hz, seconds: 0.4));
        final segment = MonophonicPitchSegmentBuilder().build(frames).single;
        expect(_cents(segment.medianHz, cell.hz).abs(), lessThanOrEqualTo(2));
        expect(segment.medianMidi, cell.midi);
      });
    }

    test('silence yields only unvoiced frames', () {
      final frames = _extract(List<double>.filled(_sampleRate ~/ 4, 0));
      expect(frames, isNotEmpty);
      expect(
        frames,
        everyElement(predicate<PitchFrame>((frame) => !frame.isVoiced)),
      );
    });

    test('deterministic white noise is unavailable, never a pitch score', () {
      final random = math.Random(17);
      final frames = _extract(
        List<double>.generate(
          _sampleRate ~/ 2,
          (_) => random.nextDouble() * 2 - 1,
        ),
      );
      final capability = PitchCapabilityGate()
          .evaluate<void>(
            analysisPitchEnabled: true,
            hasMonophonicTarget: true,
            frames: frames,
          )
          .report;
      expect(capability.status, CapabilityStatus.unavailable);
      expect(
        capability.reason,
        anyOf(
          CapabilityUnavailableReason.insufficientEvents,
          CapabilityUnavailableReason.confidenceTooLow,
          CapabilityUnavailableReason.polyphonicInput,
        ),
      );
    });

    test('vibrato-like ±30-cent modulation remains a single segment', () {
      final frames = _extract(_vibrato(seconds: 0.8));
      final segments = MonophonicPitchSegmentBuilder().build(frames);
      expect(segments, hasLength(1));
      expect(segments.single.stabilityCents, closeTo(30, 5));
    });

    test('A4 to C5 is split within 40 ms of the actual transition', () {
      final samples = <double>[
        ..._sine(440, seconds: 0.3),
        ..._sine(523.251, seconds: 0.3),
      ];
      final segments = MonophonicPitchSegmentBuilder().build(_extract(samples));
      expect(segments, hasLength(2));
      expect(
        (segments.first.end - const Duration(milliseconds: 300)).inMilliseconds
            .abs(),
        lessThanOrEqualTo(40),
      );
    });
  });
}

List<PitchFrame> _extract(List<double> samples) =>
    PitchFrameExtractor().extract(samples: samples, sampleRate: _sampleRate);

List<double> _sine(double frequency, {required double seconds}) =>
    List<double>.generate(
      (seconds * _sampleRate).round(),
      (index) => 0.4 * math.sin(2 * math.pi * frequency * index / _sampleRate),
    );

List<double> _vibrato({required double seconds}) {
  var phase = 0.0;
  return List<double>.generate((seconds * _sampleRate).round(), (index) {
    final time = index / _sampleRate;
    final cents = 30 * math.sin(2 * math.pi * 5 * time);
    final frequency = 440 * math.pow(2, cents / 1200).toDouble();
    phase += 2 * math.pi * frequency / _sampleRate;
    return 0.4 * math.sin(phase);
  });
}

double _cents(double actual, double expected) =>
    1200 * math.log(actual / expected) / math.ln2;
