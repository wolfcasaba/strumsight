import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/crnn_strum_net.dart';

/// r168 — parity + real-domain lock for the LIVE (70 ms audio-truncated)
/// model, mirroring crnn_strum_net_test.dart for the shipped batch model.
void main() {
  final net = CrnnStrumNet.parse(
    ByteData.sublistView(
        File('assets/ml/strum_crnn_live.bin').readAsBytesSync()),
  );
  final fixture = json.decode(
          File('test/fixtures/crnn_live_parity.json').readAsStringSync())
      as Map<String, dynamic>;

  List<List<double>> window(int i) => ((fixture['windows'] as List)[i] as List)
      .map((row) =>
          (row as List).map((v) => (v as num).toDouble()).toList())
      .toList();

  test('live net matches the Keras reference to <=1e-3', () {
    final probs = fixture['probs'] as List;
    for (var i = 0; i < probs.length; i++) {
      final out = net.forward(window(i));
      for (var c = 0; c < 2; c++) {
        expect((out[c] - ((probs[i] as List)[c] as num).toDouble()).abs(),
            lessThan(1e-3),
            reason: 'window $i class $c');
      }
    }
  });

  test('live fixture windows classify above the real-domain floor', () {
    final labels = fixture['labels'] as List;
    var correct = 0;
    for (var i = 0; i < labels.length; i++) {
      final out = net.forward(window(i));
      if ((out[1] > out[0] ? 1 : 0) == labels[i] as int) correct++;
    }
    expect(correct / labels.length, greaterThanOrEqualTo(0.65),
        reason: 'the shipped live weights must be the trained ones '
            '(70 ms model eval 0.799; 32-window fixture, wide tolerance)');
  });
}
