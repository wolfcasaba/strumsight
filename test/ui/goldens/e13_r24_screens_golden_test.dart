// Golden snapshots of the E13-R24 Song import, import-preview, and editor
// (V2) screens, at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0 — the two frames the round brief §7/A9 requires.
// Pattern and sizing follow the merged
// `test/ui/goldens/e13_r23_screens_golden_test.dart` precedent.
//
// E15-R05 correction: `theme` is `SsDarkTheme.data()`, not the original
// `AppTheme.dark()` — all three screens now use design-system components
// whose `Theme.of(context).extension<SsColorScheme>()!` null-check crashes
// under the bare legacy theme (`SsDarkTheme.data()` is additive-only,
// `AppTheme.dark()` + design-system extensions, ADR 0466 D2).
//
// Recorded on x86_64 (ADR 0426, §0.0/B/R9) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart' show SsDarkTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/import/import_preview.dart';
import 'package:strumsight/features/song_trainer/application/import/song_import_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/importer_registry.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_preview_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _compactPortrait = Size(412, 915);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const <Override>[],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: SsDarkTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

final class _NoopFilePicker implements FilePickerAdapter {
  const _NoopFilePicker();

  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async => null;
}

final class _NoopAssetRepository implements SongAssetRepository {
  const _NoopAssetRepository();

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(SongAssetWriteRequest request) =>
      throw UnimplementedError();
  @override
  Future<AppResult<Uint8List?>> get(String sha256) async =>
      const AppResult<Uint8List?>.success(null);
  @override
  Future<AppResult<SongAssetSummary?>> summary(String sha256) async =>
      const AppResult<SongAssetSummary?>.success(null);
  @override
  Future<AppResult<void>> incrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);
  @override
  Future<AppResult<void>> decrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);
  @override
  Future<AppResult<void>> permanentlyDelete(String sha256) async =>
      const AppResult<void>.success(null);
}

SongDocument _editorDocument() {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('golden-editor'),
    revision: 0,
    metadata: SongMetadata(title: 'Golden Editor Song', artist: 'Fixtures'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'golden-editor.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
      SongSection(
        id: SongSectionId('chorus'),
        name: 'Chorus',
        startMeasure: 1,
        endMeasureExclusive: 2,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
    tracks: <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: const <SongChordEvent>[],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('song import — $suffix', (tester) async {
      final controller = SongImportController(
        registry: const ImporterRegistry(importers: <SongImporter>[]),
        repository: InMemorySongRepository(),
        workspaceRoot: () async => throw StateError('workspace is not used'),
      );
      addTearDown(controller.dispose);
      await _pump(
        tester,
        const SongImportScreen(),
        overrides: <Override>[
          songImportControllerProvider.overrideWithValue(controller),
          songFilePickerAdapterProvider.overrideWithValue(
            const _NoopFilePicker(),
          ),
          songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r24_song_import_$suffix');
    });

    testWidgets('song import preview — $suffix', (tester) async {
      await _pump(
        tester,
        SongImportPreviewScreen(
          preview: ImportPreview(
            displayName: 'golden-song.musicxml',
            byteLength: 4096,
            format: 'MusicXML',
            warnings: const <String>['songImport.musicXml.timingQuantized'],
            parts: const <ImportPartPreview>[
              ImportPartPreview(
                id: 'part-1',
                name: 'Guitar',
                staffCount: 1,
                noteCount: 42,
                isPolyphonic: false,
                chordSymbolCount: 8,
                hasTablature: false,
              ),
            ],
          ),
        ),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r24_song_import_preview_$suffix');
    });

    testWidgets('song editor — $suffix', (tester) async {
      await _pump(
        tester,
        const SongEditorScreen(songId: 'golden-editor'),
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(
            InMemorySongRepository()..create(_editorDocument()),
          ),
          songAssetRepositoryProvider.overrideWithValue(
            const _NoopAssetRepository(),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r24_song_editor_$suffix');
    });
  }
}
