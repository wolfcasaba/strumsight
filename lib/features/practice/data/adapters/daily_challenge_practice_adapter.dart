import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
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
import 'package:strumsight/features/streak/public.dart';

/// Converts a [DailyChallenge] into a one-bar strum-pattern
/// [PracticeDefinition]. The first [PracticeAdapterKeys.dailyChallengeMaxSlots]
/// pattern entries are mapped onto eighth-note slots; the rest are dropped
/// (matches [Lessons.fromDailyChallenge]).
///
/// The adapter is pure: it never reads the wall clock. The day-based ID is
/// stable per epoch day, but it is the caller's job to pass [challenge] — the
/// adapter does not call [DailyChallenge.forDay] itself.
AppResult<PracticeDefinition> practiceDefinitionFromDailyChallenge(
  DailyChallenge challenge, {
  double bpm = 80,
}) {
  if (challenge.pattern.isEmpty) {
    return _unsupportedFailure('dailyChallenge.pattern is empty');
  }
  if (!bpm.isFinite || bpm < Tempo.minimumBpm || bpm > Tempo.maximumBpm) {
    return _unsupportedFailure('dailyChallenge bpm ($bpm) out of Tempo range');
  }

  final id =
      '${PracticeAdapterKeys.dailyChallengeIdPrefix}${challenge.day}'
      '${PracticeAdapterKeys.dailyChallengeVersionSuffix}';
  final slotCount =
      challenge.pattern.length < PracticeAdapterKeys.dailyChallengeMaxSlots
      ? challenge.pattern.length
      : PracticeAdapterKeys.dailyChallengeMaxSlots;

  final events = <PracticeEvent>[
    for (var i = 0; i < slotCount; i++)
      PracticeEvent(
        id: '$id.e$i',
        position: BeatPosition.eighths(i),
        direction: challenge.pattern[i],
      ),
  ];

  final def = PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: PracticeAdapterKeys.dailyChallengeTitleKey,
    descriptionKey: PracticeAdapterKeys.dailyChallengeDescriptionKey,
    mode: PracticeMode.strumPattern,
    source: PracticeSource.dailyChallenge,
    meter: Meter(beatsPerBar: PracticeAdapterKeys.dailyChallengeBeatsPerBar),
    defaultTempo: Tempo(bpm),
    totalBeats: BeatPosition.quarters(
      PracticeAdapterKeys.dailyChallengeBeatsPerBar,
    ),
    events: List<PracticeEvent>.unmodifiable(events),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: PracticeAdapterKeys.dailyChallengeSkillTags,
    sourceReference:
        '${PracticeAdapterKeys.dailyChallengeSourcePrefix}${challenge.day}',
    difficulty: PracticeDifficulty.beginner,
    displayTitle: _displayTitle(challenge.name),
  );
  final failures = def.validate();
  if (failures.isNotEmpty) {
    return _unsupportedFailure(
      'dailyChallenge $id failed PracticeDefinition validation: '
      '${failures.map((f) => f.code).join(', ')}',
    );
  }
  return AppResult.success(def);
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
