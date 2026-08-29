import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/library/song_library_state.dart';
import '../../application/library/song_query.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/song_source.dart';
import '../widgets/song_source_badge.dart';
import '../widgets/song_summary_tile.dart';
import 'song_import_screen.dart';

/// Keeps the last applied Library query alive across a real dispose and
/// re-entry of [SongLibraryScreen]. `songLibraryControllerProvider` is
/// `autoDispose` and loses its query the moment the route (a top-level
/// `GoRoute`, not shell-branched) disposes, so the surviving query is held
/// here instead, at file scope.
final class _SongLibraryQueryNotifier extends Notifier<SongLibraryQuery> {
  @override
  SongLibraryQuery build() => const SongLibraryQuery();

  void save(SongLibraryQuery query) => state = query;
}

final _songLibraryQueryProvider =
    NotifierProvider<_SongLibraryQueryNotifier, SongLibraryQuery>(
      _SongLibraryQueryNotifier.new,
    );

final class SongLibraryScreen extends ConsumerStatefulWidget {
  const SongLibraryScreen({super.key});

  @override
  ConsumerState<SongLibraryScreen> createState() => _SongLibraryScreenState();
}

final class _SongLibraryScreenState extends ConsumerState<SongLibraryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    final savedQuery = ref.read(_songLibraryQueryProvider);
    _searchController = TextEditingController(text: savedQuery.searchText);
    Future<void>.microtask(() async {
      final controller = ref.read(songLibraryControllerProvider);
      await controller.load();
      controller.setQuery(savedQuery);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyQuery(SongLibraryQuery query) {
    ref.read(songLibraryControllerProvider).setQuery(query);
    ref.read(_songLibraryQueryProvider.notifier).save(query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(songLibraryControllerProvider);
    final state = ref.watch(songLibraryStateProvider).value ?? controller.state;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.songLibraryTitle),
        actions: <Widget>[
          IconButton(
            key: const Key('song-editor-create'),
            onPressed: () => context.push(AppRoutes.songTrainerNewEditor),
            icon: const Icon(Icons.add),
            tooltip: l10n.songLibraryCreate,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const SongImportScreen()),
        ),
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(l10n.songLibraryImport),
      ),
      body: SafeArea(
        child: switch (state.status) {
          SongLibraryStatus.loading => Semantics(
            label: l10n.songLibraryLoading,
            child: const _LibraryLoading(),
          ),
          SongLibraryStatus.failure => _LibraryError(onRetry: controller.load),
          SongLibraryStatus.ready => Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    TextField(
                      controller: _searchController,
                      onChanged: (text) => _applyQuery(
                        SongLibraryQuery(
                          searchText: text,
                          sourceType: state.query.sourceType,
                          favoritesOnly: state.query.favoritesOnly,
                          sort: state.query.sort,
                        ),
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.songLibrarySearch,
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: SsSpacing.space3),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<SongSourceType?>(
                            key: const Key('song-library-source-filter'),
                            initialValue: state.query.sourceType,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.songLibrarySourceFilter,
                            ),
                            items: <DropdownMenuItem<SongSourceType?>>[
                              DropdownMenuItem<SongSourceType?>(
                                value: null,
                                child: Text(l10n.songLibraryAllSources),
                              ),
                              for (final sourceType in SongSourceType.values)
                                DropdownMenuItem<SongSourceType?>(
                                  value: sourceType,
                                  child: Text(
                                    songSourceTypeLabel(l10n, sourceType),
                                  ),
                                ),
                            ],
                            onChanged: (sourceType) => _applyQuery(
                              SongLibraryQuery(
                                searchText: state.query.searchText,
                                sourceType: sourceType,
                                favoritesOnly: state.query.favoritesOnly,
                                sort: state.query.sort,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<SongLibrarySort>(
                            key: const Key('song-library-sort'),
                            initialValue: state.query.sort,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.songLibrarySort,
                            ),
                            items: <DropdownMenuItem<SongLibrarySort>>[
                              DropdownMenuItem<SongLibrarySort>(
                                value: SongLibrarySort.recent,
                                child: Text(l10n.songLibrarySortRecent),
                              ),
                              DropdownMenuItem<SongLibrarySort>(
                                value: SongLibrarySort.title,
                                child: Text(l10n.songLibrarySortTitle),
                              ),
                            ],
                            onChanged: (sort) {
                              if (sort == null) return;
                              _applyQuery(
                                SongLibraryQuery(
                                  searchText: state.query.searchText,
                                  sourceType: state.query.sourceType,
                                  favoritesOnly: state.query.favoritesOnly,
                                  sort: sort,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: state.summaries.isEmpty
                    ? const _LibraryEmpty()
                    : ListView.builder(
                        itemCount: state.summaries.length,
                        itemBuilder: (context, index) {
                          final summary = state.summaries[index];
                          final canPersist =
                              summary.capability?.canPersist ?? true;
                          return InkWell(
                            key: ValueKey<String>(
                              'song-editor-open-${summary.documentId.value}',
                            ),
                            onTap: () {
                              if (!canPersist) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.songLibraryReadOnlySnackBar,
                                    ),
                                  ),
                                );
                                context.push(
                                  AppRoutes.songTrainerOverview.replaceFirst(
                                    ':songId',
                                    Uri.encodeComponent(
                                      summary.documentId.value,
                                    ),
                                  ),
                                );
                                return;
                              }
                              context.push(
                                AppRoutes.songTrainerEditor.replaceFirst(
                                  ':songId',
                                  Uri.encodeComponent(summary.documentId.value),
                                ),
                              );
                            },
                            child: SongSummaryTile(
                              summary: summary,
                              isFavorite:
                                  summary.favorite ||
                                  state.favoriteIds.contains(
                                    summary.documentId,
                                  ),
                              onFavorite: () =>
                                  controller.toggleFavorite(summary.documentId),
                              onExport: () async {
                                final export = await controller.export(
                                  summary.documentId,
                                );
                                if (!context.mounted || export == null) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.songLibraryExportPrepared(
                                        export.filename,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              onDelete: () async {
                                await controller.moveToTrash(
                                  summary.documentId,
                                );
                                if (!context.mounted ||
                                    controller.state.undoSongId == null) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.songLibraryTrashed),
                                    action: SnackBarAction(
                                      label: l10n.songLibraryUndo,
                                      onPressed: controller.undoTrash,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

final class _LibraryLoading extends StatelessWidget {
  const _LibraryLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(SsSpacing.space4),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: SsSpacing.space2),
      itemBuilder: (_, _) =>
          const SsSkeleton(width: double.infinity, height: 72),
    );
  }
}

/// Built from design tokens directly rather than [SsFailureState]: the
/// library's `failureCode` (`song_library_state.dart`) is a bare
/// [SongRepositoryErrorCode] string, not an [AppFailure] with a `retryable`
/// flag, so there is nothing honest to feed [SsFailurePresentation.from]
/// without fabricating one (E15-R04 review MAJOR-2). The single retry action
/// already existed pre-migration (`controller.load`) — only its styling
/// moves onto design tokens.
final class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 40),
            const SizedBox(height: SsSpacing.space4),
            SsButton(label: l10n.songLibraryRetry, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

/// Built from design tokens directly rather than [SsEmptyState]: that
/// component mandates an [SsEmptyState.onAction] (§5.2), and the legacy
/// empty state took no action at all (measured: `git show
/// origin/main:…song_library_screen.dart` — a bare `Center(Text(...))`).
/// Wiring the existing FAB's import action into a new `onAction` here would
/// be a behaviour change in an appearance-only round (E15-R04 review
/// MAJOR-3 pattern) — this mirrors [PracticeHubScreen]'s
/// `_EmptyCatalogLayout`, the same documented §5.2 exception.
final class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Text(
          l10n.songLibraryEmpty,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
