import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/analyze_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/analyze/public.dart';

void main() {
  test('projects aggregate analysis data from the public result', () {
    const result = AnalyzeResult(
      durationSec: 12.5,
      bpm: 100,
      beatsPerBar: 3,
      chords: <TimelineChord>[
        TimelineChord(label: 'Am', startSec: 0, endSec: 4),
        TimelineChord(label: 'G', startSec: 4, endSec: 8),
      ],
      strums: <TimelineStrum>[],
    );

    final adapted = const AnalyzeContextAdapter(
      schemaVersion: 'analyze.v1',
    ).adapt(result);

    expect(adapted!.key, TutorContextFieldKey.analyze);
    expect(adapted.values['bpm'], 100);
    expect(adapted.values['chordLabels'], <Object?>['Am', 'G']);
    expect(adapted.provenance.sourceFeature, ContextSourceFeature.analyze);
  });

  test('imports only the Analyze public boundary', () {
    const path =
        'lib/features/ai_tutor/application/context/adapters/analyze_context_adapter.dart';
    final imports = File(path)
        .readAsStringSync()
        .split('\n')
        .where((line) => line.trimLeft().startsWith('import '))
        .join('\n');
    expect(imports, contains('features/analyze/public.dart'));
    expect(imports, isNot(contains('features/analyze/model/')));
  });
}
