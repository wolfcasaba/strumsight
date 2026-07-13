import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/crnn_strum_net.dart';

/// Parity contract for the pure-Dart CRNN forward pass (ml-track P1.3).
///
/// The fixture ships RAW (un-normalised) log-mel windows and the Keras
/// float32 softmax probabilities computed FROM THE ROUNDED values the JSON
/// carries (r143 lesson) — the Dart net, loading the same shipped weights
/// asset, must reproduce them to <=1e-3. Feature drift OR math drift on
/// either side turns this red.
void main() {
  final binFile = File('assets/ml/strum_crnn.bin');
  final fixtureFile = File('test/fixtures/crnn_parity.json');

  group('CrnnStrumNet', () {
    late CrnnStrumNet net;
    late Map<String, dynamic> fixture;

    setUpAll(() {
      net = CrnnStrumNet.parse(
        Uint8List.fromList(binFile.readAsBytesSync()).buffer.asByteData(),
      );
      fixture =
          json.decode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
    });

    test('shipped weights asset parses with the expected architecture', () {
      expect(net.frames, 15); // PRE 3 + POST 12 (ml/features.py)
      expect(net.mels, 128);
    });

    test('forward pass matches the Keras reference to <=1e-3', () {
      final windows = fixture['windows'] as List<dynamic>;
      final probs = fixture['probs'] as List<dynamic>;
      expect(windows, isNotEmpty);
      for (var i = 0; i < windows.length; i++) {
        final w = (windows[i] as List<dynamic>)
            .map((row) => (row as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList();
        final out = net.forward(w);
        final ref = (probs[i] as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();
        expect(out, hasLength(2));
        expect((out[0] + out[1] - 1.0).abs(), lessThan(1e-6),
            reason: 'softmax must sum to 1');
        for (var c = 0; c < 2; c++) {
          expect((out[c] - ref[c]).abs(), lessThan(1e-3),
              reason: 'window $i class $c: dart=${out[c]} keras=${ref[c]}');
        }
      }
    });

    test('fixture windows classify to their labels well above chance', () {
      // The REAL-domain accuracy lock (32 eval-fold phone-mic windows,
      // measured 0.91 at export; full eval fold 0.867): the shipped weights
      // must be the TRAINED ones, not garbage that still passes parity.
      final windows = fixture['windows'] as List<dynamic>;
      final labels = fixture['labels'] as List<dynamic>;
      var correct = 0;
      for (var i = 0; i < windows.length; i++) {
        final w = (windows[i] as List<dynamic>)
            .map((row) => (row as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList();
        final out = net.forward(w);
        if ((out[1] > out[0] ? 1 : 0) == labels[i] as int) correct++;
      }
      expect(correct / windows.length, greaterThanOrEqualTo(0.75));
    });
  });
}
