// Shared measurement harness for the whitening sweeps (E18-R10, E18-R11).
//
// Three criteria, one definition each. They live here rather than in the sweep
// files because the rounds compare numbers ACROSS files — the E18-R11 floor
// grid has to reproduce the E18-R10 coefficient row exactly — and two copies of
// a stimulus that drift apart would make that comparison a lie rather than a
// check. The in-key sets are shared with
// `test/tooling/real_audio_hearing_probe_test.dart` for the same reason.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/core/music/guitar_strings.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/live/engine/dsp/chord_dictionary.dart';
import 'package:strumsight/features/live/engine/dsp/chord_matcher.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/nnls_chroma.dart';
import 'package:strumsight/features/live/engine/dsp/viterbi_chord_decoder.dart';

import 'synth.dart';

const int sweepSampleRate = 44100;

/// The seven chords the beginner course teaches, with exact ground truth.
const modelledChords = ['Em', 'Am', 'D', 'G', 'C', 'E', 'A'];

/// One whitening setting: the three dials a sweep varies together.
class WhiteningSetting {
  const WhiteningSetting({
    this.meanCoefficient = 0.0,
    this.spectralFloor = 0.0,
    this.exponent = NnlsChroma.defaultWhiteningExponent,
  });

  final double meanCoefficient;
  final double spectralFloor;
  final double exponent;

  @override
  String toString() =>
      'k=${meanCoefficient.toStringAsFixed(2)} '
      'beta=${spectralFloor.toStringAsFixed(2)} '
      'w=${exponent.toStringAsFixed(1)}';
}

// --- modelled guitar -------------------------------------------------------

List<double> pluckedString({
  required double freqHz,
  required double seconds,
  required int seed,
  double damping = 0.996,
  double amplitude = 0.25,
}) {
  final length = (seconds * sweepSampleRate).round();
  final delay = math.max(2, (sweepSampleRate / freqHz).round());
  final random = math.Random(seed);
  final buffer = List<double>.generate(
    delay,
    (_) => random.nextDouble() * 2 - 1,
  );
  for (var pass = 0; pass < 2; pass++) {
    for (var i = 1; i < buffer.length; i++) {
      buffer[i] = (buffer[i] + buffer[i - 1]) / 2;
    }
  }
  final out = List<double>.filled(length, 0);
  var index = 0;
  for (var n = 0; n < length; n++) {
    final current = buffer[index];
    final next = buffer[(index + 1) % delay];
    out[n] = current * amplitude;
    buffer[index] = damping * (current + next) / 2;
    index = (index + 1) % delay;
  }
  final fade = (0.03 * sweepSampleRate).round();
  for (var i = 0; i < fade && i < length; i++) {
    out[length - 1 - i] *= i / fade;
  }
  return out;
}

/// Karplus-Strong strum of [label] from the app's OWN [ChordShapes] fingering,
/// so the stimulus cannot disagree with the chord the app would teach.
List<double> strumChord(String label, {double seconds = 3.0}) {
  final shape = ChordShapes.forLabel(label)!;
  final strings = GuitarStrings.standard;
  final pcm = List<double>.filled((seconds * sweepSampleRate).round(), 0);
  var voice = 0;
  for (var position = 0; position < 6; position++) {
    final fret = shape.frets[position];
    if (fret < 0) continue;
    final midi = strings[position].midi + fret;
    final freq = 440 * math.pow(2, (midi - 69) / 12).toDouble();
    final offset = (position * 0.022 * sweepSampleRate).round();
    final tone = pluckedString(
      freqHz: freq,
      seconds: seconds - position * 0.022,
      seed: 1000 + voice * 17,
      damping: midi < 55 ? 0.9975 : 0.9955,
    );
    for (var i = 0; i < tone.length; i++) {
      final at = offset + i;
      if (at < pcm.length) pcm[at] += tone[i];
    }
    voice++;
  }
  return pcm;
}

// --- criterion 1: the quiet third ------------------------------------------

/// Open E (022100), levels from the E18-R01 reference recording; the third G#3
/// is the quiet one, at [third] of the peak.
List<(double, double)> openEVoicing(double third) => [
  (82.41, 0.60), // E2
  (123.47, 0.97), // B2  the fifth, doubled and loud
  (164.81, 1.00), // E3
  (207.65, third), // G#3 the major third, fretted once
  (246.94, 0.49), // B3
  (329.63, 0.53), // E4
];

/// The SHIPPED fixture's own voicing and decode path, not a replica of it.
///
/// An earlier version of this sweep built its own quiet-third signal through
/// `LivePipeline` and got no confirmed chord at ANY coefficient — including
/// today's shipped one, where the fixture passes. The replica was measuring
/// nothing. This uses `voicedChord` and the direct NnlsChroma + Viterbi path
/// that `spectral_whitening_test.dart` uses, so the number here is the same
/// number that guards the shipped behaviour. A uniform column of dashes means
/// the stimulus broke, not that the engine went deaf.
String? quietThird(WhiteningSetting setting, {double third = 0.08}) {
  final nc = NnlsChroma(
    sampleRate: sweepSampleRate,
    whiteningMeanCoefficient: setting.meanCoefficient,
    whiteningSpectralFloor: setting.spectralFloor,
    whiteningExponent: setting.exponent,
  );
  final decoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(),
  );
  ChordMatch? last;
  for (final frame in frames(
    voicedChord(openEVoicing(third)),
    DspConfig.nnlsWindow,
    DspConfig.nnlsHop,
  )) {
    final chroma = nc.process(frame);
    final tonal =
        chroma != null && nc.lastTonalness >= DspConfig.chordMinTonalness;
    last = tonal
        ? decoder.process(nc.lastBassChroma, nc.lastTrebleChroma)
        : decoder.process(Float64List(12), Float64List(12));
  }
  return last?.chord.label;
}

/// The MEAN relative weight of the quiet third's own bin (G#3, 207.65 Hz) in the
/// whitened spectrum, across the stimulus's frames.
///
/// This is the mechanism datum behind the E18-R11 verdict. "The third still reads
/// as Em" has two very different explanations — the bin was DELETED, or the bin
/// survived but carries too little weight to outvote the doubled fifth — and the
/// spectral floor is supposed to fix only the first. Reading the bin directly
/// says which one is actually happening.
double quietThirdBinWeight(WhiteningSetting setting, {double third = 0.08}) {
  final nc = NnlsChroma(
    sampleRate: sweepSampleRate,
    whiteningMeanCoefficient: setting.meanCoefficient,
    whiteningSpectralFloor: setting.spectralFloor,
    whiteningExponent: setting.exponent,
  );
  var sum = 0.0;
  var counted = 0;
  for (final frame in frames(
    voicedChord(openEVoicing(third)),
    DspConfig.nnlsWindow,
    DspConfig.nnlsHop,
  )) {
    if (nc.process(frame) == null) continue;
    sum += nc.debugWhitenedRelativeAt(207.65);
    counted++;
  }
  return counted == 0 ? 0 : sum / counted;
}

// --- running the real pipeline ---------------------------------------------

class SweepRun {
  SweepRun({
    required this.chords,
    required this.confirmed,
    required this.rescuedFraction,
    required this.zeroedFraction,
  });

  final Map<String, int> chords;
  final int confirmed;

  /// Mean over frames of the share of log-frequency bins the spectral floor
  /// rescued from the hard zero, and the share still left at zero after it.
  final double rescuedFraction;
  final double zeroedFraction;
}

SweepRun runPipeline(
  List<double> pcm,
  int sampleRate,
  WhiteningSetting setting,
) {
  final pipeline = LivePipeline(
    sampleRate: sampleRate,
    whiteningMeanCoefficient: setting.meanCoefficient,
    whiteningSpectralFloor: setting.spectralFloor,
    whiteningExponent: setting.exponent,
  );
  final chords = <String, int>{};
  var confirmed = 0;
  var rescued = 0.0;
  var zeroed = 0.0;
  var frameCount = 0;
  const chunk = 1024;
  for (var i = 0; i < pcm.length; i += chunk) {
    final end = math.min(i + chunk, pcm.length);
    for (final frame in pipeline.addChunk(pcm.sublist(i, end))) {
      frameCount++;
      rescued += pipeline.debugWhiteningRescuedFraction;
      zeroed += pipeline.debugWhiteningZeroedFraction;
      final label = frame.current?.label;
      if (label == null) continue;
      confirmed++;
      chords[label] = (chords[label] ?? 0) + 1;
    }
  }
  return SweepRun(
    chords: chords,
    confirmed: confirmed,
    rescuedFraction: frameCount == 0 ? 0 : rescued / frameCount,
    zeroedFraction: frameCount == 0 ? 0 : zeroed / frameCount,
  );
}

String? topChord(Map<String, int> chords) => chords.isEmpty
    ? null
    : chords.entries.reduce((a, b) => b.value > a.value ? b : a).key;

/// The share of named frames labelled `sus4` or `aug` — the qualities the
/// real-audio probe found over-reported. A triad whose third is too weak to see
/// reads as a sus4 exactly that way, which is why this number is expected to
/// move when the third survives.
double colourShare(Map<String, int> chords) {
  final total = chords.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 0;
  final suspect = chords.entries
      .where((e) => e.key.contains('sus4') || e.key.contains('aug'))
      .fold<int>(0, (a, e) => a + e.value);
  return suspect / total;
}

// --- key membership (shared with the real-audio probe) ---------------------

const pitchNames = [
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

/// Chords that belong to a natural minor key, by tonic pitch class:
/// i, ii-dim, III, iv, v, VI, VII — plus the V that harmonic minor borrows,
/// because popular music uses it constantly.
///
/// Triads AND their diatonic sevenths. The first version of this set listed
/// triads only, which scored a decoder that correctly named `Gmaj7` and `Dmaj7`
/// in B minor as if it had wandered out of the key — the measurement was wrong,
/// not the engine.
Set<String> minorKeyChords(int tonicPc) {
  String name(int pc) => pitchNames[pc % 12];
  return {
    '${name(tonicPc)}m', '${name(tonicPc)}m7', // i
    '${name(tonicPc + 2)}dim', // ii dim
    name(tonicPc + 3), '${name(tonicPc + 3)}maj7', // III
    '${name(tonicPc + 5)}m', '${name(tonicPc + 5)}m7', // iv
    '${name(tonicPc + 7)}m', '${name(tonicPc + 7)}m7', // v
    name(tonicPc + 7),
    '${name(tonicPc + 7)}7', // V, borrowed from harmonic minor
    name(tonicPc + 8), '${name(tonicPc + 8)}maj7', // VI
    name(tonicPc + 10), '${name(tonicPc + 10)}7', // VII
  };
}

/// The tonic pitch class stated in a stock loop's FILENAME, or null — the only
/// harmonic ground truth these third-party recordings carry.
int? tonicFromName(String fileName) {
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

/// The share of named frames that belong to [tonicPc] minor, or null when
/// nothing was named at all — which is NOT 0 %: "named nothing" and "named the
/// wrong things" are different failures with different fixes.
double? inKeyShare(Map<String, int> chords, int tonicPc) {
  final inKey = minorKeyChords(tonicPc);
  final named = chords.values.fold<int>(0, (a, b) => a + b);
  if (named == 0) return null;
  final hits = chords.entries
      .where((e) => inKey.contains(e.key))
      .fold<int>(0, (a, e) => a + e.value);
  return hits / named;
}

// --- the recordings --------------------------------------------------------

/// The WAVs in `REAL_AUDIO_DIR`, sorted, or empty when unset — the recordings
/// are third-party stock audio and are never committed.
List<File> realAudioFiles() {
  final dir = Platform.environment['REAL_AUDIO_DIR'];
  if (dir == null || dir.isEmpty) return <File>[];
  final root = Directory(dir);
  if (!root.existsSync()) return <File>[];
  return root.listSync().whereType<File>().where((f) {
    return f.path.toLowerCase().endsWith('.wav');
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
}

({List<double> pcm, int sampleRate})? decodeWav(File file) {
  final decoded = WavDecoder.decode(file.readAsBytesSync());
  if (decoded == null) return null;
  final (pcm, sampleRate) = decoded;
  return (pcm: pcm, sampleRate: sampleRate);
}
