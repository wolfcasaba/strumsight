import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_theory/features/auth/data/auth_repository.dart';
import 'package:music_theory/features/auth/data/token_store.dart';
import 'package:music_theory/features/auth/providers/auth_providers.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/settings/data/settings_repository.dart';
import 'package:music_theory/features/settings/providers/lab_mode_provider.dart';
import 'package:music_theory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/fake_settings.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Lab mode SwitchListTile is present, off by default, and toggles',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strumEngineProvider.overrideWithValue(engine),
          tokenStoreProvider.overrideWithValue(FakeTokenStore()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
          accountEnabledProvider.overrideWithValue(false),
        ],
        child: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return const StrumSightApp();
        }),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, 'Lab mode (diagnostics)');
    await tester.scrollUntilVisible(tile, 250,
        scrollable: find.byType(Scrollable).first);
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
  });
}
