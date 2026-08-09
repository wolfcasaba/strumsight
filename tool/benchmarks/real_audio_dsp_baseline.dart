import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart';
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';

const int microsecondsPerSecond = 1000000;
const List<int> onsetTolerancesUs = [25000, 50000, 100000];
const int tempoTolerancePerMille = 40;
const List<double> metricLevelTempoRatios = [
  1 / 3,
  1 / 2,
  2 / 3,
  1,
  3 / 2,
  2,
  3,
];

/// One labeled strum event from a Klangio `.strums` file.
class GroundTruthEvent {
  const GroundTruthEvent({required this.timeUs, required this.label});

  final int timeUs;
  final String label;
}

class OnsetMetrics {
  const OnsetMetrics({
    required this.matched,
    required this.falsePositives,
    required this.falseNegatives,
  });

  final int matched;
  final int falsePositives;
  final int falseNegatives;

  int get predicted => matched + falsePositives;
  int get expected => matched + falseNegatives;
  double get precision => predicted == 0 ? 0 : matched / predicted;
  double get recall => expected == 0 ? 0 : matched / expected;
  double get f1 => precision + recall == 0
      ? 0
      : 2 * precision * recall / (precision + recall);

  OnsetMetrics merge(OnsetMetrics other) => OnsetMetrics(
    matched: matched + other.matched,
    falsePositives: falsePositives + other.falsePositives,
    falseNegatives: falseNegatives + other.falseNegatives,
  );

  Map<String, Object> toJson() => {
    'matched': matched,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
    'precision': precision,
    'recall': recall,
    'f1': f1,
  };
}

/// Two-sided greedy matching on sorted integer microsecond timestamps.
OnsetMetrics matchOnsetsUs(
  List<int> groundTruthUs,
  List<int> predictedUs, {
  required int toleranceUs,
}) {
  final expected = [...groundTruthUs]..sort();
  final predicted = [...predictedUs]..sort();
  var expectedIndex = 0;
  var predictedIndex = 0;
  var matched = 0;
  var falsePositives = 0;
  var falseNegatives = 0;

  while (expectedIndex < expected.length && predictedIndex < predicted.length) {
    final deltaUs = (expected[expectedIndex] - predicted[predictedIndex]).abs();
    if (deltaUs <= toleranceUs) {
      matched++;
      expectedIndex++;
      predictedIndex++;
    } else if (predicted[predictedIndex] < expected[expectedIndex]) {
      falsePositives++;
      predictedIndex++;
    } else {
      falseNegatives++;
      expectedIndex++;
    }
  }
  falsePositives += predicted.length - predictedIndex;
  falseNegatives += expected.length - expectedIndex;
  return OnsetMetrics(
    matched: matched,
    falsePositives: falsePositives,
    falseNegatives: falseNegatives,
  );
}

/// Difference from a reference tempo, rounded to an integer per mille.
int tempoDeviationPerMille(double predictedBpm, double referenceBpm) =>
    (((predictedBpm / referenceBpm - 1).abs()) * 1000).round();

/// Strict tempo agreement with the independent beat-tracker reference.
bool temposMatch(
  double predictedBpm,
  double referenceBpm, {
  int tolerancePerMille = tempoTolerancePerMille,
}) => tempoDeviationPerMille(predictedBpm, referenceBpm) <= tolerancePerMille;

/// Tempo agreement that accepts only the pinned metrical-level ratios.
bool metricLevelTemposMatch(
  double predictedBpm,
  double referenceBpm, {
  int tolerancePerMille = tempoTolerancePerMille,
}) => metricLevelTempoRatios.any(
  (ratio) => temposMatch(
    predictedBpm,
    referenceBpm * ratio,
    tolerancePerMille: tolerancePerMille,
  ),
);

/// Summarizes tempo only when an independent reference is supplied.
Map<String, Object?> buildTempoSummary(
  Map<String, double> predictedByRecording,
  Map<String, double>? referenceByRecording, {
  Iterable<String> referenceExpectedRecordings = const [],
}) {
  if (referenceByRecording == null) {
    return const {
      'status': 'notRun',
      'reason': 'independent tempo reference JSON is missing',
    };
  }

  final expected = referenceExpectedRecordings.toSet();
  final missingReferenceRecordings = [
    for (final recording in expected)
      if (!referenceByRecording.containsKey(recording)) recording,
  ]..sort();
  var strictMatches = 0;
  var metricLevelMatches = 0;
  var eligibleRecordings = 0;
  final records = <Map<String, Object>>[];
  for (final entry in predictedByRecording.entries) {
    final referenceBpm = referenceByRecording[entry.key];
    if (referenceBpm == null) continue;
    final strictMatch = temposMatch(entry.value, referenceBpm);
    final metricLevelMatch = metricLevelTemposMatch(entry.value, referenceBpm);
    eligibleRecordings++;
    if (strictMatch) strictMatches++;
    if (metricLevelMatch) metricLevelMatches++;
    records.add({
      'recording': entry.key,
      'referenceBpm': referenceBpm,
      'predictedBpm': entry.value,
      'strictMatch': strictMatch,
      'metricLevelMatch': metricLevelMatch,
    });
  }
  records.sort(
    (left, right) =>
        (left['recording']! as String).compareTo(right['recording']! as String),
  );
  return {
    'status': 'measured',
    'referenceMethod': 'librosa.beat.beat_track',
    'tolerancePerMille': tempoTolerancePerMille,
    'strictTempoMatch': {
      'matched': strictMatches,
      'eligible': eligibleRecordings,
    },
    'metricLevelTempoMatch': {
      'matched': metricLevelMatches,
      'eligible': eligibleRecordings,
      'ratios': metricLevelTempoRatios,
    },
    'missingReferenceRecordings': missingReferenceRecordings,
    'records': records,
  };
}

class PerLabelMetrics {
  const PerLabelMetrics({
    required this.support,
    required this.truePositives,
    required this.predicted,
  });

  final int support;
  final int truePositives;
  final int predicted;

  double get precision => predicted == 0 ? 0 : truePositives / predicted;
  double get recall => support == 0 ? 0 : truePositives / support;

  Map<String, Object> toJson() => {
    'support': support,
    'precision': precision,
    'recall': recall,
  };
}

class ChordMetrics {
  const ChordMetrics({
    required this.total,
    required this.correct,
    required this.perLabel,
  });

  final int total;
  final int correct;
  final Map<String, PerLabelMetrics> perLabel;

  double get accuracy => total == 0 ? 0 : correct / total;
}

class MajorityClassBaseline {
  const MajorityClassBaseline({
    required this.label,
    required this.count,
    required this.total,
  });

  final String label;
  final int count;
  final int total;

  double get accuracy => total == 0 ? 0 : count / total;
}

final RegExp _groundTruthLabel = RegExp(r'^([A-G](?:#|b)?)-(major|minor)$');
final RegExp _predictedLabel = RegExp(r'^([A-G](?:#|b)?)(m)?$');
const Map<String, String> _enharmonicRoots = {
  'Bb': 'A#',
  'Db': 'C#',
  'Gb': 'F#',
};

String? _canonicalGroundTruthLabel(String raw) {
  final match = _groundTruthLabel.firstMatch(raw.trim());
  if (match == null) return null;
  final root = _enharmonicRoots[match.group(1)!] ?? match.group(1)!;
  return '$root-${match.group(2)!}';
}

String? _canonicalPredictedLabel(String raw) {
  final match = _predictedLabel.firstMatch(raw.trim());
  if (match == null) return null;
  final root = _enharmonicRoots[match.group(1)!] ?? match.group(1)!;
  final quality = match.group(2) == 'm' ? 'minor' : 'major';
  return '$root-$quality';
}

/// True only for the pinned maj/min label contract; no quality truncation.
bool labelsMatch(String groundTruth, String predicted) {
  final expected = _canonicalGroundTruthLabel(groundTruth);
  final actual = _canonicalPredictedLabel(predicted);
  return expected != null && actual != null && expected == actual;
}

/// Scores every ground-truth event, including those no chord segment covers.
ChordMetrics scoreChords(
  List<GroundTruthEvent> events,
  List<TimelineChord> predictedChords, {
  Map<String, String>? labelsByCanonical,
}) {
  final labels =
      labelsByCanonical ??
      {
        for (final event in events)
          _canonicalGroundTruthLabel(event.label)!: event.label,
      };
  final support = <String, int>{for (final label in labels.values) label: 0};
  final truePositives = <String, int>{
    for (final label in labels.values) label: 0,
  };
  final predicted = <String, int>{for (final label in labels.values) label: 0};
  var correct = 0;

  for (final event in events) {
    final expectedCanonical = _canonicalGroundTruthLabel(event.label)!;
    final expected = labels[expectedCanonical]!;
    support[expected] = support[expected]! + 1;
    final timeSec = event.timeUs / microsecondsPerSecond;
    final chord = predictedChords.cast<TimelineChord?>().firstWhere(
      (segment) => segment!.startSec <= timeSec && timeSec < segment.endSec,
      orElse: () => null,
    );
    final actualCanonical = chord == null
        ? null
        : _canonicalPredictedLabel(chord.label);
    final actual = actualCanonical == null ? null : labels[actualCanonical];
    if (actual != null) {
      predicted[actual] = predicted[actual]! + 1;
    }
    if (actualCanonical == expectedCanonical && actual != null) {
      correct++;
      truePositives[expected] = truePositives[expected]! + 1;
    }
  }

  return ChordMetrics(
    total: events.length,
    correct: correct,
    perLabel: {
      for (final label in labels.values)
        label: PerLabelMetrics(
          support: support[label]!,
          truePositives: truePositives[label]!,
          predicted: predicted[label]!,
        ),
    },
  );
}

MajorityClassBaseline majorityClassBaseline(List<String> labels) {
  final counts = <String, int>{};
  for (final rawLabel in labels) {
    final label = _canonicalGroundTruthLabel(rawLabel)!;
    counts[label] = (counts[label] ?? 0) + 1;
  }
  final majority = counts.entries.reduce(
    (current, candidate) =>
        candidate.value > current.value ? candidate : current,
  );
  return MajorityClassBaseline(
    label: majority.key,
    count: majority.value,
    total: labels.length,
  );
}

class _Recording {
  const _Recording({
    required this.stem,
    required this.wav,
    required this.events,
  });

  final String stem;
  final File wav;
  final List<GroundTruthEvent> events;
}

class _SkippedRecording {
  const _SkippedRecording({required this.fileName, required this.error});

  final String fileName;
  final String error;

  Map<String, String> toJson() => {'file': fileName, 'error': error};
}

List<GroundTruthEvent> _readStrums(File file) {
  final events = <GroundTruthEvent>[];
  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final fields = line.split('\t');
    if (fields.length != 3) {
      throw FormatException('expected three tab-separated fields: $line');
    }
    final seconds = double.tryParse(fields[0]);
    if (seconds == null || seconds < 0) {
      throw FormatException('invalid onset time: ${fields[0]}');
    }
    if (_canonicalGroundTruthLabel(fields[2]) == null) {
      throw FormatException('unsupported ground-truth label: ${fields[2]}');
    }
    events.add(
      GroundTruthEvent(
        timeUs: (seconds * microsecondsPerSecond).round(),
        label: fields[2],
      ),
    );
  }
  if (events.isEmpty) throw const FormatException('no strum events');
  return events;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double? _deriveStrumDensityBpm(List<GroundTruthEvent> events) {
  final intervalsUs = <double>[
    for (var index = 1; index < events.length; index++)
      (events[index].timeUs - events[index - 1].timeUs).toDouble(),
  ].where((intervalUs) => intervalUs > 0).toList();
  if (intervalsUs.isEmpty) return null;
  final medianUs = _median(intervalsUs);
  return 60 * microsecondsPerSecond / medianUs;
}

Map<String, double>? _readTempoReference() {
  const referencePath = String.fromEnvironment(
    'REAL_AUDIO_DSP_TEMPO_REFERENCE',
  );
  if (referencePath.isEmpty) return null;
  final file = File(referencePath);
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('tempo reference JSON must be an object');
  }
  final reference = <String, double>{};
  for (final entry in decoded.entries) {
    if (entry.value is! num || (entry.value as num) <= 0) {
      throw FormatException('invalid tempo reference for ${entry.key}');
    }
    reference[entry.key] = (entry.value as num).toDouble();
  }
  return reference;
}

String _corpusChecksum(List<File> files) {
  final output = _DigestCollector();
  final input = sha256.startChunkedConversion(output);
  for (final file in files) {
    input.add(utf8.encode('${file.uri.pathSegments.last}\n'));
    input.add(file.readAsBytesSync());
  }
  input.close();
  return output.value.toString();
}

class _DigestCollector implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest!;

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}
}

Map<String, Object> _chordJson(
  ChordMetrics metrics,
  MajorityClassBaseline baseline,
  ChordMetrics minorMetrics,
) => {
  'correct': metrics.correct,
  'total': metrics.total,
  'accuracy': metrics.accuracy,
  'majorityClassBaseline': {
    'label': baseline.label,
    'correct': baseline.count,
    'total': baseline.total,
    'accuracy': baseline.accuracy,
  },
  'minorSubset': {
    'correct': minorMetrics.correct,
    'total': minorMetrics.total,
    'accuracy': minorMetrics.accuracy,
  },
  'perLabel': {
    for (final entry
        in metrics.perLabel.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key)))
      entry.key: entry.value.toJson(),
  },
};

void main([List<String> arguments = const []]) {
  const corpusFromDefine = String.fromEnvironment(
    'REAL_AUDIO_DSP_BASELINE_CORPUS',
  );
  if (arguments.length > 1 || (arguments.isEmpty && corpusFromDefine.isEmpty)) {
    stderr.writeln(
      'usage: dart run tool/benchmarks/real_audio_dsp_baseline.dart <corpus-directory>\n'
      'or: flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=<corpus-directory> '
      '--dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=<reference.json> '
      'tool/benchmarks/real_audio_dsp_baseline.dart',
    );
    exitCode = 64;
    return;
  }

  final corpus = Directory(
    arguments.isEmpty ? corpusFromDefine : arguments.single,
  );
  if (!corpus.existsSync()) {
    stderr.writeln('corpus directory does not exist: ${corpus.path}');
    exitCode = 66;
    return;
  }
  final strumFiles =
      corpus
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.strums'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final wavFiles =
      corpus
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.wav'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final recordings = <_Recording>[];
  final skipped = <_SkippedRecording>[];

  for (final strum in strumFiles) {
    final fileName = strum.uri.pathSegments.last;
    final stem = fileName.substring(0, fileName.length - '.strums'.length);
    final wav = File(
      '${corpus.path}${Platform.pathSeparator}${stem}_phone.wav',
    );
    if (!wav.existsSync()) {
      skipped.add(
        _SkippedRecording(fileName: fileName, error: 'matching WAV is missing'),
      );
      continue;
    }
    try {
      recordings.add(
        _Recording(stem: stem, wav: wav, events: _readStrums(strum)),
      );
    } on Object catch (error) {
      skipped.add(
        _SkippedRecording(fileName: fileName, error: error.toString()),
      );
    }
  }

  final allEvents = [for (final recording in recordings) ...recording.events];
  final labelsByCanonical = {
    for (final event in allEvents)
      _canonicalGroundTruthLabel(event.label)!: event.label,
  };
  final baseline = majorityClassBaseline([
    for (final event in allEvents) event.label,
  ]);
  var chords = ChordMetrics(
    total: 0,
    correct: 0,
    perLabel: {
      for (final label in labelsByCanonical.values)
        label: const PerLabelMetrics(
          support: 0,
          truePositives: 0,
          predicted: 0,
        ),
    },
  );
  final onsetMetrics = {
    for (final toleranceUs in onsetTolerancesUs)
      toleranceUs: const OnsetMetrics(
        matched: 0,
        falsePositives: 0,
        falseNegatives: 0,
      ),
  };
  final predictedTempoByRecording = <String, double>{};
  final strumDensityRecords = <Map<String, Object?>>[];
  final tempoReference = _readTempoReference();
  final analyzer = const ClipAnalyzer();

  for (var index = 0; index < recordings.length; index++) {
    final recording = recordings[index];
    stderr.writeln(
      '[${index + 1}/${recordings.length}] ${recording.wav.uri.pathSegments.last}',
    );
    try {
      final decoded = WavDecoder.decode(recording.wav.readAsBytesSync());
      if (decoded == null) {
        throw const FormatException('unsupported or invalid WAV');
      }
      final result = analyzer.analyze(decoded.$1, decoded.$2);
      final recordingChords = scoreChords(
        recording.events,
        result.chords,
        labelsByCanonical: labelsByCanonical,
      );
      chords = _mergeChordMetrics(chords, recordingChords);
      final expectedOnsets = [
        for (final event in recording.events) event.timeUs,
      ];
      final predictedOnsets = [
        for (final strum in result.strums)
          (strum.timeSec * microsecondsPerSecond).round(),
      ];
      for (final toleranceUs in onsetTolerancesUs) {
        onsetMetrics[toleranceUs] = onsetMetrics[toleranceUs]!.merge(
          matchOnsetsUs(
            expectedOnsets,
            predictedOnsets,
            toleranceUs: toleranceUs,
          ),
        );
      }
      predictedTempoByRecording[recording.stem] = result.bpm;
      final strumDensityBpm = _deriveStrumDensityBpm(recording.events);
      if (strumDensityBpm != null) {
        strumDensityRecords.add({
          'recording': recording.stem,
          'strumDensityBpm': strumDensityBpm,
          'predictedBpm': result.bpm,
          'absoluteDifferenceBpm': (result.bpm - strumDensityBpm).abs(),
        });
      }
    } on Object catch (error) {
      skipped.add(
        _SkippedRecording(
          fileName: recording.wav.uri.pathSegments.last,
          error: error.toString(),
        ),
      );
    }
  }

  final minorEvents = allEvents
      .where((event) => event.label.endsWith('-minor'))
      .toList();
  final minorMetrics = _minorMetricsFromAggregate(
    chords,
    minorEvents,
    labelsByCanonical,
  );
  final tempoSummary = buildTempoSummary(
    predictedTempoByRecording,
    tempoReference,
    referenceExpectedRecordings: recordings.map((recording) => recording.stem),
  );
  final strumDensityDifferences = strumDensityRecords
      .map((record) => record['absoluteDifferenceBpm'])
      .whereType<double>()
      .toList();
  final report = <String, Object?>{
    'corpus': {
      'path': corpus.path,
      'wavCount': wavFiles.length,
      'strumsCount': strumFiles.length,
      'eventCount': allEvents.length,
      'sha256': _corpusChecksum([...wavFiles, ...strumFiles]),
      'versionControlled': false,
    },
    'processedRecordings':
        recordings.length -
        skipped.where((entry) => entry.fileName.endsWith('.wav')).length,
    'skippedRecordings': skipped.map((entry) => entry.toJson()).toList(),
    'chords': _chordJson(chords, baseline, minorMetrics),
    'onsets': {
      for (final toleranceUs in onsetTolerancesUs)
        '$toleranceUs': onsetMetrics[toleranceUs]!.toJson(),
    },
    'bpm': {
      ...tempoSummary,
      'strumDensityAgreement': {
        'method': '60 / median positive .strums inter-onset interval',
        'recordings': strumDensityRecords.length,
        'meanAbsoluteDifferenceBpm': strumDensityDifferences.isEmpty
            ? null
            : strumDensityDifferences.reduce((sum, value) => sum + value) /
                  strumDensityDifferences.length,
        'records': strumDensityRecords,
      },
    },
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

ChordMetrics _mergeChordMetrics(ChordMetrics left, ChordMetrics right) {
  final labels = {...left.perLabel.keys, ...right.perLabel.keys};
  return ChordMetrics(
    total: left.total + right.total,
    correct: left.correct + right.correct,
    perLabel: {
      for (final label in labels)
        label: PerLabelMetrics(
          support:
              (left.perLabel[label]?.support ?? 0) +
              (right.perLabel[label]?.support ?? 0),
          truePositives:
              (left.perLabel[label]?.truePositives ?? 0) +
              (right.perLabel[label]?.truePositives ?? 0),
          predicted:
              (left.perLabel[label]?.predicted ?? 0) +
              (right.perLabel[label]?.predicted ?? 0),
        ),
    },
  );
}

ChordMetrics _minorMetricsFromAggregate(
  ChordMetrics aggregate,
  List<GroundTruthEvent> minorEvents,
  Map<String, String> labelsByCanonical,
) {
  final minorLabels = {for (final event in minorEvents) event.label};
  return ChordMetrics(
    total: minorEvents.length,
    correct: minorLabels.fold(
      0,
      (sum, label) => sum + (aggregate.perLabel[label]?.truePositives ?? 0),
    ),
    perLabel: {
      for (final label in labelsByCanonical.values.where(
        (label) => label.endsWith('-minor'),
      ))
        label:
            aggregate.perLabel[label] ??
            const PerLabelMetrics(support: 0, truePositives: 0, predicted: 0),
    },
  );
}
