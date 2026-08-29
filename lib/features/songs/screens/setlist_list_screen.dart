import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                child: SsEmptyState(
                  icon: Icons.queue_music,
                  title: l10n.setlistsEmptyTitle,
                  message: l10n.setlistsEmpty,
                  actionLabel: l10n.setlistNew,
                  onAction: () => _create(context, ref),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: setlists.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: SsSpacing.space2),
                itemBuilder: (context, i) {
                  final set = setlists[i];
                  return SsContentCard(
                    icon: Icons.queue_music,
                    title: set.name,
                    message: l10n.setlistSongCount(set.songIds.length),
                    actions: [
                      SsCardAction(
                        label: set.name,
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

/// Lets [child] (an [SsEmptyState], always `Center`-wrapped internally)
/// scroll instead of overflow when the viewport is too short for it —
/// measured need: at `textScaler` 2.5 + `hu`, the empty state's icon +
/// title + message + action button outgrows a short test viewport by 39px.
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
