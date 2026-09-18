import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Dio instances are created only by DioFactory', () {
    const allowed = 'lib/core/network/dio_factory.dart';
    final violations = <String>[];
    final dioConstructor = RegExp(r'\bDio\s*\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = _posixPath(entity.path);
      if (path == allowed) continue;

      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (dioConstructor.hasMatch(lines[index])) {
          violations.add('$path:${index + 1}');
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

/// `Directory.listSync` reports paths with the platform separator (`\` on
/// Windows) while the allowlist above is written POSIX-style — compare on one
/// form. A no-op wherever `/` already is the separator (Linux CI).
String _posixPath(String path) => Platform.pathSeparator == '/'
    ? path
    : path.replaceAll(Platform.pathSeparator, '/');
