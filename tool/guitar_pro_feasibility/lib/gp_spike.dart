import 'dart:convert';
import 'dart:io';

/// The exact fields R13 requires a candidate to expose for a technical fixture.
final class GuitarProProbeResult {
  const GuitarProProbeResult({
    required this.title,
    required this.trackCount,
    required this.tuning,
    required this.measureCount,
    required this.noteCount,
    required this.firstString,
    required this.firstFret,
    required this.tempo,
    required this.meterNumerator,
    required this.meterDenominator,
  });

  final String title;
  final int trackCount;
  final List<int> tuning;
  final int measureCount;
  final int noteCount;
  final int firstString;
  final int firstFret;
  final int tempo;
  final int meterNumerator;
  final int meterDenominator;

  Map<String, Object> toJson() => <String, Object>{
    'title': title,
    'trackCount': trackCount,
    'tuning': tuning,
    'measureCount': measureCount,
    'noteCount': noteCount,
    'firstString': firstString,
    'firstFret': firstFret,
    'tempo': tempo,
    'meterNumerator': meterNumerator,
    'meterDenominator': meterDenominator,
  };

  @override
  bool operator ==(Object other) =>
      other is GuitarProProbeResult &&
      other.title == title &&
      other.trackCount == trackCount &&
      _sameIntegers(other.tuning, tuning) &&
      other.measureCount == measureCount &&
      other.noteCount == noteCount &&
      other.firstString == firstString &&
      other.firstFret == firstFret &&
      other.tempo == tempo &&
      other.meterNumerator == meterNumerator &&
      other.meterDenominator == meterDenominator;

  @override
  int get hashCode => Object.hash(
    title,
    trackCount,
    Object.hashAll(tuning),
    measureCount,
    noteCount,
    firstString,
    firstFret,
    tempo,
    meterNumerator,
    meterDenominator,
  );

  static bool _sameIntegers(List<int> left, List<int> right) =>
      left.length == right.length &&
      List.generate(
        left.length,
        (index) => left[index] == right[index],
      ).every((isEqual) => isEqual);
}

/// A contained candidate failure; the caller never receives Node's raw output.
final class GuitarProProbeFailure {
  const GuitarProProbeFailure(this.reason);

  final String reason;
}

/// Executes alphaTab outside the production app to measure its parser fidelity.
final class AlphaTabProbe {
  const AlphaTabProbe({required this.modulePath});

  final String modulePath;

  Future<GuitarProProbeResult> probe(Uri fixture) async {
    final outcome = await tryProbe(fixture);
    if (outcome is GuitarProProbeResult) {
      return outcome;
    }
    throw FormatException((outcome as GuitarProProbeFailure).reason);
  }

  Future<Object> tryProbe(Uri fixture) async {
    try {
      final process = await Process.run('node', <String>[
        '-e',
        _nodeProbe,
        modulePath,
        fixture.toFilePath(),
      ]);
      if (process.exitCode != 0) {
        return const GuitarProProbeFailure('Candidate rejected the fixture.');
      }
      return _readResult(process.stdout as String);
    } on ProcessException {
      return const GuitarProProbeFailure(
        'Node candidate runtime is unavailable.',
      );
    } on FormatException {
      return const GuitarProProbeFailure(
        'Candidate returned an invalid probe report.',
      );
    } on Object {
      return const GuitarProProbeFailure(
        'Candidate returned an invalid probe report.',
      );
    }
  }

  GuitarProProbeResult _readResult(String stdout) {
    final data = jsonDecode(stdout) as Map<String, Object?>;
    final tuning = (data['tuning'] as List<Object?>).cast<int>();
    return GuitarProProbeResult(
      title: data['title']! as String,
      trackCount: data['trackCount']! as int,
      tuning: tuning,
      measureCount: data['measureCount']! as int,
      noteCount: data['noteCount']! as int,
      firstString: data['firstString']! as int,
      firstFret: data['firstFret']! as int,
      tempo: data['tempo']! as int,
      meterNumerator: data['meterNumerator']! as int,
      meterDenominator: data['meterDenominator']! as int,
    );
  }
}

const minimalGp3Expectation = GuitarProProbeResult(
  title: 'StrumSight Minimal',
  trackCount: 1,
  tuning: <int>[64, 59, 55, 50, 45, 40],
  measureCount: 1,
  noteCount: 1,
  firstString: 6,
  firstFret: 3,
  tempo: 120,
  meterNumerator: 4,
  meterDenominator: 4,
);

const minimalGp5Expectation = minimalGp3Expectation;

const minimalGpxExpectation = GuitarProProbeResult(
  title: '',
  trackCount: 1,
  tuning: <int>[64, 59, 55, 50, 45, 40],
  measureCount: 1,
  noteCount: 28,
  firstString: 1,
  firstFret: 1,
  tempo: 120,
  meterNumerator: 4,
  meterDenominator: 4,
);

const _nodeProbe = r'''
const fs = require('fs');
const alphaTab = require(process.argv[1]);
const score = alphaTab.importer.ScoreLoader.loadScoreFromBytes(
  fs.readFileSync(process.argv[2]),
);
const track = score.tracks[0];
const bars = track.staves[0].bars;
const notes = bars.flatMap((bar) =>
  bar.voices.flatMap((voice) => voice.beats.flatMap((beat) => beat.notes)),
);
const firstNote = notes[0];
const firstMasterBar = score.masterBars[0];
if (!firstNote || !firstMasterBar) {
  throw new Error('fixture does not contain required data');
}
process.stdout.write(JSON.stringify({
  title: score.title,
  trackCount: score.tracks.length,
  tuning: track.staves[0].tuning,
  measureCount: score.masterBars.length,
  noteCount: notes.length,
  firstString: firstNote.string,
  firstFret: firstNote.fret,
  tempo: score.tempo,
  meterNumerator: firstMasterBar.timeSignatureNumerator,
  meterDenominator: firstMasterBar.timeSignatureDenominator,
}));
''';
