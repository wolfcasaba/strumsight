// E13-R28 — A1 (type-safe item routing) and A8 (the legacy Library route
// keeps working, untouched by this round).
//
// A1: the unified library aggregates four content kinds behind one sealed
// [LibraryItem] union. Tapping a row of one type must open ONLY that type's
// detail content — never another type's, and never crash on a mismatched
// `extra` (mirrors the pre-existing V1 `librarySession` redirect pattern).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_repository.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/library_v2/domain/library_item.dart';
import 'package:strumsight/features/library_v2/domain/library_item_source.dart';
import 'package:strumsight/features/library_v2/providers/library_v2_providers.dart';
import 'package:strumsight/features/library_v2/screens/library_item_detail_screen.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// `_AnalysisDetailBody` always references `analysisRepositoryProvider`
/// (for the export action) even when a test never taps export — this fake
/// only needs to exist, never to be called, in every cell here.
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
  Future<AppResult<void>> replace(String id, AnalysisSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) =>
      throw UnimplementedError();
}

final class _FakeSource implements LibraryItemSource {
  const _FakeSource(this.type, this._items);

  @override
  final LibraryItemType type;
  final List<LibraryItem> _items;

  @override
  Future<LibrarySourceLoad> load() async => LibrarySourceLoad.success(_items);
}

final _analysisItem = AnalysisLibraryItem(
  id: 'analysis-1',
  title: 'Analysis Session',
  createdAt: DateTime.utc(2026, 8, 1),
  syncStatus: LibrarySyncStatus.synced,
  hasRawAudio: false,
  hasResult: true,
);
final _practiceItem = PracticeLibraryItem(
  id: 'practice-1',
  title: 'Practice Session',
  createdAt: DateTime.utc(2026, 8, 2),
  syncStatus: LibrarySyncStatus.synced,
);
final _songItem = SongLibraryItem(
  id: 'song-1',
  title: 'Test Song',
  artist: 'Test Artist',
  updatedAt: DateTime.utc(2026, 8, 3),
  syncStatus: LibrarySyncStatus.synced,
);
final _setlistItem = SetlistLibraryItem(
  id: 'setlist-1',
  title: 'Test Setlist',
  songCount: 3,
  updatedAt: DateTime.utc(2026, 8, 4),
  syncStatus: LibrarySyncStatus.synced,
);

Future<GoRouter> _pumpRouter(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: AppRoutes.profileLibrary,
    routes: [
      GoRoute(
        path: AppRoutes.profileLibrary,
        builder: (_, _) => const UnifiedLibraryScreen(),
      ),
      GoRoute(
        path: AppRoutes.profileLibrarySession,
        redirect: (_, state) =>
            state.extra is LibraryItem ? null : AppRoutes.profileLibrary,
        builder: (_, state) =>
            LibraryItemDetailScreen(item: state.extra as LibraryItem),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryV2SourcesProvider.overrideWithValue([
          _FakeSource(LibraryItemType.analysis, [_analysisItem]),
          _FakeSource(LibraryItemType.practice, [_practiceItem]),
          _FakeSource(LibraryItemType.song, [_songItem]),
          _FakeSource(LibraryItemType.setlist, [_setlistItem]),
        ]),
        analysisRepositoryProvider.overrideWithValue(
          const _UnusedAnalysisRepository(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('A1 — tapping a row opens exactly that type\'s detail content', () {
    testWidgets(
      'an analysis row opens the analysis detail, never metadata-only',
      (tester) async {
        await _pumpRouter(tester);

        await tester.tap(find.byKey(const ValueKey('library-item-analysis-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('library-detail-analysis')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('library-detail-metadata')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('library-detail-corrupt')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a practice row opens metadata-only content, never the analysis body',
      (tester) async {
        await _pumpRouter(tester);

        await tester.tap(find.byKey(const ValueKey('library-item-practice-1')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('library-detail-metadata')),
          findsOneWidget,
        );
        // The title renders in both the AppBar and the body.
        expect(find.text('Practice Session'), findsWidgets);
        expect(
          find.byKey(const ValueKey('library-detail-analysis')),
          findsNothing,
        );
      },
    );

    testWidgets('a song row opens its own metadata, never the setlist count', (
      tester,
    ) async {
      await _pumpRouter(tester);

      await tester.tap(find.byKey(const ValueKey('library-item-song-1')));
      await tester.pumpAndSettle();

      // The title renders in both the AppBar and the body.
      expect(find.text('Test Song'), findsWidgets);
      expect(find.text('Test Artist'), findsOneWidget);
    });

    testWidgets('a setlist row opens its own metadata with its song count', (
      tester,
    ) async {
      await _pumpRouter(tester);

      await tester.tap(find.byKey(const ValueKey('library-item-setlist-1')));
      await tester.pumpAndSettle();

      expect(find.text('Test Setlist'), findsWidgets);
    });

    testWidgets(
      'a mismatched extra (not a LibraryItem) redirects to the list instead of crashing',
      (tester) async {
        final router = await _pumpRouter(tester);

        router.push(
          AppRoutes.profileLibrarySession.replaceFirst(':sessionId', 'unknown'),
          extra: 'not-a-library-item',
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(UnifiedLibraryScreen), findsOneWidget);
      },
    );

    testWidgets(
      'a corrupt placeholder opens the isolated failure body directly',
      (tester) async {
        final router = await _pumpRouter(tester);

        router.push(
          AppRoutes.profileLibrarySession.replaceFirst(
            ':sessionId',
            'source:song',
          ),
          extra: const CorruptLibraryItem(
            id: 'source:song',
            type: LibraryItemType.song,
            reasonCode: 'songRepository.corruptIndex',
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('library-detail-corrupt')),
          findsOneWidget,
        );
      },
    );
  });

  group('A8 — the legacy /library route is untouched by this round', () {
    test(
      'AppRoutes.library still builds LibraryScreen and AppRoutes.librarySession '
      'still builds SessionDetailScreen (§0.0/B2 route contract)',
      () {
        final source = File(
          'lib/app/routing/app_router.dart',
        ).readAsStringSync();

        bool buildsWithin(
          String routeConst,
          String screenType, {
          int window = 120,
        }) {
          // Search for the GoRoute's `path:` declaration specifically — the
          // bare constant also appears in unrelated `redirect:` fallbacks
          // elsewhere in the file (e.g. `: AppRoutes.profileLibrary,`),
          // which would otherwise be matched first.
          final routeIndex = source.indexOf('path: AppRoutes.$routeConst,');
          expect(
            routeIndex,
            greaterThanOrEqualTo(0),
            reason: 'path: AppRoutes.$routeConst not found',
          );
          final slice = source.substring(
            routeIndex,
            (routeIndex + window).clamp(0, source.length),
          );
          return slice.contains(screenType);
        }

        expect(
          buildsWithin('library', 'LibraryScreen'),
          isTrue,
          reason: 'the legacy /library route must keep building LibraryScreen',
        );
        expect(
          buildsWithin('librarySession', 'SessionDetailScreen', window: 400),
          isTrue,
          reason:
              'AppRoutes.librarySession must keep building SessionDetailScreen',
        );
        expect(
          buildsWithin('profileLibrary', 'UnifiedLibraryScreen'),
          isTrue,
          reason:
              'AppRoutes.profileLibrary is the ONE builder this round replaces',
        );
        expect(
          buildsWithin(
            'profileLibrarySession',
            'LibraryItemDetailScreen',
            window: 400,
          ),
          isTrue,
          reason: 'AppRoutes.profileLibrarySession is the new UI-41 route',
        );
      },
    );
  });
}
