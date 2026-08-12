import 'package:meta/meta.dart';

/// One YIN-derived pitch observation for Audio Analysis V2.
///
/// An unvoiced frame carries no frequency or MIDI value. This keeps silence
/// and uncertain audio explicit instead of fabricating a zero-Hz pitch.
@immutable
final class PitchFrame {
  PitchFrame({
    required this.time,
    required this.confidence,
    this.frequencyHz,
    this.midiNote,
  }) {
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
    if (frequencyHz == null && midiNote != null) {
      throw ArgumentError('An unvoiced frame cannot have a MIDI note.');
    }
    if (frequencyHz != null &&
        (!frequencyHz!.isFinite || frequencyHz! <= 0 || frequencyHz! > 5000)) {
      throw ArgumentError.value(frequencyHz, 'frequencyHz');
    }
    if (midiNote != null && (midiNote! < 0 || midiNote! > 127)) {
      throw ArgumentError.value(midiNote, 'midiNote');
    }
  }

  final Duration time;
  final double confidence;
  final double? frequencyHz;
  final int? midiNote;

  bool get isVoiced => frequencyHz != null;
}
