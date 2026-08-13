import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/timeline_viewport.dart';

void main() {
  const duration = Duration(seconds: 10);
  const width = 400.0;

  group('TimelineViewport', () {
    test('zooms around the requested focal time without leaving the clip', () {
      final viewport = TimelineViewport.full(
        duration: duration,
        logicalWidth: width,
      );

      final zoomed = viewport.zoomBy(
        scale: 2,
        focalTime: const Duration(seconds: 5),
      );

      expect(zoomed.visibleDuration, const Duration(seconds: 5));
      expect(zoomed.start, const Duration(milliseconds: 2500));
      expect(zoomed.end, const Duration(milliseconds: 7500));
      expect(zoomed.isWithinDuration, isTrue);
    });

    test(
      'zooms out around the focal time and clamps near either clip edge',
      () {
        final centered = TimelineViewport(
          duration: duration,
          logicalWidth: width,
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 6),
        ).zoomBy(scale: .5, focalTime: const Duration(seconds: 5));
        final nearEdge = TimelineViewport(
          duration: duration,
          logicalWidth: width,
          start: const Duration(milliseconds: 100),
          end: const Duration(seconds: 2),
        ).zoomBy(scale: .1, focalTime: const Duration(seconds: 1));

        expect(centered.start, const Duration(seconds: 3));
        expect(centered.end, const Duration(seconds: 7));
        expect(centered.isWithinDuration, isTrue);
        expect(nearEdge.start, greaterThanOrEqualTo(Duration.zero));
        expect(nearEdge.end, lessThanOrEqualTo(duration));
        expect(nearEdge.isWithinDuration, isTrue);
      },
    );

    test('pans in both directions and clamps against both clip edges', () {
      final viewport = TimelineViewport(
        duration: duration,
        logicalWidth: width,
        start: Duration(seconds: 2),
        end: Duration(seconds: 6),
      );

      final left = viewport.panBy(const Duration(seconds: -5));
      final right = viewport.panBy(const Duration(seconds: 9));

      expect(left.start, Duration.zero);
      expect(left.end, const Duration(seconds: 4));
      expect(right.start, const Duration(seconds: 6));
      expect(right.end, duration);
    });

    test(
      'accepts the inclusive minimum zoom window and clamps narrower windows',
      () {
        final full = TimelineViewport.full(
          duration: duration,
          logicalWidth: width,
        );
        final below = full.withVisibleDuration(
          const Duration(milliseconds: 399),
          focalTime: const Duration(seconds: 5),
        );
        final exact = full.withVisibleDuration(
          const Duration(milliseconds: 400),
          focalTime: const Duration(seconds: 5),
        );
        final above = full.withVisibleDuration(
          const Duration(milliseconds: 401),
          focalTime: const Duration(seconds: 5),
        );

        expect(below.visibleDuration, const Duration(milliseconds: 400));
        expect(exact.visibleDuration, const Duration(milliseconds: 400));
        expect(above.visibleDuration, const Duration(milliseconds: 401));
      },
    );

    test('keeps a near-edge zoom window inside the clip', () {
      final viewport = TimelineViewport.full(
        duration: duration,
        logicalWidth: width,
      );

      final zoomed = viewport.zoomBy(
        scale: 4,
        focalTime: const Duration(milliseconds: 100),
      );

      expect(zoomed.start, greaterThanOrEqualTo(Duration.zero));
      expect(zoomed.end, lessThanOrEqualTo(duration));
      expect(zoomed.isWithinDuration, isTrue);
    });

    test('maps time and pixels inside the visible window', () {
      final viewport = TimelineViewport(
        duration: duration,
        logicalWidth: width,
        start: Duration(seconds: 2),
        end: Duration(seconds: 6),
      );

      expect(viewport.timeForPixel(200), const Duration(seconds: 4));
      expect(viewport.pixelForTime(const Duration(seconds: 4)), 200);
    });

    test(
      'reveals a hotspot range without expanding beyond either clip edge',
      () {
        final viewport = TimelineViewport(
          duration: duration,
          logicalWidth: width,
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 6),
        );

        final left = viewport.revealRange(
          const Duration(milliseconds: 400),
          const Duration(seconds: 1),
        );
        final right = viewport.revealRange(
          const Duration(seconds: 9),
          const Duration(milliseconds: 9500),
        );

        expect(left.start, const Duration(milliseconds: 400));
        expect(left.end, const Duration(milliseconds: 4400));
        expect(right.start, const Duration(milliseconds: 5500));
        expect(right.end, const Duration(milliseconds: 9500));
      },
    );
  });
}
