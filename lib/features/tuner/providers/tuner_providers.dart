import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/real_tuner_engine.dart';
import '../engine/tuner_engine.dart';
import '../model/tuner_reading.dart';

/// The active tuner engine — the REAL microphone+YIN engine.
/// (MockTunerEngine remains test infrastructure; tests override this.)
final tunerEngineProvider = Provider<TunerEngine>((ref) {
  final engine = RealTunerEngine();
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
