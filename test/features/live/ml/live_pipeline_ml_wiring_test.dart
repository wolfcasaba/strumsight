import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/dsp/live_pipeline.dart';
import 'package:music_theory/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:music_theory/features/live/engine/ml/live_crnn_classifier.dart';

/// r169 — the live model reaches the DSP isolate: LivePipeline accepts the
/// weights BYTES (rootBundle is main-isolate-only; the engine loads them and
/// the isolate parses — the same pattern as the r165 Analyze wiring) and
/// puts the CRNN behind the r139 seam; anything invalid keeps the heuristic.
void main() {
  final bytes = Uint8List.fromList(
      File('assets/ml/strum_crnn_live.bin').readAsBytesSync());

  test('valid weights bytes put the live CRNN behind the seam', () {
    final p = LivePipeline(sampleRate: 44100, crnnWeights: bytes);
    expect(p.debugStrumClassifier, isA<LiveCrnnStrumClassifier>());
  });

  test('no bytes -> heuristic (mock mode, stripped builds)', () {
    final p = LivePipeline(sampleRate: 44100);
    expect(p.debugStrumClassifier, isA<HeuristicStrumClassifier>());
  });

  test('garbage bytes -> heuristic, never a crash (model is an upgrade)', () {
    final p = LivePipeline(sampleRate: 44100, crnnWeights: Uint8List(16));
    expect(p.debugStrumClassifier, isA<HeuristicStrumClassifier>());
  });
}
