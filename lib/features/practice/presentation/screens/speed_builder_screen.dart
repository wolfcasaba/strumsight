/// The Speed Builder setup / active / result screen (SDD UI-23, E13-R22,
/// ADR 0283 §Döntés 5).
///
/// The domain's [SpeedBuilderEngine] is the single source of truth for the
/// step-up ladder — this screen drives it with attempts, but never computes
/// "the best tempo" itself. [SpeedBuilderState.highestStableTempo] is always
/// what gets shown, never the single best-scoring attempt (A6): a lucky
/// one-off pass at a high tempo is not "stable" unless the engine's
/// consecutive-pass rule confirms it.
///
/// There is no live attempt source yet — recording a real pass/miss needs a
/// running practice session (microphone, DSP, `PracticeObservation`), and
/// that wiring is a later round's work. This screen never fabricates an
/// attempt to fill that gap (E13-R22 review MAJOR-1): with no
/// [SpeedBuilderState] to drive, it states plainly that live measurement
/// isn't available yet (ADR 0277 — a non-punitive failure presentation) and
/// offers no control that would produce an unmeasured result.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/speed_builder_policy.dart';
import '../../domain/model/speed_builder_state.dart';
import '../../domain/service/speed_builder_engine.dart';
import '../widgets/speed_builder_progress.dart';

class SpeedBuilderScreen extends StatefulWidget {
  const SpeedBuilderScreen({
    required this.policy,
    this.initialState,
    super.key,
  });

  final SpeedBuilderPolicy policy;

  /// Test-only seam (mirrors `PracticeSetupScreen.argsOverride`): drives the
  /// screen straight into an active/finished ladder without a live attempt
  /// source. Production callers leave this null — see the library doc.
  final SpeedBuilderState? initialState;

  @override
  State<SpeedBuilderScreen> createState() => _SpeedBuilderScreenState();
}

class _SpeedBuilderScreenState extends State<SpeedBuilderScreen> {
  static const _engine = SpeedBuilderEngine();

  SpeedBuilderState? _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  void _finish() {
    final state = _state;
    if (state == null || state.isClosed) return;
    setState(() => _state = _engine.finish(state));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.speedBuilderScreenTitle)),
      body: SafeArea(
        child: state == null
            ? const _UnavailableLayout()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(SsSpacing.space4),
                child: state.isClosed
                    ? _ResultLayout(
                        state: state,
                        onDone: () => Navigator.of(context).maybePop(),
                      )
                    : _ActiveLayout(state: state, onFinish: _finish),
              ),
      ),
    );
  }
}

/// The honest "no live session yet" entry (ADR 0277): reached whenever there
/// is no [SpeedBuilderState] to drive. Deliberately offers no "Start"
/// affordance — starting a ladder here could only ever be closed by a
/// fabricated attempt, which is exactly what the E13-R22 review rejected.
///
/// Built from design tokens directly rather than [SsEmptyState] /
/// [SsFailureState]: both mandate at least one action button (§5.2 of their
/// own contract), which would reintroduce the fabricated-attempt affordance
/// the E13-R22 review removed. There is no design-system catalog entry for
/// an action-less informational state.
class _UnavailableLayout extends StatelessWidget {
  const _UnavailableLayout();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.speed, color: colors.textSecondary, size: 40),
            const SizedBox(height: SsSpacing.space4),
            Text(
              l10n.speedBuilderUnavailableTitle,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              l10n.speedBuilderUnavailableBody,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveLayout extends StatelessWidget {
  const _ActiveLayout({required this.state, required this.onFinish});

  final SpeedBuilderState state;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpeedBuilderProgress(state: state),
        const SizedBox(height: SsSpacing.space4),
        SsButton(
          label: l10n.speedBuilderFinishCta,
          variant: SsButtonVariant.tertiary,
          onPressed: onFinish,
        ),
      ],
    );
  }
}

class _ResultLayout extends StatelessWidget {
  const _ResultLayout({required this.state, required this.onDone});

  final SpeedBuilderState state;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A6 — always the engine-confirmed stable tempo, never a raw attempt
    // peak: `state.highestStableTempo` is the ONLY tempo value read here.
    final stable = state.highestStableTempo;
    final stableLabel = stable == null
        ? l10n.speedBuilderNoStableBpm
        : '${_formatBpm(stable.bpm)} BPM';
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.speedBuilderResultTitle,
                style: typography.titleMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: SsSpacing.space2),
              Text(
                _statusLabel(l10n, state.status),
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: SsSpacing.space1),
              Text(
                l10n.speedBuilderHighestStable(stableLabel),
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: SsSpacing.space1),
              Text(
                l10n.speedBuilderResultAttempts(state.attempts.length),
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SsSpacing.space4),
        SsButton(label: l10n.speedBuilderDoneCta, onPressed: onDone),
      ],
    );
  }

  String _statusLabel(AppLocalizations l10n, SpeedBuilderStatus status) =>
      switch (status) {
        SpeedBuilderStatus.completed => l10n.speedBuilderStatusCompleted,
        SpeedBuilderStatus.maxAttemptsReached =>
          l10n.speedBuilderStatusMaxAttempts,
        SpeedBuilderStatus.userFinished => l10n.speedBuilderStatusUserFinished,
        // Unreachable: `_ResultLayout` is only built once `state.isClosed`
        // is true, and `isClosed` is defined as `status != active`.
        SpeedBuilderStatus.active => '',
      };
}

String _formatBpm(num bpm) =>
    bpm == bpm.roundToDouble() ? bpm.toInt().toString() : bpm.toString();
