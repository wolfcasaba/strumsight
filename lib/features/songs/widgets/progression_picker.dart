import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../theory/progressions.dart';

/// A modal sheet: pick a key, then a common progression → returns the resolved
/// chord list (or null if dismissed). The songwriter's shortcut into a song.
Future<List<String>?> showProgressionPicker(BuildContext context) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _ProgressionPicker(),
  );
}

class _ProgressionPicker extends StatefulWidget {
  const _ProgressionPicker();

  @override
  State<_ProgressionPicker> createState() => _ProgressionPickerState();
}

class _ProgressionPickerState extends State<_ProgressionPicker> {
  SongKey _key = SongKey.all.first;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.songSuggestTitle,
                style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 20)),
            const SizedBox(height: 4),
            Text(l10n.songKeyLabel,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final k in SongKey.all)
                  ChoiceChip(
                    label: Text(k.name),
                    selected: _key.name == k.name,
                    onSelected: (_) => setState(() => _key = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (final p in ProgressionTemplate.all)
              _ProgressionTile(
                template: p,
                chords: p.chordsFor(_key),
                onTap: () => Navigator.of(context).pop(p.chordsFor(_key)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressionTile extends StatelessWidget {
  const _ProgressionTile({
    required this.template,
    required this.chords,
    required this.onTap,
  });

  final ProgressionTemplate template;
  final List<String> chords;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text('${template.name}  ·  ${chords.join(' ')}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(template.roman),
        trailing: const Icon(Icons.add, color: AppColors.primary),
        onTap: onTap,
      ),
    );
  }
}
