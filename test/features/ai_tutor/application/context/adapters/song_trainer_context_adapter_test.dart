import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/song_trainer_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';

void main() {
  test(
    'reports a versioned unavailable section while scoring remains private',
    () {
      final adapted = const SongTrainerContextAdapter().adapt();

      expect(adapted.key, TutorContextFieldKey.songTrainer);
      expect(adapted.availability, ContextFieldAvailability.unavailable);
      expect(adapted.values, isEmpty);
      expect(
        adapted.provenance.sourceFeature,
        ContextSourceFeature.songTrainer,
      );
      expect(adapted.provenance.schemaVersion, 'songTrainer.unavailable.v1');
    },
  );

  test('imports only the Song Trainer public boundary', () async {
    const path =
        'lib/features/ai_tutor/application/context/adapters/song_trainer_context_adapter.dart';
    final result = await Process.run('rg', <String>['-n', r'^import ', path]);
    expect(result.exitCode, 0);
    final imports = result.stdout as String;
    expect(imports, contains('features/song_trainer/public.dart'));
    expect(imports, isNot(contains('features/song_trainer/domain/')));
  });
}
