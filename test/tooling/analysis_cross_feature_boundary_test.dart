import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'analysis integration public surface exports only its adapter contracts',
    () {
      final publicSurface = File(
        'lib/features/audio_analysis/public.dart',
      ).readAsStringSync();

      for (final export in <String>[
        'application/adapters/practice_analysis_adapter.dart',
        'application/adapters/song_analysis_adapter.dart',
        'application/adapters/tutor_analysis_snapshot.dart',
        'application/adapters/progress_evidence_adapter.dart',
      ]) {
        expect(publicSurface, contains("export '$export';"));
      }
    },
  );

  test('audio analysis imports other features only through public barrels', () {
    final analysisFiles = Directory('lib/features/audio_analysis')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in analysisFiles) {
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r"(?:import|export)\s+'([^']*features/[^']+)'",
      ).allMatches(source)) {
        final target = match.group(1)!;
        final featurePath = RegExp(r'features/([^/]+)/(.+)').firstMatch(target);
        if (featurePath == null || featurePath.group(1) == 'audio_analysis') {
          continue;
        }
        expect(
          featurePath.group(2),
          'public.dart',
          reason: '${file.path} must not import $target directly.',
        );
      }
    }
  });

  test('architecture exception allowlist remains the committed 12 entries', () {
    final source = File('tool/check_architecture.dart').readAsStringSync();
    final entries = RegExp(
      r"^  'lib/features/",
      multiLine: true,
    ).allMatches(source).length;

    expect(entries, 12);
  });
}
