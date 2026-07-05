import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/mock_tuner_engine.dart';
import '../engine/tuner_engine.dart';
import '../model/tuner_reading.dart';

/// The active tuner engine. v1 = mock; swap to the FFI pitch detector later.
final tunerEngineProvider = Provider<TunerEngine>((ref) {
  final engine = MockTunerEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Live tuner readings; runs the engine only while the Tuner screen is open.
final tunerReadingProvider = StreamProvider.autoDispose<TunerReading>((ref) {
  final engine = ref.watch(tunerEngineProvider);
  engine.start();
  ref.onDispose(engine.stop);
  return engine.readings;
});
