import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/public.dart';
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

/// Converts an [AnalyzeResult] (recorded clip or synthetic song timeline) into
/// a v2 [PracticeDefinition].
///
/// The legacy [Lessons.fromAnalyze] builder uses `result.bpm > 0 ? result.bpm :
/// 90.0` as a fallback; this adapter tightens that to the documented Tempo
/// range (30..300 BPM) so the resulting [Tempo] never fails validation. This
/// is a deliberate, documented departure from the legacy semantics — see ADR
/// 0071 §5.
///
/// [sourceId] is the persisted identifier of the source clip (used in the
/// definition ID and sourceReference). [title] is the user-facing title shown
/// in the UI when [displayTitle] is non-null.
AppResult<PracticeDefinition> practiceDefinitionFromAnalyze(
  AnalyzeResult result, {
  required String sourceId,
  required String title,
}) {
  final trimmedId = sourceId.trim();
  if (trimmedId.isEmpty) {
    return _unsupportedFailure('analyze.sourceId is blank');
  }
  if (result.beatsPerBar < Meter.minimumBeatsPerBar ||
      result.beatsPerBar > Meter.maximumBeatsPerBar) {
    return _unsupportedFailure(
      'analyze.beatsPerBar (${result.beatsPerBar}) is outside the Meter range',
    );
  }

  // BPM fallback narrowed to the Tempo range. The legacy `> 0` check is
  // intentionally wider; we tighten it so the resulting Tempo validates.
  final bpm =
      (result.bpm.isFinite &&
          result.bpm >= PracticeAdapterKeys.analyzeMinimumBpm &&
          result.bpm <= PracticeAdapterKeys.analyzeMaximumBpm)
      ? result.bpm
      : PracticeAdapterKeys.analyzeFallbackBpm;
  final secPerBeat = 60.0 / bpm;

  // Drop strums with non-finite time, then sort by time.
  final strums = <TimelineStrum>[
    for (final s in result.strums)
      if (s.timeSec.isFinite) s,
  ]..sort((a, b) => a.timeSec.compareTo(b.timeSec));

  if (strums.isEmpty) {
    return _buildEmpty(result: result, sourceId: trimmedId, title: title);
  }

  final t0 = strums.first.timeSec;
  final bpb = result.beatsPerBar;

  // Compute the working tick window: include the last event plus enough bar
  // padding so the exclusive `totalBeats` bound never rejects it.
  var lastBeat = (strums.last.timeSec - t0) / secPerBeat;
  if (!lastBeat.isFinite || lastBeat < 0) lastBeat = 0;
  final initialBars = (lastBeat / bpb).floor() + 1;
  var bars = initialBars < 1 ? 1 : initialBars;
  var totalBeatsTicks = bars * bpb * BeatPosition.ticksPerBeat;

  final events = <PracticeEvent>[];
  final id =
      '${PracticeAdapterKeys.analyzeIdPrefix}$trimmedId'
      '${PracticeAdapterKeys.analyzeVersionSuffix}';
  var lastIssuedTick = -1;

  for (final s in strums) {
    var beat = (s.timeSec - t0) / secPerBeat;
    if (!beat.isFinite || beat < 0) beat = 0;
    var tick = BeatPosition.fromLegacyBeats(beat).ticks;
    if (lastIssuedTick >= 0 && tick <= lastIssuedTick) {
      tick = lastIssuedTick + 1;
    }
    if (tick >= totalBeatsTicks) {
      // Grow the timeline by one bar so the exclusive bound accepts us.
      totalBeatsTicks += bpb * BeatPosition.ticksPerBeat;
    }
    lastIssuedTick = tick;
    events.add(
      PracticeEvent(
        id: '$id.e${events.length}',
        position: BeatPosition.fromTicks(tick),
        direction: s.direction,
        chord: legacyPracticeChordLabel(_chordAt(result.chords, s.timeSec)),
      ),
    );
  }

  return _buildDefinition(
    id: id,
    sourceId: trimmedId,
    title: title,
    bpm: bpm,
    meter: Meter(beatsPerBar: bpb),
    totalBeats: BeatPosition.fromTicks(totalBeatsTicks),
    events: events,
    mode: PracticeMode.strumPattern,
    scoringProfile: ScoringProfile.legacyLearnParity,
    difficulty: PracticeDifficulty.intermediate,
    source: PracticeSource.analyze,
    titleKey: PracticeAdapterKeys.analyzeTitleKey,
    descriptionKey: PracticeAdapterKeys.analyzeDescriptionKey,
    sourcePrefix: PracticeAdapterKeys.analyzeSourcePrefix,
    skillTags: PracticeAdapterKeys.analyzeSkillTags,
  );
}

AppResult<PracticeDefinition> _buildEmpty({
  required AnalyzeResult result,
  required String sourceId,
  required String title,
}) {
  final bpb = result.beatsPerBar;
  final id =
      '${PracticeAdapterKeys.analyzeIdPrefix}$sourceId'
      '${PracticeAdapterKeys.analyzeVersionSuffix}';

  return _buildDefinition(
    id: id,
    sourceId: sourceId,
    title: title,
    bpm: PracticeAdapterKeys.analyzeFallbackBpm,
    meter: Meter(beatsPerBar: bpb),
    totalBeats: BeatPosition.quarters(bpb),
    events: const <PracticeEvent>[],
    mode: PracticeMode.freePractice,
    scoringProfile: ScoringProfile.freePracticeOpen,
    difficulty: PracticeDifficulty.intermediate,
    source: PracticeSource.analyze,
    titleKey: PracticeAdapterKeys.analyzeTitleKey,
    descriptionKey: PracticeAdapterKeys.analyzeDescriptionKey,
    sourcePrefix: PracticeAdapterKeys.analyzeSourcePrefix,
    skillTags: PracticeAdapterKeys.analyzeSkillTags,
  );
}

AppResult<PracticeDefinition> _buildDefinition({
  required String id,
  required String sourceId,
  required String title,
  required double bpm,
  required Meter meter,
  required BeatPosition totalBeats,
  required List<PracticeEvent> events,
  required PracticeMode mode,
  required ScoringProfile scoringProfile,
  required PracticeDifficulty difficulty,
  required PracticeSource source,
  required String titleKey,
  required String descriptionKey,
  required String sourcePrefix,
  required List<String> skillTags,
}) {
  final def = PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: titleKey,
    descriptionKey: descriptionKey,
    mode: mode,
    source: source,
    meter: meter,
    defaultTempo: Tempo(bpm),
    totalBeats: totalBeats,
    events: List<PracticeEvent>.unmodifiable(events),
    scoringProfile: scoringProfile,
    skillTags: skillTags,
    sourceReference: '$sourcePrefix$sourceId',
    difficulty: difficulty,
    displayTitle: _displayTitle(title),
  );
  final failures = def.validate();
  if (failures.isNotEmpty) {
    return _unsupportedFailure(
      'analyze $id failed PracticeDefinition validation: '
      '${failures.map((f) => f.code).join(', ')}',
    );
  }
  return AppResult.success(def);
}

String _chordAt(List<TimelineChord> chords, double t) {
  for (final c in chords) {
    if (t >= c.startSec && t < c.endSec) return c.label;
  }
  return '';
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
