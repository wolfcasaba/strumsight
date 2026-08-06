import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/practice_result_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/practice/public.dart';

void main() {
  const result = PracticeSessionResult(
    id: 'practice-result-1',
    activeDuration: Duration(seconds: 120),
    pausedDuration: Duration(seconds: 30),
    attempts: <PracticeAttemptResult>[],
    finishReason: PracticeFinishReason.userFinished,
    highestStableTempo: null,
    coachingSummary: <String>['measuredSession'],
  );

  test('creates a versioned immutable reference from a public result', () {
    final adapted = const PracticeResultContextAdapter(
      schemaVersion: 'practice-result.v1',
    ).adapt(result);

    expect(adapted, isNotNull);
    expect(adapted!.key, TutorContextFieldKey.practice);
    expect(adapted.values['resultId'], 'practice-result-1');
    expect(adapted.values['activeSeconds'], 120);
    expect(adapted.provenance.schemaVersion, 'practice-result.v1');
    expect(adapted.provenance.sourceFeature, ContextSourceFeature.practice);
  });

  test('withholds a result reference without scorer or schema provenance', () {
    expect(const PracticeResultContextAdapter().adapt(result), isNull);
  });

  test('imports only the Practice public boundary', () {
    final imports =
        File(
              'lib/features/ai_tutor/application/context/adapters/practice_result_context_adapter.dart',
            )
            .readAsStringSync()
            .split('\n')
            .where((line) => line.trimLeft().startsWith('import '));

    expect(imports.join('\n'), contains('features/practice/public.dart'));
    expect(
      imports.where((line) => line.contains('package:strumsight/features/')),
      everyElement(contains('features/practice/public.dart')),
    );
  });
}
