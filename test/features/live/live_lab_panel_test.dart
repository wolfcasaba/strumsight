import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/settings/providers/lab_mode_provider.dart';
import 'package:strumsight/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// A LabMode notifier fixed at [_v] (skips the async prefs load) for tests.
class _FixedLabMode extends LabModeNotifier {
  _FixedLabMode(this._v);
  final bool _v;
  @override
  bool build() => _v;
}

/// E15-R02 (ADR 0467 D9): the app now boots on the adaptive shell's /today
/// entry point by default; /live is reachable through legacyRedirects'
/// target, AppRoutes.practiceLive.
Future<void> _pumpLiveApp(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  container.read(routerProvider).go(AppRoutes.practiceLive);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Live Lab panel is HIDDEN when Lab mode is off (default)', (
    tester,
  ) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await _pumpLiveApp(
      tester,
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        labModeProvider.overrideWith(() => _FixedLabMode(false)),
      ],
    );

    expect(find.text('Capture & analyze last ~60 s'), findsNothing);
    // With Lab off the engine is told NOT to capture (never a stray `true`).
    expect(engine.captureCalls, isNot(contains(true)));

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets(
    'Live Lab panel SHOWS with a capture button when Lab mode is on',
    (tester) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      await _pumpLiveApp(
        tester,
        overrides: [
          ...preferenceOverrides(),
          strumEngineProvider.overrideWithValue(engine),
          labModeProvider.overrideWith(() => _FixedLabMode(true)),
        ],
      );

      expect(find.text('Capture & analyze last ~60 s'), findsOneWidget);
      // Lab on → the engine's rolling capture was enabled.
      expect(engine.captureCalls, contains(true));

      await tester.pump(const Duration(milliseconds: 400));
    },
  );

  testWidgets('Capture with an empty mic buffer shows the "no audio yet" hint', (
    tester,
  ) async {
    final engine = FakeStrumEngine(); // fakePcm empty by default
    addTearDown(engine.dispose);

    await _pumpLiveApp(
      tester,
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        labModeProvider.overrideWith(() => _FixedLabMode(true)),
      ],
    );

    await tester.tap(find.text('Capture & analyze last ~60 s'));
    await tester.pumpAndSettle();

    // Empty buffer → the guard reports "no audio", never runs analysis/crashes.
    expect(find.textContaining('No audio captured yet'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
  });
}
