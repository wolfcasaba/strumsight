import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/synth/plucked_string_synth.dart';

String _tag(List<int> b, int o) => String.fromCharCodes(b.sublist(o, o + 4));

/// Zero crossings over [samples] → an estimated frequency, used to check
/// `pluck` actually rings at (roughly) the requested pitch rather than just
/// "some periodic-ish noise".
double _estimatedHz(List<double> samples, double windowSeconds) {
  var crossings = 0;
  for (var i = 1; i < samples.length; i++) {
    if ((samples[i - 1] >= 0) != (samples[i] >= 0)) crossings++;
  }
  return crossings / 2 / windowSeconds;
}

void main() {
  group('PluckedStringSynth.pluck', () {
    test('rings at (roughly) the requested pitch, non-silent, bounded', () {
      const sampleRate = 44100;
      final out = PluckedStringSynth.pluck(
        freqHz: 220,
        seconds: 1,
        sampleRate: sampleRate,
      );
      expect(out.length, sampleRate);
      expect(out.any((s) => s != 0), isTrue);

      var peak = 0.0;
      for (final s in out) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      expect(peak, lessThanOrEqualTo(0.5 + 1e-9));

      // Karplus–Strong period = round(sr/f); the transient dies out well
      // before 0.8 s of ringing, so measuring the tail is the honest check.
      const windowSeconds = 0.8;
      final windowStart = out.length - (windowSeconds * sampleRate).round();
      final estimatedHz = _estimatedHz(out.sublist(windowStart), windowSeconds);
      expect(estimatedHz, closeTo(220, 220 * 0.04));
    });

    test('is deterministic — two calls are byte-identical', () {
      final a = PluckedStringSynth.pluck(freqHz: 220, seconds: 0.5);
      final b = PluckedStringSynth.pluck(freqHz: 220, seconds: 0.5);
      expect(a, equals(b));
    });

    test('non-positive frequency renders silence', () {
      final out = PluckedStringSynth.pluck(freqHz: 0, seconds: 0.5);
      expect(out.every((s) => s == 0), isTrue);
      final negative = PluckedStringSynth.pluck(freqHz: -10, seconds: 0.5);
      expect(negative.every((s) => s == 0), isTrue);
    });

    test('zero seconds yields an empty buffer', () {
      final out = PluckedStringSynth.pluck(freqHz: 220, seconds: 0);
      expect(out, isEmpty);
    });
  });

  group('PluckedStringSynth.strumOnsets', () {
    test('a down-stroke sweeps low → high, strictly increasing from 0', () {
      final onsets = PluckedStringSynth.strumOnsets(count: 6, downstroke: true);
      expect(onsets, [0, 794, 1588, 2382, 3176, 3970]);
      for (var i = 1; i < onsets.length; i++) {
        expect(onsets[i], greaterThan(onsets[i - 1]));
      }
    });

    test('an up-stroke sweeps high → low, strictly decreasing from 5*step', () {
      final onsets = PluckedStringSynth.strumOnsets(
        count: 6,
        downstroke: false,
      );
      expect(onsets, [3970, 3176, 2382, 1588, 794, 0]);
      expect(onsets.first, 5 * 794);
      for (var i = 1; i < onsets.length; i++) {
        expect(onsets[i], lessThan(onsets[i - 1]));
      }
    });

    test('a single string always starts at 0', () {
      expect(PluckedStringSynth.strumOnsets(count: 1, downstroke: true), [0]);
      expect(PluckedStringSynth.strumOnsets(count: 1, downstroke: false), [0]);
    });
  });

  group('PluckedStringSynth.strumPcm', () {
    const freqs = [82.41, 110.0, 146.83, 196.0, 246.94, 329.63];

    test('down- and up-strokes produce different PCM', () {
      final down = PluckedStringSynth.strumPcm(freqs: freqs, downstroke: true);
      final up = PluckedStringSynth.strumPcm(freqs: freqs, downstroke: false);
      expect(down, isNot(equals(up)));
    });

    test('peak amplitude is close to amp * 32767', () {
      const amp = 0.6;
      final pcm = PluckedStringSynth.strumPcm(
        freqs: freqs,
        downstroke: true,
        amp: amp,
      );
      var peak = 0;
      for (final s in pcm) {
        final a = s.abs();
        if (a > peak) peak = a;
      }
      final expectedPeak = amp * 32767;
      expect(peak, closeTo(expectedPeak, expectedPeak * 0.02));
    });

    test('an empty chord renders silence', () {
      final pcm = PluckedStringSynth.strumPcm(
        freqs: const [],
        downstroke: true,
      );
      expect(pcm.every((s) => s == 0), isTrue);
    });

    test('the last sample is 0 — the release fade never clicks', () {
      final pcm = PluckedStringSynth.strumPcm(freqs: freqs, downstroke: true);
      expect(pcm.last, 0);
    });
  });

  group('PluckedStringSynth.strumWav', () {
    test('produces a well-formed RIFF/WAVE with the right data length', () {
      const sampleRate = 44100;
      const seconds = 0.05;
      final wav = PluckedStringSynth.strumWav(
        freqs: const [220.0],
        downstroke: true,
        seconds: seconds,
        sampleRate: sampleRate,
      );
      expect(_tag(wav, 0), 'RIFF');
      expect(_tag(wav, 8), 'WAVE');
      expect(_tag(wav, 36), 'data');

      final n = (seconds * sampleRate).round();
      expect(wav.length, 44 + n * 2);
    });
  });
}
