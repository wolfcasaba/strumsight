/// Deterministic V1 Analyze baseline harness for E06-R01.
///
/// Run with:
/// `flutter test --reporter expanded tool/audio_analysis_baseline.dart`
///
/// The Flutter test runner is required because [runClipAnalysis] transitively
/// imports `dart:ui`; the harness intentionally uses no `rootBundle` access.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/providers/analyze_providers.dart';
import 'package:strumsight/features/live/engine/ml/crnn_strum_net.dart';
import 'package:strumsight/features/live/engine/ml/strum_crnn.dart';

const _sampleRate = 44100;
const _modelAsset = 'assets/ml/strum_crnn.bin';

void main() {
  test('prints the deterministic Analyze V1 baseline', () {
    final modelLoad = _measureModelLoad();
    final first = _runFixtures(modelLoad);
    final second = _runFixtures(modelLoad);
    final firstBytes = utf8.encode(
      jsonEncode([for (final result in first) result.toDeterminismJson()]),
    );
    final secondBytes = utf8.encode(
      jsonEncode([for (final result in second) result.toDeterminismJson()]),
    );

    expect(secondBytes, orderedEquals(firstBytes));

    stdout.writeln('MODEL ${jsonEncode(modelLoad.toJson())}');
    for (final result in first) {
      stdout.writeln('FIXTURE ${jsonEncode(result.toJson())}');
    }
    stdout.writeln('DETERMINISM_SHA256 ${sha256.convert(firstBytes)}');
  });
}

List<_FixtureResult> _runFixtures(_ModelLoad modelLoad) {
  return [
        _Fixture('silence_2s', Float64List(_sampleRate * 2)),
        _Fixture('strums_120_bpm', _strumPattern()),
        _Fixture('progression_c_g_am_f', _fourChordProgression()),
      ]
      .map((fixture) {
        final stopwatch = Stopwatch()..start();
        final result = runClipAnalysis((
          fixture.pcm,
          _sampleRate,
          modelLoad.weights,
          false,
          null,
        ));
        stopwatch.stop();
        return _FixtureResult(
          name: fixture.name,
          analysisMicroseconds: stopwatch.elapsedMicroseconds,
          durationSec: result.durationSec,
          bpm: result.bpm,
          strumCount: result.strums.length,
          chordSegmentCount: result.chords.length,
          chordTimeline: [
            for (final chord in result.chords)
              {
                'label': chord.label,
                'startSec': chord.startSec,
                'endSec': chord.endSec,
              },
          ],
          modelAssetBytes: modelLoad.bytes,
        );
      })
      .toList(growable: false);
}

_ModelLoad _measureModelLoad() {
  final stopwatch = Stopwatch()..start();
  final bytes = File(_modelAsset).readAsBytesSync();
  StrumCrnn(CrnnStrumNet.parse(ByteData.sublistView(bytes)));
  stopwatch.stop();
  return _ModelLoad(
    asset: _modelAsset,
    bytes: bytes.length,
    readAndParseMicroseconds: stopwatch.elapsedMicroseconds,
    weights: bytes,
  );
}

Float64List _fourChordProgression() => _concatenate([
  _chordSignal(const [130.81, 164.81, 196.00]),
  _chordSignal(const [98.00, 123.47, 196.00]),
  _chordSignal(const [110.00, 130.81, 164.81]),
  _chordSignal(const [87.31, 110.00, 130.81]),
]);

Float64List _strumPattern() {
  const lowToHigh = [82.41, 110.00, 146.83, 196.00, 246.94, 329.63];
  const gapSamples = _sampleRate ~/ 2;
  const leadSamples = _sampleRate ~/ 10;
  final staggerSamples = (0.008 * _sampleRate).round();
  final notes = <Float64List>[];
  final offsets = <int>[];
  for (var strum = 0; strum < 5; strum++) {
    final order = strum.isEven ? lowToHigh : lowToHigh.reversed;
    for (var string = 0; string < lowToHigh.length; string++) {
      notes.add(
        _harmonicNote(order.elementAt(string), seconds: 0.45, amp: 0.12),
      );
      offsets.add(leadSamples + strum * gapSamples + string * staggerSamples);
    }
  }
  return _mix(notes, offsets, length: leadSamples + 5 * gapSamples);
}

Float64List _chordSignal(List<double> frequencies) => _mix([
  for (final frequency in frequencies) _harmonicNote(frequency, seconds: 0.8),
], const []);

Float64List _harmonicNote(
  double frequency, {
  required double seconds,
  double amp = 0.2,
}) {
  final samples = (seconds * _sampleRate).round();
  final output = Float64List(samples);
  for (var harmonic = 1; harmonic <= 6; harmonic++) {
    final harmonicFrequency = frequency * harmonic;
    if (harmonicFrequency > _sampleRate / 2) break;
    final angularFrequency = 2 * math.pi * harmonicFrequency / _sampleRate;
    for (var sample = 0; sample < samples; sample++) {
      final envelope = math.exp(-1.5 * sample / _sampleRate);
      output[sample] +=
          (amp / harmonic) * envelope * math.sin(angularFrequency * sample);
    }
  }
  final releaseSamples = math.min((0.010 * _sampleRate).round(), samples);
  for (var sample = 0; sample < releaseSamples; sample++) {
    output[samples - 1 - sample] *=
        0.5 - 0.5 * math.cos(math.pi * sample / releaseSamples);
  }
  return output;
}

Float64List _concatenate(List<Float64List> parts) {
  final output = Float64List(parts.fold(0, (sum, part) => sum + part.length));
  var offset = 0;
  for (final part in parts) {
    output.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return output;
}

Float64List _mix(List<Float64List> notes, List<int> offsets, {int? length}) {
  final effectiveOffsets = offsets.isEmpty
      ? List.filled(notes.length, 0)
      : offsets;
  final outputLength =
      length ??
      List.generate(
        notes.length,
        (index) => notes[index].length + effectiveOffsets[index],
      ).reduce(math.max);
  final output = Float64List(outputLength);
  for (var note = 0; note < notes.length; note++) {
    for (
      var sample = 0;
      sample < notes[note].length &&
          effectiveOffsets[note] + sample < output.length;
      sample++
    ) {
      output[effectiveOffsets[note] + sample] += notes[note][sample];
    }
  }
  return output;
}

class _Fixture {
  const _Fixture(this.name, this.pcm);

  final String name;
  final Float64List pcm;
}

class _ModelLoad {
  const _ModelLoad({
    required this.asset,
    required this.bytes,
    required this.readAndParseMicroseconds,
    required this.weights,
  });

  final String asset;
  final int bytes;
  final int readAndParseMicroseconds;
  final Uint8List weights;

  Map<String, Object> toJson() => {
    'asset': asset,
    'bytes': bytes,
    'readAndParseMicroseconds': readAndParseMicroseconds,
  };
}

class _FixtureResult {
  const _FixtureResult({
    required this.name,
    required this.analysisMicroseconds,
    required this.durationSec,
    required this.bpm,
    required this.strumCount,
    required this.chordSegmentCount,
    required this.chordTimeline,
    required this.modelAssetBytes,
  });

  final String name;
  final int analysisMicroseconds;
  final double durationSec;
  final double bpm;
  final int strumCount;
  final int chordSegmentCount;
  final List<Map<String, Object>> chordTimeline;
  final int modelAssetBytes;

  Map<String, Object> toJson() => {
    'name': name,
    'analysisMicroseconds': analysisMicroseconds,
    'durationSec': durationSec,
    'bpm': bpm,
    'strumCount': strumCount,
    'chordSegmentCount': chordSegmentCount,
    'chordTimeline': chordTimeline,
    'modelAssetBytes': modelAssetBytes,
  };

  Map<String, Object> toDeterminismJson() => {
    'name': name,
    'durationSec': durationSec,
    'bpm': bpm,
    'strumCount': strumCount,
    'chordSegmentCount': chordSegmentCount,
    'chordTimeline': chordTimeline,
    'modelAssetBytes': modelAssetBytes,
  };
}
