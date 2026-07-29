import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

Future<({FakeStrumEngine live, FakeTunerEngine tuner})> _pumpShell(
  WidgetTester tester,
) async {
  final live = FakeStrumEngine();
  final tuner = FakeTunerEngine();
  addTearDown(live.dispose);
  addTearDown(tuner.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        ...fakeAudioOverrides(),
        strumEngineProvider.overrideWithValue(live),
        tunerEngineProvider.overrideWithValue(tuner),
      ],
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (live: live, tuner: tuner);
}

void main() {
  testWidgets('Live to Settings disposes the live mic owner', (tester) async {
    final rig = await _pumpShell(tester);
    expect(rig.live.startCalls, greaterThan(0));
    final stopsBefore = rig.live.stopCalls;

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));

    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 4);
    expect(
      rig.live.stopCalls,
      greaterThan(stopsBefore),
      reason: 'the mic must not stay hot after leaving Live',
    );
  });

  testWidgets('Tuner back returns to the existing Live shell tab', (
    tester,
  ) async {
    await _pumpShell(tester);

    await tester.tap(find.text('Tuner').first);
    await tester.pumpAndSettle();
    expect(find.byType(TunerScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(LiveScreen), findsOneWidget);
    final navigationBar = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(navigationBar.selectedIndex, 0);
  });
}
