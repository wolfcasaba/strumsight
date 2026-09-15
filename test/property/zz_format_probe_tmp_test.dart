// TEMPORARY diagnostic (to be deleted): prints the formatter's output for the
// files this branch touched, so a session without a Dart SDK can read the
// exact formatting from the CI log. Never asserts anything.
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

void main() {
  test('format probe', () async {
    for (final file in _files) {
      final result = await Process.run('dart', ['format', '--output=show', file]);
      stdout.writeln('=====FORMAT-PROBE-BEGIN $file');
      stdout.writeln(result.stdout);
      stdout.writeln('=====FORMAT-PROBE-END $file');
    }
  });
}
