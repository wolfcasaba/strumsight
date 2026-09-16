import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Ch18 spec §0.2 — one finite gesture: items fade + rise one `stagger`
/// apart, the whole entrance stays under `celebration` for five items,
/// and reduced motion shows everything at once.
void main() {
  Widget host({required List<Widget> children, bool reducedMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SsStaggeredEntrance(children: children),
      ),
    );
  }

  double opacityOf(WidgetTester tester, String text) {
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    );
    return opacity.opacity;
  }

  test('totalDuration: last item starts (n−1)×stagger in, then its own', () {
    expect(SsStaggeredEntrance.totalDuration(0), Duration.zero);
    expect(SsStaggeredEntrance.totalDuration(1), SsMotion.contentFade);
    expect(
      SsStaggeredEntrance.totalDuration(5),
      SsMotion.contentFade + SsMotion.stagger * 4,
    );
    // Five cards stay under the celebration cap (spec §0.1).
    expect(
      SsStaggeredEntrance.totalDuration(5) <= SsMotion.celebration,
      isTrue,
    );
  });

  testWidgets('items start hidden and are all visible after settling', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(children: const [Text('one'), Text('two'), Text('three')]),
    );
    // First frame: nothing has faded in yet.
    expect(opacityOf(tester, 'one'), 0);
    expect(opacityOf(tester, 'three'), 0);
    // Mid-way: the first item leads the last.
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOf(tester, 'one'), greaterThan(opacityOf(tester, 'three')));
    // Finite: settles, and every item ends fully visible.
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'one'), 1);
    expect(opacityOf(tester, 'two'), 1);
    expect(opacityOf(tester, 'three'), 1);
  });

  testWidgets('reduced motion shows every item on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(children: const [Text('one'), Text('two')], reducedMotion: true),
    );
    expect(opacityOf(tester, 'one'), 1);
    expect(opacityOf(tester, 'two'), 1);
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
  });

  testWidgets('an empty list renders nothing and settles', (tester) async {
    await tester.pumpWidget(host(children: const []));
    await tester.pumpAndSettle();
    expect(find.byType(Opacity), findsNothing);
  });
}
