import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/analyze_result_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/analyze/public.dart';

void main() {
  const result = AnalyzeResult(
    durationSec: 12.5,
    bpm: 100,
    chords: <TimelineChord>[TimelineChord(label: 'Am', startSec: 0, endSec: 4)],
    strums: <TimelineStrum>[],
  );

  test('records only public aggregate result values and capability state', () {
    final adapted = const AnalyzeResultContextAdapter(
      scorerVersion: 'analyze-scorer.v1',
    ).adapt(resultId: 'analysis-result-1', result: result);

    expect(adapted, isNotNull);
    expect(adapted!.key, TutorContextFieldKey.analyze);
    expect(adapted.values['resultId'], 'analysis-result-1');
    expect(adapted.values['bpm'], 100);
    expect(adapted.values['mlDiagnosticsAvailable'], isFalse);
    expect(adapted.values, isNot(contains('mlAgreement')));
    expect(adapted.provenance.scorerVersion, 'analyze-scorer.v1');
  });

  test('withholds an analysis reference when provenance is missing', () {
    expect(
      const AnalyzeResultContextAdapter().adapt(
        resultId: 'analysis-result-1',
        result: result,
      ),
      isNull,
    );
  });

  test('imports only the Analyze public boundary', () {
    final imports =
        File(
              'lib/features/ai_tutor/application/context/adapters/analyze_result_context_adapter.dart',
            )
            .readAsStringSync()
            .split('\n')
            .where((line) => line.trimLeft().startsWith('import '));

    expect(imports.join('\n'), contains('features/analyze/public.dart'));
    expect(
      imports.where((line) => line.contains('package:strumsight/features/')),
      everyElement(contains('features/analyze/public.dart')),
    );
  });
}
