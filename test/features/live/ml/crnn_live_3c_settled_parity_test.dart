import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/ml/crnn_strum_net.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

/// Parity for the UNWIRED settled 3-class asset — the §9 leg that was missing.
///
/// ADR 0555 D3 said "the parity fixture is in
/// `test/fixtures/crnn_live_3c_settled_parity.json`", and it was: 1.26 MB of it, committed,
/// and **read by nothing**. So the settled asset's Dart↔Keras agreement was never checked,
/// while ADR 0567 measured that same asset through the shipped pipeline and reported
/// +0.186 direction macro-F1. A measurement of a model whose Dart port is unverified is a
/// measurement of an unknown model, which is why this file exists before the wiring round
/// rather than inside it (ADR 0568).
///
/// The fixture's schema differs from its sibling's — `cases: [{window, expected, label}]`
/// rather than parallel `windows`/`probs`/`labels` arrays — so a copy of
/// `crnn_live_3c_parity_test.dart` would have silently read nothing. It is spelled out
/// here because that is exactly the sort of near-miss that leaves a green test proving
/// nothing (`docs/LESSONS.md` L671).
void main() {
  const settledAsset = 'assets/ml/strum_crnn_live_3c_settled.bin';
  const shippedAsset = 'assets/ml/strum_crnn_live_3c.bin';

  final net = CrnnStrumNet.parse(
    ByteData.sublistView(File(settledAsset).readAsBytesSync()),
  );
  final fixture =
      json.decode(
            File(
              'test/fixtures/crnn_live_3c_settled_parity.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  List<List<double>> windowOf(Map<String, dynamic> row) =>
      (row['window'] as List)
          .map(
            (r) => (r as List)
                .map((v) => (v as num).toDouble())
                .toList(growable: false),
          )
          .toList(growable: false);

  test('the fixture actually carries cases, and they are 3-class', () {
    // Guards the schema itself: an empty or renamed `cases` key would make every
    // assertion below pass over nothing.
    expect(cases, isNotEmpty, reason: 'the fixture must exercise the net');
    expect(net.nClasses, 3);
    for (final row in cases) {
      expect(windowOf(row), hasLength(15));
      expect(windowOf(row).first, hasLength(128));
      expect(row['expected'] as List, hasLength(3));
    }
  });

  test('the settled net matches the Keras reference to <=1e-3', () {
    var worst = 0.0;
    for (var i = 0; i < cases.length; i++) {
      final expectedProbs = (cases[i]['expected'] as List)
          .map((v) => (v as num).toDouble())
          .toList();
      final out = net.forward(windowOf(cases[i]));
      expect(out, hasLength(3));
      for (var c = 0; c < 3; c++) {
        final delta = (out[c] - expectedProbs[c]).abs();
        if (delta > worst) worst = delta;
        expect(delta, lessThan(1e-3), reason: 'case $i class $c');
      }
    }
    // Printed so a drift that stays inside tolerance is still visible to a reader.
    // ignore: avoid_print
    print('settled parity: ${cases.length} cases, worst |delta| = $worst');
  });

  test('mined no-strum cases land on the reject class above chance', () {
    var negTotal = 0, negRejected = 0;
    for (final row in cases) {
      if ((row['label'] as num).toInt() != 2) continue;
      negTotal++;
      final out = net.forward(windowOf(row));
      if (out[2] >= out[0] && out[2] >= out[1]) negRejected++;
    }
    expect(
      negTotal,
      greaterThan(0),
      reason: 'the fixture must exercise the no-strum class',
    );
    expect(
      negRejected / negTotal,
      greaterThanOrEqualTo(0.6),
      reason:
          'these weights must be the trained reject model, not any 3-class net',
    );
  });

  test('the softmax is a distribution on arbitrary input, not only on the '
      'fixture rows', () {
    // The §9 property leg: the fixture pins 32 points, and a net that produced a
    // non-distribution anywhere else would still pass it. Seeded so a failure is
    // reproducible.
    final rng = Random(20260912);
    for (var trial = 0; trial < 40; trial++) {
      final window = List.generate(
        15,
        (_) => List.generate(128, (_) => rng.nextDouble() * 8 - 4),
        growable: false,
      );
      final out = net.forward(window);
      var sum = 0.0;
      for (final p in out) {
        expect(p.isFinite, isTrue, reason: 'trial $trial produced $p');
        expect(p, greaterThanOrEqualTo(0.0));
        expect(p, lessThanOrEqualTo(1.0));
        sum += p;
      }
      expect(
        (sum - 1.0).abs(),
        lessThan(1e-9),
        reason: 'trial $trial sums to $sum',
      );
    }
  });

  test('the settled asset is MEASURED, not wired — and this test says so', () {
    // ADR 0567 D4: the swap is the wiring round's job. Two independent facts pin that,
    // so the switch cannot happen quietly: the shipped gate constant is untouched, and
    // the two assets are genuinely different files. Without the second check this test
    // would keep passing if someone copied the settled weights over the shipped path,
    // which is precisely the change it exists to notice.
    expect(
      LiveCrnnStrumClassifier.noStrumThreshold,
      0.85,
      reason:
          'ADR 0549s gate; the settled asset would want the fitted 0.439 '
          '(ADR 0567 D3), so a change here means the wiring round happened',
    );
    final shippedBytes = File(shippedAsset).readAsBytesSync();
    final settledBytes = File(settledAsset).readAsBytesSync();
    expect(
      shippedBytes.length == settledBytes.length &&
          _sameBytes(shippedBytes, settledBytes),
      isFalse,
      reason: 'the shipped asset must still be the UNSWAPPED one',
    );
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
