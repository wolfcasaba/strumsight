import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation calls use the central AppRoutes catalogue', () {
    const catalogue = 'lib/app/routing/app_route.dart';
    final routeLiteral = RegExp(
      r'''\.\s*(?:go|push|replace|pushReplacement|goNamed)\s*\(\s*['"]/''',
    );
    final violations = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path == catalogue) continue;

      final source = entity.readAsStringSync();
      for (final match in routeLiteral.allMatches(source)) {
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        violations.add('${entity.path}:$line');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use an AppRoutes constant for GoRouter navigation instead of a '
          'route string literal. '
          'Found: ${violations.join(', ')}',
    );
  });
}
