import '../model/tuner_reading.dart';

/// Source of chromatic tuner readings. v1 ships a mock; the real pitch detector
/// (YIN/autocorrelation in the C++ core) lands behind this same interface.
abstract class TunerEngine {
  Stream<TunerReading> get readings;
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
