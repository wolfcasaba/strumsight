import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;

void main() {
  testWidgets('empty library offers an import entry point', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
        ],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SongLibraryScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('No songs yet. Import a file to start your library.'),
      findsOneWidget,
    );
    expect(find.text('Import'), findsOneWidget);
  });

  testWidgets('source filter and sort controls change the visible summaries', (
    tester,
  ) async {
    final repository = _SummaryRepository(<SongSummary>[
      _summary(
        id: 'json',
        title: 'Zulu JSON',
        sourceType: SongSourceType.strumSightJson,
        updatedAt: DateTime.utc(2026, 8, 5),
      ),
      _summary(
        id: 'midi',
        title: 'Alpha MIDI',
        sourceType: SongSourceType.midi,
        updatedAt: DateTime.utc(2026, 8, 4),
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [songRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SongLibraryScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('song-library-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MIDI').last);
    await tester.pump();
    expect(find.text('Alpha MIDI'), findsOneWidget);
    expect(find.text('Zulu JSON'), findsNothing);

    await tester.tap(find.byKey(const Key('song-library-source-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All sources').last);
    await tester.pump();
    await tester.tap(find.byKey(const Key('song-library-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z').last);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('Alpha MIDI')).dy,
      lessThan(tester.getTopLeft(find.text('Zulu JSON')).dy),
    );
  });
}

SongSummary _summary({
  required String id,
  required String title,
  required SongSourceType sourceType,
  required DateTime updatedAt,
}) => SongSummary(
  documentId: SongId(id),
  title: title,
  artist: null,
  tags: const <String>[],
  updatedAt: updatedAt,
  lastPracticedAt: updatedAt,
  capability: null,
  sourceType: sourceType,
  favorite: false,
  archived: false,
  revision: 0,
  documentHash: '0' * 64,
  trashed: false,
);

final class _SummaryRepository implements SongRepository {
  const _SummaryRepository(this._summaries);

  final List<SongSummary> _summaries;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async =>
      AppResult<List<SongSummary>>.success(_summaries);

  @override
  Future<AppResult<void>> create(SongDocument document) =>
      throw UnimplementedError();

  @override
  Future<AppResult<SongDocument?>> get(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> moveToTrash(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> permanentlyDelete(SongId id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> restore(SongId id) => throw UnimplementedError();

  @override
  Future<AppResult<void>> update(
    SongDocument document, {
    required int expectedRevision,
  }) => throw UnimplementedError();
}
