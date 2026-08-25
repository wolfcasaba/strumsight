// E13-R17 — Today Hub (UI-05). A1/A4/A6/A7/A8 (brief §6, §6.1 matrix).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/today/domain/today_plan_repository.dart';
import 'package:strumsight/features/today/domain/today_plan_snapshot.dart';
import 'package:strumsight/features/today/providers/today_providers.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// A fake plan source for tests (brief §5.5 — the real Chapter 8 source has
/// no presentation-layer provider yet; production reads the honest
/// [UnavailableTodayPlanRepository] default).
class _FakeTodayPlanRepository implements TodayPlanRepository {
  const _FakeTodayPlanRepository(this._snapshot);
  final TodayPlanSnapshot _snapshot;

  @override
  TodayPlanSnapshot load() => _snapshot;
}

Widget _host({
  TodayPlanSnapshot? plan,
  bool visionEnabled = false,
  bool visionSetupEnabled = false,
  DateTime? now,
}) => ProviderScope(
  overrides: [
    ...preferenceOverrides(),
    if (plan != null)
      todayPlanRepositoryProvider.overrideWithValue(
        _FakeTodayPlanRepository(plan),
      ),
    appConfigProvider.overrideWithValue(
      AppConfig(
        environment: AppEnvironment.development,
        apiBaseUrl: AppConfig.devApiBaseUrl,
        flags: FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          visionEnabled: visionEnabled,
          visionSetupEnabled: visionSetupEnabled,
        ),
        diagnosticsToken: AppConfig.devDiagnosticsToken,
        buildMode: 'test',
        appVersion: 'test',
      ),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TodayHubScreen(now: now ?? DateTime(2026, 8, 25)),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A1 — exactly one primary action, in every plan state', () {
    Future<void> expectOnePrimaryCta(
      WidgetTester tester,
      TodayPlanSnapshot? plan,
    ) async {
      await tester.pumpWidget(_host(plan: plan));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('today-hub-primary-cta')),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsOneWidget);
    }

    testWidgets('new user (no plan, no history)', (tester) async {
      await expectOnePrimaryCta(tester, null);
    });

    testWidgets('plan ready, not completed', (tester) async {
      await expectOnePrimaryCta(
        tester,
        const TodayPlanSnapshot(
          availability: TodayPlanAvailability.ready,
          recommendedTaskLabel: 'Warm-up: chromatic run',
          completedTaskCount: 1,
          totalTaskCount: 3,
        ),
      );
    });

    testWidgets('day completed — shows a recap, not a dead end', (
      tester,
    ) async {
      await expectOnePrimaryCta(
        tester,
        const TodayPlanSnapshot(
          availability: TodayPlanAvailability.ready,
          completedTaskCount: 3,
          totalTaskCount: 3,
        ),
      );
      expect(find.text('Nice work today'), findsOneWidget);
    });

    testWidgets('offline cached plan', (tester) async {
      await expectOnePrimaryCta(
        tester,
        const TodayPlanSnapshot(
          availability: TodayPlanAvailability.offlineCached,
          recommendedTaskLabel: 'Chord changes: G to C',
          completedTaskCount: 0,
          totalTaskCount: 2,
        ),
      );
    });
  });

  group('A4 — the hub never touches a microphone/camera/wakelock API', () {
    test(
      'no resource-acquisition call sites in the three hub feature dirs',
      () {
        // §0.0/R6.2 — the measured acquisition call sites this diff must not
        // introduce: the live stream, the recorder, the vision coordinator,
        // and the screen wakelock.
        const forbidden = [
          'liveFrameProvider',
          'startRecording',
          'coordinator.acquire',
          'WakelockPlus',
          'CameraController',
        ];
        final dirs = [
          Directory('lib/features/today'),
          Directory('lib/features/practice_hub'),
          Directory('lib/features/profile_hub'),
        ];
        for (final dir in dirs) {
          for (final entity in dir.listSync(recursive: true)) {
            if (entity is! File || !entity.path.endsWith('.dart')) continue;
            final source = entity.readAsStringSync();
            for (final token in forbidden) {
              expect(
                source.contains(token),
                isFalse,
                reason: '${entity.path} must not reference $token',
              );
            }
          }
        }
      },
    );
  });

  group('A6 — offline cached content stays visible, with an offline badge', () {
    testWidgets('offline-cached plan renders the offline badge and the '
        'cached recommendation — not an empty screen', (tester) async {
      await tester.pumpWidget(
        _host(
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.offlineCached,
            recommendedTaskLabel: 'Chord changes: G to C',
            completedTaskCount: 0,
            totalTaskCount: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Chord changes: G to C'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('sync-pending plan renders the sync badge', (tester) async {
      await tester.pumpWidget(
        _host(
          plan: const TodayPlanSnapshot(
            availability: TodayPlanAvailability.syncPending,
            recommendedTaskLabel: 'Rhythm: down-down-up',
            completedTaskCount: 0,
            totalTaskCount: 1,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sync pending'), findsOneWidget);
    });
  });

  group('A7 — the disabled Vision card names the reason', () {
    testWidgets('vision disabled: reason text, no action button', (
      tester,
    ) async {
      await tester.pumpWidget(_host(visionEnabled: false));
      await tester.pump();

      expect(
        find.textContaining("isn't available in this build"),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Vision practice'), findsNothing);
    });

    testWidgets('vision enabled: actionable, no reason text', (tester) async {
      await tester.pumpWidget(_host(visionEnabled: true));
      await tester.pump();

      expect(find.textContaining('Use your camera for guided'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Vision practice'),
        findsOneWidget,
      );
    });
  });

  group('A8 — no invented statistic when there is no real data', () {
    testWidgets('new user: streak and progress both read real zero, '
        'never a placeholder number', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pump();

      expect(find.text('0'), findsOneWidget); // the streak metric
      // New-user framing (§0.0/D — isNewUser wins over the generic no-plan
      // copy), never a guessed number or a fabricated recommendation.
      expect(
        find.text('Your first practice session takes just a few minutes.'),
        findsOneWidget,
      );
    });
  });
}
