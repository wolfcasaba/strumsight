import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/library/song_library_state.dart';
import '../../application/library/song_query.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/song_source.dart';
import '../widgets/song_summary_tile.dart';
import 'song_import_screen.dart';

final class SongLibraryScreen extends ConsumerStatefulWidget {
  const SongLibraryScreen({super.key});

  @override
  ConsumerState<SongLibraryScreen> createState() => _SongLibraryScreenState();
}

final class _SongLibraryScreenState extends ConsumerState<SongLibraryScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(songLibraryControllerProvider).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(songLibraryControllerProvider);
    final state = ref.watch(songLibraryStateProvider).value ?? controller.state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songLibraryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => const SongImportScreen()),
        ),
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(l10n.songLibraryImport),
      ),
      body: SafeArea(
        child: switch (state.status) {
          SongLibraryStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          SongLibraryStatus.failure => Center(
            child: FilledButton(
              onPressed: controller.load,
              child: Text(l10n.songLibraryRetry),
            ),
          ),
          SongLibraryStatus.ready => Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    TextField(
                      onChanged: (text) => controller.setQuery(
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
                    const SizedBox(height: 12),
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
                                    _sourceTypeLabel(l10n, sourceType),
                                  ),
                                ),
                            ],
                            onChanged: (sourceType) => controller.setQuery(
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
                              controller.setQuery(
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
                    ? Center(child: Text(l10n.songLibraryEmpty))
                    : ListView.builder(
                        itemCount: state.summaries.length,
                        itemBuilder: (context, index) {
                          final summary = state.summaries[index];
                          return SongSummaryTile(
                            summary: summary,
                            isFavorite:
                                summary.favorite ||
                                state.favoriteIds.contains(summary.documentId),
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
                              await controller.moveToTrash(summary.documentId);
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

String _sourceTypeLabel(AppLocalizations l10n, SongSourceType sourceType) =>
    switch (sourceType) {
      SongSourceType.legacyLocal => l10n.songLibrarySourceLegacy,
      SongSourceType.createdInApp => l10n.songLibrarySourceCreated,
      SongSourceType.strumSightJson => l10n.songLibrarySourceNativeJson,
      SongSourceType.musicXml => l10n.songLibrarySourceMusicXml,
      SongSourceType.compressedMusicXml => l10n.songLibrarySourceMxl,
      SongSourceType.midi => l10n.songLibrarySourceMidi,
      SongSourceType.guitarPro => l10n.songLibrarySourceGuitarPro,
    };
