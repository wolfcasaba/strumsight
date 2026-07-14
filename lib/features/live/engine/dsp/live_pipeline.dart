import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../model/chord.dart';
import '../../model/live_frame.dart';
import '../../model/strum.dart';
import '../ml/crnn_strum_net.dart';
import '../ml/live_crnn_classifier.dart';
import 'chord_dictionary.dart';
import 'chord_matcher.dart';
import 'dsp_config.dart';
import 'nnls_chroma.dart';
import 'sliding_framer.dart';
import 'strum_analyzer.dart';
import 'strum_direction_classifier.dart';
import 'tempo_tracker.dart';
import 'viterbi_chord_decoder.dart';

StrumDirectionClassifier? _tryLiveCrnn(Uint8List? weights, int sampleRate) {
  if (weights == null) return null;
  try {
    return LiveCrnnStrumClassifier(
      CrnnStrumNet.parse(ByteData.sublistView(weights)),
      sampleRate: sampleRate,
    );
  } catch (_) {
    return null; // fall back to the heuristic, never fail the pipeline
  }
}

/// The REAL detection pipeline: PCM chunks in → [LiveFrame]s out (~15 Hz).
///
/// Pure Dart, deterministic (sample-count clock, no wall time), platform-free
/// — the isolate and mic are plumbing around this class, and tests drive it
/// directly with synthesized PCM (RAG chunk 010).
class LivePipeline {
  LivePipeline({
    required this.sampleRate,
    Uint8List? crnnWeights,
    double? chordConfRise,
    double? chordConfRelease,
  })  : _chordConfRise = chordConfRise ?? DspConfig.chordConfRise,
        _chordConfRelease = chordConfRelease ?? DspConfig.chordConfRelease,
        _chroma = NnlsChroma(sampleRate: sampleRate, window: DspConfig.nnlsWindow),
        _strums = StrumAnalyzer(
          sampleRate: sampleRate,
          // The live 70 ms model behind the r139 seam (r169): the engine
          // hands the weights-asset BYTES across the isolate boundary
          // (rootBundle is main-isolate-only, same pattern as the r165
          // Analyze wiring); null/unparseable keeps the heuristic — the
          // model is an upgrade, never a dependency.
          classifier: _tryLiveCrnn(crnnWeights, sampleRate),
        ),
        _chordFramer = SlidingFramer(
          window: DspConfig.nnlsWindow,
          hop: DspConfig.nnlsHop,
        ),
        _onsetFramer = SlidingFramer(
          window: DspConfig.onsetWindow,
          hop: DspConfig.onsetHop,
        ),
        _emitEverySamples = (sampleRate * 0.066).round();

  final int sampleRate;

  /// The musical-presence gate (round 176): a Schmitt trigger on the
  /// EMA-smoothed chord-match confidence. A chord is surfaced to the UI once
  /// the smoothed confidence rises past [_chordConfRise] and held until it
  /// falls below [_chordConfRelease] — so voiced speech (weak, ambiguous, spiky
  /// chord matches) never latches and the screen shows nothing instead of
  /// jumping between phantom chords, while a real guitar chord latches on the
  /// strum and rings out. Injectable so the offline probe can sweep it.
  final double _chordConfRise;
  final double _chordConfRelease;
  double _chordConfEma = 0;
  bool _chordLatched = false;

  final NnlsChroma _chroma;
  final ViterbiChordDecoder _chordDecoder = ViterbiChordDecoder(
    selfBonus: DspConfig.chordSelfTransitionBonus,
    dictionary: ChordDictionary(
      bassWeight: DspConfig.chordBassWeight,
      trebleWeight: DspConfig.chordTrebleWeight,
      noChordScore: DspConfig.chordNoChordScore,
    ),
  );
  final StrumAnalyzer _strums;

  static final Float64List _silentChroma = Float64List(12);
  final TempoTracker _tempo = TempoTracker();
  final SlidingFramer _chordFramer;
  final SlidingFramer _onsetFramer;

  final int _emitEverySamples;
  int _samplesSeen = 0;
  int _lastEmitAt = 0;

  /// Hint the currently expected chord (or clear with null) — the Viterbi
  /// expected-target prior (chunk 016, round 137).
  void setExpectedChord(String? label) => _chordDecoder.setExpected(label);

  ChordMatch? _lastChord;
  Strum? _latestStrum;
  double _latestStrumTime = -1;
  int _strumSeq = 0;
  final List<BeatSlot> _bar = _emptyBar();
  int _lastSlot = -1;
  double _barStartSec = -1;

  static const _labels = ['1', '&', '2', '&', '3', '&', '4', '&'];

  static List<BeatSlot> _emptyBar() => [
        for (var i = 0; i < 8; i++)
          BeatSlot(label: _labels[i], isDownbeat: i.isEven),
      ];

  /// Feed a PCM chunk (any length, -1..1). Returns the frames due for
  /// emission (usually 0 or 1).
  List<LiveFrame> addChunk(List<double> chunk) {
    final out = <LiveFrame>[];
    _samplesSeen += chunk.length;

    // Fast path: onsets + direction.
    for (final frame in _onsetFramer.add(chunk)) {
      final event = _strums.process(frame);
      // Onset-aligned chord updates (chunk 016, round 138): a fresh onset
      // relaxes the Viterbi switch penalty for the next couple of chord
      // frames — the chord changes ON the strum, stays stable between.
      if (_strums.onsetJustFired) _chordDecoder.noteOnset();
      if (event == null) continue;
      _tempo.addOnset(event.timeSec);
      if (event.direction != null) {
        _latestStrum = Strum(
          direction: event.direction!,
          confidence: event.confidence,
        );
        _latestStrumTime = event.timeSec;
        _strumSeq++; // a discrete new strum (for the play-along scorer)
        _placeInBar(event);
      }
    }

    // Slow path: chroma → chord. The NNLS transcription yields a bass+treble
    // (24-dim) chroma; the Viterbi decoder scores it against the chord-profile
    // dictionary and smooths the path (RAG chunk 012). Gate on tonalness so a
    // diffuse frame (speech, noise) is fed as silence and resolves to no-chord
    // rather than faking one (RAG chunk 003).
    for (final frame in _chordFramer.add(chunk)) {
      final chroma = _chroma.process(frame);
      final tonal =
          chroma != null && _chroma.lastTonalness >= DspConfig.chordMinTonalness;
      _lastChord = tonal
          ? _chordDecoder.process(
              _chroma.lastBassChroma, _chroma.lastTrebleChroma)
          : _chordDecoder.process(_silentChroma, _silentChroma, gated: true);
      // Musical-presence gate (round 176 probe): EMA-smooth the match
      // confidence so a sustained guitar chord builds up over the gate while a
      // brief speech spike cannot. A gated/no-chord frame feeds 0, decaying the
      // EMA back down so a phantom chord fades out.
      final conf = _lastChord?.confidence ?? 0.0;
      _chordConfEma += DspConfig.chordConfEmaAlpha * (conf - _chordConfEma);
      if (_chordConfEma >= _chordConfRise) {
        _chordLatched = true;
      } else if (_chordConfEma < _chordConfRelease) {
        _chordLatched = false;
      }
    }

    // Sample-clock emission (~15 Hz).
    if (_samplesSeen - _lastEmitAt >= _emitEverySamples) {
      _lastEmitAt = _samplesSeen;
      out.add(_buildFrame());
    }
    return out;
  }

  void _placeInBar(StrumEvent event) {
    final bpm = _tempo.bpm;
    int slot;
    if (bpm > 0) {
      final eighth = 60 / bpm / 2;
      if (_barStartSec < 0 || event.timeSec - _barStartSec >= 8 * eighth) {
        _barStartSec = event.timeSec;
        _clearBar();
      }
      slot = ((event.timeSec - _barStartSec) / eighth).round().clamp(0, 7);
    } else {
      slot = (_lastSlot + 1) % 8;
      if (slot == 0) _clearBar();
    }
    _lastSlot = slot;
    _bar[slot] = BeatSlot(
      label: _labels[slot],
      isDownbeat: slot.isEven,
      strum: _latestStrum,
    );
  }

  void _clearBar() {
    for (var i = 0; i < 8; i++) {
      _bar[i] = BeatSlot(label: _labels[i], isDownbeat: i.isEven);
    }
  }

  LiveFrame _buildFrame() {
    final nowSec = _samplesSeen / sampleRate;
    // The hero arrow fades out: drop the strum after 2 s without a new one.
    if (_latestStrum != null && nowSec - _latestStrumTime > 2.0) {
      _latestStrum = null;
    }
    final level = (_strums.lastRms * 8).clamp(0.0, 1.0).toDouble();
    // Only surface the chord once the smoothed match confidence clears the
    // musical-presence gate: below it we're almost certainly hearing speech /
    // noise, not a guitar, so show nothing rather than a phantom chord.
    final showChord = _lastChord != null && _chordLatched;
    return LiveFrame(
      current: showChord ? Chord(_lastChord!.chord.label) : null,
      next: null, // the real engine cannot know the future
      latestStrum: _latestStrum,
      bar: List.unmodifiable(_bar),
      bpm: _tempo.bpm,
      inputLevel: level,
      tuningHz: 440,
      listening: true,
      strumSeq: _strumSeq,
      latestStrumTime: _latestStrumTime,
      engineTimeSec: nowSec,
    );
  }

  /// Chord-match confidence (separate from the strum confidence the pill
  /// shows) — available for future UI use.
  double get chordConfidence => _lastChord?.confidence ?? 0;

  /// The most recent chroma tonalness (top-3 pitch-class energy) — the value
  /// the non-guitar gate tests. Exposed for the offline real-audio probe
  /// harness (`test/tools/real_audio_probe_test.dart`).
  @visibleForTesting
  double get debugTonalness => _chroma.lastTonalness;

  /// The EMA-smoothed chord-match confidence the musical-presence gate tests.
  @visibleForTesting
  double get debugChordConfEma => _chordConfEma;

  /// The strum classifier actually behind the seam (r169 wiring proof).
  @visibleForTesting
  StrumDirectionClassifier get debugStrumClassifier =>
      _strums.debugClassifier;

  void reset() {
    _chordFramer.reset();
    _onsetFramer.reset();
    _chordDecoder.reset();
    _tempo.reset();
    _lastChord = null;
    _chordConfEma = 0;
    _chordLatched = false;
    _latestStrum = null;
    _strumSeq = 0;
    _clearBar();
    _lastSlot = -1;
    _barStartSec = -1;
    _samplesSeen = 0;
    _lastEmitAt = 0;
  }
}
