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
                  key: Key('song-editor-section-move-up-$index'),
                  // ADR 0280 §Döntés 5: every reorder affordance declares a
                  // >= 48 dp touch target, keyboard/button reachable without
                  // a drag gesture. Measured (E13-R24 review): this theme's
                  // MaterialTapTargetSize.padded default already inflates a
                  // Material 3 IconButton's hit box to 48x48 regardless of
                  // `constraints`, so this value is not what makes the tap
                  // target big enough today — it is the declared contract
                  // the test asserts on directly (IconButton.constraints),
                  // so a regression here is still caught even where a
                  // future theme change (e.g. shrinkWrap tap target size)
                  // would otherwise let it slip through unnoticed.
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  tooltip: l10n.songEditorMoveSectionUp,
                  onPressed: index == 0 ? null : () => onMove(index, index - 1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  key: Key('song-editor-section-move-down-$index'),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  tooltip: l10n.songEditorMoveSectionDown,
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
