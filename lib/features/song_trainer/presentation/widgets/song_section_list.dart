import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/trainer/song_trainer_setup_state.dart';

/// Accessible list of persisted song sections. Section names are authored
/// music data; all surrounding UI copy comes from ARB resources.
final class SongSectionList extends StatelessWidget {
  const SongSectionList({required this.sections, this.onSelected, super.key});

  final List<TrainerSectionOption> sections;
  final ValueChanged<TrainerSectionOption>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (sections.isEmpty) return Text(l10n.songOverviewNoSections);
    return Column(
      children: <Widget>[
        for (final section in sections)
          ListTile(
            key: Key('song-overview-section-${section.id.value}'),
            title: Text(section.name),
            subtitle: Text(
              '${section.startMeasure + 1}–${section.endMeasureExclusive}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onSelected == null ? null : () => onSelected!(section),
          ),
      ],
    );
  }
}
