import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';

import '../../domain/models/meter_map.dart' as song_meter;
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event_reference.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart' as song_time;
import '../../domain/models/trainer_config.dart';
import '../../domain/models/trainer_range.dart';
import '../../domain/services/song_time_map.dart';

/// A compiled scored session, or a transport-only playback session.
final class SongPracticeCompilation {
  const SongPracticeCompilation._({
    required this.definition,
    required this.practiceConfig,
    required this.eventReferences,
  });

  const SongPracticeCompilation.playbackOnly()
    : definition = null,
      practiceConfig = null,
      eventReferences = const <String, SongEventReference>{};

  final PracticeDefinition? definition;
  final PracticeSessionConfig? practiceConfig;
  final Map<String, SongEventReference> eventReferences;

  bool get isPlaybackOnly => definition == null;
}

/// Deterministic Song Trainer → Practice public-contract adapter.
///
/// Song coordinates remain in the Song Trainer domain; this application-layer
/// adapter imports only the Practice feature's public barrel. It does not
/// construct matchers or scorers and never mutates the input document.
abstract final class SongPracticeCompiler {
  static const int _practiceSchemaVersion = 1;
  static const String _titleKey = 'songTrainerCompiledPracticeTitle';
  static const String _descriptionKey =
      'songTrainerCompiledPracticeDescription';

  static SongPracticeCompilation compile({
    required SongDocument document,
    required TrainerConfig config,
  }) {
    _validateIdentity(document, config);
    if (config.mode == TrainerMode.pitch) {
      return const SongPracticeCompilation.playbackOnly();
    }

    final track = _findTrack(document.tracks, config.trackId);
    if (track is BackingAudioTrack ||
        track is! ChordTrack && track is! StrumTrack && track is! NoteTrack) {
      return const SongPracticeCompilation.playbackOnly();
    }

    final range = config.range.resolve(
      measureCount: document.measures.length,
      sections: document.sections,
    );
    if (range == null) {
      throw ArgumentError.value(
        config.range,
        'config.range',
        'Range is stale.',
      );
    }
    final timeline = _SongTimeline(document: document, range: range);
    final candidates = _candidatesFor(track: track, document: document);
    final inRange =
        candidates
            .where((candidate) => timeline.contains(candidate.at))
            .toList()
          ..sort((a, b) {
            final byTime = a.at.compareTo(b.at);
            return byTime != 0
                ? byTime
                : a.eventId.value.compareTo(b.eventId.value);
          });
    if (inRange.isEmpty) {
      return const SongPracticeCompilation.playbackOnly();
    }

    final profile = _profileFor(inRange);
    final events = <PracticeEvent>[];
    final references = <String, SongEventReference>{};
    final positions = <int>{};
    for (final candidate in inRange) {
      final localPosition = timeline.localPositionFor(candidate.at);
      if (!positions.add(localPosition.ticks)) {
        throw ArgumentError(
          'Distinct song events collapse to practice tick ${localPosition.ticks}.',
        );
      }
      final practiceId = _practiceEventId(
        document,
        track.id,
        candidate.eventId,
      );
      events.add(
        PracticeEvent(
          id: practiceId,
          position: localPosition,
          chord: candidate.chord,
          direction: candidate.direction,
        ),
      );
      references[practiceId] = SongEventReference(
        songId: document.id,
        songRevision: document.revision,
        trackId: track.id,
        eventId: candidate.eventId,
        measureIndex: timeline.measureIndexFor(candidate.at),
        sectionId: _sectionAt(
          document.sections,
          timeline.measureIndexFor(candidate.at),
        ),
      );
    }

    final definition = PracticeDefinition(
      id: _definitionId(document, track.id, range, config.mode),
      schemaVersion: _practiceSchemaVersion,
      titleKey: _titleKey,
      descriptionKey: _descriptionKey,
      mode: profile.mode,
      source: PracticeSource.song,
      meter: timeline.practiceMeter,
      defaultTempo: timeline.referenceTempo,
      totalBeats: timeline.totalBeats,
      events: List<PracticeEvent>.unmodifiable(events),
      scoringProfile: profile.scoringProfile,
      skillTags: const <String>['songTrainer'],
      sourceReference:
          'song:${document.id.value}:revision:${document.revision}',
      displayTitle: document.metadata.title,
    );
    final problems = definition.validate();
    if (problems.isNotEmpty) {
      throw ArgumentError('Compiled practice definition is invalid: $problems');
    }
    return SongPracticeCompilation._(
      definition: definition,
      practiceConfig: _practiceConfig(definition, config),
      eventReferences: Map<String, SongEventReference>.unmodifiable(references),
    );
  }

  static void _validateIdentity(SongDocument document, TrainerConfig config) {
    if (document.id != config.songId ||
        document.revision != config.songRevision) {
      throw ArgumentError(
        'Trainer config does not match the document revision.',
      );
    }
  }

  static SongTrack _findTrack(List<SongTrack> tracks, SongTrackId id) {
    for (final track in tracks) {
      if (track.id == id) return track;
    }
    throw ArgumentError.value(
      id,
      'config.trackId',
      'Track is not in the document.',
    );
  }

  static List<_Candidate> _candidatesFor({
    required SongTrack track,
    required SongDocument document,
  }) {
    final songTimeMap = SongTimeMap.fromTempoMap(document.tempoMap);
    Duration normalized(Duration at) =>
        songTimeMap.timeAt(songTimeMap.positionAt(at));
    switch (track) {
      case ChordTrack(:final events):
        return [
          for (final event in events)
            if (isCanonicalPracticeChordLabel(event.symbol.label))
              _Candidate(
                eventId: event.id,
                at: normalized(event.start),
                chord: event.symbol.label,
                direction: null,
                rhythmPlaceholder: false,
              ),
        ];
      case StrumTrack(:final events):
        final chords = _canonicalChordsById(document.tracks);
        return [
          for (final event in events)
            if (event.direction != null || chords[event.targetChordId] != null)
              _Candidate(
                eventId: event.id,
                at: normalized(event.at),
                chord: chords[event.targetChordId],
                direction: event.direction,
                rhythmPlaceholder: false,
              ),
        ];
      case NoteTrack(:final events):
        return [
          for (final event in events)
            _Candidate(
              eventId: event.id,
              at: normalized(event.start),
              chord: null,
              direction: StrumDirection.down,
              rhythmPlaceholder: true,
            ),
        ];
      default:
        return const <_Candidate>[];
    }
  }

  static Map<SongEventId, String> _canonicalChordsById(List<SongTrack> tracks) {
    final result = <SongEventId, String>{};
    for (final track in tracks.whereType<ChordTrack>()) {
      for (final event in track.events) {
        final label = event.symbol.label;
        if (isCanonicalPracticeChordLabel(label)) {
          result[event.id] = label;
        }
      }
    }
    return result;
  }

  static _Profile _profileFor(List<_Candidate> candidates) {
    final hasChord = candidates.any((candidate) => candidate.chord != null);
    final hasDirection = candidates.any(
      (candidate) => candidate.direction != null,
    );
    if (hasChord && hasDirection) {
      return const _Profile(
        mode: PracticeMode.chordProgression,
        scoringProfile: ScoringProfile.chordProgressionDefault,
      );
    }
    if (hasChord) {
      return const _Profile(
        mode: PracticeMode.chordChanges,
        scoringProfile: ScoringProfile.chordChangeDefault,
      );
    }
    if (hasDirection &&
        candidates.every((candidate) => candidate.rhythmPlaceholder)) {
      return const _Profile(
        mode: PracticeMode.rhythmOnly,
        scoringProfile: ScoringProfile.rhythmOnlyDefault,
      );
    }
    return const _Profile(
      mode: PracticeMode.strumPattern,
      scoringProfile: ScoringProfile.legacyLearnParity,
    );
  }

  static PracticeSessionConfig _practiceConfig(
    PracticeDefinition definition,
    TrainerConfig config,
  ) {
    final repeatCount = config.loopConfig.maxRepeats ?? 1;
    return PracticeSessionConfig(
      definitionId: definition.id,
      definitionSnapshotVersion: definition.schemaVersion,
      effectiveTempo: Tempo(definition.defaultTempo.bpm * config.targetSpeed),
      countInBars: config.countInBars,
      loopCount: repeatCount,
      metronomeEnabled: config.metronomeEnabled,
      accentEnabled: config.metronomeEnabled,
      backingEnabled: false,
      scoringProfileId: definition.scoringProfile.id,
      inputLatency: Duration.zero,
      visualLatency: Duration.zero,
      expectedChordHintEnabled: true,
      sessionTimeout: const Duration(minutes: 30),
      reducedMotion: false,
    );
  }

  static SongSectionId? _sectionAt(List<SongSection> sections, int measure) {
    for (final section in sections) {
      if (measure >= section.startMeasure &&
          measure < section.endMeasureExclusive) {
        return section.id;
      }
    }
    return null;
  }

  static String _definitionId(
    SongDocument document,
    SongTrackId trackId,
    MeasureRange range,
    TrainerMode mode,
  ) =>
      'song.${document.id.value}.r${document.revision}.${trackId.value}.${mode.name}.m${range.start}-${range.endExclusive}';

  static String _practiceEventId(
    SongDocument document,
    SongTrackId trackId,
    SongEventId eventId,
  ) =>
      'song.${document.id.value}.r${document.revision}.${trackId.value}.${eventId.value}';
}

final class _Candidate {
  const _Candidate({
    required this.eventId,
    required this.at,
    required this.chord,
    required this.direction,
    required this.rhythmPlaceholder,
  });

  final SongEventId eventId;
  final Duration at;
  final String? chord;
  final StrumDirection? direction;
  final bool rhythmPlaceholder;
}

final class _Profile {
  const _Profile({required this.mode, required this.scoringProfile});

  final PracticeMode mode;
  final ScoringProfile scoringProfile;
}

final class _MeasureSpan {
  const _MeasureSpan({
    required this.index,
    required this.start,
    required this.end,
  });

  final int index;
  final song_time.BeatPosition start;
  final song_time.BeatPosition end;
}

final class _SongTimeline {
  _SongTimeline({required SongDocument document, required MeasureRange range})
    : _timeMap = SongTimeMap.fromTempoMap(document.tempoMap),
      _spans = _measureSpans(document.measures) {
    final startSpan = _spanFor(range.start);
    final endSpan = _spanFor(range.endExclusive - 1);
    _rangeStartBeat = startSpan.start;
    _rangeEndBeat = endSpan.end;
    _rangeStartTime = _timeMap.timeAt(_rangeStartBeat);
    _rangeEndTime = _timeMap.timeAt(_rangeEndBeat);
    final sourceTempo = _tempoAt(document.tempoMap, _rangeStartBeat);
    referenceTempo = Tempo(sourceTempo.bpm.toDouble());
    final sourceMeter = _meterAt(document.meterMap, range.start);
    practiceMeter = Meter(
      beatsPerBar: sourceMeter.numerator,
      beatUnit: sourceMeter.denominator,
    );
    totalBeats = _toPracticeTicks(_rangeEndTime - _rangeStartTime);
  }

  final SongTimeMap _timeMap;
  final List<_MeasureSpan> _spans;
  late final song_time.BeatPosition _rangeStartBeat;
  late final song_time.BeatPosition _rangeEndBeat;
  late final Duration _rangeStartTime;
  late final Duration _rangeEndTime;
  late final Tempo referenceTempo;
  late final Meter practiceMeter;
  late final BeatPosition totalBeats;

  bool contains(Duration time) =>
      time >= _rangeStartTime && time < _rangeEndTime;

  BeatPosition localPositionFor(Duration time) =>
      _toPracticeTicks(time - _rangeStartTime);

  int measureIndexFor(Duration time) {
    final position = _timeMap.positionAt(time);
    for (final span in _spans) {
      if (position >= span.start && position < span.end) return span.index;
    }
    throw ArgumentError.value(time, 'time', 'Event is outside song measures.');
  }

  BeatPosition _toPracticeTicks(Duration duration) {
    final ticks =
        (duration.inMicroseconds *
                referenceTempo.bpm *
                BeatPosition.ticksPerBeat /
                Duration.microsecondsPerMinute)
            .round();
    return BeatPosition.fromTicks(ticks);
  }

  _MeasureSpan _spanFor(int index) {
    for (final span in _spans) {
      if (span.index == index) return span;
    }
    throw ArgumentError.value(
      index,
      'range',
      'Measure is not in the document.',
    );
  }

  static List<_MeasureSpan> _measureSpans(List<SongMeasure> measures) {
    final ordered = measures.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    var cursor = song_time.BeatPosition.zero;
    return List<_MeasureSpan>.unmodifiable([
      for (final measure in ordered)
        _MeasureSpan(
          index: measure.index,
          start: cursor,
          end: cursor = cursor + measure.durationBeats,
        ),
    ]);
  }

  static song_time.Tempo _tempoAt(
    song_time.TempoMap map,
    song_time.BeatPosition position,
  ) {
    var result = map.changes.first.bpm;
    for (final change in map.changes) {
      if (change.at > position) break;
      result = change.bpm;
    }
    return result;
  }

  static song_meter.Meter _meterAt(song_meter.MeterMap map, int measure) {
    var result = map.changes.first.meter;
    for (final change in map.changes) {
      if (change.atMeasure > measure) break;
      result = change.meter;
    }
    return result;
  }
}
