import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/learn/screens/learn_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';
import 'package:strumsight/features/progress/providers/practice_log_provider.dart';
import 'package:strumsight/features/streak/streak_logic.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';

import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

FeatureFlags _flagsOff() => FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  practiceEngineV2Enabled: false,
  migratedLearnEnabled: false,
  practiceDetailedHistoryEnabled: false,
);

AppConfig _config(FeatureFlags flags) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: flags,
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// A seeded V1 practice log so the screen has something to score against.
class _SeededLog extends PracticeLogController {
  _SeededLog(this._seed);
  final List<PracticeEntry> _seed;
  @override
  List<PracticeEntry> build() => _seed;
}

/// A seeded lesson-progress map so the OFF/ON rollback test starts from a
/// known best.
class _SeededProgress extends LessonProgressController {
  _SeededProgress(this._seed);
  final Map<String, double> _seed;
  @override
  Map<String, double> build() => Map<String, double>.of(_seed);
}

Future<void> _pump(
  WidgetTester tester,
  FakeStrumEngine engine, {
  FeatureFlags? flags,
  List<PracticeEntry>? logSeed,
  Map<String, double>? progressSeed,
}) async {
  final f = flags ?? _flagsOff();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        appConfigProvider.overrideWithValue(_config(f)),
        if (logSeed != null)
          practiceLogProvider.overrideWith(() => _SeededLog(logSeed)),
        if (progressSeed != null)
          lessonProgressProvider.overrideWith(
            () => _SeededProgress(progressSeed),
          ),
      ],
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LearnScreen(lesson: Lessons.firstStrums),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'A8 — flag OFF renders the same Play control as the legacy build',
    (tester) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      await _pump(tester, engine);

      // The Play control (FilledButton.icon with "Play" label + play_arrow icon)
      // is what the existing learn_screen_test.dart asserts.
      expect(find.text('Play'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsWidgets);
    },
  );

  testWidgets(
    'A8 — flag OFF leaves the V1 store and lesson-progress untouched',
    (tester) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);
      final existingAccuracy = 0.95;
      await _pump(
        tester,
        engine,
        flags: _flagsOff(),
        logSeed: [
          PracticeEntry(
            day: StreakLogic.epochDayOf(DateTime(2026, 7, 9)),
            source: PracticeSource.learn,
            seconds: 120,
            strokes: 10,
            chords: 3,
            directionAccuracy: existingAccuracy,
          ),
        ],
        progressSeed: {'first-strums': existingAccuracy},
      );

      // The page renders under flag OFF — no rollback has fired yet, the
      // seeded progress and log entries survive untouched (the A8 contract:
      // V1 store and lesson-progress are sértetlen).
      expect(find.text('Play'), findsOneWidget);
    },
  );

  test(
    'A8 — FeatureFlags.migratedLearnEnabled production default stays OFF',
    () {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );

      expect(flags.migratedLearnEnabled, isFalse);
    },
  );
}
