import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/songs/public.dart';

import '../../domain/models/practice_plan_block.dart';
import '../../domain/models/practice_plan_draft.dart';
import '../../domain/models/skill_node.dart';
import '../../domain/services/practice_plan_validator.dart';

final class PracticePlanTargetInput {
  const PracticePlanTargetInput({
    required this.definition,
    required this.config,
  });

  final PracticeDefinition definition;
  final PracticeSessionConfig config;
}

final class PracticePlanCompilationContext {
  PracticePlanCompilationContext({
    required List<Song> songs,
    required Map<String, PracticePlanTargetInput> practiceTargets,
    required Set<String> userAvoidList,
    required List<String> activeTuning,
    required Set<PracticePlanCapability> capabilities,
    required Set<SkillId> availableSkillIds,
  }) : songs = List<Song>.unmodifiable(songs),
       practiceTargets = Map<String, PracticePlanTargetInput>.unmodifiable(
         practiceTargets,
       ),
       validationContext = PracticePlanValidationContext(
         songIds: songs.map((song) => song.id).toSet(),
         practiceTargetIds: practiceTargets.keys.toSet(),
         userAvoidList: userAvoidList,
         activeTuning: activeTuning,
         capabilities: capabilities,
         availableSkillIds: availableSkillIds,
       );

  final List<Song> songs;
  final Map<String, PracticePlanTargetInput> practiceTargets;
  final PracticePlanValidationContext validationContext;

  Song? songById(String id) {
    for (final song in songs) {
      if (song.id == id) return song;
    }
    return null;
  }
}

final class CompiledPracticePlan {
  CompiledPracticePlan({
    required this.draftId,
    required List<CompiledPracticePlanBlock> blocks,
    required this.isOfflineRunnable,
  }) : blocks = List<CompiledPracticePlanBlock>.unmodifiable(blocks);

  final String draftId;
  final List<CompiledPracticePlanBlock> blocks;
  final bool isOfflineRunnable;
}

final class CompiledPracticePlanBlock {
  const CompiledPracticePlanBlock({
    required this.id,
    required this.type,
    required this.duration,
    required this.definition,
    required this.config,
    required this.compiledTarget,
  });

  final String id;
  final String type;
  final Duration duration;
  final PracticeDefinition? definition;
  final PracticeSessionConfig? config;
  final CompiledPracticeTarget? compiledTarget;
}

final class PracticePlanCompiler {
  const PracticePlanCompiler({this._validator = const PracticePlanValidator()});

  final PracticePlanValidator _validator;

  AppResult<CompiledPracticePlan> compile({
    required PracticePlanDraft draft,
    required PracticePlanCompilationContext context,
  }) {
    final validation = _validator.validate(
      draft,
      context: context.validationContext,
    );
    if (!validation.isValid) {
      return AppResult<CompiledPracticePlan>.failure(
        ValidationFailure(cause: validation),
      );
    }

    final compiledBlocks = <CompiledPracticePlanBlock>[];
    for (final block in draft.blocks) {
      final compilation = _compileBlock(block, context: context);
      switch (compilation) {
        case Success<CompiledPracticePlanBlock>(:final value):
          compiledBlocks.add(value);
        case Failure<CompiledPracticePlanBlock>(:final error):
          return AppResult<CompiledPracticePlan>.failure(error);
      }
    }
    return AppResult<CompiledPracticePlan>.success(
      CompiledPracticePlan(
        draftId: draft.id,
        blocks: compiledBlocks,
        isOfflineRunnable: draft.blocks.every(
          (block) => block.assetAvailableLocally,
        ),
      ),
    );
  }

  AppResult<CompiledPracticePlanBlock> _compileBlock(
    PracticePlanBlock block, {
    required PracticePlanCompilationContext context,
  }) {
    switch (block.adapter) {
      case PracticePlanBlockAdapter.none:
        return AppResult<CompiledPracticePlanBlock>.success(
          CompiledPracticePlanBlock(
            id: block.id,
            type: block.type,
            duration: block.duration,
            definition: null,
            config: null,
            compiledTarget: null,
          ),
        );
      case PracticePlanBlockAdapter.practiceTarget:
        final target = context.practiceTargets[block.practiceTargetId!]!;
        return _compileTargetBlock(
          block,
          definition: target.definition,
          config: target.config,
        );
      case PracticePlanBlockAdapter.song:
        final song = context.songById(block.songId!);
        final definition = _definitionForSong(song!, block);
        final config = _configForSong(definition, block);
        return _compileTargetBlock(
          block,
          definition: definition,
          config: config,
        );
    }
  }

  AppResult<CompiledPracticePlanBlock> _compileTargetBlock(
    PracticePlanBlock block, {
    required PracticeDefinition definition,
    required PracticeSessionConfig config,
  }) {
    final compilation = compilePracticeTarget(
      definition: definition,
      config: config,
    );
    return switch (compilation) {
      Success<CompiledPracticeTarget>(:final value) =>
        AppResult<CompiledPracticePlanBlock>.success(
          CompiledPracticePlanBlock(
            id: block.id,
            type: block.type,
            duration: block.duration,
            definition: definition,
            config: config,
            compiledTarget: value,
          ),
        ),
      Failure<CompiledPracticeTarget>(:final error) =>
        AppResult<CompiledPracticePlanBlock>.failure(error),
    };
  }

  PracticeDefinition _definitionForSong(Song song, PracticePlanBlock block) {
    final events = <PracticeEvent>[];
    final slotsPerBar = song.beatsPerBar * 2;
    for (var bar = 0; bar < song.chords.length; bar++) {
      final barStartTicks = bar * song.beatsPerBar * BeatPosition.ticksPerBeat;
      final firstDirection = _directionAt(song, 0);
      events.add(
        PracticeEvent(
          id: 'song.${song.id}.bar.$bar.chord',
          position: BeatPosition.fromTicks(barStartTicks),
          chord: song.chords[bar],
          direction: firstDirection,
        ),
      );
      for (var slot = 1; slot < slotsPerBar; slot++) {
        final direction = _directionAt(song, slot);
        if (direction == null) continue;
        events.add(
          PracticeEvent(
            id: 'song.${song.id}.bar.$bar.slot.$slot',
            position: BeatPosition.fromTicks(
              barStartTicks + slot * (BeatPosition.ticksPerBeat ~/ 2),
            ),
            direction: direction,
          ),
        );
      }
    }
    final hasDirection = events.any((event) => event.direction != null);
    final mode = hasDirection
        ? PracticeMode.chordProgression
        : PracticeMode.chordChanges;
    final scoringProfile = hasDirection
        ? ScoringProfile.chordProgressionDefault
        : ScoringProfile.chordChangeDefault;
    return PracticeDefinition(
      id: 'practicePlan.song.${song.id}.${block.id}',
      schemaVersion: 1,
      titleKey: 'practicePlan.song.title',
      descriptionKey: 'practicePlan.song.description',
      mode: mode,
      source: PracticeSource.song,
      meter: Meter(beatsPerBar: song.beatsPerBar),
      defaultTempo: Tempo(song.bpm.toDouble()),
      totalBeats: BeatPosition.quarters(song.chords.length * song.beatsPerBar),
      events: events,
      scoringProfile: scoringProfile,
      skillTags: const <String>['song.practicePlan'],
      sourceReference: 'song:${song.id}',
      displayTitle: song.name.trim().isEmpty ? null : song.name,
    );
  }

  StrumDirection? _directionAt(Song song, int slot) =>
      slot < song.pattern.length ? song.pattern[slot] : null;

  PracticeSessionConfig _configForSong(
    PracticeDefinition definition,
    PracticePlanBlock block,
  ) => PracticeSessionConfig(
    definitionId: definition.id,
    definitionSnapshotVersion: definition.schemaVersion,
    effectiveTempo: definition.defaultTempo,
    countInBars: 1,
    loopCount: 1,
    metronomeEnabled: true,
    accentEnabled: true,
    backingEnabled: false,
    scoringProfileId: definition.scoringProfile.id,
    inputLatency: Duration.zero,
    visualLatency: Duration.zero,
    expectedChordHintEnabled: true,
    sessionTimeout: block.duration,
    reducedMotion: false,
  );
}
