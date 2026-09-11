// SWEEP: how much local mean can whitening subtract before it starts lying?
//
//   REAL_AUDIO_DIR=/path/to/wavs flutter test \
//     test/tooling/whitening_mean_coefficient_sweep_test.dart
//
// At the full reference value the engine hears far more on real recordings and
// also loses a QUIET MAJOR THIRD, reading an open E as `Em`. Major-for-minor is
// the worst error this app can make — those are the chords the beginner course
// teaches — so the question is not "on or off" but "how far can this go before
// it costs a third".
//
// Three criteria are measured on the SAME axis, because a gain on one is only
// worth having if it does not buy a loss on another:
//
//   1. the quiet third — an open E with its third at 0.08 must stay `E`;
//   2. the modelled chords — seven with exact ground truth must stay correct;
//   3. real recordings — named frames, and the share of them that are `sus4`
//      or `aug`, the qualities the probe found over-reported.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/guitar_strings.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';
import 'package:strumsight/features/live/engine/dsp/chord_matcher.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';
import 'package:strumsight/features/live/engine/dsp/viterbi_chord_decoder.dart';

import '../support/synth.dart';

const int _sampleRate = 44100;
const _coefficients = [0.0, 0.25, 0.5, 0.75, 1.0];

// --- modelled guitar -------------------------------------------------------

List<double> _pluckedString({
  required double freqHz,
  required double seconds,
  required int seed,
  double damping = 0.996,
  double amplitude = 0.25,
}) {
  final length = (seconds * _sampleRate).round();
  final delay = math.max(2, (_sampleRate / freqHz).round());
  final random = math.Random(seed);
  final buffer = List<double>.generate(
    delay,
    (_) => random.nextDouble() * 2 - 1,
  );
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 1; i < buffer.length; i++) {
      buffer[i] = (buffer[i] + buffer[i - 1]) / 2;
    }
  }
  final out = List<double>.filled(length, 0);
  var index = 0;
  for (var n = 0; n < length; n++) {
    final current = buffer[index];
    final next = buffer[(index + 1) % delay];
    out[n] = current * amplitude;
    buffer[index] = damping * (current + next) / 2;
    index = (index + 1) % delay;
  }
  final fade = (0.03 * _sampleRate).round();
  for (var i = 0; i < fade && i < length; i++) {
    out[length - 1 - i] *= i / fade;
  }
  return out;
}

List<double> _strumChord(String label, {double seconds = 3.0}) {
  final shape = ChordShapes.forLabel(label)!;
  final strings = GuitarStrings.standard;
  final pcm = List<double>.filled((seconds * _sampleRate).round(), 0);
  var voice = 0;
  for (var position = 0; position < 6; position++) {
    final fret = shape.frets[position];
    if (fret < 0) continue;
    final midi = strings[position].midi + fret;
    final freq = 440 * math.pow(2, (midi - 69) / 12).toDouble();
    final offset = (position * 0.022 * _sampleRate).round();
    final tone = _pluckedString(
      freqHz: freq,
      seconds: seconds - position * 0.022,
      seed: 1000 + voice * 17,
      damping: midi < 55 ? 0.9975 : 0.9955,
    );
    for (var i = 0; i < tone.length; i++) {
      final at = offset + i;
      if (at < pcm.length) pcm[at] += tone[i];
    }
    voice++;
  }
  return pcm;
}

/// The SHIPPED fixture's own voicing and decode path, not a replica of it.
///
/// An earlier version of this sweep built its own quiet-third signal through
/// `LivePipeline` and got no confirmed chord at ANY coefficient — including
/// today's shipped one, where the fixture passes. The replica was measuring
/// nothing. This uses `voicedChord` and the direct NnlsChroma + Viterbi path
/// that `spectral_whitening_test.dart` uses, so the number here is the same
/// number that guards the shipped behaviour.
///
/// Open E (022100), levels from the E18-R01 reference recording; the third G#3
/// is the quiet one at 0.08.
String? _quietThirdE(double coefficient) {
  final voicing = <(double, double)>[
    (82.41, 0.60), // E2
    (123.47, 0.97), // B2  the fifth, doubled and loud
    (164.81, 1.00), // E3
    (207.65, 0.08), // G#3 the major third, fretted once
    (246.94, 0.49), // B3
    (329.63, 0.53), // E4
  ];
  final nc = NnlsChroma(
    sampleRate: _sampleRate,
    whiteningMeanCoefficient: coefficient,
  );
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? last;
  for (final frame in frames(
    voicedChord(voicing),
    DspConfig.nnlsWindow,
    DspConfig.nnlsHop,
  )) {
    final chroma = nc.process(frame);
    final tonal =
        chroma != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

// --- running ---------------------------------------------------------------

({Map<String, int> chords, int confirmed}) _run(
  List<double> pcm,
  int sampleRate,
  double coefficient,
) {
  final pipeline = LivePipeline(
    sampleRate: sampleRate,
    whiteningMeanCoefficient: coefficient,
  );
  final chords = <String, int>{};
  var confirmed = 0;
  const chunk = 1024;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      final label = frame.current?.label;
      if (label == null) continue;
      confirmed++;
      chords[label] = (chords[label] ?? 0) + 1;
    }
  }
  return (chords: chords, confirmed: confirmed);
}

String? _top(Map<String, int> chords) => chords.isEmpty
    ? null
    : chords.entries.reduce((a, b) => b.value > a.value ? b : a).key;

double _colourShare(Map<String, int> chords) {
  final total = chords.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 0;
  final suspect = chords.entries
      .where((e) => e.key.contains('sus4') || e.key.contains('aug'))
      .fold<int>(0, (a, e) => a + e.value);
  return suspect / total;
}

void main() {
  const modelled = ['Em', 'Am', 'D', 'G', 'C', 'E', 'A'];

  test('SWEEP the mean coefficient across all three criteria', () {
    final modelledPcm = {
      for (final chord in modelled) chord: _strumChord(chord),
    };

    final dir = Platform.environment['REAL_AUDIO_DIR'];
    final realFiles = dir == null || dir.isEmpty
        ? <File>[]
        : (Directory(dir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.wav'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)));

    final lines = <String>[];
    for (final coefficient in _coefficients) {
      final quietTop = _quietThirdE(coefficient);
      var correct = 0;
      for (final chord in modelled) {
        if (_top(_run(modelledPcm[chord]!, _sampleRate, coefficient).chords) ==
            chord) {
          correct++;
        }
      }

      var named = 0;
      var colour = 0.0;
      var counted = 0;
      for (final file in realFiles) {
        final decoded = WavDecoder.decode(file.readAsBytesSync());
        if (decoded == null) continue;
        final (pcm, sampleRate) = decoded;
        final result = _run(pcm, sampleRate, coefficient);
        named += result.confirmed;
        colour += _colourShare(result.chords);
        counted++;
      }

      lines.add(
        'k=${coefficient.toStringAsFixed(2)}  '
        'quiet-third=${quietTop ?? "-"}  '
        'modelled=$correct/${modelled.length}  '
        'real: named=$named  '
        'sus4+aug=${counted == 0 ? "-" : (colour / counted * 100).toStringAsFixed(1)}%',
      );
    }

    // ignore: avoid_print
    print('\nWHITENING MEAN-COEFFICIENT SWEEP\n${lines.join("\n")}\n');
    expect(lines, isNotEmpty);
  });
}
