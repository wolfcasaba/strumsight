import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// The session-readiness row (SDD UI-20, §0.0/R6).
///
/// Renders **two separate, never-merged** indicators — weak signal and
/// degraded capability — plus a third, always-honest tuning entry that never
/// claims the instrument is in tune (the live tuning readout is a follow-up,
/// §0.0/R6). Each indicator carries both an icon and a label — status is
/// never conveyed by colour alone (ADR 0079 §10).
class PracticeReadinessRow extends StatelessWidget {
  const PracticeReadinessRow({
    required this.weakSignal,
    required this.degradedCapability,
    required this.onOpenTuner,
    super.key,
  });

  /// True when the live score has not produced a signal yet while capture
  /// is active — derived from the presentation-visible `liveOverallPerMille`
  /// primitive, never from a domain/service reason code (A9 guard).
  final bool weakSignal;

  /// True when a recoverable audio/mic failure is currently surfaced —
  /// derived from the presentation-side error overlay, never from a new
  /// business concept invented for this row.
  final bool degradedCapability;

  /// Opens the Tuner via `AppRoutes.practiceTuner`. The row itself holds no
  /// routing knowledge — the caller supplies the navigation.
  final VoidCallback onOpenTuner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _ReadinessChip(
          key: const ValueKey('practice-readiness-signal'),
          icon: weakSignal
              ? Icons.graphic_eq_outlined
              : Icons.check_circle_outline,
          label: weakSignal
              ? l10n.practiceSessionReadinessWeakSignal
              : l10n.practiceSessionReadinessSignalOk,
          warn: weakSignal,
        ),
        _ReadinessChip(
          key: const ValueKey('practice-readiness-capability'),
          icon: degradedCapability
              ? Icons.warning_amber_outlined
              : Icons.check_circle_outline,
          label: degradedCapability
              ? l10n.practiceSessionReadinessDegraded
              : l10n.practiceSessionReadinessCapabilityOk,
          warn: degradedCapability,
        ),
        PracticeTuningEntry(onOpenTuner: onOpenTuner),
      ],
    );
  }
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip({
    required this.icon,
    required this.label,
    required this.warn,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warn ? scheme.error : scheme.primary;
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tuning entry point — always "not measured", never "in tune"
/// (§0.0/R6): the live tuning readout does not exist yet, so this row must
/// not lie about it. Tapping navigates to the Tuner
/// (`AppRoutes.practiceTuner`).
///
/// Public (not private to [PracticeReadinessRow]) so the Setup screen can
/// render the same entry point outside a running session (review E13-R21
/// MINOR-1) — the setup surface has no weak-signal/degraded-capability
/// concept (no capture is active yet), only the tuning affordance applies.
class PracticeTuningEntry extends StatelessWidget {
  const PracticeTuningEntry({required this.onOpenTuner, super.key});

  final VoidCallback onOpenTuner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label:
          '${l10n.practiceSessionReadinessTuningUnmeasured}. '
          '${l10n.practiceSessionReadinessOpenTuner}',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('practice-readiness-tuning'),
        onTap: onOpenTuner,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          // ADR 0280 §Döntés 5: critical components need a ≥ 48 dp touch
          // target. This is the row's only interactive element and the
          // sole entry point to the Tuner from this surface (review
          // E13-R21 MAJOR-2 — measured 32 dp).
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 16, color: scheme.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  l10n.practiceSessionReadinessTuningUnmeasured,
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
