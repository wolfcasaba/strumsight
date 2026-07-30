import 'package:meta/meta.dart';

import 'beat_position.dart';
import 'meter.dart';
import 'practice_difficulty.dart';
import 'practice_event.dart';
import 'practice_mode.dart';
import 'practice_source.dart';
import 'practice_validation.dart';
import 'practice_value_equality.dart';
import 'scoring_profile.dart';
import 'tempo.dart';

/// Immutable authored practice content, independent of one session's settings.
///
/// [events] and [skillTags] must be immutable; pass const lists or
/// unmodifiable lists. Event positions use an exclusive [totalBeats] bound.
@immutable
final class PracticeDefinition {
  const PracticeDefinition({
    required this.id,
    required this.schemaVersion,
    required this.titleKey,
    required this.descriptionKey,
    required this.mode,
    required this.source,
    required this.meter,
    required this.defaultTempo,
    required this.totalBeats,
    required this.events,
    required this.scoringProfile,
    required this.skillTags,
    this.sourceReference,
    this.difficulty = PracticeDifficulty.beginner,
    this.displayTitle,
  });

  final String id;
  final int schemaVersion;
  final String titleKey;
  final String descriptionKey;
  final PracticeMode mode;
  final PracticeSource source;
  final Meter meter;
  final Tempo defaultTempo;
  final BeatPosition totalBeats;

  /// Read-only events in nondecreasing timeline order.
  final List<PracticeEvent> events;

  final ScoringProfile scoringProfile;

  /// Read-only stable skill identifiers.
  final List<String> skillTags;

  final String? sourceReference;
  final PracticeDifficulty difficulty;

  /// Already-localized display text for adapted user content. The UI resolves
  /// `displayTitle ?? l10n(titleKey)`. `null` means the UI should localize by
  /// [titleKey]; a non-null value carries user-provided text that must NOT be
  /// re-localized. An empty/whitespace-only value is rejected by [validate].
  final String? displayTitle;

  /// Returns field, nested-value, and event-list validation problems.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (id.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.definitionIdEmpty,
          message: 'Practice definition ID cannot be empty.',
        ),
      );
    }
    if (schemaVersion <= 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.definitionSchemaVersionInvalid,
          message: 'Definition schema version must be positive.',
        ),
      );
    }
    if (titleKey.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.definitionTitleKeyEmpty,
          message: 'Definition title key cannot be empty.',
        ),
      );
    }
    if (descriptionKey.isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.definitionDescriptionKeyEmpty,
          message: 'Definition description key cannot be empty.',
        ),
      );
    }
    if (totalBeats.ticks <= 0) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.definitionTotalBeatsNonPositive,
          message: 'Definition total beats must be strictly positive.',
        ),
      );
    }
    if (displayTitle != null && displayTitle!.trim().isEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.definitionDisplayTitleBlank,
          message: 'Display title cannot be blank when present.',
        ),
      );
    }

    failures
      ..addAll(meter.validate())
      ..addAll(defaultTempo.validate())
      ..addAll(scoringProfile.validate());
    for (final event in events) {
      failures.addAll(event.validate());
    }

    if (events.isEmpty && mode.scoredDimensions.isNotEmpty) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventsEmpty,
          message: 'A scored practice definition needs at least one event.',
        ),
      );
    }

    if (_eventsAreUnsorted) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventsUnsorted,
          message: 'Events must be ordered by nondecreasing position.',
        ),
      );
    }
    if (_hasDuplicateEventIds) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventsIdDuplicate,
          message: 'Event IDs must be unique within a definition.',
        ),
      );
    }
    if (_hasDuplicateEventPositions) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventsPositionDuplicate,
          message: 'Only one event may occupy a timeline tick.',
        ),
      );
    }
    if (events.any((event) => event.position.ticks >= totalBeats.ticks)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.eventPositionOutOfRange,
          message: 'Event position must be before total beats.',
        ),
      );
    }
    if (!_profileMatchesMode) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode
              .definitionScoringProfileIncompatibleWithMode,
          message: 'Scoring profile dimensions must exactly match the mode.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  bool get _eventsAreUnsorted {
    for (var index = 1; index < events.length; index++) {
      if (events[index].position.compareTo(events[index - 1].position) < 0) {
        return true;
      }
    }
    return false;
  }

  bool get _hasDuplicateEventIds {
    final ids = <String>{};
    for (final event in events) {
      if (!ids.add(event.id)) return true;
    }
    return false;
  }

  bool get _hasDuplicateEventPositions {
    final positions = <int>{};
    for (final event in events) {
      if (!positions.add(event.position.ticks)) return true;
    }
    return false;
  }

  bool get _profileMatchesMode {
    final expected = mode.scoredDimensions;
    final actual = scoringProfile.weights.keys;
    return actual.length == expected.length && actual.every(expected.contains);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeDefinition &&
          other.id == id &&
          other.schemaVersion == schemaVersion &&
          other.titleKey == titleKey &&
          other.descriptionKey == descriptionKey &&
          other.mode == mode &&
          other.source == source &&
          other.meter == meter &&
          other.defaultTempo == defaultTempo &&
          other.totalBeats == totalBeats &&
          listEquals(other.events, events) &&
          other.scoringProfile == scoringProfile &&
          listEquals(other.skillTags, skillTags) &&
          other.sourceReference == sourceReference &&
          other.difficulty == difficulty &&
          other.displayTitle == displayTitle;

  @override
  int get hashCode => Object.hash(
    id,
    schemaVersion,
    titleKey,
    descriptionKey,
    mode,
    source,
    meter,
    defaultTempo,
    totalBeats,
    listHash(events),
    scoringProfile,
    listHash(skillTags),
    sourceReference,
    difficulty,
    displayTitle,
  );
}
