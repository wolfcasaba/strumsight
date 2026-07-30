import 'package:meta/meta.dart';

import '../../../../core/music/strum.dart';
import 'beat_position.dart';
import 'practice_validation.dart';

const Set<String> _canonicalPracticeChordLabels = {
  'C',
  'Cm',
  'C#',
  'C#m',
  'D',
  'Dm',
  'D#',
  'D#m',
  'E',
  'Em',
  'F',
  'Fm',
  'F#',
  'F#m',
  'G',
  'Gm',
  'G#',
  'G#m',
  'A',
  'Am',
  'A#',
  'A#m',
  'B',
  'Bm',
};

/// Whether [label] is absent or a canonical sharp-spelled major/minor chord.
bool isCanonicalPracticeChordLabel(String? label) =>
    label == null || _canonicalPracticeChordLabels.contains(label);

/// One exact target or non-scored marker on a practice timeline.
@immutable
final class PracticeEvent {
  const PracticeEvent({
    required this.id,
    required this.position,
    this.duration,
    this.chord,
    this.direction,
    this.accent = false,
    this.optional = false,
    this.marker = false,
  });

  final String id;
  final BeatPosition position;

  /// Optional strictly-positive musical duration.
  final BeatPosition? duration;

  final String? chord;
  final StrumDirection? direction;
  final bool accent;
  final bool optional;

  /// A non-scored timeline marker, which cannot carry chord or direction.
  final bool marker;

  /// Returns every independent validation problem for this event.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (id.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventIdEmpty,
          message: 'Practice event ID cannot be empty.',
        ),
      );
    }
    if (!isCanonicalPracticeChordLabel(chord)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventChordInvalid,
          message: 'Chord must be a canonical major/minor label or null.',
        ),
      );
    }
    if (duration != null && duration!.ticks <= 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventDurationNonPositive,
          message: 'Event duration must be strictly positive.',
        ),
      );
    }
    final hasScoredAttribute = chord != null || direction != null;
    if (!marker && !hasScoredAttribute) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventScorableMissing,
          message: 'A non-marker event needs a chord or direction target.',
        ),
      );
    }
    if (marker && hasScoredAttribute) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventMarkerScorable,
          message: 'A marker event cannot carry scored attributes.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeEvent &&
          other.id == id &&
          other.position == position &&
          other.duration == duration &&
          other.chord == chord &&
          other.direction == direction &&
          other.accent == accent &&
          other.optional == optional &&
          other.marker == marker;

  @override
  int get hashCode => Object.hash(
    id,
    position,
    duration,
    chord,
    direction,
    accent,
    optional,
    marker,
  );
}
