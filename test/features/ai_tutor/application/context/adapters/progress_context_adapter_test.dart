import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/progress_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/progress/public.dart';

void main() {
  test('projects aggregate public progress statistics', () {
    final stats = PracticeStats(<PracticeEntry>[
      const PracticeEntry(day: 10, source: PracticeSource.learn, seconds: 60),
      const PracticeEntry(day: 11, source: PracticeSource.live, seconds: 30),
    ]);

    final adapted = const ProgressContextAdapter(
      schemaVersion: 'progress.v1',
    ).adapt(stats);

    expect(adapted!.key, TutorContextFieldKey.progress);
    expect(adapted.values['totalSessions'], 2);
    expect(adapted.values['totalSeconds'], 90);
    expect(adapted.provenance.sourceFeature, ContextSourceFeature.progress);
  });

  test('imports only the Progress public boundary', () {
    const path =
        'lib/features/ai_tutor/application/context/adapters/progress_context_adapter.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports, contains('features/progress/public.dart'));
    expect(imports, isNot(contains('features/progress/model/')));
  });
}
