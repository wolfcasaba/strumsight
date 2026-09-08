// M6 (re-audit 2026-09-08) — the library item's Notes field must not throw
// the learner's text away.
//
// MEASURED before this round: `library_item_detail_screen.dart` created the
// notes controller empty in `initState` ("Ephemeral in this round — no notes
// storage/use case exists on the tree") and disposed it on the way out.
// There is no save button, so a learner typed a note about a session, left
// the screen, and the note was gone — silently. The UI-side twin of this
// repo's own "cloud write swallowed by try/catch" trap.
//
//   C1 — a note survives a NEW repository over the same store (the shape an
//        app restart produces),
//   C2 — notes are keyed per item; one item's note never becomes another's,
//   C3 — clearing the field removes the entry rather than storing '',
//   C4 — an unreadable document is a FAILURE, not an innocent empty note,
//        and the next write still lands,
//   C5 — the screen restores what was typed after a re-entry, with no new
//        label or control (the E13-R28 golden stays byte-identical).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_repository.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/library_v2/data/key_value_library_note_repository.dart';
import 'package:strumsight/features/library_v2/domain/library_item.dart';
import 'package:strumsight/features/library_v2/screens/library_item_detail_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// `_AnalysisDetailBody` always references `analysisRepositoryProvider`
/// (for the export action) even when a cell never taps export.
final class _UnusedAnalysisRepository implements AnalysisRepository {
  const _UnusedAnalysisRepository();

  @override
  Future<AppResult<void>> delete(String id) => throw UnimplementedError();

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<List<AnalysisSummary>>> list() => throw UnimplementedError();

  @override
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  }) => throw UnimplementedError();

  @override
  Future<AppResult<void>> save(AnalysisDocument document) =>
      throw UnimplementedError();
}

final _item = AnalysisLibraryItem(
  id: 'analysis-notes',
  title: 'Saturday warm-up',
  createdAt: DateTime.utc(2026, 8, 18),
  syncStatus: LibrarySyncStatus.synced,
  hasRawAudio: false,
  hasResult: true,
);

KeyValueLibraryNoteRepository _repositoryOn(InMemoryKeyValueStore store) =>
    KeyValueLibraryNoteRepository(keyValueStore: store);

/// The detail screen on [store], sized so the whole body lays out (the notes
/// field sits below the fold on a default 800×600 test surface).
Future<void> _pumpDetail(
  WidgetTester tester,
  InMemoryKeyValueStore store,
) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferenceStoreOverride(store),
        analysisRepositoryProvider.overrideWithValue(
          const _UnusedAnalysisRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LibraryItemDetailScreen(item: _item),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the note store', () {
    test('C1 a note survives a new repository over the same store', () async {
      final store = InMemoryKeyValueStore();

      final write = await _repositoryOn(store).write(
        itemId: _item.id,
        note: 'Chord changes were late in bar 3.',
      );
      expect(write.isSuccess, isTrue);

      // A FRESH repository reading the same bytes — the app restart shape.
      expect(
        _repositoryOn(store).read(_item.id).valueOrNull,
        'Chord changes were late in bar 3.',
      );
    });

    test('C2 notes are keyed per item', () async {
      final store = InMemoryKeyValueStore();
      final repository = _repositoryOn(store);

      await repository.write(itemId: 'item-a', note: 'about A');
      await repository.write(itemId: 'item-b', note: 'about B');

      expect(repository.read('item-a').valueOrNull, 'about A');
      expect(repository.read('item-b').valueOrNull, 'about B');
      expect(repository.read('item-c').valueOrNull, '');
    });

    test('C3 clearing the field removes the entry', () async {
      final store = InMemoryKeyValueStore();
      final repository = _repositoryOn(store);

      await repository.write(itemId: _item.id, note: 'draft');
      await repository.write(itemId: _item.id, note: '');

      expect(repository.read(_item.id).valueOrNull, '');
      expect(
        store.readString(StorageKeys.libraryItemNotes),
        isNot(contains('draft')),
      );
    });

    test('C4 an unreadable document is a failure, not an empty note', () async {
      final store = InMemoryKeyValueStore({
        StorageKeys.libraryItemNotes: 'not-json-at-all{{{',
      });
      final repository = _repositoryOn(store);

      final read = repository.read(_item.id);

      expect(read.isFailure, isTrue);
      expect(read.failureOrNull?.code, FailureCode.storageRead);

      await repository.write(itemId: _item.id, note: 'written anyway');

      expect(repository.read(_item.id).valueOrNull, 'written anyway');
    });
  });

  group('the detail screen', () {
    testWidgets('C5 what was typed is there on the way back in', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      await _pumpDetail(tester, store);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);

      await tester.enterText(field, 'Slow the outro down next time.');
      await tester.pumpAndSettle();

      expect(
        store.readString(StorageKeys.libraryItemNotes),
        contains('Slow the outro down next time.'),
        reason: 'MEASURED before this round: nothing was ever written',
      );

      // Leave the screen entirely — the root widget changes, so the state
      // (and its controller) is really disposed — and come back to a brand
      // new screen over the same store.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _pumpDetail(tester, store);

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Slow the outro down next time.',
      );
    });

    testWidgets('C5b an unreadable store still opens, with an empty field', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore({
        StorageKeys.libraryItemNotes: 'not-json-at-all{{{',
      });

      await _pumpDetail(tester, store);

      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    });
  });
}
