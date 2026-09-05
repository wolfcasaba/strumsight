import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/lifecycle/audio_session_lease.dart';
import '../engine/real_strum_engine.dart';
import '../engine/recognition_stabilizer.dart';
import '../engine/strum_engine.dart';
import '../model/live_frame.dart';

/// The active detection engine — the REAL microphone+DSP engine.
/// (MockStrumEngine remains test infrastructure; tests override this.)
final strumEngineProvider = Provider<StrumEngine>((ref) {
  final engine = RealStrumEngine(mic: createMicCapture(ref, AudioOwner.live));
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

/// Whether mic permission is granted (requests it on first read).
///
/// E01-R09: a missing permission channel is `unavailable`, i.e. NOT granted —
/// production never treats a plugin error as consent. Tests override
/// [microphonePermissionGatewayProvider] with a fake gateway.
final micPermissionProvider = FutureProvider<bool>((ref) async {
  final gateway = ref.watch(microphonePermissionGatewayProvider);
  final current = await gateway.currentState();
  if (current.isGranted) return true;
  return (await gateway.request()).isGranted;
});
