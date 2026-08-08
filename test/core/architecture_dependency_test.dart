import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_architecture.dart';

void main() {
  group('repository architecture', () {
    test('contains exactly the allowlisted dependency deviations', () {
      final report = checkArchitecture(projectRoot: Directory.current);

      expect(report.isClean, isTrue, reason: report.format());
    });
  });

  group('architecture dependency rules', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync(
        'strumsight_architecture_test_',
      );
    });

    tearDown(() {
      project.deleteSync(recursive: true);
    });

    test('detects relative and package core-to-feature dependencies', () {
      _write(
        project,
        'lib/core/first.dart',
        "import '../features/live/engine/live_pipeline.dart';",
      );
      _write(project, 'lib/core/second.dart', '''
export
  'package:strumsight/features/tuner/model/tuner_reading.dart'
  show TunerReading;
''');
      _write(project, 'lib/core/third.dart', '''
import 'safe_transport.dart'
    if (dart.library.io)
        'package:strumsight/features/analyze/engine/clip_analyzer.dart';
''');

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        containsAll({
          'lib/core/first.dart -> '
              'lib/features/live/engine/live_pipeline.dart',
          'lib/core/second.dart -> '
              'lib/features/tuner/model/tuner_reading.dart',
          'lib/core/third.dart -> '
              'lib/features/analyze/engine/clip_analyzer.dart',
        }),
      );
    });

    test('decodes escaped dependency URIs before applying rules', () {
      _write(
        project,
        'lib/core/music/escaped_framework.dart',
        r"import 'package:\x66lutter/widgets.dart';",
      );
      _write(
        project,
        'lib/core/escaped_feature.dart',
        r"import 'package:strumsight/\u{66}eatures/live/engine/live_pipeline.dart';",
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        unorderedEquals({
          'lib/core/music/escaped_framework.dart -> '
              'package:flutter/widgets.dart',
          'lib/core/escaped_feature.dart -> '
              'lib/features/live/engine/live_pipeline.dart',
        }),
      );
    });

    test('canonicalizes percent-encoded dependency URIs', () {
      _write(
        project,
        'lib/core/music/encoded_framework.dart',
        "import 'package:%66lutter/widgets.dart';",
      );
      _write(
        project,
        'lib/core/encoded_package_feature.dart',
        "import 'package:strumsight/%66eatures/live/engine/live_pipeline.dart';",
      );
      _write(
        project,
        'lib/core/encoded_relative_feature.dart',
        "import '../%66eatures/live/engine/live_pipeline.dart';",
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        unorderedEquals({
          'lib/core/music/encoded_framework.dart -> '
              'package:flutter/widgets.dart',
          'lib/core/encoded_package_feature.dart -> '
              'lib/features/live/engine/live_pipeline.dart',
          'lib/core/encoded_relative_feature.dart -> '
              'lib/features/live/engine/live_pipeline.dart',
        }),
      );
    });

    test('checks part and part-of architecture dependencies', () {
      _write(
        project,
        'lib/core/feature_part.dart',
        "part '../features/live/engine/live_pipeline.dart';",
      );
      _write(
        project,
        'lib/core/music/framework_part.dart',
        "part 'package:flutter/widgets.dart';",
      );
      _write(
        project,
        'lib/core/owned_by_feature.dart',
        "part of '../features/live/live_library.dart';",
      );
      _write(
        project,
        'lib/core/music/owned_by_framework.dart',
        "part of 'package:flutter/widgets.dart';",
      );
      _write(
        project,
        'lib/features/live/named_library.dart',
        "part '../../core/named_feature_part.dart';",
      );
      _write(
        project,
        'lib/core/named_feature_part.dart',
        'part of live_feature;',
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        unorderedEquals({
          'lib/core/feature_part.dart -> '
              'lib/features/live/engine/live_pipeline.dart',
          'lib/core/music/framework_part.dart -> '
              'package:flutter/widgets.dart',
          'lib/core/owned_by_feature.dart -> '
              'lib/features/live/live_library.dart',
          'lib/core/music/owned_by_framework.dart -> '
              'package:flutter/widgets.dart',
          'lib/core/named_feature_part.dart -> '
              'lib/features/live/named_library.dart',
        }),
      );
    });

    test('keeps shared music and WAV codec domains framework-free', () {
      _write(
        project,
        'lib/core/music/chord.dart',
        "import 'package:flutter/foundation.dart';",
      );
      _write(
        project,
        'lib/core/audio/codec/adapter.dart',
        "import 'package:dio/dio.dart';",
      );
      _write(
        project,
        'lib/core/music/progression.dart',
        "import 'package:riverpod/riverpod.dart';",
      );
      _write(
        project,
        'lib/core/audio/codec/preferences.dart',
        "import 'package:shared_preferences/shared_preferences.dart';",
      );
      _write(
        project,
        'lib/core/music/label.dart',
        "import '../../l10n/app_localizations.dart';",
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        containsAll({
          'lib/core/music/chord.dart -> package:flutter/foundation.dart',
          'lib/core/audio/codec/adapter.dart -> package:dio/dio.dart',
          'lib/core/music/progression.dart -> package:riverpod/riverpod.dart',
          'lib/core/audio/codec/preferences.dart -> '
              'package:shared_preferences/shared_preferences.dart',
          'lib/core/music/label.dart -> lib/l10n/app_localizations.dart',
        }),
      );
    });

    test('keeps the practice domain framework-free', () {
      _write(
        project,
        'lib/features/practice/domain/model/beat_position.dart',
        "import 'package:flutter/foundation.dart';",
      );
      _write(
        project,
        'lib/features/practice/domain/model/tempo.dart',
        "import 'dart:math';",
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        unorderedEquals({
          'lib/features/practice/domain/model/beat_position.dart -> '
              'package:flutter/foundation.dart',
        }),
      );
    });

    test('allows public APIs and core while blocking feature internals', () {
      _write(project, 'lib/features/analyze/screens/analyze_screen.dart', '''
import '../../live/public.dart';
import '../../live/engine/live_pipeline.dart';
import 'package:strumsight/features/tuner/providers/tuner_provider.dart';
import '../../../core/music/chord.dart';
''');

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        unorderedEquals({
          'lib/features/analyze/screens/analyze_screen.dart -> '
              'lib/features/live/engine/live_pipeline.dart',
          'lib/features/analyze/screens/analyze_screen.dart -> '
              'lib/features/tuner/providers/tuner_provider.dart',
        }),
      );
    });

    // Regression for the E04-R21 halt H3 (ADR 0112 self-heal, ADR 0176,
    // 2026-08-06). ADR 0089 designates `song_trainer/domain/public.dart` as the
    // cross-feature entry point, but the checker previously accepted ONLY the
    // feature-root `public.dart`, so the first cross-feature consumer (the
    // ai_tutor Song adapter/tool) was flagged and the round could not build in
    // scope. A cross-feature import of a nested `public.dart` barrel must be
    // allowed; reaching a non-`public.dart` file inside the feature must still
    // be flagged.
    test('allows nested public.dart barrels but blocks feature internals', () {
      _write(
        project,
        'lib/features/ai_tutor/application/tools/song_tutor_tools.dart',
        '''
import '../../../song_trainer/domain/public.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
''',
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      // The designated nested barrel is NOT a violation.
      expect(
        report.violations.map((violation) => violation.key),
        isNot(
          contains(
            'lib/features/ai_tutor/application/tools/song_tutor_tools.dart -> '
            'lib/features/song_trainer/domain/public.dart',
          ),
        ),
      );
      // Reaching a concrete internal model file is still a violation.
      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        contains(
          'lib/features/ai_tutor/application/tools/song_tutor_tools.dart -> '
          'lib/features/song_trainer/domain/models/song_document.dart',
        ),
      );
    });

    test('rejects raw frame payloads from vision persistence', () {
      _write(
        project,
        'lib/features/vision/data/persistence/vision_session_repository.dart',
        '''
import '../landmarks/hand_landmark_provider.dart';

final class VisionSessionRepository {
  const VisionSessionRepository(this.image);

  final VisionImage image;
}
''',
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        contains(
          'lib/features/vision/data/persistence/vision_session_repository.dart '
          '-> raw vision payload VisionImage in persistence',
        ),
      );
    });

    test('rejects raw pixel buffers from vision provider state', () {
      _write(
        project,
        'lib/features/vision/application/vision_session_state.dart',
        '''
import 'dart:typed_data';

final class VisionSessionState {
  const VisionSessionState(this.pixels);

  final Uint8List pixels;
}
''',
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        contains(
          'lib/features/vision/application/vision_session_state.dart '
          '-> raw vision payload Uint8List in provider state',
        ),
      );
    });

    test('ignores imports inside comments', () {
      _write(project, 'lib/core/music/commented.dart', '''
// import 'package:flutter/widgets.dart';
/*
import 'package:dio/dio.dart';
*/
const example = "import 'package:flutter/foundation.dart';";
''');

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(report.violations, isEmpty);
    });

    test('continues scanning after raw strings in library metadata', () {
      _write(project, 'lib/core/music/annotated.dart', r'''
@Marker(r'ends with \')
library annotated;
import 'package:flutter/widgets.dart';
''');

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        contains(
          'lib/core/music/annotated.dart -> package:flutter/widgets.dart',
        ),
      );
    });

    test('fails when an allowlist entry no longer describes a violation', () {
      _write(project, 'lib/core/safe.dart', 'const safe = true;');
      const stale = 'lib/core/old.dart -> lib/features/live/engine/old.dart';

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {stale},
      );

      expect(report.unexpectedViolations, isEmpty);
      expect(report.staleAllowlistEntries, [stale]);
      expect(report.isClean, isFalse);
    });

    test('does not allowlist hard core or domain boundaries', () {
      _write(
        project,
        'lib/core/bridge.dart',
        "import '../features/live/engine/live_pipeline.dart';",
      );
      _write(
        project,
        'lib/core/music/chord.dart',
        "import 'package:flutter/foundation.dart';",
      );
      const coreViolation =
          'lib/core/bridge.dart -> '
          'lib/features/live/engine/live_pipeline.dart';
      const domainViolation =
          'lib/core/music/chord.dart -> package:flutter/foundation.dart';

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {coreViolation, domainViolation},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        unorderedEquals({coreViolation, domainViolation}),
      );
      expect(
        report.staleAllowlistEntries,
        unorderedEquals({coreViolation, domainViolation}),
      );
      expect(report.isClean, isFalse);
    });
  });
}

void _write(Directory project, String relativePath, String contents) {
  final file = File('${project.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
