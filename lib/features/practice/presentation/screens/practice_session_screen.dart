import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/app_lifecycle.dart';
import '../../../../core/platform/platform_providers.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/mic_permission_banner.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/public.dart';
import '../../application/practice_session_command.dart';
import '../../domain/model/practice_mode.dart';
import '../../domain/model/practice_session_state.dart';
import '../practice_effect_listener.dart';
import '../views/chord_change_view.dart';
import '../views/chord_progression_view.dart';
import '../views/free_practice_view.dart';
import '../views/rhythm_only_view.dart';
import '../views/strum_pattern_view.dart';
import '../widgets/practice_controls.dart';
import '../widgets/practice_count_in_overlay.dart';
import '../widgets/practice_error_panel.dart';
import '../widgets/practice_hud.dart';

class PracticeSessionScreen extends ConsumerStatefulWidget {
  const PracticeSessionScreen({super.key});

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
      child: PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestExit();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context).practiceSessionTitle),
            leading: IconButton(
              onPressed: _requestExit,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_state.status == PracticeSessionStatus.preparing ||
                    _state.status == PracticeSessionStatus.finishing) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_statusLabel(context, _state.status)),
                ],
                if (_state.status == PracticeSessionStatus.permissionRequired)
                  const MicPermissionBanner(),
                if (_state.status == PracticeSessionStatus.countIn)
                  PracticeCountInOverlay(state: _state),
                if (_state.status == PracticeSessionStatus.running ||
                    _state.status == PracticeSessionStatus.paused)
                  PracticeHud(
                    state: _state,
                    liveOverallPerMille: host.liveOverallPerMille,
                  ),
                if ((_state.status == PracticeSessionStatus.running ||
                        _state.status == PracticeSessionStatus.paused) &&
                    _state.target != null)
                  _ModeView(state: _state),
                if (_state.status == PracticeSessionStatus.failed &&
                    _state.recoverableFailure != null)
                  PracticeErrorPanel(
                    failure: _state.recoverableFailure!,
                    onRetry: () => host.send(const RetryPractice()),
                  ),
                if (_state.status != PracticeSessionStatus.failed)
                  _RecoverableErrorOverlay(),
                if (_state.status == PracticeSessionStatus.idle ||
                    _state.status == PracticeSessionStatus.completed ||
                    _state.status == PracticeSessionStatus.cancelled)
                  PracticeStateMessage(state: _state),
                PracticeControls(
                  state: _state,
                  onCommand: host.send,
                  onExit: _requestExit,
                ),
              ],
            ),
          ),
        ),
      ),
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
