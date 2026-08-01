import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/compiled_practice_target.dart';
import '../../domain/model/practice_metrics.dart';

/// Mode view for Rhythm-only practice. The chord dimension is irrelevant
/// here (the scoring profile is `rhythmOnlyDefault` and the A1 acceptance
/// pins `chord = NotApplicable`); the direction dimension is informational
/// only — when the definition carries no direction, the dimension is still
/// surfaced as `NotApplicable` rather than a misleading 0%.
///
/// The view only ever depends on the deterministic `target` + the
/// host-wired metrics snapshot. It renders correctly with `metrics == null`
/// before the R10 host boundary is bound.
class RhythmOnlyView extends StatelessWidget {
  const RhythmOnlyView({
    required this.target,
    required this.playhead,
    required this.width,
    this.metrics,
    super.key,
  });

  final CompiledPracticeTarget target;
  final Duration playhead;
  final double width;
  final PracticeMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasDirection = target.events.any((event) => event.direction != null);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.practiceRhythmOnlyTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasDirection
                        ? l10n.practiceRhythmOnlyBodyWithDirection
                        : l10n.practiceRhythmOnlyBodyNoDirection,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _RhythmOnlySummary(metrics: metrics),
        ],
      ),
    );
  }
}

class _RhythmOnlySummary extends StatelessWidget {
  const _RhythmOnlySummary({this.metrics});

  final PracticeMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final metrics = this.metrics;
    final rhythmValue = metrics?.rhythm;
    final isReady = metrics != null;
    final rhythmSemantics = l10n.practiceRhythmOnlyRhythmSemantics;
    return Semantics(
      container: true,
      label: rhythmSemantics,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.practiceRhythmOnlyRhythmDimension,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                isReady ? _dimensionLabel(l10n, rhythmValue) : '—',
                style: theme.textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _dimensionLabel(AppLocalizations l10n, MetricValue? value) {
  if (value == null) return l10n.practiceRhythmOnlyDimensionPending;
  return switch (value) {
    MetricAvailable() => l10n.practiceRhythmOnlyDimensionAvailable,
    MetricNotApplicable() => l10n.practiceRhythmOnlyDimensionNotApplicable,
    MetricInsufficientData() => l10n.practiceRhythmOnlyDimensionInsufficient,
  };
}
