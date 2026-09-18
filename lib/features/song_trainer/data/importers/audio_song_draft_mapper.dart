/// Audio analysis → DRAFT [SongDocument] mapping (K3).
///
/// The clip analyzer answers a different question than a notation importer
/// does: it returns a measured, statistical timeline (chord segments in
/// seconds, strum marks with a direction and a confidence, an estimated
/// tempo), not an authored score. This mapper is the single place that turns
/// that timeline into a document the Song Trainer can open — and the single
/// place that refuses to.
///
/// Three refusals are deliberate, because each of them would otherwise ship a
/// song that LOOKS finished and is not:
///
///   * a non-positive clip length is not a song (`invalidDuration`);
///   * an analysis whose chord timeline is empty produces NO document at all
///     (`noChords`) — a zero-event "song" is the exact silent failure this
///     round exists to prevent;
///   * a strum whose direction confidence is below
///     [AudioSongDraftMapper.minStrumConfidence] is dropped rather than
///     written down as a ↓ or ↑ the detector never actually decided.
///
/// The produced document is always marked [SongSourceType.audioAnalysis] and
/// always carries [AudioSongDraftWarningCode.reviewRequired] in its
/// provenance, so every consumer can tell a derived draft from an authored
/// song without re-running the analysis.
///
/// Out of scope for this round (and therefore NOT faked here): real beat
/// tracking, tempo changes and section detection. The document gets one
/// constant tempo, a 4/4 metre and exactly one section.
library;

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/music/chord.dart';
import '../../../../core/music/strum.dart';
import '../../../analyze/public.dart'
    show AnalyzeResult, TimelineChord, TimelineStrum;
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';

/// Stable failure codes emitted by [AudioSongDraftMapper].
abstract final class AudioSongDraftFailureCode {
  /// The clip length is zero, negative or not a number.
  static const String invalidDuration = 'audioDraft.invalidDuration';

  /// The analysis found no usable chord segment. No document is produced —
  /// an empty song is a failure with a name, never a success.
  static const String noChords = 'audioDraft.noChords';
}

/// Stable, code-shaped warnings recorded on the draft's provenance
/// ([SongSource.warningSummary]). The UI localises them by code.
abstract final class AudioSongDraftWarningCode {
  /// ALWAYS present: the document is a machine-derived draft.
  static const String reviewRequired = 'audioDraft.reviewRequired';

  /// The analysis declared no usable tempo; the fallback BPM was used.
  static const String tempoFallback = 'audioDraft.tempo.fallback';

  /// The estimated tempo fell outside the practicable range and was clamped.
  static const String tempoClamped = 'audioDraft.tempo.clamped';

  /// At least one strum was dropped because its direction was uncertain.
  static const String strumDirectionUncertain =
      'audioDraft.strum.uncertainDropped';

  /// At least two adjacent segments carried the same chord and were merged.
  static const String chordsMerged = 'audioDraft.chord.merged';
}

/// The mapping result: the draft document plus what the mapper had to decide.
final class AudioSongDraft {
  AudioSongDraft({
    required this.document,
    required this.bpm,
    required this.tempoEstimated,
    required List<String> warnings,
  }) : warnings = List<String>.unmodifiable(warnings);

  /// The draft song. Never carries zero events.
  final SongDocument document;

  /// The constant tempo written into the document (40–240).
  final int bpm;

  /// False when [bpm] is the fallback because the analysis had none — the
  /// flag the UI needs in order to call the tempo a guess honestly.
  final bool tempoEstimated;

  /// Code-shaped warnings, also persisted on `document.source`.
  final List<String> warnings;
}

/// Maps an [AnalyzeResult] onto a draft [SongDocument] (K3/A1).
final class AudioSongDraftMapper {
  const AudioSongDraftMapper({
    this.minStrumConfidence = defaultMinStrumConfidence,
    this.fallbackBpm = fallbackTempoBpm,
  });

  /// Practicable tempo window. Below 40 the grid stops being a beat, and
  /// above 240 the quantiser puts every chord on its own beat.
  static const int minTempoBpm = 40;
  static const int maxTempoBpm = 240;

  /// Used when the analysis declares no tempo at all.
  static const int fallbackTempoBpm = 100;

  /// Direction is a two-class decision, so anything below a coin flip
  /// carries no information: such a strum is dropped, never guessed.
  static const double defaultMinStrumConfidence = 0.5;

  /// Fixed metre for this round — metre detection is out of scope.
  static const int beatsPerBar = 4;

  /// Stable importer identity persisted on the document's provenance.
  static const String importerVersion = 'audioAnalysis@1';

  /// Title used when the file name carries no usable stem.
  static const String fallbackTitle = 'Audio import';

  final double minStrumConfidence;
  final int fallbackBpm;

  /// Builds the draft, or names the reason there is none.
  ///
  /// [duration] is the DECODED clip length; every event is clipped to it, so
  /// a detector that reported past the end cannot inflate the grid.
  /// [sha256] is the hash of the ORIGINAL compressed bytes, shared with the
  /// backing asset so provenance and playback point at the same file.
  AppResult<AudioSongDraft> map({
    required AnalyzeResult analysis,
    required Duration duration,
    required String fileName,
    required SongId songId,
    required String sha256,
    required DateTime importedAt,
  }) {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    if (!seconds.isFinite || seconds <= 0) {
      return const Failure<AudioSongDraft>(
        ValidationFailure(code: AudioSongDraftFailureCode.invalidDuration),
      );
    }

    final warnings = <String>[AudioSongDraftWarningCode.reviewRequired];
    final tempo = _resolveTempo(analysis.bpm, warnings);
    final beatSeconds = 60 / tempo.bpm;

    final merged = _mergeAdjacent(analysis.chords, seconds, warnings);
    if (merged.isEmpty) {
      return const Failure<AudioSongDraft>(
        ValidationFailure(code: AudioSongDraftFailureCode.noChords),
      );
    }
    final quantised = _quantise(merged, beatSeconds);
    if (quantised.isEmpty) {
      return const Failure<AudioSongDraft>(
        ValidationFailure(code: AudioSongDraftFailureCode.noChords),
      );
    }

    final strokes = _strums(analysis.strums, seconds, warnings);
    final title = _titleFrom(fileName);

    var totalBeats = (seconds / beatSeconds).ceil();
    if (quantised.last.endBeat > totalBeats) {
      totalBeats = quantised.last.endBeat;
    }
    if (strokes.isNotEmpty) {
      final lastStrumBeat = (strokes.last.timeSec / beatSeconds).ceil();
      if (lastStrumBeat > totalBeats) totalBeats = lastStrumBeat;
    }
    if (totalBeats < beatsPerBar) totalBeats = beatsPerBar;
    final measureCount = (totalBeats + beatsPerBar - 1) ~/ beatsPerBar;

    final chordEvents = <SongChordEvent>[];
    for (var index = 0; index < quantised.length; index++) {
      final segment = quantised[index];
      final start = _beatDuration(segment.startBeat, tempo.bpm);
      final end = _beatDuration(segment.endBeat, tempo.bpm);
      final event = SongChordEvent(
        id: SongEventId('chord-${index + 1}'),
        start: start,
        duration: end - start,
        symbol: Chord(segment.label),
      );
      chordEvents.add(event);
    }

    final strumEvents = <SongStrumEvent>[];
    for (var index = 0; index < strokes.length; index++) {
      final stroke = strokes[index];
      final event = SongStrumEvent(
        id: SongEventId('strum-${index + 1}'),
        at: _secondsDuration(stroke.timeSec),
        // Never null: an undecided strum was dropped above rather than
        // written down as a direction the detector never picked.
        direction: stroke.direction,
      );
      strumEvents.add(event);
    }

    final measures = <SongMeasure>[];
    for (var index = 0; index < measureCount; index++) {
      final measure = SongMeasure(
        index: index,
        durationBeats: BeatPosition.fromBeats(beatsPerBar),
      );
      measures.add(measure);
    }

    final tracks = <SongTrack>[
      ChordTrack(
        id: SongTrackId('chords'),
        name: 'Chords',
        instrument: SongInstrument(name: 'Guitar'),
        events: chordEvents,
      ),
    ];
    if (strumEvents.isNotEmpty) {
      final strumTrack = StrumTrack(
        id: SongTrackId('strums'),
        name: 'Strums',
        instrument: SongInstrument(name: 'Guitar'),
        events: strumEvents,
      );
      tracks.add(strumTrack);
    }

    final section = SongSection(
      id: SongSectionId('section-1'),
      name: title,
      startMeasure: 0,
      endMeasureExclusive: measureCount,
    );

    final document = SongDocument(
      schemaVersion: songDocumentSchemaVersion,
      id: songId,
      revision: 0,
      metadata: SongMetadata(
        title: title,
        tags: const <String>['audio-import', 'draft'],
      ),
      source: SongSource(
        type: SongSourceType.audioAnalysis,
        originalFileName: fileName,
        sha256: sha256,
        importedAt: importedAt,
        importerVersion: importerVersion,
        warningSummary: warnings,
      ),
      createdAt: importedAt,
      updatedAt: importedAt,
      sections: <SongSection>[section],
      measures: measures,
      tempoMap: TempoMap.constant(Tempo(tempo.bpm)),
      meterMap: MeterMap.constant(Meter(beatsPerBar, 4)),
      tracks: tracks,
    );

    final draft = AudioSongDraft(
      document: document,
      bpm: tempo.bpm,
      tempoEstimated: tempo.estimated,
      warnings: warnings,
    );
    return Success<AudioSongDraft>(draft);
  }

  _Tempo _resolveTempo(double raw, List<String> warnings) {
    if (!raw.isFinite || raw <= 0) {
      warnings.add(AudioSongDraftWarningCode.tempoFallback);
      return _Tempo(bpm: fallbackBpm, estimated: false);
    }
    final rounded = raw.round();
    var clamped = rounded;
    if (clamped < minTempoBpm) clamped = minTempoBpm;
    if (clamped > maxTempoBpm) clamped = maxTempoBpm;
    if (clamped != rounded) {
      warnings.add(AudioSongDraftWarningCode.tempoClamped);
    }
    return _Tempo(bpm: clamped, estimated: true);
  }

  /// Sanitises the timeline and merges consecutive identical labels.
  ///
  /// Sorting first is not cosmetic: the mapper must survive a timeline that
  /// arrives out of order (the property cell feeds exactly that), and the
  /// merge below only ever sees neighbours.
  List<_ChordSegment> _mergeAdjacent(
    List<TimelineChord> chords,
    double clipSeconds,
    List<String> warnings,
  ) {
    final sane = <TimelineChord>[];
    for (final chord in chords) {
      if (_isUsableChord(chord, clipSeconds)) sane.add(chord);
    }
    sane.sort(_byChordStart);

    final merged = <_ChordSegment>[];
    var didMerge = false;
    for (final chord in sane) {
      final label = chord.label.trim();
      final end = chord.endSec > clipSeconds ? clipSeconds : chord.endSec;
      if (merged.isNotEmpty && merged.last.label == label) {
        didMerge = true;
        if (end > merged.last.endSec) merged.last.endSec = end;
        continue;
      }
      final segment = _ChordSegment(
        label: label,
        startSec: chord.startSec,
        endSec: end,
      );
      merged.add(segment);
    }
    if (didMerge) warnings.add(AudioSongDraftWarningCode.chordsMerged);
    return merged;
  }

  static int _byChordStart(TimelineChord a, TimelineChord b) {
    final byStart = a.startSec.compareTo(b.startSec);
    if (byStart != 0) return byStart;
    return a.endSec.compareTo(b.endSec);
  }

  static bool _isUsableChord(TimelineChord chord, double clipSeconds) {
    if (chord.label.trim().isEmpty) return false;
    if (!chord.startSec.isFinite || !chord.endSec.isFinite) return false;
    if (chord.startSec < 0 || chord.startSec >= clipSeconds) return false;
    return chord.endSec > chord.startSec;
  }

  /// Snaps every segment onto the beat grid of the estimated tempo.
  ///
  /// The running `cursor` is what keeps the progression's ORDER intact: two
  /// segments that round onto the same beat become consecutive one-beat
  /// chords instead of a zero-length event the model would reject.
  List<_Quantised> _quantise(List<_ChordSegment> segments, double beat) {
    final result = <_Quantised>[];
    var cursor = 0;
    for (final segment in segments) {
      var startBeat = (segment.startSec / beat).round();
      if (startBeat < cursor) startBeat = cursor;
      var endBeat = (segment.endSec / beat).round();
      if (endBeat <= startBeat) endBeat = startBeat + 1;
      final beats = _Quantised(
        label: segment.label,
        startBeat: startBeat,
        endBeat: endBeat,
      );
      result.add(beats);
      cursor = endBeat;
    }
    return result;
  }

  /// Keeps the strums whose direction the detector actually decided.
  List<_Stroke> _strums(
    List<TimelineStrum> strums,
    double clipSeconds,
    List<String> warnings,
  ) {
    final sorted = <TimelineStrum>[];
    sorted.addAll(strums);
    sorted.sort(_byStrumTime);
    final kept = <_Stroke>[];
    var dropped = false;
    for (final strum in sorted) {
      if (!strum.timeSec.isFinite ||
          strum.timeSec < 0 ||
          strum.timeSec > clipSeconds) {
        dropped = true;
        continue;
      }
      final confidence = strum.confidence;
      if (!confidence.isFinite || confidence < minStrumConfidence) {
        dropped = true;
        continue;
      }
      kept.add(_Stroke(timeSec: strum.timeSec, direction: strum.direction));
    }
    if (dropped) {
      warnings.add(AudioSongDraftWarningCode.strumDirectionUncertain);
    }
    return kept;
  }

  static int _byStrumTime(TimelineStrum a, TimelineStrum b) =>
      a.timeSec.compareTo(b.timeSec);

  static String _titleFrom(String fileName) {
    final separator = fileName.lastIndexOf(RegExp(r'[/\\]'));
    final base = separator < 0 ? fileName : fileName.substring(separator + 1);
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    final trimmed = stem.trim();
    if (trimmed.isEmpty) return fallbackTitle;
    const limit = SongMetadata.maxTitleLength;
    if (trimmed.length <= limit) return trimmed;
    return trimmed.substring(0, limit);
  }

  static Duration _beatDuration(int beats, int bpm) => Duration(
    microseconds: (beats * 60 * Duration.microsecondsPerSecond / bpm).round(),
  );

  static Duration _secondsDuration(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}

final class _Tempo {
  const _Tempo({required this.bpm, required this.estimated});

  final int bpm;
  final bool estimated;
}

final class _ChordSegment {
  _ChordSegment({
    required this.label,
    required this.startSec,
    required this.endSec,
  });

  final String label;
  final double startSec;
  double endSec;
}

final class _Stroke {
  const _Stroke({required this.timeSec, required this.direction});

  final double timeSec;
  final StrumDirection direction;
}

final class _Quantised {
  const _Quantised({
    required this.label,
    required this.startBeat,
    required this.endBeat,
  });

  final String label;
  final int startBeat;
  final int endBeat;
}
