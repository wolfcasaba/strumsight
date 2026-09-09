// E14-R23 — what the strum shadow observer actually measures.
//
// These cells drive the observer DIRECTLY with hand-built frames and
// predictions, so the comparison rules are pinned independently of whatever
// the DSP happens to produce for a synthetic signal.
//
// RED before this round: `StrumShadowObserver` did not exist.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/recognition_rollout_stage.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_observers.dart';
import 'package:strumsight/features/live/data/shadow/recognition_shadow_recorder.dart';
import 'package:strumsight/features/live/data/shadow/shadow_metrics.dart';
import 'package:strumsight/features/live/domain/recognition/recognition_mode.dart';
import 'package:strumsight/features/live/domain/recognition/strum_prediction.dart';
import 'package:strumsight/features/live/model/live_frame.dart';

LiveFrame _frame({Strum? strum, int seq = 0, double engineTimeSec = 1.0}) =>
    LiveFrame(
      current: null,
      next: null,
      latestStrum: strum,
      bar: const [],
      bpm: 100,
      inputLevel: 0.4,
      tuningHz: 440,
      listening: true,
      strumSeq: seq,
      engineTimeSec: engineTimeSec,
    );

StrumPrediction _prediction({
  required double pDown,
  required double pUp,
  double pNoStrum = 0.0,
  double onsetTimeSec = 1.0,
  double verdictTimeSec = 1.03,
}) => StrumPrediction(
  onsetTimeSec: onsetTimeSec,
  verdictTimeSec: verdictTimeSec,
  pDown: pDown,
  pUp: pUp,
  pNoStrum: pNoStrum,
  calibratedConfidence: null,
  modelId: 'test-model',
);

void _feed(
  StrumShadowObserver observer,
  LiveFrame frame,
  StrumPrediction? strum,
) => observer.onRecognitionFrame(
  mode: RecognitionMode.free,
  frame: frame,
  chord: null,
  strum: strum,
);

void main() {
  test('a frame with no model verdict is UNAVAILABLE, not an abstention', () {
    final recorder = RecognitionShadowRecorder();
    final observer = StrumShadowObserver(recorder);
    _feed(observer, _frame(), null);
    _feed(observer, _frame(), null);

    final aggregate = recorder.strumAggregate;
    expect(aggregate.observedFrames, 2);
    expect(aggregate.candidateUnavailableFrames, 2);
    expect(aggregate.candidateVerdicts, 0);
    expect(aggregate.agreementRate, isNull);
  });

  test('a verdict held across frames is counted ONCE', () {
    final recorder = RecognitionShadowRecorder();
    final observer = StrumShadowObserver(recorder);
    final prediction = _prediction(pDown: 0.9, pUp: 0.1);
    final strum = const Strum(direction: StrumDirection.down, confidence: 0.9);

    _feed(observer, _frame(strum: strum, seq: 1), prediction);
    _feed(observer, _frame(strum: strum, seq: 1), prediction);
    _feed(observer, _frame(strum: strum, seq: 1), prediction);

    final aggregate = recorder.strumAggregate;
    expect(aggregate.observedFrames, 3);
    expect(aggregate.candidateVerdicts, 1);
    expect(aggregate.comparedVerdicts, 1);
    expect(aggregate.agreed, 1);
    expect(aggregate.agreementRate, 1.0);
  });

  test('a disagreement is recorded as a disagreement', () {
    final recorder = RecognitionShadowRecorder();
    final observer = StrumShadowObserver(recorder);
    _feed(
      observer,
      _frame(
        strum: const Strum(direction: StrumDirection.up, confidence: 0.6),
        seq: 1,
      ),
      _prediction(pDown: 0.95, pUp: 0.05),
    );

    final aggregate = recorder.strumAggregate;
    expect(aggregate.disagreed, 1);
    expect(aggregate.agreed, 0);
    expect(aggregate.agreementRate, 0.0);
  });

  test('the no-strum class and a thin margin both count as an ABSTENTION', () {
    final recorder = RecognitionShadowRecorder();
    final observer = StrumShadowObserver(recorder);
    final published = const Strum(
      direction: StrumDirection.down,
      confidence: 0.7,
    );

    // The learned no-strum class wins.
    _feed(
      observer,
      _frame(strum: published, seq: 1),
      _prediction(pDown: 0.3, pUp: 0.2, pNoStrum: 0.5, onsetTimeSec: 1.0),
    );
    // The down/up margin is inside StrumPrediction's uncertainty band.
    _feed(
      observer,
      _frame(strum: published, seq: 2),
      _prediction(pDown: 0.5, pUp: 0.48, onsetTimeSec: 2.0),
    );

    final aggregate = recorder.strumAggregate;
    expect(aggregate.candidateVerdicts, 2);
    expect(aggregate.candidateAbstained, 2);
    expect(aggregate.comparedVerdicts, 0);
    expect(
      aggregate.agreementRate,
      isNull,
      reason: 'two abstentions are not a 0% agreement rate',
    );
    expect(aggregate.candidateAbstentionRate, 1.0);
  });

  test('production publishing nothing new is PRODUCTION-abstained', () {
    final recorder = RecognitionShadowRecorder();
    final observer = StrumShadowObserver(recorder);
    // seq never advances → the pipeline suppressed this onset's direction.
    _feed(observer, _frame(seq: 0), _prediction(pDown: 0.9, pUp: 0.1));
    _feed(
      observer,
      _frame(seq: 0),
      _prediction(pDown: 0.05, pUp: 0.9, onsetTimeSec: 2.0),
    );

    final aggregate = recorder.strumAggregate;
    expect(aggregate.productionAbstained, 2);
    expect(aggregate.comparedVerdicts, 0);
  });

  test('latency is bucketed from the two clocks, unusable stays unknown', () {
    final recorder = RecognitionShadowRecorder();
    final observer = StrumShadowObserver(recorder);
    _feed(
      observer,
      _frame(
        strum: const Strum(direction: StrumDirection.down, confidence: 0.9),
        seq: 1,
      ),
      _prediction(
        pDown: 0.9,
        pUp: 0.1,
        onsetTimeSec: 1.0,
        verdictTimeSec: 1.07,
      ),
    );
    _feed(
      observer,
      _frame(
        strum: const Strum(direction: StrumDirection.down, confidence: 0.9),
        seq: 2,
      ),
      _prediction(
        pDown: 0.9,
        pUp: 0.1,
        onsetTimeSec: -1,
        verdictTimeSec: -1,
      ),
    );

    final histogram = recorder.strumAggregate.latencyHistogram;
    expect(histogram[ShadowLatencyBucket.under100ms], 1);
    expect(histogram[ShadowLatencyBucket.unknown], 1);
  });

  test('the sample ring keeps the newest comparisons and says so', () {
    final recorder = RecognitionShadowRecorder(ringCapacity: 2);
    final observer = StrumShadowObserver(recorder);
    for (var i = 0; i < 5; i++) {
      _feed(
        observer,
        _frame(
          strum: const Strum(direction: StrumDirection.down, confidence: 0.9),
          seq: i + 1,
        ),
        _prediction(pDown: 0.9, pUp: 0.1, onsetTimeSec: i.toDouble()),
      );
    }
    final snapshot = recorder.snapshot(
      mode: RecognitionMode.free,
      strumShadowEnabled: true,
      chordShadowEnabled: false,
      strumStage: RecognitionRolloutStage.shadow,
      chordStage: RecognitionRolloutStage.off,
    );
    expect(snapshot.strumSamples.length, 2);
    expect(snapshot.strumSamples.first.onsetTimeSec, 3.0);
    expect(snapshot.droppedStrumSamples, 3);
    expect(
      snapshot.strum.candidateVerdicts,
      5,
      reason: 'the COUNTS cover the whole session, only the ring is a window',
    );
  });
}
