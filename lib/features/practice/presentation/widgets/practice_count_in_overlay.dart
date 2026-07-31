import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_session_state.dart';

class PracticeCountInOverlay extends StatelessWidget {
  const PracticeCountInOverlay({required this.state, super.key});
  final PracticeSessionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = (state.countInSpanBeats - state.emittedCountInClicks)
        .clamp(0, state.countInSpanBeats);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '${l10n.practiceSessionCountIn}: $remaining',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
