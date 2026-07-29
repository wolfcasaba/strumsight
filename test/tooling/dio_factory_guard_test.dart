import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Dio instances are created only by DioFactory', () {
    const allowed = 'lib/core/network/dio_factory.dart';
    final violations = <String>[];
    final dioConstructor = RegExp(r'\bDio\s*\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path == allowed) continue;

      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (dioConstructor.hasMatch(lines[index])) {
          violations.add('${entity.path}:${index + 1}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Move every production Dio construction into $allowed.',
    );
  });
}
