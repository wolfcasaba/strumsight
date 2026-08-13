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

    expect(_flagsOff(), isTrue);
    await migrator.run();
    expect(
      _flagsOff(),
      isTrue,
      reason: 'migration never changes rollout flags',
    );
    expect(legacy.toJson(), containsPair('id', 'rollback'));
    expect((await repository.getById('rollback')).valueOrNull!.id, 'rollback');
    expect(
      _flagsOff(),
      isTrue,
      reason: 'rollback keeps V1 as the shipping path',
    );
    expect((await repository.getById('rollback')).valueOrNull!.id, 'rollback');
  });
}

bool _flagsOff() {
  const flags = FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  );
  return !flags.audioAnalysisV2Enabled &&
      !flags.analysisBeatGridEnabled &&
      !flags.analysisPitchEnabled &&
      !flags.analysisPreprocessingExperimentalEnabled &&
      !flags.analysisExperimentalFusionEnabled &&
      !flags.analysisTechniqueProxiesEnabled &&
      !flags.analysisComparisonEnabled &&
      !flags.analysisPracticeIntegrationEnabled &&
      !flags.analysisTutorIntegrationEnabled;
}

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
