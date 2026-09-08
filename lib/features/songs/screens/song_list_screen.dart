import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.songsTitle),
        actions: [
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
            ? _SongsEmpty(onCreate: () => _openBuilder(context))
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

/// The empty songbook (audit U4). The whole explanation used to be rendered
/// in `EmptyState`'s 18px semibold TITLE slot — four loud lines with no way
/// out except the corner FAB. It is now a one-line title, the explanation in
/// body type, and the SAME create action as the FAB, inline and reachable
/// where the user is already looking.
///
/// Built here rather than through `core/widgets/empty_state.dart` because
/// that shared component has no action slot; the layout (icon → title →
/// body → action, centered, scrollable when the parent is short) is
/// deliberately identical to it.
class _SongsEmpty extends StatelessWidget {
  const _SongsEmpty({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 40, color: palette.muted),
          const SizedBox(height: 16),
          Text(
            l10n.songsEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 18,
              height: 1.35,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.songsEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              height: 1.45,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('songs-empty-create'),
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: Text(l10n.songNew),
          ),
        ],
      ),
    );

    // "Center, but scroll if too tall" — the same idiom `EmptyState` uses, so
    // the inline action can never be pushed off a short viewport.
    return LayoutBuilder(
      builder: (context, constraints) {
        final padded = Padding(
          padding: const EdgeInsets.all(24),
          child: content,
        );
        if (!constraints.hasBoundedHeight) {
          return Center(child: padded);
        }
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: padded),
          ),
        );
      },
    );
  }
}
