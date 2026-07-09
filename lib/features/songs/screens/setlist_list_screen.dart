import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
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
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SetlistDetailScreen(setlistId: id),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final setlists = ref.watch(setlistsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.setlistsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add),
        label: Text(l10n.setlistNew),
      ),
      body: SafeArea(
        child: setlists.isEmpty
            ? _Empty(text: l10n.setlistsEmpty)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: setlists.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final set = setlists[i];
                  return Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.queue_music, color: Colors.white),
                      ),
                      title: Text(set.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(l10n.setlistSongCount(set.songIds.length)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, set.id),
                    ),
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
Future<String?> promptSetlistName(BuildContext context, {String initial = ''}) =>
    _promptName(context, initial: initial);

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
            Icon(Icons.queue_music,
                size: 56, color: AppColors.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
