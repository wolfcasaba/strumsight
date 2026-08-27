// Golden snapshots of the E13-R28 unified library — the list (UI-40) and
// the analysis item detail (UI-41) — at a compact portrait phone (412×915)
// and the same frame at textScaler 2.0, per the round brief §7/A9. Pattern
// follows the merged `test/ui/goldens/e13_r23_screens_golden_test.dart`
// precedent: `AppTheme` (the app's actual runtime theme), not `SsDarkTheme`.
//
// Recorded on x86_64 (ADR 0426, §0.0/B/R14) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.
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

const _compactPortrait = Size(412, 915);

final class _GoldenSource implements LibraryItemSource {
  const _GoldenSource(this.type, this._items);

  @override
  final LibraryItemType type;
  final List<LibraryItem> _items;

  @override
  Future<LibrarySourceLoad> load() async => LibrarySourceLoad.success(_items);
}

/// `_AnalysisDetailBody` always references `analysisRepositoryProvider`
/// (for the export action) even when a golden pump never taps export.
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

List<Override> _goldenSourceOverrides() => [
  libraryV2SourcesProvider.overrideWithValue([
    _GoldenSource(LibraryItemType.analysis, [
      AnalysisLibraryItem(
        id: 'golden-analysis',
        title: 'Saturday warm-up',
        createdAt: DateTime.utc(2026, 8, 20, 9),
        syncStatus: LibrarySyncStatus.synced,
        hasRawAudio: false,
        hasResult: true,
      ),
    ]),
    _GoldenSource(LibraryItemType.practice, [
      PracticeLibraryItem(
        id: 'golden-practice',
        title: 'Chord switching drill',
        createdAt: DateTime.utc(2026, 8, 19),
        syncStatus: LibrarySyncStatus.pending,
      ),
    ]),
    _GoldenSource(LibraryItemType.song, [
      SongLibraryItem(
        id: 'golden-song',
        title: 'Wonderwall',
        artist: 'Oasis',
        updatedAt: DateTime.utc(2026, 8, 18),
        syncStatus: LibrarySyncStatus.synced,
      ),
    ]),
    _GoldenSource(LibraryItemType.setlist, [
      SetlistLibraryItem(
        id: 'golden-setlist',
        title: 'Saturday gig',
        songCount: 5,
        updatedAt: DateTime.utc(2026, 8, 17),
        syncStatus: LibrarySyncStatus.conflict,
      ),
    ]),
  ]),
];

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
      overrides: [
        analysisRepositoryProvider.overrideWithValue(
          const _UnusedAnalysisRepository(),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('unified library list — $suffix', (tester) async {
      await _pump(
        tester,
        const UnifiedLibraryScreen(),
        overrides: _goldenSourceOverrides(),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r28_unified_library_$suffix');
    });

    testWidgets('library item detail (analysis) — $suffix', (tester) async {
      final item = AnalysisLibraryItem(
        id: 'golden-detail',
        title: 'Saturday warm-up',
        createdAt: DateTime.utc(2026, 8, 20, 9),
        syncStatus: LibrarySyncStatus.synced,
        hasRawAudio: false,
        hasResult: true,
      );
      await _pump(
        tester,
        LibraryItemDetailScreen(item: item),
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r28_library_item_detail_$suffix');
    });
  }
}
