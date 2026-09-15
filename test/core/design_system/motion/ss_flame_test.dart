import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Ch18 spec §11 — the streak flame: static at rest (no idle frames), a
/// finite ignite when the count grows or the flame lights, snapped under
/// reduced motion, and a repaint-tight painter.
void main() {
  Widget host({
    required bool lit,
    int ignition = 0,
    bool igniteOnMount = false,
    bool reducedMotion = false,
    SsFlameSize size = SsFlameSize.medium,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SsFlame(
            lit: lit,
            color: const Color(0xFFB87333),
            dimColor: const Color(0xFF6E7480),
            size: size,
            ignition: ignition,
            igniteOnMount: igniteOnMount,
          ),
        ),
      ),
    );
  }

  SsFlamePainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SsFlamePainter,
      ),
    );
    return paint.painter! as SsFlamePainter;
  }

  test('milestones are 7, 30 and 100 days', () {
    expect(SsFlame.milestoneFor(7), 7);
    expect(SsFlame.milestoneFor(30), 30);
    expect(SsFlame.milestoneFor(100), 100);
    expect(SsFlame.milestoneFor(6), isNull);
    expect(SsFlame.milestoneFor(0), isNull);
    expect(SsFlame.milestoneFor(14), isNull);
  });

  testWidgets('rests at scale 1 with no glow and schedules no frames', (
    tester,
  ) async {
    await tester.pumpWidget(host(lit: true, ignition: 3));
    final painter = painterOf(tester);
    expect(painter.scale, 1);
    expect(painter.glow, 0);
    expect(painter.lit, isTrue);
    // No idle animation: nothing is pending after the first frame.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('an unlit flame keeps the shape in the dim colour', (
    tester,
  ) async {
    await tester.pumpWidget(host(lit: false));
    final painter = painterOf(tester);
    expect(painter.lit, isFalse);
    expect(painter.color, const Color(0xFF6E7480));
    expect(painter.scale, 1);
  });

  testWidgets('ignites once when the count grows, then settles', (
    tester,
  ) async {
    await tester.pumpWidget(host(lit: true, ignition: 3));
    await tester.pumpWidget(host(lit: true, ignition: 4));
    // First frame of the gesture: small, from the base.
    expect(painterOf(tester).scale, SsFlame.igniteFrom);

    // Around the overshoot peak the flame is bigger than at rest and glows.
    await tester.pump(SsMotion.celebration * 0.45);
    final peak = painterOf(tester);
    expect(peak.scale, greaterThan(1));
    expect(peak.scale, lessThanOrEqualTo(SsFlame.overshoot + 1e-9));
    expect(peak.glow, greaterThan(0.9));

    // Finite: it settles back to exactly 1 with no glow.
    await tester.pumpAndSettle();
    final rest = painterOf(tester);
    expect(rest.scale, 1);
    expect(rest.glow, 0);
  });

  testWidgets('lighting the flame ignites it; a same count does not', (
    tester,
  ) async {
    await tester.pumpWidget(host(lit: false, ignition: 0));
    await tester.pumpWidget(host(lit: true, ignition: 1));
    expect(painterOf(tester).scale, SsFlame.igniteFrom);
    await tester.pumpAndSettle();

    // A rebuild with the same count is not a new credit.
    await tester.pumpWidget(host(lit: true, ignition: 1));
    expect(painterOf(tester).scale, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('igniteOnMount plays the gesture on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(host(lit: true, igniteOnMount: true));
    expect(painterOf(tester).scale, SsFlame.igniteFrom);
    await tester.pumpAndSettle();
    expect(painterOf(tester).scale, 1);
  });

  testWidgets('reduced motion never animates — the state snaps', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(lit: true, igniteOnMount: true, reducedMotion: true),
    );
    expect(painterOf(tester).scale, 1);
    await tester.pumpWidget(host(lit: true, ignition: 9, reducedMotion: true));
    expect(painterOf(tester).scale, 1);
    expect(painterOf(tester).glow, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the three sizes lay out at their pinned dimension', (
    tester,
  ) async {
    for (final size in SsFlameSize.values) {
      await tester.pumpWidget(host(lit: true, size: size));
      final box = tester.getSize(find.byType(SsFlame));
      expect(box, Size(size.dimension, size.dimension));
    }
    expect(SsFlameSize.small.dimension, 16);
    expect(SsFlameSize.medium.dimension, 40);
    expect(SsFlameSize.large.dimension, 72);
  });

  testWidgets('is excluded from semantics unless labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    await tester.pumpWidget(host(lit: true));
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SsFlame(
          lit: true,
          color: Color(0xFFB87333),
          semanticLabel: 'Practice streak',
        ),
      ),
    );
    expect(find.bySemanticsLabel('Practice streak'), findsOneWidget);
  });

  test('painter repaints only when a drawn input changes', () {
    const base = SsFlamePainter(
      color: Color(0xFFB87333),
      lit: true,
      scale: 1,
      glow: 0,
    );
    expect(base.shouldRepaint(base), isFalse);
    expect(
      base.shouldRepaint(
        const SsFlamePainter(
          color: Color(0xFFB87333),
          lit: true,
          scale: 1.1,
          glow: 0,
        ),
      ),
      isTrue,
    );
    expect(
      base.shouldRepaint(
        const SsFlamePainter(
          color: Color(0xFFB87333),
          lit: false,
          scale: 1,
          glow: 0,
        ),
      ),
      isTrue,
    );
    expect(
      base.shouldRepaint(
        const SsFlamePainter(
          color: Color(0xFFB87333),
          lit: true,
          scale: 1,
          glow: 0.5,
        ),
      ),
      isTrue,
    );
  });

  test('flame paths fill the glyph box from tip to foot', () {
    final outer = SsFlamePainter.flamePath(40, 40).getBounds();
    expect(outer.top, closeTo(0.8, 0.5));
    expect(outer.bottom, closeTo(40, 0.5));
    final core = SsFlamePainter.corePath(40, 40).getBounds();
    // The core sits inside the outer flame, on its foot.
    expect(core.top, greaterThan(outer.top));
    expect(core.bottom, lessThan(outer.bottom));
    expect(core.width, lessThan(outer.width));
  });
}
