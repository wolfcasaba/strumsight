import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// Widget contract of the strummed six-string band: it draws at rest without
/// scheduling frames, a strum runs a LOCAL ticker that stops itself (so
/// `pumpAndSettle` terminates), a late direction verdict UPGRADES the running
/// stroke instead of starting a second one, reduced motion schedules nothing at
/// all, and the band is silent to screen readers unless it is given a label.
void main() {
  const down = Color(0xFFB87333);
  const up = Color(0xFF3DDC84);
  const strings = Color(0xFF9E9E9E);

  Widget host({
    int onsetSeq = 0,
    int strumSeq = 0,
    bool? isDown,
    double strength = 0.9,
    bool reducedMotion = false,
    String? semanticLabel,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 300,
            child: SsStrumStrings(
              onsetSeq: onsetSeq,
              strumSeq: strumSeq,
              isDown: isDown,
              strength: strength,
              downColor: down,
              upColor: up,
              stringColor: strings,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders an idle band at its declared height, scheduling no '
      'frames', (tester) async {
    await tester.pumpWidget(host());

    expect(find.byType(SsStrumStrings), findsOneWidget);
    expect(tester.getSize(find.byType(SsStrumStrings)), const Size(300, 72));
    // Nothing is ringing, so nothing is animating.
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await tester.pumpAndSettle(), 1);
  });

  testWidgets('a rising strumSeq starts the ticker and pumpAndSettle '
      'completes', (tester) async {
    await tester.pumpWidget(host(isDown: true));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(host(strumSeq: 1, isDown: true));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Mid-ring it is still animating…
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // …and the ticker stops itself once the stroke is done.
    expect(await tester.pumpAndSettle(), greaterThan(1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a rebuild with unchanged counters never starts a stroke', (
    tester,
  ) async {
    await tester.pumpWidget(host(onsetSeq: 4, strumSeq: 3, isDown: true));
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(
      host(onsetSeq: 4, strumSeq: 3, isDown: true, strength: 0.2),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a strum with no direction is ignored', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpWidget(host(strumSeq: 1));

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  // The two tests below are a matched pair: identical except for how long the
  // verdict takes. Within the grace window the band must hold ONE stroke that
  // ends 0.6 s after the onset; outside it, a second stroke is started and the
  // band is still alive well past that.
  testWidgets('an onset then a direction inside the grace window resolves the '
      'running stroke instead of starting a second', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpWidget(host(onsetSeq: 1));
    // First tick: the stroke's clock origin (elapsed 0).
    await tester.pump(const Duration(milliseconds: 16));
    // 0.1 s later — inside SsStrumStrings.directionGraceSec — the verdict lands.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(onsetSeq: 1, strumSeq: 1, isDown: true));
    expect(tester.binding.hasScheduledFrame, isTrue);

    // The strings keep ringing from the ONSET, so everything is over 0.6 s
    // after it. A second stroke would have run to 0.76 s instead.
    await tester.pump(const Duration(milliseconds: 560));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await tester.pumpAndSettle(), 1);
  });

  testWidgets('a direction arriving after the grace window starts its own '
      'stroke', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpWidget(host(onsetSeq: 1));
    await tester.pump(const Duration(milliseconds: 16));
    // 0.3 s — past the 0.25 s grace, so this verdict belongs to its own strum.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(host(onsetSeq: 1, strumSeq: 1, isDown: true));

    // At 0.7 s the onset's own ring-out is long gone; the band is only still
    // alive because a second stroke was started at 0.3 s.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.binding.hasScheduledFrame, isTrue);

    expect(await tester.pumpAndSettle(), greaterThan(1));
  });

  testWidgets('reduced motion schedules no frames for a strum', (tester) async {
    await tester.pumpWidget(host(reducedMotion: true));
    await tester.pumpWidget(
      host(onsetSeq: 1, strumSeq: 1, isDown: true, reducedMotion: true),
    );

    // Static strings and a parked pick glyph: painted, never animated.
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await tester.pumpAndSettle(), 1);
    expect(find.byType(SsStrumStrings), findsOneWidget);
  });

  testWidgets('a running stroke is dropped when reduced motion turns on', (
    tester,
  ) async {
    await tester.pumpWidget(host(isDown: true));
    await tester.pumpWidget(host(strumSeq: 1, isDown: true));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(
      host(strumSeq: 1, isDown: true, reducedMotion: true),
    );
    // One frame was already requested before the ticker was stopped; draining
    // it must not produce another, because the stroke is gone with it.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await tester.pumpAndSettle(), 1);
  });

  testWidgets('the semantic label is exposed when given', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(semanticLabel: 'Down strum, strong'));

    expect(find.bySemanticsLabel('Down strum, strong'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('without a label the band is excluded from semantics', (
    tester,
  ) async {
    await tester.pumpWidget(host());

    expect(find.byType(ExcludeSemantics), findsOneWidget);
  });
}
