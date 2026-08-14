import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';

void main() {
  test(
    'migrates 50 legacy sessions idempotently without changing legacy fields',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'full_migration_test_',
      );
      addTearDown(() => root.delete(recursive: true));
      final repository = await FileAnalysisRepository.openAtDirectory(
        directory: root,
        clock: () => DateTime.utc(2026, 8, 13),
      );
      final store = AnalysisMigrationVersionStore.open(analysisRoot: root);
      final sessions = <AnalyzedSession>[
        for (var index = 0; index < 50; index++)
          AnalyzedSession(
            id: 'legacy-$index',
            createdAt: DateTime.utc(2026, 8, 1).add(Duration(minutes: index)),
            title: 'Legacy $index',
            customTitle: index.isEven,
            result: _result(),
          ),
      ];
      final originalPayloads = <String, Map<String, Object?>>{
        for (final session in sessions)
          session.id: _deepCopyJsonObject(session.toJson()),
      };
      final migrator = LegacyLibraryMigrator(
        repository: repository,
        versionStore: store,
        supplier: () async => sessions,
      );

      final first = await migrator.run();
      final second = await migrator.run();

      expect(first.attempted, 50);
      expect(first.migrated, 50);
      expect(first.failed, 0);
      expect(second.attempted, 50);
      expect(second.migrated, 0);
      expect(second.skipped, 50);
      expect(second.failed, 0);
      final summaries = (await repository.list()).valueOrNull!;
      expect(summaries, hasLength(50));
      for (final session in sessions) {
        final document = (await repository.getById(session.id)).valueOrNull!;
        expect(document.id, session.id);
        expect(document.createdAt, session.createdAt);
        final summary = summaries.singleWhere(
          (item) => item.documentId == session.id,
        );
        expect(summary.title, session.title);
        expect(summary.customTitle, session.customTitle);
        final reencoded = session.toJson();
        for (final entry in originalPayloads[session.id]!.entries) {
          expect(
            reencoded[entry.key],
            entry.value,
            reason: 'legacy ${session.id} field ${entry.key} must survive',
          );
        }
      }
    },
  );
}

Map<String, Object?> _deepCopyJsonObject(Map<String, Object?> payload) {
  final decoded = jsonDecode(jsonEncode(payload));
  return Map<String, Object?>.from(decoded as Map<String, Object?>);
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
