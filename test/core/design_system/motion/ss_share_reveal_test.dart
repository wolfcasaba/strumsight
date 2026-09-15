import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Ch18 spec §12 — the card builds up over one finite progress: slots map
/// it onto their own windows, a slot with no reveal above it is inert (the
/// export capture), reduced motion completes on the first frame, and the
/// host is told exactly once when the card is final.
void main() {
  Widget host({
    required Widget child,
    bool reducedMotion = false,
    VoidCallback? onCompleted,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SsShareReveal(onCompleted: onCompleted, child: child),
      ),
    );
  }

  double opacityOf(WidgetTester tester, String text) {
    final found = find.ancestor(
      of: find.text(text),
      matching: find.byType(Opacity),
    );
    if (found.evaluate().isEmpty) return 1;
    return tester.widget<Opacity>(found.first).opacity;
  }

  test('windowFor spreads count windows evenly between from and to', () {
    final first = SsRevealSlot.windowFor(0, 4, from: 0.4, to: 0.85);
    final last = SsRevealSlot.windowFor(3, 4, from: 0.4, to: 0.85);
    expect(first.start, 0.4);
    expect(first.end, closeTo(0.52, 1e-9));
    expect(last.end, closeTo(0.85, 1e-9));
    expect(last.start, greaterThan(first.end));
    // A single item takes the head of the window.
    final only = SsRevealSlot.windowFor(0, 1, from: 0.4, to: 0.45);
    expect(only.start, 0.4);
    expect(only.end, 0.45);
  });

  test('localProgress is 0 before the window, 1 at and past its end', () {
    const slot = SsRevealSlot(start: 0.2, end: 0.6, child: SizedBox.shrink());
    expect(slot.localProgress(0), 0);
    expect(slot.localProgress(0.2), 0);
    expect(slot.localProgress(0.4), greaterThan(0));
    expect(slot.localProgress(0.4), lessThan(1));
    expect(slot.localProgress(0.6), 1);
    expect(slot.localProgress(1), 1);
  });

  testWidgets('with no reveal above, a slot renders its child untouched', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SsRevealSlot(start: 0.5, end: 1, child: Text('inert')),
      ),
    );
    expect(SsShareReveal.progressOf(tester.element(find.text('inert'))), 1);
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('slots come in over their windows and end untouched', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      host(
        onCompleted: () => completed++,
        child: const Column(
          children: [
            SsRevealSlot(start: 0, end: 0.3, child: Text('first')),
            SsRevealSlot(
              start: 0.6,
              end: 1,
              landing: true,
              child: Text('last'),
            ),
          ],
        ),
      ),
    );
    // First frame: nothing shown yet.
    expect(opacityOf(tester, 'first'), 0);
    expect(opacityOf(tester, 'last'), 0);

    // Mid-way: the first slot leads the last, which has not started.
    await tester.pump(SsMotion.celebration * 0.4);
    expect(opacityOf(tester, 'first'), 1);
    expect(find.byType(Opacity), findsOneWidget);
    expect(opacityOf(tester, 'last'), 0);
    expect(completed, 0);

    // A landing slot arrives from larger than life.
    await tester.pump(SsMotion.celebration * 0.3);
    final transform = tester.widget<Transform>(
      find.ancestor(of: find.text('last'), matching: find.byType(Transform)),
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));

    // Finite: settles with every slot inert and the host told once.
    await tester.pumpAndSettle();
    expect(find.byType(Opacity), findsNothing);
    expect(find.byType(Transform), findsNothing);
    expect(completed, 1);
  });

  testWidgets('reduced motion is complete on the first frame, still done', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      host(
        reducedMotion: true,
        onCompleted: () => completed++,
        child: const SsRevealSlot(start: 0.5, end: 1, child: Text('now')),
      ),
    );
    expect(find.byType(Opacity), findsNothing);
    expect(find.text('now'), findsOneWidget);
    // The completion lands at the end of the first frame (post-frame, never
    // during build) — and exactly once.
    expect(completed, 1);
    await tester.pumpAndSettle();
    expect(completed, 1);
  });
}
