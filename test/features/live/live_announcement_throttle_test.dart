// E13-R18 A5 — the accessible chord announcement is throttled to the ADR
// 0280 §2 budget (1000 ms, boundary inclusive), while the VISUAL chord label
// tracks every frame unthrottled. Three mandatory cells (brief §6.1):
//   below the threshold (200 ms apart)  -> one announcement, every visual
//                                           change still shown
//   exactly at the threshold (1000 ms)  -> announced (inclusive boundary)
//   above the threshold (3000 ms apart) -> every change announced
//
// Reads [SsLiveRegion.announcements] straight off the mounted
// [SsLiveRegionAnnouncer] rather than the semantics tree: the chord label
// itself is ALSO visible (hero + timeline), so a `find.bySemanticsLabel`
// search would match those too and can't isolate the announcer.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

LiveFrame _frameAt(String chord, double engineTimeSec) => LiveFrame(
  current: Chord(chord),
  next: null,
  latestStrum: null,
  bar: const [],
  bpm: 96,
  inputLevel: 0.6,
  tuningHz: 440,
  listening: true,
  engineTimeSec: engineTimeSec,
);

Future<FakeStrumEngine> _pumpLive(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      strumEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  // E15-R02 (ADR 0467 D9): the app now boots on the adaptive shell's
  // /today entry point by default; /live is reachable through
  // legacyRedirects' target, AppRoutes.practiceLive.
  container.read(routerProvider).go(AppRoutes.practiceLive);
  await tester.pumpAndSettle();
  return engine;
}

List<String> _announcements(WidgetTester tester) => tester
    .widget<SsLiveRegionAnnouncer>(find.byType(SsLiveRegionAnnouncer))
    .controller
    .announcements;

void main() {
  testWidgets('below the threshold (200 ms apart): one announcement, but every '
      'visual change is still shown', (tester) async {
    final engine = await _pumpLive(tester);

    engine.emit(_frameAt('C', 0.0));
    await tester.pumpAndSettle();
    expect(_announcements(tester), ['C']);
    expect(find.text('C'), findsWidgets);

    engine.emit(_frameAt('G', 0.2));
    await tester.pumpAndSettle();
    // The VISUAL label followed the new chord immediately…
    expect(find.text('G'), findsWidgets);
    // …but the announcement budget suppressed it (still just "C").
    expect(_announcements(tester), ['C']);

    engine.emit(_frameAt('D', 0.4));
    await tester.pumpAndSettle();
    expect(find.text('D'), findsWidgets);
    expect(_announcements(tester), ['C']);

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('exactly at the threshold (1000 ms): the boundary is inclusive — '
      'announced', (tester) async {
    final engine = await _pumpLive(tester);

    engine.emit(_frameAt('C', 0.0));
    await tester.pumpAndSettle();
    expect(_announcements(tester), ['C']);

    engine.emit(_frameAt('G', 1.0));
    await tester.pumpAndSettle();

    expect(find.text('G'), findsWidgets);
    expect(_announcements(tester), ['C', 'G']);

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'above the threshold (3000 ms apart): every distinct reading announces',
    (tester) async {
      final engine = await _pumpLive(tester);

      engine.emit(_frameAt('C', 0.0));
      await tester.pumpAndSettle();
      expect(_announcements(tester), ['C']);

      engine.emit(_frameAt('G', 3.0));
      await tester.pumpAndSettle();
      expect(find.text('G'), findsWidgets);
      expect(_announcements(tester), ['C', 'G']);

      engine.emit(_frameAt('D', 6.0));
      await tester.pumpAndSettle();
      expect(find.text('D'), findsWidgets);
      expect(_announcements(tester), ['C', 'G', 'D']);

      await tester.pump(const Duration(milliseconds: 400));
    },
  );
}
