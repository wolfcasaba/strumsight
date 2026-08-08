import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import 'package:strumsight/features/vision/public.dart';

/// Isolated summary card for optional Vision evidence.
///
/// The result screen intentionally does not host this widget until a later
/// round wires the session lifecycle to the Vision adapter.
class PracticeVisionDimension extends StatelessWidget {
  const PracticeVisionDimension({required this.quality, super.key});

  final VisionPracticeQuality quality;

  @override
  Widget build(BuildContext context) {
    if (quality == VisionPracticeQuality.unavailable) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final body = quality == VisionPracticeQuality.good
        ? l10n.practiceVisionDimensionGood
        : l10n.practiceVisionDimensionDegraded;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          label: l10n.practiceResultDimensionSemantic(
            l10n.practiceVisionDimensionTitle,
            body,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.practiceVisionDimensionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(body),
            ],
          ),
        ),
      ),
    );
  }
}
