import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/practice_session_command.dart';
import '../../domain/model/practice_session_state.dart';

class PracticeControls extends StatelessWidget {
  const PracticeControls({
    required this.state,
    required this.onCommand,
    required this.onExit,
    super.key,
  });
  final PracticeSessionState state;
  final void Function(PracticeSessionCommand command) onCommand;
  final VoidCallback onExit;

  /// Per ADR 0079 §4 the controls freeze while the session is in its
  /// terminal `finishing` phase — nothing else can be issued in parallel.
  bool get _locked => state.status == PracticeSessionStatus.finishing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final buttons = <Widget>[];
    if (state.status == PracticeSessionStatus.ready) {
      buttons.add(
        _button(
          l10n.practiceSessionStart,
          () => onCommand(const StartPractice()),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.countIn ||
        state.status == PracticeSessionStatus.running) {
      buttons.add(
        _button(
          l10n.practiceSessionPause,
          () => onCommand(const PausePractice(cause: PauseCause.user)),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.paused) {
      buttons.add(
        _button(
          l10n.practiceSessionResume,
          () => onCommand(const ResumePractice()),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.running ||
        state.status == PracticeSessionStatus.paused) {
      buttons.add(
        _button(
          l10n.practiceSessionFinish,
          () => onCommand(const FinishPractice()),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.permissionRequired) {
      final definition = state.definition;
      final config = state.config;
      if (definition != null && config != null) {
        buttons.add(
          _button(
            l10n.practiceSessionPrepare,
            () => onCommand(
              PreparePractice(definition: definition, config: config),
            ),
          ),
        );
      }
    }
    if (state.status == PracticeSessionStatus.failed) {
      // The PracticeErrorPanel already exposes a Retry button; the
      // controls row only needs to provide the exit affordance.
    }
    // Exit is always present so the user can always reach the leave path,
    // but in `finishing` the gate inside `_requestExit` is closed.
    buttons.add(_button(l10n.practiceSessionExit, onExit, enabled: !_locked));
    return Semantics(
      enabled: !_locked,
      child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
    );
  }

  Widget _button(String label, VoidCallback onPressed, {bool enabled = true}) =>
      Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: ElevatedButton(
            onPressed: enabled ? onPressed : null,
            child: Text(label),
          ),
        ),
      );
}

const Map<PracticeSessionStatus, bool> practiceExitNeedsConfirmation = {
  PracticeSessionStatus.idle: false,
  PracticeSessionStatus.preparing: false,
  PracticeSessionStatus.permissionRequired: false,
  PracticeSessionStatus.ready: false,
  PracticeSessionStatus.countIn: true,
  PracticeSessionStatus.running: true,
  PracticeSessionStatus.paused: true,
  PracticeSessionStatus.finishing: false,
  PracticeSessionStatus.completed: false,
  PracticeSessionStatus.cancelled: false,
  PracticeSessionStatus.failed: false,
};

const Map<PracticeSessionStatus, bool> practiceExitSendsCancel = {
  PracticeSessionStatus.idle: false,
  PracticeSessionStatus.preparing: false,
  PracticeSessionStatus.permissionRequired: true,
  PracticeSessionStatus.ready: true,
  PracticeSessionStatus.countIn: true,
  PracticeSessionStatus.running: true,
  PracticeSessionStatus.paused: true,
  PracticeSessionStatus.finishing: false,
  PracticeSessionStatus.completed: false,
  PracticeSessionStatus.cancelled: false,
  PracticeSessionStatus.failed: false,
};
