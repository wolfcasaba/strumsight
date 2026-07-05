import 'package:flutter/foundation.dart';

/// A single tuner reading: the nearest note, how many cents sharp/flat it is,
/// and the measured frequency.
@immutable
class TunerReading {
  const TunerReading({
    required this.note,
    required this.cents,
    required this.frequencyHz,
  });

  /// Nearest note name ("E", "A", …); empty when there is no signal.
  final String note;

  /// Offset from the target pitch, −50..+50 cents (negative = flat).
  final double cents;

  /// Measured frequency in Hz.
  final double frequencyHz;

  bool get hasSignal => note.isNotEmpty;

  /// Within ±5 cents is considered in tune.
  bool get inTune => hasSignal && cents.abs() <= 5;

  static const silent = TunerReading(note: '', cents: 0, frequencyHz: 0);
}
