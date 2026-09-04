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

  // E07-R02: `lib/features/practice_generator/domain/` is new and not yet
  // among `checkArchitecture`'s hard-coded shared-domain prefixes (only
  // `lib/core/music/`, `lib/core/audio/codec/` and
  // `lib/features/practice/domain/` are covered there today). Widening that
  // list lives in `tool/check_architecture.dart`, which is outside this
  // round's allowed-paths — so this scans the real, checked-in source
  // directly for the same forbidden dependencies (ADR 0257 §6, A1/A8).
  group('practice generator domain stays framework-free (E07-R02)', () {
    test('no Flutter, dart:ui, DateTime.now(), or Random in the domain', () {
      final domainDir = Directory('lib/features/practice_generator/domain');
      expect(domainDir.existsSync(), isTrue);

      final offenders = <String>[];
      for (final entity in domainDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(
          _forbiddenDomainMarkerOffenders(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    // Regression for the E07-R09 halt H5 (ADR 0112 self-heal, 2026-08-16,
    // docs/LESSONS.md L291): the scan above used to match forbidden markers
    // against the RAW file text, so `exercise_prescription.dart`'s own doc
    // comment — truthfully documenting the purity guarantee this very check
    // enforces — tripped the check it was describing (measured, exact wording
    // from the failing Full Gate run,
    // https://github.com/wolfcasaba/strumsight/actions/runs/31922993201).
    // Comments and string literals must be excluded from the scan; a real
    // occurrence in executable code must still be caught.
    test('ignores forbidden markers inside comments and string literals', () {
      const measuredPurityDocComment = '''
/// The bounded, measurable execution recipe for one chosen
/// [ExerciseCandidate] (SDD Ch8 Kör 9, ADR 0294).
///
/// Deliberately out of scope (later rounds, ADR 0294 §Kontextus):
/// plan assembly, validator/repair, priority/selection. Flutter-free,
/// `DateTime.now()`-free, `Random`-free — every input is supplied by the
/// caller (ADR 0257 §5-6).
library;
''';
      expect(
        _forbiddenDomainMarkerOffenders(
          'memory.dart',
          measuredPurityDocComment,
        ),
        isEmpty,
      );

      const stringLiteralExplanation =
          "throw StateError('DateTime.now( must never appear here');";
      expect(
        _forbiddenDomainMarkerOffenders(
          'memory.dart',
          stringLiteralExplanation,
        ),
        isEmpty,
      );

      const realWallClockCall = 'final started = DateTime.now();';
      expect(
        _forbiddenDomainMarkerOffenders('memory.dart', realWallClockCall),
        ['memory.dart contains "DateTime.now("'],
      );

      const realRandomCall = 'final roll = Random().nextInt(6);';
      expect(_forbiddenDomainMarkerOffenders('memory.dart', realRandomCall), [
        'memory.dart contains "Random("',
      ]);

      const realFlutterImport = "import 'package:flutter/widgets.dart';";
      expect(
        _forbiddenDomainMarkerOffenders('memory.dart', realFlutterImport),
        ['memory.dart contains "package:flutter/"'],
      );
    });
  });

  // E08-R02: Gamification enters as a new feature-domain root. Its stable
  // events must remain portable across the later reward ledger and outbox.
  group('gamification domain stays framework-free (E08-R02)', () {
    test(
      'no framework, storage, wall-clock, or random source in the domain',
      () {
        final domainDir = Directory('lib/features/gamification/domain');
        expect(domainDir.existsSync(), isTrue);

        final offenders = <String>[];
        for (final entity in domainDir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          offenders.addAll(
            _forbiddenGamificationDomainMarkerOffenders(
              entity.path,
              entity.readAsStringSync(),
            ),
          );
        }

        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );
  });

  group('gamification application stays framework-free and presentation keeps '
      'storage in data (E08-R08)', () {
    test('enforces the layer-specific dependency boundaries', () {
      final applicationDir = Directory('lib/features/gamification/application');
      final presentationDir = Directory(
        'lib/features/gamification/presentation',
      );
      expect(applicationDir.existsSync(), isTrue);

      final offenders = <String>[];
      for (final entity in applicationDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(
          _forbiddenGamificationDomainMarkerOffenders(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }
      if (presentationDir.existsSync()) {
        for (final entity in presentationDir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          offenders.addAll(
            _forbiddenGamificationPresentationStorageMarkerOffenders(
              entity.path,
              entity.readAsStringSync(),
            ),
          );
        }
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the reused guard detects a direct SharedPreferences import', () {
      const directImport =
          "import 'package:shared_preferences/shared_preferences.dart';";

      expect(
        _forbiddenGamificationDomainMarkerOffenders(
          'application.dart',
          directImport,
        ),
        <String>['application.dart contains "package:shared_preferences/"'],
      );
    });

    test('the presentation guard detects direct storage imports', () {
      const directImport =
          "import 'package:shared_preferences/shared_preferences.dart';";

      expect(
        _forbiddenGamificationPresentationStorageMarkerOffenders(
          'presentation.dart',
          directImport,
        ),
        <String>['presentation.dart contains "package:shared_preferences/"'],
      );
    });

    // Regression for E08-R12/H3 (Full Gate run 32393885486): the original
    // E08-R08 scan reused the domain/application marker set for presentation
    // and therefore rejected the three legitimate Flutter UI files below.
    test('presentation allows the measured Flutter UI imports', () {
      const measuredPresentationImports = <String, String>{
        'lib/features/gamification/presentation/screens/'
                'streak_detail_screen.dart':
            "import 'package:flutter/material.dart';",
        'lib/features/gamification/presentation/widgets/'
                'streak_status_card.dart':
            "import 'package:flutter/material.dart';",
        'lib/features/gamification/presentation/widgets/'
                'weekly_consistency_card.dart':
            "import 'package:flutter/material.dart';",
      };

      final offenders = <String>[
        for (final entry in measuredPresentationImports.entries)
          ..._forbiddenGamificationPresentationStorageMarkerOffenders(
            entry.key,
            entry.value,
          ),
      ];

      expect(offenders, isEmpty, reason: offenders.join('\n'));
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

    test('blocks Practice Generator feature internals in both directions', () {
      _write(
        project,
        'lib/features/practice_generator/application/practice_planner.dart',
        "import '../../learn/application/learn_progress_reader.dart';",
      );
      _write(
        project,
        'lib/features/learn/application/practice_plan_adapter.dart',
        "import '../../practice_generator/application/practice_planner.dart';",
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(
        report.unexpectedViolations.map((violation) => violation.key),
        containsAll({
          'lib/features/practice_generator/application/practice_planner.dart '
              '-> lib/features/learn/application/learn_progress_reader.dart',
          'lib/features/learn/application/practice_plan_adapter.dart -> '
              'lib/features/practice_generator/application/practice_planner.dart',
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

    // E99-R18 (GOV-12): the generated-barrel fragments live at
    // `lib/features/<f>/public/<topic>.dart`. They are feature-INTERNAL:
    // a cross-feature import of a fragment must still be flagged, because
    // the barrel is regenerated from them and is the SOLE cross-feature
    // entry point. The feature-boundary rule does not loosen.
    test(
      'flags cross-feature imports of public.dart fragments as violations',
      () {
        _write(
          project,
          'lib/features/ai_tutor/application/tools/song_tutor_tools.dart',
          '''
import '../../../practice_generator/public/data.dart';
import 'package:strumsight/features/practice_generator/public/domain.dart';
''',
        );

        final report = checkArchitecture(
          projectRoot: project,
          allowlist: const {},
        );

        expect(
          report.unexpectedViolations.map((violation) => violation.key),
          containsAll({
            'lib/features/ai_tutor/application/tools/song_tutor_tools.dart -> '
                'lib/features/practice_generator/public/data.dart',
            'lib/features/ai_tutor/application/tools/song_tutor_tools.dart -> '
                'lib/features/practice_generator/public/domain.dart',
          }),
        );
      },
    );

    test('allows imports of a fragment from inside the same feature', () {
      _write(
        project,
        'lib/features/practice_generator/application/service/foo.dart',
        "import '../public/data.dart';",
      );

      final report = checkArchitecture(
        projectRoot: project,
        allowlist: const {},
      );

      expect(report.unexpectedViolations, isEmpty);
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

  group('design system boundaries (E13-R02)', () {
    test('real design system source has no feature dependency', () {
      final designSystemDir = Directory('lib/core/design_system');
      expect(designSystemDir.existsSync(), isTrue);

      final offenders = <String>[];
      for (final entity in designSystemDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(
          _forbiddenDesignSystemFeatureImports(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test(
      'real production source reaches the design system only via public.dart',
      () {
        final libDir = Directory('lib');
        final offenders = <String>[];
        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          if (entity.path.contains('/core/design_system/')) continue;
          offenders.addAll(
            _forbiddenDesignSystemInternalImports(
              entity.path,
              entity.readAsStringSync(),
            ),
          );
        }

        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );

    test(
      'boundary parser rejects a feature import and an internal barrel bypass',
      () {
        expect(
          _forbiddenDesignSystemFeatureImports(
            'lib/core/design_system/example.dart',
            "import 'package:strumsight/features/live/public.dart';",
          ),
          [
            'lib/core/design_system/example.dart -> package:strumsight/features/live/public.dart',
          ],
        );
        expect(
          _forbiddenDesignSystemInternalImports(
            'lib/core/widgets/example.dart',
            "import '../design_system/foundations/ss_spacing.dart';",
          ),
          [
            'lib/core/widgets/example.dart -> ../design_system/foundations/ss_spacing.dart',
          ],
        );
        expect(
          _forbiddenDesignSystemInternalImports(
            'lib/core/widgets/example.dart',
            "import '../design_system/public.dart';",
          ),
          isEmpty,
        );
      },
    );
  });

  // E08-R24 — A4 architecture guard: the `practice` and `learn` features
  // must NOT import any internal file from `gamification`; the only allowed
  // entry point is `public.dart` (ADR 0390 1. döntés, brief §5.1). The
  // generic `crossFeatureImportsMustUsePublicApi` rule above only fires on
  // file-tree-level scans; this group adds an explicit assertion against
  // the contracted adapter boundary so a future regression that bypasses
  // public.dart trips the targeted test.
  group('gamification adapter boundary — A4 (E08-R24)', () {
    final allowedSourceRoots = <String>[
      'lib/features/practice/',
      'lib/features/learn/',
    ];
    final gamificationPublicMarker = 'gamification/public.dart';

    for (final root in allowedSourceRoots) {
      test('$root reaches gamification only through public.dart', () {
        final sourceDir = Directory(root);
        expect(sourceDir.existsSync(), isTrue, reason: 'missing $root');

        final offenders = <String>[];
        for (final entity in sourceDir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          offenders.addAll(
            _forbiddenGamificationInternalImports(
              entity.path,
              entity.readAsStringSync(),
              gamificationPublicMarker,
            ),
          );
        }
        expect(offenders, isEmpty, reason: offenders.join('\n'));
      });
    }

    test('the boundary detector flags a non-public gamification import', () {
      const directImport =
          "import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';";
      expect(
        _forbiddenGamificationInternalImports(
          'lib/features/practice/application/gamification_practice_adapter.dart',
          directImport,
          gamificationPublicMarker,
        ),
        <String>[
          'lib/features/practice/application/gamification_practice_adapter.dart '
              '-> package:strumsight/features/gamification/data/'
              'local_reward_ledger_repository.dart',
        ],
      );
    });

    test('the boundary detector accepts the public.dart barrel', () {
      const allowedImport =
          "import 'package:strumsight/features/gamification/public.dart';";
      expect(
        _forbiddenGamificationInternalImports(
          'lib/features/practice/application/gamification_practice_adapter.dart',
          allowedImport,
          gamificationPublicMarker,
        ),
        isEmpty,
      );
    });
  });

  // E08-R26 — Cross-feature gamification adapter boundary (A6).
  //
  // Four new adapter files in the analyze / vision / ai_tutor /
  // practice_generator features must import gamification ONLY through
  // its `public.dart` barrel. They must also import their OWN source
  // feature only through the feature's public barrels — including the
  // nested `vision/domain/integration/public.dart` barrel for the
  // vision adapter (ADR 0392 §0.0/3 + §0.0/6).
  //
  // The four adapter paths are in the brief's allowed list; this
  // group ensures no production edit sneaks an internal import past
  // the architecture guard.
  group('cross-feature gamification adapter boundary — A6 (E08-R26)', () {
    final adapters = <String>[
      'lib/features/analyze/application/gamification_analysis_adapter.dart',
      'lib/features/vision/application/gamification_vision_adapter.dart',
      'lib/features/ai_tutor/application/gamification_tutor_adapter.dart',
      'lib/features/practice_generator/application/gamification_plan_adapter.dart',
    ];

    test('each adapter reaches gamification only through public.dart', () {
      final offenders = <String>[];
      for (final path in adapters) {
        final source = File(path).readAsStringSync();
        offenders.addAll(
          _forbiddenGamificationInternalImports(
            path,
            source,
            'gamification/public.dart',
          ),
        );
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('each adapter reaches its OWN source feature only through '
        'public.dart barrels', () {
      final offenders = <String>[];
      for (final path in adapters) {
        final source = File(path).readAsStringSync();
        offenders.addAll(
          _forbiddenFeatureInternalImports(
            path,
            source,
            _ownFeaturePublicMarkers(path),
          ),
        );
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('each adapter does NOT import any other feature\'s internals '
        '(cross-feature bleed guard)', () {
      final offenders = <String>[];
      for (final path in adapters) {
        final source = File(path).readAsStringSync();
        offenders.addAll(
          _forbiddenOtherFeatureImports(path, source, _ownFeature(path)),
        );
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the boundary detector flags an internal source-feature import', () {
      const directImport =
          "import 'package:strumsight/features/analyze/model/analyze_result.dart';";
      expect(
        _forbiddenFeatureInternalImports(
          'lib/features/analyze/application/gamification_analysis_adapter.dart',
          directImport,
          const <String>{
            'analyze/public.dart',
            'analyze/domain/integration/public.dart',
          },
        ),
        <String>[
          'lib/features/analyze/application/gamification_analysis_adapter.dart '
              '-> package:strumsight/features/analyze/model/analyze_result.dart',
        ],
      );
    });

    test(
      'the boundary detector accepts the vision nested integration barrel',
      () {
        const allowedImport =
            "import 'package:strumsight/features/vision/domain/integration/public.dart';";
        expect(
          _forbiddenFeatureInternalImports(
            'lib/features/vision/application/gamification_vision_adapter.dart',
            allowedImport,
            const <String>{
              'vision/public.dart',
              'vision/domain/integration/public.dart',
            },
          ),
          isEmpty,
        );
      },
    );
  });

  // E09-R05: Community enters as a new feature-domain root. Per
  // ADR 0399 §1 / §5.1 the Community domain MUST stay
  // framework-free; the cross-feature boundary uses public.dart as
  // the SOLE cross-feature entry point. The test groups here mirror
  // the E07-R02 / E08-R02 minimal pattern: a recursive scan of the
  // domain tree plus explicit boundary tests against the cross-
  // feature import shape. Running the same scan without a new
  // `tool/check_architecture.dart` entry keeps this round inside
  // its `allowed_paths` (ADR 0399 2. döntés).
  group('community domain stays framework-free (E09-R05)', () {
    test(
      'no framework, storage, wall-clock, or random source in the domain',
      () {
        final domainDir = Directory('lib/features/community/domain');
        expect(domainDir.existsSync(), isTrue);

        final offenders = <String>[];
        for (final entity in domainDir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) continue;
          offenders.addAll(
            _forbiddenCommunityDomainMarkerOffenders(
              entity.path,
              entity.readAsStringSync(),
            ),
          );
        }

        expect(offenders, isEmpty, reason: offenders.join('\n'));
      },
    );

    test('the boundary detector flags a direct Flutter import', () {
      const directImport = "import 'package:flutter/foundation.dart';";

      expect(
        _forbiddenCommunityDomainMarkerOffenders(
          'community_profile.dart',
          directImport,
        ),
        <String>['community_profile.dart contains "package:flutter/"'],
      );
    });

    test('the boundary detector flags a direct DateTime.now() call', () {
      const directCall = 'final now = DateTime.now();';

      expect(
        _forbiddenCommunityDomainMarkerOffenders(
          'cursor_page.dart',
          directCall,
        ),
        <String>['cursor_page.dart contains "DateTime.now("'],
      );
    });
  });

  group('community is reachable only through public.dart (E09-R05)', () {
    test('everywhere under lib/ imports community only via public.dart', () {
      final libDir = Directory('lib');
      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // Skip the community feature itself — its INTERNAL imports
        // of its own domain are legal (community may import its own
        // entities / value objects).
        if (entity.path.contains('/features/community/')) continue;
        offenders.addAll(
          _forbiddenCommunityInternalImports(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the boundary detector accepts the community public.dart barrel', () {
      const allowedImport =
          "import 'package:strumsight/features/community/public.dart';";

      expect(
        _forbiddenCommunityInternalImports(
          'lib/features/analyze/application/example.dart',
          allowedImport,
        ),
        isEmpty,
      );
    });

    test('the boundary detector rejects a direct community internal import', () {
      const directImport =
          "import 'package:strumsight/features/community/domain/entities/community_post.dart';";

      expect(
        _forbiddenCommunityInternalImports(
          'lib/features/analyze/application/example.dart',
          directImport,
        ),
        <String>[
          'lib/features/analyze/application/example.dart -> '
              'package:strumsight/features/community/domain/entities/'
              'community_post.dart',
        ],
      );
    });
  });

  group('community does not import other features (E09-R05)', () {
    test('community stays one-way, gated by public.dart as outgoing only', () {
      // The community feature does not need to import anything from
      // another feature today (A6, brief §6). If a future round
      // introduces such an import, this test will catch it and the
      // team can decide whether the cross-feature boundary needs a
      // gateway adapter (E08-R26-style). Today the test passes as
      // long as no community file imports a non-self feature path.
      final communityDir = Directory('lib/features/community');
      expect(communityDir.existsSync(), isTrue);

      final offenders = <String>[];
      for (final entity in communityDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(
          _forbiddenCommunityOtherFeatureImports(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  });

  // E14-R04 — the versioned RecognitionFrame contract enters as a new
  // domain root inside the existing `live` feature (ADR 0505 D1). The
  // `tool/check_architecture.dart` shared-domain prefix list is NOT
  // extended (measured: `_isSharedDomain` offers no extension point,
  // ADR 0505 §0.0 R3) — this mirrors the `practice_generator/domain`
  // (`:23`), `gamification/domain` (`:101`) and `community/domain`
  // (`:982`) self-scanning pattern instead.
  group('recognition domain stays framework-free (E14-R04)', () {
    test('no Flutter/Riverpod imports in domain/recognition', () {
      final domainDir = Directory('lib/features/live/domain/recognition');
      expect(domainDir.existsSync(), isTrue);

      final offenders = <String>[];
      for (final entity in domainDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(
          _forbiddenRecognitionDomainMarkerOffenders(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }

      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('the boundary detector flags a direct Flutter import', () {
      const directImport = "import 'package:flutter/foundation.dart';";

      expect(
        _forbiddenRecognitionDomainMarkerOffenders(
          'strum_prediction.dart',
          directImport,
        ),
        <String>['strum_prediction.dart contains "package:flutter/"'],
      );
    });

    test('the boundary detector allows package:meta (ADR 0505 §0.0 R4)', () {
      const metaImport = "import 'package:meta/meta.dart';";

      expect(
        _forbiddenRecognitionDomainMarkerOffenders(
          'strum_prediction.dart',
          metaImport,
        ),
        isEmpty,
      );
    });

    // ADR 0505 D5 / §0.0 R5: the five pure contract files may reach
    // `model/` ONLY via `recognition_runtime_info.dart`; the adapter is
    // the SOLE documented legacy boundary and may additionally reach
    // `live_frame.dart`.
    test('only the adapter reaches live_frame.dart; the rest reach only '
        'recognition_runtime_info.dart under model/', () {
      final domainDir = Directory('lib/features/live/domain/recognition');
      final offenders = <String>[];
      for (final entity in domainDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(
          _forbiddenRecognitionModelImports(
            entity.path,
            entity.readAsStringSync(),
          ),
        );
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test(
      'the boundary detector flags a non-adapter file importing live_frame.dart',
      () {
        const directImport = "import '../../model/live_frame.dart';";

        expect(
          _forbiddenRecognitionModelImports(
            'lib/features/live/domain/recognition/recognition_frame.dart',
            directImport,
          ),
          <String>[
            'lib/features/live/domain/recognition/recognition_frame.dart -> '
                '../../model/live_frame.dart',
          ],
        );
      },
    );

    test(
      'the boundary detector allows the adapter importing live_frame.dart',
      () {
        const directImport = "import '../../model/live_frame.dart';";

        expect(
          _forbiddenRecognitionModelImports(
            'lib/features/live/domain/recognition/live_frame_adapter.dart',
            directImport,
          ),
          isEmpty,
        );
      },
    );

    test('the boundary detector allows recognition_runtime_info.dart from '
        'any contract file', () {
      const allowedImport =
          "import '../../model/recognition_runtime_info.dart';";

      expect(
        _forbiddenRecognitionModelImports(
          'lib/features/live/domain/recognition/recognition_frame.dart',
          allowedImport,
        ),
        isEmpty,
      );
    });
  });
}

void _write(Directory project, String relativePath, String contents) {
  final file = File('${project.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

// `package:flutter/` and `dart:ui` only ever legitimately match inside an
// import/export/part URI, which is itself a string literal — so string
// contents must stay VISIBLE for these two. `DateTime.now(` and `Random(`
// are calls: real occurrences are executable code, never string contents, so
// string contents must be MASKED for these two (otherwise a doc comment or
// error message quoting the call would false-positive — the exact E07-R09
// halt H5 shape). Comments are trivia for every marker and are always
// masked. See the regression test above (ADR 0112 self-heal, 2026-08-16).
const _importUriMarkers = ['package:flutter/', 'dart:ui'];
const _callMarkers = ['DateTime.now(', 'Random('];
const _gamificationImportUriMarkers = [
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:riverpod/',
  'package:shared_preferences/',
  'package:flutter_secure_storage/',
  'package:sqflite/',
  'dart:ui',
];
const _gamificationDirectStorageImportUriMarkers = [
  'package:shared_preferences/',
  'package:flutter_secure_storage/',
  'package:sqflite/',
];
final _dartDirectiveUri = RegExp(
  r'''(?:import|export|part)\s*['"]([^'"]+)['"]''',
);

List<String> _forbiddenDesignSystemFeatureImports(String path, String source) {
  return [
    for (final match in _dartDirectiveUri.allMatches(
      _withoutTrivia(source, maskStrings: false),
    ))
      if (match.group(1) case final uri? when uri.contains('features/'))
        '$path -> $uri',
  ];
}

List<String> _forbiddenDesignSystemInternalImports(String path, String source) {
  return [
    for (final match in _dartDirectiveUri.allMatches(
      _withoutTrivia(source, maskStrings: false),
    ))
      if (match.group(1) case final uri?
          when uri.contains('design_system/') && !uri.endsWith('public.dart'))
        '$path -> $uri',
  ];
}

List<String> _forbiddenDomainMarkerOffenders(String path, String content) {
  final withoutComments = _withoutTrivia(content, maskStrings: false);
  final withoutCommentsAndStrings = _withoutTrivia(content, maskStrings: true);
  return [
    for (final marker in _importUriMarkers)
      if (withoutComments.contains(marker)) '$path contains "$marker"',
    for (final marker in _callMarkers)
      if (withoutCommentsAndStrings.contains(marker))
        '$path contains "$marker"',
  ];
}

List<String> _forbiddenGamificationDomainMarkerOffenders(
  String path,
  String content,
) {
  final withoutComments = _withoutTrivia(content, maskStrings: false);
  final withoutCommentsAndStrings = _withoutTrivia(content, maskStrings: true);
  return [
    for (final marker in _gamificationImportUriMarkers)
      if (withoutComments.contains(marker)) '$path contains "$marker"',
    for (final marker in _callMarkers)
      if (withoutCommentsAndStrings.contains(marker))
        '$path contains "$marker"',
  ];
}

List<String> _forbiddenGamificationPresentationStorageMarkerOffenders(
  String path,
  String content,
) {
  final withoutComments = _withoutTrivia(content, maskStrings: false);
  return [
    for (final marker in _gamificationDirectStorageImportUriMarkers)
      if (withoutComments.contains(marker)) '$path contains "$marker"',
  ];
}

/// Flags any import/export of `features/gamification/...` whose target is
/// NOT the public.dart barrel. Used by the E08-R24 A4 architecture guard
/// to verify the practice and learn features stay on the public surface
/// of the gamification feature (ADR 0390 1. döntés).
List<String> _forbiddenGamificationInternalImports(
  String path,
  String source,
  String publicMarker,
) {
  final withoutComments = _withoutTrivia(source, maskStrings: false);
  final importMatches = _dartDirectiveUri.allMatches(withoutComments);
  return [
    for (final match in importMatches)
      if (match.group(1) case final uri?
          when uri.contains('gamification/') && !uri.endsWith(publicMarker))
        '$path -> $uri',
  ];
}

/// Returns [source] with `//` and `/* */` comments always omitted, and
/// string-literal contents (single/double/triple-quoted) omitted only when
/// [maskStrings] is true. String and comment boundaries are always parsed
/// as atomic units — regardless of [maskStrings] — so a `//` inside a string
/// or a quote inside a comment can never be misread as the other kind of
/// trivia. Not raw-string-aware: acceptable here because that only widens
/// what a marker match could still be checked against, never narrows it.
String _withoutTrivia(String source, {required bool maskStrings}) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final newline = source.indexOf('\n', index);
      index = newline == -1 ? source.length : newline;
      continue;
    }
    if (source.startsWith('/*', index)) {
      var depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth--;
          index += 2;
        } else {
          index++;
        }
      }
      continue;
    }
    final char = source[index];
    if (char == "'" || char == '"') {
      final start = index;
      final triple = source.startsWith('$char$char$char', index);
      final delimiter = triple ? '$char$char$char' : char;
      index += delimiter.length;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        index += (source[index] == r'\' && index + 1 < source.length) ? 2 : 1;
      }
      index = (index + delimiter.length).clamp(0, source.length);
      if (!maskStrings) buffer.write(source.substring(start, index));
      continue;
    }
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

// ── E08-R26 helpers ──────────────────────────────────────────────────────

/// The OWN feature for an adapter path (used to decide which feature's
/// internals are off-limits when checking imports).
String _ownFeature(String adapterPath) {
  // Path layout is `lib/features/<feature>/application/...`.
  final segments = adapterPath.split('/');
  // 0: 'lib'  1: 'features'  2: '<feature>'
  return segments[2];
}

/// Public-barrel markers the OWN feature exposes to cross-feature
/// consumers. The vision adapter is the special case: its nested
/// `domain/integration/public.dart` barrel is ALSO a recognised
/// cross-feature boundary (ADR 0392 §0.0/6).
Set<String> _ownFeaturePublicMarkers(String adapterPath) {
  final feature = _ownFeature(adapterPath);
  final markers = <String>{'$feature/public.dart'};
  if (feature == 'vision') {
    markers.add('vision/domain/integration/public.dart');
  }
  return markers;
}

/// Flags any import whose target lives under `lib/features/<feature>/...`
/// but is NOT one of [allowedMarkers] (each marker is matched as the
/// final path segment, e.g. `'analyze/public.dart'`).
List<String> _forbiddenFeatureInternalImports(
  String path,
  String source,
  Set<String> allowedMarkers,
) {
  final withoutComments = _withoutTrivia(source, maskStrings: false);
  final importMatches = _dartDirectiveUri.allMatches(withoutComments);
  return [
    for (final match in importMatches)
      if (match.group(1) case final uri?
          when _isOffendingImport(
            uri: uri,
            feature: _ownFeature(path),
            allowedMarkers: allowedMarkers,
          ))
        '$path -> $uri',
  ];
}

/// Flags any import that targets a DIFFERENT feature's internals —
/// i.e. any `lib/features/<otherFeature>/...` path other than the
/// adapter's own [ownFeature]. Cross-feature imports must go through
/// the destination feature's `public.dart` barrel.
List<String> _forbiddenOtherFeatureImports(
  String path,
  String source,
  String ownFeature,
) {
  final withoutComments = _withoutTrivia(source, maskStrings: false);
  final importMatches = _dartDirectiveUri.allMatches(withoutComments);
  return [
    for (final match in importMatches)
      if (match.group(1) case final uri?
          when _isCrossFeatureInternalImport(uri: uri, ownFeature: ownFeature))
        '$path -> $uri',
  ];
}

/// `true` when [uri] targets a file inside the same feature but is
/// not one of the [allowedMarkers].
bool _isOffendingImport({
  required String uri,
  required String feature,
  required Set<String> allowedMarkers,
}) {
  if (!uri.contains('features/$feature/')) return false;
  // Match the trailing `.../public.dart` segment regardless of prefix.
  for (final marker in allowedMarkers) {
    if (uri.endsWith(marker)) return false;
  }
  return true;
}

/// `true` when [uri] targets a file inside a DIFFERENT feature, and
/// does NOT end in that feature's `public.dart` barrel.
bool _isCrossFeatureInternalImport({
  required String uri,
  required String ownFeature,
}) {
  // Find the `<feature>/` segment after `features/`.
  final match = RegExp(r'features/([^/]+)/').firstMatch(uri);
  if (match == null) return false;
  final feature = match.group(1);
  if (feature == null || feature == ownFeature) return false;
  // Must go through `<feature>/public.dart` to be allowed.
  return !uri.endsWith('/public.dart');
}

// ── E09-R05 helpers ─────────────────────────────────────────────────────

/// Forbidden import-URI markers for the Community domain
/// (E09-R05 ADR 0399 §1). Mirrors the gamification marker set
/// (E08-R02) — adding a Community-specific storage plugin
/// (`flutter_secure_storage`) would also belong here, but the
/// backend JWT path is delivered through the central `auth` feature.
const _communityImportUriMarkers = [
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:riverpod/',
  'package:shared_preferences/',
  'package:flutter_secure_storage/',
  'package:sqflite/',
  'dart:ui',
];

/// Flags any forbidden framework marker in [path]'s [content] — the
/// E09-R05 analog of `_forbiddenGamificationDomainMarkerOffenders`.
List<String> _forbiddenCommunityDomainMarkerOffenders(
  String path,
  String content,
) {
  final withoutComments = _withoutTrivia(content, maskStrings: false);
  final withoutCommentsAndStrings = _withoutTrivia(content, maskStrings: true);
  return [
    for (final marker in _communityImportUriMarkers)
      if (withoutComments.contains(marker)) '$path contains "$marker"',
    for (final marker in _callMarkers)
      if (withoutCommentsAndStrings.contains(marker))
        '$path contains "$marker"',
  ];
}

/// Flags any cross-feature import of the Community feature that is
/// NOT the `community/public.dart` barrel. Mirrors
/// `_forbiddenGamificationInternalImports` for the Community side
/// (A5, brief §6).
List<String> _forbiddenCommunityInternalImports(String path, String source) {
  const publicMarker = 'community/public.dart';
  final withoutComments = _withoutTrivia(source, maskStrings: false);
  final importMatches = _dartDirectiveUri.allMatches(withoutComments);
  return [
    for (final match in importMatches)
      if (match.group(1) case final uri?
          when uri.contains('community/') && !uri.endsWith(publicMarker))
        '$path -> $uri',
  ];
}

/// Flags any import from a Community file that targets another
/// feature's internals (A6, brief §6). The Community feature today
/// has no cross-feature consumer — any such import lands here as a
/// tripwire.
List<String> _forbiddenCommunityOtherFeatureImports(
  String path,
  String source,
) {
  final withoutComments = _withoutTrivia(source, maskStrings: false);
  final importMatches = _dartDirectiveUri.allMatches(withoutComments);
  return [
    for (final match in importMatches)
      if (match.group(1) case final uri?
          when _isCrossFeatureInternalImport(uri: uri, ownFeature: 'community'))
        '$path -> $uri',
  ];
}

// ── E14-R04 helpers (ADR 0505) ──────────────────────────────────────────

/// Forbidden import-URI markers for the recognition domain (ADR 0505 D1).
/// `package:meta/meta.dart` is deliberately NOT in this list — it is how
/// the domain's classes stay `@immutable` without pulling in
/// `package:flutter/foundation.dart` (ADR 0505 §0.0 R4).
const _recognitionImportUriMarkers = [
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:riverpod/',
  'dart:ui',
];

List<String> _forbiddenRecognitionDomainMarkerOffenders(
  String path,
  String content,
) {
  final withoutComments = _withoutTrivia(content, maskStrings: false);
  return [
    for (final marker in _recognitionImportUriMarkers)
      if (withoutComments.contains(marker)) '$path contains "$marker"',
  ];
}

/// Flags any `model/` import from a `domain/recognition/**` file that is
/// NOT `recognition_runtime_info.dart` — except `live_frame_adapter.dart`,
/// which may ALSO reach `live_frame.dart`, the sole documented legacy
/// boundary (ADR 0505 D5, §0.0 R5).
List<String> _forbiddenRecognitionModelImports(String path, String source) {
  final withoutComments = _withoutTrivia(source, maskStrings: false);
  final importMatches = _dartDirectiveUri.allMatches(withoutComments);
  final isAdapter = path.endsWith('live_frame_adapter.dart');
  return [
    for (final match in importMatches)
      if (match.group(1) case final uri?
          when uri.contains('/model/') &&
              !uri.endsWith('recognition_runtime_info.dart') &&
              !(isAdapter && uri.endsWith('live_frame.dart')))
        '$path -> $uri',
  ];
}
