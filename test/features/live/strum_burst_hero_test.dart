import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/widgets/strum_burst_hero.dart';

/// The Live hero's strum spark (chunk 016b P0 juice brought to Live): a burst
/// fires only when the strum counter ADVANCES, lives < 0.5 s, stops its own
/// ticker (so `pumpAndSettle` terminates), and is skipped under reduced motion.
void main() {
  Widget host({
    required int seq,
    bool? isDown = true,
    double confidence = 0.9,
    bool reducedMotion = false,
  }) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: StrumBurstHero(
            strumSeq: seq,
            isDown: isDown,
            confidence: confidence,
            child: const SizedBox(width: 200, height: 80, child: Text('G')),
          ),
        ),
      ),
    );
  }

  final overlay = find.byKey(StrumBurstHero.overlayKey);

  testWidgets('no spark on first mount, even with a strum present', (
    tester,
  ) async {
    await tester.pumpWidget(host(seq: 3));
    expect(overlay, findsNothing);
    expect(find.text('G'), findsOneWidget); // the hero itself is untouched
  });

  testWidgets('a rising strumSeq fires a spark that fades out on its own', (
    tester,
  ) async {
    await tester.pumpWidget(host(seq: 0));
    await tester.pumpWidget(host(seq: 1));
    expect(overlay, findsOneWidget);

    // Still alive mid-life…
    await tester.pump(const Duration(milliseconds: 200));
    expect(overlay, findsOneWidget);

    // …gone after its 0.45 s life, and the ticker has stopped: settle returns.
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });

  testWidgets('a rebuild with the same strumSeq does not re-fire', (
    tester,
  ) async {
    await tester.pumpWidget(host(seq: 0));
    await tester.pumpWidget(host(seq: 1));
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);

    await tester.pumpWidget(host(seq: 1, confidence: 0.4));
    await tester.pump();
    expect(overlay, findsNothing);
  });

  testWidgets('a strum with no direction never bursts', (tester) async {
    await tester.pumpWidget(host(seq: 0, isDown: null));
    await tester.pumpWidget(host(seq: 1, isDown: null));
    await tester.pump();
    expect(overlay, findsNothing);
  });

  testWidgets('reduced motion keeps the hero but draws no spark', (
    tester,
  ) async {
    await tester.pumpWidget(host(seq: 0, reducedMotion: true));
    await tester.pumpWidget(host(seq: 1, reducedMotion: true));
    await tester.pump();
    expect(overlay, findsNothing);
    expect(find.text('G'), findsOneWidget);
  });

  testWidgets('back-to-back strums stack and the overlay outlives the first', (
    tester,
  ) async {
    await tester.pumpWidget(host(seq: 0));
    await tester.pumpWidget(host(seq: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(host(seq: 2, isDown: false));
    // 300 ms later the first burst (0.45 s life) is gone, the second is not.
    await tester.pump(const Duration(milliseconds: 300));
    expect(overlay, findsOneWidget);
    await tester.pumpAndSettle();
    expect(overlay, findsNothing);
  });
}
