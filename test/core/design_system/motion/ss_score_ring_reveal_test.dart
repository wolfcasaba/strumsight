import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Ch18 spec §0.2 — the ring fills 0 → value over `ringFill`, the centre
/// label counts up with it, a non-measured state renders at once, and
/// reduced motion shows the final value on the first frame.
void main() {
  Widget host(Widget child, {bool reducedMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: MaterialApp(home: Center(child: child)),
    );
  }

  double shownRatio(WidgetTester tester) =>
      tester.widget<SsScoreRing>(find.byType(SsScoreRing)).ratio!;

  testWidgets('fills from empty to the measured value and counts up', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SsScoreRingReveal(
          state: SsScoreRingState.measured,
          ratio: 0.8,
          semanticLabel: 'score',
        ),
      ),
    );
    expect(shownRatio(tester), 0);
    expect(find.text('0%'), findsOneWidget);
    await tester.pump(SsMotion.ringFill ~/ 2);
    final mid = shownRatio(tester);
    expect(mid, greaterThan(0));
    expect(mid, lessThan(0.8));
    await tester.pumpAndSettle();
    expect(shownRatio(tester), closeTo(0.8, 1e-9));
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final value on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SsScoreRingReveal(
          state: SsScoreRingState.measured,
          ratio: 0.5,
          semanticLabel: 'score',
        ),
        reducedMotion: true,
      ),
    );
    expect(shownRatio(tester), closeTo(0.5, 1e-9));
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('a custom label follows the shown fraction', (tester) async {
    await tester.pumpWidget(
      host(
        SsScoreRingReveal(
          state: SsScoreRingState.measured,
          ratio: 1,
          semanticLabel: 'minutes',
          labelBuilder: (shown) => '${(shown * 15).round()} min',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('15 min'), findsOneWidget);
  });

  testWidgets('a not-applicable ring renders its empty label at once', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const SsScoreRingReveal(
          state: SsScoreRingState.notApplicable,
          semanticLabel: 'no goal',
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    await tester.pumpAndSettle();
  });
}
