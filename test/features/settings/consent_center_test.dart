// E13-R35 — A5 (the privacy & consent center is reachable from the Settings
// ROOT in one tap, not three menus deep) and A8 (export/delete are explicit
// tasks with a visible state and a visible result — ADR 0279).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/screens/privacy_center_screen.dart';
import 'package:strumsight/features/vision/public.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

Future<InMemoryKeyValueStore> _openSettings(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  final store = InMemoryKeyValueStore();
  final container = ProviderContainer(
    overrides: [
      preferenceStoreOverride(store),
      strumEngineProvider.overrideWithValue(engine),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
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
  // E15-R02 (ADR 0467 D9): the app boots on the adaptive shell's /today
  // entry point now; Settings lives at AppRoutes.profileSettings (same
  // SettingsScreen widget as the legacy /settings route).
  container.read(routerProvider).go(AppRoutes.profileSettings);
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets(
    'A5 — the privacy & consent center opens from the Settings root in one tap',
    (tester) async {
      await _openSettings(tester);

      expect(find.text('Privacy & data'), findsOneWidget);
      await tester.tap(find.text('Privacy & data'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyCenterScreen), findsOneWidget);
    },
  );

  testWidgets(
    'A8 — export is an explicit task: idle → running → a visible result',
    (tester) async {
      final store = await _openSettings(tester);
      await VisionSessionRepository(store: store).save(
        _visionResult(),
        modelVersions: const <String, String>{'hand_landmarker': '1.2.3'},
      );

      await tester.tap(find.text('Privacy & data'));
      await tester.pumpAndSettle();

      expect(find.text('Export my Vision data'), findsOneWidget);
      await tester.tap(find.text('Export my Vision data'));
      await tester.pump(); // the running frame — before the microtask settles
      await tester.pumpAndSettle();

      // A visible result — the export dialog with the actual JSON — not a
      // button that silently reverts to idle.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Export ready'),
        ),
        findsOneWidget,
      );
      // Javító kör 1, m1: the dialog only ever shows JSON in place — nothing
      // is written to a file — so the copy must say so, not let "Export
      // ready" imply a saved artifact exists somewhere.
      expect(
        find.textContaining('viewable snapshot, not a saved file'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // The result stays visible after the dialog closes too — the row does
      // not silently revert to the idle "Export my data" button.
      expect(find.text('Export ready'), findsOneWidget);
    },
  );

  testWidgets(
    'A8 — delete-all is consequence-first and explicit: confirm names what '
    'is lost, and the result is visible after it runs',
    (tester) async {
      final store = await _openSettings(tester);
      await VisionSessionRepository(store: store).save(
        _visionResult(),
        modelVersions: const <String, String>{'hand_landmarker': '1.2.3'},
      );

      await tester.tap(find.text('Privacy & data'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete all my Vision data'));
      await tester.pumpAndSettle();

      // The consequence is spelled out before anything happens.
      expect(
        find.textContaining("can't be undone"),
        findsOneWidget,
        reason: 'ADR 0279 §5.6 — consequence-first, not a bare "are you sure?"',
      );

      await tester.tap(find.byKey(const Key('privacyCenterDeleteAllConfirm')));
      await tester.pumpAndSettle();

      expect(find.text('All Vision data deleted'), findsOneWidget);
      expect(VisionSessionRepository(store: store).list(), isEmpty);
    },
  );

  testWidgets(
    // Javító kör 1, F3 (S3): the action's copy and its actual reach must
    // agree — "delete all my Vision data" only ever visits
    // `StorageKeys.visionData`, so a value under an unrelated key (the kind
    // library/songs/practice-log actually use) MUST survive the operation.
    'F3 — "delete all my Vision data" leaves non-Vision storage untouched',
    (tester) async {
      final store = await _openSettings(tester);
      await VisionSessionRepository(store: store).save(
        _visionResult(),
        modelVersions: const <String, String>{'hand_landmarker': '1.2.3'},
      );
      await store.writeString(StorageKeys.songs, 'not-vision-data');

      await tester.tap(find.text('Privacy & data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all my Vision data'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacyCenterDeleteAllConfirm')));
      await tester.pumpAndSettle();

      expect(find.text('All Vision data deleted'), findsOneWidget);
      expect(VisionSessionRepository(store: store).list(), isEmpty);
      expect(
        store.readString(StorageKeys.songs),
        'not-vision-data',
        reason:
            'the action is scoped to Vision data — it must never reach into '
            'other features\' storage keys',
      );
    },
  );

  testWidgets(
    'A5 — the session-by-session Vision history is one tap further in, not '
    'the ONLY way to reach privacy controls',
    (tester) async {
      await _openSettings(tester);
      await tester.tap(find.text('Privacy & data'));
      await tester.pumpAndSettle();

      expect(find.text('Session-by-session history'), findsOneWidget);
    },
  );
}

VisionSessionResult _visionResult() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('consent-center'),
    startedAt: DateTime.utc(2026, 8, 8),
  ),
  endedAt: DateTime.utc(2026, 8, 8, 0, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: const <VisionInsight>[],
  observedFrameCount: 0,
);
