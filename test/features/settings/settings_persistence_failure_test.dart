// E13-R35 — A3 (a setting is only marked synced after the server confirms)
// and A4 (a failed save surfaces a pending/failed state and offers a
// USER-INITIATED retry — never an automatic replay). The automatic-replay
// invariant itself is pinned by the round's listed, non-editable
// `settings_sync_test.dart` cells; this file measures what the SETTINGS
// SCREEN shows and does with that state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/providers/confidence_threshold_provider.dart';
import 'package:strumsight/features/settings/providers/settings_sync.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

/// A settings backend whose `update()` blocks until released — the ONLY way
/// to actually observe the in-flight window, unlike `FakeSettingsRepository`
/// (test/support/fake_settings.dart, outside this round's allowed files)
/// whose `update()` always resolves synchronously (javító kör 1, F6: the
/// previous version of the cell below used the synchronous fake and so could
/// never have caught anything other than the settled end state).
final class _DelayedUpdateRepository implements SettingsRepository {
  final Completer<void> updateStarted = Completer<void>();
  final Completer<void> releaseUpdate = Completer<void>();
  RemoteSettings _current = const RemoteSettings(
    themeMode: ThemeMode.system,
    locale: null,
    confidenceThreshold: 0.45,
    tuningA4: 440,
  );

  @override
  Future<AppResult<RemoteSettings>> fetch() async => Success(_current);

  @override
  Future<AppResult<RemoteSettings>> update(Map<String, Object?> patch) async {
    if (!updateStarted.isCompleted) updateStarted.complete();
    await releaseUpdate.future;
    if (patch.containsKey('confidence_threshold')) {
      _current = RemoteSettings(
        themeMode: _current.themeMode,
        locale: _current.locale,
        confidenceThreshold: (patch['confidence_threshold']! as num).toDouble(),
        tuningA4: _current.tuningA4,
      );
    }
    return Success(_current);
  }
}

Future<ProviderContainer> _openSettings(
  WidgetTester tester, {
  required SettingsRepository settings,
}) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  late final ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...preferenceOverrides(),
        strumEngineProvider.overrideWithValue(engine),
        tokenStoreProvider.overrideWithValue(FakeTokenStore('stored-token')),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        settingsRepositoryProvider.overrideWithValue(settings),
        accountEnabledProvider.overrideWithValue(true),
        // No debounce — the test drives the push synchronously.
        settingsSyncDebounceProvider.overrideWithValue(Duration.zero),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return const StrumSightApp();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  // E15-R02 (ADR 0467 D9): the app boots on the adaptive shell's /today
  // entry point now; Settings lives at AppRoutes.profileSettings (same
  // SettingsScreen widget as the legacy /settings route).
  container.read(routerProvider).go(AppRoutes.profileSettings);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'A3/A4 — a failed save shows a pending state, not "saved", and a Retry '
    'action sends exactly one more attempt through the existing push path',
    (tester) async {
      final settings = FakeSettingsRepository();
      final container = await _openSettings(tester, settings: settings);

      // Fail the very next push.
      settings.updateFailure = const NetworkFailure(
        code: FailureCode.networkServer,
      );
      unawaited(container.read(confidenceThresholdProvider.notifier).set(0.8));
      await tester.pumpAndSettle();

      expect(settings.updates, hasLength(1));
      expect(find.text('All changes saved'), findsNothing);
      expect(
        find.text("Couldn't save — changes are only on this device"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settingsSyncRetry')), findsOneWidget);

      // The next attempt (via Retry) succeeds.
      settings.updateFailure = null;
      await tester.tap(find.byKey(const Key('settingsSyncRetry')));
      await tester.pumpAndSettle();

      expect(
        settings.updates,
        hasLength(2),
        reason:
            'retry is exactly one user-initiated attempt, not a replay loop',
      );
      expect(find.text('All changes saved'), findsOneWidget);
      expect(find.byKey(const Key('settingsSyncRetry')), findsNothing);
    },
  );

  testWidgets(
    // Javító kör 1, F6: the ORIGINAL cell here asserted "All changes saved"
    // is shown with NO save in flight at all — the opposite of its own name
    // — because `FakeSettingsRepository.update()` always resolves
    // synchronously, so there was never an in-flight window to observe. This
    // measured hole is exactly what let F2/S2 (a later push's confirm
    // getting masked by an earlier one's) through: this file's `settings_
    // sync_test.dart` sibling that DOES exercise real async timing
    // (`_OutOfOrderUpdateRepository`) only checks push counts, not the
    // status text. `_DelayedUpdateRepository` (above) genuinely blocks the
    // request so this cell can assert the true in-flight state.
    'A3 — while a save is in flight the screen shows "Saving…", not "saved"',
    (tester) async {
      final settings = _DelayedUpdateRepository();
      final container = await _openSettings(tester, settings: settings);
      expect(find.text('All changes saved'), findsOneWidget);

      // `pumpAndSettle` (not a raw `await settings.updateStarted.future`) —
      // the zero-duration debounce Timer this schedules only fires once the
      // test clock is advanced by a pump; it settles as soon as no more
      // frames are scheduled, which happens well before `update()` below
      // returns (it stays blocked on `releaseUpdate`), so this reliably
      // lands mid-flight rather than hanging on it.
      unawaited(container.read(confidenceThresholdProvider.notifier).set(0.8));
      await tester.pumpAndSettle();

      expect(
        settings.updateStarted.isCompleted,
        isTrue,
        reason:
            'a real in-flight measurement requires the push to have '
            'actually started',
      );
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('All changes saved'), findsNothing);

      settings.releaseUpdate.complete();
      await tester.pumpAndSettle();

      expect(find.text('All changes saved'), findsOneWidget);
      expect(find.text('Saving…'), findsNothing);
    },
  );
}
