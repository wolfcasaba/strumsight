import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../../song_trainer/public.dart';
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LearnScreen(lesson: set.combine(songs)),
      ),
    );
  }

  /// E17-R03 (ADR 0522 §5.2) — the mode chooser in front of the ONE session
  /// launcher. Both tiles resolve to a [SetlistSessionMode] and fall through
  /// to [_startSession]; there is no second entry path per mode.
  Future<void> _chooseSessionMode(
    BuildContext context,
    WidgetRef ref,
    Setlist set,
    List<Song> library,
  ) async {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final mode = await showModalBottomSheet<SetlistSessionMode>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.setlistSessionChooseMode,
                style: typography.titleMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            ListTile(
              key: const Key('setlist-session-mode-practice'),
              leading: Icon(Icons.mic, color: colors.brand),
              title: Text(l10n.setlistSessionPracticeTitle),
              subtitle: Text(l10n.setlistSessionPracticeDescription),
              onTap: () =>
                  Navigator.of(context).pop(SetlistSessionMode.practice),
            ),
            ListTile(
              key: const Key('setlist-session-mode-performance'),
              leading: Icon(Icons.play_circle_outline, color: colors.brand),
              title: Text(l10n.setlistSessionPerformanceTitle),
              subtitle: Text(l10n.setlistSessionPerformanceDescription),
              onTap: () =>
                  Navigator.of(context).pop(SetlistSessionMode.performance),
            ),
          ],
        ),
      ),
    );
    if (mode == null || !context.mounted) return;
    await _startSession(context, ref, set, library, mode);
  }

  /// E17-R03 (ADR 0522 §5.1) — the single Song Trainer session launcher;
  /// [mode] is a parameter, never a second code path.
  ///
  /// The legacy [Setlist] is projected into a V2 setlist IN MEMORY on every
  /// entry by [SetlistSessionComposer.compose] (same mapping as the
  /// migration adapter, nothing persisted — the legacy `setlistsProvider`
  /// stays the single source of truth this screen edits). Availability and
  /// both runners come from the real song repositories through the same
  /// composer. Finishing pops back to THIS screen (A4) and reports the run
  /// in a snack bar.
  Future<void> _startSession(
    BuildContext context,
    WidgetRef ref,
    Setlist set,
    List<Song> library,
    SetlistSessionMode mode,
  ) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final composition = await ref
        .read(setlistSessionComposerProvider)
        .compose(
          legacySetlist: LegacySetlistRecord(
            id: set.id,
            name: set.name,
            songIds: set.songIds,
          ),
          legacySongs: [for (final song in library) song.toJson()],
          presentStage: (stage) => _presentStage(navigator, stage),
        );
    if (!context.mounted) return;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SetlistSessionScreen(
          setlist: composition.setlist,
          mode: mode,
          availability: composition.availability,
          performanceRunner: composition.performanceRunner,
          createPracticeRunner: composition.createPracticeRunner,
          onCompleted: (result) {
            navigator.pop();
            final completed = result.itemResults
                .where(
                  (item) => item.status == SetlistItemResultStatus.completed,
                )
                .length;
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  l10n.setlistSessionResult(
                    completed,
                    result.itemResults.length,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Shows one item's Stage — the same `SongTrainerScreen(songId, inputs)`
  /// composition the `/song-trainer/session` route renders — pushed so the
  /// session list stays underneath, and resolves with the time on screen
  /// once the guitarist leaves it.
  static Future<Duration> _presentStage(
    NavigatorState navigator,
    SetlistItemStage stage,
  ) async {
    final stopwatch = Stopwatch()..start();
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => SongTrainerScreen(
          songId: stage.document.id.value,
          inputs: stage.inputs,
        ),
      ),
    );
    stopwatch.stop();
    return stopwatch.elapsed;
  }

  Future<void> _addSong(
    BuildContext context,
    WidgetRef ref,
    List<Song> library,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (library.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.setlistNoSongsYet)));
      return;
    }
    final brand = Theme.of(context).extension<SsColorScheme>()!.brand;
    final picked = await showModalBottomSheet<Song>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in library)
              ListTile(
                leading: Icon(Icons.music_note, color: brand),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    // Same flag gate as the Song Trainer routes and the Songs-tab entry
    // (`song_list_screen.dart`): the V2 session is a V2 surface.
    final sessionEnabled = ref
        .watch(appConfigProvider)
        .flags
        .songTrainerV2Enabled;

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
        backgroundColor: colors.brand,
        icon: const Icon(Icons.add),
        label: Text(l10n.setlistAddSong),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SsButton(
                    onPressed: songs.isEmpty
                        ? null
                        : () => _playAll(context, set, songs),
                    icon: Icons.play_arrow,
                    label: l10n.setlistPlayAll,
                  ),
                  if (sessionEnabled) ...[
                    const SizedBox(height: SsSpacing.space2),
                    SsButton(
                      key: const Key('setlist-session-entry'),
                      onPressed: songs.isEmpty
                          ? null
                          : () =>
                                _chooseSessionMode(context, ref, set, library),
                      variant: SsButtonVariant.secondary,
                      icon: Icons.queue_play_next,
                      label: l10n.setlistSessionEntry,
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: songs.isEmpty
                  ? _ScrollableIfShort(
                      child: SsEmptyState(
                        icon: Icons.queue_music,
                        title: l10n.setlistEmptyDetailTitle,
                        message: l10n.setlistEmptyDetail,
                        actionLabel: l10n.setlistAddSong,
                        onAction: () => _addSong(context, ref, library),
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
                          margin: const EdgeInsets.only(
                            bottom: SsSpacing.space2,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            leading: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: colors.brand,
                              ),
                            ),
                            title: Text(
                              song.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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

/// Lets [child] (an [SsEmptyState], always `Center`-wrapped internally)
/// scroll instead of overflow when the viewport is too short for it — same
/// measured need as `setlist_list_screen.dart`'s `_ScrollableIfShort` (Dart
/// privacy keeps that one file-local, so this is a deliberate duplicate
/// rather than a shared-widget extraction, which `core/design_system/**`
/// being a forbidden zone for this round rules out).
class _ScrollableIfShort extends StatelessWidget {
  const _ScrollableIfShort({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) return child;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}
