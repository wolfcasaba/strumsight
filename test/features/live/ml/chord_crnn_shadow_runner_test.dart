// E14-R26 — the shipped chord CRNN as a live SHADOW candidate.
//
// RED before this round: `chord_crnn.bin` had exactly one loader in the app
// (`analyze_providers.dart`) and never ran on the live path at all. What
// these cells PIN:
//   1. manifest integrity — the constant in the code, the manifest's declared
//      hash and the bytes on disk are the SAME sha256;
//   2. a missing / truncated / tampered asset produces a TYPED
//      `FallbackReason`, never a silent no-op;
//   3. the label taxonomy is the shipped one (index-aligned to labels.py);
//   4. the clip decode is deterministic and its grid matches the CQT hop;
//   5. the streaming ring is allocated once and never grows.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/engine/ml_chord_decoder.dart';
import 'package:strumsight/features/live/engine/dsp/cqt_extractor.dart';
import 'package:strumsight/features/live/engine/ml/chord_crnn_shadow_runner.dart';
import 'package:strumsight/features/live/model/recognition_runtime_info.dart';

const _assetPath = 'assets/ml/chord_crnn.bin';
const _manifestPath = 'assets/ml/model_manifest.json';

/// A short, deterministic tone — enough audio for a handful of CQT hops
/// without paying for a long forward pass in CI.
List<double> _tone(double freq, {int sampleRate = 22050, double seconds = 2}) {
  final n = (sampleRate * seconds).round();
  return <double>[
    for (var i = 0; i < n; i++)
      0.3 * math.sin(2 * math.pi * freq * i / sampleRate),
  ];
}

void main() {
  final assetBytes = Uint8List.fromList(File(_assetPath).readAsBytesSync());

  group('manifest integrity', () {
    test('code constant == manifest sha256 == the bytes on disk', () {
      final onDisk = crypto.sha256.convert(assetBytes).toString();
      final manifest =
          json.decode(File(_manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      final entry = (manifest['models'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((m) => m['path'] == _assetPath);

      expect(entry['sha256'], onDisk);
      expect(ChordCrnnShadowRunner.shippedChordModelSha256, onDisk);
      expect(entry['format'], 'CCRN');
      expect(
        entry['format_version'],
        ChordCrnnShadowRunner.chordModelFormatVersion,
      );
      expect(entry['input_shape'], [
        ChordCrnnShadowRunner.windowFrames,
        CqtExtractor.nBins,
      ]);
      expect(entry['output_classes'], ChordCrnnShadowRunner.majmin25Labels);
    });

    test('the label list is the shipped majmin taxonomy', () {
      expect(
        ChordCrnnShadowRunner.majmin25Labels,
        MlChordDecoder.majmin25Labels,
      );
      expect(ChordCrnnShadowRunner.majmin25Labels.first, 'N.C.');
      expect(ChordCrnnShadowRunner.majmin25Labels.length, 25);
    });
  });

  group('activation is fail-VISIBLE', () {
    test('no bytes → assetMissing, and no runner', () {
      final activation = ChordShadowActivation.activate(null);
      expect(activation.isActivated, isFalse);
      expect(activation.runner, isNull);
      expect(activation.reason, FallbackReason.assetMissing);
    });

    test('empty bytes → assetMissing', () {
      expect(
        ChordShadowActivation.activate(Uint8List(0)).reason,
        FallbackReason.assetMissing,
      );
    });

    test('garbage bytes → parseFailed, never a partially built model', () {
      final activation = ChordShadowActivation.activate(
        Uint8List.fromList(List<int>.filled(512, 0x7F)),
      );
      expect(activation.reason, FallbackReason.parseFailed);
      expect(activation.runner, isNull);
    });

    test('a TRUNCATED real asset → parseFailed', () {
      final activation = ChordShadowActivation.activate(
        Uint8List.sublistView(assetBytes, 0, 4096),
      );
      expect(activation.reason, FallbackReason.parseFailed);
    });

    test('a hash mismatch refuses to activate (fail-closed)', () {
      final activation = ChordShadowActivation.activate(
        assetBytes,
        expectedSha256: 'de' * 32,
      );
      expect(
        activation.isActivated,
        isFalse,
        reason: 'bytes that are not the reviewed bytes have no measured '
            'behaviour and must not be used',
      );
      expect(activation.reason, FallbackReason.parseFailed);
    });

    test('the shipped asset activates and reports its own hash', () {
      final activation = ChordShadowActivation.activate(
        assetBytes,
        expectedSha256: ChordCrnnShadowRunner.shippedChordModelSha256,
      );
      expect(activation.isActivated, isTrue);
      expect(activation.reason, isNull);
      expect(
        activation.sha256,
        ChordCrnnShadowRunner.shippedChordModelSha256,
      );
      expect(activation.runner!.sha256, activation.sha256);
    });
  });

  group('clip decoding', () {
    late ChordCrnnShadowRunner runner;

    setUpAll(() {
      runner = ChordShadowActivation.activate(assetBytes).runner!;
    });

    test('verdicts sit on the CQT grid and carry a real posterior', () {
      final pcm = _tone(196.0);
      final verdicts = runner.runClip(pcm, 22050);
      expect(verdicts, isNotEmpty);
      expect(verdicts.length, CqtExtractor.nFrames(pcm.length));
      for (var i = 0; i < verdicts.length; i++) {
        expect(
          verdicts[i].timeSec,
          closeTo(i * ChordCrnnShadowRunner.frameHopSec, 1e-12),
        );
        expect(
          ChordCrnnShadowRunner.majmin25Labels,
          contains(verdicts[i].label),
        );
        expect(verdicts[i].posterior, inInclusiveRange(0.0, 1.0));
      }
    });

    test('the same PCM decodes to the same labels every time', () {
      final pcm = _tone(220.0);
      final first = runner.runClip(pcm, 22050).map((v) => v.label).toList();
      final second = runner.runClip(pcm, 22050).map((v) => v.label).toList();
      expect(first, second);
    });

    test('empty input yields no verdict — never a fabricated N.C.', () {
      expect(runner.runClip(const <double>[], 22050), isEmpty);
      expect(runner.verdictAtSeconds(0), isNull);
    });

    test('verdictAtSeconds picks the frame covering the instant', () {
      final pcm = _tone(261.63);
      final verdicts = runner.runClip(pcm, 22050);
      final hop = ChordCrnnShadowRunner.frameHopSec;
      expect(runner.verdictAtSeconds(0)!.timeSec, 0.0);
      expect(
        runner.verdictAtSeconds(hop * 2 + hop / 2)!.timeSec,
        closeTo(hop * 2, 1e-12),
      );
      // Past the end of the clip the LAST verdict stands rather than a null:
      // the clip really was analysed up to there.
      expect(
        runner.verdictAtSeconds(1e6)!.timeSec,
        verdicts.last.timeSec,
      );
      expect(runner.verdictAtSeconds(-1), isNull);
    });
  });

  group('the streaming adapter is bounded', () {
    test('no verdict before the window has filled', () {
      final runner = ChordShadowActivation.activate(assetBytes).runner!;
      runner.addPcm(_tone(196.0, seconds: 1), 22050);
      expect(runner.poll(), isNull);
    });

    test('a filled window produces a verdict stamped on the ENGINE clock', () {
      final runner = ChordShadowActivation.activate(assetBytes).runner!;
      // One full window plus one emit hop, so poll() has both enough audio
      // and enough NEW audio to re-run.
      const seconds =
          ChordCrnnShadowRunner.windowFrames * CqtExtractor.hop /
              CqtExtractor.sr +
          1.0;
      runner.addPcm(_tone(196.0, seconds: seconds), 22050);
      final verdict = runner.poll();
      expect(verdict, isNotNull);
      expect(
        ChordCrnnShadowRunner.majmin25Labels,
        contains(verdict!.label),
      );
      expect(
        verdict.timeSec,
        closeTo(seconds, 1e-3),
        reason: 'the streaming verdict is stamped at the audio fed so far, '
            "not on the analysis window's own grid",
      );
      // …and a later instant is what the observer would ask for.
      expect(runner.verdictAtSeconds(seconds + 1), isNotNull);
      expect(runner.verdictAtSeconds(0), isNull);
    });

    test('the PCM ring is allocated once and never grows', () {
      final runner = ChordShadowActivation.activate(assetBytes).runner!;
      final chunk = _tone(196.0, seconds: 0.5);
      runner.addPcm(chunk, 22050);
      final allocated = runner.debugRingLength;
      expect(allocated, greaterThan(0));
      for (var i = 0; i < 200; i++) {
        runner.addPcm(chunk, 22050);
      }
      expect(
        runner.debugRingLength,
        allocated,
        reason: 'a ten-minute stream must cost one window, not ten minutes',
      );
      expect(
        allocated,
        (ChordCrnnShadowRunner.windowFrames * CqtExtractor.hop),
        reason: 'at the CQT rate the window is exactly N hops',
      );
    });
  });
}
