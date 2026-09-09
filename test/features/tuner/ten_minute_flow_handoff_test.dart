// E14-R36 (ADR 0546) — the tuner's link in the "10 useful minutes" chain.
// The tuner is step 1; nothing here infers that the guitar is in tune, so
// the ONLY thing that ends the step is the player pressing the hand-off
// button — which then goes straight to the exercise, so the chain is one
// guided flow rather than three separate islands.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/today/domain/ten_minute_flow.dart';
import 'package:strumsight/features/today/providers/ten_minute_flow_providers.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _continueKey = ValueKey('tuner-ten-minute-continue');

class _SeededFlowController extends TenMinuteFlowController {
  _SeededFlowController(this._seed);
  final TenMinuteFlowState? _seed;

  @override
  TenMinuteFlowState? build() => _seed;
}

TenMinuteFlowState _chainAt(TenMinuteStep step) => TenMinuteFlowState(
  plan: TenMinutePlan.standard,
  step: step,
  startedAt: DateTime(2026, 8, 25, 18),
  baselineActiveSeconds: 0,
);

Future<(GoRouter, ProviderContainer)> _pumpTuner(
  WidgetTester tester, {
  TenMinuteFlowState? chain,
}) async {
  final engine = FakeTunerEngine();
  addTearDown(engine.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.practiceTuner,
    routes: [
      GoRoute(
        path: AppRoutes.practiceTuner,
        builder: (_, _) => const TunerScreen(),
      ),
      GoRoute(
        path: AppRoutes.practiceSetup,
        builder: (_, _) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );

  final container = ProviderContainer(
    overrides: <Override>[
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      tunerEngineProvider.overrideWithValue(engine),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            practiceEngineV2Enabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
      if (chain != null)
        tenMinuteFlowProvider.overrideWith(() => _SeededFlowController(chain)),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router, container);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a tuner opened on its own shows no chain hand-off at all', (
    tester,
  ) async {
    await _pumpTuner(tester);

    expect(find.byKey(_continueKey), findsNothing);
  });

  testWidgets('a chain sitting on a LATER step does not claim the tuner', (
    tester,
  ) async {
    await _pumpTuner(tester, chain: _chainAt(TenMinuteStep.play));

    expect(find.byKey(_continueKey), findsNothing);
  });

  testWidgets('step 1: the hand-off is offered and names the position', (
    tester,
  ) async {
    await _pumpTuner(tester, chain: _chainAt(TenMinuteStep.tune));

    expect(find.byKey(_continueKey), findsOneWidget);
    expect(
      find.text('Step 1 of 3'),
      findsOneWidget,
      reason: 'visible, scalable text — never a colour-only progress dot',
    );
  });

  testWidgets(
    'the hand-off advances the chain to the play step AND opens the '
    'recommended exercise, so the chain never dead-ends in the tuner',
    (tester) async {
      final (router, container) = await _pumpTuner(
        tester,
        chain: _chainAt(TenMinuteStep.tune),
      );

      await tester.tap(find.byKey(_continueKey));
      await tester.pumpAndSettle();

      expect(container.read(tenMinuteFlowProvider)?.step, TenMinuteStep.play);
      expect(
        router.state.uri.toString(),
        '/practice/setup?id=builtin.quarterDownstrokes.v1',
      );
    },
  );
}
