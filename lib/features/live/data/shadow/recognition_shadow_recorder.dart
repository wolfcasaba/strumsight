import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../../../app/config/recognition_rollout_stage.dart';
import '../../domain/recognition/recognition_mode.dart';
import '../../model/recognition_runtime_info.dart';
import 'shadow_metrics.dart';

/// The in-memory sink every shadow observer writes into (E14-R23, ADR 0548).
///
/// One recorder per shadow session. It owns EVERY allocation the shadow path
/// makes after construction:
///
/// * two fixed-capacity [ShadowRingBuffer]s of recent samples;
/// * one dense [Int32List] chord confusion matrix (26×26);
/// * one dense [Int32List] latency histogram.
///
/// Nothing here grows with the length of the session — the ten-minute
/// stream the SDD Ch14 Kör 22 memory question is about costs exactly the
/// same bytes as the first second. That is a STRUCTURAL claim, pinned by
/// `shadow_allocation_bound_test.dart`; the DEVICE memory measurement it
/// stands in for is still NEEDS-MEASUREMENT.
///
/// The recorder holds no audio, no PCM, no feature frame and no raw label
/// history beyond the bounded ring: a shadow report is counts plus a short
/// tail of comparisons, never a recording.
class RecognitionShadowRecorder {
  RecognitionShadowRecorder({
    this.ringCapacity = ShadowRingBuffer.defaultCapacity,
  }) : _strumRing = ShadowRingBuffer<StrumShadowSample>(
         capacity: ringCapacity,
       ),
       _chordRing = ShadowRingBuffer<ChordShadowSample>(
         capacity: ringCapacity,
       ),
       _confusion = newChordConfusionMatrix(),
       _latency = Int32List(ShadowLatencyBucket.values.length);

  final int ringCapacity;

  final ShadowRingBuffer<StrumShadowSample> _strumRing;
  final ShadowRingBuffer<ChordShadowSample> _chordRing;
  final Int32List _confusion;
  final Int32List _latency;

  int _strumFrames = 0;
  int _strumCandidateVerdicts = 0;
  int _strumCompared = 0;
  int _strumAgreed = 0;
  int _strumDisagreed = 0;
  int _strumCandidateAbstained = 0;
  int _strumProductionAbstained = 0;
  int _strumBothAbstained = 0;
  int _strumCandidateUnavailable = 0;

  int _chordFrames = 0;
  int _chordCompared = 0;
  int _chordExactAgreed = 0;
  int _chordRootAgreed = 0;
  int _chordQualityAgreed = 0;
  int _chordBothNoChord = 0;
  int _chordProductionNoChordOnly = 0;
  int _chordCandidateNoChordOnly = 0;
  int _chordCandidateUnavailable = 0;

  /// One emitted frame passed the strum observer.
  void noteStrumFrame() => _strumFrames++;

  /// The frame carried no candidate verdict at all (the heuristic strum path
  /// is running). Counted separately from an abstention: "the model was not
  /// there" is not "the model declined".
  void noteStrumCandidateUnavailable() => _strumCandidateUnavailable++;

  void recordStrum(StrumShadowSample sample) {
    _strumCandidateVerdicts++;
    _latency[sample.latency.index]++;
    switch (sample.agreement) {
      case ShadowAgreement.agreed:
        _strumCompared++;
        _strumAgreed++;
      case ShadowAgreement.disagreed:
        _strumCompared++;
        _strumDisagreed++;
      case ShadowAgreement.candidateAbstained:
        _strumCandidateAbstained++;
      case ShadowAgreement.productionAbstained:
        _strumProductionAbstained++;
      case ShadowAgreement.bothAbstained:
        _strumBothAbstained++;
    }
    _strumRing.add(sample);
  }

  /// One emitted frame passed the chord observer.
  void noteChordFrame() => _chordFrames++;

  /// The chord CRNN had no verdict for this frame (window not filled, or it
  /// never activated).
  void noteChordCandidateUnavailable() => _chordCandidateUnavailable++;

  void recordChord(ChordShadowSample sample) {
    _chordCompared++;
    final production = sample.production;
    final candidate = sample.candidate;
    _confusion[production.index * ShadowChordClass.classCount +
        candidate.index]++;
    if (production == candidate) _chordExactAgreed++;
    if (production.rootIndex == candidate.rootIndex) _chordRootAgreed++;
    if (production.quality == candidate.quality) _chordQualityAgreed++;
    final productionSilent = production.quality == ShadowChordQuality.noChord;
    final candidateSilent = candidate.quality == ShadowChordQuality.noChord;
    if (productionSilent && candidateSilent) {
      _chordBothNoChord++;
    } else if (productionSilent) {
      _chordProductionNoChordOnly++;
    } else if (candidateSilent) {
      _chordCandidateNoChordOnly++;
    }
    _chordRing.add(sample);
  }

  StrumShadowAggregate get strumAggregate => StrumShadowAggregate(
    observedFrames: _strumFrames,
    candidateVerdicts: _strumCandidateVerdicts,
    comparedVerdicts: _strumCompared,
    agreed: _strumAgreed,
    disagreed: _strumDisagreed,
    candidateAbstained: _strumCandidateAbstained,
    productionAbstained: _strumProductionAbstained,
    bothAbstained: _strumBothAbstained,
    candidateUnavailableFrames: _strumCandidateUnavailable,
    latencyHistogram: <ShadowLatencyBucket, int>{
      for (final bucket in ShadowLatencyBucket.values)
        if (_latency[bucket.index] > 0) bucket: _latency[bucket.index],
    },
  );

  ChordShadowAggregate get chordAggregate => ChordShadowAggregate(
    observedFrames: _chordFrames,
    comparedFrames: _chordCompared,
    exactAgreed: _chordExactAgreed,
    rootAgreed: _chordRootAgreed,
    qualityAgreed: _chordQualityAgreed,
    bothNoChord: _chordBothNoChord,
    productionNoChordOnly: _chordProductionNoChordOnly,
    candidateNoChordOnly: _chordCandidateNoChordOnly,
    candidateUnavailableFrames: _chordCandidateUnavailable,
    confusion: _confusion,
  );

  /// Builds the immutable report. [strumStage]/[chordStage] and the two
  /// enabled flags are recorded so a report can never be read out of its
  /// rollout context (a shadow number and an alpha number are not the same
  /// measurement).
  RecognitionShadowSnapshot snapshot({
    required RecognitionMode mode,
    required bool strumShadowEnabled,
    required bool chordShadowEnabled,
    required RecognitionRolloutStage strumStage,
    required RecognitionRolloutStage chordStage,
    FallbackReason? chordFallbackReason,
  }) => RecognitionShadowSnapshot(
    mode: mode,
    strumShadowEnabled: strumShadowEnabled,
    chordShadowEnabled: chordShadowEnabled,
    strumStage: strumStage,
    chordStage: chordStage,
    chordFallbackReason: chordFallbackReason,
    strum: strumAggregate,
    chord: chordAggregate,
    strumSamples: _strumRing.toList(),
    chordSamples: _chordRing.toList(),
    ringCapacity: ringCapacity,
    droppedStrumSamples: _strumRing.dropped,
    droppedChordSamples: _chordRing.dropped,
  );

  /// The number of shadow sample objects the recorder is holding on to. A
  /// test asserts this stops growing once the rings are full — the
  /// allocation bound R22 asks about, measured by OBJECT COUNT rather than
  /// by a wall-clock or RSS reading this box cannot take.
  @visibleForTesting
  int get debugRetainedSampleCount => _strumRing.length + _chordRing.length;

  /// The allocated slot counts + the two dense counters. Constant for the
  /// life of the recorder.
  @visibleForTesting
  int get debugAllocatedSlotCount =>
      _strumRing.slotCount +
      _chordRing.slotCount +
      _confusion.length +
      _latency.length;
}

/// The immutable report a Lab surface renders and a diagnostics export
/// serialises.
@immutable
class RecognitionShadowSnapshot {
  const RecognitionShadowSnapshot({
    required this.mode,
    required this.strumShadowEnabled,
    required this.chordShadowEnabled,
    required this.strumStage,
    required this.chordStage,
    required this.chordFallbackReason,
    required this.strum,
    required this.chord,
    required this.strumSamples,
    required this.chordSamples,
    required this.ringCapacity,
    required this.droppedStrumSamples,
    required this.droppedChordSamples,
  });

  /// What a build with both gates closed reports: no counts, no samples, and
  /// — the point of the whole gate — no inference was run to produce it.
  RecognitionShadowSnapshot.disabled({required this.mode})
    : strumShadowEnabled = false,
      chordShadowEnabled = false,
      strumStage = RecognitionRolloutStage.off,
      chordStage = RecognitionRolloutStage.off,
      chordFallbackReason = null,
      strum = StrumShadowAggregate.empty,
      chord = _emptyChordAggregate,
      strumSamples = const <StrumShadowSample>[],
      chordSamples = const <ChordShadowSample>[],
      ringCapacity = 0,
      droppedStrumSamples = 0,
      droppedChordSamples = 0;

  final RecognitionMode mode;
  final bool strumShadowEnabled;
  final bool chordShadowEnabled;
  final RecognitionRolloutStage strumStage;
  final RecognitionRolloutStage chordStage;

  /// Why the chord CRNN did not activate, or `null` when it did (or when the
  /// chord band was never asked to run). A typed code — never a swallowed
  /// exception.
  final FallbackReason? chordFallbackReason;

  final StrumShadowAggregate strum;
  final ChordShadowAggregate chord;
  final List<StrumShadowSample> strumSamples;
  final List<ChordShadowSample> chordSamples;
  final int ringCapacity;
  final int droppedStrumSamples;
  final int droppedChordSamples;

  /// True when at least one band ran. A `false` here plus non-zero counts
  /// would be a contradiction; the Lab renders the two together so it cannot
  /// be read as "the shadow said nothing".
  bool get ranAnything => strumShadowEnabled || chordShadowEnabled;

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'strumShadowEnabled': strumShadowEnabled,
    'chordShadowEnabled': chordShadowEnabled,
    'strumStage': strumStage.name,
    'chordStage': chordStage.name,
    'chordFallbackReason': chordFallbackReason?.name,
    'ringCapacity': ringCapacity,
    'droppedStrumSamples': droppedStrumSamples,
    'droppedChordSamples': droppedChordSamples,
    'strum': strum.toJson(),
    'chord': chord.toJson(),
    'strumSamples': [for (final s in strumSamples) s.toJson()],
    'chordSamples': [for (final s in chordSamples) s.toJson()],
  };
}

/// `ChordShadowAggregate` copies a list, so it cannot be `const`. The
/// disabled snapshot shares this one lazily-built empty instance instead of
/// allocating a fresh matrix-free aggregate per read.
final ChordShadowAggregate _emptyChordAggregate = ChordShadowAggregate.empty();
