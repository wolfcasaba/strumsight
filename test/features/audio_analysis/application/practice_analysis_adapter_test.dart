import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/music/strum.dart' as core;
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/public.dart';

void main() {
  const adapter = PracticeAnalysisAdapter();

  test(
    'preserves compiled practice events and target version without scoring',
    () {
      final target = adapter.toAnalysisTarget(_compiled());

      expect(target.targetVersion, 7);
      expect(target.expectedEvents, hasLength(2));
      expect(target.expectedEvents.map((event) => event.time), <Duration>[
        const Duration(microseconds: 1),
        const Duration(microseconds: 2),
      ]);
      expect(
        target.expectedEvents.map((event) => event.type),
        <ExpectedEventType>[
          ExpectedEventType.strum,
          ExpectedEventType.chordChange,
        ],
      );
      expect(target.expectedEvents.first.direction!.name, 'down');
      expect(target.expectedChords, <String>['G']);
    },
  );

  test('adapter exposes evidence fields without a parallel Practice score', () {
    final source = File(
      'lib/features/audio_analysis/application/adapters/'
      'practice_analysis_adapter.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('sessionScore')));
    expect(source, isNot(contains('PracticeScore')));
  });

  test(
    'retry tempo uses inclusive named thresholds and a sixty-percent floor',
    () {
      const tempo = 100.0;
      expect(
        adapter.recommendedRetryTempo(
          targetTempo: tempo,
          timingErrorSeverity: .25,
        ),
        100,
      );
      expect(
        adapter.recommendedRetryTempo(
          targetTempo: tempo,
          timingErrorSeverity: .250001,
        ),
        95,
      );
      expect(
        adapter.recommendedRetryTempo(
          targetTempo: tempo,
          timingErrorSeverity: .5,
        ),
        95,
      );
      expect(
        adapter.recommendedRetryTempo(
          targetTempo: tempo,
          timingErrorSeverity: .500001,
        ),
        90,
      );
      expect(
        adapter.recommendedRetryTempo(
          targetTempo: tempo,
          timingErrorSeverity: .75,
        ),
        90,
      );
      expect(
        adapter.recommendedRetryTempo(
          targetTempo: tempo,
          timingErrorSeverity: .750001,
        ),
        85,
      );
      expect(
        adapter.recommendedRetryTempo(targetTempo: 50, timingErrorSeverity: 1),
        42.5,
      );
    },
  );

  test('OFF integration flags do not instantiate either adapter provider', () {
    final practiceFactory = _CountingPracticeFactory();
    final tutorFactory = _CountingTutorFactory();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(_flagsOffConfig()),
        practiceAnalysisAdapterFactoryProvider.overrideWithValue(
          practiceFactory,
        ),
        tutorAnalysisSnapshotAdapterFactoryProvider.overrideWithValue(
          tutorFactory,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(practiceAnalysisAdapterProvider), isNull);
    expect(container.read(tutorAnalysisSnapshotAdapterProvider), isNull);
    expect(practiceFactory.calls, 0);
    expect(tutorFactory.calls, 0);
  });

  test('integration flags remain OFF in every environment', () {
    for (final environment in AppEnvironment.values) {
      final flags = FeatureFlags.forEnvironment(
        environment,
        accountEnabled: false,
      );
      expect(flags.analysisPracticeIntegrationEnabled, isFalse);
      expect(flags.analysisTutorIntegrationEnabled, isFalse);
    }
  });
}

AppConfig _flagsOffConfig() => const AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

final class _CountingPracticeFactory implements PracticeAnalysisAdapterFactory {
  int calls = 0;

  @override
  PracticeAnalysisAdapter create() {
    calls++;
    return const PracticeAnalysisAdapter();
  }
}

final class _CountingTutorFactory
    implements TutorAnalysisSnapshotAdapterFactory {
  int calls = 0;

  @override
  TutorAnalysisSnapshotAdapter create() {
    calls++;
    return const TutorAnalysisSnapshotAdapter();
  }
}

CompiledPracticeTarget _compiled() => CompiledPracticeTarget(
  definitionId: 'exercise',
  definitionSnapshotVersion: 7,
  tempo: const Tempo(100),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: const <CompiledTargetEvent>[
    CompiledTargetEvent(
      sourceEventId: 'one',
      loopIndex: 0,
      position: BeatPosition(0),
      time: Duration(microseconds: 1),
      barIndex: 0,
      chord: 'G',
      direction: core.StrumDirection.down,
      accent: false,
      optional: false,
    ),
    CompiledTargetEvent(
      sourceEventId: 'two',
      loopIndex: 0,
      position: BeatPosition(480),
      time: Duration(microseconds: 2),
      barIndex: 0,
      chord: 'G',
      direction: null,
      accent: false,
      optional: false,
    ),
  ],
  musicalDuration: const Duration(microseconds: 2),
  ringOutDuration: Duration.zero,
  totalDuration: const Duration(microseconds: 2),
  barBoundaries: const <Duration>[Duration.zero],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const <ExpectedChordSegment>[
    ExpectedChordSegment(
      chord: 'G',
      start: Duration.zero,
      end: Duration(microseconds: 2),
    ),
  ],
  scoringApplicable: true,
);
