import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/song_section.dart';

final class SongSectionEditor extends StatelessWidget {
  const SongSectionEditor({
    required this.sections,
    required this.onMove,
    super.key,
  });

  final List<SongSection> sections;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.songEditorSections,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (var index = 0; index < sections.length; index++)
          ListTile(
            dense: true,
            title: Text(sections[index].name),
            subtitle: Text(
              '${sections[index].startMeasure + 1}–${sections[index].endMeasureExclusive}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  onPressed: index == 0 ? null : () => onMove(index, index - 1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  onPressed: index + 1 == sections.length
                      ? null
                      : () => onMove(index, index + 1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
