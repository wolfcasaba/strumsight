// E04-R22 §6 — Tutor Profile screen matrix.
//
// RED-first. Compiles only after `tutor_profile_screen.dart` and
// `tutor_privacy_providers.dart` (which exposes the
// `tutorProfileControllerProvider`/`tutorLearningGoalControllerProvider`
// notifiers) land. Cells:
//   * R22-PF1 — profile screen renders every editable surface
//     (student experience, locale, weekly minutes, guitar, goals).
//   * R22-PF2 — invalid input surfaces a localized error.
//   * R22-PF3 — adding a goal updates the goal list.
//   * R22-PF4 — hu locale renders Hungarian copy.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/components/actions/ss_button.dart';
import 'package:strumsight/core/design_system/components/inputs/ss_validation_summary.dart';
import 'package:strumsight/core/design_system/components/surfaces/ss_section.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/ai_tutor/domain/models/learning_goal.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_profile_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';
import 'package:strumsight/l10n/app_localizations_hu.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../../support/preference_store.dart';

AppLocalizations l10nEn() => AppLocalizationsEn();
AppLocalizations l10nHu() => AppLocalizationsHu();

AppConfig _config({bool aiTutorEnabled = true}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    aiTutorEnabled: aiTutorEnabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      ...preferenceOverrides(),
      appConfigProvider.overrideWithValue(_config()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: SsLightTheme.data(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TutorProfileScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('R22-PF1: profile screen renders every editable surface', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(TutorProfileScreen), findsOneWidget);
    // Weekly minutes field exists.
    expect(find.byKey(const Key('tutorProfileWeeklyMinutes')), findsOneWidget);
    // Guitar name field exists.
    expect(find.byKey(const Key('tutorProfileGuitarName')), findsOneWidget);
    // Goal add button exists.
    expect(find.byKey(const Key('tutorProfileAddGoal')), findsOneWidget);
  });

  testWidgets('R22-PF2: invalid weekly minutes surfaces a localized error', (
    tester,
  ) async {
    final container = await _pump(tester);
    // Push the controller past the weekly-max — the screen surfaces
    // a localized validation error.
    container
        .read(tutorProfileControllerProvider.notifier)
        .setWeeklyMinutes(100000000);
    await tester.pump();
    expect(
      find.byKey(const Key('tutorProfileWeeklyMinutesError')),
      findsOneWidget,
    );
    // E15-R09 §0.0.B/R15 — the validation error is the design-system
    // SsValidationSummary, not a bare styled Text.
    expect(find.byType(SsValidationSummary), findsOneWidget);
  });

  testWidgets('R22-PF3: adding a goal appends it to the goal list', (
    tester,
  ) async {
    final container = await _pump(tester);
    container
        .read(tutorLearningGoalControllerProvider.notifier)
        .addGoal(
          LearningGoal(
            id: 'g-stable-tempo',
            statement: 'Stable tempo at 90 BPM',
            category: LearningGoalCategory.increaseStableTempo,
            priority: LearningGoalPriority.high,
            status: LearningGoalStatus.active,
          ),
        );
    await tester.pump();
    expect(find.text('Stable tempo at 90 BPM'), findsOneWidget);
  });

  testWidgets('R22-PF4: hu locale renders the Hungarian profile copy', (
    tester,
  ) async {
    await _pump(tester, locale: const Locale('hu'));
    expect(find.text(l10nHu().tutorProfileTitle), findsOneWidget);
  });

  testWidgets(
    'R22-PF5: profile screen exposes a screen-level semantics label',
    (tester) async {
      await _pump(tester);
      expect(
        find.bySemanticsLabel(l10nEn().tutorProfileScreenSemantics),
        findsOneWidget,
      );
    },
  );

  // -------------------------------------------------------------------
  // E15-R09 §0.0.B/R15 — per-screen design-system type assertions.
  // -------------------------------------------------------------------
  testWidgets(
    'R22-PF6: the three sections are the design-system SsSection, and Add goal is SsButton',
    (tester) async {
      await _pump(tester);
      expect(find.byType(SsSection), findsNWidgets(3));
      expect(find.byType(SsButton), findsOneWidget);
    },
  );

  // -------------------------------------------------------------------
  // E15-R09 §0.0.B/R14 — committed textScaler 2.0 coverage (en + hu), on
  // the phone viewport the golden lane uses (412x915). Drives the
  // weekly-minutes validation error AND adds a goal, so the
  // `SsValidationSummary` and the goal-row `IconButton` both render.
  // -------------------------------------------------------------------
  for (final locale in const [Locale('en'), Locale('hu')]) {
    testWidgets(
      'R22-PF7: textScaler 2.0, locale=${locale.languageCode} — no overflow',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final container = await _pump(tester, locale: locale);
        container
            .read(tutorProfileControllerProvider.notifier)
            .setWeeklyMinutes(100000000);
        container
            .read(tutorLearningGoalControllerProvider.notifier)
            .addGoal(
              LearningGoal(
                id: 'g-stable-tempo',
                statement: 'Stable tempo at 90 BPM',
                category: LearningGoalCategory.increaseStableTempo,
                priority: LearningGoalPriority.high,
                status: LearningGoalStatus.active,
              ),
            );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
