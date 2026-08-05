import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/practice_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/practice/public.dart';

void main() {
  test('adapts a public practice result only when its schema is known', () {
    const result = PracticeSessionResult(
      id: 'practice-1',
      activeDuration: Duration(seconds: 120),
      pausedDuration: Duration(seconds: 30),
      attempts: <PracticeAttemptResult>[],
      finishReason: PracticeFinishReason.userFinished,
      highestStableTempo: null,
      coachingSummary: <String>[],
    );

    final adapted = const PracticeContextAdapter(
      schemaVersion: 'practice.v1',
    ).adapt(result);

    expect(adapted!.key, TutorContextFieldKey.practice);
    expect(adapted.values['activeSeconds'], 120);
    expect(adapted.provenance.sourceFeature, ContextSourceFeature.practice);
    expect(const PracticeContextAdapter().adapt(result), isNull);
  });

  test('imports only the Practice public boundary', () {
    _expectOnlyPublicFeatureImport(
      'lib/features/ai_tutor/application/context/adapters/practice_context_adapter.dart',
      'practice',
    );
  });
}

void _expectOnlyPublicFeatureImport(String path, String feature) {
  final imports = File(path)
      .readAsStringSync()
      .split('\n')
      .where((line) => line.trimLeft().startsWith('import '))
      .join('\n');
  expect(imports, contains('features/$feature/public.dart'));
  for (final line in imports.split('\n')) {
    if (line.contains('package:strumsight/features/')) {
      expect(line, contains('features/$feature/public.dart'));
    }
  }
}
