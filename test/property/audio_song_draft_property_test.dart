// K3/A5 — randomized property cell for the audio → draft mapper.
//
// The generator feeds the mapper what a real detector actually produces on a
// bad day: silence (no chords at all), noise (garbage labels, out-of-order
// and out-of-range times, NaN / infinite tempo), and clips too short to carry
// a bar. The invariant is deliberately narrow and absolute:
//
//   for every input, the mapper returns a VALID document or a NAMED failure —
//   it never throws, and it never reports success with zero events.
//
// Reads PROPERTY_SEED (absent → 42, the deterministic dev loop); CI runs an
// extra HARD step with a randomized seed.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/song_trainer/data/importers/audio_song_draft_mapper.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/services/song_validator.dart';

const int _trials = 300;

const Set<String> _namedFailures = <String>{
  AudioSongDraftFailureCode.noChords,
  AudioSongDraftFailureCode.invalidDuration,
};

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('a noisy analysis yields a valid draft or a named failure', () {
    const mapper = AudioSongDraftMapper();
    const validator = SongValidator();
    var successes = 0;

    for (var trial = 0; trial < _trials; trial++) {
      final rng = math.Random(seed + trial * 7919);
      final duration = _duration(rng);
      final analysis = _analysis(rng, duration);
      final where = 'seed=$seed trial=$trial';

      late final AppResult<AudioSongDraft> result;
      try {
        result = mapper.map(
          analysis: analysis,
          duration: duration,
          fileName: _fileName(rng),
          songId: SongId('audio-prop-$trial'),
          sha256: 'd' * 64,
          importedAt: DateTime.utc(2026, 9, 17),
        );
      } catch (error) {
        fail('$where: the mapper threw $error');
      }

      switch (result) {
        case Success<AudioSongDraft>(:final value):
          successes += 1;
          _assertHonestDraft(value, validator, where);
        case Failure<AudioSongDraft>(:final error):
          expect(_namedFailures, contains(error.code), reason: where);
      }
    }

    // Percentage-based, so the cell is not flaky: the generator is built so
    // that clearly usable analyses are a large minority. Zero successes would
    // mean the mapper (or the generator) degenerated into always-refusing.
    expect(
      successes,
      greaterThan(_trials ~/ 10),
      reason: 'seed=$seed produced $successes usable drafts out of $_trials',
    );
  });
}

void _assertHonestDraft(
  AudioSongDraft draft,
  SongValidator validator,
  String where,
) {
  final document = draft.document;
  expect(_eventCount(document), greaterThan(0), reason: '$where: 0-event song');
  expect(document.source.type, SongSourceType.audioAnalysis, reason: where);
  expect(
    draft.warnings,
    contains(AudioSongDraftWarningCode.reviewRequired),
    reason: where,
  );
  expect(draft.bpm, greaterThanOrEqualTo(40), reason: where);
  expect(draft.bpm, lessThanOrEqualTo(240), reason: where);
  expect(document.measures, isNotEmpty, reason: where);
  expect(document.sections, hasLength(1), reason: where);
  expect(
    document.sections.single.endMeasureExclusive,
    lessThanOrEqualTo(document.measures.length),
    reason: where,
  );
  expect(
    validator.validate(document).hasFatalIssue,
    isFalse,
    reason: '$where: ${validator.validate(document).issues}',
  );

  var cursor = Duration.zero;
  for (final event in _chords(document)) {
    expect(event.start >= cursor, isTrue, reason: '$where: chords overlap');
    expect(event.duration > Duration.zero, isTrue, reason: where);
    cursor = event.start + event.duration;
  }
  for (final event in _strums(document)) {
    expect(event.direction, isNotNull, reason: '$where: guessed direction');
    expect(event.at >= Duration.zero, isTrue, reason: where);
  }
}

List<SongChordEvent> _chords(SongDocument document) {
  final events = <SongChordEvent>[];
  for (final track in document.tracks) {
    if (track is ChordTrack) events.addAll(track.events);
  }
  return events;
}

List<SongStrumEvent> _strums(SongDocument document) {
  final events = <SongStrumEvent>[];
  for (final track in document.tracks) {
    if (track is StrumTrack) events.addAll(track.events);
  }
  return events;
}

int _eventCount(SongDocument document) =>
    _chords(document).length + _strums(document).length;

Duration _duration(math.Random rng) {
  return switch (rng.nextInt(4)) {
    // A clip too short to carry a bar — sometimes literally zero.
    0 => Duration(milliseconds: rng.nextInt(200)),
    // A plausible song.
    1 || 2 => Duration(milliseconds: 4000 + rng.nextInt(240000)),
    // The 10-minute ceiling.
    _ => const Duration(minutes: 10),
  };
}

AnalyzeResult _analysis(math.Random rng, Duration duration) {
  final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  final mode = rng.nextInt(4);
  final bpm = _bpm(rng, mode);
  if (mode == 0) {
    // Silence: the detector found nothing at all.
    return AnalyzeResult(
      durationSec: seconds,
      bpm: bpm,
      chords: const <TimelineChord>[],
      strums: const <TimelineStrum>[],
    );
  }
  final chords = <TimelineChord>[];
  final strums = <TimelineStrum>[];
  final count = rng.nextInt(24);
  for (var index = 0; index < count; index++) {
    chords.add(_chord(rng, mode, seconds));
    strums.add(_strum(rng, mode, seconds));
  }
  return AnalyzeResult(
    durationSec: seconds,
    bpm: bpm,
    chords: chords,
    strums: strums,
  );
}

double _bpm(math.Random rng, int mode) {
  if (mode == 1) {
    return switch (rng.nextInt(4)) {
      0 => double.nan,
      1 => double.infinity,
      2 => -rng.nextDouble() * 200,
      _ => rng.nextDouble() * 4000,
    };
  }
  return 60 + rng.nextDouble() * 140;
}

const List<String> _labels = <String>['G', 'C', 'D', 'Am', 'F#m', 'H7', ''];

TimelineChord _chord(math.Random rng, int mode, double seconds) {
  final label = _labels[rng.nextInt(_labels.length)];
  if (mode == 1) {
    // Noise: out of order, out of range, occasionally inverted.
    final start = (rng.nextDouble() * 2 - 0.5) * (seconds + 5);
    final end = start + (rng.nextDouble() * 2 - 0.5) * 6;
    return TimelineChord(label: label, startSec: start, endSec: end);
  }
  final start = rng.nextDouble() * seconds;
  final end = start + rng.nextDouble() * 4;
  return TimelineChord(label: label, startSec: start, endSec: end);
}

TimelineStrum _strum(math.Random rng, int mode, double seconds) {
  final direction = rng.nextBool() ? StrumDirection.down : StrumDirection.up;
  if (mode == 1) {
    return TimelineStrum(
      direction: direction,
      timeSec: (rng.nextDouble() * 2 - 0.5) * (seconds + 5),
      confidence: rng.nextDouble() * 2 - 0.5,
    );
  }
  return TimelineStrum(
    direction: direction,
    timeSec: rng.nextDouble() * seconds,
    confidence: rng.nextDouble(),
  );
}

String _fileName(math.Random rng) {
  return switch (rng.nextInt(4)) {
    0 => 'clip.mp3',
    1 => '/storage/emulated/0/Music/My Song.m4a',
    2 => '.mp3',
    _ => 'a' * 400,
  };
}
