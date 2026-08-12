import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/target/expected_event.dart';
import 'package:strumsight/features/audio_analysis/engine/alignment/event_aligner.dart';
import 'package:strumsight/features/audio_analysis/engine/alignment/tolerance_policy.dart';

void main() {
  const policy = TolerancePolicy();
  const aligner = EventAligner(tolerancePolicy: policy);

  group('TolerancePolicy tempo-dependent clamp', () {
    test('120 BPM derives a 125 ms inclusive window', () {
      expect(
        policy.forBeatDuration(const Duration(milliseconds: 500)),
        const Duration(milliseconds: 125),
      );

      for (final delta in const <int>[124, 125]) {
        final result = aligner.align(
          observed: <AnalysisEvent>[_onset(delta)],
          expected: <ExpectedEvent>[_expected()],
          beatDuration: const Duration(milliseconds: 500),
        );
        expect(result.matches, hasLength(1), reason: 'delta=$delta ms');
      }

      final outside = aligner.align(
        observed: <AnalysisEvent>[_onset(126)],
        expected: <ExpectedEvent>[_expected()],
        beatDuration: const Duration(milliseconds: 500),
      );
      expect(outside.matches, isEmpty);
      expect(outside.missedExpected, hasLength(1));
      expect(outside.extraObserved, hasLength(1));
    });

    test('upper clamp is inclusive at 40 BPM', () {
      expect(
        policy.forBeatDuration(const Duration(milliseconds: 1500)),
        const Duration(milliseconds: 150),
      );
      for (final delta in const <int>[150]) {
        expect(
          aligner
              .align(
                observed: <AnalysisEvent>[_onset(delta)],
                expected: <ExpectedEvent>[_expected()],
                beatDuration: const Duration(milliseconds: 1500),
              )
              .matches,
          hasLength(1),
        );
      }
      expect(
        aligner
            .align(
              observed: <AnalysisEvent>[_onset(151)],
              expected: <ExpectedEvent>[_expected()],
              beatDuration: const Duration(milliseconds: 1500),
            )
            .matches,
        isEmpty,
      );
    });

    test('unclamped and lower-clamped windows preserve their boundaries', () {
      expect(
        policy.forBeatDuration(const Duration(milliseconds: 200)),
        const Duration(milliseconds: 50),
      );
      expect(
        policy.forBeatDuration(const Duration(milliseconds: 150)),
        const Duration(milliseconds: 40),
      );

      for (final fixture in <({int beatMs, int inclusive, int exclusive})>[
        (beatMs: 200, inclusive: 50, exclusive: 51),
        (beatMs: 150, inclusive: 40, exclusive: 41),
      ]) {
        final beat = Duration(milliseconds: fixture.beatMs);
        expect(
          aligner
              .align(
                observed: <AnalysisEvent>[_onset(fixture.inclusive)],
                expected: <ExpectedEvent>[_expected()],
                beatDuration: beat,
              )
              .matches,
          hasLength(1),
          reason: 'inclusive=${fixture.inclusive}',
        );
        expect(
          aligner
              .align(
                observed: <AnalysisEvent>[_onset(fixture.exclusive)],
                expected: <ExpectedEvent>[_expected()],
                beatDuration: beat,
              )
              .matches,
          isEmpty,
          reason: 'exclusive=${fixture.exclusive}',
        );
      }
    });
  });
}

OnsetEvent _onset(int milliseconds) => OnsetEvent(
  id: 'observed-$milliseconds',
  time: Duration(milliseconds: milliseconds),
  confidence: 1,
);

ExpectedEvent _expected() => ExpectedEvent(
  id: 'expected',
  time: Duration.zero,
  type: ExpectedEventType.onset,
);
