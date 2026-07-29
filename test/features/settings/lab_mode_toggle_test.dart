import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/features/auth/data/auth_repository.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/providers/lab_mode_provider.dart';
import 'package:strumsight/main.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

void main() {
  setUp(TestWidgetsFlutterBinding.ensureInitialized);

  testWidgets(
    'Lab mode SwitchListTile is present, off by default, and toggles',
    (tester) async {
      final engine = FakeStrumEngine();
      addTearDown(engine.dispose);

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            strumEngineProvider.overrideWithValue(engine),
            tokenStoreProvider.overrideWithValue(FakeTokenStore()),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
            settingsRepositoryProvider.overrideWithValue(
              FakeSettingsRepository(),
            ),
            accountEnabledProvider.overrideWithValue(false),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const StrumSightApp();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(
        SwitchListTile,
        'Lab mode (diagnostics)',
      );
      await tester.scrollUntilVisible(
        tile,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(tile, findsOneWidget);
      // The consent subtitle is shown.
      expect(find.textContaining('short audio'), findsOneWidget);

      // Off by default.
      expect(capturedRef.read(labModeProvider), isFalse);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);

      // Toggling flips the bound provider.
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(capturedRef.read(labModeProvider), isTrue);
    },
  );
}
