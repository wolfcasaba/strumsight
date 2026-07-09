import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/screens/learn_screen.dart';
import '../model/setlist.dart';
import '../model/song.dart';
import '../providers/setlists_provider.dart';
import '../providers/songs_provider.dart';
import 'setlist_list_screen.dart';

/// One setlist: reorder its songs, add/remove, rename, and **play the whole set
/// back-to-back** as a single continuous scorable lesson.
class SetlistDetailScreen extends ConsumerWidget {
  const SetlistDetailScreen({super.key, required this.setlistId});

  final String setlistId;

  void _playAll(BuildContext context, Setlist set, List<Song> songs) {
    if (songs.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LearnScreen(lesson: set.combine(songs)),
    ));
  }

  Future<void> _addSong(
      BuildContext context, WidgetRef ref, List<Song> library) async {
    final l10n = AppLocalizations.of(context);
    if (library.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.setlistNoSongsYet)));
      return;
    }
    final picked = await showModalBottomSheet<Song>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in library)
              ListTile(
                leading: const Icon(Icons.music_note, color: AppColors.primary),
                title: Text(s.name),
                subtitle: Text(s.chords.join(' · ')),
                onTap: () => Navigator.of(context).pop(s),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref.read(setlistsProvider.notifier).addSong(setlistId, picked.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final set = ref
        .watch(setlistsProvider)
        .where((s) => s.id == setlistId)
        .firstOrNull;
    // Deleted out from under us → leave.
    if (set == null) return const Scaffold(body: SizedBox.shrink());

    final library = ref.watch(songsProvider);
    final songs = set.resolve(library);

    return Scaffold(
      appBar: AppBar(
        title: Text(set.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: l10n.setlistRename,
            onPressed: () async {
              final name = await promptSetlistName(context, initial: set.name);
              if (name != null && name.trim().isNotEmpty) {
                await ref
                    .read(setlistsProvider.notifier)
                    .rename(setlistId, name.trim());
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.setlistDelete,
            onPressed: () async {
              await ref.read(setlistsProvider.notifier).remove(setlistId);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSong(context, ref, library),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: Text(l10n.setlistAddSong),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: FilledButton.icon(
                onPressed:
                    songs.isEmpty ? null : () => _playAll(context, set, songs),
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.setlistPlayAll),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
              ),
            ),
            Expanded(
              child: songs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l10n.setlistEmptyDetail,
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: songs.length,
                      // onReorder's classic (unadjusted newIndex) semantics
                      // match reorder()'s contract; keep it over onReorderItem.
                      // ignore: deprecated_member_use
                      onReorder: (oldI, newI) => ref
                          .read(setlistsProvider.notifier)
                          .reorder(setlistId, oldI, newI),
                      itemBuilder: (context, i) {
                        final song = songs[i];
                        return Card(
                          key: ValueKey('$i-${song.id}'),
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: Text('${i + 1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                            title: Text(song.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(song.chords.join(' · ')),
                            trailing: IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              tooltip: l10n.setlistRemoveSong,
                              onPressed: () => ref
                                  .read(setlistsProvider.notifier)
                                  .removeAt(setlistId, i),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
