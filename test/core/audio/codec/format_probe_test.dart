// TEMPORARY formatting probe (deleted in the same round).
//
// This container has no Dart SDK, so `dart format` cannot be run locally. The
// probe asks CI for the canonical formatting of whatever the format gate
// reports as changed, and prints it into the job log.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prints the canonical formatting of every changed file', () {
    final root = Platform.environment['FLUTTER_ROOT'];
    final dartBin = root == null ? 'dart' : '$root/bin/dart';
    final scan = Process.runSync(dartBin, <String>[
      'format',
      '--output=none',
      '--set-exit-if-changed',
      'lib',
      'test',
      'tool',
    ]);
    final changed = <String>[];
    for (final line in const LineSplitter().convert('${scan.stdout}')) {
      if (line.startsWith('Changed ')) {
        changed.add(line.substring(8));
      }
    }
    stdout.writeln('PROBE-CHANGED $changed');
    for (final path in changed) {
      final shown = Process.runSync(dartBin, <String>[
        'format',
        '--output=show',
        '--summary=none',
        path,
      ]);
      stdout.writeln('PROBE-BEGIN $path');
      stdout.writeln(shown.stdout);
      stdout.writeln('PROBE-END $path');
    }
  });
}
