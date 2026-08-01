import '../../../core/foundation/app_result.dart';
import '../../practice/public.dart';
import '../model/lesson.dart';

/// Compiles one legacy Learn lesson to the V2 target timeline used for scoring.
CompiledPracticeTarget compileLessonPracticeTarget(
  Lesson lesson, {
  double? bpm,
  Duration inputLatency = Duration.zero,
}) {
  final definition = PracticeDefinition(
    id: 'learn.${lesson.id}.v2',
    schemaVersion: 1,
    titleKey: 'practiceSourceLessonTitle',
    descriptionKey: 'practiceSourceLessonDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.lesson,
    meter: Meter(beatsPerBar: lesson.beatsPerBar),
    defaultTempo: Tempo(bpm ?? lesson.bpm),
    totalBeats: BeatPosition.fromLegacyBeats(lesson.totalBeats),
    events: List<PracticeEvent>.unmodifiable([
      for (var index = 0; index < lesson.events.length; index++)
        PracticeEvent(
          id: 'learn.${lesson.id}.v2.e$index',
          position: BeatPosition.fromLegacyBeats(lesson.events[index].beat),
          direction: lesson.events[index].direction,
        ),
    ]),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['learnMigration'],
    sourceReference: 'learn:${lesson.id}',
  );
  final config = PracticeSessionConfig(
    definitionId: definition.id,
    definitionSnapshotVersion: definition.schemaVersion,
    effectiveTempo: definition.defaultTempo,
    countInBars: 1,
    loopCount: 1,
    metronomeEnabled: true,
    accentEnabled: true,
    backingEnabled: false,
    scoringProfileId: definition.scoringProfile.id,
    inputLatency: inputLatency,
    visualLatency: Duration.zero,
    expectedChordHintEnabled: true,
    sessionTimeout: const Duration(minutes: 10),
    reducedMotion: false,
  );
  final result = compilePracticeTarget(definition: definition, config: config);
  return switch (result) {
    Success(:final value) => value,
    Failure(:final error) => throw StateError(
      'Cannot compile Learn lesson ${lesson.id}: ${error.code}',
    ),
  };
}
