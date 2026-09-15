// TEMPORARY diagnostic (to be deleted): runs the Live summary test file in a
// subprocess and prints its full output into the CI log tail, so a session
// without a Dart SDK can read the failure text. Never asserts anything.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('live summary probe', () async {
    final result = await Process.run('flutter', [
      'test',
      '--reporter=expanded',
      'test/features/live/live_summary_test.dart',
    ]);
    stdout.writeln('=====LIVE-PROBE-BEGIN');
    stdout.writeln(result.stdout);
    stdout.writeln(result.stderr);
    stdout.writeln('=====LIVE-PROBE-END');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
