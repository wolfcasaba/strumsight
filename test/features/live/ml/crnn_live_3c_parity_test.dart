import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/crnn_strum_net.dart';

/// r175 — parity + reject lock for the 3-class LIVE model (down/up/no-strum),
/// mirroring crnn_live_parity_test.dart. The fixture (built by
/// ml/train_live_3c.py) ships eval-fold windows INCLUDING label-2 no-strum
/// negatives, so the Dart forward pass is proven on both the direction and the
/// reject columns.
void main() {
  final net = CrnnStrumNet.parse(
    ByteData.sublistView(
        File('assets/ml/strum_crnn_live_3c.bin').readAsBytesSync()),
  );
  final fixture = json.decode(
          File('test/fixtures/crnn_live_3c_parity.json').readAsStringSync())
      as Map<String, dynamic>;

  List<List<double>> window(int i) => ((fixture['windows'] as List)[i] as List)
      .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
      .toList();

  test('the 3-class net exposes three output classes', () {
    expect(net.nClasses, 3);
  });

  test('3-class live net matches the Keras reference to <=1e-3', () {
    final probs = fixture['probs'] as List;
    for (var i = 0; i < probs.length; i++) {
      final out = net.forward(window(i));
      expect(out, hasLength(3));
      for (var c = 0; c < 3; c++) {
        expect((out[c] - ((probs[i] as List)[c] as num).toDouble()).abs(),
            lessThan(1e-3),
            reason: 'window $i class $c');
      }
    }
  });

  test('mined no-strum windows land on the reject class above chance', () {
    final labels = (fixture['labels'] as List).cast<int>();
    var negTotal = 0, negRejected = 0;
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] != 2) continue;
      negTotal++;
      final out = net.forward(window(i));
      if (out[2] >= out[0] && out[2] >= out[1]) negRejected++;
    }
    expect(negTotal, greaterThan(0),
        reason: 'the fixture must exercise the no-strum class');
    expect(negRejected / negTotal, greaterThanOrEqualTo(0.6),
        reason: 'the shipped weights must be the trained reject model');
  });
}
