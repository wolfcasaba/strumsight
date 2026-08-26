// Golden snapshots of the E13-R21 practice Setup and active-Session
// screens, at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0 — the two frames the round brief §7/A9 requires. Pattern
// and sizing follow the merged
// `test/ui/goldens/e13_r20_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme), not `SsDarkTheme`.
//
// Recorded on x86_64 (ADR 0426, §0.0/R5) via `tools/golden-x86.sh record`
// — NOT `flutter test --update-goldens` on this (aarch64) box.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/practice/application/practice_catalog_controller.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/practice_route_args.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/practice/session/practice_session_test_fixtures.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

class _SingleDefRepository implements PracticeCatalogRepository {
  const _SingleDefRepository(this.definition);
  final PracticeDefinition definition;

  @override
  List<PracticeDefinition> all() =>
      List<PracticeDefinition>.unmodifiable([definition]);
  @override
  PracticeDefinition? byId(String id) =>
      id == definition.id ? definition : null;
  @override
  List<PracticeDefinition> byMode(PracticeMode mode) => definition.mode == mode
      ? List<PracticeDefinition>.unmodifiable([definition])
      : const <PracticeDefinition>[];
  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) =>
      const <PracticeDefinition>[];
}

class _NoopFeedback implements PracticeFeedbackOutput {
  const _NoopFeedback();
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

AppConfig _config() => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: const FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(_config()),
        appLifecycleEventsProvider.overrideWithValue(FakeLifecycleEvents()),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final definition = practiceSessionFixtureDefinition(
    id: 'fixture.golden.setup',
  );

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    testWidgets('practice setup — $suffix', (tester) async {
      await _pump(
        tester,
        PracticeSetupScreen(
          argsOverride: PracticeSetupArgs(
            request: PracticeSetupRequest.hasId,
            definitionId: definition.id,
          ),
        ),
        overrides: [
          practiceCatalogRepositoryProvider.overrideWithValue(
            _SingleDefRepository(definition),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r21_practice_setup_$suffix');
    });

    testWidgets('practice session — running — $suffix', (tester) async {
      final host = FakeSessionHost()..liveScore = 640;
      host.emitState(
        practiceSessionStateFor(
          PracticeSessionStatus.running,
          definition: practiceSessionFixtureDefinition(
            id: 'fixture.golden.session',
          ),
          config: practiceSessionFixtureConfig(
            definitionId: 'fixture.golden.session',
          ),
          attemptIndex: 1,
          activeElapsed: const Duration(seconds: 37),
        ),
      );
      addTearDown(host.close);
      await _pump(
        tester,
        const PracticeSessionScreen(),
        overrides: [
          practiceSessionHostProvider.overrideWithValue(host),
          practiceFeedbackOutputProvider.overrideWithValue(
            const _NoopFeedback(),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r21_practice_session_running_$suffix');
    });

    testWidgets('practice session — pause/recovery overlay — $suffix', (
      tester,
    ) async {
      final host = FakeSessionHost();
      host.emitState(
        practiceSessionStateFor(
          PracticeSessionStatus.paused,
          definition: practiceSessionFixtureDefinition(
            id: 'fixture.golden.paused',
          ),
          config: practiceSessionFixtureConfig(
            definitionId: 'fixture.golden.paused',
          ),
          pauseCause: PauseCause.interruption,
        ),
      );
      addTearDown(host.close);
      await _pump(
        tester,
        const PracticeSessionScreen(),
        overrides: [
          practiceSessionHostProvider.overrideWithValue(host),
          practiceFeedbackOutputProvider.overrideWithValue(
            const _NoopFeedback(),
          ),
        ],
        textScale: textScale,
      );
      await _expectGolden(tester, 'e13_r21_practice_session_paused_$suffix');
    });
  }
}
