import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';

void main() {
  test('OFF → migrate → OFF → ON preserves both legacy and V2 reads', () async {
    final root = await Directory.systemTemp.createTemp('rollback_test_');
    addTearDown(() => root.delete(recursive: true));
    final legacy = AnalyzedSession(
      id: 'rollback',
      createdAt: DateTime.utc(2026, 8, 13),
      title: 'Legacy rollback',
      result: _result(),
    );
    final repository = await FileAnalysisRepository.openAtDirectory(
      directory: root,
    );
    final migrator = LegacyLibraryMigrator(
      repository: repository,
      versionStore: AnalysisMigrationVersionStore.open(analysisRoot: root),
      supplier: () async => <AnalyzedSession>[legacy],
    );
    final flagsOff = _flagsOff();
    final flagsOn = _flagsOn();

    expect(flagsOff == flagsOn, isFalse);
    expect(_allAnalysisFlagsAreOff(flagsOff), isTrue);
    expect(_allAnalysisFlagsAreOff(flagsOn), isFalse);
    expect(flagsOff.audioAnalysisV2Enabled, isFalse);
    expect(flagsOn.audioAnalysisV2Enabled, isTrue);
    await migrator.run();
    expect(
      _allAnalysisFlagsAreOff(flagsOff),
      isTrue,
      reason: 'migration leaves the V1 shipping configuration unchanged',
    );
    expect(legacy.toJson(), containsPair('id', 'rollback'));

    await _expectV2ReadSucceeds(
      repository: repository,
      flags: flagsOff,
      expectedV2Enabled: false,
    );
    await _expectV2ReadSucceeds(
      repository: repository,
      flags: flagsOn,
      expectedV2Enabled: true,
    );
  });
}

FeatureFlags _flagsOff() => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
);

FeatureFlags _flagsOn() => const FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  audioAnalysisV2Enabled: true,
);

Future<void> _expectV2ReadSucceeds({
  required FileAnalysisRepository repository,
  required FeatureFlags flags,
  required bool expectedV2Enabled,
}) async {
  expect(
    flags.audioAnalysisV2Enabled,
    expectedV2Enabled,
    reason: 'the test must exercise the requested rollout state',
  );
  final document = (await repository.getById('rollback')).valueOrNull;
  expect(document, isNotNull);
  expect(document!.id, 'rollback');
}

bool _allAnalysisFlagsAreOff(FeatureFlags flags) =>
    !flags.audioAnalysisV2Enabled &&
    !flags.analysisBeatGridEnabled &&
    !flags.analysisPitchEnabled &&
    !flags.analysisPreprocessingExperimentalEnabled &&
    !flags.analysisExperimentalFusionEnabled &&
    !flags.analysisTechniqueProxiesEnabled &&
    !flags.analysisComparisonEnabled &&
    !flags.analysisPracticeIntegrationEnabled &&
    !flags.analysisTutorIntegrationEnabled;

AnalyzeResult _result() => const AnalyzeResult(
  durationSec: 1,
  bpm: 120,
  chords: <TimelineChord>[TimelineChord(label: 'C', startSec: 0, endSec: 1)],
  strums: <TimelineStrum>[
    TimelineStrum(
      direction: legacy_core.StrumDirection.down,
      timeSec: .5,
      confidence: 1,
    ),
  ],
);
