import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/mic_capture.dart';
import '../engine/real_strum_engine.dart';
import '../engine/strum_engine.dart';
import '../model/live_frame.dart';

/// The active detection engine — the REAL microphone+DSP engine.
/// (MockStrumEngine remains test infrastructure; tests override this.)
final strumEngineProvider = Provider<StrumEngine>((ref) {
  final engine = RealStrumEngine();
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

/// Whether mic permission is granted (requests it on first read). True in
/// environments without the platform channel (tests) so widget tests never
/// hit a platform dependency.
final micPermissionProvider = FutureProvider<bool>((ref) {
  return MicCapture.ensurePermission();
});
