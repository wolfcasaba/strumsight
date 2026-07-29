import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/lifecycle/audio_session_lease.dart';
import '../../settings/providers/tuning_reference_provider.dart';
import '../engine/real_tuner_engine.dart';
import '../engine/tuner_engine.dart';
import '../model/tuner_reading.dart';

/// The active tuner engine — the REAL microphone+YIN engine.
/// (MockTunerEngine remains test infrastructure; tests override this.)
final tunerEngineProvider = Provider<TunerEngine>((ref) {
  final engine = RealTunerEngine(mic: createMicCapture(ref, AudioOwner.tuner));
  ref.onDispose(engine.dispose);
  return engine;
});

/// Live tuner readings; runs the engine only while the Tuner screen is open.
final tunerReadingProvider = StreamProvider.autoDispose<TunerReading>((ref) {
  final engine = ref.watch(tunerEngineProvider);
  // Watching A4 restarts the engine (with the new reference) when it changes.
  final a4 = ref.watch(tuningReferenceProvider);
  engine.start(a4: a4);
  ref.onDispose(engine.stop);
  return engine.readings;
});
