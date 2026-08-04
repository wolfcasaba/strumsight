import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public boundary has no imports or exports in its baseline state', () {
    final boundary = File('lib/features/ai_tutor/public.dart');

    expect(
      boundary.existsSync(),
      isTrue,
      reason: 'AI Tutor must expose a public feature boundary.',
    );

    final source = boundary.readAsStringSync();
    final directives = RegExp(
      r'''(?:import|export)\s+['"][^'"]+['"]''',
    ).allMatches(source);

    expect(
      directives,
      isEmpty,
      reason:
          'the empty baseline boundary must not pull in another feature\'s '
          'domain, data, application, or presentation internals',
    );
  });
}
