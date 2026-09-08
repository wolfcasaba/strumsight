import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/practice_session_command.dart';
import '../../domain/model/practice_session_state.dart';

/// The visual weight of one transport control (audit L9).
///
/// The row used to be three identical [ElevatedButton]s, so nothing on
/// screen told the user which of Finish / Exit keeps the result and which
/// throws it away. Weight is now part of that answer: Finish is the filled
/// primary action, Start/Pause/Resume/Prepare stay the plain secondary
/// ones, and Exit is a low-emphasis action — error-toned exactly when it
/// really does discard the session.
enum _ControlEmphasis {
  /// Filled, brand-coloured: the action that ends the session and KEEPS
  /// the result.
  primary,

  /// The default [ElevatedButton]: transport actions that neither save
  /// nor discard anything.
  secondary,

  /// A plain text button: leaving a session that has already produced (or
  /// can no longer produce) a result — nothing is lost, so nothing is
  /// coloured as a danger.
  quiet,

  /// A text button in the error colour: this tap throws the running
  /// session away.
  destructive,
}

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

  /// True when tapping Exit in the current status really throws work away
  /// (audit L9). It is the SAME map the screen's exit handler consults, so
  /// the promise the button makes and the command it sends cannot drift
  /// apart: a `CancelPractice` is exactly what discards the session.
  bool get _exitDiscards => practiceExitSendsCancel[state.status] == true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final buttons = <Widget>[];
    if (state.status == PracticeSessionStatus.ready) {
      buttons.add(
        _button(
          context,
          l10n.practiceSessionStart,
          () => onCommand(const StartPractice()),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.countIn ||
        state.status == PracticeSessionStatus.running) {
      buttons.add(
        _button(
          context,
          l10n.practiceSessionPause,
          () => onCommand(const PausePractice(cause: PauseCause.user)),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.paused) {
      buttons.add(
        _button(
          context,
          l10n.practiceSessionResume,
          () => onCommand(const ResumePractice()),
        ),
      );
    }
    if (state.status == PracticeSessionStatus.running ||
        state.status == PracticeSessionStatus.paused) {
      // Audit L9: Finish is the one control that ends the session AND
      // keeps the result, so it carries the primary weight and says so.
      buttons.add(
        _button(
          context,
          l10n.practiceSessionFinish,
          () => onCommand(const FinishPractice()),
          emphasis: _ControlEmphasis.primary,
          hint: l10n.practiceSessionFinishHint,
        ),
      );
    }
    if (state.status == PracticeSessionStatus.permissionRequired) {
      final definition = state.definition;
      final config = state.config;
      if (definition != null && config != null) {
        buttons.add(
          _button(
            context,
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
    //
    // Audit L9: the destructive tone and the "this discards it" hint are
    // attached ONLY while an exit would actually cancel a live session.
    // In a terminal status (completed / cancelled / failed) the result is
    // already recorded and Exit merely leaves the screen — claiming a loss
    // there would be a false warning.
    buttons.add(
      _button(
        context,
        l10n.practiceSessionExit,
        onExit,
        enabled: !_locked,
        emphasis: _exitDiscards
            ? _ControlEmphasis.destructive
            : _ControlEmphasis.quiet,
        hint: _exitDiscards ? l10n.practiceSessionExitHint : null,
      ),
    );
    return Semantics(
      enabled: !_locked,
      child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
    );
  }

  /// One transport button.
  ///
  /// [hint] is the localized consequence sentence (audit L9). It is exposed
  /// twice on purpose: as the semantics `hint` for screen-reader users and
  /// as a [Tooltip] for everyone else. It is never folded into the
  /// semantics `label` — the label stays the bare action word, which is
  /// what the accessibility traversal regression pins.
  Widget _button(
    BuildContext context,
    String label,
    VoidCallback onPressed, {
    bool enabled = true,
    _ControlEmphasis emphasis = _ControlEmphasis.secondary,
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveOnPressed = enabled ? onPressed : null;
    final text = Text(label);
    // `Finish`, `Start`, `Pause`, `Resume` and `Prepare` stay
    // `ElevatedButton`s: the release-flow and E2E harnesses find them by
    // that exact type, and the audit asked for a weight change, not a
    // widget swap.
    final Widget button = switch (emphasis) {
      _ControlEmphasis.primary => ElevatedButton(
        onPressed: effectiveOnPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
        child: text,
      ),
      _ControlEmphasis.secondary => ElevatedButton(
        onPressed: effectiveOnPressed,
        child: text,
      ),
      _ControlEmphasis.quiet => TextButton(
        onPressed: effectiveOnPressed,
        child: text,
      ),
      _ControlEmphasis.destructive => TextButton(
        onPressed: effectiveOnPressed,
        style: TextButton.styleFrom(foregroundColor: scheme.error),
        child: text,
      ),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: hint,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: hint == null ? button : Tooltip(message: hint, child: button),
      ),
    );
  }
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
