import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/song_measure.dart';

final class MeasureGrid extends StatelessWidget {
  const MeasureGrid({
    required this.measures,
    required this.onInsert,
    required this.onDelete,
    super.key,
  });

  final List<SongMeasure> measures;
  final ValueChanged<int> onInsert;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.songEditorMeasures,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final measure in measures)
              InputChip(
                label: Text('${measure.index + 1}'),
                onDeleted: measures.length > 1
                    ? () => onDelete(measure.index)
                    : null,
              ),
            ActionChip(
              key: const Key('song-editor-add-measure'),
              avatar: const Icon(Icons.add),
              label: Text(l10n.songEditorAddMeasure),
              onPressed: () => onInsert(measures.length),
            ),
          ],
        ),
      ],
    );
  }
}
