import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/mock_strum_engine.dart';
import '../engine/strum_engine.dart';
import '../model/live_frame.dart';

/// The active detection engine. v1 = [MockStrumEngine]; swap to the C++ FFI
/// engine here later and nothing else changes.
final strumEngineProvider = Provider<StrumEngine>((ref) {
  final engine = MockStrumEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The live stream of frames: starts the engine while it is being listened to,
/// stops it when the Live screen goes away.
final liveFrameProvider = StreamProvider.autoDispose<LiveFrame>((ref) {
  final engine = ref.watch(strumEngineProvider);
  engine.start();
  ref.onDispose(engine.stop);
  return engine.frames;
});
