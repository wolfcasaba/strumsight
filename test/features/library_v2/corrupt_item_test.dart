// E13-R28 — A2 (a broken source doesn't break the list), A3 (a local item
// opens offline — the cell measures the DETAIL RENDER, not just list
// visibility, per §0.0/B4 / L499) and A6 (missing raw audio still leaves the
// result openable).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
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

final class _FakeSource implements LibraryItemSource {
  const _FakeSource(this.type, this._load);

  @override
  final LibraryItemType type;
  final Future<LibrarySourceLoad> Function() _load;

  @override
  Future<LibrarySourceLoad> load() => _load();
}

/// `_AnalysisDetailBody` always references `analysisRepositoryProvider`
/// (for the export action) even when a test never taps export.
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

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analysisRepositoryProvider.overrideWithValue(
          const _UnusedAnalysisRepository(),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group(
    'A2 — a broken source is isolated, the rest of the library still works',
    () {
      testWidgets(
        'a healthy analysis item and a failed song source both appear; the '
        'healthy item stays tappable',
        (tester) async {
          final healthyItem = AnalysisLibraryItem(
            id: 'healthy-analysis',
            title: 'Healthy Analysis',
            createdAt: DateTime.utc(2026, 8, 1),
            syncStatus: LibrarySyncStatus.synced,
            hasRawAudio: false,
            hasResult: true,
          );

          await _pump(
            tester,
            const UnifiedLibraryScreen(),
            overrides: [
              libraryV2SourcesProvider.overrideWithValue([
                _FakeSource(
                  LibraryItemType.analysis,
                  () async => LibrarySourceLoad.success([healthyItem]),
                ),
                // The simulated failure source: a corrupt on-disk song
                // index (SongRepositoryErrorCode.corruptIndex is a real,
                // documented failure code — this is not a fabricated error).
                _FakeSource(
                  LibraryItemType.song,
                  () async => const LibrarySourceLoad.unavailable(
                    'songRepository.corruptIndex',
                  ),
                ),
              ]),
            ],
          );

          expect(tester.takeException(), isNull);
          // The healthy item renders...
          expect(
            find.byKey(const ValueKey('library-item-healthy-analysis')),
            findsOneWidget,
          );
          // ...alongside an isolated placeholder for the broken source, not a
          // crash and not an empty list.
          expect(
            find.byKey(const ValueKey('library-item-corrupt-source:song')),
            findsOneWidget,
          );
        },
      );
    },
  );

  group(
    'A3 — a local item opens (renders content) while its own copy is offline',
    () {
      testWidgets(
        'an item marked offline still renders its full detail content — '
        'this widget performs no network call, so nothing here can distinguish '
        'online from offline except the syncStatus field itself (the '
        'simulated network-loss source for this cell)',
        (tester) async {
          final offlineItem = AnalysisLibraryItem(
            id: 'offline-item',
            title: 'Offline Analysis',
            createdAt: DateTime.utc(2026, 7, 30),
            syncStatus: LibrarySyncStatus.offline,
            hasRawAudio: true,
            hasResult: true,
          );

          await _pump(tester, LibraryItemDetailScreen(item: offlineItem));

          expect(tester.takeException(), isNull);
          // The detail screen renders its full analysis body — metadata AND
          // result section — not a blocked/empty placeholder.
          expect(
            find.byKey(const ValueKey('library-detail-analysis')),
            findsOneWidget,
          );
          // The title renders in both the AppBar and the body.
          expect(find.text('Offline Analysis'), findsWidgets);
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          expect(find.text(l10n.libraryV2ResultAvailable), findsOneWidget);
        },
      );
    },
  );

  group('A6 — missing raw audio never hides the analysis result', () {
    testWidgets(
      'hasRawAudio=false, hasResult=true still renders the result as available',
      (tester) async {
        final item = AnalysisLibraryItem(
          id: 'no-raw',
          title: 'No Raw Audio',
          createdAt: DateTime.utc(2026, 7, 15),
          syncStatus: LibrarySyncStatus.synced,
          hasRawAudio: false,
          hasResult: true,
        );

        await _pump(tester, LibraryItemDetailScreen(item: item));

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(find.text(l10n.libraryV2ResultAvailable), findsOneWidget);
        expect(
          find.byKey(const ValueKey('library-detail-raw-missing-notice')),
          findsOneWidget,
        );
      },
    );
  });

  group('A2 — the corrupt detail body itself never crashes', () {
    testWidgets('a CorruptLibraryItem renders the isolated failure state', (
      tester,
    ) async {
      const item = CorruptLibraryItem(
        id: 'source:practice',
        type: LibraryItemType.practice,
        reasonCode: 'storage.read',
      );

      await _pump(tester, const LibraryItemDetailScreen(item: item));

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('library-detail-corrupt')),
        findsOneWidget,
      );
      expect(find.text('storage.read'), findsOneWidget);
    });
  });
}
