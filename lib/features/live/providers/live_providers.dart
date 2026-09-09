import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/lifecycle/audio_session_lease.dart';
import '../../../core/platform/microphone_permission.dart';
import '../domain/recognition/recognition_mode.dart';
import '../engine/real_strum_engine.dart';
import '../engine/recognition_stabilizer.dart';
import '../engine/strum_engine.dart';
import '../model/live_frame.dart';

/// The regime the app-wide detection engine is CONSTRUCTED in (E14-R30,
/// ADR 0544 D1 — read by [strumEngineProvider], never by a screen).
///
/// [RecognitionMode.free] is the fail-closed default and the ONLY value this
/// build ships: an expected-chord hint cannot even be BUILT for a free
/// engine, so no caller — Live, Learn, Practice — can bias the chord verdict
/// with a lesson target, whatever it passes to
/// [StrumEngine.setExpectedChord] (ADR 0550 D4).
///
/// It is a provider rather than a literal so the regime is one declared,
/// overridable value instead of an implicit constructor default: a future
/// round that decides the microphone-lease question can raise it here, in
/// one place, and every consumer of the shared engine moves with it.
/// Raising it is a PRODUCT decision with a measurable consequence (ADR 0544
/// D3 marks the tie-break's real-lesson value as UNKNOWN), so this round
/// does not raise it.
final liveRecognitionModeProvider = Provider<RecognitionMode>(
  (ref) => RecognitionMode.free,
);

/// The active detection engine — the REAL microphone+DSP engine.
/// (MockStrumEngine remains test infrastructure; tests override this.)
///
/// This is the app's single microphone client for chord/strum detection:
/// Live, Learn and the Practice observation gateway all drive THIS instance,
/// which is why the regime above is a property of the engine and not of the
/// screen that happens to be on top.
final strumEngineProvider = Provider<StrumEngine>((ref) {
  final engine = RealStrumEngine(
    mic: createMicCapture(ref, AudioOwner.live),
    mode: ref.watch(liveRecognitionModeProvider),
    // ADR 0552 D2: the quality-aware preprocessor is fail-closed — it runs
    // only when the build's flag says so (off in every environment today).
    preprocessingEnabled: ref
        .watch(appConfigProvider)
        .flags
        .recognitionPreprocessingEnabled,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// The live stream of frames: starts the engine while it is being listened to,
/// stops it (releasing the microphone) when the Live screen goes away.
final liveFrameProvider = StreamProvider.autoDispose<LiveFrame>((ref) {
  final engine = ref.watch(strumEngineProvider);
  engine.start();
  ref.onDispose(engine.stop);
  return engine.frames;
});

/// The chord-timeline's label-stability gate (ADR 0518). `autoDispose` so
/// every Live visit gets a fresh state machine and this never outlives the
/// timeline that owns it (D9).
final recognitionStabilizerProvider =
    Provider.autoDispose<RecognitionStabilizer>(
      (ref) => RecognitionStabilizer(),
    );

/// The microphone permission the mic-driven screens read — a CHECK, never a
/// request.
///
/// E01-R09: a missing permission channel is `unavailable`, i.e. NOT granted —
/// production never treats a plugin error as consent. Tests override
/// [microphonePermissionGatewayProvider] with a fake gateway.
///
/// Reading this provider must never show the system dialog (L6): a rebuild is
/// not user intent, and Android denies permanently after two refusals, so a
/// dialog burned by a rebuild costs the user a permission they can then only
/// restore from the system settings. Asking is an explicit action —
/// [MicPermissionController.requestOnce] — and re-reading the platform state
/// is [MicPermissionController.refresh], which the Live and Tuner screens
/// call on `AppLifecycleState.resumed` so a permission granted in the
/// settings takes effect without restarting the app (L5).
final micPermissionProvider =
    AsyncNotifierProvider<MicPermissionController, MicrophonePermissionState>(
      MicPermissionController.new,
    );

/// Owns the microphone-permission state for the whole app run.
///
/// The state is the raw [MicrophonePermissionState] rather than a `bool` so a
/// screen can tell "denied, ask again" from "denied for good, open settings"
/// — and so an unresolved read stays visibly unknown instead of collapsing
/// into a `false` that reads like a measured denial.
class MicPermissionController extends AsyncNotifier<MicrophonePermissionState> {
  /// Whether the system dialog has already been shown in this app run. Asking
  /// twice is what pushes Android into a permanent denial.
  bool _asked = false;

  @override
  Future<MicrophonePermissionState> build() =>
      ref.watch(microphonePermissionGatewayProvider).currentState();

  /// Re-read the CURRENT platform state. Never shows a dialog, so it is safe
  /// on every resume — this is what makes "grant it in the settings, come
  /// back" work without an app restart (L5).
  Future<void> refresh() async {
    final gateway = ref.read(microphonePermissionGatewayProvider);
    final next = await gateway.currentState();
    if (!ref.mounted) return;
    state = AsyncData(next);
  }

  /// Ask the user, at most once per app run and only when asking can still
  /// help (L6).
  ///
  /// A permanently denied / restricted permission — or a broken permission
  /// channel — cannot be repaired by another dialog: the banner's "Open
  /// settings" is the only way out, and a second dialog would merely burn a
  /// refusal. Call this from an explicit entry point (opening a mic-driven
  /// screen, tapping an "enable the microphone" action), never from `build`.
  Future<void> requestOnce() async {
    if (_asked) return;
    _asked = true;
    final gateway = ref.read(microphonePermissionGatewayProvider);
    final current = await gateway.currentState();
    if (!ref.mounted) return;
    if (current.isGranted || current.failure?.retryable == false) {
      state = AsyncData(current);
      return;
    }
    final result = await gateway.request();
    if (!ref.mounted) return;
    state = AsyncData(result);
  }
}
