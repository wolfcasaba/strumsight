import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/chord_crnn.dart';

/// Parity contract for the pure-Dart CHORD CRNN forward pass (r196).
///
/// The fixture ships a RAW (un-normalised) (100,144) CQT and the Keras float32
/// per-frame softmax computed FROM THE ROUNDED values the JSON carries (r143
/// lesson). The Dart net, loading the same shipped `chord_crnn.bin` asset, must
/// reproduce every one of the 100×25 probabilities to <=1e-3 and match the
/// argmax sequence exactly. Any BN order / eps, GRU reset_after / gate-order,
/// backward-direction, conv-padding or normalization drift turns this red.
void main() {
  final binFile = File('assets/ml/chord_crnn.bin');
  final fixtureFile = File('test/fixtures/chord_crnn_parity.json');

  group('ChordCrnn', () {
    late ChordCrnn net;
    late Map<String, dynamic> fixture;

    setUpAll(() {
      net = ChordCrnn.parse(
        Uint8List.fromList(binFile.readAsBytesSync()).buffer.asByteData(),
      );
      fixture =
          json.decode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    });

    test('shipped weights asset parses with the expected architecture', () {
      expect(net.nBins, 144);
      expect(net.nClasses, 25);
    });

    test('forward pass matches the Keras reference to <=1e-3', () {
      final input = (fixture['input_cqt'] as List<dynamic>)
          .map((row) => (row as List<dynamic>)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList();
      final refProbs = fixture['probs'] as List<dynamic>;
      final refArgmax = (fixture['argmax'] as List<dynamic>)
          .map((v) => v as int)
          .toList();

      final out = net.infer(input);
      expect(out, hasLength(input.length));

      var maxAbsDiff = 0.0;
      var argmaxMismatches = 0;
      for (var i = 0; i < out.length; i++) {
        final frame = out[i];
        expect(frame, hasLength(25));
        final ref = (refProbs[i] as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();

        var sum = 0.0;
        var dartArg = 0;
        var dartPeak = frame[0];
        for (var c = 0; c < 25; c++) {
          sum += frame[c];
          final d = (frame[c] - ref[c]).abs();
          if (d > maxAbsDiff) maxAbsDiff = d;
          if (frame[c] > dartPeak) {
            dartPeak = frame[c];
            dartArg = c;
          }
        }
        expect((sum - 1.0).abs(), lessThan(1e-5),
            reason: 'frame $i softmax must sum to 1 (got $sum)');
        if (dartArg != refArgmax[i]) argmaxMismatches++;
      }

      // ignore: avoid_print
      print('ChordCrnn parity: maxAbsDiff=$maxAbsDiff '
          'argmaxMismatches=$argmaxMismatches / ${out.length}');

      // Per-probability tolerance (report happens above regardless).
      for (var i = 0; i < out.length; i++) {
        final ref = (refProbs[i] as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();
        for (var c = 0; c < 25; c++) {
          expect((out[i][c] - ref[c]).abs(), lessThan(1e-3),
              reason: 'frame $i class $c: dart=${out[i][c]} keras=${ref[c]}');
        }
      }
      expect(argmaxMismatches, 0, reason: 'argmax sequence must match exactly');
    });
  });
}
