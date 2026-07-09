import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/screens/learn_screen.dart';
import '../../share/screens/share_preview_screen.dart';
import '../model/song.dart';
import '../providers/songs_provider.dart';
import 'song_builder_screen.dart';

/// The user's songbook: create your own chord-progression songs and play them
/// as scorable Learn lessons. A build-your-own answer to the song libraries in
/// Ultimate Guitar / Chordify / Songsterr — offline and with our ↓/↑ scoring.
class SongListScreen extends ConsumerWidget {
  const SongListScreen({super.key});

  void _openBuilder(BuildContext context, {Song? existing}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SongBuilderScreen(existing: existing),
    ));
  }

  void _play(BuildContext context, Song song) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LearnScreen(lesson: song.toLesson()),
    ));
  }

  void _share(BuildContext context, Song song) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          SharePreviewScreen(result: song.toAnalyzeResult(), title: song.name),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final songs = ref.watch(songsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.songsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBuilder(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: Text(l10n.songNew),
      ),
      body: SafeArea(
        child: songs.isEmpty
            ? _Empty(text: l10n.songsEmpty)
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
                      title: Text(song.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        '${song.chords.join(' · ')}\n${l10n.songBpm(song.bpm)}',
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
                            onPressed: () => ref
                                .read(songsProvider.notifier)
                                .remove(song.id),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined,
                size: 56, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
