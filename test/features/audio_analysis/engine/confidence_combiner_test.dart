import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test('uses the contracted geometric mean rather than arithmetic mean', () {
    const values = <double>[0.9, 0.9, 0.9, 0.9, 0.1];
    final result = ConfidenceCombiner().combine(values);

    expect(result.confidence, closeTo(0.5799546134795288, 1e-15));
    expect(result.confidence, isNot(closeTo(0.74, 1e-12)));
  });

  test('applies hard gates before a confidence is published', () {
    final result = ConfidenceCombiner().combine(const <double>[
      1,
      1,
      1,
    ], hardGateOpen: false);

    expect(result.confidence, 0);
    expect(result.hardGateOpen, isFalse);
  });
}
