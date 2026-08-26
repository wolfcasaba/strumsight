import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../core/platform/app_lifecycle.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/mic_permission_banner.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/public.dart';
import '../../application/practice_session_command.dart';
import '../../domain/model/practice_mode.dart';
import '../../domain/model/practice_session_state.dart';
import '../../domain/model/speed_builder_state.dart';
import '../practice_effect_listener.dart';
import '../views/chord_change_view.dart';
import '../views/chord_progression_view.dart';
import '../views/free_practice_view.dart';
import '../views/rhythm_only_view.dart';
import '../views/strum_pattern_view.dart';
import '../widgets/adaptive_suggestion_banner.dart';
import '../widgets/practice_controls.dart';
import '../widgets/practice_count_in_overlay.dart';
import '../widgets/practice_error_panel.dart';
import '../widgets/practice_hud.dart';
import '../widgets/practice_pause_overlay.dart';
import '../widgets/practice_readiness_row.dart';
import '../widgets/speed_builder_progress.dart';

class PracticeSessionScreen extends ConsumerStatefulWidget {
  const PracticeSessionScreen({
    this.speedBuilderState,
    this.adaptiveSuggestion,
    this.onAcceptAdaptiveSuggestion,
    this.onDismissAdaptiveSuggestion,
    this.currentLoop,
    this.totalLoops,
    super.key,
  });

  final SpeedBuilderState? speedBuilderState;
  final AdaptiveSuggestion? adaptiveSuggestion;
  final ValueChanged<AdaptiveSuggestion>? onAcceptAdaptiveSuggestion;
  final VoidCallback? onDismissAdaptiveSuggestion;
  final int? currentLoop;
  final int? totalLoops;

  @override
  ConsumerState<PracticeSessionScreen> createState() =>
      _PracticeSessionScreenState();
}

class _PracticeSessionScreenState extends ConsumerState<PracticeSessionScreen> {
  StreamSubscription<PracticeSessionState>? _states;
  PracticeSessionHost? _host;
  PracticeSessionState _state = PracticeSessionState.initial;
  bool _exitInProgress = false;
  late final void Function(AppLifecycleState) _lifecycleListener;
  late final AppLifecycleEvents _lifecycle;

  @override
  void initState() {
    super.initState();
    _host = ref.read(practiceSessionHostProvider);
    final host = _host;
    if (host != null) {
      _state = host.state;
      _states = host.states.listen((state) {
        if (mounted) setState(() => _state = state);
      });
    }
    _lifecycleListener = (state) {
      final host = _host;
      if (host != null) forwardPracticeLifecycle(host, state);
    };
    _lifecycle = ref.read(appLifecycleEventsProvider);
    _lifecycle.addListener(_lifecycleListener);
  }

  @override
  void dispose() {
    _states?.cancel();
    _lifecycle.removeListener(_lifecycleListener);
    super.dispose();
  }

  /// True only when the session is in a non-terminal phase AND the user
  /// has not yet confirmed an exit. Used by the [PopScope] so system back
  /// and the AppBar back affordance share the same gate.
  bool get _canPop {
    if (_exitInProgress) return true;
    final status = _state.status;
    return status == PracticeSessionStatus.completed ||
        status == PracticeSessionStatus.cancelled ||
        status == PracticeSessionStatus.idle;
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) return const _Unavailable();
    return PracticeEffectListener(
      child: SsStageScaffold(
        statusHeader: Text(
          AppLocalizations.of(context).practiceSessionTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        hero: _buildHero(context, host),
        feedback: _buildFeedback(context, host),
        timeline: const SizedBox.shrink(),
        bottomAction: PracticeControls(
          state: _state,
          onCommand: host.send,
          onExit: _requestExit,
        ),
        // ADR 0276/0079 §4: the same gate the previous PopScope used — the
        // Stage scaffold's own PopScope now owns the wiring, but the
        // decision of WHICH statuses need confirmation is still `_canPop`.
        hasUnsavedSession: !_canPop,
        onUnsavedSessionBackAttempt: _requestExit,
      ),
    );
  }

  /// The Stage `hero` slot — the primary, per-status content. Exactly the
  /// same conditions the pre-migration `ListView` used, just grouped into
  /// one slot instead of interleaved with the feedback-only widgets below.
  Widget _buildHero(BuildContext context, PracticeSessionHost host) {
    final status = _state.status;
    final children = <Widget>[];
    if (status == PracticeSessionStatus.preparing ||
        status == PracticeSessionStatus.finishing) {
      children.addAll([
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(_statusLabel(context, status)),
      ]);
    }
    if (status == PracticeSessionStatus.permissionRequired) {
      children.add(const MicPermissionBanner());
    }
    if (status == PracticeSessionStatus.countIn) {
      children.add(PracticeCountInOverlay(state: _state));
    }
    if (status == PracticeSessionStatus.paused) {
      // The Pause/Recovery overlay (SDD UI-20) — a widget inside this slot,
      // not a separate route (§0.0/R7). It renders from `pauseCause` alone
      // and its Resume button sends the SAME `ResumePractice` command the
      // bottom transport's own Resume affordance sends.
      children.add(
        PracticePauseOverlay(
          pauseCause: _state.pauseCause,
          onResume: () => host.send(const ResumePractice()),
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    if ((status == PracticeSessionStatus.running ||
            status == PracticeSessionStatus.paused) &&
        _state.target != null) {
      children.add(_ModeView(state: _state));
    }
    if (status == PracticeSessionStatus.failed &&
        _state.recoverableFailure != null) {
      children.add(
        PracticeErrorPanel(
          failure: _state.recoverableFailure!,
          onRetry: () => host.send(const RetryPractice()),
        ),
      );
    }
    if (status == PracticeSessionStatus.idle ||
        status == PracticeSessionStatus.completed ||
        status == PracticeSessionStatus.cancelled) {
      children.add(PracticeStateMessage(state: _state));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// The Stage `feedback` slot — the HUD, the readiness row (§0.0/R6), the
  /// adaptive/speed-builder banners, and the recoverable-error overlay.
  Widget _buildFeedback(BuildContext context, PracticeSessionHost host) {
    final status = _state.status;
    final isSessionActive =
        status == PracticeSessionStatus.running ||
        status == PracticeSessionStatus.paused;
    final children = <Widget>[];
    if (widget.speedBuilderState case final speedBuilderState?) {
      children.add(
        SpeedBuilderProgress(
          state: speedBuilderState,
          currentLoop: widget.currentLoop,
          totalLoops: widget.totalLoops,
        ),
      );
    }
    if (widget.adaptiveSuggestion case final suggestion?) {
      if (widget.onAcceptAdaptiveSuggestion != null &&
          widget.onDismissAdaptiveSuggestion != null) {
        children.add(
          AdaptiveSuggestionBanner(
            suggestion: suggestion,
            onAccept: widget.onAcceptAdaptiveSuggestion!,
            onDismiss: widget.onDismissAdaptiveSuggestion!,
          ),
        );
      }
    }
    if (isSessionActive) {
      children.add(
        PracticeHud(
          state: _state,
          liveOverallPerMille: host.liveOverallPerMille,
        ),
      );
      // Weak signal: no live score yet while capture is active. Degraded
      // capability: a recoverable failure is currently surfaced. Both are
      // presentation-visible primitives — never a domain/service import
      // (A9 guard) — and are rendered as two SEPARATE indicators, never
      // merged into one banner (§0.0/R6).
      final degradedCapability =
          ref.watch(practiceErrorOverlayProvider) != null;
      final weakSignal = host.liveOverallPerMille == null;
      children.add(
        PracticeReadinessRow(
          weakSignal: weakSignal,
          degradedCapability: degradedCapability,
          onOpenTuner: () => context.go(AppRoutes.practiceTuner),
        ),
      );
    }
    if (status != PracticeSessionStatus.failed) {
      children.add(_RecoverableErrorOverlay());
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children) ...[child, const SizedBox(height: 12)],
      ],
    );
  }

  String _statusLabel(BuildContext context, PracticeSessionStatus status) =>
      PracticeHud.statusLabel(AppLocalizations.of(context), status);

  Future<void> _requestExit() async {
    if (_exitInProgress) return;
    final host = _host;
    if (host == null) return;
    final status = _state.status;
    if (status == PracticeSessionStatus.finishing) return;
    if (practiceExitNeedsConfirmation[status] == true) {
      // Set the gate BEFORE opening the dialog so a rapid second back tap
      // is dropped at the entry guard (M1) — and clear it if the user
      // cancels so the screen remains usable.
      _exitInProgress = true;
      final confirmed = await showDialog<bool>(
        context: context,
        // ADR 0279 §3/§5: the choice must be an explicit Stay/Exit tap, not
        // an accidental barrier dismiss reinterpreted as "Stay". A
        // dismissible barrier is more reachable now that the consequence
        // copy is longer and the dialog sits on a compact-width screen —
        // more of the screen is bare barrier around it (measured while
        // writing this round's own tests, see the round handoff §10).
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).practiceSessionExit),
          content: Text(
            AppLocalizations.of(context).practiceSessionConfirmExit,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).practiceSessionStay),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).practiceSessionExit),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        _exitInProgress = false;
        return;
      }
    }
    final sentCommand = practiceExitSendsCancel[status] == true;
    if (sentCommand) {
      host.send(const CancelPractice());
    }
    if (!mounted) return;
    // Pop only when leaving the screen is meaningful: terminal states
    // (the PopScope already permits it) or when a CancelPractice was
    // just issued (the reducer will move the state to `cancelled` and
    // the next pop will go through). For no-op exit taps (preparing,
    // failed, …) the screen stays put.
    if (_canPop || sentCommand) {
      Navigator.of(context).pop();
    }
  }
}

class _RecoverableErrorOverlay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(practiceErrorOverlayProvider);
    if (failure == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      label: l10n.practiceSessionErrorTitle,
      child: Card(
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
              const SizedBox(height: 4),
              Text(practiceFailureMessage(l10n, failure)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => dismissPracticeError(ref),
                  child: Text(l10n.practiceSessionStay),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: EmptyState(
      icon: Icons.hourglass_empty,
      title: AppLocalizations.of(context).practiceSessionUnavailableTitle,
      subtitle: AppLocalizations.of(context).practiceSessionUnavailableBody,
    ),
  );
}

/// Renders the mode-specific view for the active session.
///
/// The runtime verdict/metrics are not part of the host boundary (R10) —
/// construction passes `null` and the live values will be wired in by the
/// round that wires the host. The widget still renders correctly today
/// (the highway, the chord lane, and the feedback banner all handle
/// `null` verdicts / metrics).
class _ModeView extends ConsumerWidget {
  const _ModeView({required this.state});
  final PracticeSessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = state.target;
    if (target == null) return const SizedBox.shrink();
    final definition = state.definition;
    final mode = definition?.mode ?? PracticeMode.strumPattern;
    final visualOffset = Duration(
      milliseconds: ref.watch(visualLatencyProvider),
    );
    final constraints = MediaQuery.of(context);
    final width = constraints.size.width - 32;
    // The verdict and metrics are part of the runtime feedback that the
    // host boundary does not yet expose (R10). Their absence is benign
    // for the layout — the widgets render correctly with null and the
    // round that wires the host will provide the live values.
    switch (mode) {
      case PracticeMode.strumPattern:
        return StrumPatternView(
          target: target,
          playhead: state.timelinePosition,
          visualOffset: visualOffset,
          width: width,
          highwayHeight: 168,
          lastVerdict: null,
          metrics: null,
        );
      case PracticeMode.chordProgression:
        return ChordProgressionView(
          target: target,
          playhead: state.timelinePosition,
          visualOffset: visualOffset,
          width: width,
          highwayHeight: 168,
          lastVerdict: null,
          metrics: null,
          showChordHint: state.config?.expectedChordHintEnabled ?? true,
        );
      case PracticeMode.chordChanges:
        return ChordChangeView(
          target: target,
          playhead: state.timelinePosition,
          width: width,
          latestChange: null,
          analysis: null,
          showChordHint: state.config?.expectedChordHintEnabled ?? true,
        );
      case PracticeMode.rhythmOnly:
        return RhythmOnlyView(
          target: target,
          playhead: state.timelinePosition,
          width: width,
          metrics: null,
        );
      case PracticeMode.freePractice:
        return FreePracticeView(summary: null, width: width);
    }
  }
}
