import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Ch18 spec §4 — the ring closes when `locked` turns true, opens when it
/// turns false, snaps under reduced motion, and its geometry is a pure,
/// repaint-tight painter.
void main() {
  Widget host({required bool locked, bool reducedMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SsLockRing(
            locked: locked,
            color: const Color(0xFF00FF00),
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      ),
    );
  }

  double closedOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SsLockRingPainter,
      ),
    );
    return (paint.painter! as SsLockRingPainter).closed;
  }

  testWidgets('closes over `standard` when locked, then opens again', (
    tester,
  ) async {
    await tester.pumpWidget(host(locked: false));
    expect(closedOf(tester), 0);

    await tester.pumpWidget(host(locked: true));
    await tester.pump(SsMotion.standard ~/ 2);
    final mid = closedOf(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(1));
    await tester.pumpAndSettle();
    expect(closedOf(tester), 1);

    await tester.pumpWidget(host(locked: false));
    await tester.pumpAndSettle();
    expect(closedOf(tester), 0);
  });

  testWidgets('reduced motion snaps the ring closed on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(host(locked: false, reducedMotion: true));
    await tester.pumpWidget(host(locked: true, reducedMotion: true));
    expect(closedOf(tester), 1);
  });

  test('painter repaints only when its inputs change', () {
    const a = SsLockRingPainter(
      closed: 0.5,
      color: Color(0xFF00FF00),
      trackColor: null,
      strokeWidth: 4,
    );
    expect(
      a.shouldRepaint(
        const SsLockRingPainter(
          closed: 0.5,
          color: Color(0xFF00FF00),
          trackColor: null,
          strokeWidth: 4,
        ),
      ),
      isFalse,
    );
    expect(
      a.shouldRepaint(
        const SsLockRingPainter(
          closed: 0.6,
          color: Color(0xFF00FF00),
          trackColor: null,
          strokeWidth: 4,
        ),
      ),
      isTrue,
    );
  });
}
