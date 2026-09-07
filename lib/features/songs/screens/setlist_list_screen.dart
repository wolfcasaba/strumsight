import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/setlists_provider.dart';
import 'setlist_detail_screen.dart';

/// The user's setlists: ordered practice sets of their own songs. A gig/practice
/// routine grouping on top of the songbook.
class SetlistListScreen extends ConsumerWidget {
  const SetlistListScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _promptName(context);
    if (name == null || name.trim().isEmpty) return;
    final id = await ref.read(setlistsProvider.notifier).add(name.trim());
    if (context.mounted) _open(context, id);
  }

  void _open(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SetlistDetailScreen(setlistId: id),
      ),
    );
  }

  /// The Setlist V2 entry point (audit §5.2, R12).
  ///
  /// [AppRoutes.setlistsV2] has been registered since R10, but NO shipped
  /// surface pushed it — measured, and the reason the ordered setlist run
  /// (each item launching the real Song Trainer session and waiting for it)
  /// did not exist for the user at all. This card is that entry, and it
  /// lives in the scrolling body rather than the AppBar so a long label at
  /// 2.0 text scale scrolls instead of squeezing the title row.
  ///
  /// `context.push`, not `go`: Back returns to this list.
  Widget _runnerEntry(BuildContext context, AppLocalizations l10n) {
    return SsContentCard(
      key: const Key('setlist-open-v2'),
      icon: Icons.playlist_play,
      title: l10n.setlistRunnerTitle,
      message: l10n.setlistRunnerBody,
      actions: [
        SsCardAction(
          label: l10n.setlistRunnerTitle,
          onPressed: () => context.push(AppRoutes.setlistsV2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final setlists = ref.watch(setlistsProvider);
    final colors = Theme.of(context).extension<SsColorScheme>()!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setlistsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        backgroundColor: colors.brand,
        icon: const Icon(Icons.add),
        label: Text(l10n.setlistNew),
      ),
      body: SafeArea(
        child: setlists.isEmpty
            ? _ScrollableIfShort(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _runnerEntry(context, l10n),
                    ),
                    SsEmptyState(
                      icon: Icons.queue_music,
                      title: l10n.setlistsEmptyTitle,
                      message: l10n.setlistsEmpty,
                      actionLabel: l10n.setlistNew,
                      onAction: () => _create(context, ref),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: setlists.length + 1,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SsSpacing.space2),
                itemBuilder: (context, i) {
                  if (i == 0) return _runnerEntry(context, l10n);
                  final set = setlists[i - 1];
                  return SsContentCard(
                    icon: Icons.queue_music,
                    title: set.name,
                    message: l10n.setlistSongCount(set.songIds.length),
                    actions: [
                      SsCardAction(
                        label: l10n.setlistOpen,
                        onPressed: () => _open(context, set.id),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

/// A tiny name prompt shared by create + rename.
Future<String?> _promptName(BuildContext context, {String initial = ''}) {
  final l10n = AppLocalizations.of(context);
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.setlistName),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: l10n.setlistName),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text),
          child: Text(l10n.songSave),
        ),
      ],
    ),
  );
}

// Exposed for the detail screen's rename action.
Future<String?> promptSetlistName(
  BuildContext context, {
  String initial = '',
}) => _promptName(context, initial: initial);

/// Lets [child] (the runner-entry card above an [SsEmptyState], which is
/// always `Center`-wrapped internally) scroll instead of overflow when the
/// viewport is too short for it — measured need: at `textScaler` 2.5 +
/// `hu`, the empty state's icon + title + message + action button outgrows
/// a short test viewport by 39px, and the R12 entry card adds to that.
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
