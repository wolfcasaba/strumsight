import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/practice/data/adapters/legacy_chord_label.dart';
import 'package:strumsight/features/practice/data/adapters/practice_adapter_keys.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

/// Converts a legacy [Lesson] into a v2 [PracticeDefinition].
///
/// The conversion is event-level identical to [Lesson.events] — positions,
/// directions and chord labels round-trip exactly. The legacy chord
/// vocabulary is reduced to the canonical 24-label set via
/// [legacyPracticeChordLabel], which is documented as a lossy-but-safe step
/// in ADR 0071 §2.
///
/// [easy] selects the simplified on-beat-downstroke cut of the lesson. The
/// Easy variant always receives its own definition ID (`.easy.v1`) even when
/// [Lesson.simplified] returns the original lesson unchanged.
AppResult<PracticeDefinition> practiceDefinitionFromLesson(
  Lesson lesson, {
  bool easy = false,
}) {
  final source = easy ? lesson.simplified : lesson;

  if (!lesson.bpm.isFinite) {
    return _unsupportedFailure('lesson.bpm is not finite');
  }
  if (!lesson.totalBeats.isFinite || lesson.totalBeats <= 0) {
    return _unsupportedFailure('lesson.totalBeats is not positive');
  }
  if (source.events.isEmpty) {
    return _unsupportedFailure('lesson.events is empty');
  }
  for (final event in source.events) {
    if (!event.beat.isFinite || event.beat < 0) {
      return _unsupportedFailure('lesson event beat is not finite');
    }
  }

  final id = easy
      ? '${PracticeAdapterKeys.lessonIdPrefix}${lesson.id}'
            '${PracticeAdapterKeys.lessonEasySuffix}'
      : '${PracticeAdapterKeys.lessonIdPrefix}${lesson.id}'
            '${PracticeAdapterKeys.lessonVersionSuffix}';

  final events = <PracticeEvent>[
    for (var index = 0; index < source.events.length; index++)
      PracticeEvent(
        id: '$id.e$index',
        position: BeatPosition.fromLegacyBeats(source.events[index].beat),
        direction: source.events[index].direction,
        chord: legacyPracticeChordLabel(source.events[index].chord),
      ),
  ];

  final definition = PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: PracticeAdapterKeys.lessonTitleKey,
    descriptionKey: PracticeAdapterKeys.lessonDescriptionKey,
    mode: PracticeMode.strumPattern,
    source: PracticeSource.lesson,
    meter: Meter(beatsPerBar: source.beatsPerBar),
    defaultTempo: Tempo(source.bpm),
    totalBeats: BeatPosition.fromLegacyBeats(source.totalBeats),
    events: List<PracticeEvent>.unmodifiable(events),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: easy
        ? PracticeAdapterKeys.lessonEasySkillTags
        : PracticeAdapterKeys.lessonSkillTags,
    sourceReference: '${PracticeAdapterKeys.lessonSourcePrefix}${lesson.id}',
    difficulty: switch (source.difficulty) {
      Difficulty.beginner => PracticeDifficulty.beginner,
      Difficulty.intermediate => PracticeDifficulty.intermediate,
      Difficulty.advanced => PracticeDifficulty.advanced,
    },
    displayTitle: _displayTitle(source.name),
  );

  final failures = definition.validate();
  if (failures.isNotEmpty) {
    return _unsupportedFailure(
      'lesson $id failed PracticeDefinition validation: '
      '${failures.map((f) => f.code).join(', ')}',
    );
  }
  return AppResult.success(definition);
}

AppResult<PracticeDefinition> _unsupportedFailure(String diagnostic) =>
    AppResult<PracticeDefinition>.failure(
      ValidationFailure(
        code: FailureCode.practiceContentUnsupported,
        cause: diagnostic,
      ),
    );

String? _displayTitle(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}
