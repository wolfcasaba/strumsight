/// K1 — "audio file as a backing track" attach cells.
///
/// The editor's attach button picks an AUDIO file (not a notation file),
/// the bytes reach the content-hash asset store under their real SHA-256,
/// the document gains exactly one `BackingAudioTrack`, and the asset the
/// trainer hand-off value carries is resolvable from the saved document.
/// An oversized or non-playable pick is refused with a named, user-facing
/// message and writes nothing.
///
/// The widget cells run against an in-memory capturing store on purpose:
/// real `dart:io` work never completes inside `testWidgets`' fake-async
/// zone. The temp-directory `FileSongAssetRepository` round-trip is the
/// plain (non-widget) cell below, where real I/O does complete.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/editor/song_editor_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/file_song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
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
  testWidgets('attaching an m4a file writes it once and adds one track', (
    tester,
  ) async {
    final payload = Uint8List.fromList(<int>[9, 8, 7]);
    final hash = crypto.sha256.convert(payload).toString();
    final assetRepository = _CapturingAssetRepository();
    final repository = InMemorySongRepository();
    final document = _document('backing-attach');
    await repository.create(document);
    final container = _container(
      repository: repository,
      assetRepository: assetRepository,
      picker: _AudioPicker(name: 'backing.m4a', payload: payload),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container, document.id.value);
    await _tapAttach(tester);

    final l10n = _localizations(tester);
    expect(
      find.text(l10n.songEditorBackingAttached('backing.m4a', '3 B')),
      findsOneWidget,
    );

    final controller = container.read(
      songEditorControllerProvider(document.id),
    );
    final tracks = controller.state.draft!.tracks
        .whereType<BackingAudioTrack>();
    expect(tracks, hasLength(1));
    expect(assetRepository.requests, hasLength(1));
    final request = assetRepository.requests.single;
    expect(request.bytes, payload);
    expect(request.expectedSha256, hash);
    expect(request.extension, 'm4a');
    // The m4a container is stored as audio: only its audio stream plays,
    // whatever type the platform picker reported.
    expect(request.mimeType, 'audio/mp4');
    expect(request.durationMs, isNull);

    await _drainSnackBar(tester);
  });

  testWidgets('an oversized pick is refused by name and writes nothing', (
    tester,
  ) async {
    final assetRepository = _CapturingAssetRepository();
    final repository = InMemorySongRepository();
    final document = _document('backing-too-large');
    await repository.create(document);
    final picker = _OversizedPicker();
    final container = _container(
      repository: repository,
      assetRepository: assetRepository,
      picker: picker,
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container, document.id.value);
    await _tapAttach(tester);

    final l10n = _localizations(tester);
    expect(find.text(l10n.songEditorBackingTooLarge), findsOneWidget);
    // A 33 MiB pick that declares its size honestly is refused before a
    // single byte is read.
    expect(picker.reads, 0);
    expect(assetRepository.requests, isEmpty);
    final controller = container.read(
      songEditorControllerProvider(document.id),
    );
    expect(
      controller.state.draft!.tracks.whereType<BackingAudioTrack>(),
      isEmpty,
    );

    await _drainSnackBar(tester);
  });

  testWidgets('a pick that under-reports its size is stopped mid-stream', (
    tester,
  ) async {
    final assetRepository = _CapturingAssetRepository();
    final repository = InMemorySongRepository();
    final document = _document('backing-lying-size');
    await repository.create(document);
    final container = _container(
      repository: repository,
      assetRepository: assetRepository,
      picker: _LyingSizePicker(),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container, document.id.value);
    await _tapAttach(tester);

    final l10n = _localizations(tester);
    expect(find.text(l10n.songEditorBackingTooLarge), findsOneWidget);
    expect(assetRepository.requests, isEmpty);

    await _drainSnackBar(tester);
  });

  testWidgets('a container outside the playable set is refused by name', (
    tester,
  ) async {
    final assetRepository = _CapturingAssetRepository();
    final repository = InMemorySongRepository();
    final document = _document('backing-unsupported');
    await repository.create(document);
    final container = _container(
      repository: repository,
      assetRepository: assetRepository,
      picker: _AudioPicker(
        name: 'notes.txt',
        payload: Uint8List.fromList(<int>[1]),
      ),
    );
    addTearDown(container.dispose);

    await _pumpEditor(tester, container, document.id.value);
    await _tapAttach(tester);

    final l10n = _localizations(tester);
    expect(find.text(l10n.songEditorBackingUnsupported), findsOneWidget);
    expect(assetRepository.requests, isEmpty);

    await _drainSnackBar(tester);
  });

  test('the store keeps the attached bytes under their SHA-256', () async {
    final sandbox = Directory.systemTemp.createTempSync('backing_attach_');
    addTearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });
    final payload = Uint8List.fromList(<int>[4, 5, 6, 7]);
    final hash = crypto.sha256.convert(payload).toString();
    final assetRepository = await FileSongAssetRepository.openAtDirectory(
      root: Directory('${sandbox.path}/songs'),
      clock: () => DateTime.utc(2026, 9, 17),
    );
    final repository = InMemorySongRepository();
    final document = _document('backing-store');
    await repository.create(document);
    final controller = SongEditorController(
      repository: repository,
      assetRepository: assetRepository,
    );
    addTearDown(controller.dispose);
    await controller.load(document.id);

    await controller.attachBacking(
      SongAssetWriteRequest(
        bytes: payload,
        assetId: SongAssetId('backing-${hash.substring(0, 16)}'),
        extension: 'm4a',
        expectedSha256: hash,
        mimeType: 'audio/mp4',
      ),
    );

    expect(
      controller.state.draft!.tracks.whereType<BackingAudioTrack>(),
      hasLength(1),
    );
    expect((await assetRepository.get(hash)).valueOrNull, payload);
    final summary = (await assetRepository.summary(hash)).valueOrNull;
    expect(summary, isNotNull);
    expect(summary!.extension, 'm4a');
    expect(summary.mimeType, 'audio/mp4');

    // The launcher cell: the value the trainer route hands to the session
    // controller resolves to the freshly attached asset.
    await controller.save();
    final persisted = (await repository.get(document.id)).valueOrNull!;
    final inputs = SongTrainerControllerInputs(
      compilation: const SongPracticeCompilation.playbackOnly(),
      backingAsset: _backingAssetOf(persisted),
    );
    expect(inputs.backingAsset, isNotNull);
    expect(inputs.backingAsset!.sha256, hash);
    expect(inputs.backingAsset!.extension, 'm4a');
  });
}

ProviderContainer _container({
  required InMemorySongRepository repository,
  required SongAssetRepository assetRepository,
  required FilePickerAdapter picker,
}) => ProviderContainer(
  overrides: [
    songRepositoryProvider.overrideWithValue(repository),
    songAssetRepositoryProvider.overrideWithValue(assetRepository),
    songFilePickerAdapterProvider.overrideWithValue(picker),
  ],
);

Future<void> _pumpEditor(
  WidgetTester tester,
  ProviderContainer container,
  String songId,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SongEditorScreen(songId: songId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapAttach(WidgetTester tester) async {
  final attach = find.byKey(const Key('song-editor-attach-backing'));
  await tester.ensureVisible(attach);
  await tester.tap(attach);
  await tester.pumpAndSettle();
}

AppLocalizations _localizations(WidgetTester tester) => AppLocalizations.of(
  tester.element(find.byKey(const Key('song-editor-attach-backing'))),
);

/// The attach message owns a dismissal timer; draining it leaves the tree
/// timer-free at the end of the test.
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

/// What a launcher does: the backing track names an asset id, the document
/// carries the matching reference.
SongAssetReference? _backingAssetOf(SongDocument document) {
  for (final track in document.tracks) {
    if (track is! BackingAudioTrack) continue;
    for (final asset in document.assets) {
      if (asset.id == track.assetId) return asset;
    }
  }
  return null;
}

SongDocument _document(String id) {
  final now = DateTime.utc(2026, 9, 17);
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

/// Serves one audio pick exactly as the platform adapter would: a real
/// MIME type derived from the extension, and a reopenable byte stream.
final class _AudioPicker implements FilePickerAdapter {
  _AudioPicker({required this.name, required this.payload});

  final String name;
  final Uint8List payload;

  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async => null;

  @override
  Future<ImportSourceFile?> pickAudioFile() async => ImportSourceFile(
    displayName: name,
    byteLength: payload.length,
    mimeType: PlatformFilePickerAdapter.mimeTypeOf(name),
    openRead: () => Stream<List<int>>.value(payload),
  );
}

/// Declares 33 MiB up front. Reading its bytes would be the bug.
final class _OversizedPicker implements FilePickerAdapter {
  var reads = 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async => null;

  @override
  Future<ImportSourceFile?> pickAudioFile() async => ImportSourceFile(
    displayName: 'album.mp3',
    byteLength: 33 * 1024 * 1024,
    mimeType: 'audio/mpeg',
    openRead: () {
      reads++;
      return const Stream<List<int>>.empty();
    },
  );
}

/// Declares one byte and then streams 36 MiB — a picker's declared size is
/// metadata, not a promise.
final class _LyingSizePicker implements FilePickerAdapter {
  @override
  Future<void> dispose() async {}

  @override
  Future<ImportSourceFile?> pickSongFile() async => null;

  @override
  Future<ImportSourceFile?> pickAudioFile() async => ImportSourceFile(
    displayName: 'album.mp3',
    byteLength: 1,
    mimeType: 'audio/mpeg',
    openRead: _chunks,
  );

  static Stream<List<int>> _chunks() async* {
    final chunk = Uint8List(4 * 1024 * 1024);
    for (var index = 0; index < 9; index++) {
      yield chunk;
    }
  }
}

final class _CapturingAssetRepository implements SongAssetRepository {
  final List<SongAssetWriteRequest> requests = <SongAssetWriteRequest>[];

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async {
    requests.add(request);
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
