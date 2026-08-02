// Riverpod binding for the production Practice observation gateway.
//
// Per ADR 0074 / ADR 0111 §2, the gateway provider lives in the `data/`
// layer (NOT in `application/practice_session_providers.dart`) because
// it depends on the `StrumEngine` and the microphone-permission gateway
// — both are forbidden by ADR 0077 §10 in the controllers/providers
// layer. The `data/` folder is the production boundary the engine and
// the audio session coordinate through; it is free to reference those
// symbols.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/logging/logger_provider.dart';
import '../../live/public.dart';
import '../application/practice_observation_gateway.dart';
import 'live_practice_observation_gateway.dart';

/// The production [PracticeObservationGateway] — wraps a
/// [LivePracticeObservationGateway] around the `strumEngineProvider`
/// and the `microphonePermissionGatewayProvider` (ADR 0111 §2 cross-
/// feature wiring on the live-public surface).
///
/// `timelineNow` reads a long-lived [Stopwatch] so the gateway's
/// monotonic pad and frame-delivery-lag math line up with the engine's
/// wall-clock production read. The default `Stopwatch().elapsed` is the
/// production choice — no hidden dependency on `DateTime.now`. Tests
/// override `strumEngineProvider` with a controllable fake and the
/// timeline flows through the same `_stopwatch()` closure.
final livePracticeObservationGatewayProvider =
    Provider<PracticeObservationGateway>((ref) {
      final engine = ref.watch(strumEngineProvider);
      final permissions = ref.watch(microphonePermissionGatewayProvider);
      final logger = ref.watch(appLoggerProvider);
      final stopwatch = Stopwatch()..start();
      return LivePracticeObservationGateway(
        engine: engine,
        permissions: permissions,
        timelineNow: () => stopwatch.elapsed,
        logger: logger,
      );
    });
