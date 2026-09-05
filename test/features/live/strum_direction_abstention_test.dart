import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/engine/dsp/live_pipeline.dart';
import 'package:strumsight/features/live/engine/dsp/strum_direction_classifier.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/core/music/strum.dart';
// StrumPrediction is DSP/ML engine-adjacent domain, reached the same way
// every other cross-boundary read in this test tree reaches it: via the
// public barrel (ADR 0505 §0.0 R4 pattern), never the direct domain file.
import 'package:strumsight/features/live/public.dart' show StrumPrediction;

import '../../support/synth.dart';

const _sr = 44100;

/// Injects a FIXED verdict regardless of audio content — the onset detector
/// still runs for real on [strumSignal] (SuperFlux), only the direction
/// verdict behind the r139 seam is controlled, same pattern as
/// `strum_classifier_seam_test.dart`'s `_RecordingClassifier`.
class _FixedClassifier implements StrumDirectionClassifier {
  _FixedClassifier(this.verdict);
  final StrumClassification verdict;

  @override
  void observe(Float64List frame, StrumFrameFeatures features) {}

  @override
  StrumClassification classifyAt({
    required int onsetFrame,
    required int currentFrame,
  }) => verdict;
}

/// Feeds one real strum onset through [LivePipeline.debugWithClassifier] with
/// [verdict] as the fixed direction-classifier output, mic-chunked like every
/// other pipeline test in this tree.
List<LiveFrame> _runOneStrum(StrumClassification verdict) {
  final pipeline = LivePipeline.debugWithClassifier(
    _FixedClassifier(verdict),
    sampleRate: _sr,
  );
  final frames = <LiveFrame>[];
  final signal = strumSignal(lowFirst: true);
  for (var i = 0; i < signal.length; i += 1024) {
    final end = (i + 1024 < signal.length) ? i + 1024 : signal.length;
    frames.addAll(pipeline.addChunk(signal.sublist(i, end)));
  }
  return frames;
}

void main() {
  const t = StrumPrediction.uncertainMarginThreshold;

  group(
    'E14-R10: margin decision-trio reaches the live pipeline (ADR 0512 D6)',
    () {
      // Cellák (brief §6/2, ADR 0512 D6) — a "rajta" pár a KONSTANSBÓL
      // származik (2*T, T), NEM a naiv (0.525, 0.475)-tel, mert az utóbbi
      // IEEE-754-ben mérve 0.050000000000000044 -> confirmed lenne.
      test('below the threshold -> uncertain, no arrow ever surfaces', () {
        final frames = _runOneStrum(
          const StrumClassification(
            direction: StrumDirection.down,
            confidence: 0.7,
            pDown: 0.5245,
            pUp: 0.4755,
          ),
        );
        expect(frames, isNotEmpty);
        expect(frames.every((f) => f.latestStrum == null), isTrue);
        expect(
          frames.every((f) => f.latestStrumTime == -1),
          isTrue,
          reason:
              'an uncertain event must not advance the 2 s fade clock '
              '(ADR 0512 D4)',
        );
      });

      test('exactly on the threshold ((2*T, T), egzakt) -> uncertain', () {
        final pDown = 2 * t;
        final pUp = t;
        expect(
          pDown - pUp,
          0.05,
          reason: 'the (2*T, T) pair is the one EXACT double at the threshold',
        );
        final frames = _runOneStrum(
          StrumClassification(
            direction: StrumDirection.down,
            confidence: 0.7,
            pDown: pDown,
            pUp: pUp,
          ),
        );
        expect(frames.every((f) => f.latestStrum == null), isTrue);
        expect(frames.every((f) => f.latestStrumTime == -1), isTrue);
      });

      test('above the threshold -> confirmed, today\'s arrow behaviour', () {
        final frames = _runOneStrum(
          const StrumClassification(
            direction: StrumDirection.down,
            confidence: 0.81,
            pDown: 0.5255,
            pUp: 0.4745,
          ),
        );
        final withArrow = frames.where((f) => f.latestStrum != null).toList();
        expect(withArrow, isNotEmpty);
        expect(withArrow.first.latestStrum!.direction, StrumDirection.down);
        expect(withArrow.first.latestStrum!.confidence, 0.81);
        expect(frames.last.strumSeq, 1);
      });
    },
  );

  group('E14-R10: the heuristic branch never gets a fabricated probability '
      '(ADR 0512 D2)', () {
    test(
      'a probability-less StrumEvent keeps today\'s direct-arrow behaviour',
      () {
        final frames = _runOneStrum(
          const StrumClassification(
            direction: StrumDirection.up,
            confidence: 0.55,
            // pDown/pUp intentionally omitted -> null, the heuristic's own
            // shape (a fixed confidence ladder, never a probability).
          ),
        );
        final withArrow = frames.where((f) => f.latestStrum != null).toList();
        expect(
          withArrow,
          isNotEmpty,
          reason:
              'a null probability must not gain an abstention it never '
              'had before this round',
        );
        expect(withArrow.first.latestStrum!.direction, StrumDirection.up);
        expect(withArrow.first.latestStrum!.confidence, 0.55);
      },
    );
  });
}
