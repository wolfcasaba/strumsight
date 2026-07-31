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
              _statusLabel(l10n, state.status),
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

  String _statusLabel(AppLocalizations l10n, PracticeSessionStatus status) =>
      switch (status) {
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

class PracticeStateMessage extends StatelessWidget {
  const PracticeStateMessage({required this.state, super.key});
  final PracticeSessionState state;

  @override
  Widget build(BuildContext context) => Text(
    AppLocalizations.of(context).practiceSessionStateMessage(state.status.name),
  );
}
