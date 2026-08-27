import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio_analysis/application/analysis_providers.dart';
import '../../practice/data/local_practice_history_repository.dart';
import '../../song_trainer/application/song_trainer_providers.dart';
import '../data/analysis_item_source.dart';
import '../data/analysis_library_delete_actions.dart';
import '../data/practice_item_source.dart';
import '../data/setlist_item_source.dart';
import '../data/song_item_source.dart';
import '../domain/library_delete_actions.dart';
import '../domain/library_item.dart';
import '../domain/library_item_source.dart';

/// The four content-kind sources the unified library aggregates (§0.0/B1).
/// Each wraps an existing repository provider — no new storage is opened
/// here (§5.4).
final libraryV2SourcesProvider = Provider<List<LibraryItemSource>>((ref) {
  return [
    AnalysisItemSource(ref.watch(analysisRepositoryProvider)),
    PracticeItemSource(ref.watch(practiceHistoryRepositoryProvider)),
    SongItemSource(ref.watch(songRepositoryProvider)),
    SetlistItemSource(ref.watch(setlistRepositoryProvider)),
  ];
});

/// The sole delete entry point wired for production (§0.0/B3 — only
/// `AnalysisRepository`-backed items support deletion in this round).
final libraryV2DeleteActionsProvider = Provider<LibraryDeleteActions>((ref) {
  return AnalysisLibraryDeleteActions(
    repository: ref.watch(analysisRepositoryProvider),
  );
});

/// Free-text search over item titles.
class LibraryV2SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final libraryV2SearchQueryProvider =
    NotifierProvider<LibraryV2SearchQueryController, String>(
      LibraryV2SearchQueryController.new,
    );

/// Optional type filter; `null` means "show every type".
class LibraryV2TypeFilterController extends Notifier<LibraryItemType?> {
  @override
  LibraryItemType? build() => null;

  void setFilter(LibraryItemType? value) => state = value;
}

final libraryV2TypeFilterProvider =
    NotifierProvider<LibraryV2TypeFilterController, LibraryItemType?>(
      LibraryV2TypeFilterController.new,
    );

/// Loads and combines every source's items, newest first, mixing
/// [CorruptLibraryItem] placeholders in for any source that failed to load
/// (§5.1). One failing source never empties the whole list.
class LibraryV2Controller extends AsyncNotifier<List<LibraryItem>> {
  @override
  Future<List<LibraryItem>> build() async {
    final sources = ref.watch(libraryV2SourcesProvider);
    final items = <LibraryItem>[];
    for (final source in sources) {
      final loaded = await source.load();
      if (loaded.unavailable) {
        items.add(
          CorruptLibraryItem(
            id: 'source:${source.type.name}',
            type: source.type,
            reasonCode: loaded.failureReasonCode ?? 'unknown',
          ),
        );
      } else {
        items.addAll(loaded.items);
      }
    }
    items.sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));
    return List.unmodifiable(items);
  }

  /// Reloads every source (e.g. after a delete or a conflict resolution).
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

final libraryV2ItemsProvider =
    AsyncNotifierProvider<LibraryV2Controller, List<LibraryItem>>(
      LibraryV2Controller.new,
    );

/// The filtered/searched view of [libraryV2ItemsProvider] the list screen
/// renders. [CorruptLibraryItem] rows are never filtered out by type or
/// search — a broken source must stay visible regardless of the active
/// filter (§5.1).
final libraryV2VisibleItemsProvider = Provider<AsyncValue<List<LibraryItem>>>((
  ref,
) {
  final query = ref.watch(libraryV2SearchQueryProvider).trim().toLowerCase();
  final typeFilter = ref.watch(libraryV2TypeFilterProvider);
  return ref
      .watch(libraryV2ItemsProvider)
      .whenData(
        (items) => [
          for (final item in items)
            if (item is CorruptLibraryItem ||
                ((typeFilter == null || item.type == typeFilter) &&
                    (query.isEmpty ||
                        _titleOf(item).toLowerCase().contains(query))))
              item,
        ],
      );
});

/// Same-instant items sort last, before an "always at the top" tiebreak
/// would be needed; a stable [DateTime.now()] epoch is never read here so
/// list order stays deterministic under test (SDD gate: no clock reads).
DateTime _sortKey(LibraryItem item) => switch (item) {
  CorruptLibraryItem() => DateTime.fromMillisecondsSinceEpoch(0),
  AnalysisLibraryItem(:final createdAt) => createdAt,
  PracticeLibraryItem(:final createdAt) => createdAt,
  SongLibraryItem(:final updatedAt) => updatedAt,
  SetlistLibraryItem(:final updatedAt) => updatedAt,
};

String _titleOf(LibraryItem item) => switch (item) {
  CorruptLibraryItem() => '',
  AnalysisLibraryItem(:final title) => title,
  PracticeLibraryItem(:final title) => title,
  SongLibraryItem(:final title) => title,
  SetlistLibraryItem(:final title) => title,
};
