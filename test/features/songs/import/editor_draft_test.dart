// A5/A6/A8 — SongEditorScreen draft-safety cells (ADR 0284 §Döntés 4 + §Döntés
// 5, round brief §0.0/B/R10 + R11).
//
//   A5 — a failed save never discards the draft; the failure is NAMED with
//        the repository's `failureCode`, not a generic message.
//   A6 — `canPersist == false` (a validator-fatal persisted document) locks
//        the in-place Save action; the only surviving write path is an
//        explicit copy under a brand-new SongId + `createdInApp` source, and
//        the original stored document is never touched.
//   A8 — leaving the editor with unsaved changes names the consequence
//        (save / discard / keep editing) before the pop is allowed.
//
// MINOR-2 (E13-R24 review) — the "save copy" write path A6 exercises never
// covered the unfixed-copy failure case: saving a copy that STILL carries
// the fatal issue (the user never ran the in-editor fix first) must not
// write anything, and must not strand the editor on an orphaned,
// never-persisted draft with the locked Save button silently re-enabled.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/song_trainer/application/editor/song_editor_controller.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  testWidgets(
    'A5: a failed save keeps the draft on screen and names the failure code',
    (tester) async {
      final repository = _FailingUpdateRepository(_validDocument('draft-a5'));
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(
            const _NoopAssetRepository(),
          ),
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
            home: const SongEditorScreen(songId: 'draft-a5'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('song-editor-title')),
        'Edited while offline',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.byKey(const Key('song-editor-save')));
      await tester.pumpAndSettle();

      // The failure is NAMED — the exact repository error code is on
      // screen, not a generic "something went wrong".
      expect(find.textContaining(SongRepositoryErrorCode.io), findsOneWidget);

      // The edited draft survived the failed save (it was never discarded
      // or replaced by an empty state).
      final id = SongId('draft-a5');
      final state = container.read(songEditorControllerProvider(id)).state;
      expect(state.draft!.metadata.title, 'Edited while offline');
      expect(find.text('Edited while offline'), findsOneWidget);
    },
  );

  testWidgets(
    'A6: canPersist == false locks Save; only a copy with a new SongId and '
    'createdInApp source can be written, and the original stays untouched',
    (tester) async {
      // A document already in storage before this validator existed: its
      // StrumTrack targets a chord event that does not exist, a fatal
      // structural issue (SongValidationCode.strumTargetChordMissing). The
      // id is chosen to be exactly what a fixed-clock controller's first
      // `addChord` call will generate, so the in-editor fix below (the only
      // repair the exposed editor actions can make to this fatal class) is
      // deterministic rather than a race against `DateTime.now()`.
      final fixedClock = DateTime.utc(2026, 8, 4);
      final missingChordId = 'chord-1-${fixedClock.microsecondsSinceEpoch}';
      final now = DateTime.utc(2026, 8, 4);
      final original = SongDocument(
        schemaVersion: songDocumentSchemaVersion,
        id: SongId('legacy-fatal'),
        revision: 3,
        metadata: SongMetadata(title: 'Legacy Song'),
        source: SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'legacy.song',
          sha256: 'a' * 64,
          importedAt: now,
          importerVersion: 'legacy@1',
        ),
        createdAt: now,
        updatedAt: now,
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
        ],
        tempoMap: TempoMap.constant(Tempo(120)),
        meterMap: MeterMap.constant(Meter(4, 4)),
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('strum-track'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum-1'),
                at: Duration.zero,
                direction: StrumDirection.down,
                targetChordId: SongEventId(missingChordId),
              ),
            ],
          ),
        ],
      );
      final repository = _ReadOnlySeedRepository(original);
      final id = SongId('legacy-fatal');
      final editorController = SongEditorController(
        repository: repository,
        assetRepository: const _NoopAssetRepository(),
        clock: () => fixedClock,
      );
      addTearDown(editorController.dispose);
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(
            const _NoopAssetRepository(),
          ),
          songEditorControllerProvider(id).overrideWithValue(editorController),
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
            home: const SongEditorScreen(songId: 'legacy-fatal'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Save (in-place update) is disabled — the persisted source is
      // validator-fatal, so `canPersist` is false.
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('song-editor-save')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('song-editor-save-copy')), findsOneWidget);

      // Fix the fatal reference by adding a chord event — the fixed clock
      // makes its generated id exactly equal the strum event's dangling
      // target, closing the gap `SongValidator` flagged.
      editorController.addChord(measureIndex: 0, symbol: 'C');
      await tester.pump();
      final fixedChordId = editorController.state.draft!.tracks
          .whereType<ChordTrack>()
          .single
          .events
          .single
          .id
          .value;
      expect(fixedChordId, missingChordId);

      // Save (in-place) stays disabled throughout — canPersist reflects the
      // read-only SOURCE, not the live, possibly-fixed draft.
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('song-editor-save')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('song-editor-save-copy')));
      await tester.pumpAndSettle();

      // The write actually lands: the (now-valid) copy persists under its
      // new identity, and the original is untouched — `update()` was never
      // invoked (the fake throws if it is), and the stored original is
      // still the exact same instance/revision.
      expect(repository.stored[id], same(original));
      expect(repository.createCalls, hasLength(1));
      final copy = repository.createCalls.single;
      expect(copy.id, isNot(id));
      expect(copy.source.type, SongSourceType.createdInApp);
      expect(copy.revision, 0);
      expect(
        copy.tracks.whereType<ChordTrack>().single.events.single.id.value,
        fixedChordId,
      );
      expect(
        copy.tracks
            .whereType<StrumTrack>()
            .single
            .events
            .single
            .targetChordId
            ?.value,
        fixedChordId,
      );
      // The editor itself now tracks the new, persisted copy identity.
      expect(editorController.state.persisted?.id, copy.id);
      expect(editorController.state.draft!.id, isNot(id));
    },
  );

  testWidgets(
    'MINOR-2: saving a copy that is still fatal writes nothing and restores '
    'the editor to the untouched original',
    (tester) async {
      // Same read-only-source fixture shape as A6 (a legacy StrumTrack
      // targeting a chord event that does not exist), but this time the
      // in-editor fix (`addChord`) is skipped — the copy carries the exact
      // same fatal issue the original does.
      final now = DateTime.utc(2026, 8, 4);
      final original = SongDocument(
        schemaVersion: songDocumentSchemaVersion,
        id: SongId('legacy-fatal-unfixed'),
        revision: 3,
        metadata: SongMetadata(title: 'Legacy Song'),
        source: SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'legacy.song',
          sha256: 'a' * 64,
          importedAt: now,
          importerVersion: 'legacy@1',
        ),
        createdAt: now,
        updatedAt: now,
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
        ],
        tempoMap: TempoMap.constant(Tempo(120)),
        meterMap: MeterMap.constant(Meter(4, 4)),
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('strum-track'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum-1'),
                at: Duration.zero,
                direction: StrumDirection.down,
                targetChordId: SongEventId('missing-chord'),
              ),
            ],
          ),
        ],
      );
      final repository = _ReadOnlySeedRepository(original);
      final id = SongId('legacy-fatal-unfixed');
      final editorController = SongEditorController(
        repository: repository,
        assetRepository: const _NoopAssetRepository(),
      );
      addTearDown(editorController.dispose);
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(
            const _NoopAssetRepository(),
          ),
          songEditorControllerProvider(id).overrideWithValue(editorController),
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
            home: const SongEditorScreen(songId: 'legacy-fatal-unfixed'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('song-editor-save-copy')), findsOneWidget);

      // Tap "Save copy" WITHOUT fixing the fatal reference first.
      await tester.tap(find.byKey(const Key('song-editor-save-copy')));
      await tester.pumpAndSettle();

      // Nothing was ever written — the still-fatal copy never reaches
      // repository.create.
      expect(repository.createCalls, isEmpty);

      // The editor is restored to the untouched original, not left
      // stranded on the orphaned, unsaved copy.
      expect(editorController.state.persisted?.id, id);
      expect(editorController.state.draft?.id, id);

      // Save (in-place) is still locked — persisted is the original,
      // validator-fatal document again, not null.
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('song-editor-save')))
            .onPressed,
        isNull,
      );
      // The retry path (fix, then save a copy) is still available.
      expect(find.byKey(const Key('song-editor-save-copy')), findsOneWidget);
    },
  );

  testWidgets(
    'MAJOR-2: a failed copy attempt never discards an edit the user made '
    'before saving',
    (tester) async {
      // Same read-only-source shape as MINOR-2 above (a legacy StrumTrack
      // targeting a chord event that does not exist), but this time the
      // user ALSO renames the document before attempting "Save copy" —
      // reproducing the reviewer's probe (E13-R24 review §6.2): the
      // renamed title must survive the failed copy attempt, not be
      // silently replaced by the untouched original's title.
      final now = DateTime.utc(2026, 8, 4);
      final original = SongDocument(
        schemaVersion: songDocumentSchemaVersion,
        id: SongId('legacy-fatal-edited'),
        revision: 3,
        metadata: SongMetadata(title: 'Legacy Song'),
        source: SongSource(
          type: SongSourceType.legacyLocal,
          originalFileName: 'legacy.song',
          sha256: 'a' * 64,
          importedAt: now,
          importerVersion: 'legacy@1',
        ),
        createdAt: now,
        updatedAt: now,
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
        ],
        tempoMap: TempoMap.constant(Tempo(120)),
        meterMap: MeterMap.constant(Meter(4, 4)),
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('strum-track'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum-1'),
                at: Duration.zero,
                direction: StrumDirection.down,
                targetChordId: SongEventId('missing-chord'),
              ),
            ],
          ),
        ],
      );
      final repository = _ReadOnlySeedRepository(original);
      final id = SongId('legacy-fatal-edited');
      final editorController = SongEditorController(
        repository: repository,
        assetRepository: const _NoopAssetRepository(),
      );
      addTearDown(editorController.dispose);
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(
            const _NoopAssetRepository(),
          ),
          songEditorControllerProvider(id).overrideWithValue(editorController),
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
            home: const SongEditorScreen(songId: 'legacy-fatal-edited'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The user renames the document — a live, unsaved edit — but never
      // runs the in-editor fix for the fatal reference.
      await tester.enterText(
        find.byKey(const Key('song-editor-title')),
        'My careful rename',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(editorController.state.draft!.metadata.title, 'My careful rename');

      await tester.tap(find.byKey(const Key('song-editor-save-copy')));
      await tester.pumpAndSettle();

      // Nothing was ever written — the still-fatal copy never reaches
      // repository.create.
      expect(repository.createCalls, isEmpty);

      // The rename SURVIVES the failed copy attempt — this is the exact
      // data loss the reviewer's probe measured (title reverting to
      // "Legacy Song") when the fix incorrectly called `controller.load`.
      expect(editorController.state.draft!.metadata.title, 'My careful rename');

      // The failure reason is named on the surface.
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SongEditorScreen)),
      );
      expect(find.text(l10n.songEditorInvalid), findsOneWidget);

      // Save (in-place) is still locked, and the retry path is still
      // available.
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('song-editor-save')))
            .onPressed,
        isNull,
      );
      expect(find.byKey(const Key('song-editor-save-copy')), findsOneWidget);
    },
  );

  testWidgets(
    'A8: leaving the editor with unsaved changes names the consequence '
    'before the pop is allowed',
    (tester) async {
      final repository = _ReadOnlySeedRepository(_validDocument('draft-a8'));
      final container = ProviderContainer(
        overrides: [
          songRepositoryProvider.overrideWithValue(repository),
          songAssetRepositoryProvider.overrideWithValue(
            const _NoopAssetRepository(),
          ),
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
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const SongEditorScreen(songId: 'draft-a8'),
                      ),
                    ),
                    child: const Text('open editor'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open editor'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('song-editor-title')),
        'Dirty title',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.maybePop());
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(SongEditorScreen)),
      );
      expect(find.text(l10n.songEditorUnsavedBody), findsOneWidget);
      expect(find.text(l10n.songEditorSave), findsWidgets);
      expect(find.text(l10n.songEditorDiscard), findsOneWidget);
      expect(find.text(l10n.songEditorStay), findsOneWidget);

      await tester.tap(find.text(l10n.songEditorStay));
      await tester.pumpAndSettle();
      expect(find.byType(SongEditorScreen), findsOneWidget);
    },
  );
}

SongDocument _validDocument(String id) {
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
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
  );
}

/// Loads [seed] successfully but fails every `update` — the swallowed
/// disk-write error class the project already measured (docs/LESSONS.md).
final class _FailingUpdateRepository implements SongRepository {
  _FailingUpdateRepository(this._document);

  final SongDocument _document;

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async =>
      AppResult<SongDocument?>.success(_document);

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) async => songRepositoryFailure<void>(SongRepositoryErrorCode.io);

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();
  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();
}

/// A document that was already in storage before today's validator existed
/// (A6's "read-only source"). `get` returns it as-is, unvalidated — exactly
/// how a real file-backed repository loads bytes already on disk. `update`
/// throws: A6 requires the original NEVER be rewritten in place, so any
/// accidental `update()` call must fail the test loudly rather than silently
/// "fixing" the fixture.
final class _ReadOnlySeedRepository implements SongRepository {
  _ReadOnlySeedRepository(SongDocument seed) : stored = {seed.id: seed};

  final Map<SongId, SongDocument> stored;
  final List<SongDocument> createCalls = <SongDocument>[];

  @override
  Future<AppResult<SongDocument?>> get(SongId id) async =>
      AppResult<SongDocument?>.success(stored[id]);

  @override
  Future<AppResult<void>> create(SongDocument document) async {
    createCalls.add(document);
    stored[document.id] = document;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw StateError(
    'A6: the read-only original must never be updated in place',
  );

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();
  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();
  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();
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
