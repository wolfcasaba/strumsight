import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache tests contain no wall-clock expectation', () {
    const testFiles = <String>[
      'test/features/audio_analysis/data/analysis_cache_test.dart',
      'test/features/audio_analysis/data/audio_fingerprint_test.dart',
      'test/features/audio_analysis/domain/analysis_cache_key_test.dart',
      'test/property/analysis_cache_property_test.dart',
    ];

    for (final path in testFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains(
          'Stop'
          'watch',
        ),
        isFalse,
        reason: path,
      );
      expect(
        source.contains(
          'less'
          'Than',
        ),
        isFalse,
        reason: path,
      );
    }
  });
}
