import '../analysis_event.dart';

/// The evidence type expected at one point in an [AnalysisTarget] snapshot.
enum ExpectedEventType { onset, strum, chordChange, beat, noteOnset }

/// One immutable expected event on a target timeline.
final class ExpectedEvent {
  ExpectedEvent({
    required this.id,
    required this.time,
    required this.type,
    this.direction,
  }) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (time.isNegative) throw ArgumentError.value(time, 'time');
    if (direction != null && type != ExpectedEventType.strum) {
      throw ArgumentError.value(
        direction,
        'direction',
        'is only valid for strum events',
      );
    }
  }

  final String id;
  final Duration time;
  final ExpectedEventType type;
  final StrumDirection? direction;
}
