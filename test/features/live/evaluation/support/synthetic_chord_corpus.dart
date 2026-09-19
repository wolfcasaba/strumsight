// E14-R25 (ADR 0538): a DETERMINISTIC, SEEDED, **SYNTHETIC** chord corpus.
//
// READ THIS BEFORE USING IT FOR ANYTHING: this generator produces
// Karplus–Strong plucks plus a decaying harmonic series. That is a plausible
// guitar-shaped signal and nothing more. It exists to exercise the corpus
// VALIDATOR and the decoder plumbing — every manifest it emits carries
// `corpusKind: synthetic`, and `ChordCorpusManifest.gateEvidenceRefusal`
// refuses it as release evidence (SDD Ch14 §12/2). No accuracy number
// measured on this corpus is a measurement of the product.
//
// Determinism: the only randomness is the Karplus–Strong excitation, drawn
// from a `math.Random(seed)` created per item from `seed + itemIndex`, so
// the same seed always produces the same bytes in the same order.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:strumsight/features/live/domain/evaluation/chord_corpus_manifest.dart';

/// One generated item: its metadata row plus the PCM it stands for.
final class SyntheticChordItem {
  const SyntheticChordItem({required this.item, required this.pcm});

  final ChordCorpusItem item;
  final Float64List pcm;
}

/// The generated corpus: the manifest (validator input) and the audio.
final class SyntheticChordCorpus {
  const SyntheticChordCorpus({
    required this.manifest,
    required this.items,
    required this.sampleRate,
  });

  final ChordCorpusManifest manifest;
  final List<SyntheticChordItem> items;
  final int sampleRate;
}

/// The three voicings the generator renders, and how each places the triad.
///
/// These are SYNTHETIC placements, not transcriptions of real fingerings:
/// `open` puts the triad low with a doubled root, `barre` raises the whole
/// shape by a fifth, `alt` inverts it. They differ audibly and consistently,
/// which is all the validator needs.
const Map<ChordVoicing, List<int>> syntheticVoicingSemitones =
    <ChordVoicing, List<int>>{
      ChordVoicing.open: <int>[0, 12, 19],
      ChordVoicing.barre: <int>[7, 12, 16],
      ChordVoicing.alt: <int>[12, 19, 24],
    };

/// Tempi the generator sweeps (bpm).
const List<int> syntheticCorpusTempos = <int>[60, 90, 120];

/// Generates a balanced synthetic corpus: every supported chord label, every
/// voicing, every tempo — `24 * 3 * 3 = 216` items by default.
///
/// The rotating player/device/guitar/room assignment is deliberately
/// COARSER than the label sweep, so a grouped holdout over it is non-trivial
/// (every group holds several labels).
SyntheticChordCorpus generateSyntheticChordCorpus({
  required int seed,
  int sampleRate = 22050,
  double secondsPerItem = 1.0,
  List<String> labels = chordCorpusMajMin24Labels,
  List<ChordVoicing> voicings = ChordVoicing.values,
  List<int> tempos = syntheticCorpusTempos,
}) {
  final items = <SyntheticChordItem>[];
  var index = 0;
  for (final label in labels) {
    for (final voicing in voicings) {
      for (final tempo in tempos) {
        final random = math.Random(seed + index);
        final pcm = _renderChord(
          label: label,
          voicing: voicing,
          sampleRate: sampleRate,
          seconds: secondsPerItem,
          random: random,
        );
        items.add(
          SyntheticChordItem(
            item: ChordCorpusItem(
              itemId: 'syn-${index.toString().padLeft(4, '0')}-$label',
              label: label,
              voicing: voicing,
              capo: index % 3,
              pickStyle: index.isEven
                  ? ChordPickStyle.pick
                  : ChordPickStyle.finger,
              loudness: ChordLoudness.values[index % 3],
              room: 'synthetic-room-${index % 4}',
              distanceCm: 50 + 25 * (index % 3),
              guitar: 'synthetic-guitar-${index % 4}',
              player: 'synthetic-player-${index % 8}',
              device: 'synthetic-device-${index % 6}',
              durationMs: (secondsPerItem * 1000).round(),
              tempoBpm: tempo,
              hardNegativeCategory: null,
            ),
            pcm: pcm,
          ),
        );
        index++;
      }
    }
  }
  final manifest = ChordCorpusManifest(
    schemaVersion: supportedChordCorpusSchemaVersion,
    corpusId: 'synthetic-majmin-seed$seed',
    corpusKind: ChordCorpusKind.synthetic,
    corpusSha256: 'synthetic:seed=$seed:items=${items.length}',
    items: <ChordCorpusItem>[for (final entry in items) entry.item],
  );
  return SyntheticChordCorpus(
    manifest: manifest,
    items: List<SyntheticChordItem>.unmodifiable(items),
    sampleRate: sampleRate,
  );
}

/// Semitone offsets from the root for the two supported qualities.
const List<int> _majorTriad = <int>[0, 4, 7];
const List<int> _minorTriad = <int>[0, 3, 7];

/// Pitch classes in the order `chordCorpusMajMin24Labels` uses.
const List<String> _pitchClasses = <String>[
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

/// MIDI note of the C below the guitar's open A string (C2 = 36).
const int _rootMidiBase = 36;

Float64List _renderChord({
  required String label,
  required ChordVoicing voicing,
  required int sampleRate,
  required double seconds,
  required math.Random random,
}) {
  final isMinor = label.endsWith('m');
  final rootName = isMinor ? label.substring(0, label.length - 1) : label;
  final rootIndex = _pitchClasses.indexOf(rootName);
  if (rootIndex < 0) {
    throw ArgumentError.value(label, 'label', 'is not a supported chord');
  }
  final triad = isMinor ? _minorTriad : _majorTriad;
  final placement = syntheticVoicingSemitones[voicing]!;
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  for (var voice = 0; voice < triad.length; voice++) {
    final midi = _rootMidiBase + rootIndex + triad[voice] + placement[voice];
    final freq = 440 * math.pow(2, (midi - 69) / 12).toDouble();
    // A staggered pluck, low string first — a downstroke's shape.
    final offset = (voice * 0.008 * sampleRate).round();
    _addKarplusStrong(
      out,
      freq: freq,
      sampleRate: sampleRate,
      offset: offset,
      amp: 0.22,
      random: random,
    );
    _addHarmonicVoice(
      out,
      freq: freq,
      sampleRate: sampleRate,
      offset: offset,
      amp: 0.08,
    );
  }
  return out;
}

/// Karplus–Strong plucked string: a noise burst of one period, then a
/// two-tap averaging comb. Deterministic given [random].
void _addKarplusStrong(
  Float64List out, {
  required double freq,
  required int sampleRate,
  required int offset,
  required double amp,
  required math.Random random,
}) {
  final period = (sampleRate / freq).round();
  if (period < 2 || offset >= out.length) return;
  final buffer = Float64List(period);
  for (var i = 0; i < period; i++) {
    buffer[i] = random.nextDouble() * 2 - 1;
  }
  var read = 0;
  var previous = 0.0;
  for (var i = offset; i < out.length; i++) {
    final current = buffer[read];
    final filtered = 0.5 * (current + previous) * 0.996;
    buffer[read] = filtered;
    previous = current;
    out[i] += amp * filtered;
    read = (read + 1) % period;
  }
}

/// A decaying harmonic series on top of the pluck — the sustained part a
/// chroma/CQT front end actually sees.
void _addHarmonicVoice(
  Float64List out, {
  required double freq,
  required int sampleRate,
  required int offset,
  required double amp,
  int harmonics = 6,
  double decayPerSecond = 1.5,
}) {
  for (var h = 1; h <= harmonics; h++) {
    final f = freq * h;
    if (f > sampleRate / 2) break;
    final a = amp / h;
    final w = 2 * math.pi * f / sampleRate;
    for (var i = offset; i < out.length; i++) {
      final t = (i - offset) / sampleRate;
      out[i] += a * math.exp(-decayPerSecond * t) * math.sin(w * (i - offset));
    }
  }
}
