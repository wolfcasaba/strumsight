import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_session_state.dart';

/// The Pause/Recovery overlay (SDD UI-20, ADR 0079 §9).
///
/// Renders ONLY from [PracticeSessionState.pauseCause] — it carries no
/// business state of its own (A4/§5.1): a user-initiated pause and a
/// system-interruption pause show different copy, both sourced from the
/// same state field the reducer already sets. `onResume` sends exactly the
/// same `ResumePractice` command the transport's own resume affordance
/// sends — this overlay is a second AFFORDANCE, not a second COMMAND PATH.
class PracticePauseOverlay extends StatelessWidget {
  const PracticePauseOverlay({
    required this.pauseCause,
    required this.onResume,
    super.key,
  });

  final PauseCause? pauseCause;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isInterruption = pauseCause == PauseCause.interruption;
    return Card(
      key: const ValueKey('practice-pause-overlay'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isInterruption
                  ? l10n.practiceSessionPausedByInterruption
                  : l10n.practiceSessionPausedByUser,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.practiceSessionResumeHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                key: const ValueKey('practice-pause-overlay-resume'),
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow),
                label: Text(l10n.practiceSessionResume),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
