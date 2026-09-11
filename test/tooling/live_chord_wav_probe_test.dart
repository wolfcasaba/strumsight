// Feeds labelled WAV recordings through the REAL Live pipeline and reports
// what the chord decoder emits — no emulator, no microphone, no room.
//
// WHY (E18-R01 verification round, 2026-09-11). The emulator measurement that
// produced "G reads as Bm, E flips to Bsus4, D is silent" was taken through
// Windows "Stereo Mix". That device's MEASURED in-band (70–5000 Hz) noise
// floor on the test box is −24.1 dBFS, while the test signal arrived at about
// −20 dBFS — an SNR of roughly 4 dB, at which the result says nothing about
// the decoder. The same box could not point the emulator at a real microphone
// (`-allow-host-audio` + cold boot + Microphone Array as the Windows default
// recording device still produced a zero-level input), so the decoder is not
// measurable THROUGH that emulator at all. This probe measures it directly.
//
// It is an OBSERVATION harness, not a gate: it never fails on recognition
// quality, it prints a table. Moving a DSP constant still needs the fixture +
// property + real-guitar chain (`AGENTS.md` §9, ADR 0539 D4 / E18-R05).
//
// The recordings are not committed; point the probe at a directory:
//
//   LIVE_WAV_DIR=/path/to/wavs flutter test \
//       test/tooling/live_chord_wav_probe_test.dart
//
// It expects `<LABEL>-major.wav` (44.1 kHz mono) for the seven naturals and
// skips silently when the variable is unset, so CI stays unaffected.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

const _labels = <String>['C', 'G', 'D', 'E', 'A', 'F', 'B'];

void main() {
  final dir = Platform.environment['LIVE_WAV_DIR'];

  test('Live pipeline chord probe over labelled real-guitar WAVs', () {
    final root = Directory(dir!);
    expect(root.existsSync(), isTrue, reason: 'LIVE_WAV_DIR must exist');

    final rows = <String>[];
    var scored = 0;
    var correct = 0;
    for (final label in _labels) {
      final wav = File(
        '${root.path}${Platform.pathSeparator}$label-major.wav',
      );
      if (!wav.existsSync()) {
        rows.add('$label | MISSING ${wav.path}');
        continue;
      }
      final decoded = WavDecoder.decode(
        Uint8List.fromList(wav.readAsBytesSync()),
      );
      if (decoded == null) {
        rows.add('$label | NOT A SUPPORTED WAV');
        continue;
      }
      final (pcm, sampleRate) = decoded;

      final pipeline = LivePipeline(sampleRate: sampleRate);
      final frames = <LiveFrame>[];
      const chunk = 1024;
      for (var i = 0; i < pcm.length; i += chunk) {
        final end = i + chunk < pcm.length ? i + chunk : pcm.length;
        frames.addAll(pipeline.addChunk(pcm.sublist(i, end)));
      }

      final histogram = <String, int>{};
      String? first;
      final decisions = <String, int>{};
      final rejects = <String, int>{};
      for (final frame in frames) {
        final decision = frame.chordDecision?.name ?? 'none';
        decisions[decision] = (decisions[decision] ?? 0) + 1;
        final reject = frame.chordRejectReason?.name;
        if (reject != null) rejects[reject] = (rejects[reject] ?? 0) + 1;
        final emitted = frame.current?.label;
        if (emitted == null) continue;
        histogram[emitted] = (histogram[emitted] ?? 0) + 1;
        first ??= emitted;
      }
      final entries = histogram.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = entries.isEmpty ? null : entries.first.key;
      final hist = entries.isEmpty
          ? '(no chord in ${frames.length} frames)'
          : entries.map((e) => '${e.key}x${e.value}').join(' ');
      scored++;
      if (top == label) correct++;
      final verdict = top == null
          ? 'NO-DETECT'
          : (top == label ? 'CORRECT' : 'WRONG(top=$top)');
      final dec = (decisions.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .map((e) => '${e.key}x${e.value}')
          .join(' ');
      final rej = rejects.isEmpty
          ? '-'
          : (rejects.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .map((e) => '${e.key}x${e.value}')
                .join(' ');
      rows.add(
        '$label | len=${(pcm.length / sampleRate).toStringAsFixed(2)}s | '
        'shown: $hist | first=${first ?? '-'} | $verdict\n'
        '      decisions: $dec\n'
        '      rejects  : $rej\n'
        '      raw last : ${pipeline.chordPrediction?.label ?? '-'}',
      );
    }

    // ignore: avoid_print
    print('--- Live pipeline chord probe ---');
    for (final row in rows) {
      // ignore: avoid_print
      print(row);
    }
    // ignore: avoid_print
    print('SUMMARY: $correct/$scored top-label matches');
  }, skip: dir == null ? 'set LIVE_WAV_DIR to run the probe' : null);
}
