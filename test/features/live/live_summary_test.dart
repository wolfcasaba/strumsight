// The Live Finish recap: a session in which the learner actually strummed
// ends with a one-screen summary (strums, distinct chords, time, one next
// step) instead of a silent jump back to the hub. A session with no strums
// still leaves immediately (covered by `live_stage_test.dart`).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/live/model/live_frame.dart';
import 'package:strumsight/features/live/providers/chord_timeline_provider.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/live/widgets/live_summary_dialog.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _finishKey = ValueKey('ss-session-transport-finish');
const _dialogKey = ValueKey('live-summary-dialog');
const _doneKey = ValueKey('live-summary-done');
const _courseKey = ValueKey('live-summary-course');

typedef _LiveHarness = ({FakeStrumEngine engine, ProviderContainer container});

Future<_LiveHarness> _pumpLive(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      // E14: the transport is fail-closed on the microphone permission
      // (`micGranted` defaults to FALSE until the platform answers, ADR
      // 0596 / the permission-truthfulness cells), so a Live harness has to
      // say what the permission IS — the real gateway has no platform here.
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
    ],
  );
  addTearDown(container.dispose);
  // Registered AFTER container.dispose so it runs BEFORE it (LIFO): the Live
  // screen lives in a StatefulShellRoute branch and stays mounted after
  // Finish switches to /today, so its dispose (which records the session
  // into practiceLogProvider) must run while the container is still alive.
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  container.read(routerProvider).go(AppRoutes.practiceLive);
  await tester.pumpAndSettle();
  return (engine: engine, container: container);
}

/// One strummed frame; [seq] must differ between strums for the Live
/// screen's stroke counter to see a NEW stroke.
LiveFrame _strum(String chord, int seq) => LiveFrame(
  current: Chord(chord),
  next: null,
  latestStrum: const Strum(direction: StrumDirection.down, confidence: 0.9),
  bar: const [],
  bpm: 96,
  inputLevel: 0.6,
  tuningHz: 440,
  listening: true,
  strumSeq: seq,
  engineTimeSec: seq.toDouble(),
);

Future<void> _play(
  FakeStrumEngine engine,
  WidgetTester tester,
  int strums,
) async {
  for (var i = 1; i <= strums; i++) {
    engine.emit(_strum(i.isOdd ? 'C' : 'G', i));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.tap(find.byKey(_finishKey));
  await tester.pump();
  // Past the 300 ms deferred "finishing" beat, then the dialog's own
  // transition. Fixed pumps, not pumpAndSettle: the Live stage behind the
  // dialog keeps scheduling frames (its idle pulse), so "settled" never
  // arrives while the recap is open (measured in CI).
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('a played session shows the recap with real counts, and Done '
      'leaves to the entry route', (tester) async {
    final live = await _pumpLive(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _play(live.engine, tester, 3);
    // The recap's chord count is whatever the stabilised timeline confirmed
    // for these frames — read it from the same provider the screen reads,
    // rather than assuming how many of the C/G frames were confirmed.
    final confirmedChords = <String>{
      for (final event in live.container.read(chordTimelineProvider))
        event.chord.label,
    }.length;

    await _finish(tester);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.text(l10n.liveSummaryStrums(3)), findsOneWidget);
    expect(find.text(l10n.liveSummaryChords(confirmedChords)), findsOneWidget);
    // Under the short-session threshold: the tip asks for a longer session
    // and the course shortcut is not offered.
    expect(find.text(l10n.liveSummaryTipShort), findsOneWidget);
    expect(find.byKey(_courseKey), findsNothing);

    await tester.tap(find.byKey(_doneKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(_dialogKey), findsNothing);
    expect(find.byType(LiveScreen), findsNothing);
    expect(find.byType(TodayHubScreen), findsOneWidget);
  });

  testWidgets('a longer session offers the guided course as the next step, '
      'and taking it opens the lesson list', (tester) async {
    final live = await _pumpLive(tester);
    final l10n = lookupAppLocalizations(const Locale('en'));
    await _play(live.engine, tester, LiveSummaryDialog.shortSessionStrums);

    await _finish(tester);

    expect(find.byKey(_dialogKey), findsOneWidget);
    expect(find.text(l10n.liveSummaryTipCourse), findsOneWidget);

    await tester.tap(find.byKey(_courseKey));
    // The lesson list carries its own continuous motion, so settle by
    // fixed pumps instead of pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(_dialogKey), findsNothing);
    expect(find.byType(LessonListScreen), findsOneWidget);
  });

  testWidgets('a session with no strum leaves without a recap', (tester) async {
    final live = await _pumpLive(tester);
    live.engine.emit(
      LiveFrame.empty.copyWith(listening: true, inputLevel: 0.3),
    );
    await tester.pump();

    await _finish(tester);

    expect(find.byKey(_dialogKey), findsNothing);
    expect(find.byType(TodayHubScreen), findsOneWidget);
  });
}
