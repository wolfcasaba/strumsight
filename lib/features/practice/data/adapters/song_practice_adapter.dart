import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
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
import 'package:strumsight/features/songs/public.dart';

/// Converts a user-authored [Song] into a v2 [PracticeDefinition] without
/// calling the legacy Song-to-lesson builder (ADR 0071 §7 — the legacy builder
/// asserts on the pattern-length contract, while this adapter must validate
/// it itself because the in-memory constructor does not enforce it).
AppResult<PracticeDefinition> practiceDefinitionFromSong(Song song) {
  if (song.chords.isEmpty) {
    return _unsupportedFailure('song.chords is empty');
  }
  final wantSlots = song.beatsPerBar * 2;
  if (song.pattern.length != wantSlots) {
    return _unsupportedFailure(
      'song.pattern.length (${song.pattern.length}) != '
      'beatsPerBar * 2 ($wantSlots)',
    );
  }
  if (song.beatsPerBar < Meter.minimumBeatsPerBar ||
      song.beatsPerBar > Meter.maximumBeatsPerBar) {
    return _unsupportedFailure(
      'song.beatsPerBar (${song.beatsPerBar}) is outside the Meter range',
    );
  }
  if (!song.bpm.isFinite ||
      song.bpm < Tempo.minimumBpm ||
      song.bpm > Tempo.maximumBpm) {
    return _unsupportedFailure('song.bpm (${song.bpm}) is out of Tempo range');
  }

  final id =
      '${PracticeAdapterKeys.songIdPrefix}${song.id}'
      '${PracticeAdapterKeys.songVersionSuffix}';

  final events = <PracticeEvent>[];
  var hasAny = false;
  for (var bar = 0; bar < song.chords.length; bar++) {
    for (var slot = 0; slot < song.pattern.length; slot++) {
      final dir = song.pattern[slot];
      if (dir == null) continue;
      hasAny = true;
      events.add(
        PracticeEvent(
          id: '$id.e${events.length}',
          position: BeatPosition.fromLegacyBeats(
            bar * song.beatsPerBar + slot * 0.5,
          ),
          direction: dir,
          chord: legacyPracticeChordLabel(song.chords[bar]),
        ),
      );
    }
  }
  if (!hasAny) {
    return _unsupportedFailure('song.pattern contains no non-null strum slots');
  }

  final definition = PracticeDefinition(
    id: id,
    schemaVersion: 1,
    titleKey: PracticeAdapterKeys.songTitleKey,
    descriptionKey: PracticeAdapterKeys.songDescriptionKey,
    mode: PracticeMode.strumPattern,
    source: PracticeSource.song,
    meter: Meter(beatsPerBar: song.beatsPerBar),
    defaultTempo: Tempo(song.bpm.toDouble()),
    totalBeats: BeatPosition.quarters(song.chords.length * song.beatsPerBar),
    events: List<PracticeEvent>.unmodifiable(events),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: PracticeAdapterKeys.songSkillTags,
    sourceReference: '${PracticeAdapterKeys.songSourcePrefix}${song.id}',
    difficulty: PracticeDifficulty.beginner,
    displayTitle: _displayTitle(song.name),
  );

  final failures = definition.validate();
  if (failures.isNotEmpty) {
    return _unsupportedFailure(
      'song $id failed PracticeDefinition validation: '
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
