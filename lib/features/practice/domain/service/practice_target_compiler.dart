import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../model/beat_position.dart';
import '../model/beat_time_converter.dart';
import '../model/compiled_practice_target.dart';
import '../model/practice_definition.dart';
import '../model/practice_event.dart';
import '../model/practice_session_config.dart';
import '../model/practice_validation.dart';

/// Constants shared by practice-target compilation consumers.
abstract final class PracticeTargetCompiler {
  /// Legacy `learn_screen.dart` `_activeChord()` lookahead: 0.25 quarter beat.
  static const BeatPosition expectedChordLookahead = BeatPosition(120);
}

/// Compiles authored musical content into one deterministic session timeline.
AppResult<CompiledPracticeTarget> compilePracticeTarget({
  required PracticeDefinition definition,
  required PracticeSessionConfig config,
  PracticeLoopRange? loopRange,
}) {
  final definitionFailures = definition.validate();
  if (definitionFailures.isNotEmpty) {
    return _compilationFailure(
      PracticeValidationCode.targetDefinitionInvalid,
      'Definition validation failed: '
      '${definitionFailures.map((failure) => failure.code).join(', ')}',
    );
  }

  final configFailures = config.validate();
  if (configFailures.isNotEmpty) {
    return _compilationFailure(
      PracticeValidationCode.targetConfigInvalid,
      'Session config validation failed: '
      '${configFailures.map((failure) => failure.code).join(', ')}',
    );
  }

  if (config.definitionId != definition.id) {
    return _compilationFailure(
      PracticeValidationCode.targetDefinitionMismatch,
      'Config definition ID does not match the definition.',
    );
  }

  if (config.easyVariationId != null &&
      config.easyVariationId != definition.id) {
    return _compilationFailure(
      PracticeValidationCode.targetVariationMismatch,
      'Easy variation ID does not match the compiled definition.',
    );
  }

  final ticksPerBar = definition.meter.ticksPerBar;
  final definitionBars =
      (definition.totalBeats.ticks + ticksPerBar - 1) ~/ ticksPerBar;
  if (loopRange != null &&
      (loopRange.startBar < 0 ||
          loopRange.endBarExclusive <= loopRange.startBar ||
          loopRange.endBarExclusive > definitionBars)) {
    return _compilationFailure(
      PracticeValidationCode.targetLoopRangeInvalid,
      'Loop range must select complete bars inside the definition.',
    );
  }

  final converter = BeatTimeConverter(
    tempo: config.effectiveTempo,
    meter: definition.meter,
  );
  final countInTicks = config.countInBars * ticksPerBar;
  final countInDuration = converter.timeOfTicks(countInTicks);
  final sourceStartTicks = loopRange == null
      ? 0
      : loopRange.startBar * ticksPerBar;
  final sourceEndTicks = loopRange == null
      ? definition.totalBeats.ticks
      : loopRange.endBarExclusive * ticksPerBar;
  final passTicks = loopRange == null
      ? definitionBars * ticksPerBar
      : (loopRange.endBarExclusive - loopRange.startBar) * ticksPerBar;
  final sourceEvents = definition.events
      .where(
        (event) =>
            !event.marker &&
            event.position.ticks >= sourceStartTicks &&
            event.position.ticks < sourceEndTicks,
      )
      .toList(growable: false);

  final compiledEvents = <CompiledTargetEvent>[];
  for (var loopIndex = 0; loopIndex < config.loopCount; loopIndex++) {
    final loopOffsetTicks = loopIndex * passTicks;
    for (final sourceEvent in sourceEvents) {
      final passLocalTicks = sourceEvent.position.ticks - sourceStartTicks;
      final absoluteTicks = loopOffsetTicks + passLocalTicks;
      compiledEvents.add(
        _compileEvent(
          sourceEvent: sourceEvent,
          loopIndex: loopIndex,
          absoluteTicks: absoluteTicks,
          countInTicks: countInTicks,
          ticksPerBar: ticksPerBar,
          converter: converter,
        ),
      );
    }
  }
  _ensureNondecreasingEventTimes(compiledEvents);

  final musicalTicks = passTicks * config.loopCount;
  final musicalDuration = converter.timeOfTicks(musicalTicks);
  final ringOutDuration = converter.barDuration;
  final totalDuration = countInDuration + musicalDuration + ringOutDuration;
  final musicalBars = musicalTicks ~/ ticksPerBar;

  final target = CompiledPracticeTarget(
    definitionId: definition.id,
    definitionSnapshotVersion: config.definitionSnapshotVersion,
    tempo: config.effectiveTempo,
    meter: definition.meter,
    countInBars: config.countInBars,
    countInDuration: countInDuration,
    events: compiledEvents,
    musicalDuration: musicalDuration,
    ringOutDuration: ringOutDuration,
    totalDuration: totalDuration,
    barBoundaries: _barBoundaries(
      converter: converter,
      countInBars: config.countInBars,
      musicalBars: musicalBars,
      ticksPerBar: ticksPerBar,
      countInDuration: countInDuration,
    ),
    loopCount: config.loopCount,
    loopRange: loopRange,
    expectedChordSegments: _expectedChordSegments(
      events: compiledEvents,
      converter: converter,
      countInTicks: countInTicks,
      totalDuration: totalDuration,
    ),
    scoringApplicable:
        definition.mode.scoredDimensions.isNotEmpty &&
        compiledEvents.isNotEmpty,
  );
  return AppResult<CompiledPracticeTarget>.success(target);
}

CompiledTargetEvent _compileEvent({
  required PracticeEvent sourceEvent,
  required int loopIndex,
  required int absoluteTicks,
  required int countInTicks,
  required int ticksPerBar,
  required BeatTimeConverter converter,
}) => CompiledTargetEvent(
  sourceEventId: sourceEvent.id,
  loopIndex: loopIndex,
  position: BeatPosition.fromTicks(absoluteTicks),
  time: converter.timeOfTicks(countInTicks + absoluteTicks),
  barIndex: absoluteTicks ~/ ticksPerBar,
  chord: sourceEvent.chord,
  direction: sourceEvent.direction,
  accent: sourceEvent.accent,
  optional: sourceEvent.optional,
);

List<Duration> _barBoundaries({
  required BeatTimeConverter converter,
  required int countInBars,
  required int musicalBars,
  required int ticksPerBar,
  required Duration countInDuration,
}) => List<Duration>.unmodifiable([
  for (var bar = 0; bar <= countInBars; bar++)
    converter.timeOfTicks(bar * ticksPerBar),
  for (var bar = 1; bar <= musicalBars; bar++)
    countInDuration + converter.timeOfTicks(bar * ticksPerBar),
]);

void _ensureNondecreasingEventTimes(List<CompiledTargetEvent> events) {
  for (var index = 1; index < events.length; index++) {
    if (events[index].time < events[index - 1].time) {
      throw StateError('Compiled target event times must be nondecreasing.');
    }
  }
}

List<ExpectedChordSegment> _expectedChordSegments({
  required List<CompiledTargetEvent> events,
  required BeatTimeConverter converter,
  required int countInTicks,
  required Duration totalDuration,
}) {
  final chordEvents = events
      .where((event) => event.chord != null)
      .toList(growable: false);
  if (chordEvents.isEmpty) return const [];

  final segments = <ExpectedChordSegment>[];
  var currentChord = chordEvents.first.chord!;
  var currentStart = Duration.zero;

  for (final event in chordEvents.skip(1)) {
    final nextChord = event.chord!;
    if (nextChord == currentChord) continue;

    final rawSwitchTicks =
        countInTicks +
        event.position.ticks -
        PracticeTargetCompiler.expectedChordLookahead.ticks;
    final switchTime = converter.timeOfTicks(
      rawSwitchTicks < 0 ? 0 : rawSwitchTicks,
    );
    if (switchTime <= currentStart) {
      currentChord = nextChord;
      continue;
    }

    segments.add(
      ExpectedChordSegment(
        chord: currentChord,
        start: currentStart,
        end: switchTime,
      ),
    );
    currentChord = nextChord;
    currentStart = switchTime;
  }

  segments.add(
    ExpectedChordSegment(
      chord: currentChord,
      start: currentStart,
      end: totalDuration,
    ),
  );
  return List<ExpectedChordSegment>.unmodifiable(segments);
}

AppResult<CompiledPracticeTarget> _compilationFailure(
  String validationCode,
  String diagnostic,
) => AppResult<CompiledPracticeTarget>.failure(
  ValidationFailure(
    code: FailureCode.practiceTargetUncompilable,
    cause: PracticeValidationFailure(
      code: validationCode,
      message: '$validationCode: $diagnostic',
    ),
  ),
);
