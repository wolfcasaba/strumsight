import 'package:flutter/material.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/practice_session_command.dart';

class PracticeErrorPanel extends StatelessWidget {
  const PracticeErrorPanel({
    required this.failure,
    required this.onRetry,
    super.key,
  });
  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practiceSessionErrorTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(l10n.practiceSessionErrorBody),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onRetry,
              child: Text(l10n.practiceSessionRetry),
            ),
          ],
        ),
      ),
    );
  }
}

// Keeps the command import explicit at this presentation boundary.
PracticeSessionCommand retryCommand() => const RetryPractice();
