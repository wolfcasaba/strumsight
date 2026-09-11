// PROBE: what the engine hears in real guitar recordings.
//
//   REAL_AUDIO_DIR=/path/to/wavs flutter test \
//     test/tooling/real_audio_hearing_probe_test.dart
//
// Self-skipping without the variable, so CI is untouched. The recordings are NOT
// committed: they are third-party stock audio, and a licence that permits use
// does not permit redistribution inside a repository. Only the MEASUREMENT is
// ever written down.
//
// ## What can honestly be measured here, and what cannot
//
// Stock loops carry only the ground truth that is in their filename. Some state
// a TEMPO ("120-bpm"), which is real, checkable ground truth on real audio —
// the first this project has had for tempo outside its own corpus.
//
// Some state a KEY ("b-minor"). A key is NOT a chord: a sample in B minor plays
// a progression, so "did the decoder output Bm" is the wrong question. The right
// one is whether the chords it reports belong to that key — a decoder wandering
// outside the key on clean material would be suspect, while a decoder naming
// several in-key chords is behaving exactly as it should.
//
// And most of these are produced loops: layered guitars, effects, sometimes a
// full band. The app's target is one guitar into a phone microphone. So this
// probe REPORTS rather than grades: it is a window onto real-world behaviour,
// not a pass/fail gate, and the numbers it prints are the deliverable.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';

/// Chords that belong to a natural minor key, by tonic pitch class.
///
/// i, III, iv, v, VI, VII — plus the V that harmonic minor borrows, because
/// popular music uses it constantly.
const _pitchNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

Set<String> _minorKeyChords(int tonicPc) {
  String name(int pc) => _pitchNames[pc % 12];
  // Triads AND their diatonic sevenths. The first version of this set listed
  // triads only, which scored a decoder that correctly named `Gmaj7` and
  // `Dmaj7` in B minor as if it had wandered out of the key — the measurement
  // was wrong, not the engine.
  return {
    '${name(tonicPc)}m', '${name(tonicPc)}m7', // i
    '${name(tonicPc + 2)}dim', // ii°
    name(tonicPc + 3), '${name(tonicPc + 3)}maj7', // III
    '${name(tonicPc + 5)}m', '${name(tonicPc + 5)}m7', // iv
    '${name(tonicPc + 7)}m', '${name(tonicPc + 7)}m7', // v
    name(tonicPc + 7),
    '${name(tonicPc + 7)}7', // V, borrowed from harmonic minor
    name(tonicPc + 8), '${name(tonicPc + 8)}maj7', // VI
    name(tonicPc + 10), '${name(tonicPc + 10)}7', // VII
  };
}

int? _tonicFromName(String fileName) {
  final lower = fileName.toLowerCase();
  const roots = {
    'a-minor': 9,
    'a#-minor': 10,
    'b-minor': 11,
    'c-minor': 0,
    'c#-minor': 1,
    'd-minor': 2,
    'd#-minor': 3,
    'e-minor': 4,
    'f-minor': 5,
    'f#-minor': 6,
    'g-minor': 7,
    'g#-minor': 8,
  };
  for (final entry in roots.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return null;
}

String _histogram(Map<String, int> counts) {
  if (counts.isEmpty) return '(none)';
  final entries = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return entries.map((e) => '${e.key}:${e.value}').join(' ');
}

double? _labelledBpm(String fileName) {
  final match = RegExp(
    r'(\d{2,3})[-_ ]?bpm',
  ).firstMatch(fileName.toLowerCase());
  return match == null ? null : double.tryParse(match.group(1)!);
}

void main() {
  final dir = Platform.environment['REAL_AUDIO_DIR'];
  if (dir == null || dir.isEmpty) {
    test('skipped: REAL_AUDIO_DIR not set', () {
      // Nothing to measure without recordings; CI must stay green.
    });
    return;
  }

  test('PROBE: what the engine hears in real recordings', () {
    final root = Directory(dir);
    expect(root.existsSync(), isTrue, reason: 'REAL_AUDIO_DIR must exist');
    final files =
        root
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'no WAV files in REAL_AUDIO_DIR');

    final rows = <String>[];
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final decoded = WavDecoder.decode(file.readAsBytesSync());
      if (decoded == null) {
        rows.add('$name | NOT A SUPPORTED WAV');
        continue;
      }
      final (pcm, sampleRate) = decoded;

      final pipeline = LivePipeline(sampleRate: sampleRate);
      final chordCounts = <String, int>{};
      // The typed verdicts exist so a silence can be EXPLAINED rather than
      // guessed at: "I could not hear you" and "that is not a chord I know" are
      // different failures with different fixes.
      final decisions = <String, int>{};
      final rejects = <String, int>{};
      final strumTimes = <double>[];
      final bpms = <double>[];
      final levels = <double>[];
      var frames = 0;
      var lastSeq = 0;
      const chunk = 1024;
      for (var i = 0; i < pcm.length; i += chunk) {
        final end = math.min(i + chunk, pcm.length);
        for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
          frames++;
          levels.add(frame.inputLevel);
          if (frame.bpm > 0) bpms.add(frame.bpm);
          if (frame.strumSeq > lastSeq) {
            lastSeq = frame.strumSeq;
            strumTimes.add(frame.latestStrumTime);
          }
          final decision = frame.chordDecision?.name ?? 'none';
          decisions[decision] = (decisions[decision] ?? 0) + 1;
          final reject = frame.chordRejectReason?.name;
          if (reject != null) rejects[reject] = (rejects[reject] ?? 0) + 1;
          final label = frame.current?.label;
          if (label != null) {
            chordCounts[label] = (chordCounts[label] ?? 0) + 1;
          }
        }
      }

      final seconds = pcm.length / sampleRate;
      final sortedBpm = [...bpms]..sort();
      final medianBpm = sortedBpm.isEmpty
          ? null
          : sortedBpm[sortedBpm.length ~/ 2];
      final labelledBpm = _labelledBpm(name);
      final tonic = _tonicFromName(name);

      final top =
          (chordCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .take(4)
              .map((e) => '${e.key}:${e.value}')
              .join(' ');

      final buffer = StringBuffer()
        ..writeln(name)
        ..writeln(
          '  ${seconds.toStringAsFixed(1)}s | frames $frames | '
          'strums ${strumTimes.length} '
          '(${(strumTimes.length / seconds).toStringAsFixed(1)}/s) | '
          'peak level ${levels.isEmpty ? 0 : levels.reduce(math.max).toStringAsFixed(2)}',
        );

      if (labelledBpm != null) {
        final error = medianBpm == null
            ? null
            : (medianBpm - labelledBpm).abs() / labelledBpm * 100;
        // Half- and double-tempo are musically correct readings of the same
        // pulse, so they are named rather than counted as errors — the repo's
        // own tempo metric treats metrical levels the same way.
        final ratio = medianBpm == null ? null : medianBpm / labelledBpm;
        final level = ratio == null
            ? ''
            : (ratio - 0.5).abs() < 0.06
            ? ' (half-time)'
            : (ratio - 2).abs() < 0.24
            ? ' (double-time)'
            : (ratio - 1).abs() < 0.06
            ? ' (on the labelled pulse)'
            : ' (neither the pulse nor a metrical level of it)';
        buffer.writeln(
          '  TEMPO: labelled ${labelledBpm.toStringAsFixed(0)} | '
          'engine ${medianBpm?.toStringAsFixed(1) ?? "none"} | '
          '${error?.toStringAsFixed(1) ?? "-"}%$level',
        );
      }

      if (tonic != null) {
        final inKey = _minorKeyChords(tonic);
        final named = chordCounts.entries.fold<int>(0, (a, e) => a + e.value);
        final inKeyFrames = chordCounts.entries
            .where((e) => inKey.contains(e.key))
            .fold<int>(0, (a, e) => a + e.value);
        buffer.writeln(
          '  KEY ${_pitchNames[tonic]} minor: '
          '${named == 0 ? 0 : (inKeyFrames * 100 / named).round()}% of named '
          'frames are IN KEY (${inKey.join(", ")})',
        );
      }

      buffer
        ..writeln('  chords: ${top.isEmpty ? "(none named)" : top}')
        ..writeln('  decisions: ${_histogram(decisions)}')
        ..write('  rejects: ${_histogram(rejects)}');
      rows.add(buffer.toString());
    }

    // ignore: avoid_print
    print('\n${rows.join("\n\n")}\n');
    expect(rows, isNotEmpty);
  });
}
