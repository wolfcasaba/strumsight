import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test(
    'timeline snapshots event collections and region events use Duration ranges',
    () {
      final events = <AnalysisEvent>[
        OnsetEvent(id: 'onset', time: Duration.zero, confidence: 1),
        SilenceRegionEvent(
          id: 'silence',
          time: const Duration(microseconds: 1),
          end: const Duration(microseconds: 2),
          confidence: 1,
        ),
        ClippingRegionEvent(
          id: 'clip',
          time: const Duration(microseconds: 3),
          end: const Duration(microseconds: 4),
          confidence: 1,
        ),
      ];
      final timeline = AnalysisTimeline(
        duration: const Duration(microseconds: 5),
        events: events,
      );
      events.add(
        OnsetEvent(
          id: 'later',
          time: const Duration(microseconds: 4),
          confidence: 1,
        ),
      );
      expect(timeline.events, hasLength(3));
      expect(
        () => timeline.events.add(
          OnsetEvent(id: 'no', time: Duration.zero, confidence: 1),
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('region end before start is rejected', () {
    expect(
      () => SilenceRegionEvent(
        id: 'bad',
        time: const Duration(microseconds: 2),
        end: const Duration(microseconds: 1),
        confidence: 1,
      ),
      throwsArgumentError,
    );
  });
}
