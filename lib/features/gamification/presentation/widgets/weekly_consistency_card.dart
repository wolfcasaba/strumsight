import 'package:flutter/material.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Shows a validated weekly consistency projection supplied by the caller.
class WeeklyConsistencyCard extends StatelessWidget {
  WeeklyConsistencyCard({super.key, required this.days}) {
    if (days < 0 || days > 7) {
      throw ArgumentError.value(days, 'days', 'must be between 0 and 7');
    }
  }

  final int days;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.streakV2WeeklySemantics(days),
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.streakV2WeeklyTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.streakV2WeeklyValue(days),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
