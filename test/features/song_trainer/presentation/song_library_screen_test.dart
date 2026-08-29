import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/public.dart';

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
    // A2 guard: the empty-state text must carry the design-token color, not
    // a raw Material default — this fails red if `_LibraryEmpty` is reverted
    // to an unstyled `Text`.
    final emptyText = tester.widget<Text>(
      find.text('No songs yet. Import a file to start your library.'),
    );
    final colors = Theme.of(
      tester.element(find.byType(SongLibraryScreen)),
    ).extension<SsColorScheme>()!;
    expect(emptyText.style?.color, colors.textSecondary);
  });

  testWidgets(
    'loading library renders the design-system skeleton, not a raw spinner',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            songRepositoryProvider.overrideWithValue(_PendingRepository()),
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

      // A2 guard: `_LibraryLoading` must be built from `SsSkeleton`, never a
      // raw `CircularProgressIndicator`.
      expect(find.byType(SsSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('failed library load renders the design-system retry button', (
    tester,
  ) async {
    // `_SongLibraryScreenState.initState` always chains a `setQuery()` call
    // right after the first `load()`, and `setQuery()` unconditionally
    // republishes `SongLibraryStatus.ready` — so a repository that fails on
    // the very first load never lets the widget tree observe the failure
    // frame. Mount with a repository that succeeds first (reaching the
    // steady `ready` state the same way the screen's own initState does),
    // then invoke a second, standalone `controller.load()` — the retry
    // button's own callback, with no `setQuery` chained after it — against a
    // repository that now fails, which is the only path that leaves the
    // widget tree observably in `SongLibraryStatus.failure`.
    final repository = _ToggleRepository();
    final container = ProviderContainer(
      overrides: [songRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: SsLightTheme.data(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SongLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    repository.failNextLoad = true;
    await container.read(songLibraryControllerProvider).load();
    await tester.pump();

    // A2 guard: `_LibraryError` must render its retry action through
    // `SsButton` (which itself composes a `FilledButton`) — a bare
    // `TextButton`/`ElevatedButton` fallback would leave `SsButton` absent.
    expect(find.byType(SsButton), findsOneWidget);
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

  for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
    testWidgets('remains overflow-free at 200 percent text scale — '
        '${locale.languageCode} locale', (tester) async {
      final repository = _SummaryRepository(<SongSummary>[
        _summary(
          id: 'json',
          title: 'Zulu JSON',
          sourceType: SongSourceType.strumSightJson,
          updatedAt: DateTime.utc(2026, 8, 5),
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [songRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: SsLightTheme.data(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: const SongLibraryScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zulu JSON'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
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

/// `list()` never resolves, so the screen stays on `SongLibraryStatus.loading`
/// for the lifetime of the test.
final class _PendingRepository implements SongRepository {
  final _pending = Completer<AppResult<List<SongSummary>>>();

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) => _pending.future;

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

/// Succeeds with an empty catalog until [failNextLoad] is set, then fails
/// every subsequent `list()` call.
final class _ToggleRepository implements SongRepository {
  var failNextLoad = false;

  @override
  Future<AppResult<List<SongSummary>>> list(SongQuery query) async {
    if (failNextLoad) {
      return AppResult<List<SongSummary>>.failure(
        const StorageFailure(code: SongRepositoryErrorCode.notFound),
      );
    }
    return const AppResult<List<SongSummary>>.success(<SongSummary>[]);
  }

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
