// TEMPORARY diagnostic (to be deleted): prints, into the CI log tail, what a
// session without a Dart SDK cannot produce locally — the formatter's exact
// output for the touched files, the analyzer's findings, the outcome of the
// suspect test files. Never asserts anything.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _files = <String>[
  'test/features/live/live_summary_test.dart',
  'test/features/library/library_test.dart',
  'test/widget_test.dart',
];

const _suspectTests = <String>[
  'test/features/live/live_summary_test.dart',
  'test/features/library/library_test.dart',
  'test/widget_test.dart',
  'test/features/onboarding/first_win_production_engine_test.dart',
  'test/features/practice_hub/practice_area_hub_categories_test.dart',
  'test/app/navigation/adaptive_scaffold_test.dart',
  'test/accessibility/closure_suite_test.dart',
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
          line.contains('EXCEPTION CAUGHT') ||
          line.contains('Expected') ||
          line.contains('Actual') ||
          line.contains('Error') ||
          line.contains('tests passed') ||
          line.contains('Some tests failed') ||
          line.contains('All tests passed')) {
        keep = 14;
      }
      if (keep > 0) {
        stdout.writeln(line);
        keep--;
      }
    }
    stdout.writeln('=====TESTS-PROBE-END');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
