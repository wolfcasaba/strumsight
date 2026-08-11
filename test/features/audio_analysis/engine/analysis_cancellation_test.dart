// ignore_for_file: depend_on_referenced_packages

import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:test/test.dart';

void main() {
  test(
    'source becomes cancelled and its token throws a cancellation exception',
    () {
      final source = AnalysisCancellationSource();

      expect(source.isCancelled, isFalse);
      source.cancel();

      expect(source.isCancelled, isTrue);
      expect(
        source.throwIfCancelled,
        throwsA(isA<AnalysisCancelledException>()),
      );
    },
  );

  test('cancelling a source is idempotent', () {
    final source = AnalysisCancellationSource();

    source.cancel();
    source.cancel();

    expect(source.isCancelled, isTrue);
  });
}
