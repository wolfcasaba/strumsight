import 'package:flutter/material.dart';

import '../../../../core/music/tuning.dart';
import '../../../../l10n/app_localizations.dart';

/// Setup-time reminders only. This widget does not start tuner, transport, or
/// session resources; those remain owned by their later feature rounds.
final class TuningCapoReminder extends StatelessWidget {
  const TuningCapoReminder({
    required this.tuning,
    required this.showCapoReminder,
    required this.canResume,
    this.onResume,
    super.key,
  });

  final Tuning? tuning;
  final bool showCapoReminder;
  final bool canResume;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (tuning != null)
          Semantics(
            key: const Key('trainer-tuning-reminder'),
            label: l10n.trainerTuningReminder(tuning!.id),
            child: ListTile(
              leading: const Icon(Icons.tune),
              title: Text(l10n.trainerTuningReminder(tuning!.id)),
            ),
          ),
        if (showCapoReminder)
          Semantics(
            key: const Key('trainer-capo-reminder'),
            label: l10n.trainerCapoReminder,
            child: ListTile(
              leading: const Icon(Icons.music_note_outlined),
              title: Text(l10n.trainerCapoReminder),
            ),
          ),
        if (canResume)
          FilledButton.tonal(
            onPressed: onResume,
            child: Text(l10n.trainerResume),
          ),
      ],
    );
  }
}
