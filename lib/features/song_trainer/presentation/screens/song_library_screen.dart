import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/library/song_library_state.dart';
import '../../application/library/song_query.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/song_id.dart';
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

  /// Empty-state CTA: puts the shipped practice songs back.
  ///
  /// The boot path NEVER does this — a seed the user deleted only returns on
  /// this explicit tap (`SongSeedInstaller.restore`). The outcome is always
  /// reported: a restored count, or the named failure code.
  Future<void> _restoreSeedSongs() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref.read(songSeedRestoreProvider)();
    if (!mounted) return;
    await ref.read(songLibraryControllerProvider).load();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          outcome.isClean
              ? l10n.songLibraryRestoreSeedsDone(
                  outcome.installedSeedIds.length,
                )
              : l10n.songLibraryRestoreSeedsFailed(
                  outcome.failures.first.reason,
                ),
        ),
      ),
    );
  }

  /// Origin kinds the LOADED library actually contains.
  Set<SongSourceType> _presentOrigins(SongLibraryState state) =>
      <SongSourceType>{
        for (final summary in state.summaries) summary.sourceType,
      };

  /// Whether the origin filter earns its place (owner feedback 2026-09-17:
  /// "why so many libraries, all empty").
  ///
  /// A dropdown offering eight import formats over a library that holds one
  /// kind — or none — reads as eight empty libraries. It renders only when
  /// there is something to choose between, and stays put while a filter is
  /// active so it cannot vanish under the user's own selection.
  bool _showsOriginFilter(SongLibraryState state) =>
      state.query.sourceType != null || _presentOrigins(state).length >= 2;

  /// The offered origins. Guitar Pro is left out while there is no direct
  /// `.gp*` importer — the conversion guidance elsewhere stays — unless the
  /// library somehow already holds such a document.
  List<SongSourceType> _originOptions(SongLibraryState state) {
    final present = _presentOrigins(state);
    return <SongSourceType>[
      for (final sourceType in SongSourceType.values)
        if (sourceType != SongSourceType.guitarPro ||
            present.contains(sourceType) ||
            state.query.sourceType == sourceType)
          sourceType,
    ];
  }

  /// Opens the trainer setup for [songId] — the row's Play affordance.
  void _openTrainerSetup(SongId songId) {
    context.push(
      AppRoutes.songTrainerSetup.replaceFirst(
        ':songId',
        Uri.encodeComponent(songId.value),
      ),
    );
  }

  /// Empty-state secondary CTA: the guided Learn highway.
  void _openLearnHighway() => context.push(AppRoutes.practiceLearn);

  /// Opens the import sheet and RELOADS on the way back.
  ///
  /// The library only loaded in `initState`, so a song created while this
  /// route stayed mounted underneath (the K3 audio import lands in the editor
  /// on top of it) was invisible until the user left the tab and came back.
  Future<void> _openImport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SongImportScreen()),
    );
    if (!mounted) return;
    await ref.read(songLibraryControllerProvider).load();
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
          // E17-R03 (ADR 0585 D1) — the ONE human entry point into the
          // shipped Setlist V2 composition; without this affordance the
          // route is unreachable by a person even though it exists.
          IconButton(
            key: const Key('song-library-open-setlists'),
            onPressed: () => context.push(AppRoutes.songTrainerSetlists),
            icon: const Icon(Icons.queue_music_outlined),
            tooltip: l10n.songLibraryOpenSetlists,
          ),
          // Learner-loop round 5: the legacy "My songs" builder list stays
          // one tap away now that this library is the Songs destination.
          IconButton(
            key: const Key('song-library-own-songs'),
            onPressed: () => context.push(AppRoutes.songsOwn),
            icon: const Icon(Icons.edit_note),
            tooltip: l10n.songsTitle,
          ),
          IconButton(
            key: const Key('song-editor-create'),
            onPressed: () => context.push(AppRoutes.songTrainerNewEditor),
            icon: const Icon(Icons.add),
            tooltip: l10n.songLibraryCreate,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openImport,
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
                        if (_showsOriginFilter(state)) ...<Widget>[
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
                                for (final sourceType in _originOptions(state))
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
                        ],
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
                    ? _LibraryEmpty(
                        onRestoreSeeds: _restoreSeedSongs,
                        onOpenLearn: _openLearnHighway,
                      )
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
                              onPlay: () =>
                                  _openTrainerSetup(summary.documentId),
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

/// The empty library is no longer a dead end (E16-R01/A1).
///
/// The measured state before this round was a bare `Center(Text(...))` with
/// ZERO actions: on a fresh install the Songs tab said "no songs yet" and
/// offered nothing but the import FAB, so a beginner with no song file had
/// nowhere to go. It now carries the two honest ways forward — put the
/// shipped practice songs back, or leave for the Learn highway — plus a
/// sentence naming where the up/down strumming drills actually live.
///
/// Built from design tokens directly rather than [SsEmptyState] because that
/// component takes exactly one action (§5.2) and this state has two; it is
/// a [ListView] so the two buttons and the hint still fit at 200% text scale.
final class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty({
    required this.onRestoreSeeds,
    required this.onOpenLearn,
  });

  final VoidCallback onRestoreSeeds;
  final VoidCallback onOpenLearn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return ListView(
      key: const Key('song-library-empty'),
      padding: const EdgeInsets.all(SsSpacing.space6),
      children: <Widget>[
        Text(
          l10n.songLibraryEmpty,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SsSpacing.space3),
        Text(
          l10n.songLibraryEmptyPracticeHint,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SsSpacing.space4),
        SsButton(
          key: const Key('song-library-restore-seeds'),
          label: l10n.songLibraryRestoreSeeds,
          onPressed: onRestoreSeeds,
        ),
        const SizedBox(height: SsSpacing.space2),
        SsButton(
          key: const Key('song-library-open-learn'),
          label: l10n.songLibraryOpenLearn,
          variant: SsButtonVariant.secondary,
          onPressed: onOpenLearn,
        ),
      ],
    );
  }
}
