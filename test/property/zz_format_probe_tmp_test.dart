// TEMPORARY diagnostic (to be deleted): prints, into the CI log tail, what a
// session without a Dart SDK cannot measure locally — the formatter's exact
// output for the touched files, the analyzer's findings, and the outcome of
// the suspect test files. Never asserts anything.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _files = <String>[
  'lib/features/live/screens/live_screen.dart',
  'lib/features/live/widgets/live_summary_dialog.dart',
  'lib/features/practice_hub/screens/practice_area_hub_screen.dart',
  'lib/features/practice_hub/practice_area_hub_categories.dart',
  'test/features/live/live_summary_test.dart',
  'test/features/onboarding/first_win_production_engine_test.dart',
  'test/features/practice_hub/practice_area_hub_categories_test.dart',
];

const _suspectTests = <String>[
  'test/features/live/live_summary_test.dart',
  'test/features/onboarding/first_win_production_engine_test.dart',
  'test/features/profile/profile_hub_test.dart',
  'test/features/practice_hub/practice_area_hub_categories_test.dart',
  'test/ui/goldens/e13_r17_screens_golden_test.dart',
  'test/ui/goldens/e13_r22_screens_golden_test.dart',
  'test/ui/goldens/e13_r35_screens_golden_test.dart',
];

void main() {
  test('format probe', () async {
    for (final file in _files) {
      final result = await Process.run('dart', [
        'format',
        '--output=show',
        file,
      ]);
      stdout.writeln('=====FORMAT-PROBE-BEGIN $file');
      stdout.writeln(result.stdout);
      stdout.writeln('=====FORMAT-PROBE-END $file');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('analyze probe', () async {
    final result = await Process.run('dart', [
      'analyze',
      'lib/features/live',
      'lib/features/practice_hub',
      'lib/features/practice/presentation',
      'lib/features/settings',
      'lib/features/today',
      'lib/features/profile_hub',
      'lib/features/onboarding',
      'test/features/live',
      'test/features/practice_hub',
      'test/features/onboarding',
    ]);
    stdout.writeln('=====ANALYZE-PROBE-BEGIN');
    stdout.writeln(result.stdout);
    stdout.writeln(result.stderr);
    stdout.writeln('=====ANALYZE-PROBE-END');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('suspect tests probe', () async {
    final result = await Process.run('flutter', [
      'test',
      '--reporter=compact',
      ..._suspectTests,
    ]);
    final lines = (result.stdout as String).split('\n');
    stdout.writeln('=====TESTS-PROBE-BEGIN');
    var keep = 0;
    for (final line in lines) {
      if (line.contains('❌') ||
          line.contains('[E]') ||
          line.contains('Expected') ||
          line.contains('Actual') ||
          line.contains('Error') ||
          line.contains('Golden') ||
          line.contains('pixel') ||
          line.contains('tests passed') ||
          line.contains('Some tests failed')) {
        keep = 12;
      }
      if (keep > 0) {
        stdout.writeln(line);
        keep--;
      }
    }
    stdout.writeln('=====TESTS-PROBE-END');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
