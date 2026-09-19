import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_session_state.dart';

class PracticeHud extends StatelessWidget {
  const PracticeHud({
    required this.state,
    required this.liveOverallPerMille,
    super.key,
  });

  final PracticeSessionState state;
  final int? liveOverallPerMille;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final score = liveOverallPerMille == null
        ? l10n.practiceSessionScoreUnavailable
        : '${(liveOverallPerMille! / 10).toStringAsFixed(1)}%';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.practiceSessionStatusLabel),
            Text(
              statusLabel(l10n, state.status),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.practiceSessionElapsed}: ${_format(state.activeElapsed)}',
            ),
            Text('${l10n.practiceSessionAttempt}: ${state.attemptIndex + 1}'),
            Text('${l10n.practiceSessionScore}: $score'),
          ],
        ),
      ),
    );
  }

  String _format(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  /// Maps a [PracticeSessionStatus] to the localized status label. Exposed
  /// as a static so the screen and the HUD agree on the exact string for
  /// every cell of the A1 matrix.
  static String statusLabel(
    AppLocalizations l10n,
    PracticeSessionStatus status,
  ) => switch (status) {
    PracticeSessionStatus.idle => l10n.practiceSessionStatusIdle,
    PracticeSessionStatus.preparing => l10n.practiceSessionStatusPreparing,
    PracticeSessionStatus.permissionRequired =>
      l10n.practiceSessionStatusPermission,
    PracticeSessionStatus.ready => l10n.practiceSessionStatusReady,
    PracticeSessionStatus.countIn => l10n.practiceSessionStatusCountIn,
    PracticeSessionStatus.running => l10n.practiceSessionStatusRunning,
    PracticeSessionStatus.paused => l10n.practiceSessionStatusPaused,
    PracticeSessionStatus.finishing => l10n.practiceSessionStatusFinishing,
    PracticeSessionStatus.completed => l10n.practiceSessionStatusCompleted,
    PracticeSessionStatus.cancelled => l10n.practiceSessionStatusCancelled,
    PracticeSessionStatus.failed => l10n.practiceSessionStatusFailed,
  };
}

/// The designed, localized non-running state of the session screen — the
/// idle entry state and the two terminal states (audit H16).
///
/// It replaces the developer dump this used to render ("Session state:
/// completed", the raw enum name interpolated into an ARB string): a
/// terminal session now gets a localized headline plus a body that says
/// what happens next, and no machine identifier ever reaches the user.
class PracticeStateMessage extends StatelessWidget {
  const PracticeStateMessage({required this.state, super.key});
  final PracticeSessionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // Exhaustive over every status: a new one must decide its own copy
    // here instead of silently falling into the neutral branch.
    final (IconData icon, String body) = switch (state.status) {
      PracticeSessionStatus.completed => (
        Icons.check_circle_outline,
        l10n.practiceSessionCompletedBody,
      ),
      PracticeSessionStatus.cancelled => (
        Icons.cancel_outlined,
        l10n.practiceSessionCancelledBody,
      ),
      PracticeSessionStatus.idle ||
      PracticeSessionStatus.preparing ||
      PracticeSessionStatus.permissionRequired ||
      PracticeSessionStatus.ready ||
      PracticeSessionStatus.countIn ||
      PracticeSessionStatus.running ||
      PracticeSessionStatus.paused ||
      PracticeSessionStatus.finishing ||
      PracticeSessionStatus.failed => (
        Icons.play_circle_outline,
        l10n.practiceSessionIdleBody,
      ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    PracticeHud.statusLabel(l10n, state.status),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
