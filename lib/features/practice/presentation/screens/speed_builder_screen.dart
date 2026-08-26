/// The Speed Builder setup / active / result screen (SDD UI-23, E13-R22,
/// ADR 0283 §Döntés 5).
///
/// The domain's [SpeedBuilderEngine] is the single source of truth for the
/// step-up ladder — this screen drives it with attempts, but never computes
/// "the best tempo" itself. [SpeedBuilderState.highestStableTempo] is always
/// what gets shown, never the single best-scoring attempt (A6): a lucky
/// one-off pass at a high tempo is not "stable" unless the engine's
/// consecutive-pass rule confirms it.
library;

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_attempt_result.dart';
import '../../domain/model/practice_metrics.dart';
import '../../domain/model/practice_verdict.dart';
import '../../domain/model/speed_builder_policy.dart';
import '../../domain/model/speed_builder_state.dart';
import '../../domain/model/tempo.dart';
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
  /// screen straight into an active/finished ladder without tapping through
  /// the setup layout. Production callers leave this null.
  final SpeedBuilderState? initialState;

  @override
  State<SpeedBuilderScreen> createState() => _SpeedBuilderScreenState();
}

class _SpeedBuilderScreenState extends State<SpeedBuilderScreen> {
  static const _engine = SpeedBuilderEngine();

  SpeedBuilderState? _state;
  int _nextAttemptIndex = 0;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    _nextAttemptIndex = widget.initialState?.attempts.length ?? 0;
  }

  void _start() {
    setState(() => _state = SpeedBuilderState.initial(widget.policy));
  }

  void _record({required bool pass}) {
    final state = _state;
    if (state == null || state.isClosed) return;
    final attempt = _syntheticAttempt(
      index: _nextAttemptIndex,
      tempo: state.currentTempo,
      pass: pass,
    );
    _nextAttemptIndex++;
    setState(() => _state = _engine.record(state, attempt));
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: state == null
              ? _SetupLayout(policy: widget.policy, onStart: _start)
              : state.isClosed
              ? _ResultLayout(
                  state: state,
                  onDone: () => Navigator.of(context).maybePop(),
                )
              : _ActiveLayout(
                  state: state,
                  onRecordPass: () => _record(pass: true),
                  onRecordFail: () => _record(pass: false),
                  onFinish: _finish,
                ),
        ),
      ),
    );
  }
}

/// Synthesizes one attempt result for the demo ladder. `pass` picks metric
/// values on either side of [SpeedBuilderEngine]'s own pass thresholds — the
/// engine (not this function) decides whether the attempt actually advances
/// the ladder.
PracticeAttemptResult _syntheticAttempt({
  required int index,
  required Tempo tempo,
  required bool pass,
}) {
  final metrics = PracticeMetrics(
    completion: MetricAvailable(pass ? 0.98 : 0.5),
    rhythm: MetricAvailable(pass ? 0.9 : 0.6),
    direction: const MetricNotApplicable(),
    chord: const MetricNotApplicable(),
    overall: MetricAvailable(pass ? 0.9 : 0.6),
    totalTargets: 8,
    resolvedTargets: pass ? 8 : 4,
    maxCombo: pass ? 8 : 2,
    scorePoints: pass ? 800 : 300,
    meanAbsoluteOffset: const Duration(milliseconds: 20),
    timingBias: Duration.zero,
  );
  return PracticeAttemptResult(
    index: index,
    tempo: tempo,
    metrics: metrics,
    verdicts: const <PracticeVerdict>[],
    outcome: pass
        ? PracticeAttemptOutcome.passed
        : PracticeAttemptOutcome.failed,
  );
}

class _SetupLayout extends StatelessWidget {
  const _SetupLayout({required this.policy, required this.onStart});
  final SpeedBuilderPolicy policy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.speedBuilderSetupIntro),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(
                  l10n.speedBuilderCurrentBpm(_formatBpm(policy.startBpm.bpm)),
                ),
                Text(
                  l10n.speedBuilderTargetBpm(_formatBpm(policy.targetBpm.bpm)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onStart,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(l10n.speedBuilderStartCta),
        ),
      ],
    );
  }
}

class _ActiveLayout extends StatelessWidget {
  const _ActiveLayout({
    required this.state,
    required this.onRecordPass,
    required this.onRecordFail,
    required this.onFinish,
  });

  final SpeedBuilderState state;
  final VoidCallback onRecordPass;
  final VoidCallback onRecordFail;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpeedBuilderProgress(state: state),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onRecordPass,
                child: Text(l10n.speedBuilderRecordPass),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: onRecordFail,
                child: Text(l10n.speedBuilderRecordFail),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: onFinish,
          child: Text(l10n.speedBuilderFinishCta),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.speedBuilderResultTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(_statusLabel(l10n, state.status)),
                const SizedBox(height: 4),
                Text(l10n.speedBuilderHighestStable(stableLabel)),
                const SizedBox(height: 4),
                Text(l10n.speedBuilderResultAttempts(state.attempts.length)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onDone, child: Text(l10n.speedBuilderDoneCta)),
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
