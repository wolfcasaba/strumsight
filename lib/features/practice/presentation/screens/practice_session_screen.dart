import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/platform_providers.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/practice_session_command.dart';
import '../../domain/model/practice_session_state.dart';
import '../practice_effect_listener.dart';
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
    ref.read(appLifecycleEventsProvider).addListener(_lifecycleListener);
  }

  @override
  void dispose() {
    _states?.cancel();
    ref.read(appLifecycleEventsProvider).removeListener(_lifecycleListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) return _Unavailable();
    return PopScope(
      canPop: false,
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
                  _state.status == PracticeSessionStatus.finishing)
                const LinearProgressIndicator(),
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
              if (_state.status == PracticeSessionStatus.failed &&
                  _state.recoverableFailure != null)
                PracticeErrorPanel(
                  failure: _state.recoverableFailure!,
                  onRetry: () => host.send(const RetryPractice()),
                ),
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
    );
  }

  Future<void> _requestExit() async {
    if (_exitInProgress) return;
    final host = _host;
    if (host == null) return;
    final status = _state.status;
    if (status == PracticeSessionStatus.finishing) return;
    if (practiceExitNeedsConfirmation[status] == true) {
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
      if (confirmed != true) return;
    }
    _exitInProgress = true;
    if (practiceExitSendsCancel[status] == true) {
      host.send(const CancelPractice());
    }
    if (mounted) Navigator.of(context).maybePop();
  }
}

class _Unavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: EmptyState(
      icon: Icons.hourglass_empty,
      title: AppLocalizations.of(context).practiceSessionUnavailableTitle,
      subtitle: AppLocalizations.of(context).practiceSessionUnavailableBody,
    ),
  );
}

class MicPermissionBanner extends StatelessWidget {
  const MicPermissionBanner({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: Text(AppLocalizations.of(context).practiceSessionPermissionBody),
  );
}
