import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const barrelPath = 'lib/features/vision/domain/integration/public.dart';

  test(
    'the integration barrel never exports raw Vision implementation types',
    () {
      final barrel = File(barrelPath);
      final exports = RegExp(
        r"^export\s+'([^']+)'",
        multiLine: true,
      ).allMatches(barrel.readAsStringSync());

      for (final match in exports) {
        final relativeUri = match.group(1)!;
        final target = File(
          barrel.parent.uri.resolve(relativeUri).toFilePath(),
        ).absolute.path;

        expect(
          _isForbiddenExport(target),
          isFalse,
          reason: 'Integration barrel must not export $relativeUri.',
        );
      }
    },
  );

  test('Song Trainer Vision consumers never import the wide Vision barrel', () {
    final consumers = <File>[
      File('lib/features/song_trainer/data/vision/song_vision_adapter.dart'),
      File('lib/features/song_trainer/domain/models/song_vision_summary.dart'),
    ];

    for (final consumer in consumers.where((file) => file.existsSync())) {
      final imports = RegExp(
        r"^import\s+'([^']+)'",
        multiLine: true,
      ).allMatches(consumer.readAsStringSync());

      expect(
        imports.map((match) => match.group(1)),
        isNot(contains('package:strumsight/features/vision/public.dart')),
        reason: '${consumer.path} must use the narrow integration barrel.',
      );
    }
  });
}

bool _isForbiddenExport(String absoluteTarget) {
  final normalized = absoluteTarget.replaceAll('\\', '/');
  return normalized.contains('/lib/features/vision/domain/landmarks/') ||
      normalized.contains('/lib/features/vision/domain/geometry/') ||
      normalized.contains('/lib/features/vision/data/landmarks/') ||
      normalized.contains('/lib/features/vision/presentation/') ||
      normalized.endsWith('/lib/core/camera/camera_coordinate_space.dart');
}
