import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/platform/app_lifecycle.dart';
import '../../../../l10n/app_localizations.dart';
import '../application/practice_session_command.dart';
import '../application/practice_session_effect.dart';
import '../domain/model/practice_session_state.dart';

abstract interface class PracticeSessionHost {
  Stream<PracticeSessionState> get states;
  PracticeSessionState get state;
  Stream<PracticeSessionEffect> get effects;
  int? get liveOverallPerMille;
  void send(PracticeSessionCommand command);
}

abstract interface class PracticeFeedbackOutput {
  void haptic();
  void countInClick(int beatIndex);
  void announce(String message);
  void openPermissionSettings();
}

final practiceSessionHostProvider = Provider<PracticeSessionHost?>((_) => null);
final practiceHapticsEnabledProvider = Provider<bool>((_) => true);

final class PlatformPracticeFeedbackOutput implements PracticeFeedbackOutput {
  const PlatformPracticeFeedbackOutput();
  @override
  void haptic() => HapticFeedback.mediumImpact();
  @override
  void countInClick(int beatIndex) => SystemSound.play(SystemSoundType.click);
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

final practiceFeedbackOutputProvider = Provider<PracticeFeedbackOutput>(
  (_) => const PlatformPracticeFeedbackOutput(),
);

typedef PracticeResultNavigationSink = void Function();
final practiceResultNavigationSinkProvider =
    Provider<PracticeResultNavigationSink>((_) => () {});

class PracticeEffectListener extends ConsumerStatefulWidget {
  const PracticeEffectListener({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<PracticeEffectListener> createState() =>
      _PracticeEffectListenerState();
}

class _PracticeEffectListenerState
    extends ConsumerState<PracticeEffectListener> {
  StreamSubscription<PracticeSessionEffect>? _effects;
  bool _navigated = false;
  @override
  void initState() {
    super.initState();
    final host = ref.read(practiceSessionHostProvider);
    if (host != null) _effects = host.effects.listen(_handleEffect);
  }

  void _handleEffect(PracticeSessionEffect effect) {
    if (!mounted) return;
    final output = ref.read(practiceFeedbackOutputProvider);
    switch (effect) {
      case PlayHaptic():
        if (ref.read(practiceHapticsEnabledProvider)) output.haptic();
      case PlayCountInClick(:final beatIndex):
        output.countInClick(beatIndex);
      case ShowPermissionSettings():
        output.openPermissionSettings();
      case NavigateToResult():
        if (!_navigated) {
          _navigated = true;
          ref.read(practiceResultNavigationSinkProvider)();
        }
      case ShowRecoverableError():
        break;
      case AnnounceAccessibilityFeedback():
        break;
    }
  }

  @override
  void dispose() {
    _effects?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void forwardPracticeLifecycle(
  PracticeSessionHost host,
  AppLifecycleState state,
) {
  if (!isBackgroundLifecycleState(state)) return;
  final status = host.state.status;
  if (status == PracticeSessionStatus.countIn ||
      status == PracticeSessionStatus.running) {
    host.send(const PausePractice(cause: PauseCause.interruption));
  }
}

String practiceFailureMessage(AppLocalizations l10n, AppFailure failure) =>
    '${l10n.practiceSessionErrorTitle}: ${failure.code}';
