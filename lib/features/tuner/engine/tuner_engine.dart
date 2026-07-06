import '../model/tuner_reading.dart';

/// Source of chromatic tuner readings. v1 ships a mock; the real pitch detector
/// (YIN/autocorrelation in the C++ core) lands behind this same interface.
abstract class TunerEngine {
  Stream<TunerReading> get readings;

  /// Start listening. [a4] is the concert-pitch reference in Hz (default 440),
  /// which shifts the note/cents mapping.
  Future<void> start({int a4 = 440});
  Future<void> stop();
  Future<void> dispose();
}
