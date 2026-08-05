import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/streak_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  test(
    'projects a scalar streak snapshot without importing the private state type',
    () {
      const input = StreakContextInput(
        currentDays: 4,
        longestDays: 7,
        bankedFreezes: 1,
        practicedToday: false,
      );

      final adapted = const StreakContextAdapter(
        schemaVersion: 'streak.v1',
      ).adapt(input);

      expect(adapted!.key, TutorContextFieldKey.streak);
      expect(adapted.values['currentDays'], 4);
      expect(adapted.provenance.sourceFeature, ContextSourceFeature.streak);
    },
  );

  test('imports only the Streak public boundary', () {
    const path =
        'lib/features/ai_tutor/application/context/adapters/streak_context_adapter.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports, contains('features/streak/public.dart'));
    expect(imports, isNot(contains('features/streak/model/')));
  });
}
