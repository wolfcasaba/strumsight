import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/logger_provider.dart';
import '../platform/microphone_permission.dart';
import '../platform/platform_providers.dart';
import 'capture/audio_capture_factory.dart';
import 'lifecycle/audio_lifecycle_guard.dart';
import 'lifecycle/audio_session_coordinator.dart';
import 'lifecycle/audio_session_lease.dart';
import 'mic_capture.dart';

/// The microphone permission gateway (SDD Ch2 Kör 9 §9.1). Tests override this
/// with a fake instead of mocking the platform channel.
final microphonePermissionGatewayProvider =
    Provider<MicrophonePermissionGateway>(
      (_) => const PermissionHandlerMicrophoneGateway(),
    );

/// How a raw PCM capture is created. Overridden in tests with a fake capture.
final audioCaptureFactoryProvider = Provider<AudioCaptureFactory>(
  (_) => createPlatformAudioCapture,
);

/// THE microphone session coordinator — one per `ProviderScope`, which is what
/// makes "at most one owner" enforceable at all (§9.2).
final audioSessionCoordinatorProvider = Provider<AudioSessionCoordinator>(
  (ref) => AudioSessionCoordinator(logger: ref.watch(appLoggerProvider)),
);

/// Mounted for the app's lifetime (see `StrumSightApp`): releases the mic when
/// the app is backgrounded (§9.4).
final audioLifecycleGuardProvider = Provider<AudioLifecycleGuard>((ref) {
  final guard = AudioLifecycleGuard(
    coordinator: ref.watch(audioSessionCoordinatorProvider),
    events: ref.watch(appLifecycleEventsProvider),
  );
  ref.onDispose(guard.dispose);
  return guard;
});

/// Builds a mic session for [owner] from the wired-up providers — the one
/// place engines get their microphone from.
MicCapture createMicCapture(Ref ref, AudioOwner owner) => MicCapture(
  owner: owner,
  coordinator: ref.watch(audioSessionCoordinatorProvider),
  permissions: ref.watch(microphonePermissionGatewayProvider),
  captureFactory: ref.watch(audioCaptureFactoryProvider),
);
