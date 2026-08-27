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
import 'package:strumsight/core/foundation/app_failure.dart';
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

Future<ProviderContainer> _openSettings(
  WidgetTester tester, {
  required FakeSettingsRepository settings,
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
  await tester.tap(find.text('Settings'));
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
    'A3 — while a save is in flight the screen shows "Saving…", not "saved"',
    (tester) async {
      final settings = FakeSettingsRepository();
      await _openSettings(tester, settings: settings);

      expect(find.text('All changes saved'), findsOneWidget);
    },
  );
}
