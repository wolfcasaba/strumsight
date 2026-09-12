import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/live/engine/dsp/dsp_config.dart';
import 'package:strumsight/features/live/engine/dsp/strum_analyzer.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/engine/ml/live_crnn_classifier.dart';

import '../../../support/synth.dart';

/// A classifier WITH a settled tier, under the test's control: the first
/// `classifyAt` for an onset is the fast verdict, the second is the settled one.
class _TwoTierClassifier implements StrumDirectionClassifier {
  _TwoTierClassifier({
    required this.settleAfterFrames,
    required this.fast,
    required this.settled,
  });

  @override
  final int? settleAfterFrames;

  final StrumClassification Function(int onsetFrame) fast;
  final StrumClassification Function(int onsetFrame) settled;

  final List<({int onsetFrame, int currentFrame, bool isSettled})> calls = [];
  final Map<int, int> _seen = {};

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) {
    final before = _seen[onsetFrame] ?? 0;
    _seen[onsetFrame] = before + 1;
    calls.add((
      onsetFrame: onsetFrame,
      currentFrame: currentFrame,
      isSettled: before > 0,
    ));
    return before == 0 ? fast(onsetFrame) : settled(onsetFrame);
  }
}

StrumClassification _down({bool suppressed = false}) => StrumClassification(
  direction: suppressed ? null : StrumDirection.down,
  confidence: suppressed ? 0 : 0.8,
  suppressed: suppressed,
  pDown: 0.8,
  pUp: 0.2,
  pNoStrum: suppressed ? 0.99 : 0.01,
);

StrumClassification _up() => const StrumClassification(
  direction: StrumDirection.up,
  confidence: 0.9,
  pDown: 0.1,
  pUp: 0.9,
  pNoStrum: 0.01,
);

/// Everything [StrumAnalyzer] produced over one signal.
({List<StrumEvent> events, List<StrumRevision> revisions, int bothFrames}) _run(
  Float64List signal,
  StrumDirectionClassifier classifier, {
  int sampleRate = 44100,
}) {
  final analyzer = StrumAnalyzer(
    sampleRate: sampleRate,
    classifier: classifier,
    // Opt in explicitly: the tier is off by default so an unconsumed second
    // model forward cannot ship (see [StrumAnalyzer.settledTier]).
    settledTier: true,
  );
  final events = <StrumEvent>[];
  final revisions = <StrumRevision>[];
  var bothFrames = 0;
  for (
    var start = 0;
    start + DspConfig.onsetWindow <= signal.length;
    start += DspConfig.onsetHop
  ) {
    final event = analyzer.process(
      Float64List.sublistView(signal, start, start + DspConfig.onsetWindow),
    );
    final revision = analyzer.settledRevision;
    if (event != null) events.add(event);
    if (revision != null) revisions.add(revision);
    if (event != null && revision != null) bothFrames++;
  }
  return (events: events, revisions: revisions, bothFrames: bothFrames);
}

void main() {
  group('the settled instant is DERIVED, and the window is really complete', () {
    // The settled tier only means anything if, at its instant, the model's whole
    // window has arrived. If it fired early the verdict would run on the same
    // zero-padded tail the fast tier already had, and the +0.08 macro-F1 the tier
    // is justified by would not exist (ADR 0552/0554).
    const sampleRate = 44100;
    const hop = DspConfig.onsetHop;
    const window = DspConfig.onsetWindow;

    test('framesUntilComplete is derived from the model geometry', () {
      final frontend = LiveCrnnFrontend(sampleRate: sampleRate);
      // Pinned so a change to preFrames/postFrames/modelHop/nFft shows up here as
      // a failing expectation rather than as a silently shorter wait.
      expect(frontend.framesUntilComplete, 41);
      expect(
        frontend.framesUntilComplete * hop / sampleRate,
        closeTo(0.238, 0.003),
      );
    });

    test('at the settled instant the streamed window equals the reference', () {
      final signal = strumSignal(
        lowFirst: true,
        seconds: 1.2,
        sampleRate: sampleRate,
      );
      final frontend = LiveCrnnFrontend(sampleRate: sampleRate);
      final settleAfter = frontend.framesUntilComplete;
      const onsetFrame = 30;
      final lastFrame = onsetFrame + settleAfter;
      expect(lastFrame * hop + window, lessThan(signal.length));

      for (var f = 0; f <= lastFrame; f++) {
        frontend.observe(
          Float64List.sublistView(signal, f * hop, f * hop + window),
        );
      }
      final streamed = frontend.windowAt(onsetFrame, lastFrame);
      final reference = LiveCrnnFrontend.referenceWindow(
        Float64List.sublistView(signal, 0, lastFrame * hop + window),
        sampleRate,
        onsetFrame * hop / sampleRate,
      );
      expect(streamed.length, reference.length);
      for (var r = 0; r < streamed.length; r++) {
        for (var c = 0; c < streamed[r].length; c++) {
          expect(streamed[r][c], closeTo(reference[r][c], 1e-9));
        }
      }
    });

    test('at the FAST instant the tail is still zero-padded', () {
      // The other half of the claim: the truncation the settled tier removes is
      // real. 70 ms after the onset the window's last row covers onset+110 ms to
      // onset+238 ms, none of which exists yet, so it is the log-mel of silence —
      // one constant value across all 128 mels.
      final signal = strumSignal(
        lowFirst: true,
        seconds: 1.2,
        sampleRate: sampleRate,
      );
      final frontend = LiveCrnnFrontend(sampleRate: sampleRate);
      const onsetFrame = 30;
      const fastFrame = onsetFrame + 12;
      for (var f = 0; f <= fastFrame; f++) {
        frontend.observe(
          Float64List.sublistView(signal, f * hop, f * hop + window),
        );
      }
      final fast = frontend.windowAt(onsetFrame, fastFrame);
      final lastRow = fast.last;
      expect(lastRow.every((v) => (v - lastRow.first).abs() < 1e-12), isTrue);

      final settled = LiveCrnnFrontend(sampleRate: sampleRate);
      final settleFrame = onsetFrame + settled.framesUntilComplete;
      for (var f = 0; f <= settleFrame; f++) {
        settled.observe(
          Float64List.sublistView(signal, f * hop, f * hop + window),
        );
      }
      final settledRow = settled.windowAt(onsetFrame, settleFrame).last;
      expect(
        settledRow.every((v) => (v - settledRow.first).abs() < 1e-12),
        isFalse,
        reason: 'the settled row must carry real audio, not silence',
      );
    });
  });

  group('the tier is DARK by default', () {
    test('without opting in, no revision is ever produced', () {
      // The guard that keeps an unconsumed computation off a learner's phone.
      // With the live CRNN behind the seam, settleAfterFrames is 41, so enabling
      // the tier means a SECOND model forward per strum. Measured on this JIT test
      // harness one forward is ~29 ms; the AOT on-device figure is NOT measured and
      // the two are not comparable, which is precisely why the tier stays off until
      // the round that both consumes the revision and measures the cost in a
      // profile build (ADR 0558 D1).
      final classifier = _TwoTierClassifier(
        settleAfterFrames: 41,
        fast: (_) => _down(),
        settled: (_) => _up(),
      );
      final analyzer = StrumAnalyzer(sampleRate: 44100, classifier: classifier);
      final signal = strumSignal(lowFirst: true, seconds: 1.2);
      var events = 0;
      for (
        var start = 0;
        start + DspConfig.onsetWindow <= signal.length;
        start += DspConfig.onsetHop
      ) {
        if (analyzer.process(
              Float64List.sublistView(
                signal,
                start,
                start + DspConfig.onsetWindow,
              ),
            ) !=
            null) {
          events++;
        }
        expect(analyzer.settledRevision, isNull);
      }
      expect(events, greaterThan(0), reason: 'the fast tier must still work');
      // One call per strum, never two: the second forward is not merely ignored,
      // it is never issued.
      expect(classifier.calls.every((c) => !c.isSettled), isTrue);
      expect(classifier.calls, hasLength(events));
    });
  });

  group('hazard 1 — a revision must NOT create a strum', () {
    test('one onset yields one event and one revision, never two events', () {
      final classifier = _TwoTierClassifier(
        settleAfterFrames: 41,
        fast: (_) => _down(),
        settled: (_) => _up(),
      );
      final result = _run(
        strumSignal(lowFirst: true, seconds: 1.2),
        classifier,
      );

      expect(result.events, hasLength(1), reason: 'exactly one strum happened');
      expect(result.revisions, hasLength(1));
      // The revision names the SAME strum, and arrives later than the event.
      expect(
        result.revisions.single.onsetFrame,
        result.events.single.onsetFrame,
      );
      expect(result.revisions.single.timeSec, result.events.single.timeSec);
      // The fast verdict is what the event carried; the settled one differs, and
      // that difference reaching the event would be the flip ADR 0556 D1 forbids.
      expect(result.events.single.direction, StrumDirection.down);
      expect(result.revisions.single.direction, StrumDirection.up);
      // Two calls for one onset: fast then settled, the second strictly later.
      expect(classifier.calls, hasLength(2));
      expect(classifier.calls[0].isSettled, isFalse);
      expect(classifier.calls[1].isSettled, isTrue);
      expect(
        classifier.calls[1].currentFrame - classifier.calls[0].currentFrame,
        41 - 12,
      );
    });

    test('the heuristic path emits NO revisions at all', () {
      // settleAfterFrames == null must leave the analyzer exactly as it was.
      final result = _run(
        strumSignal(lowFirst: true, seconds: 1.2),
        HeuristicStrumClassifier(),
      );
      expect(result.events, isNotEmpty);
      expect(result.revisions, isEmpty);
    });
  });

  group('hazard 2 — a revision must NOT overwrite a NEWER stroke', () {
    test('with several strokes in flight, revisions match by onset frame', () {
      // 100 ms apart is ~17 analyzer frames while settling takes 41, so more than
      // one stroke is genuinely in flight. The precondition is asserted rather
      // than assumed: if the onset detector merged the strokes, this test would
      // otherwise pass while exercising nothing.
      final classifier = _TwoTierClassifier(
        settleAfterFrames: 41,
        fast: (_) => _down(),
        settled: (_) => _up(),
      );
      final result = _run(
        strumPattern(
          lowFirstPerStrum: const [true, false, true, false, true],
          gapSeconds: 0.1,
        ),
        classifier,
      );

      expect(
        result.events.length,
        greaterThanOrEqualTo(3),
        reason: 'the overlap scenario must actually be exercised',
      );
      expect(result.revisions, hasLength(result.events.length));

      // Every revision names its own stroke, in the order the strokes were
      // reported — so a consumer matching on onsetFrame can never apply a
      // revision to a stroke that arrived afterwards.
      for (final (index, revision) in result.revisions.indexed) {
        expect(
          revision.onsetFrame,
          result.events[index].onsetFrame,
          reason: 'revision $index must name event $index',
        );
      }
      // And the frames are strictly increasing, so no two revisions collide.
      final frames = result.revisions.map((r) => r.onsetFrame).toList();
      for (var i = 1; i < frames.length; i++) {
        expect(frames[i], greaterThan(frames[i - 1]));
      }
      // The onset frames are close enough together that a float-time match with a
      // plausible epsilon would have been ambiguous — which is why the identity is
      // an integer frame index.
      expect(frames[1] - frames[0], lessThan(41));
    });
  });

  group('hazard 3 — a SUPPRESSED onset must never come back', () {
    test('a suppressed fast verdict produces no event and no revision', () {
      final classifier = _TwoTierClassifier(
        settleAfterFrames: 41,
        fast: (_) => _down(suppressed: true),
        settled: (_) => _up(),
      );
      final result = _run(
        strumPattern(
          lowFirstPerStrum: const [true, false, true],
          gapSeconds: 0.25,
        ),
        classifier,
      );
      expect(result.events, isEmpty);
      expect(
        result.revisions,
        isEmpty,
        reason: 'a suppressed onset must not be queued for settling',
      );
      // The seam was still consulted once per onset — suppression is a decision,
      // not a bypass — but never a second time.
      expect(classifier.calls, isNotEmpty);
      expect(classifier.calls.every((c) => !c.isSettled), isTrue);
    });

    test('a SETTLED suppression does not retract an already-reported strum', () {
      // The mirror case. Existence was decided at the fast deadline and an event
      // has already reached every consumer; deleting it would remove a stroke the
      // learner saw. The settled tier revises direction, never existence — so the
      // event stands and simply gets no revision.
      final classifier = _TwoTierClassifier(
        settleAfterFrames: 41,
        fast: (_) => _down(),
        settled: (_) => _down(suppressed: true),
      );
      final result = _run(
        strumSignal(lowFirst: true, seconds: 1.2),
        classifier,
      );
      expect(result.events, hasLength(1));
      expect(result.events.single.direction, StrumDirection.down);
      expect(result.revisions, isEmpty);
      expect(classifier.calls, hasLength(2));
      expect(classifier.calls[1].isSettled, isTrue);
    });
  });

  group('both tiers can come due on the same frame', () {
    test('a settled verdict and a fast verdict coexist in one process call', () {
      // The early return in the fast branch would swallow the settled verdict if
      // the queues were drained in the other order, so the collision has to be
      // provoked on purpose. A stroke's FAST verdict comes due 12 frames after its
      // onset and its SETTLED verdict 41 frames after, so two strokes collide when
      // `B.onset + 12 == A.onset + 41` — a gap of 29 frames, not 41.
      //
      // The onset detector places its peak frame itself, so the realised gap can
      // land a frame either side of the intended one. Rather than assert on a
      // single gap and hope, the neighbourhood is swept and the collision is
      // required to occur at least once; the gap that produced it is reported so a
      // future regression says which case stopped working.
      const settleAfter = 41;
      const fastAfter = 12;
      final collided = <int>[];
      for (final gapFrames in [
        settleAfter - fastAfter - 1,
        settleAfter - fastAfter,
        settleAfter - fastAfter + 1,
      ]) {
        final classifier = _TwoTierClassifier(
          settleAfterFrames: settleAfter,
          fast: (_) => _down(),
          settled: (_) => _up(),
        );
        final result = _run(
          strumPattern(
            lowFirstPerStrum: const [true, false, true, false, true, false],
            gapSeconds: gapFrames * DspConfig.onsetHop / 44100,
          ),
          classifier,
        );
        // Whatever the gap, the bookkeeping must hold: one revision per reported
        // stroke, and nothing lost to the early return.
        expect(
          result.events.length,
          greaterThanOrEqualTo(3),
          reason: 'gap $gapFrames frames: the overlap must be exercised',
        );
        expect(
          result.revisions,
          hasLength(result.events.length),
          reason: 'gap $gapFrames frames: every stroke must settle',
        );
        if (result.bothFrames > 0) collided.add(gapFrames);
      }
      expect(
        collided,
        isNotEmpty,
        reason:
            'no gap produced a same-frame collision, so the ordering of the '
            'two queues was never actually tested',
      );
    });
  });
}
