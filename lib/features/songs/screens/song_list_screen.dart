import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../../share/public.dart';
import '../model/song.dart';
import '../providers/songs_provider.dart';
import 'setlist_list_screen.dart';
import 'song_builder_screen.dart';

/// The user's songbook: create your own chord-progression songs and play them
/// as scorable Learn lessons. A build-your-own answer to the song libraries in
/// Ultimate Guitar / Chordify / Songsterr — offline and with our ↓/↑ scoring.
class SongListScreen extends ConsumerWidget {
  const SongListScreen({super.key});

  void _openBuilder(BuildContext context, {Song? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SongBuilderScreen(existing: existing),
      ),
    );
  }

  void _play(BuildContext context, Song song) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LearnScreen(lesson: song.toLesson()),
      ),
    );
  }

  void _share(BuildContext context, Song song) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SharePreviewScreen(
          result: song.toAnalyzeResult(),
          title: song.name,
        ),
      ),
    );
  }

  /// Delete with an UNDO affordance: the remove is applied (and persisted)
  /// immediately, but a SnackBar lets the user restore the song at its
  /// original position before the SnackBar dismisses (r187).
  void _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    int index,
    Song song,
  ) {
    ref.read(songsProvider.notifier).remove(song.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.songDeleted),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () =>
                ref.read(songsProvider.notifier).restore(index, song),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final songs = ref.watch(songsProvider);
    final flags = ref.watch(appConfigProvider).flags;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.songsTitle),
        actions: [
          // The V2 Song Trainer (library → editor) had no entry from the
          // four-tab shell: its only door was the Learn lesson list, which
          // the shell never reaches (E18-R01 emulator finding F8). The Songs
          // tab is where a user looks for it, so it opens from here — same
          // flag gate as the routes themselves, pushed so back returns.
          if (flags.songTrainerV2Enabled)
            IconButton(
              key: const Key('songs-entry-song-trainer'),
              icon: const Icon(Icons.auto_stories_outlined),
              tooltip: l10n.songTrainerTitle,
              onPressed: () => context.push(AppRoutes.songTrainerLibrary),
            ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: l10n.setlistsTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SetlistListScreen(),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBuilder(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: Text(l10n.songNew),
      ),
      body: SafeArea(
        child: songs.isEmpty
            ? EmptyState(
                icon: Icons.library_music_outlined,
                title: l10n.songsEmpty,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: songs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final song = songs[i];
                  return Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.music_note, color: Colors.white),
                      ),
                      title: Text(
                        song.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        // Time-signature notation is universal (round 116
                        // decision) — only the non-default metre is shown.
                        '${song.chords.join(' · ')}\n${l10n.songBpm(song.bpm)}'
                        '${song.beatsPerBar == 3 ? ' · 3/4' : ''}',
                      ),
                      isThreeLine: true,
                      onTap: () => _play(context, song),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.ios_share),
                            tooltip: l10n.shareCardButton,
                            onPressed: () => _share(context, song),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: l10n.songEditTitle,
                            onPressed: () =>
                                _openBuilder(context, existing: song),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: l10n.songDelete,
                            onPressed: () =>
                                _delete(context, ref, l10n, i, song),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
