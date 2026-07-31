import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/platform/app_lifecycle.dart';
import '../../../../l10n/app_localizations.dart';
import '../application/practice_session_command.dart';
import '../application/practice_session_effect.dart';
import '../domain/model/practice_session_state.dart';

/// Presentation-side boundary the V2 session screen reads through
/// (ADR 0079 §2). The real implementation is wired in the next round;
/// the production default of [practiceSessionHostProvider] is `null`,
/// which the screen renders as a localised "session unavailable" state.
abstract interface class PracticeSessionHost {
  Stream<PracticeSessionState> get states;
  PracticeSessionState get state;
  Stream<PracticeSessionEffect> get effects;
  int? get liveOverallPerMille;
  void send(PracticeSessionCommand command);
}

/// Side-effects produced by the reducer. The presentation layer forwards
/// them to the platform (haptics, system sound, OS settings) and to the
/// in-app surfaces (error panel, navigation).
abstract interface class PracticeFeedbackOutput {
  void haptic();
  void countInClick(int beatIndex);
  void announce(String message);
  void openPermissionSettings();
}

/// Production default: nothing is wired yet, but the entry points still
/// delegate to the right platform call (ADR 0079 §7) so the listener is
/// not a silent no-op.
final class PlatformPracticeFeedbackOutput implements PracticeFeedbackOutput {
  const PlatformPracticeFeedbackOutput();
  @override
  void haptic() => HapticFeedback.mediumImpact();
  @override
  void countInClick(int beatIndex) => SystemSound.play(SystemSoundType.click);
  @override
  void announce(String message) {
    // Use the new (post-3.35) API; the single-view assumption holds for
    // every supported platform today (no multi-window on Android/iOS).
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view != null) {
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr);
    }
  }

  @override
  void openPermissionSettings() => openAppSettings();
}

final practiceSessionHostProvider = Provider<PracticeSessionHost?>((_) => null);
final practiceHapticsEnabledProvider = Provider<bool>((_) => true);

final practiceFeedbackOutputProvider = Provider<PracticeFeedbackOutput>(
  (_) => const PlatformPracticeFeedbackOutput(),
);

typedef PracticeResultNavigationSink = void Function();
final practiceResultNavigationSinkProvider =
    Provider<PracticeResultNavigationSink>((_) => () {});

/// The most recent recoverable failure delivered through a
/// [ShowRecoverableError] effect. The screen reads it via
/// `ref.read(practiceErrorOverlayProvider)` and dismisses it via
/// [dismissPracticeError]. A `null` value means "no overlay active".
final practiceErrorOverlayProvider = StateProvider<AppFailure?>((_) => null);

void dismissPracticeError(WidgetRef ref) =>
    ref.read(practiceErrorOverlayProvider.notifier).state = null;

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
      case ShowRecoverableError(:final failure):
        // ADR 0079 §6: a recoverable error keeps the session alive and
        // surfaces an in-app panel. No command is emitted.
        ref.read(practiceErrorOverlayProvider.notifier).state = failure;
      case AnnounceAccessibilityFeedback(:final messageKey):
        // The reducer never emits this variant today, but if it does the
        // surface is the screen-reader announcement channel — never
        // user-visible text.
        output.announce(messageKey);
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

/// Localises an [AppFailure] for the practice error panel. The machine
/// code never reaches the user; unknown codes fall back to a localised
/// generic message (brief §5.10).
String practiceFailureMessage(AppLocalizations l10n, AppFailure failure) {
  switch (failure.code) {
    case FailureCode.permissionMicrophoneDenied:
    case FailureCode.permissionUnavailable:
      return l10n.practiceSessionErrorPermission;
    case FailureCode.audioCaptureFailed:
    case FailureCode.audioUnavailable:
    case FailureCode.audioSessionBusy:
      return l10n.practiceSessionErrorAudio;
    case FailureCode.networkUnavailable:
    case FailureCode.networkTimeout:
    case FailureCode.networkServer:
    case FailureCode.networkTls:
    case FailureCode.networkBadResponse:
      return l10n.practiceSessionErrorNetwork;
    case FailureCode.practiceObservationStreamFailed:
    case FailureCode.practiceObservationGatewayDisposed:
    case FailureCode.practiceInvalidSessionTransition:
    case FailureCode.practiceTargetUncompilable:
    case FailureCode.practiceContentUnsupported:
      return l10n.practiceSessionErrorBody;
    default:
      return l10n.practiceSessionErrorBody;
  }
}
