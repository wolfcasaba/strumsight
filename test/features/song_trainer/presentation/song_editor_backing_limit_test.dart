// Regression (C2-import-guards round 2): the picker enforces
// `ImportLimits.maxSourceBytes` at the data boundary, and the song editor's
// backing attach is the ONE consumer that reads the picked stream directly —
// the import flow is rejected earlier, by `ImporterRegistry._checkSource`, on
// `byteLength` alone. Before this round an oversize backing pick produced an
// empty stream, so `_attachBacking` hit `if (bytes.isEmpty) return;` and did
// nothing at all: no attach, no message, no log. The adapter now refuses with
// the registry's own typed failure and the screen names it through the
// existing ARB message.
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/import_limits.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  const limits = ImportLimits();

  testWidgets('an oversize backing pick reports instead of doing nothing', (
    tester,
  ) async {
    final assetRepository = _RecordingAssetRepository();
    final container = await _pumpEditor(
      tester,
      assetRepository,
      _RealAdapterPicker(_OversizeXFile(limits.maxSourceBytes + 1)),
      'editor-oversize',
    );

    await _tapAttach(tester);

    expect(find.byKey(const Key('song-editor-backing-failed')), findsOneWidget);
    expect(
      find.textContaining(ImportLimitFailureCode.sourceBytesExceeded),
      findsOneWidget,
    );
    expect(assetRepository.putCalls, 0);
    final state = container
        .read(songEditorControllerProvider(SongId('editor-oversize')))
        .state;
    expect(state.draft!.tracks.whereType<BackingAudioTrack>(), isEmpty);
  });

  // Control: the refusal is specific to the budget, not a blanket swallow —
  // a pick inside the budget still attaches with no message.
  testWidgets('a pick inside the budget still attaches', (tester) async {
    final assetRepository = _RecordingAssetRepository();
    final container = await _pumpEditor(
      tester,
      assetRepository,
      _RealAdapterPicker(XFile.fromData(Uint8List(64), path: 'backing.mid')),
      'editor-small',
    );

    await _tapAttach(tester);

    expect(find.byKey(const Key('song-editor-backing-failed')), findsNothing);
    expect(assetRepository.putCalls, 1);
    final state = container
        .read(songEditorControllerProvider(SongId('editor-small')))
        .state;
    expect(state.draft!.tracks.whereType<BackingAudioTrack>(), hasLength(1));
  });
}

Future<ProviderContainer> _pumpEditor(
  WidgetTester tester,
  SongAssetRepository assetRepository,
  FilePickerAdapter picker,
  String id,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = InMemorySongRepository();
  await repository.create(_document(id));
  final container = ProviderContainer(
    overrides: [
      songRepositoryProvider.overrideWithValue(repository),
      songAssetRepositoryProvider.overrideWithValue(assetRepository),
      songFilePickerAdapterProvider.overrideWithValue(picker),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SongEditorScreen(songId: id),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tapAttach(WidgetTester tester) async {
  final attach = find.byKey(const Key('song-editor-attach-backing'));
  // The editor body is a lazily built ListView and the attach button is its
  // last child, so scroll the OUTER scrollable (the editors below build their
  // own) until the button exists, then bring it fully into view.
  await tester.scrollUntilVisible(
    attach,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(attach);
  await tester.tap(attach);
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 750));
}

/// Routes the pick through the REAL adapter conversion; only the platform
/// dialog is stubbed, so the limit contract under test is the production one.
final class _RealAdapterPicker implements FilePickerAdapter {
  _RealAdapterPicker(this.file);

  final XFile file;

  @override
  Future<ImportSourceFile?> pickSongFile() =>
      PlatformFilePickerAdapter.fromXFile(file);

  @override
  Future<void> dispose() async {}
}

/// Reports an oversize length and fails the test if anything reads it.
final class _OversizeXFile extends XFile {
  _OversizeXFile(this.reportedLength) : super('backing.mid');

  final int reportedLength;

  @override
  Future<int> length() async => reportedLength;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) =>
      throw StateError('an oversize pick must not be read');
}

SongDocument _document(String id) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(id),
    revision: 0,
    metadata: SongMetadata(title: id),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: '$id.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
  );
}

final class _RecordingAssetRepository implements SongAssetRepository {
  var putCalls = 0;

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async {
    putCalls++;
    return AppResult<SongAssetStoreReceipt>.success(
      SongAssetStoreReceipt(
        assetId: request.assetId,
        sha256: request.expectedSha256,
        byteLength: request.bytes.length,
        duplicate: false,
      ),
    );
  }

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
